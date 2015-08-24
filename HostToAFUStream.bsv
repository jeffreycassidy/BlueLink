package HostToAFUStream;

import Common::*;

import Assert::*;
import AFU::*;
import PSLTypes::*;
import FIFO::*;
import PAClib::*;
import Vector::*;

import CmdBuf::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import BLProgrammableLUT::*;

import ReadBuf::*;


/** Testbench to stream data from the host, using multiple parallel in-flight tags.
 * 
 * Out-of-order completions are handled by the read buffer.
 *
 * For each tag:
 *
 *  When available, acquires a tag from the TagManager
 *  Marks tag as incomplete and issues read request using the tag
 *  Enqueues the tag index in the requestTagFIFO (requests are to ordered addresses, so tags in the FIFO are ordered too)
 *  On read completion, mark tag complete
 *
 * Continuously check whether the oldest request has been serviced yet. If so, free up the buffer slot and pass the data out.
 *
 * Some requests may take a very long time to complete because of page faults etc. Since this is a streaming interface, we'll just
 * have to wait for those to complete because there's no way to signal out-of-order results to the downstream logic.
 *
 *          Rationale: if last tag takes a very long time to complete, we stop issuing new requests even though previous tags
 *                      have completed. They are blocked by the buffer not draining.
 *
 */

