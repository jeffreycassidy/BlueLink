package CAPIStream;

import BuildVector::*;

import Common::*;

import Assert::*;
import AFU::*;
import PSLTypes::*;
import FIFO::*;
import PAClib::*;
import Vector::*;
import StmtFSM::*;

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
    method Action start(UInt#(64) ea,UInt#(64) size);
    method Bool done;

    // PSL interface
    interface Client#(CacheCommand,CacheResponse)       cmd;
    interface Put#(BufferWrite)                         bw;

    // PipeOut with data
    interface PipeOut#(Bit#(1024)) istream;
endinterface



interface AFUToHostStream;
    // start the stream
    method Action start(UInt#(64) ea,UInt#(64) size);
    method Bool done;

    // PSL interface
    interface Client#(CacheCommand,CacheResponse)       cmd;
    interface ServerARU#(BufferReadRequest,Bit#(512))   br;

    // the outgoing stream
    interface Put#(Bit#(1024)) ostream;
endinterface


function Bit#(n) padpack(data_t i) provisos (Bits#(data_t,ni),Add#(ni,__some,n)) = extend(pack(i));

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

    method Bool done = ea==eaEnd && !isValid(oData.wget);

    interface Client cmd;
        interface Get request;
            method ActionValue#(CacheCommand) get if (ea != eaEnd && !pwStart);
                let t <- mgr.acquire;
                completed[t] <= False;
                requestTagFIFO.enq(t);
                ea <= ea + fromInteger(stepBytes);
                return CacheCommand { com: Read_cl_s, ctag: t, cabt: Strict, cea: EAddress64 { addr: ea }, cch: 0, csize: fromInteger(stepBytes) };
            endmethod
        endinterface

        interface Put response;
            method Action put(CacheResponse r);
                case (r.response) matches
                    Done:
                        action
                            $display($time," Read completion for tag %X",r.rtag);
                            completed[r.rtag] <= True;

                            mgr.free(r.rtag);

                            // TODO: Change this so we can restart cleanly?
                            dynamicAssert(!completed[r.rtag],"Completion received for unused tag");
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



/** Sinks a stream to host memory.
 *
 * The user starts the transfer by providing an address and a size, then is able to push (size) bytes to the host in 1024b chunks.
 *
 * Currently requires cache-aligned ea and size. 
 */

module mkAFUToHostStream(AFUToHostStream)
    provisos (
        NumAlias#(nt,4));

    Integer stepBytes=128;
    Integer alignBytes=stepBytes;

    // Manage the request tags
    let mgr <- mkTagManager(Vector#(nt,RequestTag)'(genWith(fromInteger)),False);

    // keep track of completion status
    Vector#(nt,Reg#(Bool)) completed <- replicateM(mkReg(True));

    Reg#(UInt#(64)) eaStart   <- mkReg(0);
    Reg#(UInt#(64)) ea        <- mkReg(0);
    Reg#(UInt#(64)) eaEnd     <- mkReg(0);

    FIFO#(CacheCommand) oCmd <- mkFIFO;

    WriteBuf#(2) wbuf <- mkAFUWriteBuf(4);

    PulseWire pwStart <- mkPulseWire;

    method Action start(UInt#(64) ea0,UInt#(64) size);
        eaStart <= ea0;
        ea <= ea0;
        eaEnd <= ea0+size;

        pwStart.send;

        dynamicAssert(ea0 % fromInteger(alignBytes) == 0,    "Effective address is not properly aligned");
        dynamicAssert(size % fromInteger(alignBytes) == 0,   "Transfer size is not properly aligned");
    endmethod

    method Bool done = ea==eaEnd && foldl1( \&& , read(completed));

    interface Client cmd;
        interface Get request = toGet(oCmd);

        interface Put response;
            method Action put(CacheResponse r);
                case (r.response) matches
                    Done:
                        action
                            $display($time," Write completion for tag %X",r.rtag);
                            completed[r.rtag] <= True;

                            mgr.free(r.rtag);

                            // TODO: Change this so we can restart cleanly?
                            dynamicAssert(!completed[r.rtag],"Completion received for unused tag");
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

    interface ServerARU br;
        interface Put request  = wbuf.pslin.request;
        interface Get response = wbuf.pslin.response;
    endinterface

    interface Put ostream;
        method Action put(Bit#(1024) i) if (ea != eaEnd && !pwStart);
            // get tag and write data to buffer
            let t <- mgr.acquire;
            completed[t] <= False;
            wbuf.write(t,i);

            // enq command
            let cmd = CacheCommand { com: Write_mi, ctag: t, cabt: Strict, cea: EAddress64 { addr: ea }, cch: 0, csize: fromInteger(stepBytes) };
            oCmd.enq(cmd);
            ea <= ea + fromInteger(stepBytes);
        endmethod
    endinterface
endmodule


function Action putCompletion(Put#(CacheResponse) ifc,RequestTag t) = action
    let resp = CacheResponse { rtag: t, response: Done, rcredits: 0, rcachestate: 0, rcachepos: 0 };
    ifc.put(resp);
    $display($time," PSL=>AFU ",fshow(resp));
endaction;

function Action putBufWrite(Put#(BufferWrite) ifc,RequestTag t,UInt#(6) seg,Bit#(512) data) = action
    let bw = BufferWrite { bwtag: t, bwad: seg, bwdata: data };
    $display($time," PSL=>AFU ",fshow(bw));
    ifc.put(bw);
endaction;

function Action putBufReadReq(Put#(BufferReadRequest) ifc,RequestTag t,UInt#(6) seg) = action
    let br = BufferReadRequest { brtag: t, brad: seg };
    $display($time," PSL=>AFU ",fshow(br));
    ifc.put(br);
endaction;

module mkTB_OStream();

    let dut <- mkAFUToHostStream;

    function sendBufReadReq = putBufReadReq(dut.br.request);
    function sendCompletion = putCompletion(dut.cmd.response);

    // Put the AFU command on a wire for all to see
    Wire#(CacheCommand) cmd <- mkWire;

    rule getCommand;
        let c <- dut.cmd.request.get;
        $display($time," AFU=>PSL ",fshow(c));
        cmd <= c;
    endrule


    for(Integer i=0;i<4;i=i+1)
    begin
        Stmt writeStmt = seq
            repeat(30) noAction;

            // TODO: Randomize response time
            sendBufReadReq(fromInteger(i),0);
            noAction;
            sendBufReadReq(fromInteger(i),1);
            sendCompletion(fromInteger(i));
        endseq;

        let writeFSM <- mkFSM(writeStmt);

        rule handleWriteCmd if (cmd.com == Write_mi && cmd.ctag == fromInteger(i));
            dynamicAssert(writeFSM.done,"ERROR: Tag already in flight");
            writeFSM.start;
        endrule
    end

    rule sinkReadResponse;
        let brr = dut.br.response;
        $display($time," Response from memory: %0128X",brr);
    endrule


    // generate stimulus using counter
    Reg#(UInt#(32)) oCtr <- mkReg(0);
    Wire#(Vector#(1,Bit#(64))) w <- mkWire;

    function Action sendpiece = action
        let t = { 32'hf00fffff, pack(oCtr) };
        $display($time," Putting %16X",t);
        oCtr <= oCtr + 1;
        w <= replicate(t);
    endaction;

    // take 64b stimulus, unfunnel, and sink into output stream
    // use taps to show the 64b values and 1kb values on their way through
    function Action show64b(Vector#(1,Bit#(64)) i)  = $display($time,": 64b value %016X",i[0]);
    function Action show1k (Vector#(16,Bit#(64)) i)           = $display($time,": 1024b value %0256X",pack(i));

    let o64 <- mkSource_from_constant(w);
    let t64 <- mkTap(show64b,o64);
    PipeOut#(Vector#(16,Bit#(64))) o1k <- mkUnfunnel(False,t64);
    let t1k <- mkTap(show1k,o1k);
    let t1kb <- mkFn_to_Pipe(pack,t1k);
    mkSink_to_fa(dut.ostream.put,t1kb);

    Stmt stim = seq
        noAction;

        // read 8 cache lines
        action
            dut.start(64'h10080,64'h00400);
        endaction


        sendpiece;
        sendpiece;
        repeat(10) noAction;
        sendpiece;
        noAction;
        sendpiece;
        noAction;
        noAction;
        sendpiece;
        sendpiece;
        noAction;
        noAction;
        noAction;
        sendpiece;
        sendpiece;
        sendpiece;
        noAction;
        sendpiece;
        noAction;
        sendpiece;
        noAction;
        sendpiece;
        noAction;
        sendpiece;
        noAction;
        sendpiece;
        noAction;
        noAction;
        noAction;
        noAction;
        noAction;
        sendpiece;
        sendpiece;
        sendpiece;
        sendpiece;
        sendpiece;

        while(oCtr < 128)
            sendpiece;

        $display($time," INFO: Stimulus stream finished");

        await(dut.done);
        $display($time," INFO: DUT is finished transferring");

        repeat(20) noAction;
    endseq;

    mkAutoFSM(stim);
endmodule


module mkTB_StreamManager();

    let dut <- mkHostToAFUStream;

    function sendCompletion = putCompletion(dut.cmd.response);
    function sendBufWrite   = putBufWrite(dut.bw);

//    function Action sendCompletion(RequestTag t) = action
//        let resp = CacheResponse { rtag: t, response: Done, rcredits: 0, rcachestate: 0, rcachepos: 0 };
//        dut.cmd.response.put(resp);
//        $display($time," PSL=>AFU ",fshow(resp));
//    endaction;
//
//    function Action sendBufWrite(RequestTag t,UInt#(6) seg,Bit#(512) data) = action
//        let bw = BufferWrite { bwtag: t, bwad: seg, bwdata: data };
//        $display($time," PSL=>AFU ",fshow(bw));
//        dut.bw.put(bw);
//    endaction;


    // Put the AFU command on a wire for all to see
    Wire#(CacheCommand) cmd <- mkWire;

    rule getCommand;
        let c <- dut.cmd.request.get;
        $display($time," AFU=>PSL ",fshow(c));
        cmd <= c;
    endrule


    // sends a reply after delay d, with delay wd between buf writes
    function Stmt doRead(RequestTag t,Nat delay,Nat wd,Bit#(1024) data) = seq
        // wait for read command
        await(cmd.ctag == t && cmd.com == Read_cl_s);
        repeat(delay) noAction;

        par
            sendBufWrite(t,0,data[1023:512]);
            repeat(wd) noAction;
        endpar

        par
            sendBufWrite(t,1,data[511:0]);
            sendCompletion(t);
        endpar
    endseq;

    // creates a cacheline where each 64b word has the same 32b prefix and the lower 32b word is a counter

    function Bit#(1024) makePrefixedSequence(Bit#(32) pfx);
        Vector#(16,Bit#(64)) v;
        for(Integer i=0;i<16;i=i+1)
            v[i] = { pfx, pack(fromInteger(i)) };
        return pack(v);
    endfunction

    // PSL stimulus
    Stmt psl = seq
        par
            seq
                doRead(0,14,1,makePrefixedSequence(32'h00beef00));
                doRead(0,14,2,makePrefixedSequence(32'h00beef01));
                doRead(0,14,1,makePrefixedSequence(32'h00beef02));
                doRead(0,14,2,makePrefixedSequence(32'h00beef03));
            endseq

            seq
                doRead(1,14,4,makePrefixedSequence(32'hdeadb00f));
                doRead(1,14,4,makePrefixedSequence(32'hdeadb00f));
//                doRead(1,4,1,makePrefixedSequence(32'hdeadb11f));
            endseq

            seq
                doRead(2,14,6,makePrefixedSequence(32'hdeadb11f));
//                doRead(2,4,1,makePrefixedSequence(32'hdeadb11f));
            endseq

            seq
                doRead(3,14,2,makePrefixedSequence(32'hbaadc0de));
//                doRead(3,4,1,makePrefixedSequence(32'hbaadc0de));
            endseq
        endpar

        $display($time," INFO: PSL Stimulus complete");



    endseq;

    let psltb <- mkFSM(psl);

    Reg#(UInt#(32)) oCtr <- mkReg(0);


    Stmt stim = seq
        noAction;

        // read 8 cache lines
        action
            dut.start(64'h10080,64'h00480);
            psltb.start;
        endaction

        action
            await(dut.done);
            $display($time,": DUT reports completed");
        endaction

        repeat(1000) noAction;

        await(psltb.done);

        dynamicAssert(oCtr == 8*16 ,"Invalid output count");
    endseq;

    mkAutoFSM(stim);

    // sink output to stdout and count number of outputs
    function Action show(Bit#(64) x) = action
        $display($time,"  Stream output: %16X",x);
        oCtr <= oCtr + 1;
    endaction;

    PipeOut#(Vector#(16,Bit#(64))) p <- mkFn_to_Pipe(toChunks,dut.istream);
    PipeOut#(Vector#(1,Bit#(64))) f <- mkFunnel(p);
    let u <- mkFn_to_Pipe(compose(unpack,flip(select)(0)),f);
    mkSink_to_fa(show,u);
endmodule


endpackage
