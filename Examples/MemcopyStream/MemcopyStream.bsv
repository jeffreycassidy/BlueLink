package MemcopyStream;

import Stream::*;
import WriteStream::*;
import ReadStream::*;

import AFU::*;
import AFUHardware::*;
import StmtFSM::*;
import PSLTypes::*;

import MMIO::*;
import FIFOF::*;
import Endianness::*;
import DedicatedAFU::*;
import Reserved::*;
import Vector::*;
import ReadStream::*;

import CmdArbiter::*;

import AFUShims::*;
import ConfigReg::*;

import CmdTagManager::*;

import ProgrammableLUT::*;
import HList::*;
import ModuleContext::*;

typedef struct {
    Integer     nReadTags;
    Integer     nReadBuf;
    Integer     nWriteTags;
    Integer     nWriteBuf;
    Bool        verbose;
    Bool        verboseData;
} Config;

typedef struct {
    LittleEndian#(EAddress64) addrFrom;
    LittleEndian#(EAddress64) addrTo;
    LittleEndian#(UInt#(64))  size;

    Reserved#(832)  resv;
} WED deriving(Bits);

typedef enum { Resetting, Ready, Waiting, Running, Done } Status deriving (Eq,FShow,Bits);

module [ModuleContext#(ctxT)] mkMemcopyStreamBase#(Config cfg)(DedicatedAFU#(2))
    provisos (
        Gettable#(ctxT,MemSynthesisStrategy));

    // WED
    Vector#(2,Reg#(Bit#(512))) wedSegs <- replicateM(mkConfigReg(0));
    WED wed = concatSegReg(wedSegs,LE);

    // Command-tag management
    CmdTagManagerUpstream#(2) pslside;
    CmdTagManagerClientPort#(Bit#(8)) tagmgr;

    { pslside, tagmgr } <- mkCmdTagManager(64);
    Vector#(2,CmdTagManagerClientPort#(Bit#(8))) client <- mkCmdPriorityArbiter(tagmgr);

    // Stream controllers
    GetS#(Bit#(512)) idata;
    StreamCtrl istream;
    { istream, idata } <- mkReadStream(
        StreamConfig {
            verbose: cfg.verbose,
            bufDepth: cfg.nReadBuf,
            nParallelTags: cfg.nReadTags },
        client[1]);

    let pwWEDReady <- mkPulseWire, pwStart <- mkPulseWire, pwTerm <- mkPulseWire;

    Wire#(AFUReturn) ret <- mkWire;

    Put#(Bit#(512)) odata;
    StreamCtrl ostream;
    { ostream, odata } <- mkWriteStream(
        StreamConfig {
            verbose: cfg.verbose,
            nParallelTags: cfg.nWriteTags,
            bufDepth: cfg.nWriteBuf
        },
        client[0]);

    //  Master state machine
    Reg#(Status) st <- mkReg(Resetting);
    Stmt masterstmt = seq
        st <= Resetting;

        st <= Ready;

        action
            await(pwWEDReady);
            $display($time," INFO: Starting transfer");
            $display($time,"      Src address: %016X",unpackle(wed.addrFrom).addr);
            $display($time,"      Dst address: %016X",unpackle(wed.addrTo).addr);
            $display($time,"      Size:        %016X",unpackle(wed.size));

            istream.start(unpackle(wed.addrFrom),unpackle(wed.size));
            ostream.start(unpackle(wed.addrTo),  unpackle(wed.size));
            st <= Waiting;
        endaction

        action
            st <= Running;
            await(pwStart);
        endaction


        action
            await(istream.done);
            $display($time," INFO: Read stream complete");
        endaction

        action
            await(ostream.done);
            $display($time," INFO: Write stream complete");
        endaction

        st <= Done;

        await(pwTerm);
        ret <= Done;
    endseq;

    let masterfsm <- mkFSM(masterstmt);

    rule getOutput;
        let d = idata.first;
        idata.deq;
        if (cfg.verboseData)
        begin
            $write($time," INFO: Received data ");
            for(Integer i=7;i>=0;i=i-1)
            begin
                $write("%016X ",endianSwap((Bit#(64))'(d[i*64+63:i*64])));
                if (i % 4 == 0)
                begin
                    $display;
                    if (i > 0)
                        $write("                                       ");
                end
            end
        end

        odata.put(d);
    endrule
    
    FIFOF#(MMIOResponse) mmResp <- mkGFIFOF1(True,False);

    interface ClientU command = pslside.command;
    interface AFUBufferInterface buffer = pslside.buffer;

    interface Server mmio;
        interface Get response = toGet(mmResp);

        interface Put request;
            method Action put(MMIORWRequest mm);
                case (mm) matches
                    tagged DWordWrite { index: 0, data: 0 }:
                        action
                            pwStart.send;
                            mmResp.enq(64'h0);
                        endaction
                    tagged DWordWrite { index: 0, data: 1 }:
                        action
                            pwTerm.send;
                            mmResp.enq(64'h0);
                        endaction
                    tagged DWordRead  { index: .i }:
                        mmResp.enq(case(i) matches
                            0: case(st) matches
                                    Resetting: 0;
                                    Ready: 1;
                                    Waiting: 2;
                                    Running: 3;
                                    Done: 4;
                                endcase
                            1: pack(unpackle(wed.size));
                            2: pack(unpackle(wed.addrFrom).addr);
                            3: pack(unpackle(wed.addrTo).addr);
                            default: 64'hdeadbeefbaadc0de;
                        endcase);
                    default:
                        mmResp.enq(64'h0);
                endcase
            endmethod
        endinterface
    endinterface

    method Action wedwrite(UInt#(6) i,Bit#(512) val) = asReg(wedSegs[i])._write(val);

    method Action rst = masterfsm.start;
    method Bool rdy = (st == Ready);

    method Action start(EAddress64 ea, UInt#(8) croom) = pwWEDReady.send;
    method ActionValue#(AFUReturn) retval = actionvalue return ret; endactionvalue;
endmodule


(*clock_prefix="ha_pclock"*)
module [Module] mkMemcopyStreamAFU(AFUHardware#(2));

    Config cfg = Config {
        verboseData: False,
        verbose: True,
        nReadTags: 32,
        nReadBuf: 32,
        nWriteBuf: 32,
        nWriteTags: 32};

    let { ctx, dut } <- runWithContext(
        hCons(MemSynthesisStrategy'(AlteraStratixV),hNil),
        mkMemcopyStreamBase(cfg)
    );

    let afu <- mkDedicatedAFU(dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(afuParityWrapper(afu));
    return hw;
endmodule


/** Narrowstream is permitted only two write tags, so should be quite a bit slower. */

(*clock_prefix="ha_pclock"*)
module [Module] mkMemcopyNarrowStreamAFU(AFUHardware#(2));

    Config cfg = Config {
        verbose: True,
        verboseData: False,
        nReadTags: 32,
        nReadBuf: 32,
        nWriteBuf: 32,
        nWriteTags: 2};

    let { ctx, dut } <- runWithContext(
        hCons(MemSynthesisStrategy'(AlteraStratixV),hNil),
        mkMemcopyStreamBase(cfg)
    );

    let afu <- mkDedicatedAFU(dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(afuParityWrapper(afu));
    return hw;
endmodule

endpackage
