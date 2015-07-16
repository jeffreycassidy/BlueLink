package MMIO;

import Reserved::*;
import DefaultValue::*;
import Vector::*;
import PSLTypes::*;
import DReg::*;
import ClientServer::*;
import GetPut::*;

export MMIO::*;
export GetPut::*;
export ClientServer::*;

// TODO: These SetReset/ResetSet don't belong here

interface SetReset;
    method Action set;
    method Action rst;
    method Bool _read;
    method Bool startval;           // value at beginning of cycle
endinterface

module mkSetReset#(Bool init)(SetReset);
    Reg#(Bool) st[3] <- mkCReg(3,init);
    method Action set = st[0]._write(True);
    method Action rst = st[1]._write(False);
    method Bool _read = st[2];
    method Bool startval = st[0]._read;
endmodule

module mkResetSet#(Bool init)(SetReset);
    Reg#(Bool) st[3] <- mkCReg(3,init);
    method Action rst = st[0]._write(False);
    method Action set = st[1]._write(True);
    method Bool _read = st[2];
    method Bool startval = st[0]._read;
endmodule
function Bit#(32) upper(Bit#(64) i) = truncate(pack(i>>32));
function Bit#(32) lower(Bit#(64) i) = truncate(pack(i));

typedef union tagged {
    struct { UInt#(24) index; Bit#(64) data; }  DWordWrite;
    struct { UInt#(24) index; Bit#(32) data; }  WordWrite;
    struct { UInt#(24) index; } WordRead;
    struct { UInt#(24) index; } DWordRead;
} MMIORWRequest deriving(Bits,Eq);

instance FShow#(MMIORWRequest);
    function Fmt fshow(MMIORWRequest r) = case (r) matches
        tagged DWordWrite   { index: .dwi, data: .dwd}: $format("MMIO write to dword  index %06X, value %016X",dwi,dwd);
        tagged WordWrite    { index: .wi,  data:  .wd}: $format("MMIO write to word   index %06X, value %08X",wi,wd);
        tagged WordRead     { index: .wi}:              $format("MMIO read from word  index %06X",wi);
        tagged DWordRead    { index: .dwi}:             $format("MMIO read from dword index %06X",dwi);
    endcase;
endinstance



import StmtFSM::*;
import DReg::*;

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

    RWire#(MMIOResponse) mmResp <- mkRWire;
    Reg#(Maybe#(MMIOResponse)) mmRespQ <- mkReg(tagged Invalid);
    let mmWaiting <- mkSetReset(False);

    (* mutually_exclusive="mmCfgResp,mmDataResp" *)
    rule mmCfgResp;
        let r <- mmCfg.response.get;
        $display($time," INFO: config response ",fshow(r));
        mmResp.wset(r);
    endrule

    rule mmDataResp;
        let r <- mmPSA.response.get;
        $display($time," INFO: data response ",fshow(r));
        mmResp.wset(r);
    endrule

    rule showResp if (mmResp.wget matches tagged Valid .v);
        $display($time," INFO: mmResp=",fshow(v));
    endrule

    rule saveIt;
        mmRespQ <= mmResp.wget;
    endrule

    rule showIt if (mmRespQ matches tagged Valid .v);
        $display($time," INFO: mmRespQ=",fshow(v));
    endrule


    interface Put request;
        method Action put(MMIOCommand cmd);
            $display($time," INFO: MMIO Command received ",fshow(cmd));
//            if (mmWaiting.startval)
//                $display($time," ERROR: MMIO command issued before previous command completed");

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
                mmPSA.request.put(req);
            else
            begin
                $display($time,"ERROR: MMIO problem-space access request while AFU not running");
//                mmResp.wset(WriteAck);
            end

            mmWaiting.set;
        endmethod
    endinterface

    interface ReadOnly response;
        method MMIOResponse _read if (mmRespQ matches tagged Valid .v) = v;
    endinterface
endmodule


endpackage
