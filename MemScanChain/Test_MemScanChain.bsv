package Test_MemScanChain;

import GetPut::*;
import MemScanChain::*;
import AlteraM20k::*;

import StmtFSM::*;
import Vector::*;

import FIFOF::*;

import Assert::*;
import PAClib::*;

import BDPIDevice::*;
import BDPIPort::*;

import "BDPI" function Action bdpi_initMemScanChainTest;

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

    Stmt master = seq
        $display("Passthrough data");
        out.write(tagged Response 32'hdeadbeef);
        $display("Read request");
        out.write(tagged Request tuple2(0,Read));
        $display("Write request");
        out.write(tagged Request tuple2(0,tagged Write 32'hdeadb00f));

        repeat(10) noAction;
        dev.close;
    endseq;

    mkAutoFSM(master);
endmodule

endpackage
