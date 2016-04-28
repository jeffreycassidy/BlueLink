package Test_MemScanChain;

import GetPut::*;
import MemScanChain::*;
import AlteraM20k::*;
import BRAMStall::*;

import StmtFSM::*;
import Vector::*;

import FIFOF::*;

import Assert::*;
import PAClib::*;

import BDPIDevice::*;
import BDPIPort::*;

import "BDPI" function Action bdpi_initMemScanChainTest;

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
        Alias#(dataT,UInt#(ndata))
    );

    BDPIDevice dev <- mkBDPIDevice(
        bdpi_initMemScanChainTest,
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
        $display("Passthrough data");
        out.write(tagged Response 32'hdeadbeef);
        $display("Read request");
        out.write(tagged Request tuple2(255,Read));
        $display("Write request");
        out.write(tagged Request tuple2(255,tagged Write 32'hdeadb00f));

        await(stim.done);

        repeat(10) noAction;
        dev.close;
    endseq;

    // sink output back to testbench

    mkSink_to_fa(out.write, dut);

    mkAutoFSM(master);
endmodule

endpackage
