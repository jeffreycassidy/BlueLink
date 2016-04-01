import BRAM::*;
import BRAMStall::*;
import AlteraM20k::*;

import Assert::*;
import StmtFSM::*;

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

module mkTB_Basic();

    FIFOF#(BRAMRequest#(UInt#(16),Bit#(32))) aIn <- mkBypassFIFOF, bIn <- mkBypassFIFOF;

    // the barebones RAM instance
    BRAM_DUAL_PORT_Stall#(UInt#(16),Bit#(32)) ram <- mkBRAM2Stall(256);

    // the server wrapper
    let wrapa <- mkBRAMStallWrapper(ram.a);
    let wrapb <- mkBRAMStallWrapper(ram.b);
    BRAM2Port#(UInt#(16),Bit#(32)) dut = interface BRAM2Port;
        interface BRAMServer portA = wrapa;
        interface BRAMServer portB = wrapb;
        method Action portAClear = noAction;
        method Action portBClear = noAction;
    endinterface;

    function BRAMRequest#(UInt#(16),Bit#(32)) readCmd(UInt#(16) addr) = BRAMRequest { write: False, responseOnWrite: False, datain: ?, address: addr };
    function BRAMRequest#(UInt#(16),Bit#(32)) writeCmd(UInt#(16) addr,Bit#(32) data) = BRAMRequest { write: True, responseOnWrite: False, datain: data, address: addr };

    Stmt stim = seq
        action
            aIn.enq(readCmd(0));
            bIn.enq(readCmd(0));
        endaction

        action
            aIn.enq(readCmd(1));
            bIn.enq(readCmd(1));
        endaction

        action
            aIn.enq(readCmd(2));
            bIn.enq(readCmd(2));
        endaction

        repeat(10) noAction;

        action
            let i <- dut.portA.response.get;
        endaction

        action
            let j <- dut.portB.response.get;
        endaction

        repeat(10) noAction;
    endseq;

    (* preempts = "portA,stallA" *)
    rule portA;
        aIn.deq;
        dut.portA.request.put(aIn.first);

        if (aIn.first.write)
            $display($time," A: write %08X to %08X",aIn.first.datain,aIn.first.address);
        else
            $display($time," A: read from %08X",aIn.first.address);
    endrule

    rule stallA if (aIn.notEmpty);
        $display($time," Port A stalled");
    endrule

    (* preempts = "portB,stallB" *)
    rule portB;
        bIn.deq;
        dut.portB.request.put(bIn.first);
        if (bIn.first.write)
            $display($time," B: write %08X to %08X",bIn.first.datain,bIn.first.address);
        else
            $display($time," B: read from %08X",bIn.first.address);
    endrule

    rule stallB if (bIn.notEmpty);
        $display($time," Port B stalled");
    endrule

    mkAutoFSM(stim);
    
endmodule
