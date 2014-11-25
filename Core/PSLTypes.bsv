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

import ClientServerFL::*;
import Convenience::*;

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




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Interface defintions for dealing with low-level Verilog modules
//
// AR: Always ready (can accept a request at any time)
// U:  Unbuffered (response is presented for one cycle only, no handshake)
//
// This differs from normal Bluespec semantics where Get/Put often are connected with FIFOs

interface ServerARU#(type req_t,type res_t);
    (* always_ready *)
    interface Put#(req_t)       request;
    interface ReadOnly#(res_t)  response;
endinterface

interface ClientU#(type req_t,type res_t);
    interface ReadOnly#(req_t)  request;

    (* always_ready *)
    interface Put#(res_t)     response;
endinterface

instance Connectable#(ClientU#(req_t,res_t),ServerARU#(req_t,res_t));
    module mkConnection#(ClientU#(req_t,res_t) client,ServerARU#(req_t,res_t) server)();
        mkConnection(client.request,server.request);
        mkConnection(server.response,client.response);
    endmodule
endinstance


// Note: client is unbuffered, user must make sure that Server does not ignore a request due to blocking
instance Connectable#(ClientU#(req_t,res_t),Server#(req_t,res_t));
    module mkConnection#(ClientU#(req_t,res_t) client,Server#(req_t,res_t) server)();
        mkConnection(client.request,server.request);
        mkConnection(server.response,client.response);
    endmodule
endinstance

// Note: client is unbuffered, user must make sure that ServerFL (fixed latency) does not ignore a request due to blocking
instance Connectable#(ClientU#(req_t,res_t),ServerFL#(req_t,res_t,lat));
    module mkConnection#(ClientU#(req_t,res_t) client,ServerFL#(req_t,res_t,lat) server)();
        mkConnection(toGet(asIfc(client.request)),server.request);
        mkConnection(server.response,client.response);
    endmodule
endinstance




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Basic typedefs

typedef UInt#(8)                                                    RequestTag;
typedef DataWithParity#(Bit#(512),WordWiseParity#(8,OddParity))     DWordWiseOddParity512;

