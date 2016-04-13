package Stream;

import PSLTypes::*;

interface StreamCtrl;
    method Action start(EAddress64 ea,UInt#(64) nBytes);
    method Bool done;
endinterface

typedef enum { Free, Issued, Complete } BufferSlotStatus deriving(Eq,FShow,Bits);

interface BufStatusIfc;
    method Action issue;
    method Action complete;
    method Action free;

    method Action clear;

    method BufferSlotStatus _read;
endinterface

module mkBufStatus(BufStatusIfc);
    Reg#(BufferSlotStatus) st[2] <- mkCReg(2,Free);

    let pwIssue <- mkPulseWire, pwComplete <- mkPulseWire, pwFree <- mkPulseWire;

    (* mutually_exclusive="doIssue,doComplete,doFree" *)
    rule doIssue if (pwIssue);
        st[0] <= Issued;
    endrule

    rule doComplete if (pwComplete);
        st[0] <= Complete;
    endrule

    rule doFree if (pwFree);
        st[0] <= Free;
    endrule

    method Action clear = st[1]._write(Free);

    method Action issue = pwIssue.send;

    method Action free = pwFree.send;

    method Action complete = pwComplete.send;

    method BufferSlotStatus _read = st[0];
endmodule

function Action clearStatus(BufStatusIfc r) = r.clear;


interface SetReset;
    method Action set;
    method Action rst;

    method Bool _read;

    method Action clear;
endinterface

/** Set/reset flop with mutually_exclusive assertion on set/reset
 * Imposes no scheduling order between set/reset methods.
 * 
 * Order: _read, (set/rst), clear
 */

module mkConflictFreeSetReset#(Bool init)(SetReset);
    Reg#(Bool) _r[2] <- mkCReg(2,init);

    let pwSet <- mkPulseWireOR, pwRst <- mkPulseWireOR;

    (* mutually_exclusive="doSet,doRst" *)

    rule doSet if (pwSet);
        _r[0] <= True;
    endrule

    rule doRst if (pwRst);
        _r[0] <= False;
    endrule

    method Action set = pwSet.send;
    method Action rst = pwRst.send;

    method Bool _read = _r[0]._read;
    method Action clear = _r[1]._write(init);
endmodule

typeclass Readable#(type t,type ifc);
    function t read(ifc i);
endtypeclass

instance Readable#(t,Reg#(t));
    function t read(Reg#(t) i) = i._read;
endinstance

instance Readable#(Bool,SetReset);
    function Bool read(SetReset sr) = sr._read;
endinstance

endpackage
