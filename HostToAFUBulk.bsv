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
export mkHostToAFUBulk, CAPIStream::*;



/** Module for bulk (possibly out-of-order) transfer from host to AFU using multiple parallel tags. Does not perform buffering
 * or width adaptation, for maximum leanness.
 * 
 * *** REQUIRES COMPILATION WITH -aggressive-conditions ***
 * 
 * Issues commands when able on the supplied CmdBufClientPort. Since command tags are available from the manager only when completed,
 * can use that as an implicit buffer-management scheme. 
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
 * TODO: Deal correctly with PAGED response? (or is this unnecessary in Abort mode?)
 * TODO: Graceful reset logic
 */

module mkHostToAFUBulk#(Integer nTags,CmdBufClientPort#(2) cmdbuf,EndianPolicy endianPolicy)
    (Tuple2#(StreamControl,PipeOut#(Tuple2#(UInt#(nOutputIdx),Bit#(wTransfer)))))
    provisos (
        Add#(nOutputIdx,__some,64),
        NumAlias#(512,wTransfer),
        Add#(__dummy,nTransferOffset,nOutputIdx),
        NumAlias#(6,nTransferOffset),
        Bits#(RequestTag,nTagIdx)
    );


    // synthesis options
    HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);
    staticAssert(nTags <= valueOf(TExp#(nTagIdx)),"Inadequate address bits specified for the chosen number of tags");
    Bool verbose=False;//True;

    // Transfer counters
    Reg#(UInt#(64))             eaBase          <- mkReg(0);
    Count#(UInt#(nOutputIdx))   cacheLineIndex  <- mkCount(0);
    Reg#(UInt#(nOutputIdx))     cacheLineCount  <- mkReg(0);

    FIFOF#(UInt#(nOutputIdx)) nextReadIndex <- mkFIFOF;


    // Command tag status
    List#(TagStatusIfc) tagStatus <- List::replicateM(nTags,mkTagStatus);

    let addressLUT <- mkZeroLatencyLookup(syn,nTags);

    function EAddress64 toEAddress64(UInt#(nOutputIdx) i) = EAddress64 { addr: eaBase + (extend(i) << log2(cacheLineBytes)) };

    // Status control
    Wire#(Tuple2#(UInt#(64),UInt#(nOutputIdx))) wStart <- mkWire;

    // Output
    Reg#(Maybe#(Tuple2#(UInt#(nOutputIdx),Bit#(wTransfer)))) o <- mkDReg(tagged Invalid);


    // reset everything 
    rule doTransferStart if (wStart matches { .eaIn, .countIn });
        for(Integer i=0;i<nTags;i=i+1)
            tagStatus[i].drain;
        eaBase          <= eaIn;
        cacheLineCount  <= countIn;
        cacheLineIndex  <= 0;

        nextReadIndex.clear;

        if (verbose)
        begin
            if (cacheLineCount == 0)
                $display($time," INFO: Terminating host->afu bulk transfer");
            else 
                $display($time," INFO: Starting host->afu bulk transfer for %x lines starting at %x",countIn,eaIn);
        end
    endrule




    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Paged response handling

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


    FIFOF#(RequestTag) restartTag <- mkGFIFOF(True,False);
    FIFOF#(void) pagedResponseReceived <- mkBypassFIFOF;

    Stmt pagedStmt = seq
        action
            RequestTag tag <- cmdbuf.putcmd(
                CmdWithoutTag {
                    com: Restart,
                    cabt: Strict,
                    cea: 0,
                    csize: fromInteger(cacheLineBytes) });

            if (verbose)
                $display($time," INFO: Issuing restart in response to Paged using tag %d",tag);

            restartTag.enq(tag);
        endaction

        await (!restartTag.notEmpty);               // deq'd when Done response is received
    endseq;

    let pagedHandlerFSM <- mkFSM(pagedStmt);

    rule startPagedHandler;
        pagedResponseReceived.deq;
        pagedHandlerFSM.start;
    endrule





    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Transfer commands

    FIFOF#(UInt#(nOutputIdx)) nextFetch <- mkBypassFIFOF;
    FIFOF#(UInt#(nOutputIdx)) nextStreamRead <- mkFIFOF;


    // issue next read command if still work remaining
	rule enqNextStreamRead if (cacheLineIndex != cacheLineCount);
        cacheLineIndex.incr(1);
        nextStreamRead.enq(cacheLineIndex);          // Use a 2-entry FIFO to decouple backpressure
    endrule



    // processBufWrite conflicts with reissueFlushed because of addressLUT.lookup

    rule enqReissueFlushed if (nextFlushedTag matches tagged Valid .flushedTag);
        // get address of the flushed command
        let idxReissue <- addressLUT.lookup(flushedTag);

        tagStatus[flushedTag].reissue;

        nextFetch.enq(idxReissue);

        if (verbose)
            $display($time," INFO: Enqueueing reissue for flushed tag %d",flushedTag);
    endrule

    rule enqStreamRead;
        nextFetch.enq(nextStreamRead.first);
        nextStreamRead.deq;
    endrule



    rule issueNextFetch if (pagedHandlerFSM.done && !pagedResponseReceived.notEmpty);
        nextFetch.deq;
        
        // issue read
		RequestTag tag <- cmdbuf.putcmd(                // implicit condition: able to issue command
			CmdWithoutTag {
			 	com: Read_cl_s,
				cabt: Strict,
				cea: toEAddress64(nextFetch.first),
				csize: fromInteger(cacheLineBytes) });

        // WARNING!! If tags A and B were flushed then tag addressLUT is holding their ea. reissuing read for aA using B will
        // clobber B's address in the LUT. NEED TO FIX
        // mark tag as in-use
        //
        // As-is, can issue on a tag with status flushed
//        dynamicAssert(tagStatus[tag].current == Done,"Trying to start a read with a tag where status != Done");
        tagStatus[tag].issue;

        if (verbose)
            $display($time," INFO: Issuing read using tag %d",tag);

        // save address offset for bulk transfer
        addressLUT.write(tag,nextFetch.first);
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

//    (* descending_urgency="processBufWrite,enqReissueFlushed,enqStreamRead" *)
    (* preempts="processBufWrite,enqReissueFlushed" *)
    rule processBufWrite;
        // check for valid bwad
        dynamicAssert(cmdbuf.buffer.readdata.bwad < fromInteger(transfersPerCacheLine),
            "Invalid bwad value  = transfersPerCacheLine");

        // lookup the index for this read tag, calculate its position in the output stream
        let readCmdIdx <- addressLUT.lookup(cmdbuf.buffer.readdata.bwtag);
        UInt#(nOutputIdx) oIdx = (extend(readCmdIdx) << log2(transfersPerCacheLine)) | extend(cmdbuf.buffer.readdata.bwad);

        // write out
        o <= tagged Valid tuple2(oIdx,
            endianPolicy == HostNative ? cmdbuf.buffer.readdata.bwdata : endianSwap(cmdbuf.buffer.readdata.bwdata));
    endrule

    let op <- mkSource_from_maybe_constant(o);

    return tuple2(
        interface StreamControl;
            method Action start(UInt#(64) ea0,UInt#(64) size) = wStart._write(tuple2(ea0, truncate(size >> log2(cacheLineBytes))));
            method Action abort = wStart._write(tuple2(0,0));

            method Bool done = cacheLineIndex == cacheLineCount && List::all ( \== (TagStatus'(Done)), List::map(read,tagStatus));
        endinterface,

        op
    );
endmodule

endpackage
