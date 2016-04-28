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


//instance FShow#(MemRequest#(dataT));
//    function Fmt fshow(MemRequest#(dataT) req) provisos (FShow#(dataT)) = case (req) matches
//        tagged Read:        fshow("Read       ");
//        tagged Write .d:    fshow("Write ")+fshow(d);
//    endcase;
//endinstance
//
//instance FShow#(MemItem#(addrT,dataT));
//    function Fmt fshow(MemItem#(addrT,dataT) i) provisos (FShow#(dataT)) = case (i) matches
//        tagged Response .d:             fshow("Response ")++fshow(d);
//        tagged Request { .addr, .req }: fshow("Request address ")++fshow(pack(addr))+fshow(req);
//    endcase;
//endinstance



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
        BRAMPortStall#(UInt#(noffs),dataT) brport,                      // BRAM port handling the local requests
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



/** Creates a memory scan chain.
 * 
 * Each of the block RAM ports must be exactly 2**noffs deep, addressed by UInt#(noffs)
 */

module mkMemScanChain#(
    Vector#(nBanks,BRAMPortStall#(UInt#(nbOffs),dataT)) brport,
    PipeOut#(MemItem#(addrT,dataT)) pi)
    (PipeOut#(MemItem#(addrT,dataT)))
    provisos (
        Log#(nBanks,nbBankIdx),

        Add#(nbOffs,nbBankIdx,nbMinAddress),    // ensure address line is big enough for contents
        Add#(nbMinAddress,__lessthan0,nbAddress),

        Add#(nbOffs,__lessthan1,nbAddress),     // redundant proviso (can be inferred from two above)

        Add#(1,__lessthan2,nBanks),
        Alias#(addrT,UInt#(nbAddress)),
        Bits#(dataT,nbData)
    );

    // The scan chain elements
    Vector#(nBanks,PipeOut#(MemItem#(addrT,dataT))) el;

    el[0]  <- mkMemScanChainElement(0, brport[0],pi);

    for(Integer i=1;i<valueOf(nBanks);i=i+1)
        el[i] <- mkMemScanChainElement(i, brport[i], el[i-1]);

    return last(el);
endmodule





/** Group a set of n v-wide BRAMs into a single w-wide interface (w=nv).
 * Bank striping occurs along the lowest-order bits. The number of banks n must be a power of 2.
 *
 *  w       Group-side bit width
 *  n       Number of banks to group
 *  v       Individual-side padded bit width
 *
 * In Bluespec packing convention, LSB/rightmost ends up in x[0], ie. 64b 0x0123456789ABCDEF split into 4 16b words
 *                                            [0]       [1]       [2]       [3]
 *                              words:        0xCDEF    0x89AB    0x4567    0x0123
 *
 * In a little-endian machine with ascending memory addresses ------>
 *                              bytes:        0xEF 0xCD 0xAB 0x89 0x67 0x45 0x23 0x01 
 *                              16b words:    0xCDEF    0x89AB    0x4567    0x0123
 *                              32b words:    0x89ABCDEF          0x01234567
 *                              64b word:     0x0123456789ABCDEF
 *
 * So if the n-bit word is sourced from a little-endian machine, then the order of v-bit subwords is in _descending_ order of memory
 * address, which is probably not what is wanted.
 *
 * The CAPI world works in increments of big-endian 512b half-lines. In this instance where the transfer granularity is less than
 * 512b, then an endian swap on the 512b word will sort out both the subword order, and the subword endianness.
 *
 */


// addrT:       Address type (same on both sides)
// groupDataT:  The grouped address type
// nBanks:      Number of banks
// dataT:       The individual BRAM data type

interface BRAMPortGroup#(type addrT,type groupDataT,numeric type n,type dataT);
    interface BRAMPortStall#(addrT,groupDataT)          grouped;
    interface Vector#(n,BRAMPortStall#(addrT,dataT))    individual;

    method Action                                       enableGrouped(Bool en);
endinterface

function PipeOut#(t) gatePipeOut(Bool pred,PipeOut#(t) p) = interface PipeOut;
    method Action deq if (pred) = p.deq;
    method t first if (pred) = p.first;
    method Bool notEmpty = pred && p.notEmpty;
endinterface;


module mkBRAMGroup#(Vector#(n,BRAMPortStall#(UInt#(nbAddr),dataT)) br)
    (BRAMPortGroup#(UInt#(nbAddr),Bit#(w),n,dataT))
    provisos (
        Mul#(v,n,w),                // determine padded bit size
        Bits#(dataT,nbData),
        Add#(nbData,nbPad,v),

        Alias#(UInt#(nbAddr),addrT)
    );

    Reg#(Bool)      enGroup         <- mkReg(False);

    // split/join group data,ie convert Bit#(w) <-> Vector#(n,dataT)
    function Vector#(n,dataT) splitGroupData(Bit#(w) b);
        Vector#(n,Bit#(v)) bv = unpack(b);
        return map(compose(unpack,truncate),bv);
    endfunction

    function Bit#(w) joinGroupData(Vector#(n,dataT) v);
        Vector#(n,Bit#(v)) bv = map(compose(extend,pack), v);
        return pack(bv);
    endfunction

    // implement individual accesses by gating
    Vector#(nBanks,BRAMPortStall#(addrT,dataT)) indiv;
    for(Integer i=0;i<valueOf(nBanks);i=i+1)
        indiv[i] = interface BRAMPortStall;
            method Action putcmd(Bool wr,addrT addr,dataT data) if (!enGroup) = br[i].putcmd(wr,addr,data);
            method Action clear if (!enGroup) = br[i].clear;

            interface PipeOut readdata = gatePipeOut(!enGroup, br[i].readdata);
        endinterface;

    // all block RAM should be ready at the same time in group mode (depend on this in notEmpty below)
    for(Integer i=1;i<valueOf(n);i=i+1)
        continuousAssert(!enGroup || br[i].readdata.notEmpty == br[0].readdata.notEmpty,"notEmpty mismatch in grouped mode");

    // helper functions for mapping actions over block ram ports
    function Action doPutCmd(Bool wr,a addr,d data,BRAMPortStall#(a,d) _br) = _br.putcmd(wr,addr,data);
    function Action doClear(BRAMPortStall#(a,d) _br) = _br.clear;
    function Action doDeq(BRAMPortStall#(a,d) _br) = _br.readdata.deq;
    function d      getFirst(BRAMPortStall#(a,d) _br) = _br.readdata.first;

    interface Vector individual = indiv;

    interface BRAMPortStall grouped;
        method Action putcmd(Bool wr,addrT addr,Bit#(w) data) if (enGroup)
            = zipWithM_(doPutCmd(wr,truncate(addr)),splitGroupData(data),br);

        method Action clear if (enGroup) = mapM_(doClear, br);

        interface PipeOut readdata;
            method Action deq if (enGroup) = mapM_(doDeq, br);
            method Bit#(w) first if (enGroup) = joinGroupData(map(getFirst,br));
            method Bool notEmpty = enGroup && br[0].readdata.notEmpty;
        endinterface
    endinterface

    method Action enableGrouped(Bool en) = enGroup._write(en);
endmodule

endpackage
