package HostToAFUBulk;

import DReg::*;

import Common::*;
import StmtFSM::*;

import HList::*;
import Assert::*;
import AFU::*;
import PSLTypes::*;
import FIFO::*;
import PAClib::*;
import Vector::*;
import List::*;

import Cntrs::*;

import PAClibx::*;

import CmdBuf::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import BLProgrammableLUT::*;

import Endianness::*;

import CAPIStream::*;



// Export only the public items (there are helper classes that should not be visible)
//export mkHostToAFUBulk, HostToAFUBulkIfc, CAPIStream::*;



/** Module for bulk (possibly out-of-order) transfer from host to AFU using multiple parallel tags. Does not perform buffering
 * or width adaptation, for maximum leanness. Output is tagged with an index (of polymorphic width) to give order.
 * 
 * *** REQUIRES COMPILATION WITH -aggressive-conditions ***
 * 
 * Issues commands when able on the supplied CmdBufClientPort.
 *
 * For wTransfer = 512b (64B) cache line
 *
 *
 * ENDIANNESS
 * ==========
 * 
 * Transfer units always appear with ascending index being ascending memory address. Within the transfer unit, the values may
 * be HostNative (P8LE -> appear backwards to Bluespec), or BigEndian.
 *
 *
 * PAGE FAULTS
 * ===========

 * Some requests may take a very long time to complete because of page faults etc. Since these are consecutive, the page fault
 * occurs on the first address of the page and subsequent requests are blocked anyway.
 *
 * TODO: Graceful reset logic
 */

interface HostToAFUBulkIfc#(type idxT,type addrT,type dataT);
	interface StreamControl#(addrT)		ctrl;
	interface Get#(Tuple2#(idxT,dataT)) data;
endinterface

