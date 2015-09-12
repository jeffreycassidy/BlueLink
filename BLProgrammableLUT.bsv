package BLProgrammableLUT;

import Assert::*;
import StmtFSM::*;
import DReg::*;
import BRAM::*;
import HList::*;
import Vector::*;
import ConfigReg::*;
import RevertingVirtualReg::*;

import ModuleContext::*;

typedef union tagged {
    void BSVBehavioral;
    void AlteraStratixV;
} MemSynthesisStrategy deriving(Eq);



/** Writeable LUT with zero-latency lookup
 */

interface Lookup#(numeric type na,type data_t);
    (* always_ready *)
    method Action               write(UInt#(na) addr,data_t data);

	(* always_ready *)
    method ActionValue#(data_t) lookup(UInt#(na) addr);
endinterface

interface MultiReadLookup#(numeric type na,type data_t);
    (* always_ready *)
    method Action               write(UInt#(na) addr,data_t data);

    (* always_ready *)
    interface Array#(function ActionValue#(data_t) f(UInt#(na) addr)) lookup;
endinterface



/** Wrapper around the Altera IP core for an MLAB-based unregistered lookup. The specific instance was modified to accommodate a
 * variable width/depth/number of address lines.
 *
 * The AUSED parameter specifies how many address lines are actually used to prevent a Verilog dangling-port warning.
 * TODO: Check that log2(depth) performs as expected (ceil(log2(depth))) for depth not a power of 2
 */

import "BVI" MLAB_0l = module mkAlteraStratixVMLAB_0l#(Integer depth)(Lookup#(na,t)) provisos (Bits#(t,nd));
    default_clock clock(clock, (*unused*) clk_gate);
    default_reset no_reset;

    parameter AUSED  = log2(depth);             // same as ceil(log2(depth))
    parameter AWIDTH = valueOf(na);
    parameter DWIDTH = valueOf(nd);
    parameter DEPTH  = depth;

    method write(wraddress,data) enable(wren);
    method q lookup(rdaddress) enable(rden_DUMMY);

    schedule lookup C lookup;
    schedule write  C write;
    schedule lookup CF write;
endmodule

// older form without width transformation
//function m#(Lookup#(na,t)) mkZeroLatencyLookup(Integer depth)
//	provisos (
//		Bits#(t,nd),
//		IsModule#(m,a)) = mkAlteraStratixVMLAB_0l(depth);

module mkZeroLatencyLookup#(Integer depth)(Lookup#(na,t)) provisos (Bits#(t,nd));
    staticAssert(depth <= 256,"Invalid depth requested (>256)");
    staticAssert(depth <= valueOf(TExp#(na)),"Insufficient address port width specified for requested depth");

    let _w <- mkAlteraStratixVMLAB_0l(depth);

    method Action write(UInt#(na) addr,t data);
        dynamicAssert(addr < fromInteger(depth),"Invalid address requested");
        _w.write(addr,data);
    endmethod

    method ActionValue#(t) lookup(UInt#(na) addr);
        dynamicAssert(addr < fromInteger(depth),"Invalid address requested");
        let o <- _w.lookup(addr);
        return o;
    endmethod
endmodule


typedef function ActionValue#(t) f(UInt#(na) addr) ReadPort#(numeric type na,type t);

module mkMultiReadZeroLatencyLookup#(Integer nread,Integer depth)(MultiReadLookup#(na,t))
    provisos (
        Bits#(t,nd));

    ReadPort#(na,t) readPort[nread];

    List#(Lookup#(na,t)) luts <- List::replicateM(nread,mkZeroLatencyLookup(depth));
    for(Integer i=0;i<nread;i=i+1)
        readPort[i] = luts[i].lookup;

    method Action write(UInt#(na) addr,t data);
        for(Integer i=0;i<nread;i=i+1)
            luts[i].write(addr,data);
    endmethod

    interface Array lookup = readPort;
endmodule

endpackage
