package Test_AFUToHostStream;

import BuildVector::*;

import Common::*;

import Assert::*;

import AFU::*;
import PSLTypes::*;
import CmdBuf::*;

import FIFO::*;
import PAClib::*;
import Vector::*;
import StmtFSM::*;
import MMIO::*;
import DedicatedAFU::*;
import AFUHardware::*;
import Reserved::*;
import BDPIPipe::*;

import AFUToHostStream::*;

import ShiftRegUnfunnel::*;

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
    EAddress64LE        eaDst;
    EAddress64LE        size;

    ReservedZero#(128)  padA;

    ReservedZero#(256)  padB;



    ReservedZero#(512)  padC;
} AFUToHostWED deriving(Bits,Eq);


module mkAFU_AFUToHostStream#(PipeOut#(Bit#(32)) pi)(DedicatedAFUNoParity#(AFUToHostWED,2));
    //// WED reg
    SegReg#(AFUToHostWED,2,512) wed <- mkSegReg(unpack(?));



    //// Reset controller

    Stmt rststmt = seq
        noAction;
        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);



    PipeOut#(Bit#(1024)) stream <- mkShiftRegUnfunnel(Left,pi);

    CacheCmdBuf#(1,2) cmdbuf <- mkCmdBuf(4);


    //// Host -> AFU stream controller

    let pwStart <- mkPulseWire;
    let pwFinish <- mkPulseWire;

    let streamctrl <- mkAFUToHostStream(cmdbuf.client[0],stream);

    FIFO#(void) ret <- mkFIFO1;

    Reg#(Bool) streamDone <- mkReg(False);
    Reg#(Bool) masterDone <- mkReg(False);

    Stmt ctlstmt = seq
        masterDone <= False;
        streamDone <= False;
        await(pwStart);
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",wed.entire.size.addr);
            $display($time,"      Start address: %016X",wed.entire.eaDst.addr);
            streamctrl.start(wed.entire.eaDst.addr,wed.entire.size.addr);
        endaction
        action
            await(streamctrl.done);
            $display($time," INFO: AFU Master FSM copy complete");
            streamDone <= True;
        endaction
        await(pwFinish);
        masterDone <= True;
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);



    //// Command interface checking

    ClientU#(CacheCommand,CacheResponse) cmd <- mkClientUFromClient(cmdbuf.psl);

    FIFO#(MMIOResponse) mmResp <- mkFIFO1;

    interface SegmentedReg wedreg = wed;

    interface ClientU command = cmd;

    interface AFUBufferInterface buffer = cmdbuf.pslbuff;

    interface Server mmio;
        interface Get response = toGet(mmResp);

        interface Put request;
            method Action put (MMIORWRequest i);
                if (i matches tagged DWordWrite { index: .dwi, data: .dwd })
                begin
                    case (dwi) matches
                        4: pwStart.send;
                        5: pwFinish.send;
                        default: noAction;
                    endcase

                    mmResp.enq(WriteAck);
                end
                else if (i matches tagged DWordRead { index: .dwi })
                    case (dwi) matches
                        0:          mmResp.enq(tagged DWordData 64'h0123456700f00d00);
                        1:          mmResp.enq(tagged DWordData pack(wed.entire.eaDst.addr));
                        2:          mmResp.enq(tagged DWordData pack(wed.entire.size.addr));
                        3:          mmResp.enq(tagged DWordData (streamDone ? 64'h1111111111111111 : 64'h0));
                        4:          mmResp.enq(tagged DWordData (masterDone ? 64'hf00ff00ff00ff00f : 64'h1));
                        default:    mmResp.enq(tagged DWordData 0);
                    endcase
                else
                    mmResp.enq(WriteAck);           // just ack word read/write
                        
                
            endmethod
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

endmodule

import FIFOF::*;


(*clock_prefix="ha_pclock"*)
module mkSyn_AFUToHost(AFUHardware#(2));
    // stimulus generation
	Reg#(UInt#(32)) ctr <- mkReg(0);
	Reg#(UInt#(32)) stimctr <- mkReg(0);
	FIFOF#(Bit#(32)) stimFifo <- mkFIFOF;

	PipeOut#(Bit#(32)) iPipe =	f_FIFOF_to_PipeOut(stimFifo);

	Stmt stim = seq
        par
            stimFifo.clear;
            stimctr <= 0;
            ctr <= 0;
        endpar

		repeat(512) action
			stimFifo.enq(pack(stimctr));
			stimctr <= stimctr+1;
		endaction
	endseq;

    let stimfsm <- mkFSM(stim);

    rule alwaysStart;
        stimfsm.start;
    endrule

	function Action tapDisplay(Bit#(32) i) = action
		$display($time," Input %d: %08X",ctr,i);
		ctr <= ctr+1;
	endaction;

	PipeOut#(Bit#(32)) iPipeT <- mkTap(tapDisplay,iPipe);

    // AFU instantiation & wrapping
    let dut <- mkAFU_AFUToHostStream(iPipeT);
    let wrap <- mkDedicatedAFUNoParity(False,False,dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
