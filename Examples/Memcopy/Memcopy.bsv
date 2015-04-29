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


import Endianness::*;
import DelayWire::*;
import Reserved::*;
import DReg::*;
import StmtFSM::*;
import Vector::*;
import PSLTypes::*;
import PSL::*;
import AFU::*;
import AFUHardware::*;
import CmdBuf::*;
import FIFO::*;
import Assert::*;
import ConfigReg::*;

/***********************************************************************************************************************************
 * Memcopy AFU
 *
 * Fixed buffer read latency of 1, no parity generation or checking
 */


function EAddress64 offset(EAddress64 addr,UInt#(64) o);
    return EAddress64 { addr: addr.addr + o };
endfunction

//function EAddress64 offset(EAddress64 addr,UInt#(t) o) provisos(Add#(t,__some,64));
//    return EAddress64 { addr: addr.addr + extend(o) };
//endfunction

typedef struct {
    EndianType#(LE,EAddress64)   addr_from;
    EndianType#(LE,EAddress64)   addr_to;
    EndianType#(LE,UInt#(64))    size;

    Reserved#(832)  resv;
} WED deriving(Bits);

instance FShow#(WED);
    function Fmt fshow(WED wed) =
        $format("Copying ",fshow(wed.size)," bytes from ",fshow(wed.addr_from)," to ",fshow(wed.addr_to));
endinstance




interface CommandMgr;
    interface Server#(CacheCommand,CacheResponse)   user;
    interface Client#(CacheCommand,CacheResponse)   psl;
endinterface

typedef enum {
    Sent,
    Paged,
    Restarting,
    Ready
} CommandState deriving(Bits,Eq);

module mkSingleCommandMgr#(RequestTag t)(CommandMgr);
    Reg#(CommandState) state <- mkReg(Ready);
    FIFO#(CacheCommand) cmd <- mkFIFO1;
    FIFO#(CacheCommand) ocmd <- mkFIFO1;

    Wire#(CacheResponse) iresp <- mkWire;

    FIFO#(CacheResponse) oresp <- mkFIFO;

    rule sendCmd if (state == Ready);
        ocmd.enq(cmd.first);
        state <= Sent;
    endrule

    (* descending_urgency="handleDone,handlePaged,handleOther" *)

    (* fire_when_enabled *)
    rule handleDone if (state == Sent && iresp.response == Done);
        cmd.deq;
        oresp.enq(iresp);
        state <= Ready;
    endrule

    (* fire_when_enabled *)
    rule handlePaged if (state == Sent && iresp.response == Paged);
        state <= Restarting;
        ocmd.enq(CacheCommand { com: Restart });
    endrule


    rule checkResponses;
        dynamicAssert(iresp.response != Flushed,"mkSingleCommandMgr should not ever receive a Flushed response");
    endrule

    (* fire_when_enabled *)
    rule handleRestart if (state == Restarting && iresp.response == Done);
        state <= Ready;
    endrule

    // default case
    rule handleOther if (state == Sent);
        cmd.deq;
        oresp.enq(iresp);
        state <= Ready;
    endrule

    interface Server user;
        interface Put request = toPut(cmd);
        interface Get response = toGet(oresp);
    endinterface

    interface Client psl;
        interface Get request = toGet(ocmd);
        interface Put response = toPut(asIfc(iresp));
    endinterface

endmodule

module mkMemcopy(AFU#(1));
    // setup parameters
    Reg#(EAddress64) ea <- mkReg(0);
    Reg#(EAddress64) copy_from  <- mkReg(0);
    Reg#(EAddress64) copy_to    <- mkReg(0);
    Reg#(EAddress64) copy_end   <- mkReg(0);

    Reg#(UInt#(64)) errct <- mkReg(0);

    // work element descriptor: 2 segments of 512b each
    P8CacheLineReg#(WED) wed <- mkSegmentedReg;

    // status indicators
    Reg#(UInt#(64)) st_errcode  <- mkReg(0);
    Reg#(Bool)      st_running  <- mkReg(False);
    Reg#(Bool)      wed_wen     <- mkConfigReg(False);

    PulseWire       pw_go <- mkPulseWire;

    // status control
    PulseWire       pw_done     <- mkPulseWire;
    PulseWire       pw_start    <- mkPulseWire;
    Reg#(Bool)      start_next  <- mkDReg(False);

    Wire#(CacheCommand) ocmd <- mkWire;

    let cmgr <- mkSingleCommandMgr(0);

    mkConnection(cmgr.psl.request,toPut(asIfc(ocmd)));

    // PSL Cache Command to issue
    function Action requestRead(RequestTag tag,EAddress64 addr) =
        cmgr.user.request.put(CacheCommand { ctag: tag, cch: 0, com: Read_cl_s, cea: addr, csize: 128, cabt: Strict });

    function Action requestWrite(RequestTag tag,EAddress64 addr) =
        cmgr.user.request.put(CacheCommand { ctag: tag, cch: 0, com: Write_mi,  cea: addr, csize: 128, cabt: Strict });

    function Action requestInterrupt(RequestTag tag,UInt#(12) code) =
        cmgr.user.request.put(CacheCommand { ctag: tag, cch: 0, com: Intreq, cea: EAddress64{addr:extend(code)}, csize: ?, cabt: ? });

    Wire#(RequestTag) completion <- mkWire;

    // Data buffering functions
    SegmentedReg#(Bit#(1024),2,512,6)   readbuf     <- mkSegmentedReg;          // holds read data while waiting to write
    BubblePipe#(1,UInt#(6))             brad_d      <- mkBubblePipe;            // delays the buffer read address 1 cycle
    Wire#(BufferWrite)                  wbuf        <- mkWire;                  // write buffer command

    Reg#(Bool) doPage <- mkReg(False);

    Reg#(CacheResponse) cr <- mkRegU;

    // FSM for handling memcpy
    Stmt memcpystmts = seq
        // Reset
        $display($time,": Memcopy block resetting");
        st_errcode  <= 0;
        st_running  <= False;
        errct <= 0;
        $display($time,": Memcopy block ready");

        pw_done.send;

        // Request read of WED
        await(pw_start);
        st_running <= True;

        repeat(2) noAction;


        action
            $display($time,": Memcopy block reading WED");
            requestRead(0,ea);
            wed_wen <= True;
        endaction

        action
            await(completion==0);
            wed_wen <= False;
            copy_from <= endianfix(wed.addr_from);
            copy_end  <= offset(endianfix(wed.addr_from), endianfix(wed.size));
            copy_to   <= endianfix(wed.addr_to);
        endaction

        // request interrupt service once set up
        requestInterrupt(0,1);
        await(completion==0);       // wait for interrupt to complete and MMIO write to addr 0

        $display($time,": Memcopy block running with WED: ",fshow(wed));

        await(pw_go);

        noAction;

        // request interrupt service once set up
//        requestInterrupt(0,1);
//        await(completion==0);

        // do the transfer using a single tag and single data buffer
        while (copy_from < copy_end)
        seq
            requestRead(0,copy_from);
            await(completion==0);

            action
                requestWrite(0,copy_to);
                copy_from <= copy_from+128;
            endaction

            action
                await(completion==0);
                copy_to   <= copy_to+128;
            endaction
        endseq

        noAction;

        // request interrupt service when done
        requestInterrupt(0,1);
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
        if (wed_wen)
            wed.writeseg(wbuf.bwad,wbuf.bwdata);
        else
            readbuf.writeseg(wbuf.bwad,wbuf.bwdata);
    endrule

    Reg#(Maybe#(MMIOCommand)) mmio_req <- mkDReg(tagged Invalid); // indicates we should send MMIO Ack next cycle

    MReg#(Bit#(512)) bufReadOut_m <- mkDReg(tagged Invalid);
    Reg#(Bit#(512)) bufReadOut = toReg(bufReadOut_m);

    rule doBufRead if (brad_d matches tagged Valid .i);
        bufReadOut <= readbuf.readseg(i);
    endrule

    rule handleCompletion;
        let resp <- cmgr.user.response.get;
        if (resp matches tagged CacheResponse { rtag: .tag, response: Done })
            completion <= tag;
        else
        begin
            $display("** Not expecting a response of type ",fshow(resp)," **");
            errct <= errct+1;
        end
    endrule

    // MMIO offsets are calculated in word terms
    interface ServerARU mmio;
        interface Put request;
            method Action put(MMIOCommand req);
                $display($time,": ",fshow(req));
                mmio_req._write(tagged Valid req);

                if (!req.mmcfg && !req.mmrnw && req.mmad == 0)
                begin
                    $display($time,": got the interrupt-acknowledge");
                    pw_go.send;
                end
            endmethod
        endinterface

        interface ReadOnly response;
            method MMIOResponse _read if (mmio_req matches tagged Valid .req);
                if (req.mmrnw && req.mmdw)
                    if (req.mmcfg)
                        return DWordData (case (req.mmad) matches
//                            24'h00: 64'h0000000100000010;    // <=== WORKED
                              24'h00: 64'h0001000100008010;
                            24'h0c: 64'h0100000000000000;
                            default: 64'h0000000000000000;
//                            24'h00: tagged DWordData pack (AFU_Config_Descriptor_0 {
//                                req_prog_model: DedicatedProcess,
//                                num_of_afu_CRs: 1,
//                                num_of_processes: 1,
//                                num_ints_per_process: 1 });
//                            24'h02: tagged DWordData 64'h0;                      // reserved
//                            24'h04: tagged DWordData 64'h0;                      // reserved
//                            24'h06: tagged DWordData 64'h0;                      // reserved
//                            24'h08: tagged DWordData 64'h1;                      // 63:8 AFU_CR_len, 7:0 reserved
//                            24'h0a: tagged DWordData 64'h0;                      // AFU_CR_offset (offset from start of AFU descriptor, 256B aligned)
//                            24'h0c: tagged DWordData 64'h0100000000000000;      // MSBit: problem state area required
//                            default: tagged DWordData  64'h0;
                        endcase);
                    else
                        return
                            tagged DWordData pack(EndianType#(BE,Bit#(64))'(endianfix(
                                case (req.mmad) matches
                                    0:  pack(wed.size);
                                    2:  pack(copy_from);
                                    4:  pack(copy_to);
                                    6:  pack(errct);
                                    8:  pack(wed.addr_from);
                                    default: 64'hdeadbeefbaadc0de;
                                endcase)));
                else
                    return tagged DWordData 64'h0;
            endmethod
        endinterface
    endinterface

    interface ClientU command;
        interface ReadOnly request = regToReadOnly(ocmd);
        interface Put response = cmgr.psl.response;
    endinterface

    interface AFUBufferInterface buffer;
        // Since we're using a single tag and a single register to buffer, just pipe the buffer read address (0/1 => lower/upper)
        // for four cycles and then send back the appropriate half-line

        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequest rreqp) = brad_d.send(rreqp.brad);
            endinterface

            interface ReadOnly response = regToReadOnly(bufReadOut);
        endinterface

        interface Put readdata;
            method Action put(BufferWrite wbufcmd) = wbuf._write(wbufcmd);
        endinterface
    endinterface

    interface Put control;
        method Action put(JobControl jc);
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

    interface AFUStatus status;
        method Bool tbreq           = False;
        method Bool yield           = False;

        method AFU_Status status = AFU_Status {
            done:       pw_done,
            running:    st_running,
            errcode:    st_errcode
        };
    
        method AFU_Description description = 
            AFU_Description {
                pargen:     False,
                parcheck:   False,
                brlat:      1
            };
    endinterface

