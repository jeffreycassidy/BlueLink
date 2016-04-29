package BlockMapAFU;

import Stream::*;
import WriteStream::*;
import ReadStream::*;

import AFU::*;
import StmtFSM::*;
import PSLTypes::*;

import MMIO::*;
import FIFOF::*;
import Endianness::*;
import DedicatedAFU::*;
import Reserved::*;
import Vector::*;

import CmdArbiter::*;

import ConfigReg::*;

import Cntrs::*;

import CmdTagManager::*;

import HList::*;
import ModuleContext::*;
import ProgrammableLUT::*;

typedef struct {
    LittleEndian#(EAddress64) addrTo;       // destination address/size (bytes)
    LittleEndian#(UInt#(64))  oSize;
    LittleEndian#(EAddress64) addrFrom;     // source address/size (bytes)
    LittleEndian#(UInt#(64))  iSize;
} BlockMapParams deriving(Bits);

typedef struct {
    BlockMapParams  block;
    Reserved#(768)  resv;
} BlockMapWED deriving(Bits);

typedef enum { Resetting, Ready, Waiting, Running, Done } Status deriving (Eq,FShow,Bits);



/** The client interface to be provided to the mkBlockMapAFU */

interface BlockMapAFU#(type inputT,type outputT);
    interface Server#(inputT,outputT)               stream;
    interface Server#(MMIORWRequest,Bit#(64))       mmio;

    method Action                                   istreamDone;
    method Action                                   ostreamDone;

    method Bool                                     done;
endinterface



/** Block map AFU
 * Maps a function over a block of memory, storing the result in another block via streaming reads and writes.
 * Input and output size are specified in bytes and need to be cache-aligned, but do not need to be identical (ie. may be some
 * bit growth/reduction in the function)
 *
 * MMIO Map:
 * 0x00     Status (0=Resetting, 1=Ready, 2=Waiting(WED read done), 3=Running, 4=Done)
 * 0x08     From address
 * 0x10     To address
 * 0x20     Output size
 * 0x28     Output bytes transferred
 * 0x30     Input size
 * 0x38     Input bytes transferred
 */

