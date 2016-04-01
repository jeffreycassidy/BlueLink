package Test_MemScanChain;

import ClientServer::*;
import GetPut::*;
import MemScanChain::*;
import AlteraM20k::*;

import StmtFSM::*;
import Vector::*;

import SpecialFIFOs::*;
import FIFOF::*;

import Assert::*;
import PAClib::*;
import PAClibxTest::*;

/** Try synthesis of a large scan chain */

// BankDepth    Width       BankCount
// 8k           512         8               270M        4% of ALMs
// 4k           512         16              330M        7% of ALMs

module mkSyn_MemScanChain(Server#(MemItem#(addrT,dataT),dataT))
    provisos (
        NumAlias#(naddr,16),
        NumAlias#(noffs,12),
        Alias#(addrT,UInt#(naddr)),
        Alias#(offsT,UInt#(noffs)),
        Alias#(dataT,Bit#(512))
    );

    // configuration
    Integer nBanks      = 16;
    Integer bankDepth   = 4096;

    // input/output FIFOs to break backpressure links
    FIFOF#(MemItem#(addrT,dataT))   inFifo  <- mkFIFOF;
    FIFOF#(dataT)                   outFifo <- mkFIFOF;

    // The BRAM banks
    function BRAM_PORT_Stall#(offsT,dataT) getPortA(BRAM_DUAL_PORT_Stall#(offsT,dataT) _br) = _br.a;

    List#(BRAM_DUAL_PORT_Stall#(offsT,dataT))   br  <- List::replicateM(nBanks,mkBRAM2Stall(bankDepth));
    List#(BRAM_PORT_SplitRW#(offsT,dataT))      brs <- List::mapM(mkBRAMPortSplitRW, List::map(getPortA,br));


    Vector#(16,PipeOut#(MemItem#(addrT,dataT))) el;

    el[0]  <- mkMemScanChainElement(0, brs[0],f_FIFOF_to_PipeOut(inFifo));
    el[1]  <- mkMemScanChainElement(1, brs[1], el[0] );
    el[2]  <- mkMemScanChainElement(2, brs[2], el[1] );
    el[3]  <- mkMemScanChainElement(3, brs[3], el[2] );
    el[4]  <- mkMemScanChainElement(4, brs[4], el[3] );
    el[5]  <- mkMemScanChainElement(5, brs[5], el[4] );
    el[6]  <- mkMemScanChainElement(6, brs[6], el[5] );
    el[7]  <- mkMemScanChainElement(7, brs[7], el[6] );
    el[8]  <- mkMemScanChainElement(8, brs[8], el[7] );
    el[9]  <- mkMemScanChainElement(9, brs[9], el[8] );
    el[10] <- mkMemScanChainElement(10,brs[10],el[9] );
    el[11] <- mkMemScanChainElement(11,brs[11],el[10]);
    el[12] <- mkMemScanChainElement(12,brs[12],el[11]);
    el[13] <- mkMemScanChainElement(13,brs[13],el[12]);
    el[14] <- mkMemScanChainElement(14,brs[14],el[13]);
    el[15] <- mkMemScanChainElement(15,brs[15],el[14]);


    // Output stage
    rule outStage;
        last(el).deq;

        if (last(el).first matches tagged Response .data)
            outFifo.enq(data);
        else
            dynamicAssert(False,"Request arrived at end of scan chain");
    endrule

    interface Put request  = toPut(inFifo);
    interface Get response = toGet(outFifo);
endmodule

module mkTB_MemScanChainElement_Simple()
    provisos (
        Alias#(addrT,UInt#(16)),
        Alias#(offsT,UInt#(4)),
        Alias#(dataT,Bit#(32))
    );
    // stimulus source (addr, MemRequest)
    PipeOutSourceTest#(Tuple2#(addrT,MemRequest#(dataT))) stim <- mkPipeOutSourceTest;

    function Action send(Tuple2#(addrT,MemRequest#(dataT)) t) = action
        let { addr, req } = t;
        $write($time," SENT: ");
        case (req) matches
            tagged Read:            $display("Read for %X",addr);
            tagged Write .data:     $display("Write value %X to %X",data,addr);
        endcase
    endaction;

    function MemItem#(addrT,dataT) wrapMemRequest(Tuple2#(addrT,MemRequest#(dataT)) t);
        let { addr, req } = t;
        return tagged Request tuple2(addr,req);
    endfunction

    let stimT  <- mkTap(send,stim.pipe);
    let stimTI <- mkFn_to_Pipe(wrapMemRequest,stimT);


    // DUT
    BRAM_DUAL_PORT_Stall#(offsT,dataT) br  <- mkBRAM2Stall(16);       // The block RAM
    let sa <- mkBRAMPortSplitRW(br.a);                                      // Split server interface
    let dut <- mkMemScanChainElement(0,sa,stimTI);                          // The scan-chain interface

    // Status control
    Reg#(Bool) outputEn <- mkReg(True);

    Stmt stimstmt = seq
        $display("Start");
        // do some writes
        stim.provideAssertAccepted(tuple2(0,tagged Write 32'hb00f0000));
        stim.provideAssertAccepted(tuple2(1,tagged Write 32'hb00f0001));
        stim.provideAssertAccepted(tuple2(2,tagged Write 32'hb00f0002));
        stim.provideAssertAccepted(tuple2(3,tagged Write 32'hb00f0003));
        noAction;
        noAction;
        stim.provideAssertAccepted(tuple2(4,tagged Write 32'hb00f0004));
        stim.provideAssertAccepted(tuple2(5,tagged Write 32'hb00f0005));
        stim.provideAssertAccepted(tuple2(6,tagged Write 32'hb00f0006));
        stim.provideAssertAccepted(tuple2(7,tagged Write 32'hb00f0007));
        noAction;
        stim.provideAssertAccepted(tuple2(8,tagged Write 32'hb00f0008));

        // now try reading back in random order
        stim.provideAssertAccepted(tuple2(0,Read));
        stim.provideAssertAccepted(tuple2(1,Read));
        stim.provideAssertAccepted(tuple2(2,Read));
        stim.provideAssertAccepted(tuple2(3,Read));
        stim.provideAssertAccepted(tuple2(4,Read));
        noAction;
        noAction;
        stim.provideAssertAccepted(tuple2(7,Read));
        stim.provideAssertAccepted(tuple2(6,Read));
        stim.provideAssertAccepted(tuple2(8,Read));
        noAction;
        stim.provideAssertAccepted(tuple2(5,Read));

        stim.provideAssertAccepted(tuple2(16,Read));      // this one should pass through


        ////// Testing backpressure for reads

        // allow pipe to drain, disable output
        repeat(6) noAction;
        action
            $display($time," Pipe drained - stopping output deq");
            outputEn <= False;
        endaction


        // fill the pipe back up (2-in FIFO, 2 BR stages, 1 output FIFO)
        stim.provideAssertAccepted(tuple2(0,Read));
        stim.provideAssertAccepted(tuple2(0,Read));
        stim.provideAssertAccepted(tuple2(0,Read));
        stim.provideAssertAccepted(tuple2(0,Read));
        stim.provideAssertAccepted(tuple2(0,Read));

        // check that everything blocks (input FIFO full so writes can't bypass)
        stim.provideAssertNotAccepted(tuple2(0,Read));
        stim.provideAssertNotAccepted(tuple2(0,tagged Write 32'hdeadbeef));
        stim.provideAssertNotAccepted(tuple2(16,Read));

        // drain
        outputEn <= True;
        repeat(10) noAction;
    endseq;

    mkAutoFSM(stimstmt);

    rule showOutput if (outputEn);
        let o = dut.first;
        case (o) matches
            tagged Response .r: $display($time," RECEIVED: Data %X",r);
            tagged Request { .addr, .req }: $display($time," RECEIVED: Passthrough request for address %X",addr);
        endcase
        dut.deq;
    endrule
endmodule

endpackage