interface HostToAFUStream;
    // Start the stream
    method Action   start(UInt#(64) ea,UInt#(64) size);
    method Bool     done;

    // PipeOut with data
    interface PipeOut#(Bit#(1024)) istream;
endinterface



/** Provides a PipeOut#(Bit#(1024)) stream from the host memory.
 *
 * The user starts the transfer by providing an address and a size, then is able to pull (size) bytes from the host.
 *
 * Currently requires cache-aligned ea and size. 
 */

	typedef union tagged {
		void 		Empty;
		RequestTag	FetchIssued;
		void		Done;
	} BufStatus deriving(Eq,FShow,Bits);

interface BufStatusIfc;
	method Action fetch(RequestTag t);
	method Action complete;
	method Action pop;

	(* always_ready *)
	method Bool empty;

	(* always_ready *)
	method Bool done;

	method RequestTag tag;
endinterface


module mkBufStatusReg(BufStatusIfc);
	Reg#(BufStatus) st <- mkReg(Empty);

	Wire#(RequestTag) fetchTag <- mkWire;
	let pwPop <- mkPulseWire, pwComplete <- mkPulseWire;

	(* mutually_exclusive="startFetch,doPop,doComplete" *)

	rule startFetch;
		st <= tagged FetchIssued fetchTag;
	endrule

	rule doPop if (pwPop);
		st <= Empty;
	endrule

	rule doComplete if (pwComplete);
		st <= Done;
	endrule


	// send the request
	method Action		fetch(RequestTag tag);
		dynamicAssert(st == Empty, "Fetch issued with non-empty buffer slot");
		fetchTag <= tag;
	endmethod

	// handle completion
	method Action		complete;
		dynamicAssert(st matches tagged FetchIssued .* ? True : False , "Completion without fetch in progress");
		pwComplete.send;
	endmethod

	// pop the buffered value
	method Action		pop if (st == Done);
		pwPop.send;
	endmethod


	method Bool			empty = st == Empty;
	method Bool			done = st == Done;
	method RequestTag	tag if (st matches tagged FetchIssued .ft) = ft;
endmodule



module mkHostToAFUStream#(Integer bufsize,CmdBufClientPort#(2) cmdbuf)(HostToAFUStream)
    provisos (
		NumAlias#(na,4),
        NumAlias#(nt,4));

	// basic parameters
    Integer stepBytes=128;
    Integer alignBytes=stepBytes;

	// control regs
    Reg#(UInt#(64)) eaStart   <- mkReg(0);
    Reg#(UInt#(64)) ea        <- mkReg(0);
    Reg#(UInt#(64)) eaEnd     <- mkReg(0);

    // Output data
    FIFOF#(Bit#(1024)) oData <- mkPipelineFIFOF;


	// Ring buffer
	Reg#(UInt#(na)) 		rdPtr <- mkReg(0);									// next item to be streamed out
	Reg#(UInt#(na)) 		fetchPtr <- mkReg(0);								// next item to be requested

	List#(BufStatusIfc) 	bufItemStatus <- List::replicateM(bufsize,mkBufStatusReg);	// buffer status, per buffer slot

    Vector#(2,Lookup#(na,Bit#(512))) rbufseg <- replicateM(mkZeroLatencyLookup(bufsize));

	rule outputIfAvailable;
		// provide output
		let l <- rbufseg[1].lookup(rdPtr);
		let u <- rbufseg[0].lookup(rdPtr);
		oData.enq( { u, l });

		// mark used and bump read pointer
		bufItemStatus[rdPtr].pop;
		rdPtr <= (rdPtr + 1) % fromInteger(bufsize);
	endrule


	rule fetchNext if (ea != eaEnd && (fetchPtr != rdPtr || (rdPtr==0 && bufItemStatus[0].empty)));
		// increment host read pointer
        ea <= ea + fromInteger(stepBytes);

		// bump fetch pointer
		fetchPtr <= (fetchPtr + 1) % fromInteger(bufsize);

		// issue read
		RequestTag tag <- cmdbuf.putcmd(
			CmdWithoutTag {
			 	com: Read_cl_s,
				cabt: Abort,
				cea: EAddress64 { addr: ea },
				csize: fromInteger(stepBytes) });

		// save request tag
		bufItemStatus[fetchPtr].fetch(tag);
	endrule

	Wire#(RequestTag) completeTag <- mkWire;
	let pwCompleteAck <- mkPulseWireOR;

	rule completion;
		let resp <- cmdbuf.response.get;

		case (resp.response) matches
			Done:
				completeTag <= resp.rtag;
			default:
			begin
				$display($time,"ERROR: Invalid response type received ",fshow(resp));
				dynamicAssert(False,"Invalid response type received");
			end
		endcase
	endrule

	rule completionFail if (!pwCompleteAck);
		$display($time,": ERROR - No one ack'd the completion for tag ",fshow(completeTag));
	endrule

	for(Integer i=0;i<bufsize;i=i+1)
	begin
		rule completion if (completeTag == bufItemStatus[i].tag);
			bufItemStatus[i].complete;
			pwCompleteAck.send;
    
//    		// find buffer slot corresponding to this request
//    		Maybe#(Integer) idxm = List::find(
//    			compose( \== (tagged FetchIssued resp.rtag), List::select(List::map(readReg,bufItemStatus))),
//    			List::upto(0,bufsize-1));
//    
//    		dynamicAssert(isValid(idxm), "Completion returned but no matching request found in bufItemStatus");
//    		UInt#(na) idx = fromInteger(idxm.Valid);
    	endrule

		rule receiveData if (cmdbuf.buffer.readdata.bwtag == bufItemStatus[i].tag);
			rbufseg[cmdbuf.buffer.readdata.bwad].write(fromInteger(i),cmdbuf.buffer.readdata.bwdata);
		endrule

	end




    method Action start(UInt#(64) ea0,UInt#(64) size);
        eaStart <= ea0;
        ea <= ea0;
        eaEnd <= ea0+size;

		rdPtr <= 0;
		fetchPtr <= 0;

        dynamicAssert(ea0 % fromInteger(alignBytes) == 0,   "Effective address is not properly aligned");
        dynamicAssert(size % fromInteger(alignBytes) == 0,  "Transfer size is not properly aligned");
    endmethod

    method Bool done = ea==eaEnd && !oData.notEmpty && rdPtr == fetchPtr;

	interface PipeOut istream = f_FIFOF_to_PipeOut(oData);
endmodule

endpackage
