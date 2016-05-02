package ResourceManager;

import GetPut::*;
import List::*;
import Assert::*;
import Cntrs::*;
import ProgrammableLUT::*;

import SynthesisOptions::*;

interface Resource;
    method Action   unlock;
    method Action   lock;
    method Action   clear;

    method Bool     available;
endinterface

/**
 *  initialState    Initial lock state (False = unlocked)
 *  bypass          If true, available schedules after unlock (ie. can free & re-grant in same cycle)
 *
 *
 * Schedule order
 *
 *  Bypass==True    unlock, available, lock, clear
 *  Bypass==False   available, lock, unlock, clear
 */

module mkResource#(Bool init,Bool bypass)(Resource);
    Reg#(Bool) locked[3] <- mkCReg(3,init);

    // in bypass mode, available means available at end of cycle (1)
    method Bool available = !locked[bypass ? 1 : 0];

    method Action unlock;
        dynamicAssert(locked[bypass ? 0 : 1],"Attempting to unlock already-unlocked resource");
        locked[bypass ? 0 : 1] <= False;
    endmethod

    method Action lock;
        dynamicAssert(!locked[bypass ? 1 : 0],"Attempting to lock already-locked resource");
        locked[bypass ? 1 : 0] <= True;
    endmethod 

    // clear goes last
    method Action clear = locked[2]._write(init);

endmodule




/** Resource manager interface.
 * Depending on the implementation, unlock may or may not be conflict-free with itself.
 *
 * 
 */

interface ResourceManager#(numeric type ni);
    // return the lowest-index available element, if any
    interface Get#(UInt#(ni))   nextAvailable;

    // lock/unlock a specific element (may or may not carry implicit conditions)
    method Action               lock(UInt#(ni) ri);
    method Action               unlock(UInt#(ni) ri);

    // returns the status of all elements
    method List#(Bool)          status;

    // clear everything to its initial state
    method Action               clear;
endinterface




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

    // lock a specific resource
    method Action lock(UInt#(ni) t) = resources[t].lock;

    // acquire sequences after free/clear if bypass is enabled
    method Action unlock(UInt#(ni) t) = resources[t].unlock;

    // if there is an available resource, lock it and return its index
    interface Get nextAvailable;
        method ActionValue#(UInt#(ni)) get if (List::find(compose(isAvailable,tpl_2),resourcesWithIndex) matches tagged Valid { .ri, .r });
            r.lock;
            return ri;
        endmethod
    endinterface

    method List#(Bool) status = List::map(compose( \not , isAvailable), resources);

    // clear just sends a clear signal to all resources
    method Action clear;
        let o <- List::mapM(doClear,resources);
    endmethod
endmodule





interface ResourceManagerSF#(type resID);
    method Bool anyFree;
    method Bool allFree;

    interface Get#(resID) nextAvailable;
    method Action unlock(resID r);

    method Action clear;
endinterface


module [ModuleContext#(ctxT)] mkResourceManagerFIFO#(Integer n,Bool bypass)(ResourceManagerSF#(UInt#(ni)))
    provisos (
        Alias#(resID,UInt#(ni)),
        NumAlias#(ni,6),
        Gettable#(ctxT,SynthesisOptions)
    );
    Count#(UInt#(ni)) rdPtr <- mkCount(0);
    Count#(UInt#(ni)) wrPtr <- mkCount(0);

    Reg#(Bool) lastEnq[2] <- mkCReg(2,True);    // initial state -> full (rdPtr == wrPtr && lastEnq)
    Reg#(Bool) lastDeq[2] <- mkCReg(2,False);

    // full state before any actions fire

    Bool empty = (rdPtr == wrPtr) && lastDeq[0];
    Bool full = (rdPtr == wrPtr) && lastEnq[0];

    Reg#(Bool) warmup[2] <- mkCReg(2,True);

    Wire#(UInt#(ni)) nextFreeTag <- mkWire;

    let pwGrant <- mkPulseWire, pwNextFromFIFO <- mkPulseWire;

    Lookup#(ni,UInt#(ni)) lut <- mkZeroLatencyLookup(n);

    RWire#(UInt#(ni)) unlockTag <- mkRWire;

    
    // In warmup phase, sequentially grant all tags 0..N-1 so can safely ignore rdPtr/wrPtr
    // After warmup, need wrPtr != rdPtr
    rule nextFreeFromFIFO if (!empty);
        if (!warmup[0])
        begin
            let t <- lut.lookup(rdPtr);
            nextFreeTag <= t;
        end
        else
            nextFreeTag <= rdPtr;

        pwNextFromFIFO.send;
    endrule

    // If granted from FIFO, then bump the read pointer
    rule grantFromFIFO if (pwGrant && pwNextFromFIFO);
        if (rdPtr == fromInteger(n-1))
            warmup[0] <= False;

        rdPtr.incr(1);
    endrule

    if (bypass)
    begin
        // Bypass: provide the incoming freed tag before any tags from FIFO
        (* descending_urgency="nextFreeFromBypass,nextFreeFromFIFO" *)
        rule nextFreeFromBypass if (unlockTag.wget matches tagged Valid .t);
            nextFreeTag <= t;
        endrule
    end

    // enq newly unlocked tag back into FIFO as long as it wasn't consumed by a bypass-grant
    rule enqUnlockTag if (unlockTag.wget matches tagged Valid .t &&& !(bypass && pwGrant));
        lut.write(wrPtr,t);
        wrPtr.incr(1);
    endrule

    rule updateState;
        if (pwGrant && !isValid(unlockTag.wget))
        begin
            lastDeq[0] <= True;
            lastEnq[0] <= False;
        end
        else if (!pwGrant && isValid(unlockTag.wget))
        begin
            lastDeq[0] <= False;
            lastEnq[0] <= True;
        end
    endrule

    method Bool anyFree = !empty;
    method Bool allFree = full;

    interface Get nextAvailable;
        method ActionValue#(resID) get;
            pwGrant.send;
            return nextFreeTag;             // implicit condition: there exists a free tag
        endmethod
    endinterface

    method Action unlock(resID r);
        unlockTag.wset(r);
    endmethod

    method Action clear;
        rdPtr <= 0;
        wrPtr <= 0;
        warmup[1] <= True;
        lastEnq[1] <= True;        // initial state: full
        lastDeq[1] <= False;
    endmethod
endmodule

endpackage
