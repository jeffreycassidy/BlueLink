package AFUToHostStream512;

import Common::*;
import DReg::*;
import ClientServerU::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Assert::*;
import PAClib::*;
import PSLTypes::*;
import Connectable::*;

import CmdBuf::*;
import WriteBuf::*;

import Cntrs::*;

import HList::*;
import BLProgrammableLUT::*;

import CAPIStream::*;

import Endianness::*;

/** Module to sink a stream to host memory, using multiple parallel in-flight tags and a ring buffer.
 * 
 * Issues commands when able on the supplied CmdBufClientPort.
 *
 * Arguments
 *      cmdbuf          A command buffer port to accept the issued commands
 *      endianPolicy    Specification for how to handle the incoming 512b cache line
 *                          HostNative: place little-endian 512b word directly in memory (MSByte pi[511:0] -> ea + 0x3f)
 *                          EndianSwap: byte-reverse the line (MSByte pi[511:0] -> ea + 0x00)
 *      pi              The incoming pipe to send to host
 *
 * In HostNative (LE) mode, vectors should have the high index at right
 * For EndianSwap (BE) mode, vectors should position the high index at left as is standard in Bluespec pack()
 *
 * The user starts the transfer by providing an address and a size, then is able to push (size) bytes to the host in 512b chunks.
 *
 * Currently requires cache-aligned ea and size. 
 *
 * TODO: Graceful reset logic
 */

interface AFUToHostStreamIfc#(type addrT,type dataT);
	interface StreamControl#(addrT)	ctrl;
	interface Put#(dataT) 			data;
endinterface

