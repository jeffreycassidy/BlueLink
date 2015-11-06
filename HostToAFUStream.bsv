package HostToAFUStream;

import Common::*;

import HList::*;
import DSPOps::*;

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
import RevertingVirtualReg::*;

import BLProgrammableLUT::*;

import Endianness::*;

import ReadBuf::*;

import CAPIStream::*;


// Export only the public items (there are helper classes that should not be visible)
export mkHostToAFUStream, CAPIStream::*;



/** (NON-EXPORTED) Read buffer status
 */

typedef union tagged {
	void 		Empty;                      // Available
	RequestTag	FetchIssued;                // The read command has been issued but is not completed yet
	void		Done;                       // Data is valid and has not been read
} ReadBufStatus deriving(Eq,FShow,Bits);


/** (NON-EXPORTED) Read buffer status reg
 */

interface ReadBufStatusIfc;
	method Action fetch(RequestTag t);      // Mark the buffer as reserved for an in-progress read
	method Action complete;                 // Read has completed
	method Action pop;                      // Data has been read and can be discarded

	(* always_ready *)
	method Bool empty;

	(* always_ready *)
	method Bool done;

	method RequestTag tag;
endinterface


/** (NON-EXPORTED) Read buffer status reg implementation: just a reg holding an enum with some accessor methods.
 */

module mkReadBufStatusReg(ReadBufStatusIfc);
	Reg#(ReadBufStatus) st <- mkReg(Empty);

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



/** Module to stream data from the host, using multiple parallel in-flight tags and a ring buffer.
 * 
 * *** REQUIRES COMPILATION WITH -aggressive-conditions ***
 * 
 * For argument descriptions, see AFUToHostStream
 *
 * Issues commands when able on the supplied CmdBufClientPort. For each tag, when granted:
 *
 *  Marks next buffer slot as FetchIssued and saves the tag ID
 *  On arrival of data, it is written to the buffer slot (hi/lo 512b)
 *  After completion is received, moves status to Done
 *  When pop is called, releases the buffer slot
 *
 * Simultaneously, when the current buffer slot becomes ready, the data can be read out, the buffer slot freed, and the read ptr
 * bumped upwards.
 *
 *
 * Some requests may take a very long time to complete because of page faults etc. Since this is a streaming interface, we'll just
 * have to wait for those to complete because there's no way to signal out-of-order results to the downstream logic.
 *
 * NOTE: Since these are consecutive, the page fault occurs on the first address of the page and subsequent requests are blocked
 * anyway.
 *
 * TODO: Deal correctly with PAGED response? (or is this unnecessary in Abort mode?)
 * TODO: Graceful reset logic
 */

