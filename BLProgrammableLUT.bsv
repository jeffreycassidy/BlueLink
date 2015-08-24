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



/** Wrapper around the Altera IP core for an MLAB-based unregistered lookup. The specific instance was modified to accommodate a
 * variable width/depth/number of address lines.
 *
 */

import "BVI" MLAB_0l = module mkAlteraStratixVMLAB_0l#(Integer depth)(Lookup#(na,t)) provisos (Bits#(t,nd));
    default_clock clock(clock, (*unused*) clk_gate);
    default_reset no_reset;

    parameter AWIDTH = valueOf(na);
    parameter DWIDTH = valueOf(nd);
    parameter DEPTH  = depth;

    method write(wraddress,data) enable(wren);
    method q lookup(rdaddress) enable(rden_DUMMY);

    schedule lookup C lookup;
    schedule write  C write;
    schedule lookup CF write;
endmodule

function m#(Lookup#(na,t)) mkZeroLatencyLookup(Integer depth)
	provisos (
		Bits#(t,nd),
		IsModule#(m,a)) = mkAlteraStratixVMLAB_0l(depth);

endpackage
