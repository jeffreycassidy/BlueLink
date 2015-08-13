package TagManager;

import GetPut::*;
import StmtFSM::*;
import Vector::*;
import Assert::*;

import Common::*;

interface TagManager#(type tag_t);

    // free a currently-used tag
    method Action free(tag_t t);

    // acquire a new tag (sequences after free if bypass enabled)
    method Bool available;
    method ActionValue#(tag_t) acquire;

    method Action clear;
endinterface


/** mkTagManager
 * 
 * Manages a set of request tags. The set of available tags is provided as a vector. It need not be contiguous or sorted.
 * Clients can acquire a tag, and when finished they release it for use again.
 * 
 * One tag may be acquired at once, though multiple may be freed in a given cycle.
 *
 * The bypass parameter specifies whether a tag can be freed and acquired in the same cycle.
 *
 */

module mkTagManager#(Vector#(nTags,tag_t) tags,Bool bypass)(TagManager#(tag_t))
    provisos (Eq#(tag_t));

    // indicates that this element is being freed on this cycle
    // PulseWireOr ensures that multiple tags can be simultaneously freed without schedule conflicts
    // TODO: May be possible with -aggressive-conditions, but at much increased scheduler cost
    Vector#(nTags,PulseWire)  pwClr <- replicateM(mkPulseWireOR);
    Vector#(nTags,PulseWire)  pwGt  <- replicateM(mkPulseWire);

    // True if tag is available
    Vector#(nTags,Reg#(Bool)) avail <- replicateM(mkReg(True));

    Vector#(nTags,Bool) availNext = bypass ? zipWith( \|| , read(avail), read(pwClr)) : read(avail);

    function Action send(PulseWire pw) = pw.send;

    rule update;
        for(Integer i=0;i<valueOf(nTags);i=i+1)
            avail[i] <= (avail[i] || pwClr[i]) && !pwGt[i];
    endrule

    for(Integer i=0;i<valueOf(nTags);i=i+1)
        rule showGrant if (pwGt[i]);
            $display($time," INFO: Granted tag %d",i);
        endrule

    // acquire sequences after free/clear if bypass is enabled

    method Action free(tag_t t);
        dynamicAssert(countElem(t,tags)==1,"Invalid tag requested for free: either no instances or duplicates in tags vector");

        for(Integer i=0;i<valueOf(nTags);i=i+1)
            if (tags[i] == t)
            begin
                pwClr[i].send;
 //               $display($time," INFO: Freed tag %d",i);
//                if (avail[i])
//                begin
////                    $write("Trying to free tag %d, tag status: ",i);
//                    for(Integer j=0;j<valueOf(nTags);j=j+1)
//                        $write("%d ",(avail[j] ? 1 : 0));
//                    $display;
//                end
//                dynamicAssert(!avail[i],"Attempting to free an unused tag");
            end
    endmethod

    method Bool available = elem(True,availNext);

    method ActionValue#(tag_t) acquire if (elem(True,availNext));
        Maybe#(tag_t) o = tagged Invalid;

        Integer i=0;
        while (i < valueOf(nTags) && !availNext[i])
            i=i+1;

        dynamicAssert(i < valueOf(nTags),"availNext indicates tag available but loop ran off the end without finding a free tag");
        pwGt[i].send;
        return tags[i];
    endmethod

    // clear just sends a free signal to all tags
    method Action clear = mapM_(send,pwClr);
endmodule

module mkTB_TagManager()
    provisos (
        NumAlias#(nt,4),
        NumAlias#(nbt,8)
        );

    let dut <- mkTagManager((Vector#(nt,UInt#(nbt))'(genWith(fromInteger))),True);

    let pwReq <- mkPulseWire;

    Vector#(nt,PulseWire) pwClr <- replicateM(mkPulseWire);
    Vector#(nt,PulseWire) pwClrDone <- replicateM(mkPulseWire);

    Stmt stim = seq
        pwReq.send;
        pwReq.send;
        pwReq.send;
        pwReq.send;
        pwReq.send;

        action
            pwReq.send;
            pwClr[0].send;
        endaction
        pwClr[0].send;

        action
            pwClr[1].send;
            pwClr[2].send;
            pwReq.send;
        endaction

    endseq;

    mkAutoFSM(stim);

    (* preempts="granted,denied" *)

    rule granted if (pwReq);
        let t <- dut.acquire;
        $display($time,": Request granted with tag %d",t);
    endrule

    rule denied if (pwReq);
        $display($time,": Request denied");
    endrule


    for(Integer i=0;i<valueOf(nt);i=i+1)
        rule sendClear if (pwClr[i]);
            $display($time,": Tag %d freed",i);
            pwClrDone[i].send;
            dut.free(fromInteger(i));
        endrule



    continuousAssert(map(read,pwClr) == map(read,pwClrDone),"Clear request blocked!");

endmodule


endpackage
