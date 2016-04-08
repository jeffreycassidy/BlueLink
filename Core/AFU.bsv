package AFU;

import PSLTypes::*;
import ClientServerU::*;


/** Basic AFU interface
 * Numeric type parameter brlat specifies buffer read latency (clock cycles after ha_brvalid)
 *
 * Client module can provide this and connect to the PSL, but other interfaces offer more functionality
 */

interface AFUWithParity#(numeric type brlat);
    interface ClientU#(CacheCommandWithParity,CacheResponseWithParity)      command;
    interface AFUBufferInterfaceWithParity#(brlat)                          buffer;

    interface ServerARU#(MMIOCommandWithParity,MMIOResponseWithParity)      mmio;

    (* always_ready *)
    interface Put#(JobControlWithParity)                                    control;

    interface AFUStatus                                                     status;

    (* always_enabled *)
    method Bool                                                             paren;
endinterface


interface AFU#(numeric type brlat);
    interface ClientU#(CacheCommand,CacheResponse)                          command;
    interface AFUBufferInterface#(brlat)                                    buffer;
    interface ServerARU#(MMIOCommand,MMIOResponse)                          mmio;
    
    (* always_ready *)
    interface Put#(JobControl)                                              control;

    interface AFUStatus                                                     status;
endinterface


/** AFUStatus interface as presented to the PSL. It is pin-compatible as defined here (no need for wrapper).
 */

interface AFUStatus;
    (* always_ready, prefix="ah_tbreq" *)
    method Bool tbreq;

    (* always_ready, prefix="ah_jyield" *)
    method Bool jyield;

    (* always_ready, prefix="ah_jrunning" *)
    method Bool jrunning;

    (* always_ready, prefix="ah_jdone" *)
    method Bool jdone;

    (* always_ready, prefix="ah_jerror" *)
    method UInt#(64) jerror;

    (* always_ready, prefix="ah_jcack" *)
    method Bool jcack;
endinterface


interface AFUBufferInterfaceWithParity#(numeric type brlat);
    interface ServerAFL#(BufferReadRequestWithParity,DWordWiseOddParity512,brlat)   writedata;

    (* always_ready *)
    interface Put#(BufferWriteWithParity)                                           readdata;
endinterface

interface AFUBufferInterface#(numeric type brlat); 
    interface ServerAFL#(BufferReadRequest,Bit#(512),brlat)                         writedata;

    (* always_ready *)
    interface Put#(BufferWrite)                                                     readdata;
endinterface

endpackage
