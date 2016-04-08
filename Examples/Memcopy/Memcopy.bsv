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
import Reserved::*;
import DReg::*;
import StmtFSM::*;
import Vector::*;
import PSLTypes::*;
import AFU::*;
import AFUShims::*;
import AFUHardware::*;
import FIFOF::*;
import Assert::*;
import ConfigReg::*;
import ClientServerU::*;
import PAClib::*;

//typeclass ToReadOnlyM#(type t,type ifc);
//    function ReadOnly#(t) toReadOnlyM(ifc i);
//endtypeclass
//
//instance ToReadOnlyM#(t,Reg#(Maybe#(t)));
//    function ReadOnly#(t) toReadOnlyM(Reg#(Maybe#(t)) r) = interface ReadOnly;
//        method t _read if (r matches tagged Valid .v) = v;        
//    endinterface;
//endinstance
//
//typeclass ToPutM#(type t,type ifc);
//    function Put#(t) toPutM(Reg#(Maybe#(t)) r) = interface Put;
//        method Action put(t i) = r._write(tagged Valid i);
//    endinterface;
//endtypeclass

typeclass ToReadOnly#(type t,type ifc);
    function ReadOnly#(t) toReadOnly(ifc i);
endtypeclass

instance ToReadOnly#(t,Reg#(t));
    function ReadOnly#(t) toReadOnly(Reg#(t) i) = regToReadOnly(i);
endinstance

instance ToReadOnly#(t,t);
    function ReadOnly#(t) toReadOnly(t i) = interface ReadOnly;
        method t _read = i;
    endinterface;
endinstance


/***********************************************************************************************************************************
 * Memcopy AFU
 *
 * Fixed buffer read latency of 1, no parity generation or checking
 *
 * Does not handle faults (page, address/data error)
 */