// wrap these in structs so they're nicely formatted when we print; can't define FShow#() if it's just a plain UInt#()
typedef struct { UInt#(64) code; } ErrorCode    deriving(Eq,Bits,Literal);
typedef struct { UInt#(64) addr; } EAddress64   deriving(Eq,Bits,Arith,Literal,Ord);

instance FShow#(ErrorCode);
    function Fmt fshow(ErrorCode e) = $format("Error %-d",e.code);    
endinstance

instance FShow#(EAddress64);
    function Fmt fshow(EAddress64 a) = $format("EA 0x%016X",a.addr);
endinstance




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PSL & AFU toplevel interfaces
//
// PSL and AFU are mostly conjugate interfaces (generally a Put for every Get, Client for every Server etc)
// some glue logic is required to connect the control interface (found in the Connectable#(...) instance )
// 
// The client should write a module conforming to the AFU interface, instantiate it and a mkPSL, and then connect the two



/** Basic PSL interface, using as direct a mapping as possible from module ports to BSV methods
 */

interface PSL;
    interface ServerARU#(CacheCommandWithParity,CacheResponseWithParity)                command;
    interface PSLBufferInterfaceWithParity                                              buffer;
    interface ClientU#(MMIOCommandWithParity,DataWithParity#(MMIOResponse,OddParity))   mmio;

    interface ReadOnly#(JobControlWithParity)                               control;

    (* always_enabled,always_ready *)
    method Action status(UInt#(64) ah_jerror, Bool ah_jrunning);

    (* always_ready *)
    method Action done;             // assert for single pulse to ack reset, or say accelerator done

    (* always_ready *)
    method Action yield;            // single-cycle pulse to yield

    (* always_ready *)
    method Action tbreq;            // single-cycle pulse to request timebase

    (* always_ready *)
    method Action jcack;

    (* always_ready *)
    method PSL_Description description;
endinterface

// Static PSL descriptor passed to AFU; static from reset to done, may change in between
typedef struct {
    UInt#(8)    croom;              // Number of supported in-flight commands
} PSL_Description deriving(Bits);




/** Basic AFU interface
 * Numeric type parameter brlat specifies buffer read latency
 *
 * Client module can provide this and connect to the PSL, but other interfaces offer more functionality
 */

interface AFU#(numeric type brlat);
    interface ClientU#(CacheCommandWithParity,CacheResponseWithParity)  command;
    interface AFUBufferInterfaceWithParity#(brlat)                      buffer;
    interface ServerARU#(MMIOCommandWithParity,DataWithParity#(MMIOResponse,OddParity))  mmio;

    (* always_ready *)
    interface Put#(JobControlWithParity)  control;

    (* always_ready *)
    method Bool tbreq;

    (* always_ready *)
    method Bool yield;

    (* always_ready *)
    method AFU_Status status;

    // static method, must not change during operation (once reset done)
    (* always_ready *)
    method AFU_Description                                              description;
endinterface

typedef struct {
    UInt#(4)    brlat;      // buffer read latency (for write commands)
    UInt#(8)    lroom;      // # LPC/Internal cache ops accelerator can handle (?)
    Bool        pargen;     // parity generation enable
    Bool        parcheck;   // check parity at inputs
} AFU_Description deriving(Bits);

// Simple status descriptor
typedef struct {
    Bool        running;
    Bool        done;
    UInt#(64)   errcode;
} AFU_Status deriving(Bits);



/** Basic PSL-AFU connection, passing through parity (does not do any parity checks or enforce PSL interface handshakes
 * (eg. single-clock pulse for done etc)
 */

instance Connectable#(PSL,AFU#(brlat));
    module mkConnection#(PSL psl,AFU#(brlat) afu)();
        mkConnection(afu.command,psl.command);
        mkConnection(psl.buffer,afu.buffer);
        mkConnection(psl.mmio,afu.mmio);
        mkConnection(toGet(psl.control),afu.control);

        // assert done to PSL if afu output high (does NOT ensure single-clock pulse!)
        mkDoIf(afu.status.done,psl.done);

        // send status to PSL (does NOT ensure correct transitions!)
        rule sendstatus;
            psl.status(afu.status.errcode,afu.status.running);
        endrule

        // TODO: add jcack, tbreq, yield
    endmodule
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
} CacheCommand deriving(Bits);

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

// the AFU side is parametrized by its read latency
interface AFUBufferInterfaceWithParity#(numeric type brlat);
    interface ServerFL#(BufferReadRequestWithParity,DWordWiseOddParity512,brlat)    writedata;

    (* always_ready *)
    interface Put#(BufferWriteWithParity)                                           readdata;
endinterface

interface AFUBufferInterface#(numeric type brlat); 
    interface ServerFL#(BufferReadRequest,Bit#(512),brlat)                          writedata;

    (* always_ready *)
    interface Put#(BufferWrite)                                                     readdata;
endinterface

instance Connectable#(PSLBufferInterfaceWithParity,AFUBufferInterfaceWithParity#(lat));
    module mkConnection#(PSLBufferInterfaceWithParity pslbuff,AFUBufferInterfaceWithParity#(brlat) afubuff)();
        mkConnection(pslbuff.readdata,afubuff.readdata);
        mkConnection(pslbuff.writedata,toServer(afubuff.writedata));
    endmodule
endinstance


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
// Request is outstanding until ACK'd

typedef union tagged {
    void        WriteAck;
    Bit#(32)    WordData;
    Bit#(64)    DWordData;
} MMIOResponse;

instance Bits#(MMIOResponse,64);
    function Bit#(64) pack(MMIOResponse u) = case (u) matches
        tagged WriteAck:        ?;
        tagged WordData .wd:    { wd, wd };
        tagged DWordData .dwd:  dwd;
    endcase;
endinstance

instance FShow#(MMIOResponse);
    function Fmt fshow(MMIOResponse resp) = fshow("MMIO Response: ") + (case(resp) matches
        tagged WriteAck:         fshow("Ack                     ");
        tagged WordData .w:     (fshow("Word  ") + fshow(w) + fshow("        "));
        tagged DWordData .dw:   (fshow("DWord ") + fshow(dw));
        endcase);
endinstance



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Job control interface (provided by PSL to AFU)
//


typedef struct { 
    DataWithParity#(PSLJobOpcode,OddParity)   opcode;
    DataWithParity#(EAddress64,OddParity)     jea;
} JobControlWithParity deriving(Bits);

typedef struct { 
    PSLJobOpcode    opcode;
    EAddress64      jea;
} JobControl deriving(Bits);

instance ParityStruct#(JobControl,JobControlWithParity);
    function JobControlWithParity make_parity_struct(Bool pargen,JobControl jc) = 
        JobControlWithParity {
            opcode: make_parity_struct(pargen,jc.opcode),
            jea:    make_parity_struct(pargen,jc.jea) };

    function Bool parity_ok(JobControlWithParity jcp) = parity_ok(jcp.opcode) && parity_ok(jcp.jea);

    function JobControl ignore_parity(JobControlWithParity jcp) =
        JobControl {
            opcode: ignore_parity(jcp.opcode),
            jea:    ignore_parity(jcp.jea) };
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



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Segmented register
//
// Allows a register to be read and written in pieces, or read as a whole (typical use for P8 cache line reg, eg. WED)
//
// Segments are read/written using writeseg(idx,data) or readseg(idx); whole register read using _read method
//
//  data_t  The complete data type
//  ns      Number of segments
//  nbs     Number of bits per segment
//  ni      Number of index bits

interface SegmentedReg#(type data_t,numeric type ns,numeric type nbs,numeric type ni);
    (* always_ready *)
    method Action writeseg(UInt#(ni) idx,Bit#(nbs) data);

    (* always_ready *)
    method Bit#(nbs) readseg(UInt#(ni) idx);

    (* always_ready *)
    method data_t _read;
endinterface

module mkSegmentedReg(SegmentedReg#(data_t,ns,nbs,ni)) provisos (Bits#(data_t,nb),Mul#(nbs,ns,nb));
    Vector#(ns,Reg#(Bit#(nbs))) regs <- replicateM(mkReg(0));
    
    method Action writeseg(UInt#(ni) idx,Bit#(nbs) data)    = regs[idx]._write(data);
    method Bit#(nbs) readseg(UInt#(ni) idx)                 = regs[idx]._read;

    method data_t _read = unpack(pack(readVReg(reverse(regs))));
endmodule

typedef SegmentedReg#(data_t,2,512,6) P8CacheLineReg#(type data_t);

endpackage
