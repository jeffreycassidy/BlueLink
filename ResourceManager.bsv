package ResourceManager;

import GetPut::*;
import List::*;
import Assert::*;

interface Resource;
    method Action   unlock;
    method Action   lock;
    method Action   clear;

    method Bool     available;
endinterface

/**
 *  init        Initial lock state (False = unlocked)
 *  bypass      If true, available schedules after unlock (ie. can free & re-grant in same cycle)
 *
 * Operation sequence: unlock, lock, clear
 */

module mkResource#(Bool init,Bool bypass)(Resource);
    Reg#(Bool) locked[3] <- mkCReg(3,init);

    method Bool available = !locked[bypass ? 1 : 0];

    method Action unlock;
        dynamicAssert(locked[0],"Attempting to unlock already-unlocked resource");
        locked[0] <= False;
    endmethod

    // sequences after unlock if bypass, else conflicts
    method Action lock;
        dynamicAssert(!locked[bypass ? 1 : 0],"Attempting to lock already-locked resource");
        locked[bypass ? 1 : 0] <= True;
    endmethod 

    // clear goes last
    method Action clear = locked[2]._write(init);

endmodule



/** mkResourceManager
 * Provides the facility to acquire and free resources. Each cycle, can get the next available resource. Multiple resources
 * can be freed simultaneously.
 *
 * n        Number of resources to manage
 * init     Specifies initial lock state: locked (True) or unlocked (False)
 * bypass   If true, allows a tag to be freed and granted in the same clock cycle
 *              NOTE: Forces getNext to schedule after all unlocks, and may cause some slowdown
 *
 *  ni      Number of bits in the resource tag
 */


interface ResourceManager#(numeric type ni);
    interface Get#(UInt#(ni))   nextAvailable;

    method Action               unlock(UInt#(ni) ri);

    method Action               clear;
endinterface



module mkResourceManager#(Integer n,Bool init,Bool bypass)(ResourceManager#(ni));
    // instantiate the resource state blocks
    List#(Resource) resources <- List::replicateM(n,mkResource(init,bypass));
    List#(Tuple2#(UInt#(ni),Resource)) resourcesWithIndex = List::zip(
        List::map(fromInteger,upto(0,n-1)),
        resources
        );

    // resource accessor methods used with map/mapM
    function Action doClear(Resource r) = r.clear;
    function Bool   isAvailable(Resource r) = r.available;

    // acquire sequences after free/clear if bypass is enabled
    method Action unlock(UInt#(ni) t) = resources[t].unlock;

    // if there is an available resource, lock it and return its index
    interface Get nextAvailable;
        method ActionValue#(UInt#(ni)) get if (List::find(compose(isAvailable,tpl_2),resourcesWithIndex) matches tagged Valid { .ri, .r });
            r.lock;
            return ri;
        endmethod
    endinterface

    // clear just sends a clear signal to all resources
    method Action clear;
        let o <- List::mapM(doClear,resources);
    endmethod
endmodule

import Vector::*;
import StmtFSM::*;

module mkTB_ResourceManager() provisos (NumAlias#(nt,4));

    // 4 tags, initially unlocked, with bypass
    ResourceManager#(2) dut <- mkResourceManager(4,False,False);

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
            pwReq.send;
            pwReq.send;
            pwReq.send;

    endseq;

    mkAutoFSM(stim);

    (* preempts="granted,denied" *)

    rule granted if (pwReq);
        let t <- dut.nextAvailable.get;
        $display($time,": Request granted with tag %d",t);
    endrule

    rule denied if (pwReq);
        $display($time,": Request denied");
    endrule


    for(Integer i=0;i<valueOf(nt);i=i+1)
        rule sendClear if (pwClr[i]);
            $display($time,": Tag %d freed",i);
            pwClrDone[i].send;
            dut.unlock(fromInteger(i));
        endrule

    function Bool read(PulseWire pw) = pw;

    continuousAssert(map(read,pwClr) == map(read,pwClrDone),"Clear request blocked!");

endmodule



endpackage
