package Test_AFUToHostStream512;

import BuildVector::*;
import CAPIStream::*;

import Common::*;

import Assert::*;

import AFU::*;
import PSLTypes::*;
import CmdBuf::*;

import HList::*;

import FIFO::*;
import PAClib::*;
import Vector::*;
import StmtFSM::*;
import MMIO::*;
import DedicatedAFU::*;
import AFUHardware::*;
import Reserved::*;
import BLProgrammableLUT::*;
import BDPIPipe::*;

import FIFOF::*;
import SpecialFIFOs::*;

import Endianness::*;

import AFUToHostStream512::*;

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


module mkAFU_AFUToHostStream512#(PipeOut#(Bit#(32)) pi)(DedicatedAFU#(2));
    //// WED reg
    SegReg#(AFUToHostWED,2,512) wedreg <- mkSegReg(HostNative,unpack(?));
    AFUToHostWED wed = wedreg.entire;


	HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);


    
    // unfunnel 32b words into 512b half-lines; shift rightwards to put low-order elements at lower addresses
    PipeOut#(Bit#(512)) stream <- mkShiftRegUnfunnel(Right,pi);

    CacheCmdBuf#(1,2) cmdbuf <- mkCmdBuf(8);


    //// Host -> AFU stream controller
    AFUToHostStreamIfc#(Bit#(512)) afu2host <- mkAFUToHostStream512(syn,16,16,cmdbuf.client[0],EndianSwap);


	// Status controls & return values

	FIFOF#(void) startReq <- mkGFIFOF1(True,False);
	FIFOF#(void) finishReq <- mkGFIFOF1(True,False);

	Reg#(Bool) rstDone <- mkReg(False);
    Reg#(Bool) streamDone <- mkReg(False);
    Reg#(Bool) masterDone <- mkReg(False);

    FIFO#(AFUReturn) ret <- mkFIFO1;


    // unpack the WED
    EAddress64 size  = unpackle(wed.size);
    EAddress64 eaDst = unpackle(wed.eaDst);


    Stmt ctlstmt = seq
		// reset logic
        masterDone <= False;
        streamDone <= False;
		rstDone <= True;

		// await the start command
		startReq.deq;
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",size);
            $display($time,"      Start address: %016X",eaDst);
            afu2host.ctrl.start(eaDst.addr,size.addr);
        endaction

		while(!afu2host.ctrl.done)
			action
				stream.deq;
				afu2host.data.put(stream.first);
			endaction

        action
            await(afu2host.ctrl.done);
            $display($time," INFO: AFU Master FSM copy complete");
            streamDone <= True;
        endaction

		finishReq.deq;
        masterDone <= True;
        ret.enq(Done);
    endseq;

    let ctlfsm <- mkFSM(ctlstmt);

	let kickstart <- mkOnce(ctlfsm.start);
	rule alwaysStartMain;
		kickstart.start;
	endrule



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
                        5: finishReq.enq(?);
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

    method Action start = startReq.enq(?);

    method ActionValue#(AFUReturn) retval;
        ret.deq;
        return ret.first;
    endmethod

    method Bool rst = rstDone;

endmodule

import FIFOF::*;


(*clock_prefix="ha_pclock"*)
module mkSyn_AFUToHost512(AFUHardware#(2));
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

		// transfer size is 4096, should stop there due to DUT backpressure
		repeat(10000)
		action
			stimFifo.enq(pack(stimctr));
			stimctr <= stimctr+1;
		endaction

		repeat(10000) noAction;
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
    let dut <- mkAFU_AFUToHostStream512(iPipeT);
    let wrap <- mkDedicatedAFU(dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
