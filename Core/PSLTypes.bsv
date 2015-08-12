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

package PSLTypes;

import Parity::*;
import Vector::*;
import Connectable::*;
import ClientServer::*;
import GetPut::*;
import PSLCommands::*;
import PSLJobOpcodes::*;
import PSLControlCommands::*;
import PSLTranslationOrderings::*;
import PSLResponseCodes::*;
import Assert::*;

// re-export PSL commands necessary to use these types
export PSLCommands::*;
export PSLResponseCodes::*;
export PSLJobOpcodes::*;
export PSLTranslationOrderings::*;
export PSLControlCommands::*;

// re-export essential dependencies for convenience
export Parity::*;
export GetPut::*;
export ClientServer::*;
export Connectable::*;
export FShow::*;

// export this module
export PSLTypes::*;

import ClientServerU::*;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Basic typedefs (RequestTag, Data words, Effective address)

typedef UInt#(8)                                                    RequestTag;
typedef DataWithParity#(Bit#(512),WordWiseParity#(8,OddParity))     DWordWiseOddParity512;

// wrap these in structs so they're nicely formatted when we print; can't define FShow#() if it's just a plain UInt#()
typedef struct { UInt#(64) code; } ErrorCode    deriving(Eq,Bits,Literal);
typedef struct { UInt#(64) addr; } EAddress64   deriving(Eq,Bits,Arith,Literal,Ord);
typedef EAddress64 Offset64;
typedef EAddress64 Size64;

function Bool aligned(Integer nbytes, EAddress64 addr) = addr % fromInteger(nbytes) == 0;

instance SizedLiteral#(EAddress64,64);
    function EAddress64 fromSizedInteger(Bit#(64) b) = EAddress64 { addr: unpack(b) };
endinstance

instance FShow#(ErrorCode);
    function Fmt fshow(ErrorCode e) = $format("Error %-d",e.code);    
endinstance

instance FShow#(EAddress64);
    function Fmt fshow(EAddress64 a) = $format("EA 0x%016X",a.addr);
endinstance




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Accelerator command interface
//
// PSL is a Server#(CacheCommandWithParity,CacheResponseWithParity), AFU is a Client#(...)
//
// Interfaces and Connectable#(...) are derived since just using Server/Client


////////////////////////////////////////////////////////////////////////////////
// Cache command structures

typedef struct {
    RequestTag              ctag;
    PSLCommand              com;
    PSLTranslationOrdering  cabt;
    EAddress64              cea;
    UInt#(16)               cch;
    UInt#(12)               csize;  // Size in bytes (must be power of 2)
} CacheCommand deriving(Bits,FShow);

typedef struct {
    DataWithParity#(RequestTag,OddParity)   ctag;
    DataWithParity#(PSLCommand,OddParity)   com;
    PSLTranslationOrdering                  cabt;
    DataWithParity#(EAddress64,OddParity)   cea;
    UInt#(16)                               cch;
    UInt#(12)                               csize;
} CacheCommandWithParity deriving(Bits);

instance ParityStruct#(CacheCommand,CacheCommandWithParity);
    function CacheCommandWithParity make_parity_struct(Bool pargen,CacheCommand cmd) =
        CacheCommandWithParity {
            ctag:   make_parity_struct(pargen,cmd.ctag),
            com:    make_parity_struct(pargen,cmd.com),
            cabt:   cmd.cabt,
            cea:    make_parity_struct(pargen,cmd.cea),
            cch:    cmd.cch,
            csize:  cmd.csize };
 
    function Bool parity_ok(CacheCommandWithParity pcmd) = parity_ok(pcmd.ctag) && parity_ok(pcmd.cea) && parity_ok(pcmd.com);

    function CacheCommand ignore_parity(CacheCommandWithParity pcmd) =
        CacheCommand {
            ctag:   ignore_parity(pcmd.ctag),
            com:    ignore_parity(pcmd.com),
            cabt:   pcmd.cabt,
            cea:    ignore_parity(pcmd.cea),
            cch:    pcmd.cch,
            csize:  pcmd.csize };
endinstance

instance FShow#(CacheCommandWithParity);
    function Fmt fshow(CacheCommandWithParity c) = fshow("CacheCommand       [req ") + fshow(c.ctag) + fshow("] ") + fshow(c.com) +
        fshow(" cabt=") + fshow(c.cabt) + fshow(" addr=") + fshow(c.cea) + fshow(" csize=") + fshow(c.csize);
endinstance


////////////////////////////////////////////////////////////////////////////////
// Cache command response structures

typedef struct {
    RequestTag          rtag;           // Accelerator-generated ID for request
    PSLResponseCode     response;       // Response code
    Int#(9)             rcredits;       // Two's complement #credits returned
    Bit#(2)             rcachestate;    // reserved
    UInt#(13)           rcachepos;      // reserved
} CacheResponse deriving(Bits);

typedef struct {
    DataWithParity#(RequestTag,OddParity)   rtag;
    PSLResponseCode                         response;
    Int#(9)                                 rcredits;
    Bit#(2)                                 rcachestate;
    UInt#(13)                               rcachepos;
} CacheResponseWithParity deriving(Bits);

instance ParityStruct#(CacheResponse,CacheResponseWithParity);
    function CacheResponseWithParity make_parity_struct(Bool pargen,CacheResponse r) =
        CacheResponseWithParity {
            rtag:       make_parity_struct(pargen,r.rtag),
            response:   r.response,
            rcredits:   r.rcredits,
            rcachestate:r.rcachestate,
            rcachepos:  r.rcachepos };

    function Bool parity_ok(CacheResponseWithParity pr) = parity_ok(pr.rtag);

    function CacheResponse ignore_parity(CacheResponseWithParity pr) = 
        CacheResponse {
            rtag:       ignore_parity(pr.rtag),
            response:   pr.response,
            rcredits:   pr.rcredits,
            rcachestate:pr.rcachestate,
            rcachepos:  pr.rcachepos };
endinstance

instance FShow#(CacheResponseWithParity);
    function Fmt fshow(CacheResponseWithParity r) =
        fshow("CacheResponse      [req ") + fshow(r.rtag) + fshow("] ") + fshow(r.response) + fshow(" credits: ") +
        fshow(r.rcredits) + fshow(" cache state:") + fshow(r.rcachestate) + fshow(" cache pos: ") + fshow(r.rcachepos);
endinstance

instance FShow#(CacheResponse);
    function Fmt fshow(CacheResponse r) =
        fshow("CacheResponse      [req ") + fshow(r.rtag) + fshow("] ") + fshow(r.response) + fshow(" credits: ") +
        fshow(r.rcredits) + fshow(" cache state:") + fshow(r.rcachestate) + fshow(" cache pos: ") + fshow(r.rcachepos);
endinstance




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Buffer interface
//
// NOTE: Buffer read/write names are wrt. the buffer (reversed wrt. accelerator command issued)
// the PSL _reads_ the buffer during a _write_ operation & vice-versa
// br refers to a buffer read, which is triggered by a write request
//
// accelerator-initiated write command: 
//      issue write command
//      wait for ha_brvalid
//      write data to ah_brdata after ah_brlat cycles
//
// accelerator-initiated read command:
//      issue read command
//      wait for ha_bwvalid
//      data written into buffer

interface PSLBufferInterfaceWithParity;
        interface ClientU#(BufferReadRequestWithParity,DWordWiseOddParity512)       writedata;
        interface ReadOnly#(BufferWriteWithParity)                                  readdata;
endinterface

interface PSLBufferInterface;
    interface ClientU#(BufferReadRequest,Bit#(512))                                 writedata;
    interface ReadOnly#(BufferWrite)                                                readdata;
endinterface


////////////////////////////////////////////////////////////////////////////////
// Buffer read request/response (PSL asking accelerator to provide data for write)
typedef struct {
    RequestTag      brtag;
    UInt#(6)        brad;
} BufferReadRequest deriving(Bits);

typedef struct {
    DataWithParity#(RequestTag,OddParity)   brtag;
    UInt#(6)                                brad;   // Halfline index (512b word, 1024b line; only LSB changes)
} BufferReadRequestWithParity deriving(Bits);

instance ParityStruct#(BufferReadRequest,BufferReadRequestWithParity);
    function BufferReadRequestWithParity make_parity_struct(Bool pargen,BufferReadRequest rreq) = 
        BufferReadRequestWithParity {
            brtag:  make_parity_struct(pargen,rreq.brtag),
            brad:   rreq.brad };

    function Bool parity_ok(BufferReadRequestWithParity rreqp) = parity_ok(rreqp.brtag);

    function BufferReadRequest ignore_parity(BufferReadRequestWithParity rreqp) = 
        BufferReadRequest {
            brtag:  ignore_parity(rreqp.brtag),
            brad:   rreqp.brad };
endinstance

instance FShow#(BufferReadRequestWithParity);
    function Fmt fshow(BufferReadRequestWithParity rr) =
        fshow("BufferReadRequest  [req ") + fshow(rr.brtag) + fshow("] index ") + fshow(pack(rr.brad));
endinstance

instance FShow#(BufferReadRequest);
    function Fmt fshow(BufferReadRequest rr) =
        fshow("BufferReadRequest  [req ") + fshow(rr.brtag) + fshow("] index ") + fshow(pack(rr.brad));
endinstance


////////////////////////////////////////////////////////////////////////////////
// Buffer write (PSL providing data in response to a read)

typedef struct {
    RequestTag      bwtag;
    UInt#(6)        bwad;
    Bit#(512)       bwdata;
} BufferWrite deriving(Bits);

typedef struct {
    DataWithParity#(RequestTag,OddParity)           bwtag;
    UInt#(6)                                        bwad;
    DWordWiseOddParity512                           bwdata;
} BufferWriteWithParity deriving(Bits);

instance ParityStruct#(BufferWrite,BufferWriteWithParity);
    function BufferWriteWithParity make_parity_struct(Bool pargen,BufferWrite bw) = 
        BufferWriteWithParity {
            bwtag:  make_parity_struct(pargen,bw.bwtag),
            bwad:   bw.bwad,
            bwdata: make_parity_struct(pargen,bw.bwdata) };

    function Bool parity_ok(BufferWriteWithParity bwp) = parity_ok(bwp.bwdata) && parity_ok(bwp.bwtag);

    function BufferWrite ignore_parity(BufferWriteWithParity bwp) = 
        BufferWrite {
            bwtag:  ignore_parity(bwp.bwtag),
            bwad:   bwp.bwad,
            bwdata: ignore_parity(bwp.bwdata) };
endinstance

instance FShow#(BufferWriteWithParity);
    function Fmt fshow(BufferWriteWithParity bw) =
        fshow("BufferWriteRequest [req ") + fshow(bw.bwtag) + fshow(" index ") + fshow(bw.bwad) +
        fshow(" data: ") + fshow(bw.bwdata);
endinstance

instance FShow#(BufferWrite);
    function Fmt fshow(BufferWrite bw) =
        fshow("BufferWriteRequest [req ") + fshow(bw.bwtag) + fshow(" index ") + fshow(bw.bwad) +
        fshow(" data: ") + fshow(bw.bwdata);
endinstance




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MMIO Interface
//
// PSL is a Server#(PSL_MMIOCommand,PSL_MMIOResponse), AFU is Client#(...)
//

////////////////////////////////////////////////////////////////////////////////
// MMIO command

typedef struct {
    Bool                                    mmcfg;      // access to AFU descriptor space
    Bool                                    mmrnw;
    Bool                                    mmdw;       // dword=1 for 64b access, word=0 for 32b
    DataWithParity#(UInt#(24),OddParity)    mmad;       // word address
    DataWithParity#(Bit#(64),OddParity)     mmdata;     // data (word read must duplicate high/low)
} MMIOCommandWithParity deriving(Bits);

typedef struct {
    Bool        mmcfg;
    Bool        mmrnw;
    Bool        mmdw;
    UInt#(24)   mmad;
    Bit#(64)    mmdata;
} MMIOCommand deriving(Bits);

instance ParityStruct#(MMIOCommand,MMIOCommandWithParity);
    function MMIOCommandWithParity make_parity_struct(Bool pargen,MMIOCommand cmd) =
        MMIOCommandWithParity {
            mmcfg:      cmd.mmcfg,
            mmrnw:      cmd.mmrnw,
            mmdw:       cmd.mmdw,
            mmad:       make_parity_struct(pargen,cmd.mmad),
            mmdata:     make_parity_struct(pargen,cmd.mmdata) };

    function Bool parity_ok(MMIOCommandWithParity cmdp) = parity_ok(cmdp.mmad) && parity_ok(cmdp.mmdata);

    function MMIOCommand ignore_parity(MMIOCommandWithParity cmdp) = 
        MMIOCommand { 
            mmcfg:      cmdp.mmcfg,
            mmrnw:      cmdp.mmrnw,
            mmdw:       cmdp.mmdw,
            mmad:       ignore_parity(cmdp.mmad),
            mmdata:     ignore_parity(cmdp.mmdata) };
endinstance

instance FShow#(MMIOCommandWithParity);
    function Fmt fshow(MMIOCommandWithParity c) = 
        fshow("MMIOCommand: ") + fshow(c.mmcfg ? "config" : "regular") + fshow(" ") +
        fshow(c.mmdw ? "dword" : "word") + fshow(" ") +
        fshow(c.mmrnw ? "read from" : "write to") + fshow(" ") +
        fshow(c.mmad) + (c.mmrnw ? fshow("") : fshow("data=") + fshow(c.mmdata));
endinstance

instance FShow#(MMIOCommand);
    function Fmt fshow(MMIOCommand c) = 
        fshow("MMIOCommand: ") + fshow(c.mmcfg ? "config" : "regular") + fshow(" ") +
        fshow(c.mmdw ? "dword" : "word") + fshow(" ") +
        fshow(c.mmrnw ? "read from" : "write to") + fshow(" ") +
        fshow(c.mmad) + (c.mmrnw ? fshow("") : fshow("data=") + fshow(c.mmdata));
endinstance


////////////////////////////////////////////////////////////////////////////////
// MMIO Response (note read data should be duplicated high/low)


// The Bits#() representation here carries 2 extra bits for the tags; can be dropped with rawBits()
typedef union tagged {
    void        WriteAck;
    Bit#(32)    WordData;
    Bit#(64)    DWordData;
} MMIOResponse deriving(Bits,Eq);

instance FShow#(MMIOResponse);
    function Fmt fshow(MMIOResponse r) = case (r) matches
        tagged WriteAck:          fshow("MMIO Write Ack             ");
        tagged WordData .w:     $format("MMIO Word  %08X        ",w);
        tagged DWordData .dw:   $format("MMIO DWord %016X",dw);
    endcase;
endinstance

function Bit#(64) rawBits(MMIOResponse r) = case (r) matches
    tagged DWordData .dw:   dw;
    tagged WordData .w:     { w,w };
    tagged WriteAck:        64'h0;
endcase;



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Job control interface (provided by PSL to AFU)
//


typedef struct { 
    DataWithParity#(PSLJobOpcode,OddParity)     opcode;
    DataWithParity#(EAddress64,OddParity)       jea;
    UInt#(8)                                    croom;
} JobControlWithParity deriving(Bits);

typedef struct { 
    PSLJobOpcode    opcode;
    EAddress64      jea;
    UInt#(8)        croom;
} JobControl deriving(Bits);

instance ParityStruct#(JobControl,JobControlWithParity);
    function JobControlWithParity make_parity_struct(Bool pargen,JobControl jc) = 
        JobControlWithParity {
            opcode: make_parity_struct(pargen,jc.opcode),
            jea:    make_parity_struct(pargen,jc.jea),
            croom: jc.croom };

    function Bool parity_ok(JobControlWithParity jcp) = parity_ok(jcp.opcode) && parity_ok(jcp.jea);

    function JobControl ignore_parity(JobControlWithParity jcp) =
        JobControl {
            opcode: ignore_parity(jcp.opcode),
            jea:    ignore_parity(jcp.jea),
            croom: jcp.croom };
endinstance

instance FShow#(JobControlWithParity);
    function Fmt fshow(JobControlWithParity jc);
        return fshow("JobControl  Opcode=")+fshow(jc.opcode) + (case (ignore_parity(jc.opcode)) matches
            Start:      fshow(jc.jea);
            default:    fshow("");
        endcase);
    endfunction
endinstance

instance FShow#(JobControl);
    function Fmt fshow(JobControl jc);
        return fshow("JobControl  Opcode=")+fshow(jc.opcode) + (case (jc.opcode) matches
            Start:      fshow(jc.jea);
            default:    fshow("");
        endcase);
    endfunction
endinstance



/* AFU return status
 *
 */

// Status returned by a completed AFU
typedef union tagged {
    void        Done;
    UInt#(64)   Error;
} AFUReturn deriving(Bits,Eq,FShow);

// Status values for a running AFU (not necessarily returned)
typedef union tagged {
    void        Resetting;
    void        Ready;
    AFUReturn   Idle;           // Finished with given return code
} AFUCurrentStatus deriving(Bits,Eq,FShow);



/* SegReg
 *
 * A segmented register, accessible either as a whole (r.entire) or in segments (r.seg[N])
 * 
 * For IBM CAPI interface:
 *      increasing brad/bwad is increasing memory address
 *      within each line, leftmost byte comes from the low address
 *      P8 processor in little-endian mode
 *
 * But in Bluespec:
 *      vectors are stored in descending index order (MSB/L to R): v[N-1] v[N-2] .. v[1] v[0]
 *      bit indexing is always downto, with MSB at left
 *
 * Consequently:
 *      reading contiguous 1024b lines require swapping ( bwad0 -> v[1], bwad1 -> v[0]), after which
 *      r.seg[1] MS byte is lowest memory address in the line
 *      r.seg[0] LS byte is highest memory address in the line
 *      r.entire runs from lowest to highest memory address
 *      multi-byte word order is little-endian
 *  
 *      Order of elements in host struct and Bluespec struct/tuple are same
 *      Order of vectors stored in host are _reversed_ wrt Bluespec
 */

interface SegReg#(type t,numeric type ns,numeric type nbs);
    interface Vector#(ns,Reg#(Bit#(nbs))) seg;

    interface Reg#(t) entire;
endinterface


module mkSegReg#(t init)(SegReg#(t,ns,nbs)) provisos (Div#(nb,nbs,ns),Mul#(ns,nbs,nb),Bits#(t,nb));
    Vector#(ns,Bit#(nbs)) initChunks = reverse(toChunks(pack(init)));
    Vector#(ns,Reg#(Bit#(nbs))) r <- genWithM(compose(mkReg,select(initChunks)));

    interface Vector seg = r;

    interface Reg entire;
        method Action _write(t i) = writeVReg(reverse(r),toChunks(pack(i)));
        method t _read = unpack(pack(readVReg(reverse(r))));
    endinterface
endmodule


endpackage
