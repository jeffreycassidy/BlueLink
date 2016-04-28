package Test_BRAMGroup_CAPI;

import Assert::*;
import MMIO::*;
import BlockMapAFU::*;

import AFU::*;
import AFUHardware::*;
import AFUShims::*;
import DedicatedAFU::*;
import Endianness::*;

import Vector::*;
import BRAMStall::*;
import AlteraM20k::*;
import MemScanChain::*;

import PAClib::*;
import StmtFSM::*;

import FIFOF::*;

import ProgrammableLUT::*;

import HList::*;
import ModuleContext::*;

module mkBlockRAMAdapter(
    Tuple2#(
        BRAMPortGroup#(offsT,Bit#(512),nBanks,dataT),
        BlockMapAFU#(Bit#(512),Bit#(512))))
    provisos (
        Mul#(nbData,nBanks,512),
        NumAlias#(8,nBanks),
        NumAlias#(2048,bankDepth),
        Log#(bankDepth,nbOffs),
        Add#(nbOffs,4,nbAddr),
        Alias#(UInt#(nbAddr),addrT),
        Alias#(UInt#(nbOffs),offsT),
        Alias#(UInt#(nbData),dataT)
    );

    FIFOF#(Bit#(64)) mmResp <- mkFIFOF1;

    FIFOF#(Bit#(512)) iFifo <- mkLFIFOF;
    FIFOF#(Bit#(512)) oFifo <- mkFIFOF;

    Reg#(addrT) ctr <- mkReg(0);

    Vector#(8,BRAM2PortStall#(offsT,dataT)) br <- replicateM(mkBRAM2Stall(valueOf(bankDepth)));

    BRAMPortGroup#(offsT,Bit#(512),nBanks,dataT) g <- mkBRAMGroup(map(portA,br));

    rule consumeInput;
        iFifo.deq;
        ctr <= ctr+1;
        g.grouped.putcmd(True,truncate(ctr),endianSwap(iFifo.first));
    endrule

    return tuple2(
    g,
    interface BlockMapAFU;
        interface Server stream;
            interface Put request = toPut(iFifo);
            interface Get response = toGet(oFifo);
        endinterface
    
        interface Server mmio;
            interface Put request;
                method Action put(MMIORWRequest req);
                    mmResp.enq(64'h0);
                endmethod
            endinterface
    
            interface Get response = toGet(mmResp);
        endinterface
    endinterface
    );

endmodule



(*clock_prefix="ha_pclock"*)
module [Module] mkBRAMGroupCAPI(AFUHardware#(2));

    let syn = hCons(MemSynthesisStrategy'(AlteraStratixV),hNil);

    let { brg, testAFU } <- mkBlockRAMAdapter;

    let { ctx2, dut } <- runWithContext(syn, mkBlockMapAFU(16,8,testAFU));
    let afu <- mkDedicatedAFU(dut);

    Stmt master = seq
        brg.enableGrouped(True);
        await(afu.status.jrunning);

        await(afu.status.jdone);

        brg.enableGrouped(False);

        action
            for(Integer i=0;i<8;i=i+1)
                brg.individual[i].putcmd(False,0,?);
        endaction

        action
            for(Integer i=0;i<8;i=i+1)
            begin
                $display("Address %08X RAM %02X: %016X",0,i,brg.individual[i].readdata.first);
                dynamicAssert(brg.individual[i].readdata.first == (64'hff00000000000000 | fromInteger(i)),"Unexpected read value");
            end
        endaction
    endseq;

    let masterfsm <- mkFSM(master);

    rule startOnce;
        masterfsm.start;
    endrule

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(afuParityWrapper(afu));
    return hw;
endmodule

endpackage
