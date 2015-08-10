package ShiftRegUnfunnel;

import Vector::*;
import PAClib::*;

typedef enum { Left, Right } ShiftDirection deriving(Eq);

/** Similar to mkUnfunnel, but:
 *      works on bits instead of vectors of t
 *      allows choice of direction (Left -> values shift to the left so first value in goes to MSB)
 *      synthesizes to a set of regs instead of an MLAB, which greatly reduces input-wire fanout
 */

module mkShiftRegUnfunnel#(ShiftDirection dir,PipeOut#(Bit#(n)) pi)(PipeOut#(Bit#(m)))
    provisos (Mul#(n,k,m),Log#(k,l),Add#(1,__some,k));

    Reg#(Vector#(k,Bool))  valid[2]  <- mkCReg(2,replicate(False));
    Reg#(Vector#(k,Bit#(n))) data[2] <- mkCReg(2,replicate(0));

    rule getAndEnq if (!last(valid[1]));
        pi.deq;
        data[1]  <= shiftInAt0(data[1],pi.first);
        valid[1] <= shiftInAt0(valid[1],True);
    endrule

    method Action deq if (last(valid[0]));
        valid[0] <= replicate(False);
        data[0]  <= replicate(0);
    endmethod

    method Bool     notEmpty = last(valid[0]);
    method Bit#(m)  first if (last(valid[0])) = pack(dir == Right ? reverse(data[0]) : data[0]);
endmodule

endpackage
