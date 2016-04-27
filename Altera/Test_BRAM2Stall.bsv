package Test_BRAM2Stall;

import Assert::*;
import StmtFSM::*;
import BRAMStall::*;
import PAClib::*;
import AlteraM20k::*;


module mkTB_BRAM2Stall()
    provisos (
        Alias#(UInt#(16),addrT),
        Alias#(UInt#(32),dataT));

    RWire#(dataT) readDataA <- mkRWire, readDataB <- mkRWire;
    Reg#(Maybe#(dataT)) expectDataA <- mkReg(tagged Invalid), expectDataB <- mkReg(tagged Invalid);

    BRAM2PortStall#(addrT,dataT) dut <- mkBRAM2Stall(256);

    function Action sendWrite(String pfx,BRAMPortStall#(addrT,dataT) br,addrT addr,dataT data) = action
        $display($time," ",pfx," write address %04X with data %08X",addr,data);
        br.putcmd(True,addr,data);
    endaction;

    function Action sendWriteA(addrT addr,dataT data) = sendWrite("Port A",dut.porta,addr,data);
    function Action sendWriteB(addrT addr,dataT data) = sendWrite("Port B",dut.portb,addr,data);

    function Action sendRead(String pfx,BRAMPortStall#(addrT,dataT) br,addrT addr) = action
        $display($time," ",pfx,"  read address %04X",addr);
        br.putcmd(False,addr,?);
    endaction;

    function Action sendReadA(addrT addr) = sendRead("Port A",dut.porta,addr);
    function Action sendReadB(addrT addr) = sendRead("Port B",dut.portb,addr);

    function Action sendDeq(String pfx,BRAMPortStall#(addrT,dataT) br) = action
        $display($time," ",pfx," Deq");
        br.readdata.deq;
    endaction;

    Action sendDeqA = sendDeq("Port A",dut.porta);
    Action sendDeqB = sendDeq("Port B",dut.portb);


    Stmt stim = seq
        $display(" === Super simple ===");

        action  
            sendWriteA(0,32'hffff0000);
            sendWriteB(1,32'hffff0001);
        endaction
        
        action
            sendWriteA(2,32'hffff0002);
            sendWriteB(3,32'hffff0003);
        endaction

        action
            sendReadA(3);
            sendReadB(2);
        endaction

        action
            expectDataA <= tagged Valid 32'hffff0003;
            expectDataB <= tagged Valid 32'hffff0002;
        endaction

        action
            sendDeqA;
            expectDataA <= tagged Invalid;
        endaction

        action
            sendDeqB;
            expectDataB <= tagged Invalid;
        endaction

        $display(" === Mixed-port write during read stall ===");

        action
            sendReadA(3);
        endaction

        action
            expectDataA <= tagged Valid 32'hffff0003;
            sendWriteB(3,32'hdeadbeef);
        endaction

        sendReadA(3);
        noAction;

        action
            sendDeqA;
            expectDataA <= tagged Valid 32'hdeadbeef;
        endaction

        // writes OK even with read data in the pipeline
        sendWriteA(0,32'h0);
        sendWriteA(1,32'h0);
        sendWriteA(2,32'h0);
        sendWriteA(3,32'h0);

        action
            expectDataA <= tagged Invalid;
            sendDeqA;
        endaction

        repeat(10) noAction;
        $display($time," **** Finished ****");
    endseq;

    rule peekA;
        readDataA.wset(dut.porta.readdata.first);
        $display($time," A: %016X",dut.porta.readdata.first);
    endrule

    rule peekB;
        readDataB.wset(dut.portb.readdata.first);
        $display($time," B: %016X",dut.portb.readdata.first);
    endrule



    // Check that timing and values match
    function Action compare(String pfx,Maybe#(t) expected,Maybe#(t) actual)
        provisos (Eq#(t)) = action
        if (expected matches tagged Valid .e)
        begin
            dynamicAssert(isValid(actual),pfx+": Missing expected output");
            dynamicAssert(e == actual.Valid,pfx+": Value mismatch");
        end
        else
            dynamicAssert(!isValid(actual),pfx+": Unexpected output");
    endaction;

    (* fire_when_enabled,no_implicit_conditions *)
    rule check;
        compare("Port A",expectDataA,readDataA.wget);
        compare("Port B",expectDataB,readDataB.wget);
    endrule

    // Check that notEmpty and .first conditions agree
    continuousAssert(isValid(readDataB.wget) == dut.portb.readdata.notEmpty,"Port B: Mismatch between notEmpty and .first implicit condition");
    continuousAssert(isValid(readDataA.wget) == dut.porta.readdata.notEmpty,"Port A: Mismatch between notEmpty and .first implicit condition");

    mkAutoFSM(stim);
endmodule

endpackage
