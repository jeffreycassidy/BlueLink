package Endian;

import StmtFSM::*;
import Vector::*;

typedef struct {
    Bit#(64) a64;
    Bit#(32) b32;
    Bit#(32) c32;
} Foo deriving (Bits);

module mkEndianPrinter();

    Bit#(128) b = 128'h0001020304050608090a0b0c0d0e0f;
    
    Stmt stim = seq
        $display("As bit vector: %32X",b);
        $display;
        
        action
            Vector#(2,Bit#(64)) p = unpack(b);
            $display("As two 64b vectors: p[1]=%32X",p[1]);
            $display("                    p[0]=%32X",p[0]);
            $display("Vectors are stored with highest index at MSB");
            $display;
        endaction

        action
            Foo t = unpack(b);
            $display("As struct: a64=%16X b32=%8X c32=%8X",t.a64,t.b32,t.c32);
            $display("Structs are stored with first element at MSB");
            $display;
        endaction

        action
            Tuple2#(Bit#(64),Bit#(64)) t = unpack(b);
            $display("As Tuple2#(Bit#(64),Bit#(64)): first=%16X, second=%16X",tpl_1(t),tpl_2(t));
            $display("Tuples are stored with the first element at MSB");
            $display;
        endaction
        
        
    endseq;

    mkAutoFSM(stim);

endmodule

endpackage
