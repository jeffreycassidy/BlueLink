package MMIO;

import Reserved::*;
import DefaultValue::*;
import Vector::*;
import PSLTypes::*;
import ClientServer::*;
import GetPut::*;
import ClientServerU::*;

export MMIO::*;
export GetPut::*;
export ClientServer::*;
export ClientServerU::*;

import FIFO::*;
import FIFOF::*;

import DReg::*;

import Assert::*;

function Bit#(32) upper(Bit#(64) i) = truncate(pack(i>>32));
function Bit#(32) lower(Bit#(64) i) = truncate(pack(i));
function Bit#(64) replicateWord(Bit#(32) i) = { i,i };

typedef union tagged {
    struct { UInt#(24) index; Bit#(64) data; }  DWordWrite;
    struct { UInt#(24) index; Bit#(32) data; }  WordWrite;
    struct { UInt#(24) index; } WordRead;
    struct { UInt#(24) index; } DWordRead;
} MMIORWRequest deriving(Bits,Eq);

function Bool isMMIOWrite(MMIORWRequest req) = case (req) matches
    tagged DWordWrite .*: True;
    tagged WordWrite .*: True;
    default: False;
endcase;

function Bool isMMIORead(MMIORWRequest req) = case (req) matches
    tagged DWordRead .*: True;
    tagged WordRead .*: True;
    default: False;
endcase;

instance FShow#(MMIORWRequest);
    function Fmt fshow(MMIORWRequest r) = case (r) matches
        tagged DWordWrite   { index: .dwi, data: .dwd}: $format("MMIO write to dword  index %06X, value %016X",dwi,dwd);
        tagged WordWrite    { index: .wi,  data:  .wd}: $format("MMIO write to word   index %06X, value %08X",wi,wd);
        tagged WordRead     { index: .wi}:              $format("MMIO read from word  index %06X",wi);
        tagged DWordRead    { index: .dwi}:             $format("MMIO read from dword index %06X",dwi);
    endcase;
endinstance



import StmtFSM::*;

// Reg interface with different semantics: _read only when valid contents, _write sets contents valid next cycle
// Acts like a Wire#() but delays one cycle

function Reg#(t) toMReg(Reg#(Maybe#(t)) r) = interface Reg;
        method Action _write(t i) = r._write(tagged Valid i);
        method t _read if (r._read matches tagged Valid .v) = v;
    endinterface;



/** mkMMIOSplitter(mmCfg,mmPSA)
 *
 * Splits MMIO config-space requests from problem-space requests and forwards them to the appropriate interfaces.
 * Has a register stage before the output.
 *
 * mkMMIOSplitter(mmCfg,mmPSA)
 *
 *  mmCfg   Server for config-space requests
 *  mmPSA   Server for problem-space requests
 *
 */

module mkMMIOSplitter#(Server#(MMIORWRequest,MMIOResponse) mmCfg,Server#(MMIORWRequest,MMIOResponse) mmPSA,Bool running)
    (ServerARU#(MMIOCommand,MMIOResponse));

    FIFO#(MMIOResponse) mmResp <- mkFIFO1;

    Wire#(MMIOResponse) o <- mkWire;

    (* mutually_exclusive="mmCfgResp,mmDataResp" *)
    rule mmCfgResp;
        let r <- mmCfg.response.get;
        mmResp.enq(r);
    endrule
    
    rule mmDataResp;
        let r <- mmPSA.response.get;
        mmResp.enq(r);
    endrule


    // decouple sending the downstream request from the method to break the chain of implicit conditions
    // fire_when_enabled assertion checks that the downstream module never applies backpressure when a request is coming in

    Reg#(Maybe#(MMIORWRequest)) mmPSAReq <- mkDReg(tagged Invalid);

    (* fire_when_enabled *)
    rule mmPSASend if (mmPSAReq matches tagged Valid .v);
        mmPSA.request.put(v);
    endrule

    mkConnection(toGet(mmResp),toPut(asIfc(o)));

    interface Put request;
        method Action put(MMIOCommand cmd);
            MMIORWRequest req;
            if (cmd.mmrnw)
                req = cmd.mmdw ?
                    tagged DWordRead  { index: cmd.mmad>>1 } :
                    tagged WordRead   { index: cmd.mmad };
            else
                req = cmd.mmdw ?
                    tagged DWordWrite { index: cmd.mmad>>1, data: cmd.mmdata } :
                    tagged WordWrite  { index: cmd.mmad,    data: cmd.mmdata[31:0] };

            if (cmd.mmcfg)
                mmCfg.request.put(req);
            else if (running)
                mmPSAReq._write(tagged Valid req);      // no implicit conditions here, but downstream may have implicit
                                                        // but check in this module that it can always fire
            else
                $display($time,"ERROR: MMIO problem-space access request while AFU not running");

        endmethod
    endinterface

    interface ReadOnly response;
        method MMIOResponse _read = o;
    endinterface
endmodule


endpackage
