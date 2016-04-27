package MemScanChain;

import Assert::*;

import AlteraM20k::*;
import BRAMStall::*;
import PAClib::*;
import FIFOF::*;
import GetPut::*;
import BuildVector::*;

import Vector::*;

typedef union tagged {
    void Read;
    dataT Write;
} MemRequest#(type dataT) deriving(FShow,Bits);

typedef union tagged {
    dataT                               Response;
    Tuple2#(addrT,MemRequest#(dataT))   Request;
} MemItem#(type addrT,type dataT) deriving(FShow,Bits);




/// Create a PipeOut interface from an RWire, with the specified action done when deq is called

function PipeOut#(t) f_PipeOut_from_RWire(RWire#(t) rw,Action deqAction) = interface PipeOut;
    method Action deq if (isValid(rw.wget)) = deqAction;
    method Bool notEmpty = isValid(rw.wget);
    method t first if (rw.wget matches tagged Valid .v) = v;
endinterface;


/// mkPriorityJoin: provides output from the lowest-index of the n PipeOut#(t) inputs which has output

module mkPriorityJoin#(Vector#(n,PipeOut#(t)) piv)(PipeOut#(t))
    provisos (
        Bits#(t,nb));
    let pwDeq <- mkPulseWire;
    let o <- mkRWire;

    function Bool pipeOutHasOutput(PipeOut#(t) p) = p.notEmpty;

    Vector#(n,Bool)             hasOutput       = map (pipeOutHasOutput, piv);
    Vector#(TAdd#(n,1),Bool)    hasOutputBefore = scanl( \|| , False, hasOutput);

    for(Integer i=0; i<valueOf(n); i=i+1)
    begin
        (* fire_when_enabled *)
        rule getFirstNonEmpty if (!hasOutputBefore[i] && hasOutput[i]);
            o.wset(piv[i].first);
        endrule

        (* fire_when_enabled *)
        rule deqFirstNonEmpty if (pwDeq && hasOutput[i] && !hasOutputBefore[i]);
            piv[i].deq;
        endrule
    end

    return f_PipeOut_from_RWire(o, pwDeq.send);
endmodule



/** Interfaces a pipe-interfaced BRAM into a scan chain. 
 *  noffs   Exact number of bits to express the offset component of the address
 *  naddr   Number of address bits
 *
 *  nbank   (implied from naddr-noffs) number of bits to address the bank
 *
 * Bank striping happens along the (noffs) low-order address bits
 */

module mkMemScanChainElement#(
        Integer bankNum,

        BRAMPortStall#(UInt#(noffs),dataT) brport,                  // BRAM port handling the local requests
        PipeOut#(MemItem#(UInt#(naddr),dataT)) pi)                      // Incoming pipe
    (PipeOut#(MemItem#(UInt#(naddr),dataT)))
    provisos (
        Add#(noffs,nbank,naddr),
        Bits#(dataT,nd)
    );
    
    
    // manipulate addresses (bank,offset) <-> address
    function UInt#(nbank) bankForAddress(UInt#(naddr) addr)   = truncate(addr >> valueOf(noffs)); 
    function UInt#(noffs) offsetForAddress(UInt#(naddr) addr) = truncate(addr);

    function Tuple2#(UInt#(nbank),UInt#(noffs)) splitAddress(UInt#(naddr) addr) =
        tuple2(bankForAddress(addr), offsetForAddress(addr));

    function UInt#(naddr) joinAddress(UInt#(nbank) bank,UInt#(noffs) offset)    =
        (extend(bank) << valueOf(noffs)) | extend(offset);


    // check if a given MemItem is a local request or not (response or non-local request)
    function Bool isLocalRequest(MemItem#(UInt#(naddr),dataT) i) = case (i) matches
        tagged Request { .addr, .* }: (bankForAddress(addr) == fromInteger(bankNum));
        default: False;
    endcase;


    
    // 2-stage input FIFO to ensure no combinational path going upstream
    FIFOF#(MemItem#(UInt#(naddr),dataT))     scanChainInput  <- mkFIFOF;
    mkSink_to_fa(scanChainInput.enq,pi);

    FIFOF#(MemItem#(UInt#(naddr),dataT)) bypassBuf <- mkLFIFOF;


    // local requests absorb input and may generate output if it's a read
    rule acceptLocalRequest if (isLocalRequest(scanChainInput.first));
        scanChainInput.deq;

        case (scanChainInput.first) matches
            tagged Request { .addr, Read }:                 brport.putcmd(False,offsetForAddress(addr),?);
            tagged Request { .addr, tagged Write .data }:   brport.putcmd(True, offsetForAddress(addr),data);
        endcase
    endrule

    rule passthroughNonLocal if (!isLocalRequest(scanChainInput.first));
        bypassBuf.enq(scanChainInput.first);
        scanChainInput.deq;
    endrule

    function MemItem#(UInt#(naddr),dataT) wrapReadData(dataT d) = tagged Response d;
    let brReadData <- mkFn_to_Pipe(wrapReadData, brport.readdata);

    let o <- mkPriorityJoin(
        vec(
            brReadData,
            f_FIFOF_to_PipeOut(bypassBuf)
            ));

    return o;
endmodule



/** Implements the actual scan chain
 * For correctness, the BRAM_PORT_SplitRW must be able to backpressure the input if the output is stalled. If not, elements will be
 * dropped.
 *
 * For full throughput, it should be able to do so with internal buffering so that in steady-state it can always accept input.
 */

 //   function BRAM_PORT_Stall#(offsT,dataT) getPortA(BRAM_DUAL_PORT_Stall#(offsT,dataT) _br) = _br.a;
//    List#(BRAM_DUAL_PORT_Stall#(offsT,dataT))   br  <- List::replicateM(valueOf(nBanks),mkBRAM2Stall(bankDepth));
//    List#(BRAM_PORT_SplitRW#(offsT,dataT))      brs <- List::mapM(mkBRAMPortSplitRW, List::map(getPortA,br));

//module mkMemScanChain#(Vector#(nBanks,BRAM_PORT_SplitRW#(UInt#(noffs),dataT)) brport,PipeOut#(MemItem#(UInt#(naddr),dataT)) pi)
//    (PipeOut#(dataT))
//    provisos (
//        Add#(noffs,nbank,naddr),
//        Add#(1,__some,nBanks),
//        Alias#(addrT,UInt#(naddr)),
//        Alias#(dataT,Bit#(512))
//    );
//
//    // The scan chain elements
//    Vector#(nBanks,PipeOut#(MemItem#(addrT,dataT))) el;
//
//    el[0]  <- mkMemScanChainElement(0, brport[0],pi);
//
//    for(Integer i=1;i<valueOf(nBanks);i=i+1)
//        el[i] <- mkMemScanChainElement(i, brport[i], el[i-1]);
//
//    // Check that output is data only
//    rule checkResponse;
//        case (last(el).first) matches
//            tagged Request .*:
//                dynamicAssert(False,"Request arrived at end of scan chain");
//            tagged Response .*:
//                noAction;
//        endcase
//    endrule
//
//    // Strip off the tagged union at the end
//    function dataT getData(MemItem#(UInt#(naddr),dataT) i) = i.Response;
//    let o <- mkFn_to_Pipe(getData,last(el));
//
//    return o;
//endmodule

endpackage
