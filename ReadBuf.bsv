package ReadBuf;

import PSLTypes::*;
import AFU::*;
import BLProgrammableLUT::*;
import Vector::*;
import ClientServerU::*;

import HList::*;
import DSPOps::*;

import Assert::*;

import Common::*;

interface ReadBuf;
    (* always_ready *)
    interface Put#(BufferWrite)     pslin;

    (* always_ready *)
    method ActionValue#(Bit#(1024)) lookup(RequestTag tag);
endinterface


/** AFU Read Buffer
 * 
 * Handles PSL buffer writes by stashing in an MLAB-based buffer that allows 1024b single-port reads.
 *
 * Indexing is by request tag. Subsequent read completions will overwrite a given slot, so a stored value must be consumed before
 * issuing another read on the same tag.
 */

module mkAFUReadBuf#(Integer nTags)(ReadBuf) provisos (Bits#(RequestTag,nt));

    HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);

    Vector#(2,Lookup#(nt,Bit#(512))) rbufseg <- replicateM(mkZeroLatencyLookup(syn,nTags));

    function ActionValue#(Bit#(512)) doLookup(RequestTag t,Lookup#(nt,Bit#(512)) l) = l.lookup(t);

    interface Put pslin;
        method Action put(BufferWrite bw);
            dynamicAssert(bw.bwad < 2,"Invalid address in mkAFUReadBuf");
            dynamicAssert(bw.bwtag < fromInteger(nTags),"Invalid tag in mkAFUReadBuf");

            rbufseg[bw.bwad].write(bw.bwtag,bw.bwdata);
        endmethod
    endinterface


    method ActionValue#(Bit#(1024)) lookup(RequestTag t);
        Vector#(2,Bit#(512)) v <- mapM(doLookup(t),rbufseg);
        return pack(reverse(v));
    endmethod
endmodule

endpackage