function EAddress64 offset(EAddress64 addr,UInt#(n) o) provisos (Add#(n,__some,64));
    return EAddress64 { addr: addr.addr + extend(o) };
endfunction

typedef struct {
    LittleEndian#(EAddress64) addrFrom;
    LittleEndian#(EAddress64) addrTo;
    LittleEndian#(UInt#(64))  size;

    Reserved#(832)  resv;
} WED deriving(Bits);



typedef enum { Unknown, Resetting, Ready, WEDRead, Waiting, Running, Done } Status deriving(Eq,FShow,Bits);

module mkMemcopy(AFU#(2));
    // setup parameters
    Reg#(Maybe#(EAddress64)) ea <- mkReg(tagged Invalid);

    Reg#(EAddress64) addrFrom       <- mkReg(0);
    Reg#(EAddress64) addrTo         <- mkReg(0);
    Reg#(EAddress64) addrFromEnd    <- mkReg(0);

    // internal status
    Reg#(Status)    st      <- mkReg(Unknown);
    Reg#(UInt#(64)) errct   <- mkReg(0);
    let             pwFinish <- mkPulseWire;
    let             pwStart <- mkPulseWire;

    // work element descriptor: 2 segments of 512b each
    Vector#(2,Reg#(Bit#(512))) wedSegs <- replicateM(mkConfigReg(0));
    WED wed = concatSegReg(wedSegs,LE);

    // status outputs
    Reg#(UInt#(64)) stErrcode  <- mkReg(0);
    Reg#(Bool)      stRunning  <- mkReg(False);
    PulseWire       pwDone     <- mkPulseWire;


    FIFOF#(CacheCommand) oCmd <- mkLFIFOF;

    // PSL Cache Command to issue
    function Action requestRead(RequestTag tag,EAddress64 addr) =
        oCmd.enq(CacheCommand { ctag: tag, cch: 0, com: Read_cl_s, cea: addr, csize: 128, cabt: Strict });

    function Action requestWrite(RequestTag tag,EAddress64 addr) =
        oCmd.enq(CacheCommand { ctag: tag, cch: 0, com: Write_mi,  cea: addr, csize: 128, cabt: Strict });

    Wire#(RequestTag) completion <- mkWire;

    // Data buffering functions
    Vector#(2,Reg#(Bit#(512)))          readbuf     <- replicateM(mkReg(0));

    FIFOF#(BufferWrite)                 bwIn        <- mkGFIFOF1(True,False);
    FIFOF#(Bit#(512))                   brOut       <- mkLFIFOF;
    FIFOF#(UInt#(6))                    bradQ       <- mkGFIFOF1(True,False);


    // FSM for handling memcpy
    Stmt memcpystmts = seq
        // Reset
        action
            $display($time,": Memcopy block resetting");
            st <= Resetting;
        endaction
        ea <= tagged Invalid;
        stErrcode  <= 0;
        stRunning  <= False;
        errct <= 0;

        action
            $display($time,": Memcopy block ready");
            pwDone.send;
            st <= Ready;
        endaction



        // launch WED read
        action
            await(isValid(ea));
            stRunning <= True;
            st <= WEDRead;
            $display($time,": Memcopy block reading WED");
            requestRead(0,ea.Valid);
        endaction

        // start copy when WED read is done
        action
            await(completion==0);
            st <= Waiting;
            addrFrom        <= unpackle(wed.addrFrom);
            addrFromEnd     <= offset(unpackle(wed.addrFrom),unpackle(wed.size));
            addrTo          <= unpackle(wed.addrTo);
            $display($time,": Memcopy block starting with WED addrFrom=%016X addrTo=%016X size=%016X",
                unpackle(wed.addrFrom),
                unpackle(wed.addrTo),
                unpackle(wed.size));
        endaction

        action
            st <= Running;
            await(pwStart);
        endaction


        // do the transfer using a single tag and single data buffer
        while (addrFrom != addrFromEnd)
        seq
            requestRead(0,addrFrom);

            action
                await(completion==0);
                requestWrite(0,addrTo);
                addrFrom <= addrFrom+128;
            endaction

            action
                await(completion==0);
                addrTo <= addrTo+128;
            endaction
        endseq

        st <= Done;

        noAction;

        await(pwFinish);

        action
            stRunning <= False;
            st <= Done;
        endaction
        noAction;
        pwDone.send;
    endseq;

    let memcpyfsm <- mkFSM(memcpystmts);

    // Wrapper provides hard reset, so we should always start when we can
    rule alwaysStart;
        memcpyfsm.start;
    endrule



    // Sink buffer writes, either to WED reg or transfer buffer

    function Action bufWrite(BufferWrite bw) = case(st) matches
        WEDRead: wedSegs[bw.bwad]._write(bw.bwdata);
        Running: readbuf[bw.bwad]._write(bw.bwdata);
        default: $display($time," ERROR: Unexpected buffer write");
    endcase;
    mkSink_to_fa(bufWrite, f_FIFOF_to_PipeOut(bwIn));



    // Handle buffer reads

    function Action bufRead(UInt#(6) offs) = brOut.enq(readbuf[offs]);

    mkSink_to_fa(bufRead, f_FIFOF_to_PipeOut(bradQ));
    mkSink(f_FIFOF_to_PipeOut(brOut));



    // unguarded enqs (should never get a second request before completion)
    FIFOF#(MMIOCommand) mmioReq  <- mkGFIFOF1(True,False);
    FIFOF#(Bit#(64))    mmioResp <- mkGFIFOF1(True,False);

    rule mmioConfigRead if (mmioReq.first.mmcfg && mmioReq.first.mmrnw);
        mmioReq.deq;
        case(mmioReq.first.mmad) matches
            24'h000000: mmioResp.enq(64'h0001000100008010);
            24'h000002: mmioResp.enq(64'h0000000000000000);
            24'h000004: mmioResp.enq(64'h0000000000000000);
            24'h000006: mmioResp.enq(64'h0000000000000000);
            24'h000008: mmioResp.enq(64'h0000000000000000);
            24'h00000a: mmioResp.enq(64'h0000000000000000);
            24'h00000c: mmioResp.enq(64'h0100000000000000);     // problem state area required
            24'h000010: mmioResp.enq(64'h0000000000000000);
            default:    
                action
                    $display($time," WARNING: Unexpected MMIO config read to %06X",mmioReq.first.mmad);
                    mmioResp.enq(64'h0000000000000000);
                endaction
        endcase
    endrule

    rule mmioConfigWrite if (mmioReq.first.mmcfg && !mmioReq.first.mmrnw);
        mmioReq.deq;
        mmioResp.enq(64'h0);
        $display($time," WARNING: Unexpected MMIO config write to %06X value %016X",mmioReq.first.mmad,mmioReq.first.mmdata);
    endrule

    rule mmioRead if (!mmioReq.first.mmcfg && mmioReq.first.mmrnw);
        mmioReq.deq;
        case(mmioReq.first.mmad) matches
            24'h000000: mmioResp.enq(
                case (st) matches
                    Ready:      1;
                    Waiting:    2;
                    Running:    3;
                    Done:       4;
                    default:    0;
                endcase);
            24'h000002: mmioResp.enq(pack(unpackle(wed.size)));
            24'h000004: mmioResp.enq(pack(unpackle(wed.addrFrom)));
            24'h000006: mmioResp.enq(pack(unpackle(wed.addrTo)));
            default:
            action
                $display($time," WARNING: Unexpected MMIO problem-state read to address %06X",mmioReq.first.mmad);
                mmioResp.enq(64'hdeadbeefbaadc0de);
            endaction
        endcase
    endrule

    rule mmioWrite if (!mmioReq.first.mmcfg && !mmioReq.first.mmrnw);
        mmioReq.deq;
        case (tuple2(mmioReq.first.mmad,mmioReq.first.mmdata)) matches
            { 24'h000000, 64'h0 }: pwStart.send;
            { 24'h000000, 64'h1 }: pwFinish.send;
            default:
                $display($time," WARNING: Unexpected MMIO problem-state write to %06X value %016X",mmioReq.first.mmad,mmioReq.first.mmdata);
        endcase
        mmioResp.enq(64'h0);
    endrule

    rule alwaysDeqMMIOResp;
        mmioResp.deq;
    endrule

    rule alwaysDeqCommand;
        oCmd.deq;
    endrule


    // MMIO offsets are calculated in word terms
    interface ServerARU mmio;
        interface Put request = toPut(mmioReq);
        interface ReadOnly response = toReadOnly(mmioResp.first);
    endinterface

    interface ClientU command;
        interface ReadOnly request = toReadOnly(oCmd.first);

        interface Put response;
            method Action put(CacheResponse resp);
                if (resp.response != Done) 
                begin
                    $display($time," ERROR: Not expecting a response of type ",fshow(resp));
                    errct <= errct+1;
                end

                completion <= resp.rtag;
            endmethod
        endinterface
    endinterface

    interface AFUBufferInterface buffer;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequest brr) = bradQ.enq(brr.brad);
            endinterface

            interface ReadOnly response = toReadOnly(brOut.first);
        endinterface

        interface Put readdata = toPut(bwIn);
    endinterface

    interface Put control;
        method Action put(JobControl jc);
            case (jc) matches
                tagged JobControl { opcode: Start, jea: .jea }:
                    ea <= tagged Valid jea;
                tagged JobControl { opcode: Reset }:
                    noAction;       // can safely ignore since wrapper produces a hard reset
                default:
                    $display("Unknown opcode: ",fshow(jc.opcode));
            endcase
        endmethod
    endinterface

    interface AFUStatus status;
        method Bool tbreq           = False;
        method Bool jyield          = False;
        method Bool jrunning        = stRunning;
        method Bool jdone           = pwDone;
        method UInt#(64) jerror     = stErrcode;
        method Bool jcack           = False;
    endinterface
endmodule


(* clock_prefix="ha_pclock" *)
module mkMemcopyAFU(AFUHardware#(2));
	AFU#(2) afu <- mkMemcopy;
    AFUWithParity#(2) pAFU = afuParityWrapper(afu);
    AFUWithParity#(2) snooper <- mkAFUShimSnoop(pAFU);

    AFUHardware#(2) afuhw <- mkCAPIHardwareWrapper(snooper);
	return afuhw;
endmodule

endpackage
