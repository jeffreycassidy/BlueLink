package ShiftRegUnfunnel;

import Vector::*;
import PAClib::*;

typedef enum { Left, Right } ShiftDirection deriving(Eq);

/** Similar to mkUnfunnel, taking k n-bit inputs and sending an m-bit (m=kn) output:
 *      works on bits instead of vectors of t
 *      allows choice of direction (Left -> values shift to the left so first value in goes to MSB)
 *      synthesizes to a set of regs instead of an MLAB, which greatly reduces input-wire fanout
 *
 * When shifting in sequential elements v[j+0], v[j+1], ... v[j+k-1]
 *
 * Right shift: Build big-endian (Bluespec) vector with v[j+0] at right
 * Left  shift: Build little-endian vectors (P8/x86) vectors with v[j+0] at left
 *
 */

module mkShiftRegUnfunnel#(ShiftDirection dir,PipeOut#(Bit#(n)) pi)(PipeOut#(Bit#(m)))
    provisos (Mul#(n,k,m),Log#(k,l),Add#(1,__some,k));

    Reg#(Vector#(k,Maybe#(Bit#(n)))) data[2] <- mkCReg(2,replicate(tagged Invalid));

    function Bit#(n) getValid(Maybe#(Bit#(n)) i) = i.Valid;

    // full if the last element is valid; full at beginning of next cycle if that continues to be the case
    function Bool full     = isValid(dir == Right ? head(data[0]) : last(data[0]));
    function Bool fullNext = isValid(dir == Right ? head(data[1]) : last(data[1]));

    rule getAndEnq if (!fullNext);
        pi.deq;
        data[1]  <= dir == Right ?
            shiftInAtN(data[1],tagged Valid pi.first) : 
            shiftInAt0(data[1],tagged Valid pi.first);
    endrule

    method Action deq if (full);
        data[0] <= replicate(tagged Invalid);
    endmethod

    method Bool     notEmpty = full;
    method Bit#(m)  first if (full) = pack(map(getValid,data[0]));
endmodule

endpackage