module mkHostToAFUBulk#(Integer nTags,CmdBufClientPort#(2) cmdbuf,EndianPolicy endianPolicy)
    (HostToAFUBulkIfc#(UInt#(nOutputIdx),UInt#(64),dataT))
    provisos (
        Add#(nOutputIdx,__some,64),
        Bits#(dataT,512),
        Add#(__dummy,nTransferOffset,nOutputIdx),
        NumAlias#(6,nTransferOffset),
        Bits#(RequestTag,nTagIdx)
    );


    // synthesis options & checks
    HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);
    staticAssert(nTags <= valueOf(TExp#(nTagIdx)),"Inadequate address bits specified for the chosen number of tags");
    Bool verbose=False;

    // Transfer counter
	Reg#(UInt#(64))							eaBase	    <- mkReg(0);
	StreamAddressGen#(UInt#(nOutputIdx)) 	idxStream   <- mkStreamAddressGen(cacheLineBytes);

    // Command tag information
    List#(TagStatusIfc) 				tagStatus 		<- List::replicateM(nTags,mkTagStatus);
    Lookup#(nTagIdx,UInt#(nOutputIdx))	tagAddressLUT 	<- mkZeroLatencyLookup(syn,nTags);

    // Status control
    Wire#(Tuple2#(UInt#(64),UInt#(64))) wStart <- mkWire;


	// Command state

    FIFOF#(UInt#(64)) nextStreamRead <- mkLFIFOF;

    FIFOF#(RequestTag) restartTag <- mkGFIFOF(True,False);		// holds the command tag for the restart
    FIFOF#(void) pagedResponseReceived <- mkBypassFIFOF;

    // Output
    Reg#(Maybe#(Tuple2#(UInt#(nOutputIdx),dataT))) o <- mkDReg(tagged Invalid);


    // reset everything 
    rule doTransferStart if (wStart matches { .eaIn, .countIn });
		// ditch existing tags
        for(Integer i=0;i<nTags;i=i+1)
            tagStatus[i].drain;

		// set up effective address counters (including alignment checks)
		eaBase <= eaIn;
		idxStream.ctrl.start(0,truncate(countIn));

        if (verbose)
        begin
            if (countIn == 0)
                $display($time," INFO: Terminating host->afu bulk transfer");
            else 
                $display($time," INFO: Starting host->afu bulk transfer for %x lines starting at %x",countIn,eaIn);
        end
    endrule




    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Paged response handling

	// find next flushed tag, if any
    function Maybe#(RequestTag) nextFlushedTag;
        Maybe#(RequestTag) t = tagged Invalid;
        Integer i;
        for(i=0;i<nTags && tagStatus[i].current != Flushed;i=i+1)
            begin
            end

        if (i < nTags)
            t = tagged Valid fromInteger(i);
        return t;
    endfunction



	rule issueRestartOnPaged;
		pagedResponseReceived.deq;
        RequestTag tag <- cmdbuf.putcmd(
            Any,
            CmdWithoutTag {
                com: Restart,
                cabt: Strict,
                cea: 0,
                csize: fromInteger(cacheLineBytes) });

      	$display($time," INFO: Issuing restart in response to Paged using tag %d",tag);

		nextStreamRead.clear;

        restartTag.enq(tag);
		dynamicAssert(!restartTag.notEmpty,"Paged response received before prior restart had completed");
    endrule





    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Transfer commands



	(* descending_urgency="enqReissueFlushed,enqStreamRead" *)

    rule enqReissueFlushed if (nextFlushedTag matches tagged Valid .flushedTag);
        // get address of the flushed command
        let idxReissue <- tagAddressLUT.lookup(flushedTag);

//        tagStatus[flushedTag].reissue;

        nextStreamRead.enq(eaBase + extend(idxReissue));

        if (verbose)
            $display($time," INFO: Enqueueing reissue for flushed tag %d",flushedTag);
    endrule

    // issue next read command if still work remaining
	rule enqStreamRead if (!idxStream.ctrl.done && !restartTag.notEmpty && !pagedResponseReceived.notEmpty);
		let idx <- idxStream.next.get;
        nextStreamRead.enq(extend(idx)+eaBase);
    endrule
	
	(* descending_urgency="issueRestartOnPaged,issueNextFetch" *)

    rule issueNextFetch;
        nextStreamRead.deq;									// implicit condition: fetch command enq'd
        
        // issue read
		RequestTag tag <- cmdbuf.putcmd(                	// implicit condition: able to issue command
            Any,
			CmdWithoutTag {
			 	com: 	Read_cl_na,
				cabt: 	Strict,
				cea: 	EAddress64 { addr: nextStreamRead.first},
				csize: 	fromInteger(cacheLineBytes) });

        // WARNING!! If tags A and B were flushed then tag tagAddressLUT is holding their ea. reissuing read for aA using B will
        // clobber B's address in the LUT. NEED TO FIX
        // mark tag as in-use
        //
        // Although CmdBuf grants tags in ascending order, other requestors may lock up the low-order tags which will cause grief.
        //
        // As-is, can issue on a tag with status flushed
//        dynamicAssert(tagStatus[tag].current == Done,"Trying to start a read with a tag where status != Done");
        tagStatus[tag].issue;

        if (verbose)
            $display($time," INFO: Issuing read using tag %d",tag);

        // save address offset for bulk transfer
		messageM("Using broken tagAddressLUT logic - addresses stored are incorrect for Paged restarts");
        tagAddressLUT.write(tag,truncate((nextStreamRead.first-eaBase) >> log2(cacheLineBytes)));
    endrule





    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Response handling

    Wire#(Response) cmdResponse <- mkWire;

    rule getResponse;
        let resp <- cmdbuf.response.get;
        cmdResponse <= resp;
    endrule


    (* preempts = "restartComplete,handleOtherResponse" *)

    rule restartComplete if (cmdResponse.rtag == restartTag.first);         // restartTag has value only if restart cmd outstanding
        restartTag.deq;

        if (cmdResponse.response != Done)
            $display($time," ERROR: Restart command issued for tag %d ",restartTag.first," received response ",
                fshow(cmdResponse.response)," when expecting Done");

        dynamicAssert(cmdResponse.response == Done,"Received an invalid response to Restart command");

        $display($time," INFO: Restart completed (tag %d)",cmdResponse.rtag);
    endrule

    rule handleOtherResponse;
        let tag = cmdResponse.rtag;

        case (cmdResponse.response) matches
            Paged:
                action
                    $display($time," INFO: Paged response for tag %d",tag);
                    tagStatus[tag].flush;
                    pagedResponseReceived.enq(?);
                endaction

            Done:
                tagStatus[tag].complete;

            Flushed:
            action
                $display($time," INFO: Flushed response for tag %d",tag);
                tagStatus[tag].flush;
            endaction

            default:
                action
                    // mark complete to prevent hanging up in unforeseen circumstances
				    $display($time,"ERROR: HostToAFUStream invalid response type received ",fshow(cmdResponse));
                    tagStatus[tag].complete;
                endaction
        endcase
	endrule




    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Buffer write handling

    // processBufWrite conflicts with reissueFlushed because of tagAddressLUT.lookup (could solve by adding another LUT port, but
	// that would be expensive relative to its frequency of use (will delay restart by at most a few cycles when paged)
    (* preempts="processBufWrite,enqReissueFlushed" *)
    rule processBufWrite;
        // check for valid bwad
        dynamicAssert(cmdbuf.buffer.readdata.bwad < fromInteger(transfersPerCacheLine),
            "Invalid bwad value  = transfersPerCacheLine");

        // lookup the index for this read tag, calculate its position in the output stream
        let readCmdIdx <- tagAddressLUT.lookup(cmdbuf.buffer.readdata.bwtag);
        UInt#(nOutputIdx) oIdx = (extend(readCmdIdx) << log2(transfersPerCacheLine)) | extend(cmdbuf.buffer.readdata.bwad);

        // write out
        o <= tagged Valid tuple2(oIdx,unpack(
            endianPolicy == HostNative ? cmdbuf.buffer.readdata.bwdata : endianSwap(cmdbuf.buffer.readdata.bwdata)));
    endrule

    interface StreamControl ctrl;
        method Action start(UInt#(64) ea0,UInt#(64) size) = wStart._write(tuple2(ea0, size));
        method Action abort = wStart._write(tuple2(0,0));

        method Bool done = idxStream.ctrl.done && List::all ( \== (TagStatus'(Done)), List::map(read,tagStatus));
    endinterface

	interface Get data;
		method ActionValue#(Tuple2#(UInt#(nOutputIdx),dataT)) get if (o matches tagged Valid .v);
			return v;
		endmethod
	endinterface
endmodule


endpackage
