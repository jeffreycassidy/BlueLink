package ReadBuf;

import PSLTypes::*;
import AFU::*;
import BLProgrammableLUT::*;
import Vector::*;
import ClientServerU::*;

import DReg::*;

import Assert::*;

import Common::*;

interface ReadBuf;
    (* always_ready *)
    interface Put#(BufferWrite)     pslin;

    (* always_ready *)
    method ActionValue#(Bit#(1024)) lookup(RequestTag tag);
endinterface

interface WriteBuf#(numeric type lat);
    interface ServerAFL#(BufferReadRequest,Bit#(512),lat)  pslin;

    (* always_ready *)
    method Action write(RequestTag t,Bit#(1024) data);

    (* always_ready *)
    method Action writeSeg(RequestTag t,UInt#(6) seg,Bit#(512) data);
endinterface


/** AFU Read Buffer
 * 
 * Handles PSL buffer writes by stashing in an MLAB-based buffer that allows 1024b single-port reads.
 *
 * Indexing is by request tag.
 *
 */

module mkAFUReadBuf#(Integer nTags)(ReadBuf) provisos (Bits#(RequestTag,nt));

    Vector#(2,Lookup#(nt,Bit#(512))) rbufseg <- replicateM(mkAlteraStratixVMLAB_0l(nTags));

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

module mkAFUWriteBuf#(Integer nTags)(WriteBuf#(lat)) provisos (Bits#(RequestTag,nt));
    Vector#(2,Lookup#(nt,Bit#(512))) wbufseg <- replicateM(mkAlteraStratixVMLAB_0l(nTags));

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


import StmtFSM::*;

module mkTB_AFUReadBuf();
    let dut <- mkAFUReadBuf(16);

    function Action test(UInt#(16) a,Bit#(512) d) = action
        RequestTag tag = truncate(a>>1);
        UInt#(6) bwad = truncate(a%2);
        dut.pslin.put(BufferWrite { bwtag: tag, bwad: bwad, bwdata: d });
    endaction;

    Reg#(UInt#(16)) i <- mkReg(0);

    Stmt stim = seq
        test(0, 512'hdeadbeef);
        test(1, 512'hdeadb00f);

        test(3, 512'hbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb);

        test(2, 512'haaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa);

        while(i != 16)
        action
            let t <- dut.lookup(truncate(i));
            let o = pack(t);
            $display("Output[%2d] = %64X",i,o[1023:768]);
            $display("             %64X",o[ 767:512]);
            $display("             %64X",o[ 511:256]);
            $display("             %64X",o[ 255:  0]);
            i <= i+1;
        endaction

        repeat(2) noAction;
    endseq;

    mkAutoFSM(stim);
    
endmodule

module mkTB_AFUWriteBuf();
    WriteBuf#(2) dut <- mkAFUWriteBuf(16);

    function Action testwriteall(RequestTag t, Bit#(1024) data) = action
        $display($time," Writing to tag %d: %64X",t,data[1023:768]);
        $display($time,"                    %64X",data[ 767:512]);
        $display($time,"                    %64X",data[ 511:256]);
        $display($time,"                    %64X",data[ 255:  0]);
        dut.write(t,data);
    endaction;

    function Action testwriteseg(RequestTag t,UInt#(6) seg,Bit#(512) data) = action
        $display($time," Writing to tag %3d offset %3d: %64X",t,seg,data[ 511:256]);
        $display($time,"                                %64X",data[ 255:  0]);
        dut.writeSeg(t,seg,data);
    endaction;

    Reg#(UInt#(16)) i <- mkReg(0);

    Stmt stim = seq

        testwriteall(0,   1024'h0000000000000000000000000000000000000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222222222222222222222222222222222223333333333333333333333333333333333333333333333333333333333333333 );

        testwriteall(2,   1024'hdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadb00faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa );

        testwriteseg(1,1,512'hcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc);
        noAction;
        testwriteseg(1,0,512'hbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb);
                                
        
        while (i < 16) seq
            action
                let br = BufferReadRequest { brtag: truncate(i>>1), brad: truncate(i%2) };
                $display($time, " Request: ",fshow(br));
                dut.pslin.request.put(br);
            endaction

            action 
                let o = dut.pslin.response;
                $display($time,"  Response: %64X",o[511:256]);
                $display($time,"            %64X",o[255:  0]);
                i <= i + 1;
            endaction
        endseq

        repeat(10) noAction;
    endseq;

    mkAutoFSM(stim);

endmodule

endpackage
