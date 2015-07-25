package Test_HostToAFUStream;

import AFU::*;
import PSLTypes::*;
import HostToAFUStream::*;
import Assert::*;
import StmtFSM::*;
import Vector::*;
import PAClib::*;
import CAPIConnectable::*;
import ClientServer::*;
import DedicatedAFU::*;
import PSL::*;
import Clocks::*;
import AFUHardware::*;

import BDPIPipe::*;

import MMIO::*;

//function Action putCompletion(Put#(CacheResponse) ifc,RequestTag t) = action
//    let resp = CacheResponse { rtag: t, response: Done, rcredits: 0, rcachestate: 0, rcachepos: 0 };
//    ifc.put(resp);
//    $display($time," PSL=>AFU ",fshow(resp));
//endaction;
//
//function Action putBufWrite(Put#(BufferWrite) ifc,RequestTag t,UInt#(6) seg,Bit#(512) data) = action
//    let bw = BufferWrite { bwtag: t, bwad: seg, bwdata: data };
//    $display($time," PSL=>AFU ",fshow(bw));
//    ifc.put(bw);
//endaction;
//
//function Action putBufReadReq(Put#(BufferReadRequest) ifc,RequestTag t,UInt#(6) seg) = action
//    let br = BufferReadRequest { brtag: t, brad: seg };
//    $display($time," PSL=>AFU ",fshow(br));
//    ifc.put(br);
//endaction;


import Reserved::*;

