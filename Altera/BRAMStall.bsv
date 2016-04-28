package BRAMStall;

import Assert::*;

import PAClib::*;
import GetPut::*;
import FIFOF::*;

/** Unguarded primitive BRAM port with read data stall capability.
 * Read data will be available on readdata port as soon as it's available, and will be held until deq is called.
 */

interface BRAM_PORT_Stall_PrimUG#(type addrT,type dataT);
    (* always_ready *)
    method Action           putcmd(Bool wr,addrT addr,dataT data);
    method dataT            readdata;

    (* always_ready *)
    method Action   deq;

    (* always_ready *)
    method Action   clear;
endinterface

interface BRAM_DUAL_PORT_Stall_PrimUG#(type addrT,type dataT);
    interface BRAM_PORT_Stall_PrimUG#(addrT,dataT) a;
    interface BRAM_PORT_Stall_PrimUG#(addrT,dataT) b;
endinterface




interface BRAMPortStall#(type addrT,type dataT);
    method Action putcmd(Bool wr,addrT addr,dataT data);
    method Action clear;

    interface PipeOut#(dataT)       readdata;
endinterface

interface BRAM2PortStall#(type addrT,type dataT);
    interface BRAMPortStall#(addrT,dataT)   porta;
    interface BRAMPortStall#(addrT,dataT)   portb;
endinterface



/** Wraps the primitive above to produce a BRAM interface with pipeout read data. 
 * Commands can be issued when there is space in the command reg.
 * Writes always vacate the command reg immediately.
 * Reads vacate the command reg when there is space in the output reg.
 *
 * Behaviour uses a pipeline FIFO to get full throughput, so readdata.deq schedules before putcmd.
 */


module mkBRAMStallPipeOut#(BRAM_PORT_Stall_PrimUG#(addrT,dataT) brport)(BRAMPortStall#(addrT,dataT))
    provisos (
        Bits#(addrT,na),
        Bits#(dataT,nd));
    FIFOF#(Bool)        ramiread   <- mkLFIFOF;     // True => input command is read, False => write, empty => no command
    FIFOF#(void)        oValid     <- mkLFIFOF;     // full if data present at read port

    // allow read data to propagate to output reg if there is space
    rule advanceWhenAble if (ramiread.first);
        oValid.enq(?);
        ramiread.deq;
        brport.deq;
    endrule

    // if it's not a read, we don't care about the output so can safely discard
    rule discardWrite if (!ramiread.first);
        ramiread.deq;
    endrule

    method Action putcmd(Bool wr,addrT addr,dataT data);
        ramiread.enq(!wr);
        brport.putcmd(wr,addr,data);
    endmethod

    method Action clear;
        oValid.clear;
        ramiread.clear;
        brport.clear;
    endmethod

    interface PipeOut readdata;
        method Bool notEmpty = oValid.notEmpty;
        method Action deq;
            oValid.deq;
        endmethod

        method dataT first if (oValid.notEmpty) = brport.readdata;
    endinterface
endmodule


function BRAMPortStall#(a,d) portA(BRAM2PortStall#(a,d) br) = br.porta;
function BRAMPortStall#(a,d) portB(BRAM2PortStall#(a,d) br) = br.portb;

endpackage