module mkAFUToHostStream512#(synT syn,Integer nTags,Integer bufsize,CmdBufClientPort#(2) cmdbuf,EndianPolicy endianPolicy)
	(AFUToHostStreamIfc#(UInt#(64),dataT))
    provisos (
		Bits#(dataT,512),
		NumAlias#(512,wTransfer),
		NumAlias#( 64,transferBytes),
		NumAlias#(nbTransferCount,20),
        Gettable#(synT,MemSynthesisStrategy)
		);

	Bool verbose=True;

	Wire#(Tuple2#(UInt#(64),UInt#(64))) wStart <- mkWire;

	// manage AFU input side (half-lines) and PSL effective address size (EA bytes)
	StreamAddressGen#(UInt#(nbTransferCount))	inputIdx 	<- mkStreamAddressGen(1);
	StreamAddressGen#(UInt#(64))				eaRequest 	<- mkStreamAddressGen(cacheLineBytes);



	// tag info: status (Done/RequestIssued/Flushed/Draining), buffer slot, cache line index
	List#(TagStatusIfc) 				tagStatus 				<- List::replicateM(nTags,mkTagStatus);
	MultiReadLookup#(8,UInt#(8)) 		tagBufferSlotLUT		<- mkMultiReadZeroLatencyLookup(syn,2,nTags);
	Lookup#(8,UInt#(nbTransferCount))	tagCacheLineIndexLUT 	<- mkZeroLatencyLookup(syn,nTags);



	// buffer status indication (full -> in use)
	// unguarded to save a bit of timing on the implicit conditions for putting data
	List#(FIFOF#(void)) bufferUsed 	<- List::replicateM(bufsize,mkGFIFOF1(True,False));

    Reg#(Maybe#(RequestTag)) pwBufFree <- mkDReg(tagged Invalid);

    (* fire_when_enabled *)
	rule freeBuf if (pwBufFree matches tagged Valid .v);
		bufferUsed[v].deq;
	endrule



	// buffer data (transfersPerCacheLine elements per slot)
	Lookup#(8,Bit#(512))	dataBuffer 		<- mkZeroLatencyLookup(syn,bufsize*transfersPerCacheLine);

	FIFOF#(UInt#(8))		txBufferSlot <- mkGSizedFIFOF(True,False,bufsize);
		// order of values to be transmitted

	Reg#(Maybe#(Tuple2#(UInt#(8),UInt#(6)))) nextBufferSlot <- mkReg(tagged Invalid);
		// holds (index, chunk) for destination of next input write if available


	rule doStart if (wStart matches { .ea0, .size });
		$display($time," INFO: Started AFUToHostStream512 with ea=%X size=%X",ea0,size);
		dynamicAssert(ea0  % fromInteger(cacheLineBytes)==0,"Badly aligned start address");
		dynamicAssert(size % fromInteger(cacheLineBytes)==0,"Badly aligned transfer address");

		// set up PSL-side requests
		eaRequest.ctrl.start(ea0,size);


		// set up AFU-side counters (half-lines)
		inputIdx.ctrl.start(0,truncate(size >> log2(transferBytes)));

		// ditch existing transfers
		for(Integer i=0;i<nTags;i=i+1)
			tagStatus[i].drain;
	endrule



	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// Input buffer

	// inspect the bufferUsed FIFOs to see which if any is currently free
	function Maybe#(Tuple2#(UInt#(8),UInt#(6))) nextFreeBufferSlot;
		Integer i;
		for(i=0;i<bufsize && bufferUsed[i].notEmpty;i=i+1) begin end		// scan upwards while buffers full

		// !notEmpty -> Empty -> available
		return i < bufsize ? tagged Valid tuple2(fromInteger(i),0): tagged Invalid;
	endfunction


	function UInt#(8) bufferAddressFromSlotChunk(UInt#(8) slot,UInt#(6) chunk) =
		(slot << log2(transfersPerCacheLine)) | extend(chunk);

	rule awaitFreeSlot if (!isValid(nextBufferSlot));
		nextBufferSlot <= nextFreeBufferSlot;
	endrule







	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// PSL Buffer read interface

	Reg#(Maybe#(UInt#(8))) bufReadAddr <- mkDReg(tagged Invalid);
	Reg#(Maybe#(Bit#(512))) oData <- mkDReg(tagged Invalid);

	rule handleBufferReadRequest1
			if (cmdbuf.buffer.writedata.request matches tagged BufferReadRequest { brad: .brad, brtag: .brtag});

		if (verbose)
			$display($time," INFO: Received a read request for tag=%d brad=%d",brtag,brad);

		dynamicAssert(brad < fromInteger(transfersPerCacheLine),
			"Received a buffer read request with invalid brad >= transfersPerCacheLine");

		// get the buffer slot for this tag, form data buffer address
		let bufSlotIdx <- tagBufferSlotLUT.lookup[0](brtag);
		bufReadAddr <= tagged Valid bufferAddressFromSlotChunk(bufSlotIdx,brad);
	endrule

	rule handleBufferReadRequest2 if (bufReadAddr matches tagged Valid .addr);
		let d <- dataBuffer.lookup(addr);
		oData <= tagged Valid d;
	endrule

	rule handleBufferReadRequestOut if (oData matches tagged Valid .v);
		cmdbuf.buffer.writedata.response.put(
			endianPolicy == HostNative ? v : endianSwap(v));
	endrule



	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// Command interface

	// send a write command when a tag is available and there is data to be written

	(* preempts = "doStart,doWriteCommand" *)
    rule doWriteCommand if (!eaRequest.ctrl.done);
		// get effective address and bump write pointer
		let ea <- eaRequest.next.get;

        // checkout tag and send command
        let cmd = CmdWithoutTag {
            com: Write_mi,
            cabt: Strict,
            cea: EAddress64 { addr: ea },
            csize: fromInteger(cacheLineBytes) };

        let tag <- cmdbuf.putcmd(Any,cmd);          // implicit condition: able to put a command

		tagStatus[tag].issue;

		// get next buffer slot to be written
		txBufferSlot.deq;											// implicit condition: completed buffer slot waiting for write
		tagBufferSlotLUT.write(tag,txBufferSlot.first);				// Save the buffer slot for this tag
//		tagCacheLineIndexLUT.write(tag,ea);							// Save the cache line index (in case of retry)
		messageM("WARNING - Paged retry is not functional in AFUToHostStream512");

		if (verbose)
			$display($time," INFO: Issued a write command using tag %d (buffer slot %d)",tag,txBufferSlot.first);
    endrule



	// handle responses
    rule handleResponseTagStatus;
        let resp <- cmdbuf.response.get;
		let tag = resp.rtag;

		// figure out which buffer this tag uses, release if appropriate
		// bufferUsed FIFO may throw unguarded deq warning if already freed (eg. by an abort)
		let bufSlotIdx <- tagBufferSlotLUT.lookup[1](tag);

        case (resp.response) matches
            Done:
				action
					tagStatus[tag].complete;
					pwBufFree <= tagged Valid bufSlotIdx;
					if (verbose)
						$display($time," INFO: Completion for tag %X",tag);
				endaction

   	        Paged:
				action
					tagStatus[tag].flush;
                	$display($time," INFO: Paged response for tag %X",tag);
				endaction

			Flushed:
				action
					tagStatus[tag].flush;
					$display($time," INFO: Flushed response for tag %X",tag);
				endaction
           
            default:
                action										// fault response, free the tag for lack of better option
					pwBufFree <= tagged Valid bufSlotIdx;
					tagStatus[tag].complete;
                    $display($time,"ERROR: Unexpected response received ",fshow(resp));
                    dynamicAssert(False,"Invalid command code received");
                endaction
        endcase
    endrule

	interface StreamControl ctrl;
	    method Action start(UInt#(64) ea0,UInt#(64) size) = wStart._write(tuple2(ea0,size));
		method Action abort = wStart._write(tuple2(0,0));

	    method Bool done = eaRequest.ctrl.done && List::all ( \== (TagStatus'(Done)), List::map(read,tagStatus));
	endinterface

	interface Put data;

		method Action put(dataT i) if (nextBufferSlot matches tagged Valid { .index, .chunk } &&& !inputIdx.ctrl.done);
    		if (chunk == 0)								// first use of this buffer slot: mark it as used
    		begin
				dynamicAssert(!bufferUsed[index].notEmpty,"Buffer slot assumed to be free is not");
				bufferUsed[index].enq(?);				// unguarded, but nextBufferSlot == (index, *) implies must be empty
    			$display($time," INFO: Claimed buffer slot %d",index);
    		end
    
    		if (chunk == fromInteger(transfersPerCacheLine-1))		// last use of this buffer slot: enq it for transmission
    		begin
    			txBufferSlot.enq(index);
    			nextBufferSlot <= nextFreeBufferSlot;
    			if (verbose)
    				$display($time," INFO: Enqueued buffer slot %d for transmission",index);
    		end
    		else 										// ongoing use of the buffer slot: bump chunk counter
    			nextBufferSlot <= tagged Valid tuple2(index,chunk+1);
    
    		// store the incoming value
    		dataBuffer.write(bufferAddressFromSlotChunk(index,chunk),pack(i));
    
    		if (verbose)
    			$display($time," INFO: Accepted input, writing to buffer slot %d chunk %d",index,chunk);

			// maintain the counter    
			let idx <- inputIdx.next.get;
    	endmethod
	endinterface


endmodule


endpackage
