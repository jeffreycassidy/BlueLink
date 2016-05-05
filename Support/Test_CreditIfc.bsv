package Test_CreditIfc;

import Assert::*;
import CreditIfc::*;
import StmtFSM::*;
import FIFOF::*;
import Vector::*;

import PAClib::*;

module mkTB_Simple()
    provisos (
        Alias#(dataT,UInt#(16)),
        NumAlias#(d,10));

    Integer credits = 5;
    Integer oFifoSize = 5;

    CreditManager#(UInt#(3)) dut <- mkCreditManager(
        CreditConfig {
            initCredits: credits,
            maxCredits: credits,
            bypass: False });

    FIFOF#(dataT) oFifo <- mkSizedFIFOF(oFifoSize);



    let pwAcceptInputRequired <- mkPulseWire;
    let pwAcceptInputForbidden <- mkPulseWire;
    let pwInputAccepted <- mkPulseWire;

    let pwAcceptDelayOutput <- mkPulseWire;

    let pwOutputRequired <- mkPulseWire;
    let pwOutputForbidden <- mkPulseWire;
    let pwOutputAccepted <- mkPulseWire;

    RWire#(dataT) rwStim <- mkRWire, delayOut <- mkRWire;

    PipeOut#(dataT) stimIn = interface PipeOut;
        method Bool notEmpty = isValid(rwStim.wget);
        method Action deq if (isValid(rwStim.wget)) = pwInputAccepted.send;
        method dataT first if (rwStim.wget matches tagged Valid .v) = v;
    endinterface;

    // gate the stimulus input going into the delay line by taking credits from the manager
    let stim <- mkTap(constFn(dut.take), stimIn);
    RWire#(dataT) iData <- mkRWire;
    mkSink_to_fa(iData.wset, stim);

    continuousAssert(!(pwAcceptInputForbidden && pwInputAccepted),"Accepted input when it should have been forbidden");
    continuousAssert(!(pwAcceptInputRequired && !pwInputAccepted),"Input denied when it should have been accepted");


    // fixed-latency (d) delay line acting as the module being wrapped
    Reg#(Vector#(d,Maybe#(dataT))) delayLine <- mkReg(replicate(tagged Invalid));

    (* fire_when_enabled *)
    rule shiftDelay;
        delayLine <= shiftInAt0(delayLine,iData.wget);
    endrule


    // enq delay line output into a FIFO, assert that it is accepted
    rule enqDelayLineOutput if (last(delayLine) matches tagged Valid .v);
        oFifo.enq(v);
        pwAcceptDelayOutput.send;
    endrule
    continuousAssert(!(isValid(last(delayLine)) && !pwAcceptDelayOutput),"Output FIFO failed to accept delay line output");


    // when requested, try to deq output from FIFO and assert that it succeeded
    rule deqOutput if (pwOutputRequired || pwOutputForbidden);
        oFifo.deq;
        pwOutputAccepted.send;
        dut.give;
        $display($time," Output: %X",oFifo.first);
    endrule

    continuousAssert(!(pwOutputRequired && !pwOutputAccepted),"Required output is missing");
    continuousAssert(!(pwOutputForbidden && pwOutputAccepted),"Unexpected output present");

    function Action requireInputBlock = action
        pwAcceptInputForbidden.send;
        rwStim.wset(?);
        $display($time," Input should be blocked");
    endaction;

    function Action requireInputAccept(dataT i) = action
        pwAcceptInputRequired.send;
        rwStim.wset(i);
        $display($time," Sending ",fshow(i));
    endaction;

    function requireOutputPresent = action
        pwOutputRequired.send;
        $display($time," Deq");
    endaction;

    function requireOutputBlock = action
        pwOutputForbidden.send;
        $display($time," Output should block");
    endaction;


    Stmt stimstmt = seq
        requireInputAccept(0);
        requireInputAccept(1);
        requireInputAccept(2);
        requireInputAccept(3);
        requireInputAccept(4);
        repeat(6)                       // module latency + 1 for FIFO enq
            action
                requireInputBlock;
                requireOutputBlock;
            endaction

        action
            requireInputBlock;
            requireOutputPresent;
        endaction

        action
            requireInputAccept(5);
        endaction

        requireInputBlock;

        repeat(4) requireOutputPresent;
        repeat(5) requireOutputBlock;
        requireOutputPresent;
        requireOutputBlock;

        repeat(10) noAction;

        $display($time," **** DONE ****");
    endseq;

    mkAutoFSM(stimstmt);
endmodule

endpackage
