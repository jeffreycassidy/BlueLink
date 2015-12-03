package AlteraM20k;

import FIFOF::*;
import PAClib::*;
import BRAMCore::*;

import GetPut::*;
import ClientServer::*;


/** PipeOut-like BRAM interface with ability to stall reads (works synchronously, advancing when a put or deq is called) but
 * without a backpressure mechanism.
 *
 * In a typical case with input and output reg, a read completion requires a put, followed by either a deq or another put.
 * The first put registers the read command and address, while the subsequent command allows the output reg to update.
 */

interface BRAM_PORT_Stall#(type addrT,type dataT);
    (* always_ready *)
    method Action   put(Bool wr,addrT addr,dataT data);
    method dataT    read;

    (* always_ready *)
    method Action   deq;
endinterface

interface BRAM_DUAL_PORT_Stall#(type addrT,type dataT);
    (* always_ready *)
    interface BRAM_PORT_Stall#(addrT,dataT) a;

    (* always_ready *)
    interface BRAM_PORT_Stall#(addrT,dataT) b;
endinterface




/** Create a dual-port unguarded BRAM with stall capability */

import "BVI" module mkBRAM2Stall#(Integer depth)(BRAM_DUAL_PORT_Stall#(addrT,dataT))
    provisos (
        Bits#(addrT,na),
        Bits#(dataT,nd)
        );

    default_clock(CLK,(*unused*)CLK_GATE);
    no_reset;


    parameter ADDR_WIDTH=valueOf(na);
    parameter DATA_WIDTH=valueOf(nd);
    parameter PIPELINED=1;
    parameter MEMSIZE=depth;

    interface BRAM_PORT_Stall a;
        method put(WEA,ADDRA,DIA) enable (ENA);
        method DOA read;
        method deq() enable(DEQA);
    endinterface

    interface BRAM_PORT_Stall b;
        method put(WEB,ADDRB,DIB) enable (ENB);
        method DOB read;
        method deq() enable(DEQB);
    endinterface

    schedule (a.put, a.read, a.deq) CF (b.put, b.read, b.deq);
    schedule a.put CF (a.deq,a.read);
    schedule b.put CF (b.deq,b.read);

    schedule a.put C a.put;
    schedule b.put C b.put;

    schedule a.read CF (a.read,a.deq);
    schedule b.read CF (b.read,b.deq);

    schedule a.deq C a.deq;
    schedule b.deq C b.deq;
endmodule


typedef union tagged {
    void        Read;
    dataT       Write;
} MemRequest#(type dataT) deriving(Eq,Bits,FShow);




/** Wraps a latency-2 BRAM port into a guarded Pipe interface (input: MemRequest, output: read data) with appropriate implicit
 * conditions at both input and output.
 *
 * When the pipe is full, reads are stalled until the output is deq'd to prevent loss of data. This requires that deq schedule
 * before put.
 */

module mkBRAMPortPipeOut#(BRAM_PORT_Stall#(addrT,dataT) brport,PipeOut#(Tuple2#(addrT,MemRequest#(dataT))) pi)(PipeOut#(dataT));

    // Null LFIFOFs to indicate status of input/output regs (causes dependency: method deq -> bramRead)
    FIFOF#(void)    ramireg <- mkLFIFOF;
    FIFOF#(void)    ramoreg <- mkLFIFOF;

    // read requires space downstream to store result (depends on output fifo empty or incoming deq)
    rule bramRead if (pi.first matches { .addr, Read });
        pi.deq;
        ramireg.enq(?);
        brport.put(False,addr,?);
    endrule

    // write can always proceed, will not assert rden so output reg stays same
    rule bramWrite if (pi.first matches { .addr, tagged Write .data });
        pi.deq;
        brport.put(True,addr,data);
    endrule

    // allow read address to propagate to output reg if there is space
    rule advanceWhenAble;
        ramireg.deq;        // Accept next input address
        ramoreg.enq(?);
        brport.deq;         // get next contents from RAM
    endrule

    // provide PipeOut interface using LFIFOFs to provide implicit conditions
    method Action   deq                         = ramoreg.deq;
    method Bool     notEmpty                    = ramoreg.notEmpty;
    method dataT    first if (ramoreg.notEmpty) = brport.read;
endmodule





/** Server-based variant of mkBRAMPortPipeOut.
 * Uses the BRAM_Port_SplitRW interface to allow different implicit conditions on write (none) vs read (output backpressure)
 */

interface BRAM_PORT_SplitRW#(type addrT,type dataT);
    // write is always possible
    (* always_ready *)
    method Action               write(addrT addr,dataT data);

    // read depends on output backpressure
    interface Server#(addrT,dataT) read;
endinterface

module mkBRAMPortSplitRW#(BRAM_PORT_Stall#(addrT,dataT) brport)(BRAM_PORT_SplitRW#(addrT,dataT));

    // Null LFIFOFs to indicate status of input/output regs (causes dependency: method deq -> bramRead)
    FIFOF#(void)    ramireg <- mkLFIFOF;
    FIFOF#(void)    ramoreg <- mkLFIFOF;

    // allow read address to propagate to output reg if there is space
    rule advanceWhenAble;
        ramireg.deq;        // Accept next input address
        ramoreg.enq(?);
        brport.deq;         // get next contents from RAM
    endrule

    // writes can always proceed
    method Action write(addrT addr,dataT data) = brport.put(True,addr,data);

    // reads may have implicit conditions due to output backpressure
    interface Server read;
        interface Put request;
            method Action put(addrT addr);
                ramireg.enq(?);
                brport.put(False,addr,?);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(dataT) get if (ramoreg.notEmpty);
                ramoreg.deq;
                return brport.read;
            endmethod
        endinterface
    endinterface
endmodule

endpackage
