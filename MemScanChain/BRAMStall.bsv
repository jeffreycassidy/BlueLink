import Assert::*;

import BRAM::*;
import ClientServer::*;
import GetPut::*;
import FIFOF::*;

/** BRAM interface with ability to stall reads in the pipeline using the output reg clock enable.
 * 
 * Command input clock is enabled when a command is issued.
 * Output reg clock is enabled when a command is issued or deq is asserted.
 * 
 * Reading a value requires issuing a read command, then asserting deq for one cycle (or issuing another read). The value is
 * available 1 cycle after.
 *
 * Unguarded - does not provide any backpressure signals.
 */

interface BRAM_PORT_Stall#(type addrT,type dataT);
    (* always_ready *)
    method Action           putcmd(Bool wr,addrT addr,dataT data);
    method dataT            readdata;

    (* always_ready *)
    method Action   deq;
endinterface

interface BRAM_DUAL_PORT_Stall#(type addrT,type dataT);
    interface BRAM_PORT_Stall#(addrT,dataT) a;
    interface BRAM_PORT_Stall#(addrT,dataT) b;
endinterface




/** Wraps a BRAM_PORT_Stall into the normal BRAMServer interface, including backpressure if the output isn't deq'd promptly.
 * Note this requires output get schedules before command put (put needs to know if output space is available).
 */

module mkBRAMStallWrapper#(BRAM_PORT_Stall#(addrT,dataT) brport)(BRAMServer#(addrT,dataT));

    FIFOF#(Bool)        ramiread     <- mkLFIFOF;   // True => input command is read, False => write, empty => no command
    FIFOF#(Bool)        ramoread     <- mkLFIFOF;

    // allow read data to propagate to output reg if there is space
    rule advanceWhenAble;
        ramoread.enq(ramiread.first);
        ramiread.deq;
        brport.deq;                 // advance RAM output reg
    endrule

    // if it's not a read, we don't care about the output so can safely discard
    rule discardWrite if (!ramoread.first);
        ramoread.deq;
    endrule

    interface Put request;
        method Action put(BRAMRequest#(addrT,dataT) cmd);
            ramiread.enq(!cmd.write);
            brport.putcmd(cmd.write,cmd.address,cmd.datain);
            dynamicAssert(!cmd.responseOnWrite,"Response on write is not supported by BRAMStallWrapper");
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(dataT) get if (ramoread.first);      // output data only if command was a read
            ramoread.deq;
            return brport.readdata;
        endmethod
    endinterface

endmodule
