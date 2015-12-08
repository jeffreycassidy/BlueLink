package MemScanChain;

import Assert::*;

import AlteraM20k::*;
import PAClib::*;
import FIFOF::*;
import ClientServer::*;
import GetPut::*;

import Vector::*;

typedef union tagged {
    Tuple2#(addrT,MemRequest#(dataT))   Request;
    dataT                               Response;
} MemItem#(type addrT,type dataT) deriving(Eq,Bits);


/** Interfaces a BRAM_Port_SplitRW element into a scan chain. 
 *  noffs   Exact number of bits to express the offset component of the address
 *  naddr   Number of address bits
 *
 *  nbank   (implied from naddr-noffs) number of bits to address the bank
 *
 * Bank striping happens along the (noffs) low-order address bits
 */

module mkMemScanChainElement#(
        Integer bankNum,
        BRAM_PORT_SplitRW#(UInt#(noffs),dataT) brport,                  // BRAM port handling the local requests
        PipeOut#(MemItem#(UInt#(naddr),dataT)) pi)                      // Incoming pipe
    (PipeOut#(MemItem#(UInt#(naddr),dataT)))
    provisos (
        Add#(noffs,nbank,naddr),
        Bits#(dataT,nd)
    );
    
    // Scan chain input/output buffers
    FIFOF#(MemItem#(UInt#(naddr),dataT))     scanChainInput  <- mkFIFOF;     // 2-step buffer, no combinational path to upstream via empty/full
    FIFOF#(MemItem#(UInt#(naddr),dataT))     scanChainOutput <- mkLFIFOF;    // 1-step buffer with combinational path downstream

    mkSink_to_fa(scanChainInput.enq,pi);

    // splits address into bank and offset
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


    // local requests absorb input and may generate output if it's a read
    rule localRead if (scanChainInput.first matches tagged Request { .addr, Read } &&& bankForAddress(addr) == fromInteger(bankNum));
        scanChainInput.deq;
        let offs = offsetForAddress(addr);
        brport.read.request.put(offs);
    endrule
    
    // local requests absorb input and may generate output if it's a read
    rule localWrite if (scanChainInput.first matches tagged Request { .addr, tagged Write .data } &&& bankForAddress(addr) == fromInteger(bankNum));
        scanChainInput.deq;
        let offs = offsetForAddress(addr);

        brport.write(offs,data);
    endrule



    // read response passes downstream
    rule readResponseOut;
        let resp <- brport.read.response.get;
        scanChainOutput.enq(tagged Response resp);
    endrule

    // if there's no read result on this cycle, then non-local request or incoming result passes on down
    (* descending_urgency="readResponseOut,scanChainPass" *)
    rule scanChainPass if (!isLocalRequest(scanChainInput.first));
        scanChainInput.deq;
        scanChainOutput.enq(scanChainInput.first);
    endrule

    return f_FIFOF_to_PipeOut(scanChainOutput);
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

module mkMemScanChain#(Vector#(nBanks,BRAM_PORT_SplitRW#(UInt#(noffs),dataT)) brport,PipeOut#(MemItem#(UInt#(naddr),dataT)) pi)
    (PipeOut#(dataT))
    provisos (
        Add#(noffs,nbank,naddr),
        Add#(1,__some,nBanks),
        Alias#(addrT,UInt#(naddr)),
        Alias#(dataT,Bit#(512))
    );

    // The scan chain elements
    Vector#(nBanks,PipeOut#(MemItem#(addrT,dataT))) el;

    el[0]  <- mkMemScanChainElement(0, brport[0],pi);

    for(Integer i=1;i<valueOf(nBanks);i=i+1)
        el[i] <- mkMemScanChainElement(i, brport[i], el[i-1]);

    // Check that output is data only
    rule checkResponse;
        case (last(el).first) matches
            tagged Request .*:
                dynamicAssert(False,"Request arrived at end of scan chain");
            tagged Response .*:
                noAction;
        endcase
    endrule

    // Strip off the tagged union at the end
    function dataT getData(MemItem#(UInt#(naddr),dataT) i) = i.Response;
    let o <- mkFn_to_Pipe(getData,last(el));

    return o;
endmodule

endpackage
