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

import Endianness::*;

import AFUToHostStream::*;

import ShiftRegUnfunnel::*;

/** Define WED for HostNative (little-endian) cache line ordering; requires endian swap of each element but leaves struct elements
 * in forward order.
 *
 * Corresponding C/C++ struct is 
 *
 * struct WED {
 *      void*    p;
 *      uint64_t size;
 *      uint64_t pad[14];
 * };
 */

typedef struct {
    LittleEndian#(EAddress64)        eaDst;
    LittleEndian#(EAddress64)        size;

    ReservedZero#(128)  padA;

    ReservedZero#(256)  padB;

    ReservedZero#(512)  padC;
} AFUToHostWED deriving(Bits,Eq);


module mkAFU_AFUToHostStream#(PipeOut#(Bit#(32)) pi)(DedicatedAFUNoParity#(2));
    //// WED reg
    SegReg#(AFUToHostWED,2,512) wedreg <- mkSegReg(HostNative,unpack(?));
    AFUToHostWED wed = wedreg.entire;


    //// Reset controller
    Stmt rststmt = seq
        noAction;
        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);


    
    // unfunnel 32b words into 1024b cache lines; shift rightwards to put low-order elements at lower addresses
    PipeOut#(Bit#(1024)) stream <- mkShiftRegUnfunnel(Right,pi);

    CacheCmdBuf#(1,2) cmdbuf <- mkCmdBuf(4);


    //// Host -> AFU stream controller

    let pwStart <- mkPulseWire;
    let pwFinish <- mkPulseWire;

    let streamctrl <- mkAFUToHostStream(16,cmdbuf.client[0],EndianSwap,stream);

    FIFO#(void) ret <- mkFIFO1;

    Reg#(Bool) streamDone <- mkReg(False);
    Reg#(Bool) masterDone <- mkReg(False);

    // unpack the WED
    EAddress64 size  = unpackle(wed.size);
    EAddress64 eaDst = unpackle(wed.eaDst);

    Stmt ctlstmt = seq
        masterDone <= False;
        streamDone <= False;
        await(pwStart);
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",size);
            $display($time,"      Start address: %016X",eaDst);
            streamctrl.start(eaDst.addr,size.addr);
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

    interface Vector wedwrite = map(regToWriteOnly,wedreg.seg);

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
                        1:          mmResp.enq(tagged DWordData pack(eaDst.addr));
                        2:          mmResp.enq(tagged DWordData pack(size.addr));
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
