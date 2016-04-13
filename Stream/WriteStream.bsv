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

module mkWriteStream#(Integer nBuf,Integer nTags,CmdTagManagerClientPort cmdPort)(
    Tuple2#(
        StreamCtrl,
        Put#(t)))
    provisos (
        NumAlias#(nbs,6),       // Bits for slot index
        NumAlias#(nbc,1),       // Bits for chunk counter
        NumAlias#(nbCount,32),  // lots of cache lines
        Bits#(RequestTag,nbtag),
        Bits#(t,512),
        Add#(nbs,nbc,nblut)     // Bits for lut index (slot+chunk)
    );

    let syn = hCons(MemSynthesisStrategy'(AlteraStratixV),hNil);

    // Write address management
    Count#(CacheLineCount#(nbCount))    clRemaining <- mkCount(0);
    Count#(CacheLineAddress)            clAddress   <- mkCount(0);
    Reg#(Bool)                          clCommandsDone[2] <- mkCReg(2,False);

    // FIFO
    Count#(UInt#(nbs)) issuePtr  <- mkCount(0);     // next slot to issue write command
    Count#(UInt#(nbs)) writePtr  <- mkCount(0);     // next slot to be written to at input
    Count#(UInt#(nbc)) writeChunk <- mkCount(0);

    // Buffer & buffer status
    List#(SetReset)                     bufSlotUsed <- List::replicateM(nBuf,mkConflictFreeSetReset(False));
    Lookup#(nblut,t)                    bufData <- mkZeroLatencyLookup(syn,nBuf * 2**valueOf(nbc));
    MultiReadLookup#(nbtag,UInt#(nbs))  tagSlotMap <- mkMultiReadZeroLatencyLookup(syn,2,nTags);

    Bool isEmpty            = issuePtr == writePtr && !bufSlotUsed[writePtr];
    Bool bufSlotAvailable   = !bufSlotUsed[writePtr];

    function UInt#(nblut) lutIndex(UInt#(nbs) slot,UInt#(nbc) chunk) = (extend(slot)<<valueOf(nbc)) | extend(chunk);

    // issue write commands as long as we have free tags and buffer slots
    rule issueWrite if (issuePtr != writePtr && bufSlotUsed[issuePtr] && !clCommandsDone[0]);
        issuePtr.incr(1);
        clAddress.incr(1);
        clRemaining.decr(1);

        if (clRemaining == 1)
        begin
            clCommandsDone[0] <= True;
            $display($time," INFO: Last write issued");
        end

        let tag <- cmdPort.issue(CmdWithoutTag { com: Write_mi, cabt: Strict, csize: 128, cea: toEffectiveAddress(clAddress) });
        tagSlotMap.write(tag,issuePtr);

        $display($time," INFO: Issued write for address %016X",toEffectiveAddress(clAddress));
    endrule

    Reg#(Maybe#(Tuple2#(RequestTag,UInt#(nbc)))) brReqQ <- mkDReg(tagged Invalid);
    Reg#(Maybe#(t)) brDataQ <- mkReg(tagged Invalid);

    rule regBufReadRequest;
        let br = cmdPort.writedata.request;
        brReqQ <= tagged Valid tuple2(br.brtag, truncate(br.brad));
    endrule

    rule doReadBufDataLookup if (brReqQ matches tagged Valid { .tag, .chunk });
        let slot <- tagSlotMap.lookup[1](tag);
        let data <- bufData.lookup(lutIndex(slot,chunk));
        brDataQ <= tagged Valid data;
    endrule

    rule sendOutput if (brDataQ matches tagged Valid .v);
        cmdPort.writedata.response.put(pack(v));
    endrule

    rule handleResponse;
        let resp = cmdPort.response;
        let slot <- tagSlotMap.lookup[0](resp.rtag);

        if(resp.response != Done)
            $display($time," ERROR: Slot %02X fault response received but not handled ",slot,fshow(resp));
            
        bufSlotUsed[slot].rst;
    endrule


    return tuple2(
    interface StreamCtrl;
        method Action start(EAddress64 ea,UInt#(64) nBytes);
            clAddress   <= toCacheLineAddress(ea);
            clRemaining <= toCacheLineCount(nBytes);
            clCommandsDone[1] <= False;
            dynamicAssert(nBytes % 128 == 0, "mkWriteStream: Unaligned transfer size");
            dynamicAssert(ea.addr % 128 == 0,"mkWriteStream: Unaligned transfer address");

            for(Integer i=0;i<nBuf;i=i+1)
                bufSlotUsed[i].rst;
        endmethod

        method Bool done = clCommandsDone[0] && !List::any( read, bufSlotUsed);
    endinterface,

    interface Put;
        method Action put(t iData) if (bufSlotAvailable);
            if (writeChunk == fromInteger(nChunksPerTransfer-1))        // last chunk of this input
            begin
                writePtr.incr(1);
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
