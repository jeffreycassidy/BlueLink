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

endpackage
