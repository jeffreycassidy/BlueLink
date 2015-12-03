package CmdCounter;

import ClientServer::*;
import PSLTypes::*;
import Vector::*;
import BuildVector::*;
import GetPut::*;
import PSLResponseCodes::*;
import Counter::*;
import Cntrs::*;
import DReg::*;



/** Provides a map/zip-compatible way of writing to various interfaces
 */

typeclass Writeable#(type ifcT,type t);
    function Action write(t i,ifcT ifc);
endtypeclass

instance Writeable#(Count#(t),t);
    function Action write(t i,Count#(t) ifc) = ifc._write(i);
endinstance

instance Writeable#(RWire#(t),t);
    function Action write(t i,RWire#(t) rw) = rw.wset(i);
endinstance

instance Writeable#(Reg#(Maybe#(t)),t);
    function Action write(t i,Reg#(Maybe#(t)) r) = r._write(tagged Valid i);
endinstance



typedef struct {
    UInt#(n)    nCmdTotal;

    UInt#(n)    nRespDone;
    UInt#(n)    nRespAError;
    UInt#(n)    nRespDError;
    UInt#(n)    nRespNLock;
    UInt#(n)    nRespNRes;
    UInt#(n)    nRespFlushed;
    UInt#(n)    nRespFault;
    UInt#(n)    nRespFailed;
    UInt#(n)    nRespPaged;

    UInt#(n)    nRespInvalid;
} CmdCounts#(numeric type n) deriving(Bits,FShow);


interface CmdCounter#(numeric type n);
    interface Client#(CacheCommand,CacheResponse)  c;

    method Action           clearCounters;
    method CmdCounts#(n)    counts;
endinterface




/** Wraps a command Client with counters to track number of commands issued and the responses received. 
 * Does not add any latency or conditions to the command path.
 */

module mkCmdCounter#(Client#(CacheCommand,CacheResponse) c)(CmdCounter#(n));
    // the counters
    Vector#(9,Count#(UInt#(n))) respCounts   <- replicateM(mkCount(0));
    Count#(UInt#(n))             nCmdTotal    <- mkCount(0);
    Count#(UInt#(n))             nRespInvalid <- mkCount(0);

    // helpers to translate from response codes into vector indices
    Vector#(9,PSLResponseCode) respCodes = vec(
        PSLResponseCode'(Done),
        Aerror,
        Derror,
        Nlock,
        Nres,
        Flushed,
        Fault,
        Failed,
        Paged);

    // register to hold the response code, and update the counters 1 tick after it's received
    Reg#(Maybe#(PSLResponseCode)) respQ <- mkDReg(tagged Invalid);

    rule countResponse if (respQ matches tagged Valid .rcode);
        let idx = findElem(rcode,respCodes);
        if (idx matches tagged Valid .i)
            respCounts[i].incr(1);
        else
            nRespInvalid.incr(1);
    endrule


    // The passthrough client interface
    interface Client c;
        interface Get request;
            method ActionValue#(CacheCommand) get;
                let req <- c.request.get;
                nCmdTotal.incr(1);
                return req;
            endmethod
        endinterface

        interface Put response;
            method Action put(CacheResponse resp);
                c.response.put(resp);
                respQ <= tagged Valid resp.response;
            endmethod
        endinterface
    endinterface

    // set all counters to zero, scheduling after read & increment
    method Action clearCounters;
        nCmdTotal <= 0;
        mapM_(write(UInt#(n)'(0)),respCounts);
        nRespInvalid <= 0;
    endmethod

    // return the counts
    method CmdCounts#(n) counts = CmdCounts {
        nCmdTotal:      nCmdTotal,

        nRespDone:      respCounts[0],
        nRespAError:    respCounts[1],
        nRespDError:    respCounts[2],
        nRespNLock:     respCounts[3],
        nRespNRes:      respCounts[4],
        nRespFlushed:   respCounts[5],
        nRespFault:     respCounts[6],
        nRespFailed:    respCounts[7],
        nRespPaged:     respCounts[8],

        nRespInvalid:   nRespInvalid
    };
endmodule

endpackage