module [ModuleContext#(ctxT)] mkBlockMapAFU#(Integer nReadBuf,Integer nWriteBuf,BlockMapAFU#(Bit#(512),Bit#(512)) blockMapper)(DedicatedAFU#(2))
    provisos (
        Gettable#(ctxT,MemSynthesisStrategy)
        );
    Bool verbose=False;

    Integer nReadTags = 4;
    Integer nWriteTags = 30;

    // WED
    Vector#(2,Reg#(Bit#(512))) wedSegs <- replicateM(mkConfigReg(0));
    BlockMapWED wed = concatSegReg(wedSegs,LE);

    // Command-tag management
    CmdTagManagerUpstream#(2) pslside;
    CmdTagManagerClientPort#(Bit#(8)) tagmgr;

    { pslside, tagmgr } <- mkCmdTagManager(64);
    Vector#(2,CmdTagManagerClientPort#(Bit#(8))) client <- mkCmdPriorityArbiter(tagmgr);

    // Stream controllers
    GetS#(Bit#(512)) idata;
    StreamCtrl istream;
    { istream, idata } <- mkReadStream(
        StreamConfig {
            verbose: True,
            bufDepth: nReadBuf,
            nParallelTags: nReadTags },
        client[1]);

    Put#(Bit#(512)) odata;
    StreamCtrl ostream;
    { ostream, odata } <- mkWriteStream(
        StreamConfig {
            verbose: True,
            bufDepth: nWriteBuf,
            nParallelTags: nWriteTags },
        client[0]);


    // Stream counters
    Count#(UInt#(32)) iCount <- mkCount(0), oCount <- mkCount(0);

    // Internal status lines
    let pwWEDReady <- mkPulseWire, pwStart <- mkPulseWire, pwTerm <- mkPulseWire;
    Reg#(Status) st <- mkReg(Resetting);
    Wire#(AFUReturn) ret <- mkWire;

    // FSMs to notify the block mapper when its read/write streams finish
    // NOTE: can only start these once the transfers are started, otherwise it will notify immediately because .done will be True)

    FIFOF#(void) istreamRunning <- mkGFIFOF1(True,False), ostreamRunning <- mkGFIFOF1(True,False);

    rule notifyIStreamDone if (istream.done);
        istreamRunning.deq;
        blockMapper.istreamDone;
        $display($time," INFO: Read stream complete and signaled to BlockMapAFU");
    endrule

    rule notifyOStreamDone if (ostream.done);
        ostreamRunning.deq;
        blockMapper.ostreamDone;
        $display($time," INFO: Write stream complete and signaled to BlockMapAFU");
    endrule

    //  Master state machine
    Stmt masterstmt = seq
        action
            iCount <= 0;
            oCount <= 0;
            st <= Resetting;
        endaction

        st <= Ready;

        action
            await(pwWEDReady);
            $display($time," INFO: WED read complete");
            $display($time,"      Dst address: %016X",unpackle(wed.block.addrTo).addr);
            $display($time,"      OSize:       %016X",unpackle(wed.block.oSize));
            $display($time,"      Src address: %016X",unpackle(wed.block.addrFrom).addr);
            $display($time,"      ISize:       %016X",unpackle(wed.block.iSize));

            st <= Waiting;
        endaction


        action
            st <= Running;
            await(pwStart);
            istream.start(unpackle(wed.block.addrFrom),unpackle(wed.block.iSize));
            ostream.start(unpackle(wed.block.addrTo),  unpackle(wed.block.oSize));
            $display($time," INFO: Starting streaming operation");
        endaction

        repeat(2) noAction;

        action
            istreamRunning.enq(?);
            ostreamRunning.enq(?);
        endaction

        await(blockMapper.done && istream.done && ostream.done);

        st <= Done;

        await(pwTerm);
        ret <= Done;
    endseq;

    let masterfsm <- mkFSM(masterstmt);



    rule sendInput;
        let id = idata.first;
        idata.deq;
        iCount.incr(1);
        blockMapper.stream.request.put(id);

        if (verbose)
        begin
            $write($time," INFO: Presenting input data ");
            for(Integer i=7;i>=0;i=i-1)
            begin
                $write("%016X ",endianSwap((Bit#(64))'(id[i*64+63:i*64])));
                if (i % 4 == 0)
                begin
                    $display;
                    if (i > 0)
                        $write("                                       ");
                end
            end
        end
    endrule

    rule getOutput;
        let o <- blockMapper.stream.response.get;
        odata.put(o);
        oCount.incr(1);

        if (verbose)
        begin
            $write($time," INFO: Received output data ");
            for(Integer i=7;i>=0;i=i-1)
            begin
                $write("%016X ",endianSwap((Bit#(64))'(o[i*64+63:i*64])));
                if (i % 4 == 0)
                begin
                    $display;
                    if (i > 0)
                        $write("                                       ");
                end
            end
        end
    endrule
    
    FIFOF#(MMIOResponse) mmResp <- mkGFIFOF1(True,False);

    rule handleDutMMIO;
        let resp <- blockMapper.mmio.response.get;
        mmResp.enq(resp);
    endrule

    RWire#(Bit#(64)) localMMIOResp <- mkRWire;

    (* conflict_free="handleDutMMIO,handleWrapperMMIO" *)
    rule handleWrapperMMIO if (localMMIOResp.wget matches tagged Valid .r);
        mmResp.enq(r);
    endrule

    interface ClientU command = pslside.command;
    interface AFUBufferInterface buffer = pslside.buffer;

    interface Server mmio;
        interface Get response = toGet(mmResp);

        interface Put request;
            method Action put(MMIORWRequest mm);
                case (mm) matches
                    tagged DWordWrite { index: 0, data: 0 }:
                        action
                            pwStart.send;
                            localMMIOResp.wset(64'h0);
                        endaction
                    tagged DWordWrite { index: 0, data: 1 }:
                        action
                            pwTerm.send;
                            localMMIOResp.wset(64'h0);
                        endaction
                    tagged DWordRead  { index: .i }:
                        localMMIOResp.wset(case(i) matches
                            0: ((extend(pack(istream.done)) << 49) | (extend(pack(ostream.done) << 48)) | case(st) matches
                                    Resetting: 0;
                                    Ready: 64'h1;
                                    Waiting: 64'h2;
                                    Running: 64'h3;
                                    Done: 64'h4;
                                endcase);
                            1: pack(unpackle(wed.block.addrTo));
                            2: pack(unpackle(wed.block.addrFrom));

                            4: pack(unpackle(wed.block.oSize));
                            5: pack(extend(oCount) << 6);
                            6: pack(unpackle(wed.block.iSize));
                            7: pack(extend(iCount) << 6);
                            default: 64'hdeadbeefbaadc0de;
                        endcase);
                    default:                                            // pass unhandled write requests through to DUT
                        blockMapper.mmio.request.put(mm);
                endcase
            endmethod
        endinterface
    endinterface

    method Action wedwrite(UInt#(6) i,Bit#(512) val) = asReg(wedSegs[i])._write(val);

    method Action rst = masterfsm.start;
    method Bool rdy = (st == Ready);

    method Action start(EAddress64 ea, UInt#(8) croom) = pwWEDReady.send;
    method ActionValue#(AFUReturn) retval = actionvalue return ret; endactionvalue;
endmodule

endpackage
