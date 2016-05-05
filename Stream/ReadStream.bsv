package ReadStream;

import Stream::*;
import PSLTypes::*;
import CmdTagManager::*;
import Cntrs::*;
import ProgrammableLUT::*;
import List::*;
import HList::*;
import Assert::*;
import DReg::*;

import SynthesisOptions::*;

/** Streams bytes from host memory, yielding a stream of 512b half-lines in ascending memory order.
 *
 * Both address and byte size must be cache-aligned. As the "stream" name suggests, it does non-allocating (uncached) reads.
 *
 */

module [ModuleContext#(ctxT)] mkReadStream#(StreamConfig cfg,CmdTagManagerClientPort#(Bit#(nbu)) cmdPort)(
    Tuple2#(
        StreamCtrl,
        GetS#(t)))
    provisos (
        Gettable#(ctxT,SynthesisOptions),
        NumAlias#(nbs,8),       // Bits for slot index
        NumAlias#(nbc,1),       // Bits for chunk counter
        NumAlias#(nbCount,32),  // lots of cache lines
        Add#(nbs,__some,nbu),   // user data tag big enough to accommodate a slot index
        Bits#(t,512),           // TODO: Make proviso more general on transfer type
        Add#(nbs,nbc,nblut)     // Bits for lut index (slot+chunk)
    );
    
    ctxT ctx <- getContext;
    SynthesisOptions opts = getIt(ctx);

    staticAssert(cfg.bufDepth <= 2**valueOf(nbs),"Buffer depth exceeds address counter addressable width");

    // Read address management
    Count#(CacheLineCount#(nbCount))    clRemaining <- mkCount(0);
    Count#(CacheLineAddress)            clAddress   <- mkCount(0);
    Reg#(Bool)                          clCommandsDone[2] <- mkCReg(2,True);

    Count#(UInt#(nbs))                  tagsInFlight <- mkCount(0);

    // FIFO
    UnitUpDnCount#(UInt#(nbs)) issuePtr  <- mkUnitUpDnModuloCount(cfg.bufDepth,0);     // next slot to issue
    UnitUpDnCount#(UInt#(nbs)) outputPtr <- mkUnitUpDnModuloCount(cfg.bufDepth,0);     // next slot to be read


    // Output chunking
    Count#(UInt#(nbc)) outputChunk <- mkCount(0);   // output chunk currently being read

    // Buffer & buffer status
    //      Allocated will be True if a request has been issued and the data has not yet been read
    List#(SetReset)                     bufSlotAllocated     <- List::replicateM(cfg.bufDepth,mkConflictFreeSetReset(False));

    //      Complete will be False if a request has been issued and completed
    List#(SetReset)                     bufSlotComplete     <- List::replicateM(cfg.bufDepth,mkConflictFreeSetReset(False));
    Lookup#(nblut,t)                    bufData             <- mkZeroLatencyLookup(cfg.bufDepth * 2**valueOf(nbc));

    Bool isFull             = issuePtr == outputPtr && bufSlotAllocated[outputPtr];
    Bool outputAvailable    = bufSlotComplete[outputPtr];

    function UInt#(nblut) lutIndex(UInt#(nbs) slot,UInt#(nbc) chunk) = (extend(slot)<<valueOf(nbc)) | extend(chunk);

    // issue read commands as long as we have free tags and buffer slots
    rule issueRead if (!isFull
            && !clCommandsDone[0]
            && tagsInFlight < fromInteger(cfg.nParallelTags));

        issuePtr.incr;
        clAddress.incr(1);
        clRemaining.decr(1);
        tagsInFlight.incr(1);

        let tag <- cmdPort.issue(
            CmdWithoutTag { com: Read_cl_na, cabt: Strict, csize: 128, cea: toEffectiveAddress(clAddress) },
            pack(extend(issuePtr)));

        if (clRemaining == 1)
        begin
            if (opts.showStatus)
                $display($time," INFO: Last read issued");
            clCommandsDone[0] <= True;
        end

        if (opts.showData)
            $display($time," INFO: Issued read for address %016X using tag %02X",toEffectiveAddress(clAddress),tag);

        bufSlotAllocated[issuePtr].set;
        bufSlotComplete[issuePtr].rst;
    endrule


    // peek at the output when it's available
    Wire#(t) peek <- mkWire;
    rule peekOutput if (outputAvailable);
        let val <- bufData.lookup( lutIndex(outputPtr,outputChunk) );
        peek <= val;
    endrule

    rule handleResponse;
        let { resp, s } = cmdPort.response;
        UInt#(nbs) slot = unpack(truncate(s));

        if(resp.response != Done)
            $display($time," ERROR: Slot %02X fault response received but not handled ",slot,fshow(resp));

        if(opts.showData)
            $display($time," INFO: Completed read tag %02X (slot %02X)",resp.rtag,slot);

        tagsInFlight.decr(1);
            
        bufSlotComplete[slot].set;
    endrule

    Reg#(Maybe#(Tuple2#(UInt#(nblut),t))) bufWriteIn <- mkDReg(tagged Invalid);

    rule handleBufWrite;
        let { bw, s } = cmdPort.readdata;
        UInt#(nbs) slot = unpack(truncate(s));
        bufData.write((extend(slot)<<valueOf(nbc)) | extend(bw.bwad),unpack(bw.bwdata));
    endrule 

    return tuple2(
    interface StreamCtrl;
        method Action start(EAddress64 ea,UInt#(64) nBytes);
            clAddress   <= toCacheLineAddress(ea);
            clRemaining <= toCacheLineCount(nBytes);

            clCommandsDone[1] <= nBytes==0;
            dynamicAssert(nBytes % 128 == 0, "mkReadStream: Unaligned transfer size");
            dynamicAssert(ea.addr % 128 == 0,"mkReadStream: Unaligned transfer address");

            issuePtr  <= 0;
            outputPtr <= 0;

            tagsInFlight <= 0;

            for(Integer i=0;i<cfg.bufDepth;i=i+1)
            begin
                bufSlotAllocated[i].clear;
                bufSlotComplete[i].clear;
            end
        endmethod

        method Action abort = dynamicAssert(False,"mkReadStream: abort method is not supported");

        method Bool done = clCommandsDone[0] && !List::any( read, bufSlotAllocated );
    endinterface,

    interface GetS;
        method t first = peek;

        // schedules after everything that reads status
        method Action deq if (outputAvailable);
            if (outputChunk == fromInteger(nChunksPerTransfer-1))        // last chunk of this output
            begin
                outputPtr.incr;
                bufSlotAllocated[outputPtr].rst;
                bufSlotComplete[outputPtr].rst;
                outputChunk <= 0;
            end
            else
                outputChunk <= outputChunk+1;
        endmethod
    endinterface);
endmodule

endpackage
