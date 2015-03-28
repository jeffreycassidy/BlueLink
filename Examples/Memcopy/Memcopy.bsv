// This file is part of BlueLink, a Bluespec library supporting the IBM CAPI coherent POWER8-FPGA link
// github.com/jeffreycassidy/BlueLink
//
// Copyright 2014 Jeffrey Cassidy
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package Memcopy;

// This is a very simple reimplementation of the IBM Memcopy demo from the CAPI Demo Kit
// Copies a specified size (bytes, must be cache-aligned) from one address range to another
// Only uses a single in-flight tag at a time, read latency=1
//
// Request is described by a WED (see definition below for setup details), and starts when given the start command
// 
// No parity generation or checking


import DelayWire::*;
import Reserved::*;
import DReg::*;
import StmtFSM::*;
import Vector::*;
import PSLTypes::*;
import PSLInterface::*;
import ClientServerFL::*;



/***********************************************************************************************************************************
 * Memcopy AFU
 *
 * Fixed buffer read latency of 1, no parity generation or checking
 */

typedef enum {
    DedicatedProcess=16'h8010,
    Invalid=16'haaaa
} ProgrammingModel deriving (Bits);

//typedef struct {
//    // Config dword 0x00
//    UInt#(16) num_ints_per_process;
//    UInt#(16) num_of_processes;
//    UInt#(16) num_of_afu_CRs;
//    ProgrammingModel req_prog_model;
//
//    // Config dwords 0x08 - 0x18
//    ReservedZero#(64) resv0x08;
//    ReservedZero#(64) resv0x10;
//    ReservedZero#(64) resv0x18;
//
//    // Config dword 0x20
//    ReservedZero#(8)    resv0x20_0_7
//    UInt#(24)           afu_cr_len;
//
//    // Config dword 0x24
//    UInt#(64)           afu_cr_offset;
//
//} AFU_Config_Descriptor deriving(Bits);

typedef struct {
    UInt#(16)           num_ints_per_process;
    UInt#(16)           num_of_processes;
    UInt#(16)           num_of_afu_CRs;
    ProgrammingModel    req_prog_model;
} AFU_Config_Descriptor_0 deriving(Bits);

