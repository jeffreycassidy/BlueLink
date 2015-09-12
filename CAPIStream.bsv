package CAPIStream;

import Assert::*;
import GetPut::*;
import RevertingVirtualReg::*;

Integer stepBytes=128;
Integer alignBytes=128;

typedef Bit#(1024) CacheLine;

interface StreamControl;
    method Action   start(UInt#(64) ea,UInt#(64) size);

    (* always_ready *)
    method Bool     done;
endinterface


/** Create a stream counter, which gives a Tuple2#(StreamControl,Get#(UInt#(64)))
 *
 * The StreamControl holds the start and done methods, while Get#() returns the next address in the sequence and bumps the address
 * up. 
 */

module mkStreamCounter(Tuple2#(StreamControl,Get#(UInt#(64))));
	// control regs
    Reg#(UInt#(64)) eaStart   <- mkReg(0);
    Reg#(UInt#(64)) ea        <- mkReg(0);
    Reg#(UInt#(64)) eaEnd     <- mkReg(0);

    return tuple2(
        interface StreamControl;
            method Action start(UInt#(64) ea0,UInt#(64) size);
                eaStart <= ea0;
                ea      <= ea0;
                eaEnd   <= ea0+size;

                // check request valid
                dynamicAssert(ea0  % fromInteger(alignBytes) == 0,  "Effective address is not properly aligned");
                dynamicAssert(size % fromInteger(alignBytes) == 0,  "Transfer size is not properly aligned");
            endmethod
        
            method Bool done = ea==eaEnd;
        endinterface
        ,
        interface Get;
            method ActionValue#(UInt#(64)) get if (ea != eaEnd);     // force schedule after start
                ea <= ea + fromInteger(stepBytes);
                return ea;
            endmethod
        endinterface
    );

endmodule


endpackage