typedef struct { UInt#(64) addr; } EAddress64LE deriving(Eq);

function Bit#(n) endianSwap(Bit#(n) i) provisos (Mul#(nbytes,8,n),Div#(n,8,nbytes),Log#(nbytes,k));
    Vector#(nbytes,Bit#(8)) t = toChunks(i);
    return pack(reverse(t));
endfunction

instance Bits#(EAddress64LE,64);
    function Bit#(64) pack(EAddress64LE i) = endianSwap(pack(i.addr));
    function EAddress64LE unpack(Bit#(64) b) = EAddress64LE { addr: unpack(endianSwap(b)) };
endinstance

typedef struct {
    EAddress64LE        eaSrc;
    EAddress64LE        size;

    ReservedZero#(128)  padA;

    ReservedZero#(256)  padB;



    ReservedZero#(512)  padC;
} HostToAFUWED deriving(Bits,Eq);


//module mkServerFromServerFL


//module mkServerFLFromServer#(Server#(req,res) s)(ServerFL#(req,res,lat));
//    let pwAck <- mkPulseWire, pwSend <- mkPulseWire;
//
//    interface Put request;
//        method Action put(req i);
//            s.request.put(i);
//            pwSend.send;
//        endmethod
//    endinterface
//
//    interface Get response;
//        method ActionValue#(res) get;
//            pwAck.send;
//            let o <- s.response.get;
//            return o;
//        endmethod
//    endinterface
//endmodule

import FIFO::*;

module mkAFU_HostToAFUStream(Tuple2#(DedicatedAFUNoParity#(HostToAFUWED,2),PipeOut#(UInt#(64))));
    //// WED reg
    SegReg#(HostToAFUWED,2,512) wed <- mkSegReg(unpack(?));



    //// Reset controller

    Stmt rststmt = seq
        noAction;
        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);



    //// Host -> AFU stream controller

    let streamctrl <- mkHostToAFUStream;

    FIFO#(void) ret <- mkFIFO1;

    Stmt ctlstmt = seq
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",wed.entire.eaSrc.addr);
            $display($time,"      Start address: %016X",wed.entire.size.addr);
            streamctrl.start(wed.entire.eaSrc.addr,wed.entire.size.addr);
        endaction
        await(streamctrl.done);
        $display($time," INFO: AFU Master FSM copy complete");
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);



    //// Stream consumer

    PipeOut#(Vector#(16,Bit#(64))) t <- mkFn_to_Pipe(unpack,streamctrl.istream);
    PipeOut#(Vector#(16,Bit#(64))) tr <- mkFn_to_Pipe(reverse,t);
    PipeOut#(Vector#(1,Bit#(64))) oFun <- mkFunnel(tr);

    PipeOut#(UInt#(64)) o <- mkFn_to_Pipe(compose(unpack,pack),oFun);


    //// Command interface checking

    ClientU#(CacheCommand,CacheResponse) cmd <- mkClientUFromClient(streamctrl.cmd);


    DedicatedAFUNoParity#(HostToAFUWED,2) afu = interface DedicatedAFUNoParity

    interface SegmentedReg wedreg = wed;

    interface ClientU command = cmd;

    interface AFUBufferInterface buffer;
        interface Put readdata = streamctrl.bw;
// not doing any writing
//        interface ServerFL writedata
    endinterface

// no MMIO support
    interface Server mmio;
        interface Get response;
            method ActionValue#(MMIOResponse) get if (False) = actionvalue return ?; endactionvalue;
        endinterface

        interface Put request;
            method Action put (MMIORWRequest i) = noAction;
        endinterface

    endinterface

    method Action parity_error_jobcontrol   = noAction;
    method Action parity_error_bufferread   = noAction;
    method Action parity_error_bufferwrite  = noAction;
    method Action parity_error_mmio         = noAction;
    method Action parity_error_response     = noAction;

    method Action start if (rstfsm.done);
        ctlfsm.start;
    endmethod

    method ActionValue#(AFUReturn) retval;
        ret.deq;
        return Done;
    endmethod

    interface FSM rst = rstfsm;

    method AFUAttributes attributes = AFUAttributes {
        brlat: 2,
        pargen: False,
        parcheck: False };

    endinterface;

    return tuple2(afu,o);

endmodule

(* clock_prefix="ha_pclock", no_default_reset *)


module mkSyn_HostToAFU(AFUHardware#(2));
    //// Reset generation

    let por <- mkPOR(1,reset_by noReset);
    let clk <- exposeCurrentClock;
    MakeResetIfc rstctrl <- mkResetSync(0,False,clk,reset_by noReset);

    let { dut, oPipe } <- mkAFU_HostToAFUStream(reset_by rstctrl.new_rst);
    let wrap <- mkDedicatedAFUNoParity(False,False,dut,reset_by rstctrl.new_rst);

    PipeOut#(UInt#(64)) oPipeR <- mkFn_to_Pipe(compose(unpack,compose(endianSwap,pack)),oPipe);

    let os <- mkBDPIOStreamPipe(bsv_makeOFileStreamP("host2afu.out"),oPipeR,reset_by rstctrl.new_rst);

//    AFUWithParity#(2) shim <- mkRegShim(dut, reset_by rstctrl.new_rst);

//    let { isRstCmd, rstafu } <- mkCheckAFUReset(wrap);

    rule doPOR if (por.isAsserted);
        rstctrl.assertReset;
    endrule

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap,reset_by rstctrl.new_rst);
    return hw;
endmodule


//module mkTB_StreamManager();
//
//    let dut <- mkHostToAFUStream;
//
//    function sendCompletion = putCompletion(dut.cmd.response);
//    function sendBufWrite   = putBufWrite(dut.bw);
//
////    function Action sendCompletion(RequestTag t) = action
////        let resp = CacheResponse { rtag: t, response: Done, rcredits: 0, rcachestate: 0, rcachepos: 0 };
////        dut.cmd.response.put(resp);
////        $display($time," PSL=>AFU ",fshow(resp));
////    endaction;
////
////    function Action sendBufWrite(RequestTag t,UInt#(6) seg,Bit#(512) data) = action
////        let bw = BufferWrite { bwtag: t, bwad: seg, bwdata: data };
////        $display($time," PSL=>AFU ",fshow(bw));
////        dut.bw.put(bw);
////    endaction;
//
//
//    // Put the AFU command on a wire for all to see
//    Wire#(CacheCommand) cmd <- mkWire;
//
//    rule getCommand;
//        let c <- dut.cmd.request.get;
//        $display($time," AFU=>PSL ",fshow(c));
//        cmd <= c;
//    endrule
//
//
//    // sends a reply after delay d, with delay wd between buf writes
//    function Stmt doRead(RequestTag t,Nat delay,Nat wd,Bit#(1024) data) = seq
//        // wait for read command
//        await(cmd.ctag == t && cmd.com == Read_cl_s);
//        repeat(delay) noAction;
//
//        par
//            sendBufWrite(t,0,data[1023:512]);
//            repeat(wd) noAction;
//        endpar
//
//        par
//            sendBufWrite(t,1,data[511:0]);
//            sendCompletion(t);
//        endpar
//    endseq;
//
//    // creates a cacheline where each 64b word has the same 32b prefix and the lower 32b word is a counter
//
//    function Bit#(1024) makePrefixedSequence(Bit#(32) pfx);
//        Vector#(16,Bit#(64)) v;
//        for(Integer i=0;i<16;i=i+1)
//            v[i] = { pfx, pack(fromInteger(i)) };
//        return pack(v);
//    endfunction
//
//    // PSL stimulus
//    Stmt psl = seq
//        par
//            seq
//                doRead(0,14,1,makePrefixedSequence(32'h00beef00));
//                doRead(0,14,2,makePrefixedSequence(32'h00beef01));
//                doRead(0,14,1,makePrefixedSequence(32'h00beef02));
//                doRead(0,14,2,makePrefixedSequence(32'h00beef03));
//            endseq
//
//            seq
//                doRead(1,14,4,makePrefixedSequence(32'hdeadb00f));
//                doRead(1,14,4,makePrefixedSequence(32'hdeadb00f));
////                doRead(1,4,1,makePrefixedSequence(32'hdeadb11f));
//            endseq
//
//            seq
//                doRead(2,14,6,makePrefixedSequence(32'hdeadb11f));
////                doRead(2,4,1,makePrefixedSequence(32'hdeadb11f));
//            endseq
//
//            seq
//                doRead(3,14,2,makePrefixedSequence(32'hbaadc0de));
////                doRead(3,4,1,makePrefixedSequence(32'hbaadc0de));
//            endseq
//        endpar
//
//        $display($time," INFO: PSL Stimulus complete");
//
//
//
//    endseq;
//
//    let psltb <- mkFSM(psl);
//
//    Reg#(UInt#(32)) oCtr <- mkReg(0);
//
//
//    Stmt stim = seq
//        noAction;
//
//        // read 8 cache lines
//        action
//            dut.start(64'h10080,64'h00480);
//            psltb.start;
//        endaction
//
//        action
//            await(dut.done);
//            $display($time,": DUT reports completed");
//        endaction
//
//        repeat(1000) noAction;
//
//        await(psltb.done);
//
//        dynamicAssert(oCtr == 8*16 ,"Invalid output count");
//    endseq;
//
//    mkAutoFSM(stim);
//
//    // sink output to stdout and count number of outputs
//    function Action show(Bit#(64) x) = action
//        $display($time,"  Stream output: %16X",x);
//        oCtr <= oCtr + 1;
//    endaction;
//
//    PipeOut#(Vector#(16,Bit#(64))) p <- mkFn_to_Pipe(toChunks,dut.istream);
//    PipeOut#(Vector#(1,Bit#(64))) f <- mkFunnel(p);
//    let u <- mkFn_to_Pipe(compose(unpack,flip(select)(0)),f);
//    mkSink_to_fa(show,u);
//endmodule

endpackage
