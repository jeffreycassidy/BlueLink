package Stream;

import PSLTypes::*;
import Cntrs::*;

interface StreamCtrl;
    method Action   start(EAddress64 ea,UInt#(64) nBytes);
    method Action   abort;
    method Bool     done;
endinterface

typedef struct {
    Integer bufDepth;       // number of buffer entries
    Integer nParallelTags;  // number of parallel tags to use
} StreamConfig;



/** ****** DEPRECATED ******
 * This older method of buffer allocation does not scale well in hardware (large number of regs -> encoder -> downstream logic
 * is too slow to run at 250M)
 */

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

    warningM("Stream::mkBufStatus - instantiation of deprecated module (does not scale well in hardware)");

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


//// (END DEPRECATED)



// Slight variation on mkCount(t init), in which the modulus is compile-time variable
// mkCount rolls over at maxValue#(t), whereas this may roll over sooner
//
// NOTE: Synthesis results disappointing, seems to instantiate a modulo hardware unit in Verilog?

module mkModuloCount#(Integer m,t init)(Count#(t))
    provisos (
        Arith#(t),
        Bits#(t,n));

    Wire#(t) incrVal <- mkDWire(0), decrVal <- mkDWire(0);
    Reg#(t) ctr[3] <- mkCReg(3,init);

    rule doIncrDecr;
        t next = ctr[1] + incrVal - decrVal;

//          this seems to be brutally slow - instantiates a specific modulo unit in Verilog
        ctr[1] <= (ctr[1] + incrVal - decrVal) % fromInteger(m);
    endrule

    method t _read = ctr[0];
    method Action update(t val) = asReg(ctr[0])._write(val);

    method Action incr(t val) = incrVal._write(val);
    method Action decr(t val) = decrVal._write(val);
    method Action _write(t val) = ctr[2]._write(val);
endmodule




// read, update, (incr,decr), (write, clear)

interface UnitUpDnCount#(type t);
    method Action incr;
    method Action decr;
    method Action clear;

    method t _read;
    method Action update(t val);
    method Action _write(t val);
endinterface

module mkUnitUpDnModuloCount#(Integer m,t init)(UnitUpDnCount#(t))
    provisos (
        Arith#(t),
        Bits#(t,n),
        Eq#(t));

    Reg#(t) ctr[3] <- mkCReg(3,init);
    let pwIncr <- mkPulseWire, pwDecr <- mkPulseWire;

    rule doIncr if (pwIncr && !pwDecr);
        ctr[1] <= ctr[1] == fromInteger(m-1) ? 0 : ctr[1]+1;
    endrule

    rule doDecr if (pwDecr && !pwIncr);
        ctr[1] <= ctr[1] == 0 ? fromInteger(m-1) : ctr[1]-1;
    endrule

    method t _read = ctr[0];
    method Action update(t val) = ctr[0]._write(val);

    method Action incr = pwIncr.send;
    method Action decr = pwDecr.send;

    method Action _write(t val) = ctr[2]._write(init);

    method Action clear = ctr[2]._write(init);
endmodule




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
