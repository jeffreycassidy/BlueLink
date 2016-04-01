package Test_AlteraM20k;

import Vector::*;
import StmtFSM::*;
import PAClib::*;
import PAClibx::*;
import ClientServer::*;
import GetPut::*;

import AlteraM20k::*;
import LFSR::*;



/** Test the PipeOut wrapper with Altera M20k code. It sends a sequence of read and write commands, randomly gates the output
 * pipe, and logs the output. Should exercise all of the stall functionality.
 */

module mkTest_M20kPipe();
    // output file logging
    Reg#(File) stimfh <- mkReg(InvalidFile), ofh <- mkReg(InvalidFile);



    // stimulus input
    Vector#(2,RWire#(Tuple2#(UInt#(4),MemRequest#(Bit#(32))))) rwi <- replicateM(mkRWire);

    LFSR#(Bit#(32)) rng <- mkLFSR_32;



    // Tap the commands going into the DUT and write them to a file
    function Action writeCommand(File fh,Integer portno,Tuple2#(UInt#(4),MemRequest#(Bit#(32))) t) = action
        let { addr, req } = t;
        $fwrite(fh,"%d P%1d ",$time,portno);
        case(req) matches
            tagged Read: $fdisplay(fh,"R %x",addr);
            tagged Write .data: $fdisplay(fh,"W %x %x",addr,data);
        endcase
    endaction;

    let reqAT <- mkTap(writeCommand(stimfh,0),f_RWire_to_PipeOut(rwi[0]));
    let reqBT <- mkTap(writeCommand(stimfh,1),f_RWire_to_PipeOut(rwi[1]));



    // The DUT
    let br <- mkBRAM2Stall(16);
    let portA <- mkBRAMPortPipeOut(br.a, reqAT);
    let portB <- mkBRAMPortPipeOut(br.b, reqBT);

    Reg#(UInt#(16)) ctr <- mkReg(0);

    Reg#(Bool) enA <- mkReg(True), enB <- mkReg(True);


    Stmt stim = seq
        action
            let t <- $fopen("m20k.stim.txt","w");
            stimfh <= t;

            let u <- $fopen("m20k.out.txt","w");
            ofh <= u;
        endaction
        ctr <= 0;

        while(ctr < 16)
        action
            rwi[0].wset(tuple2(truncate(ctr),  tagged Write (32'habcd0000 | extend(pack(ctr)))));
            rwi[1].wset(tuple2(truncate(ctr+1),tagged Write (32'habcd0000 | extend(pack(ctr+1)))));
            ctr <= ctr+2;
        endaction

        ctr <= 0;

        while(ctr < 16)
        action
            ctr <= ctr+1;
            rwi[0].wset(tuple2(truncate(ctr),Read));
            rwi[1].wset(tuple2(truncate(15-ctr),Read));
            enA <= (ctr != 8);                          // block port A deq when ctr==8, see what happens (should hold 8)
        endaction


        // mixed RDW cases
        action
            rwi[0].wset(tuple2(0,Read));
            rwi[1].wset(tuple2(0,tagged Write 32'hdeadbeef));
        endaction

        rwi[0].wset(tuple2(0,Read));
        rwi[0].wset(tuple2(0,Read));

        action
            rwi[0].wset(tuple2(1,tagged Write 32'hdeadb00f));
            rwi[1].wset(tuple2(1,Read));
        endaction

        rwi[1].wset(tuple2(1,Read));
        rwi[1].wset(tuple2(1,Read));

        // same-port RDW cases
        rwi[1].wset(tuple2(2,tagged Write 32'h01234567));
        rwi[1].wset(tuple2(2,Read));
        rwi[1].wset(tuple2(2,Read));

        rwi[0].wset(tuple2(3,tagged Write 32'h89abcdef));
        rwi[0].wset(tuple2(3,Read));
        rwi[0].wset(tuple2(3,Read));

        repeat(10) noAction;

        // accept drain output randomly
        repeat(10000)
        action
            let rnd = rng.value;
            rng.next;
            enA <= rnd[0]==1'b0 && rnd[1]==1'b0;
            enB <= rnd[1]==1'b0 && rnd[2]==1'b0;
        endaction

        enA <= True;
        enB <= True;

        repeat(1000) noAction;

        repeat(10) noAction;
    endseq;

    // display output to console
    function Action showPort(String s,Bit#(32) i) = $display($time," INFO: Port %s output %X",s,i);

    let portAT <- mkTap(showPort("A"),gatePipeOut(enA,portA));
    let portBT <- mkTap(showPort("B"),gatePipeOut(enB,portB));

    // save the output to a file
    function Action saveOutput(File fh,Integer portno,Bit#(32) data);
        $fdisplay(fh,"%d P%1d %x",$time,portno,data);
    endfunction

    mkSink_to_fa(saveOutput(ofh,0),portAT);
    mkSink_to_fa(saveOutput(ofh,1),portBT);

    mkAutoFSM(stim);
endmodule

endpackage
