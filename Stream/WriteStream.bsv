package WriteStream;

import PSLTypes::*;
import CmdTagManager::*;
import Cntrs::*;
import ProgrammableLUT::*;
import List::*;
import HList::*;
import Assert::*;
import ClientServerU::*;
import DReg::*;

import Stream::*;

import SynthesisOptions::*;

/** Writes a stream to host memory, consuming 512b half-lines in order.
 *
 * The transfer can be throttled by setting a maximum number of parallel tags to use in the StreamConfig parameter.
 *
 * As the "stream" name suggests, it performs non-allocating (uncached) writes.
 *
 */

module [ModuleContext#(ctxT)] mkWriteStream#(StreamConfig cfg,CmdTagManagerClientPort#(Bit#(nbu)) cmdPort)(
    Tuple2#(
        StreamCtrl,
        Put#(t)))
    provisos (
        Gettable#(ctxT,SynthesisOptions),
        NumAlias#(nbs,8),       // Bits for slot index
        NumAlias#(nbc,1),       // Bits for chunk counter
        NumAlias#(nbCount,32),  // lots of cache lines
        Add#(nbs,__some,nbu),
        Bits#(t,512),
        Add#(nbs,nbc,nblut)     // Bits for lut index (slot+chunk)
    );

    ctxT ctx <- getContext;
    SynthesisOptions opts = getIt(ctx);

    staticAssert(cfg.bufDepth <= 2**valueOf(nbs),"Buffer depth exceeds address counter addressable width");

    // Write address management
    Count#(CacheLineCount#(nbCount))    clRemaining <- mkCount(0);
    Count#(CacheLineAddress)            clAddress   <- mkCount(0);
    Reg#(Bool)                          clCommandsDone[2] <- mkCReg(2,False);

    // Tag counters
    Count#(UInt#(nbs)) tagsInFlight <- mkCount(0);

    // FIFO
    UnitUpDnCount#(UInt#(nbs)) issuePtr   <- mkUnitUpDnModuloCount(cfg.bufDepth,0);     // next slot to issue write command
    UnitUpDnCount#(UInt#(nbs)) writePtr   <- mkUnitUpDnModuloCount(cfg.bufDepth,0);     // next slot to be written to at input
    Count#(UInt#(nbc)) writeChunk <- mkCount(0);

    // Buffer & buffer status
    List#(SetReset)                     bufSlotUsed <- List::replicateM(cfg.bufDepth,mkConflictFreeSetReset(False));
    Lookup#(nblut,t)                    bufData <- mkZeroLatencyLookup(cfg.bufDepth * 2**valueOf(nbc));

    Bool isEmpty            = issuePtr == writePtr && !bufSlotUsed[writePtr];
    Bool bufSlotAvailable   = !bufSlotUsed[writePtr];

    function UInt#(nblut) lutIndex(UInt#(nbs) slot,UInt#(nbc) chunk) = (extend(slot)<<valueOf(nbc)) | extend(chunk);

    // issue write commands as long as we have free tags and buffer slots
    rule issueWrite if (issuePtr != writePtr
            && bufSlotUsed[issuePtr]
            && !clCommandsDone[0]
            && tagsInFlight < fromInteger(cfg.nParallelTags));

        issuePtr.incr;
        clAddress.incr(1);
        clRemaining.decr(1);
        tagsInFlight.incr(1);

        if (clRemaining == 1)
        begin
            clCommandsDone[0] <= True;
            if (opts.showStatus)
                $display($time," INFO: Last write issued");
        end

        let tag <- cmdPort.issue(
            CmdWithoutTag { com: Write_na, cabt: Strict, csize: 128, cea: toEffectiveAddress(clAddress) },
            pack(extend(issuePtr)));

        if (opts.showData)
            $display($time," INFO: Issued write for address %016X using tag %02X",toEffectiveAddress(clAddress),tag);
    endrule

    Reg#(Maybe#(UInt#(nblut))) brReqQ <- mkDReg(tagged Invalid);
    Reg#(Maybe#(t)) brDataQ <- mkReg(tagged Invalid);

    rule regBufReadRequest;
        let { br, s } = cmdPort.writedata.request;
        UInt#(nbs) slot = unpack(truncate(s));
        brReqQ <= tagged Valid lutIndex(slot,truncate(br.brad));
    endrule

    rule doReadBufDataLookup if (brReqQ matches tagged Valid .i);
        let data <- bufData.lookup(i);
        brDataQ <= tagged Valid data;
    endrule

    rule sendOutput if (brDataQ matches tagged Valid .v);
        cmdPort.writedata.response.put(pack(v));
    endrule

    rule handleResponse;
        let { resp, s } = cmdPort.response;
        UInt#(nbs) slot = unpack(truncate(s));

        if(resp.response != Done)
            $display($time," ERROR: Slot %02X fault response received but not handled ",slot,fshow(resp));

        if(opts.showData)
            $display($time," INFO: Completed write tag %02X (slot %02X)",resp.rtag,slot);

        tagsInFlight.decr(1);
            
        bufSlotUsed[slot].rst;
    endrule


    return tuple2(
    interface StreamCtrl;
        method Action start(EAddress64 ea,UInt#(64) nBytes);
            clAddress   <= toCacheLineAddress(ea);
            clRemaining <= toCacheLineCount(nBytes);
            clCommandsDone[1] <= nBytes==0;
            dynamicAssert(nBytes % 128 == 0, "mkWriteStream: Unaligned transfer size");
            dynamicAssert(ea.addr % 128 == 0,"mkWriteStream: Unaligned transfer address");

            for(Integer i=0;i<cfg.bufDepth;i=i+1)
                bufSlotUsed[i].rst;

            tagsInFlight <= 0;
        endmethod

        method Action abort = dynamicAssert(False,"mkWriteStream: abort method is not supported");

        method Bool done = clCommandsDone[0] && !List::any( read, bufSlotUsed);
    endinterface,

    interface Put;
        method Action put(t iData) if (bufSlotAvailable);
            if (writeChunk == fromInteger(nChunksPerTransfer-1))        // last chunk of this input
            begin
                writePtr.incr;
                bufSlotUsed[writePtr].set;
                writeChunk <= 0;
            end
            else
                writeChunk <= writeChunk+1;
            bufData.write(lutIndex(writePtr,writeChunk),iData);
        endmethod
    endinterface);
endmodule

endpackage
