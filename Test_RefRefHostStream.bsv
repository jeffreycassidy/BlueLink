package Test_RefRefHostStream;

import AFU::*;
import PSLTypes::*;
import HostToAFUStream::*;
import AFUToHostStream::*;
import StmtFSM::*;
import Vector::*;
import PAClib::*;
import ClientServer::*;
import DedicatedAFU::*;
import Clocks::*;
import AFUHardware::*;
import WrappedRefRef::*;
import FIFO::*;
import CmdBuf::*;
import Reserved::*;
import ModuleContext::*;

import MMIO::*;

typedef struct {
   //sum 384 bits
   EAddress64LE        eaInit;
   EAddress64LE        eaSrc;
   EAddress64LE        eaDest;
   EAddress64LE        init_size;
   EAddress64LE        src_size;
   EAddress64LE        dest_size;

   ReservedZero#(128)  padA;

   ReservedZero#(512)  padB;
} RefRefHostWED deriving(Bits,Eq);


/**
 * Module that controls the stream from host -> afu -> refref -> afu -> host
 * 1024bit cachelines are funneled into 64bit parts
 */
module [Module] mkAFU_RefRefHostStream(DedicatedAFUNoParity#(RefRefHostWED,2));
	//// WED reg
	SegReg#(RefRefHostWED,2,512) wed <- mkSegReg(unpack(?));


    //// Reset controller

    Stmt rststmt = seq
        noAction;
        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);

	//// Testbench module
	
	function Action display_in_vec(Bit#(64) vector);
		$display($time," Input vec: %016X",vector);
	endfunction

	function Action display_vec(Bit#(64) vector);
		$display($time," Output vec: %016X",vector);
	endfunction

	//input stream
	Wire#(Bit#(64)) refref_in_wire <- mkWire;
	let refref_tap <- mkSource_from_constant(refref_in_wire);
	let refref_in <- mkTap(display_in_vec, refref_tap);
	let refref <- mkWrappedRefRef(refref_in);
	
	//output stream, goes directly to afutohost stream
	let tapped_ostream <- mkTap(display_vec, refref.ostream);
	PipeOut#(Vector#(1,Bit#(64))) output_funnel <- mkFn_to_Pipe(replicate, tapped_ostream);
	PipeOut#(Vector#(16,Bit#(64))) refref_vec <- mkUnfunnel(False, output_funnel);
	PipeOut#(Vector#(128,Bit#(8))) refref_byte_vec <- mkFn_to_Pipe(compose(unpack,pack),refref_vec);
	PipeOut#(Bit#(1024)) refref_byte_reversed <- mkFn_to_Pipe(compose(pack,reverse),refref_byte_vec);

	
	//// Command buffer

	CacheCmdBuf#(2,2) cmdbuf <- mkCmdBuf(8);

	
	//// Host -> AFU and AFU -> Host stream controller
	
    let istreamctrl <- mkHostToAFUStream(4,cmdbuf.client[0]);
	let ostreamctrl <- mkAFUToHostStream(cmdbuf.client[1], refref_byte_reversed);
		
	let pwStart <- mkPulseWire;
	let pwFinish <- mkPulseWire;
	
	FIFO#(void) ret <- mkFIFO1;
	
	Reg#(Bool) streamStarted <- mkReg(False);
	Reg#(Bool) initStreamDone <- mkReg(False);
    Reg#(Bool) streamDone <- mkReg(False);
	Reg#(Bool) masterDone <- mkReg(False);
	Stmt ctlstmt = seq
					   masterDone <= False;
					   streamDone <= False;
					   initStreamDone <= False;	
					   await(pwStart);
					   action
						   $display($time," INFO: AFU MASTER FSM STARTING");
						   $display($time," Initializing constants...");
						   $display($time,"      Size:       %016X",wed.entire.init_size.addr);
						   $display($time,"      Start addr: %016X",wed.entire.eaInit.addr);
						   istreamctrl.start(wed.entire.eaInit.addr,wed.entire.init_size.addr);
						   streamStarted <= True;
						   refref.constants.load(fromInteger(16));
					   endaction

					   await(istreamctrl.done);
					  
					   initStreamDone <= True;
					   $display($time," Constants read");
					   repeat(20) noAction;
					   action
						   $display($time," Starting input stream...");
						   $display($time,"      Size:       %016X",wed.entire.src_size.addr);
						   $display($time,"      Start addr: %016X",wed.entire.eaSrc.addr);
						   istreamctrl.start(wed.entire.eaSrc.addr,wed.entire.src_size.addr);
						   
						   $display($time," Starting output stream...");
						   $display($time,"      Size:       %016X",wed.entire.dest_size.addr);
						   $display($time,"      Start addr: %016X",wed.entire.eaDest.addr);
						   ostreamctrl.start(wed.entire.eaDest.addr,wed.entire.dest_size.addr);
					   endaction
					   await(istreamctrl.done);
					   $display($time," Finished input stream");
					   action
						   await(ostreamctrl.done);
						   $display($time," Finished output stream");
						   streamStarted <= False;
						   streamDone <= True;
					   endaction
					   await(pwFinish);
					   $display($time," INFO: AFU MASTER FSM FINISHED");
					   masterDone <= True;
					   ret.enq(?);
				   endseq;
	
	let ctlfsm <- mkFSMWithPred(ctlstmt, rstfsm.done);

	//input arrives with the bytes in reverse order
	function Vector#(16,Bit#(64)) reorder_cacheline(Bit#(1024) cacheline);
		Vector#(128,Bit#(8)) bytevec_reversed = reverse(unpack(cacheline));
		return unpack(pack(bytevec_reversed));
	endfunction
    
	let cacheline <- mkFn_to_Pipe(reorder_cacheline, istreamctrl.istream);
	PipeOut#(Vector#(1,Bit#(64))) cacheline_funnel <- mkFunnel(cacheline);	

	// forking the input to either initialize refref's lut constants or stream through refref module
	rule put_const if (streamStarted && !initStreamDone);
		refref.constants.put(cacheline_funnel.first[0]);
		cacheline_funnel.deq;
	endrule
	
	rule put_inputstream if (streamStarted && initStreamDone);
		refref_in_wire <= cacheline_funnel.first[0];
		cacheline_funnel.deq;
	endrule
	
	
	let cmdbufu <- mkClientUFromClient(cmdbuf.psl);

	FIFO#(MMIOResponse) mmResp <- mkFIFO1;
	
    //// Command interface checking
	interface SegmentedReg wedreg = wed;
    
	interface ClientU command = cmdbufu;
    
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
						1:          mmResp.enq(tagged DWordData pack(wed.entire.eaDest.addr));
						2:          mmResp.enq(tagged DWordData pack(wed.entire.dest_size.addr));
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


(*clock_prefix="ha_pclock"*)
module [Module] mkSyn_RefRefHost(AFUHardware#(2));	
	
	let dut <- mkAFU_RefRefHostStream();	
	let wrap <- mkDedicatedAFUNoParity(False,False,dut);	
    
	AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
	return hw;
endmodule
endpackage