typedef struct { UInt#(64) addr; } EAddress64LE deriving(Eq);

function Bit#(nb) byteEndianSwap(Bit#(nb) i) provisos (Mul#(8,nw,nb));
    Vector#(nw,Bit#(8)) v = unpack(i);
    return pack(reverse(v));
endfunction

instance Bits#(EAddress64LE,64);
    function Bit#(64)       pack(EAddress64LE a) = byteEndianSwap(pack(a.addr));
    function EAddress64LE   unpack(Bit#(64) i) = EAddress64LE { addr: unpack(byteEndianSwap(i)) };
endinstance

instance FShow#(EAddress64LE);
    function Fmt fshow(EAddress64LE a) = $format("0x%016X",a.addr);
endinstance


typedef struct {
    EAddress64LE    addr_from;
    EAddress64LE    addr_to;
    UInt#(64)       size;
    Reserved#(832)  resv;
} WED deriving(Bits);

instance FShow#(WED);
    function Fmt fshow(WED wed) =
        $format("Copying %d bytes from %016X to %016X",byteEndianSwap(pack(wed.size)),wed.addr_from,wed.addr_to);
endinstance



module mkMemcopy(AFU#(1));
    // setup parameters
    Reg#(EAddress64) ea <- mkReg(0);
    Reg#(EAddress64) copy_from  <- mkReg(0);
    Reg#(EAddress64) copy_to    <- mkReg(0);
    Reg#(EAddress64) copy_end   <- mkReg(0);

    // work element descriptor: 2 segments of 512b each
    P8CacheLineReg#(WED) wed <- mkSegmentedReg;

    // status indicators
    Reg#(UInt#(64)) st_errcode  <- mkReg(0);
    Reg#(Bool)      st_running  <- mkReg(False);

    // status control
    PulseWire       pw_done     <- mkPulseWire;
    PulseWire       pw_start    <- mkPulseWire;
    Reg#(Bool)      start_next  <- mkDReg(False);

    // PSL Cache Command to issue
    Reg#(Maybe#(CacheCommand)) cmd <- mkDReg(tagged Invalid);

    function Action requestRead(RequestTag tag,EAddress64 addr) =
        cmd._write(tagged Valid CacheCommand { ctag: tag, cch: 0, com: Read_cl_s, cea: addr, csize: 128, cabt: Strict });

    function Action requestWrite(RequestTag tag,EAddress64 addr) =
        cmd._write(tagged Valid CacheCommand { ctag: tag, cch: 0, com: Write_mi,  cea: addr, csize: 128, cabt: Strict });

    Wire#(RequestTag) completion <- mkWire;

    // Data buffering functions
    SegmentedReg#(Bit#(1024),2,512,6)   readbuf     <- mkSegmentedReg;          // holds read data while waiting to write
    BubblePipe#(2,UInt#(6))             brad_d      <- mkBubblePipe;            // delays the buffer read address 1 cycle
    Wire#(BufferWrite)                  wbuf        <- mkWire;                  // write buffer command

    // FSM for handling memcpy
    Stmt memcpystmts = seq
        // Reset
        $display($time,": Memcopy block resetting");
        st_errcode  <= 0;
        st_running  <= False;
        $display($time,": Memcopy block ready");

        pw_done.send;


        // Request read of WED
        await(pw_start);
        $display($time,": Memcopy block reading WED");
        st_running <= True;
        requestRead(0,ea);

        // handle 2 read completions by writing to the buffer reg
        repeat(2) wed.writeseg(wbuf.bwad,wbuf.bwdata);

        // Get completion of WED read, register the addresses
        action
            await(completion==0);
            $display($time,": Memcopy block running with WED: ",fshow(wed));

            copy_from.addr <= wed.addr_from.addr;
            copy_end.addr  <= wed.addr_from.addr + unpack(byteEndianSwap(pack(wed.size)));

            copy_to.addr   <= wed.addr_to.addr;
        endaction

        // do the transfer using a single tag and single data buffer
        while (copy_from < copy_end)
        seq
            requestRead(0,copy_from);
            await(completion==0);

            par
                requestWrite(0,copy_to);
                copy_from <= copy_from+128;
            endpar

            par
                await(completion==0);
                copy_to   <= copy_to+128;
            endpar
        endseq


        // request interrupt service when done
        cmd._write(tagged Valid CacheCommand { ctag: 0, cch: 0, com: Intreq, cea: 1, csize: 0, cabt: Strict });
        await(completion==0);

        st_running <= False;
        noAction;
        pw_done.send;
    endseq;

    let memcpyfsm <- mkFSM(memcpystmts);

    rule startfsm if (start_next);
        memcpyfsm.start;
    endrule

    // handle buffer writes by storing to register
    rule bufferwrite;
        readbuf.writeseg(wbuf.bwad,wbuf.bwdata);
    endrule

    Reg#(Maybe#(MMIOCommandWithParity)) mmio_req <- mkDReg(tagged Invalid); // indicates we should send MMIO Ack next cycle
    
    // MMIO not supported, just ACK and send back X
    interface ServerARU mmio;
        interface Put request;
            method Action put(MMIOCommandWithParity req) = mmio_req._write(tagged Valid req);
        endinterface

        interface ReadOnly response;
            method DataWithParity#(MMIOResponse,OddParity) _read if (mmio_req matches tagged Valid .req);
                if (parity_maybe(True,req) matches tagged Valid .v &&& v.mmrnw &&& v.mmdw)
                    if (v.mmcfg)
                        return parity_x(
                            case (v.mmad) matches
                            24'h00: tagged DWordData pack (AFU_Config_Descriptor_0 {
                                req_prog_model: DedicatedProcess,
                                num_of_afu_CRs: 0,
                                num_of_processes: 1,
                                num_ints_per_process: 1 });
                            24'h08: tagged DWordData 64'h0;                      // reserved
                            24'h10: tagged DWordData 64'h0;                      // reserved
                            24'h18: tagged DWordData 64'h0;                      // reserved
                            24'h20: tagged DWordData 64'h0;                      // 63:8 AFU_CR_len, 7:0 reserved
                            24'h28: tagged DWordData 64'h0;                      // AFU_CR_offset (offset from start of AFU descriptor, 256B aligned)
                            default: tagged DWordData  64'h0;
                        endcase);
                    else
                        return parity_x(tagged DWordData 64'h0);
                else
                    return parity_x(tagged DWordData 64'h0);
            endmethod
        endinterface
    endinterface

    interface ClientU command;
        interface ReadOnly request;
            method CacheCommandWithParity _read if (cmd matches tagged Valid .c) = parity_x(c);
        endinterface

        interface Put response;
            method Action put(CacheResponseWithParity resp);
                case (resp.response) matches
                    Done: completion <= resp.rtag.data;
                    Paged: cmd._write(tagged Valid CacheCommand { ctag: 0, cch: 0, com: Restart, cea: copy_from, csize: 128, cabt: Strict }) ;
                    default: $display("** Don't know what to do with a response of type ",fshow(resp.response)," **");
                endcase
            endmethod
        endinterface
    endinterface

    interface AFUBufferInterfaceWithParity buffer;
        // Since we're using a single tag and a single register to buffer, just pipe the buffer read address (0/1 => lower/upper)
        // for four cycles and then send back the appropriate half-line

        interface ServerFL writedata;
            interface Put request;
                method Action put(BufferReadRequestWithParity rreqp) = brad_d.send(ignore_parity(rreqp).brad);
            endinterface

            interface Get response;
                method ActionValue#(DWordWiseOddParity512) get if (brad_d matches tagged Valid .i);
                    return parity_x(readbuf.readseg(i));
                endmethod
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWriteWithParity wbufcmd) = wbuf._write(ignore_parity(wbufcmd));
        endinterface
    endinterface

    interface Put control;
        method Action put(JobControlWithParity jcp);
            JobControl jc = ignore_parity(jcp);
            case (jc) matches
                tagged JobControl { opcode: Start, jea: .jea }:
                    action
                        pw_start.send;
                        ea <= jea;
                    endaction
                tagged JobControl { opcode: Reset }:
                    action
                        ea <= 0;
                        memcpyfsm.abort;
                        start_next <= True;
                    endaction
                tagged JobControl { opcode: .opcode}:
                    $display("Unknown opcode: ",fshow(opcode));
            endcase
        endmethod
    endinterface

    method Bool tbreq           = False;
    method Bool yield           = False;

    method AFU_Status status = AFU_Status {
        done:       pw_done,
        running:    st_running,
        errcode:    st_errcode
    };

    method AFU_Description description = 
        AFU_Description {
            lroom:      ?,
            pargen:     False,
            parcheck:   False,
            brlat:      1
        };

endmodule

endpackage
