package HostToAFUBulk;

import Common::*;

import DReg::*;

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


typedef enum {
    Done,
    ReadIssued,
    Flushed,
    Draining
} TagStatus deriving(Bits,Eq,FShow);


interface TagStatusIfc;
    method Action complete;
    method Action flush;
    method Action drain;
    method Action issue;

    interface ReadOnly#(TagStatus) current;
endinterface

module mkTagStatus(TagStatusIfc);
    Reg#(TagStatus) st[3] <- mkCReg(3,Done);

    // allowable transitions:
    //  Done -> ReadIssued
    //  ReadIssued -> Done
    //  ReadIssued -> Draining
    //  ReadIssued -> Flushed
    //  Flushed -> ReadIssued
    //  Flushed -> Draining

    let pwIssue <- mkPulseWire, pwDrain <- mkPulseWire, pwFlush <- mkPulseWire, pwComplete <- mkPulseWire;


    (* mutually_exclusive="doComplete,doFlush" *)       // command will receive only a single response: completed or flushed

    rule doComplete if (pwComplete);
        if (st[0] != ReadIssued)
        begin
            $display($time," ERROR: Received unexpected transition to Done from ",fshow(st[0]));
            dynamicAssert(st[0] == ReadIssued,"mkTagStatus: transitioned to Done from invalid state");
        end
        st[0] <= Done;
    endrule


    (* mutually_exclusive="doFlush,doIssue" *)          // flush implies read already issued

    rule doFlush if (pwFlush);
        if (st[0] != ReadIssued && st[0] != Flushed)
        begin
            $display($time," ERROR: Received unexpected transition to Flushed from ",fshow(st[0]));
            dynamicAssert(st[0] == ReadIssued,"mkTagStatus: transitioned to Flushed from invalid state");
        end
        if (st[0] == Flushed)
             $display($time," WARNING: Second flushed response received");
        st[0] <= Flushed;
    endrule

    rule doIssue if (pwIssue);
        if (st[1] != Done && st[1] != Flushed)
        begin
            $display($time," ERROR: Received unexpected transition to ReadIssued from ",fshow(st[1]));
            dynamicAssert(st[1] == Done || st[1] == Flushed,"mkTagStatus: transition to ReadIssued from invalid state");
        end
        st[1] <= ReadIssued;
    endrule

    // can drain from any state
    rule doDrain if (pwDrain);
        st[2] <= case (st[2]) matches
            ReadIssued:     Draining;
            Flushed:        Done;
            Done:           Done;
            Draining:       Draining;
        endcase;
    endrule


    method Action flush     = pwFlush.send;
    method Action complete  = pwComplete.send;
    method Action drain     = pwDrain.send;
    method Action issue     = pwIssue.send;

    interface ReadOnly current = regToReadOnly(st[0]);
endmodule


