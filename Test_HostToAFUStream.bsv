package Test_HostToAFUStream;

import AFU::*;
import PSLTypes::*;
import HostToAFUStream::*;
import Assert::*;
import StmtFSM::*;
import Vector::*;
import PAClib::*;
import ClientServer::*;
import DedicatedAFU::*;
import Clocks::*;
import AFUHardware::*;

import CmdBuf::*;

import BDPIPipe::*;

import MMIO::*;

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



	//// Command buffer

	CacheCmdBuf#(1,2) cmdbuf <- mkCmdBuf(8);





    //// Host -> AFU stream controller

    let streamctrl <- mkHostToAFUStream(4,cmdbuf.client[0]);

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

	let cmdbufu <- mkClientUFromClient(cmdbuf.psl);

    //// Command interface checking

    DedicatedAFUNoParity#(HostToAFUWED,2) afu = interface DedicatedAFUNoParity
    
        interface SegmentedReg wedreg = wed;
    
        interface ClientU command = cmdbufu;
    
        interface AFUBufferInterface buffer;
            interface Put readdata = cmdbuf.pslbuff.readdata;
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

    endinterface;

    return tuple2(afu,o);

endmodule

(* clock_prefix="ha_pclock" *)


module mkSyn_HostToAFU(AFUHardware#(2));
    let { dut, oPipe } <- mkAFU_HostToAFUStream;
    let wrap <- mkDedicatedAFUNoParity(False,False,dut);

    PipeOut#(UInt#(64)) oPipeR <- mkFn_to_Pipe(compose(unpack,compose(endianSwap,pack)),oPipe);

	Reg#(UInt#(32)) p <- mkReg(0);

	rule showOutput;
		oPipeR.deq;
		$display($time,"Output [%08X]: %016X",p,oPipeR.first);
		p <= p+8;
	endrule

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
