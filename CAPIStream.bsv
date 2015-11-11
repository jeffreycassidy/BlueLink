package CAPIStream;

import Common::*;

import Assert::*;
import GetPut::*;
import RevertingVirtualReg::*;

// transfer parameters
Integer cacheLineBytes      	= 128;                          // 128B = 1024b requires 7 address bits
Integer transferBytes       	= 64;         					// 512/8 = 64
Integer transfersPerCacheLine	= cacheLineBytes/transferBytes;	// 128/64 = 2

typedef Bit#(1024) CacheLine;

interface StreamControl;
    method Action   start(UInt#(64) ea,UInt#(64) size);

    (* always_ready *)
    method Bool     done;

	method Action 	abort;
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
                dynamicAssert(ea0  % fromInteger(cacheLineBytes) == 0,  "Effective address is not properly aligned");
                dynamicAssert(size % fromInteger(cacheLineBytes) == 0,  "Transfer size is not properly aligned");
            endmethod
        
            method Bool done = ea==eaEnd;
        endinterface
        ,
        interface Get;
            method ActionValue#(UInt#(64)) get if (ea != eaEnd);     // force schedule after start
                ea <= ea + fromInteger(cacheLineBytes);
                return ea;
            endmethod
        endinterface
    );

endmodule



typedef enum {
    Done,
    RequestIssued,
    Flushed,
    Draining
} TagStatus deriving(Bits,Eq,FShow);


interface TagStatusIfc;
    method Action complete;
    method Action flush;
    method Action drain;
    method Action issue;

    method Action reissue;          // mark as reissued (Flushed -> Done)

    interface ReadOnly#(TagStatus) current;
endinterface

module mkTagStatus(TagStatusIfc);
    Reg#(TagStatus) st[3] <- mkCReg(3,Done);

    // allowable transitions:
    //  Done -> RequestIssued
    //  RequestIssued -> Done
    //  RequestIssued -> Draining
    //  RequestIssued -> Flushed
    //  Flushed -> RequestIssued
    //  Flushed -> Draining

    let pwIssue <- mkPulseWire, pwDrain <- mkPulseWire, pwFlush <- mkPulseWire, pwComplete <- mkPulseWire;
    let pwReissue <- mkPulseWire;

	function Action onBadTransition(TagStatus st0,TagStatus st) = action
		$display($time," ERROR: mkTagStatus received unexpected transition (",fshow(st0)," -> ",fshow(st),")");
		dynamicAssert(False,"mkTagStatus: invalid transition");
	endaction;


    (* mutually_exclusive="doComplete,doFlush" *)       // command will receive only a single response: completed or flushed

    rule doComplete if (pwComplete);
        if (st[0] != RequestIssued)
			onBadTransition(st[0],Done);
        st[0] <= Done;
    endrule

    (* mutually_exclusive="doReissue,(doComplete,doFlush,doIssue,doDrain)" *)
    rule doReissue if (pwReissue);
        if (st[1] != Flushed)
            onBadTransition(st[1],Done);
    endrule


    (* mutually_exclusive="doFlush,doIssue" *)          // flush implies read already issued

    rule doFlush if (pwFlush);
        if (st[0] == Flushed)
             $display($time," WARNING: Second flushed response received");
        else if (st[0] != RequestIssued)
			onBadTransition(st[0],Flushed);
        st[0] <= Flushed;
    endrule

    rule doIssue if (pwIssue);
        if (st[1] != Done && st[1] != Flushed)
			onBadTransition(st[1],RequestIssued);
        st[1] <= RequestIssued;
    endrule

    // can drain from any state
    rule doDrain if (pwDrain);
        st[2] <= case (st[2]) matches
            RequestIssued:	Draining;
            Flushed:        Done;
            Done:           Done;
            Draining:       Draining;
        endcase;
    endrule


    method Action flush     = pwFlush.send;
    method Action complete  = pwComplete.send;
    method Action drain     = pwDrain.send;
    method Action issue     = pwIssue.send;

    method Action reissue   = pwReissue.send;

    interface ReadOnly current = regToReadOnly(st[0]);
endmodule

instance Readable#(TagStatusIfc,TagStatus);
	function TagStatus read(TagStatusIfc ifc) = ifc.current._read;
endinstance

endpackage
