package Test_MemScanChain;

import GetPut::*;
import MemScanChain::*;
import AlteraM20k::*;
import BRAMStall::*;

import ClientServer::*;

import StmtFSM::*;
import Vector::*;

import FIFOF::*;

import Assert::*;
import PAClib::*;

import BDPIDevice::*;
import BDPIPort::*;

//import "BDPI" function Action bdpi_initMemScanChainTest;

function PipeOut#(t) gatePipeOut(Bool pred,PipeOut#(t) p) = interface PipeOut;
    method Bool notEmpty = pred && p.notEmpty;
    method Action deq if (pred) = p.deq;
    method t first if (pred) = p.first;
endinterface;

module mkTB_MSC_SW()
    provisos (
        NumAlias#(naddr,16),
        NumAlias#(ndata,32),
        Alias#(addrT,UInt#(naddr)),
        Alias#(dataT,Bit#(ndata))
    );

    BDPIDevice dev <- mkBDPIDevice(
        noAction,
//        bdpi_initMemScanChainTest,
        bdpi_createDeviceFromFactory("MemScanChainTest","foobar",32'h0),
        True);

    BDPIPortPipe#(MemItem#(addrT,dataT))  stim <- mkBDPIPortPipe(dev,0,constFn(noAction));
    BDPIPort#(void,MemItem#(addrT,dataT)) out  <- mkBDPIPort(dev,1,constFn(noAction));

    BRAM2PortStall#(UInt#(8),dataT) br <- mkBRAM2Stall(256);

    let pwAccept <- mkPulseWire;

    function Action showStim(MemItem#(addrT,dataT) i) = $display($time," Input: ",fshow(i));
    let stimT <- mkTap(showStim,stim.pipe);

    PipeOut#(MemItem#(addrT,dataT)) dut <- mkMemScanChainElement(0,br.porta,gatePipeOut(pwAccept,stimT));

    Stmt master = seq
        while (!stim.done)
            pwAccept.send;

        repeat(10) noAction;
        dev.close;
        $display($time,"That's all folks!");
        $finish;
    endseq;

    // sink output back to testbench

    mkSink_to_fa(out.write, dut);

    mkAutoFSM(master);
endmodule

module mkTB_MemScanChain4x64()
    provisos (
        NumAlias#(nBRAM,4),
        NumAlias#(naddr,16),
        NumAlias#(bramDepth,64),
        Log#(bramDepth,bramAddrBits),
        NumAlias#(ndata,32),
        Alias#(addrT,UInt#(naddr)),
        Alias#(offsT,UInt#(bramAddrBits)),
        Alias#(dataT,Bit#(ndata))
    );

    BDPIDevice dev <- mkBDPIDevice(
        noAction,
        bdpi_createDeviceFromFactory("MemScanChainTest","foobar",32'h0),
        True);

    BDPIPortPipe#(MemItem#(addrT,dataT))  stim <- mkBDPIPortPipe(dev,0,constFn(noAction));
    BDPIPort#(void,MemItem#(addrT,dataT)) out  <- mkBDPIPort(dev,1,constFn(noAction));

    let pwAccept <- mkPulseWire;

    function Action showStim(MemItem#(addrT,dataT) i) = $display($time," Input: ",fshow(i));
    let stimT <- mkTap(showStim,stim.pipe);

    Vector#(nBRAM,BRAM2PortStall#(offsT,dataT)) br <- replicateM(mkBRAM2Stall(valueOf(bramDepth)));

    PipeOut#(MemItem#(addrT,dataT)) chain <- mkMemScanChain(map(portA,br),gatePipeOut(pwAccept,stimT));

    

    Stmt master = seq
        while (!stim.done)
            pwAccept.send;

        repeat(10) noAction;
        dev.close;
        $display($time,"That's all folks!");
        $finish;
    endseq;

    // sink output back to testbench

    mkSink_to_fa(out.write, chain);

    mkAutoFSM(master);
endmodule



/** Uses a somewhat goofy argument structure to pass in some type parameters. Values of b,o don't matter; the first argument's
 * bit width is the number of banks and the second is the number of bits in the offset (nbOffs).
 *
 * Each of the (nBanks) banks is 2**(nbOffs) deep for a total depth of nBanks * 2^nbOffs.
 */

module mkSyn_MemScanChain#(Integer depth,UInt#(nBanks) b,UInt#(nbOffs) o)(Server#(MemItem#(UInt#(nbAddr),dataT),MemItem#(UInt#(nbAddr),dataT)))
    provisos (
        Alias#(UInt#(nbOffs),offsT),
        Alias#(UInt#(nbAddr),addrT),
        Add#(1,nonzero,nBanks),
        Log#(nBanks,nbBankIdx),
        Add#(nbOffs,nbBankIdx,nbMinAddr),
        Add#(nbMinAddr,__some,nbAddr),
        Add#(nbOffs,__more,nbAddr),
        Bits#(dataT,nbData)
    );

    Integer bankDepth = 2**valueOf(nbOffs);

    staticAssert(depth == bankDepth * valueOf(nBanks),"nBanks * bankDepth != depth");


    Vector#(nBanks,BRAM2PortStall#(UInt#(nbOffs),dataT)) br <- replicateM(mkBRAM2Stall(bankDepth));

    FIFOF#(MemItem#(addrT,dataT)) iFifo <- mkFIFOF, oFifo <- mkFIFOF;

    let chain <- mkMemScanChain(map(portA,br),f_FIFOF_to_PipeOut(iFifo));
    mkSink_to_fa(oFifo.enq, chain);

    interface Put request = toPut(iFifo);
    interface Get response = toGet(oFifo);
endmodule

function module#(Server#(MemItem#(UInt#(15),Bit#(512)),MemItem#(UInt#(15),Bit#(512)))) mkSyn_MemScanChain_2k_16_512 =
    mkSyn_MemScanChain(32768,16'h0,11'h0);

function module#(Server#(MemItem#(UInt#(16),Bit#(512)),MemItem#(UInt#(16),Bit#(512)))) mkSyn_MemScanChain_4k_16_512 =
    mkSyn_MemScanChain(65536,16'h0,12'h0);

function module#(Server#(MemItem#(UInt#(16),Bit#(512)),MemItem#(UInt#(16),Bit#(512)))) mkSyn_MemScanChain_8k_8_512 =
    mkSyn_MemScanChain(65536,8'h0,13'h0);

endpackage
