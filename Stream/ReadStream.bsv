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

//function t readCReg(Integer i,Array#(Reg#(t)) r) = r[i]._read;
//function Action writeCReg(Integer i,t val,Array#(Reg#(t)) r) = r[i]._write(val);

module mkReadStream#(Integer nBuf,Integer nTags,CmdTagManagerClientPort#(Bit#(nbu)) cmdPort)(
    Tuple2#(
        StreamCtrl,
        GetS#(t)))
    provisos (
        NumAlias#(nbs,6),       // Bits for slot index
        NumAlias#(nbc,1),       // Bits for chunk counter
        NumAlias#(nbCount,32),  // lots of cache lines
        Bits#(RequestTag,nbtag),
        Add#(nbs,__some,nbu),   // user data tag big enough to accommodate a slot index
        Bits#(t,512),           // TODO: Make proviso more general on transfer type
        Add#(nbs,nbc,nblut)     // Bits for lut index (slot+chunk)
    );

    Bool verbose=True;

    let syn = hCons(MemSynthesisStrategy'(AlteraStratixV),hNil);

    // Read address management
    Count#(CacheLineCount#(nbCount))    clRemaining <- mkCount(0);
    Count#(CacheLineAddress)            clAddress   <- mkCount(0);
    Reg#(Bool)                          clCommandsDone[2] <- mkCReg(2,True);

    // FIFO
    Count#(UInt#(nbs)) issuePtr  <- mkCount(0);     // next slot to issue
    Count#(UInt#(nbs)) outputPtr <- mkCount(0);     // next slot to be read


    // Output chunking
    Count#(UInt#(nbc)) outputChunk <- mkCount(0);   // output chunk currently being read

    // Buffer & buffer status
    //      Allocated will be True if a request has been issued and the data has not yet been read
    List#(SetReset)                     bufSlotAllocated     <- List::replicateM(nBuf,mkConflictFreeSetReset(False));

    //      Complete will be False if a request has been issued and completed
    List#(SetReset)                     bufSlotComplete     <- List::replicateM(nBuf,mkConflictFreeSetReset(False));
    Lookup#(nblut,t)                    bufData             <- mkZeroLatencyLookup(syn,nBuf * 2**valueOf(nbc));

    Bool isFull             = issuePtr == outputPtr && bufSlotAllocated[outputPtr];
    Bool outputAvailable    = bufSlotComplete[outputPtr];

    function UInt#(nblut) lutIndex(UInt#(nbs) slot,UInt#(nbc) chunk) = (extend(slot)<<valueOf(nbc)) | extend(chunk);

    // issue read commands as long as we have free tags and buffer slots
    rule issueRead if (!isFull && !clCommandsDone[0]);
        issuePtr.incr(1);
        clAddress.incr(1);
        clRemaining.decr(1);

        let tag <- cmdPort.issue(
            CmdWithoutTag { com: Read_cl_na, cabt: Strict, csize: 128, cea: toEffectiveAddress(clAddress) },
            pack(extend(issuePtr)));

        if (clRemaining == 1)
        begin
            $display($time," INFO: Last read issued");
            clCommandsDone[0] <= True;
        end

        $display($time," INFO: Issued read for address %016X",toEffectiveAddress(clAddress));

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

        if(verbose)
            $display($time," INFO: Completed read tag %02X (slot %02X)",resp.rtag,slot);
            
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
            clCommandsDone[1] <= False;
            dynamicAssert(nBytes % 128 == 0, "mkReadStream: Unaligned transfer size");
            dynamicAssert(ea.addr % 128 == 0,"mkReadStream: Unaligned transfer address");

            for(Integer i=0;i<nBuf;i=i+1)
            begin
                bufSlotAllocated[i].clear;
                bufSlotComplete[i].clear;
            end
        endmethod

        method Bool done = clCommandsDone[0] && !List::any( read, bufSlotAllocated );
    endinterface,

    interface GetS;
        method t first = peek;

        // schedules after everything that reads status
        method Action deq if (outputAvailable);
            if (outputChunk == fromInteger(nChunksPerTransfer-1))        // last chunk of this output
            begin
                outputPtr.incr(1);
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
