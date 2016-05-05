package CreditIfc;

import PAClib::*;
import CommitIfc::*;
import Vector::*;
import Assert::*;
import Cntrs::*;

typedef struct {
	Integer initCredits;
	Integer maxCredits;
	Bool bypass;
} CreditConfig;

interface CreditManager#(type ctrT);
	method Action take;

	(* always_ready *)
	method Action give;

	(* always_ready *)
	method Action clear;

	(* always_ready *)
	method Bool stall;

	(* always_ready *)
	method ctrT count;
endinterface

module mkCreditManager#(CreditConfig cfg)(CreditManager#(ctrT))
	provisos (
		Arith#(ctrT),
        Bits#(ctrT,nb),
        Ord#(ctrT),
        ModArith#(ctrT),
		Bounded#(ctrT));
	staticAssert(!cfg.bypass, "Credit bypass is not supported");
	staticAssert(fromInteger(cfg.maxCredits) <= ctrT'(maxBound),
		"Counter size is insufficient to hold the specified number of credits");

    Count#(ctrT) credits <- mkCount(fromInteger(cfg.initCredits));

    let pwIncr <- mkPulseWire, pwDecr <- mkPulseWire;

    rule doIncr if (pwIncr);
        credits.incr(1);
    endrule

    rule doDecr if (pwDecr);
        credits.decr(1);
    endrule

	method Action take if (credits > 0) = pwDecr.send;

	method Action give;
//		dynamicAssert(credits < fromInteger(cfg.maxCredits),"Returning more credit than the maximum allowed");
        pwIncr.send;
//        credits.incr(1);
	endmethod

	method ctrT count = credits;
	method Action clear = credits._write(0);
endmodule

//interface NCreditManager#(type ctrT);
//	interface RecvCommit#(ctrT) take;
//
//	method Action 				give(ctrT creditReturn);
//
//	method Action 				clear;
//	method ctrT 				count;
//endinterface
//
//module mkNCreditManager#(CreditConfig cfg)(CreditManager#(ctrT))
//	provisos (
//		Arith#(ctrT),
//		Bounded#(ctrT));
//
//	Wire#(ctrT) creditReturn <- mkWire;
//	Wire#(ctrT) creditRequest <- mkWire;
//	Wire#(ctrT) creditGrant <- mkDWire(0);
//
//	Reg#(ctrT) credits[3] <- mkCReg(3,cfg.initCredits);
//
//	ctrT available = credits[cfg.bypass ? 1 : 0];
//
//	Reg#(ctrT) next = credits[2];
//
//	let pwGrant <- mkPulseWire;
//
//	// depends only on creditReturn
//	rule handleReturn;
//		credits[0] <= credits[0] + creditReturn;
//	endrule
//
//	// may depend on creditReturn (if bypass True, available depends)
//	rule grantIfAvailable(creditRequest <= available);
//		pwGrant.send;
//		creditGrant <= creditRequest;
//	endrule
//
//	// if did this within grantIfAvailable, it would force it to sequence after
//	// handleReturn (credit[1] read after credit[0] write), which is not necessary when bypass is false
//	rule finalUpdate;
//		credits[1] <= credits[1] - creditGrant;	
//	endrule
//
//	interface RecvCommit take;
//		method Action 	datain(ctrT n) = creditRequest._write(n);
//
//		// sequences after datain, and also after give if bypass == True
//		method Bool 	accept = pwGrant;
//	endinterface
//
//	// sequences before accept if bypass == True
//	method Action give(ctrT n) = creditReturn._write(n);
//endmodule




/** Counts the number of of PulseWires in a vector which have been pulsed in a given clock cycle.
 * Intended for use with the credit manager, where there are multiple output return ports that need to be
 * counted and summed.
 */

interface EncodePulses#(numeric type n,type ctrT);
	(* always_ready *)
	interface Vector#(n,Action)     send;

	(* always_ready *)
	method ctrT count;
endinterface

module mkEncodePulses(EncodePulses#(n,UInt#(nb)))
	provisos (
		Log#(TAdd#(1,n),nb));
	
	Vector#(n,PulseWire) pw <- replicateM(mkPulseWire);

	function Bool pwHas(PulseWire _pw) = _pw._read;

	function Action doSend(PulseWire _pw) = _pw.send;

	interface Vector send = map(doSend,pw);
	method UInt#(nb) count = countIf(pwHas,pw);
endmodule

//module mkTakeCredit#(CreditManager#(ctrT) cmgr,PipeOut#(t) pi)(PipeOut#(t));
//	let take <- mkTap(cmgr.take, pi);
//	return take;
//endmodule
//
//module mkGiveCredit#(CreditManager#(ctrT) cmgr,PipeOut#(t) pi)(PipeOut#(t));
//	let give <- mkTap(cmgr.give, pi);
//	return give;
//endmodule

endpackage
