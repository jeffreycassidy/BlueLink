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
// Only uses a single in-flight tag at a time, read latency=4
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
 * Fixed buffer read latency of 4, no parity generation or checking
 */

typedef struct {
    EAddress64      addr_from;
    EAddress64      addr_to;
    UInt#(64)       size;
    Reserved#(832)  resv;
} WED deriving(Bits);

instance FShow#(WED);
    function Fmt fshow(WED wed) =
        $format("Copying %d bytes from %016X to %016X",wed.size,wed.addr_from,wed.addr_to);
endinstance



module mkMemcopy(AFU#(4));
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
    BubblePipe#(4,UInt#(6))             brad_d      <- mkBubblePipe;            // delays the buffer read address 4 cycles
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

            copy_from <= wed.addr_from;
            copy_to   <= wed.addr_to;
            copy_end  <= wed.addr_from + EAddress64 { addr: wed.size};
        endaction

        // do the transfer using a single tag and single data buffer
        while (copy_from < copy_end)
        seq
            requestRead(0,copy_from);
            await(completion==0);

            requestWrite(0,copy_to);
            await(completion==0);

            copy_from <= copy_from+128;
            copy_to   <= copy_to+128;
        endseq

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
            method DataWithParity#(MMIOResponse,OddParity) _read if (isValid(mmio_req)) = parity_x(?);
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
                    default: $display("** Don't know what to do with a response of type ",fshow(resp.response)," **");
                endcase
            endmethod
        endinterface
    endinterface

    interface AFUBufferInterfaceWithParity buffer;
        // Since we're using a single tag and a single register to buffer, just pipe the buffer read address (0/1 => lower/upper)
        // for four cycles and then send back the appropriate half-line

		// TODO: Check why need to flip the read index here (appears to me but unsure PSL simulator may reverse this accidentally?)
        interface ServerFL writedata;
            interface Put request;
                method Action put(BufferReadRequestWithParity rreqp) = brad_d.send((ignore_parity(rreqp).brad+1)%2);
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
            brlat:      4
        };

endmodule

endpackage