endmodule


module mkSnoopAFU#(AFU#(brlat) afu)(AFU#(brlat));

    rule cmdRequest;
        $display($time,": ",fshow(afu.command.request));
    endrule

    rule bufReadResponse;
        $display($time,": ",fshow(afu.buffer.writedata.response));
    endrule

    rule mmioResponse;
        $display($time,": ",fshow(afu.mmio.response));
    endrule

    interface ClientU command;
        interface Put response;
            method Action put(CacheResponse cmd);
                $display($time,": ",fshow(cmd));
                afu.command.response.put(cmd);
            endmethod
        endinterface

        interface ReadOnly request = afu.command.request;
    endinterface

    interface AFUBufferInterface buffer;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequest br);
                    afu.buffer.writedata.request.put(br);
                    $display($time,": ",fshow(br));
                endmethod
            endinterface

            interface ReadOnly response = afu.buffer.writedata.response;
        endinterface

        interface Put readdata;
            method Action put(BufferWrite bw);
                afu.buffer.readdata.put(bw);
                $display($time,": ",fshow(bw));
            endmethod
        endinterface
    endinterface

    interface ServerARU mmio;
        interface Put request;
            method Action put(MMIOCommand cmd);
                $display($time,": ",fshow(cmd));
                afu.mmio.request.put(cmd);
            endmethod
        endinterface

        interface ReadOnly response = afu.mmio.response;
    endinterface 

    interface Put control;
        method Action put(JobControl jc);
            $display($time,": ",fshow(jc));
            afu.control.put(jc);
        endmethod
    endinterface

    interface AFUStatus status = afu.status;
    method Action putCroom(UInt#(8) ha_croom) = afu.putCroom(ha_croom);
endmodule


(* clock_prefix="ha_pclock" *)

module mkMemcopyAFU(AFUHardware#(1));
	AFU#(1) afu <- mkMemcopy;
    AFU#(1) snooper <- mkSnoopAFU(afu);
    AFU#(1) flopped <- mkRegShim(snooper);

    AFUHardware#(1) afuhw <- mkCAPIHardwareWrapper(ignoreParity(flopped));
	return afuhw;
endmodule

endpackage