module mkHostToAFUBulk#(Integer nTags,CmdBufClientPort#(2) cmdbuf,EndianPolicy endianPolicy)
    (Tuple2#(StreamControl,PipeOut#(Tuple2#(UInt#(nOutputIdx),Bit#(wTransfer)))))
    provisos (
        Add#(nOutputIdx,__some,64),
        NumAlias#(512,wTransfer),
        Add#(__dummy,nTransferOffset,nOutputIdx),
        NumAlias#(6,nTransferOffset),
        Bits#(RequestTag,nTagIdx)
    );

    // transfer parameters
    Integer cacheLineBytes      = 128;                          // 128B = 1024b requires 7 address bits
    Integer transferBytes       = valueOf(wTransfer)/8;         // 512/8 = 64
    Integer transfersPerCacheLine= 128/transferBytes;           // 128/64 = 2

    // synthesis options
    HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);
    staticAssert(nTags <= valueOf(TExp#(nTagIdx)),"Inadequate address bits specified for the chosen number of tags");

    // Transfer counters
    Reg#(UInt#(64))             eaBase          <- mkReg(0);
    Count#(UInt#(nOutputIdx))   cacheLineIndex  <- mkCount(0);
    Reg#(UInt#(nOutputIdx))     cacheLineCount  <- mkReg(0);

    // Command tag status
    List#(TagStatusIfc) tagStatus <- List::replicateM(nTags,mkTagStatus);

    let addressLUT <- mkZeroLatencyLookup(syn,nTags);

    function EAddress64 toEAddress64(UInt#(nOutputIdx) i) = EAddress64 { addr: eaBase + (extend(i) << log2(cacheLineBytes)) };

    // Status control
    Wire#(Tuple2#(UInt#(64),UInt#(nOutputIdx))) wStart <- mkWire;
    FIFOF#(void) restartReq <- mkGFIFOF1(True,False);               // unguarded enq, guarded deq

    Reg#(Bool) requestsDone <- mkDReg(False);

    let pwRst <- mkPulseWire;

    // Output
    RWire#(Tuple2#(UInt#(nOutputIdx),Bit#(wTransfer))) o <- mkRWire;


    // reset everything 
    rule doTransferStart if (wStart matches { .eaIn, .countIn });
        for(Integer i=0;i<nTags;i=i+1)
            tagStatus[i].drain;
        eaBase          <= eaIn;
        cacheLineCount  <= countIn;
        cacheLineIndex  <= 0;
    endrule

    FIFOF#(RequestTag) pagedRestart <- mkGFIFOF1(True,False);

    // restart if we've received a Paged response
    rule doPagedRestart;
        restartReq.deq;
        RequestTag tag <- cmdbuf.putcmd(
            CmdWithoutTag {
                com: Restart,
                cabt: Strict, 
                cea: 0,
                csize: fromInteger(cacheLineBytes)});

        pagedRestart.enq(tag);

        $display($time," INFO: Issuing restart in response to Paged using tag %d",tag);
    endrule

    function TagStatus read(TagStatusIfc ifc) = ifc.current._read;

    RWire#(RequestTag) flushedEl <- mkRWire;

    rule checkForFlushed;
        Integer i;
        for(i=0;i<nTags && tagStatus[i].current != Flushed;i=i+1)
            begin
            end

        if (i < nTags)
            flushedEl.wset(fromInteger(i));
    endrule

    rule reissueFlushed if (flushedEl.wget matches tagged Valid .i &&& !pagedRestart.notEmpty); 
        // get address of the flushed command
        let idxReissue <- addressLUT.lookup(i);

        // reissue the command
        RequestTag tag <- cmdbuf.putcmd(
            CmdWithoutTag {
                com: Read_cl_s,
                cabt: Strict,
                cea: toEAddress64(idxReissue),
                csize: fromInteger(cacheLineBytes)});

        $display($time," INFO: Reissuing command for flushed tag %d, new tag %d",i,tag);
        tagStatus[tag].issue;

        // write address to new command tag
        addressLUT.write(tag,idxReissue);
    endrule

    (* preempts="doTransferStart,(reissueFlushed,fetchNext)" *)         // don't issue new commands if we're starting fresh

    (* descending_urgency="doPagedRestart,reissueFlushed,fetchNext" *)  // give priority to handling paged/flushed commands

    // issue next read command if still work remaining
	rule fetchNext if (!pwRst && cacheLineIndex != cacheLineCount && !pagedRestart.notEmpty);
        cacheLineIndex.incr(1);
        
        // issue read
		RequestTag tag <- cmdbuf.putcmd(                // implicit condition: able to issue command
			CmdWithoutTag {
			 	com: Read_cl_s,
				cabt: Abort,
				cea: toEAddress64(cacheLineIndex),
				csize: fromInteger(cacheLineBytes) });

        $write($time," INFO - Tag status: ");
        for(Integer i=0;i<nTags;i=i+1)
            $write(" ",fshow(tagStatus[i].current));
        $display;

        // mark tag as in-use
//        dynamicAssert(tagStatus[tag].current == Done,"Trying to start a read with a tag where status != Done");
        tagStatus[tag].issue;

        $display($time," INFO: Issuing new read using tag %d",tag);

        // save address offset for bulk transfer
        addressLUT.write(tag,cacheLineIndex);
    endrule

    rule checkDone if (!pwRst && cacheLineIndex == cacheLineCount);
        requestsDone <= True;
    endrule


    Wire#(Response) cmdResponse <- mkWire;

    rule getResponse;
        let resp <- cmdbuf.response.get;
        cmdResponse <= resp;
    endrule


    (* preempts = "restartComplete,handleResponse" *)
    rule restartComplete if (cmdResponse.response == Done && cmdResponse.rtag == pagedRestart.first);
        pagedRestart.deq;
        $display($time," INFO: Restart completed (tag %d)",cmdResponse.rtag);
    endrule

    rule handleResponse;
        let tag = cmdResponse.rtag;

        case (cmdResponse.response) matches
            Paged:
                action
                    $display($time," INFO: Paged response for tag %d",tag);
                    restartReq.enq(?);
                    tagStatus[tag].flush;
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
				    $display($time,"ERROR: HostToAFUStream invalid response type received ",fshow(cmdResponse));
                    tagStatus[tag].complete;
                endaction
        endcase
	endrule


    (* descending_urgency="processBufWrite,reissueFlushed" *)
    (* fire_when_enabled *)

    rule processBufWrite;
        // check for valid bwad
        dynamicAssert(cmdbuf.buffer.readdata.bwad < fromInteger(transfersPerCacheLine),
            "Invalid bwad value  = transfersPerCacheLine");

        // lookup the index for this read tag, calculate its position in the output stream
        let readCmdIdx <- addressLUT.lookup(cmdbuf.buffer.readdata.bwtag);
        UInt#(nOutputIdx) oIdx = (extend(readCmdIdx) << log2(transfersPerCacheLine)) | extend(cmdbuf.buffer.readdata.bwad);

        // write out
        o.wset(tuple2(oIdx,
            endianPolicy == HostNative ? cmdbuf.buffer.readdata.bwdata : endianSwap(cmdbuf.buffer.readdata.bwdata)));
    endrule

    return tuple2(
        interface StreamControl;
            method Action start(UInt#(64) ea0,UInt#(64) size) = wStart._write(tuple2(ea0, truncate(size >> log2(cacheLineBytes))));
            method Action abort = wStart._write(tuple2(0,0));

            method Bool done = cacheLineIndex == cacheLineCount && List::all ( \== (TagStatus'(Done)), List::map(read,tagStatus));
        endinterface,

        f_RWire_to_PipeOut(o)
    );
endmodule

endpackage
