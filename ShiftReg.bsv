package ShiftReg;

import Vector::*;
import PAClib::*;
import Cntrs::*;

typedef enum { Left, Right } ShiftDirection deriving(Eq);

/** Similar to mkUnfunnel, taking k n-bit inputs and sending an m-bit (m=kn) output:
 *      works on bits instead of vectors of t
 *      allows choice of direction (Left -> values shift to the left so first value in goes to MSB)
 *      synthesizes to a set of regs instead of an MLAB/mux, which greatly reduces input-wire fanout
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




/** Parallel-load shift register
 * Accepts a Bit#(mk), then shifts out k Bit#(m) elements in the specified direction (Left -> MSB emerges first).
 * 
 * For P8 LE systems, leftmost byte of 128B cache line comes from lowest address. Shift out left gives increasing address stream.
 * Leftmost byte is least significant on little-endian machines, but most significant in BSV's big-endian world therefore needs an
 * endian swap.
 */


module mkShiftRegFunnel#(ShiftDirection dir,PipeOut#(Bit#(mk)) pi)(PipeOut#(Bit#(m)))
    provisos (
        Mul#(m,k,mk),
        Log#(k,nbCtr));

    // status
    Reg#(Bool) empty[2] <- mkCReg(2,True);
    let pwDeq <- mkPulseWire;

    Count#(UInt#(nbCtr)) ctr <- mkCount(0);

    Reg#(Vector#(k,Bit#(m)))  storage <- mkReg(replicate(0));          // elements (0 always emerges first)


    // shift if deq called and elements remain after counter decrement

    (* fire_when_enabled *)
    rule shift if (!empty[1] && pwDeq);
        storage <= shiftInAtN(storage,0);
    endrule



    // pull input if available and would be empty next cycle
    rule getInput if (empty[1]);
        pi.deq;

        Vector#(k,Bit#(m)) b = unpack(pi.first);        // MSB -> v[n-1]

        empty[1] <= False;

        storage <= dir == Left ? 
            reverse(b) :                                // v[0] always emerges first so reverse vector if shifting left
            b;

        ctr <= fromInteger(valueOf(k)-1);
    endrule


    method Bool notEmpty = !empty[0];

    method Bit#(m) first if (!empty[0]) = storage[0];

    method Action deq if (!empty[0]);
        pwDeq.send;
        if (ctr == 0)
            empty[0] <= True;
        else
            ctr.decr(1);
    endmethod
endmodule

endpackage
