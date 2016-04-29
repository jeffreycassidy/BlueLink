package Test_BRAMGroup_CAPI;

import Assert::*;
import MMIO::*;
import BlockMapAFU::*;

import AFU::*;
import AFUHardware::*;
import AFUShims::*;
import DedicatedAFU::*;
import Endianness::*;
import ShiftReg::*;

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

/** Checks block RAM loading using the CAPI interface, using a BlockMapAFU which writes back no output.
 * The expected pattern is a UInt#(64) counter with FF in the top byte and 0..16383 in the lower bytes.
 * The first and last memory elements are read and checked by assertion.
 *
 * BRAM configuration is 8 banks * 2k x 64b -> group side 2k x 512 / individual side 16k x 64b with stride 8
 *
 * Synthesis: 512x40 BRAM -> assume 2 wide (80b) x 4 deep (2k) x 8 banks -> 64 BRAM
 *
 * Host should provide a BlockMapWED with 64kB source and 0B destination.
 */

module mkBlockRAMAdapter(
    Tuple2#(
        BRAMPortGroup#(offsT,Bit#(512),nBanks,dataT),
        BlockMapAFU#(Bit#(512),Bit#(512))))
    provisos (
        Mul#(nbData,nBanks,512),
        NumAlias#(8,nBanks),
        NumAlias#(2048,bankDepth),
        Log#(bankDepth,nbOffs),
        Log#(nBanks,nbBank),
        Add#(nbOffs,nbBank,nbAddr),
        Alias#(UInt#(nbAddr),addrT),
        Alias#(UInt#(nbOffs),offsT),
        Alias#(UInt#(nbData),dataT)
    );

    Bool verbose = False;

    Integer nWords = valueOf(nBanks)*valueOf(bankDepth);

    // MMIO is a no-op
    FIFOF#(Bit#(64)) mmResp <- mkFIFOF1;

    // Input/output buffers
    FIFOF#(Bit#(512)) iFifo <- mkLFIFOF;

    // Status notifications (GFIFOF -> no implicit conditions but assertion check for correct use)
    FIFOF#(void) iDone <- mkGFIFOF1(True,False);
    FIFOF#(void) oDone <- mkGFIFOF1(True,False);

    // BRAM instances and convenience functions for readback
    Vector#(8,BRAM2PortStall#(offsT,dataT)) br <- replicateM(mkBRAM2Stall(valueOf(bankDepth)));

    BRAMPortGroup#(offsT,Bit#(512),nBanks,dataT) g <- mkBRAMGroup(map(portA,br));

    function Action readAll(Integer addr) = action
        for(Integer i=0;i<8;i=i+1)
            g.individual[i].putcmd(False,fromInteger(addr),?);
    endaction;
    
    Action deqAll = action
        for(Integer i=0;i<8;i=i+1)
            g.individual[i].readdata.deq;
    endaction;

    // take input and write it in sequence
    Reg#(addrT) ctr <- mkReg(0);
    Reg#(Bool) inputEnable <- mkReg(False);

    rule consumeInput if (inputEnable);
        iFifo.deq;
        ctr <= ctr+1;
        g.grouped.putcmd(True,truncate(ctr),endianSwap(iFifo.first));
    endrule

    // output writes
    Reg#(UInt#(TAdd#(nbAddr,1))) oReqCtr <- mkReg(0);
    Reg#(UInt#(TAdd#(nbAddr,1))) oRespCtr <- mkReg(0);
    Reg#(Bool) outputEnable <- mkReg(False);

    rule requestOutput if (outputEnable && oReqCtr < fromInteger(nWords));
        oReqCtr <= oReqCtr+1;
        g.individual[oReqCtr % 8].putcmd(False,truncate(oReqCtr >> 3),?);
    endrule

    FIFOF#(dataT) oWord <- mkFIFOF;
    let oWordPack <- mkFn_to_Pipe(pack, f_FIFOF_to_PipeOut(oWord));

    PipeOut#(Bit#(512)) oLine <- mkShiftRegUnfunnel(Right,oWordPack);
    PipeOut#(Bit#(512)) oLineSwapped <- mkFn_to_Pipe(endianSwap, oLine);

    FIFOF#(UInt#(3)) pAccept <- mkFIFOF;

    rule acceptOutput if (outputEnable && oRespCtr < fromInteger(nWords));
        oRespCtr <= oRespCtr+1;
        pAccept.enq(truncate(oRespCtr % 8));
    endrule

    // split from the previous rule because it looks like predicate evaluation on oRespCtr was taking too long
    // to propagate to the BRAMs (big fanout!). The pAccept FIFO effectively registers the predicate evaluation.
    rule doAccept;
        let bk = pAccept.first;
        pAccept.deq;

        let d = g.individual[bk].readdata.first;
        g.individual[bk].readdata.deq;
        oWord.enq(d);

        if (verbose)
           $display($time," INFO: Readback data %016X",d);
    endrule

    Stmt checker = seq
        g.enableGrouped(True);          // delay input to allow multicycle path at group switch
        repeat(2) noAction;
        inputEnable <= True;

        // wait until input stream is done
        action
            iDone.deq;
            $display("Input is done");
        endaction
        inputEnable <= False;

        g.enableGrouped(False);
        repeat(3) noAction;             // allow multicycle path at group switch

        $display($time," INFO: Starting readback assertion checks");

        readAll(0);
        action
            $display($time,"**** Checking first 8 values ****");
            for(Integer i=0;i<8;i=i+1)
            begin
                $display("Address %08X RAM %02X: %016X",0,i,g.individual[i].readdata.first);
                dynamicAssert(g.individual[i].readdata.first == (64'hff00000000000000 | fromInteger(i)),"Unexpected read value");
            end
        endaction
        deqAll;

        readAll(1);
        action
            $display($time,"**** Checking next 8 values ****");
            for(Integer i=0;i<8;i=i+1)
            begin
                $display("Address %08X RAM %02X: %016X",0,i,g.individual[i].readdata.first);
                dynamicAssert(g.individual[i].readdata.first == (64'hff00000000000000 | fromInteger(i+8)),"Unexpected read value");
            end
        endaction
        deqAll;

        readAll(2047);
        action
            $display($time,"**** Checking last 8 values ****");
            for(Integer i=0;i<8;i=i+1)
            begin
                $display("Address %08X RAM %02X: %016X",0,i,g.individual[i].readdata.first);
                dynamicAssert(g.individual[i].readdata.first == (64'hff00000000000000 | fromInteger(i+8*2047)),"Unexpected read value");
            end
        endaction
        deqAll;

        $display($time," INFO: Starting readback copy");

        outputEnable <= True;

        await(oRespCtr == fromInteger(nWords) && !pAccept.notEmpty);

        // NOTE: Outer loop will still wait for ostream to finish before terminating the AFU & possibly causing a reset
    endseq;

    let checkerFSM <- mkFSM(checker);

    rule startOnInput if (iFifo.notEmpty);
        checkerFSM.start;
    endrule

    return tuple2(
    g,
    interface BlockMapAFU;
        interface Server stream;
            interface Put request = toPut(iFifo);
            interface Get response = toGet(oLineSwapped);
        endinterface
    
        interface Server mmio;
            interface Put request;
                method Action put(MMIORWRequest req);
                    mmResp.enq(64'h0);
                endmethod
            endinterface
    
            interface Get response = toGet(mmResp);
        endinterface

        method Bool done = checkerFSM.done;
        method Action istreamDone = iDone.enq(?);
        method Action ostreamDone = oDone.enq(?);
    endinterface
    );

endmodule



(*clock_prefix="ha_pclock"*)
module [Module] mkBRAMGroupCAPI(AFUHardware#(2));

    let syn = hCons(MemSynthesisStrategy'(AlteraStratixV),hNil);

    let { brg, testAFU } <- mkBlockRAMAdapter;

    let { ctx2, dut } <- runWithContext(syn, mkBlockMapAFU(16,8,testAFU));
    let afu <- mkDedicatedAFU(dut);


    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(afuParityWrapper(afu));
    return hw;
endmodule

endpackage
