package ProgrammableLUT;

import Assert::*;
import StmtFSM::*;
import DReg::*;
import BRAM::*;
import HList::*;
import Vector::*;
import ConfigReg::*;
import RevertingVirtualReg::*;

import PAClib::*;
import PAClibx::*;

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

    (* always_enabled *)
    method ActionValue#(data_t) lookup(UInt#(na) addr);
endinterface


/** Writeable LUT with nonzero latency (simple dual-port RAM)
 */

interface SDPRAM#(numeric type na,type data_t);
	(* always_ready *)
	method Action		write(UInt#(na) addr,data_t data);

	(* always_ready *)
	method Action		readreq(UInt#(na) addr);
	method data_t		readresp;
endinterface



/** LUT controls. The readback side is registered to facilitate timing closure and play nice with the BRAMServer interface.
 * Writing and readback can only be done when the LUT is in the disabled state.
 */


interface LUTControl#(numeric type n,type data_t);
    method Action setEnable(Bool e);
    interface BRAMServer#(UInt#(TLog#(n)),data_t) data;
endinterface



/** ProgrammableLUT is a writeable lut with the interface split into a read-only side, and a read/write "control" side
 * with enable.
 */


interface ProgrammableLUT#(numeric type n,type data_t);
    // control interface
    interface LUTControl#(n,data_t) control;

    // lookup interface
    method ActionValue#(data_t) lookup(UInt#(TLog#(n)) i);
endinterface




/** Wrapper around the Altera IP core for an MLAB-based unregistered lookup. The specific instance was modified to accommodate a
 * variable width/depth/number of address lines.
 *
 * Because Bluespec doesn't support polymorphic Verilog imports, choose a max address-bus and data-bus width and instantiate that.
 * A separate wrapper takes care of extending inputs to match the max length.
 */

`define MAXMLABDWIDTH 64
`define MAXMLABAWIDTH 6

import "BVI" MLAB_0l = module mkAlteraStratixVMLAB_0l#(Integer na,Integer nb,Integer depth)(Lookup#(`MAXMLABAWIDTH,Bit#(`MAXMLABDWIDTH)));
    default_clock clock(clock, (*unused*) clk_gate);
    default_reset no_reset;

    parameter AWIDTH = na;
    parameter DWIDTH = nb;
    parameter DEPTH  = depth;

    method write(wraddress,data) enable(wren);
    method q lookup(rdaddress) enable((*inhigh*) t);

    schedule lookup C lookup;
    schedule write  C write;
    schedule lookup CF write;
endmodule

import "BVI" MLAB_1l = module mkAlteraStratixVMLAB_1l#(Integer na,Integer nb,Integer depth)
	(SDPRAM#(`MAXMLABAWIDTH,Bit#(`MAXMLABDWIDTH)));

    default_clock clock(CLK, (*unused*) clk_gate);
    default_reset no_reset;

    parameter AWIDTH = na;
    parameter DWIDTH = nb;
    parameter DEPTH  = depth;

    method write(wraddr,wrdata) enable(wren);
    method readreq(rdaddr) enable(rden);
	method rddata readresp ready (rdvalid);

    schedule write  C write;
	schedule readreq C readreq;
	schedule readreq CF write;
	schedule readresp CF (readresp, readreq, write);
endmodule


/** Wrapper to match a small port-width interface with the max-width interface designed above.
 */

module mkAlteraStratixVMLAB_wrap#(Integer depth)(Lookup#(na,data_t)) provisos (
    Bits#(data_t,nb),
    Add#(na,__foo, `MAXMLABAWIDTH),
    Add#(nb,__some,`MAXMLABDWIDTH)
    );

    Lookup#(`MAXMLABAWIDTH,Bit#(`MAXMLABDWIDTH)) w;
	
	w <- mkAlteraStratixVMLAB_0l(valueOf(na),valueOf(nb),depth);

    method Action write(UInt#(na) addr,data_t data) = w.write(extend(addr),extend(pack(data)));
    method ActionValue#(data_t) lookup(UInt#(na) addr);
        let o <- w.lookup(extend(addr));
        return unpack(truncate(o));
    endmethod
endmodule

module mkAlteraStratixVMLAB_1l_wrap#(Integer depth)(SDPRAM#(na,data_t)) provisos (
    Bits#(data_t,nb),
    Add#(na,__foo, `MAXMLABAWIDTH),
    Add#(nb,__some,`MAXMLABDWIDTH)
    );

    SDPRAM#(`MAXMLABAWIDTH,Bit#(`MAXMLABDWIDTH)) w;
	
	w <- mkAlteraStratixVMLAB_1l(valueOf(na),valueOf(nb),depth);

    method Action write(UInt#(na) addr,data_t data) = w.write(extend(addr),extend(pack(data)));
	method Action readreq(UInt#(na) addr) = w.readreq(extend(addr));
    method data_t readresp = unpack(truncate(w.readresp));
endmodule



/** Wraps a ProgrammableLUT to a PAClib-style Pipe interface with no latency.
 */

module mkPipe_from_LUT#(function ActionValue#(data_t) f(UInt#(na) i_),PipeOut#(UInt#(na)) i)(PipeOut#(data_t)) provisos (Bits#(data_t,nb));
    RWire#(data_t) o <- mkRWire;

    rule getinput;
        i.deq;
        UInt#(na) idata  = i.first;
        data_t odata <- f(idata);
		o.wset(odata);
    endrule

	return source_from_RWire(o);
endmodule



/** A programmable LUT with enable/disable method, and a control port for write/readback.
 * Control port does not provide response on write, and has a 1-clock latency on the read.
 *
 * Lookup must be disabled for write/readback to be permitted.
 *
 * Read-during-write is supported with bypass currently.
 */

module [ModuleContext#(ctx)] mkProgrammableLUT#(String name)(ProgrammableLUT#(n,data_t))
    provisos (Bits#(data_t,nd),Gettable#(ctx,MemSynthesisStrategy),Log#(n,ni),Add#(ni,__some,`MAXMLABAWIDTH),Add#(nd,__bar,`MAXMLABDWIDTH));

    Bool rdwNewData=False;

    // grab the context
    ctx c <- getContext;
    MemSynthesisStrategy memstrat = getIt(c);

	Reg#(Bool) rvr <- mkRevertingVirtualReg(True);

    // lookup enable
    // it's a ConfigReg to eliminate schedule conflicts between setEnable and control logic
    Reg#(Bool) en <- mkConfigReg(True);

    Wire#(UInt#(ni)) raddr <- mkWire;
    Reg#(Maybe#(data_t)) rdataq <- mkDReg(tagged Invalid);

    RWire#(Tuple2#(UInt#(ni),data_t)) wreq <- mkRWire;

    Lookup#(ni,data_t) lut;

    case (memstrat) matches
        BSVBehavioral: 
        begin
            Vector#(n,Reg#(data_t)) v <- replicateM(mkConfigReg(?));

            lut = interface Lookup;
                method Action write(UInt#(ni) addr,data_t data) = v[addr]._write(data);
                method ActionValue#(data_t) lookup(UInt#(ni) raddr);
                    if (rdwNewData &&& wreq.wget matches tagged Valid { .waddr, .din } &&& raddr==waddr)
                        return din;
                    else
                        return v[raddr]._read;
                endmethod
            endinterface;
        end

        AlteraStratixV:
        begin
            lut <- mkAlteraStratixVMLAB_wrap(valueOf(n));
        end
    endcase

    rule rdw if (wreq.wget matches tagged Valid { .waddr, .* } &&& waddr == raddr);
        $display($time,": WARNING - Read during write at address ",raddr);
    endrule

    rule dowrite if (wreq.wget matches tagged Valid { .waddr, .din });
        lut.write(waddr,din);
    endrule

    rule doread if (!en);
        let o <- lut.lookup(raddr);
        rdataq <= tagged Valid o;
    endrule

    interface LUTControl control;
        method Action setEnable(Bool e) = en._write(e);

        interface BRAMServer data;
            interface Put request;
                method Action put(BRAMRequest#(UInt#(ni),data_t) ireq);
                    // Do not support responseOnWrite
                    dynamicAssert(!(ireq.write && ireq.responseOnWrite),"mkProgrammableLUT: responseOnWrite not supported");
                    dynamicAssert(!en,"mkProgrammableLUT: attempt to write or readback through control port while enabled");

                    case (ireq) matches
                        tagged BRAMRequest { write: True,  address: .a, datain: .din }:
                            wreq.wset(tuple2(a,din));

                        tagged BRAMRequest { write: False, address: .a }:
                            raddr <= a;
                    endcase
                endmethod
            endinterface
    
            interface Get response;
                method ActionValue#(data_t) get if (rdataq matches tagged Valid .v) = actionvalue return v; endactionvalue;
            endinterface
        endinterface
    endinterface

    method ActionValue#(data_t) lookup(UInt#(ni) addr) if (en) = lut.lookup(addr);
endmodule


endpackage
