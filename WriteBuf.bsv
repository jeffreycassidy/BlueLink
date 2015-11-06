package WriteBuf;

import PSLTypes::*;
import AFU::*;
import BLProgrammableLUT::*;
import Vector::*;
import ClientServerU::*;

import DReg::*;
import HList::*;

import Assert::*;

import Common::*;

interface WriteBuf#(numeric type lat);
    interface ServerAFL#(BufferReadRequest,Bit#(512),lat)  pslin;

    (* always_ready *)
    method Action write(RequestTag t,Bit#(1024) data);

    (* always_ready *)
    method Action writeSeg(RequestTag t,UInt#(6) seg,Bit#(512) data);
endinterface


/** AFU Write buffer
 *
 * Handles PSL buffer reads by providing a 1024b-wide buffer (also writable as 2x512b)
 *
 * Decided the MLAB overhead to support 1024b write wasn't too bad. MLABs can do 32x20 or 64x10 configs.
 * If only using 16 tags, could economize on MLABs by having a 26 wide (520b) 32x20 array with halfline addressing via the 
 * last address bit. To support 32 tags requires 26 wide x 2 deep or 52 wide x 1 deep anyway. The latter is inherently 1024b.
 * 
 * No tag management here, just the storage space and the hooks to the PSL.
 *
 * Latency is given as an argument, but currently only supports 2 (brlat=1).
 */

module mkAFUWriteBuf#(synT syn,Integer nTags)(WriteBuf#(lat))
    provisos (
        Bits#(RequestTag,nt),
        Gettable#(synT,MemSynthesisStrategy)
    );
    Vector#(2,Lookup#(nt,Bit#(512))) wbufseg <- replicateM(mkZeroLatencyLookup(syn,nTags));

    // Current PSL supports only brlat=1, meaning data is available 2nd cycle after brvalid asserted
    staticAssert(valueOf(lat)==2,"Invalid latency value in mkAFUWriteBuf; must be 2 (corresponds to brlat=1)");

    Reg#(Maybe#(BufferReadRequest)) bri <- mkDReg(tagged Invalid);
    Reg#(Maybe#(Bit#(512)))         o   <- mkDReg(tagged Invalid);

    function Action doWrite(RequestTag tag,Lookup#(nt,Bit#(512)) lut,Bit#(512) data) = lut.write(tag,data);

    rule doLookup if (bri matches tagged Valid .br);
        dynamicAssert(br.brtag < fromInteger(nTags),"Invalid buffer read request; brtag >= nTags");
        dynamicAssert(br.brad < 2, "Invalid read address brad>=2");
        let t <- wbufseg[br.brad].lookup(br.brtag);
        o <= tagged Valid t;
    endrule

    interface ServerAFL pslin;
        interface Put request = toPut(asReg(bri));
        interface ReadOnly response = readIfValid(o);
    endinterface

    method Action writeSeg(RequestTag t,UInt#(6) seg,Bit#(512) i);
        wbufseg[seg].write(t,i);
    endmethod

    method Action write(RequestTag t,Bit#(1024) i) = zipWithM_(doWrite(t),reverse(wbufseg),toChunks(i));
endmodule

endpackage
