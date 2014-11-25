package Test_Parity;

// A very quick test of the Parity/ParityStruct typeclasses for odd parity and byte-wise odd parity

import Parity::*;
import StmtFSM::*;
import Vector::*;

typedef DataWithParity#(Bit#(64),WordWiseParity#(8,OddParity)) ByteWiseOddParity;

module mkTB();
    function Action testParity(parity_struct_t ps)
        provisos (ParityStruct#(data_t,parity_struct_t),FShow#(parity_struct_t),FShow#(data_t));

        return action
            data_t data = ignore_parity(ps);
            parity_struct_t right = parity_calc(data);

            $display("Supplied ",fshow(ps));
            $display("  parity_ok(",fshow(ps),")=",fshow(parity_ok(ps)));
            $display("  parity_maybe(",fshow(ps),")=",fshow(parity_maybe(True,ps)));
            $display(" parity_calc(",fshow(data),")=",fshow(right), " should always be OK");
            $display(" ignore_parity(",fshow(ps),")=",fshow(data));
            $display;
        endaction;
    endfunction


    Stmt stmt = seq
        $display("***** OddParity *****");
        $write("good: ");
        testParity(DataWithParity { data: 8'h00, parityval: OddParity'(1) });
        $write("good: ");
        testParity(DataWithParity { data: 8'h01, parityval: OddParity'(0) });
        $write("bad:  ");
        testParity(DataWithParity { data: 8'h00, parityval: OddParity'(0) });

        $display("***** ByteWiseOddParity *****");

//        testParity(ParityStruct{data:16'h0001,parity:OddParity{pbit:1'b0}});
//        testParity(ParityStruct{data:16'h0001,parity:OddParity{pbit:1'b1}});
//        testParity(ParityStruct{data:16'hffff,parity:OddParity{pbit:1'b0}});
//        testParity(ParityStruct{data:16'hf0f0,parity:OddParity{pbit:1'b0}});
//        testParity(ParityStruct{data:16'hf0f1,parity:OddParity{pbit:1'b0}});

        testParity(ByteWiseOddParity { data: Bit#(64)'(64'h0001020304050607),
            parityval: WordWiseParity#(8,OddParity)'(unpack(8'b01101001)) });   // NOTE: BSV vectors unpack with LSB = v[0] so this
                                                                                // looks backwards wrt. standard MSB-first notation

    endseq;

    mkAutoFSM(stmt);
endmodule

endpackage
