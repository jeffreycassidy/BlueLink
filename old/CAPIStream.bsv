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

interface StreamControl#(type addrT);
    method Action   start(addrT ea,addrT size);

    (* always_ready *)
    method Bool     done;

	method Action 	abort;
endinterface




interface StreamAddressGen#(type addrT);
	interface StreamControl#(addrT) ctrl;
	interface Get#(addrT)			next;
endinterface

module mkStreamAddressGen#(Integer stride)(StreamAddressGen#(UInt#(na)));
	// control regs
    Reg#(UInt#(na)) ea    	<- mkReg(0);
    Reg#(UInt#(na)) eaLast	<- mkReg(0);

	Reg#(Bool)		eaDone	<- mkReg(True);

	let pwCount <- mkPulseWire;
	let wStart <- mkWire;

	(* preempts="startNew,upCount" *)

	rule startNew if (wStart matches { .ea0, .size });
		ea      <= ea0;
       	eaLast	<= ea0+size-fromInteger(stride);

		eaDone	<= size == 0;
	endrule

	rule upCount if (pwCount);
		ea <= ea + fromInteger(stride);

		if (ea == eaLast)
			eaDone <= True;
	endrule

    interface StreamControl ctrl;
        method Action start(UInt#(na) ea0,UInt#(na) size);
            // check request valid
            dynamicAssert(ea0  % fromInteger(stride) == 0,  "Effective address is not properly aligned");
            dynamicAssert(size % fromInteger(stride) == 0,  "Transfer size is not properly aligned");

			wStart <= tuple2(ea0,size);
        endmethod

		method Action abort = wStart._write(tuple2(0,0));
    
        method Bool done = eaDone;
    endinterface

    interface Get next;
        method ActionValue#(UInt#(na)) get if (!eaDone);
			pwCount.send;
			return ea;
        endmethod
    endinterface

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