module mkHostToAFUStream#(Integer bufsize,CmdBufClientPort#(2) cmdbuf,EndianPolicy endianPolicy)
    (Tuple2#(StreamControl,PipeOut#(Bit#(1024))))
    provisos (
		NumAlias#(na,6)         // Number of address bits
    );

    // Stream counter
    let { eaCounterControl, nextAddress } <- mkStreamCounter;

    // Output data
    FIFOF#(Bit#(1024)) oData <- mkPipelineFIFOF;

	// Ring buffer
	Reg#(UInt#(na)) 		rdPtr <- mkReg(0);									// next item to be streamed out
	Reg#(UInt#(na)) 		fetchPtr <- mkReg(0);								// next item to be requested

    // buffer status, 1 space per buffer slot
    staticAssert(bufsize <= valueOf(TExp#(na)),"Inadequate address bits specified for the chosen buffer size");

    HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);

	List#(ReadBufStatusIfc) 	bufItemStatus <- List::replicateM(bufsize,mkReadBufStatusReg);
    Vector#(2,Lookup#(na,Bit#(512))) rbufseg <- replicateM(mkZeroLatencyLookup(syn,bufsize));


    // *** REQUIRES -AGGRESSIVE-CONDITIONS  *** because of conditions on bufItemStatus[rdPtr]
    // If output is available (ie. current read buffer slot has valid data), enq it for output
	rule outputIfAvailable;
		// provide output, reversing 512b halflines to match Bluespec ordering convention
        // CAPI: little-endian (high index/MSB -> high address); BSV: big-endian (high index/MSB -> low address)
		let l <- rbufseg[1].lookup(rdPtr);
		let u <- rbufseg[0].lookup(rdPtr);

        case (endianPolicy) matches
            HostNative: oData.enq( { u,l });
            EndianSwap: oData.enq( endianSwap({ u,l }));
        endcase

		// mark used and bump read pointer
		bufItemStatus[rdPtr].pop;                       // implicit condition: can only pop if data valid
		rdPtr <= (rdPtr + 1) % fromInteger(bufsize);
	endrule

    Wire#(Tuple2#(UInt#(64),UInt#(64))) wStart <- mkWire;

    (* mutually_exclusive="outputIfAvailable,doStart" *)
    (* preempts = "doStart,fetchNext" *)

    rule doStart if (wStart matches { .ea0, .size });
        // reset host pointers
        eaCounterControl.start(ea0,size);

        // reset read buffer pointers
		rdPtr <= 0;
        fetchPtr <= 0;
    endrule

    // If there's space in the buffer, launch a read
    // Special case: initially fetchPtr == rdPtr, which would normally block this rule; but if slot 0 empty then start
	rule fetchNext if (fetchPtr != rdPtr || (rdPtr==0 && bufItemStatus[0].empty));
        let ea <- nextAddress.get;

		// increment host read pointer and bump fetch pointer
		fetchPtr <= (fetchPtr + 1) % fromInteger(bufsize);

		// issue read
		RequestTag tag <- cmdbuf.putcmd(                // implicit condition: able to issue command
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

    // Handle completion with done response
	rule completionIn;
		let resp <- cmdbuf.response.get;

		case (resp.response) matches
			Done:
				completeTag <= resp.rtag;
			default:
			begin
				$display($time,"ERROR: HostToAFUStream invalid response type received ",fshow(resp));
                completeTag <= resp.rtag;
			end
		endcase
	endrule

	rule completionFail if (!pwCompleteAck);
		$display($time,": ERROR - No one ack'd the completion for tag ",fshow(completeTag));
	endrule

    // The two repeated rules below are split to avoid the need for the -aggressive-conditions argument
    // otherwise the rule would carry implicit conditions that ALL buffer items must be ready
    // fire_when_enabled is specified because there is no fall-through mechanism if the data or completion isn't dealt with here

    List#(RWire#(RequestTag)) tags <- List::replicateM(bufsize,mkRWire);

    function Maybe#(t) doWGet(RWire#(t) rw) = rw.wget;


	for(Integer i=0;i<bufsize;i=i+1)
    begin
        (* fire_when_enabled *)
		rule completion if (completeTag == bufItemStatus[i].tag);
			bufItemStatus[i].complete;
			pwCompleteAck.send;
    	endrule

        // mark buffer ready
        rule bufReady;
            tags[i].wset(bufItemStatus[i].tag);
        endrule
	end

    FIFO#(Tuple3#(UInt#(6),UInt#(na),Bit#(512))) bwReg <- mkPipelineFIFO;

    // handle buffer writes
    (* fire_when_enabled *) 
    rule bufWrite;

        let rd = cmdbuf.buffer.readdata;

        let addr = rd.bwad;
        let data = rd.bwdata;
        let tag  = rd.bwtag;

//        $display($time,fshow(cmdbuf.buffer.readdata));

        Maybe#(UInt#(na)) idx = tagged Invalid;
        for (Integer i=0;i<List::length(tags);i=i+1)
            if (tags[i].wget matches tagged Valid .t &&& t == tag)
                idx = tagged Valid fromInteger(i);

        if (idx matches tagged Valid .i)
            bwReg.enq(tuple3(addr,i,data));
//        else
//            dynamicAssert(False,"Received data for tag not currently in use");
    endrule

    // sink buffer writes requests to the read buffer
    rule bufWriteFinalize;
        let { addr, i, data } = bwReg.first;
        rbufseg[addr].write(i, data);
        bwReg.deq;
    endrule

    return tuple2(
        interface StreamControl;
            method Action start(UInt#(64) ea0,UInt#(64) size) if (eaCounterControl.done);
                wStart <= tuple2(ea0,size);
            endmethod

            method Bool done = eaCounterControl.done && !oData.notEmpty && rdPtr == fetchPtr;
        endinterface,

        f_FIFOF_to_PipeOut(oData)
    );
endmodule

endpackage
