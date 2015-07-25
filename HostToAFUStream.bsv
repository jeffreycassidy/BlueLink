package HostToAFUStream;

import Common::*;

import Assert::*;
import AFU::*;
import PSLTypes::*;
import FIFO::*;
import PAClib::*;
import Vector::*;

import TagManager::*;

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
 * TODO: Possible performance improvement (?) if we decouple the data buffer index from the tag index. Currently the same logic
 *          is used to allocate tags and buffer slots.
 *
 *          Rationale: if last tag takes a very long time to complete, we stop issuing new requests even though previous tags
 *                      have completed. They are blocked by the buffer not draining.
 *
 */

interface HostToAFUStream;
    // Start the stream
    method Action   start(UInt#(64) ea,UInt#(64) size);
    method Bool     done;

    // PSL interface
    interface Client#(CacheCommand,CacheResponse)       cmd;
    interface Put#(BufferWrite)                         bw;

    // PipeOut with data
    interface PipeOut#(Bit#(1024)) istream;
endinterface



/** Provides a PipeOut#(Bit#(1024)) stream from the host memory.
 *
 * The user starts the transfer by providing an address and a size, then is able to pull (size) bytes from the host.
 *
 * Currently requires cache-aligned ea and size. 
 */

module mkHostToAFUStream(HostToAFUStream)
    provisos (
        NumAlias#(nt,4));

    Integer stepBytes=128;
    Integer alignBytes=stepBytes;

    // Manage the request tags
    let mgr <- mkTagManager(Vector#(nt,RequestTag)'(genWith(fromInteger)),False);

    // keep track of which tags were requested in which order, and their completion status
    FIFO#(RequestTag) requestTagFIFO <- mkSizedFIFO(valueOf(nt));
    Vector#(nt,Reg#(Bool)) completed <- replicateM(mkReg(False));

    Reg#(UInt#(64)) eaStart   <- mkReg(0);
    Reg#(UInt#(64)) ea        <- mkReg(0);
    Reg#(UInt#(64)) eaEnd     <- mkReg(0);

    let rbuf <- mkAFUReadBuf(4);

    // Output data
    RWire#(Bit#(1024)) oData <- mkRWire;

    rule readyToDrain if (completed[requestTagFIFO.first]);
        let o <- rbuf.lookup(requestTagFIFO.first);
        oData.wset(o);
    endrule


    PulseWire pwStart <- mkPulseWire;

    method Action start(UInt#(64) ea0,UInt#(64) size);
        eaStart <= ea0;
        ea <= ea0;
        eaEnd <= ea0+size;

        pwStart.send;

        dynamicAssert(ea0 % fromInteger(alignBytes) == 0,    "Effective address is not properly aligned");
        dynamicAssert(size % fromInteger(alignBytes) == 0,  "Transfer size is not properly aligned");
    endmethod

    method Bool done = ea==eaEnd && !isValid(oData.wget) && all( id , read(completed));

    interface Client cmd;
        interface Get request;
            method ActionValue#(CacheCommand) get if (ea != eaEnd && !pwStart);
                let t <- mgr.acquire;
                completed[t] <= False;
                requestTagFIFO.enq(t);
                ea <= ea + fromInteger(stepBytes);
                return CacheCommand { com: Read_cl_s, ctag: t, cabt: Abort, cea: EAddress64 { addr: ea }, cch: 0, csize: fromInteger(stepBytes) };
            endmethod
        endinterface

        interface Put response;
            method Action put(CacheResponse r);
                case (r.response) matches
                    Done:
                        action
//                            $display($time," Read completion for tag %X",r.rtag);
                            completed[r.rtag] <= True;

                            mgr.free(r.rtag);

                            // TODO: Change this so we can restart cleanly?
                            //dynamicAssert(!completed[r.rtag],"Completion received for unused tag");
                        endaction
                        
                    default:
                        action
                            $display($time,"ERROR: Invalid command code received ",fshow(r));
                            dynamicAssert(False,"Invalid command code received");
                        endaction
                endcase
                    // Aerror
                    // Derror
                    // Nlock
                    // Nres
                    // Flushed
                    // Fault
                    // Failed
                    // Credit
                    // Paged
                    // Invalid
            endmethod

        endinterface
    endinterface

    interface Put bw = rbuf.pslin;

    interface PipeOut istream;
        method Action deq if (isValid(oData.wget)) = requestTagFIFO.deq;
        method Bit#(1024) first if (oData.wget matches tagged Valid .v) = v;
        method Bool notEmpty = isValid(oData.wget);
    endinterface
endmodule


endpackage
