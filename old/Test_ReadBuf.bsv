package Test_ReadBuf;

import StmtFSM::*;

module mkTB_AFUReadBuf();
    let dut <- mkAFUReadBuf(16);

    function Action test(UInt#(16) a,Bit#(512) d) = action
        RequestTag tag = truncate(a>>1);
        UInt#(6) bwad = truncate(a%2);
        dut.pslin.put(BufferWrite { bwtag: tag, bwad: bwad, bwdata: d });
    endaction;

    Reg#(UInt#(16)) i <- mkReg(0);

    Stmt stim = seq
        test(0, 512'hdeadbeef);
        test(1, 512'hdeadb00f);

        test(3, 512'hbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb);

        test(2, 512'haaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa);

        while(i != 16)
        action
            let t <- dut.lookup(truncate(i));
            let o = pack(t);
            $display("Output[%2d] = %64X",i,o[1023:768]);
            $display("             %64X",o[ 767:512]);
            $display("             %64X",o[ 511:256]);
            $display("             %64X",o[ 255:  0]);
            i <= i+1;
        endaction

        repeat(2) noAction;
    endseq;

    mkAutoFSM(stim);
    
endmodule

endpackage
