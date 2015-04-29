package PSL;

import PSLTypes::*;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PSL & AFU toplevel interfaces
//
// PSL and AFU are mostly conjugate interfaces (generally a Put for every Get, Client for every Server etc)
// some glue logic is required to connect the control interface (found in the Connectable#(...) instance )
// 
// The client should write a module conforming to the AFU interface, instantiate it and a mkPSL, and then connect the two



/** Basic PSL interface, using as direct a mapping as possible from module ports to BSV methods
 */

interface PSL;
    interface ServerARU#(CacheCommandWithParity,CacheResponseWithParity)                command;
    interface PSLBufferInterfaceWithParity                                              buffer;
    interface ClientU#(MMIOCommandWithParity,DataWithParity#(MMIOResponse,OddParity))   mmio;

    interface ReadOnly#(JobControlWithParity)                               control;

    (* always_enabled,always_ready *)
    method Action status(UInt#(64) ah_jerror, Bool ah_jrunning);

    (* always_ready *)
    method Action done;             // assert for single pulse to ack reset, or say accelerator done

    (* always_ready *)
    method Action yield;            // single-cycle pulse to yield

    (* always_ready *)
    method Action tbreq;            // single-cycle pulse to request timebase

    (* always_ready *)
    method Action jcack;

    (* always_ready *)
    method PSL_Description description;
endinterface

interface PSLNoParity;
    interface ServerARU#(CacheCommand,CacheResponse)    command;
    interface PSLBufferInterface                        buffer;
    interface ClientU#(MMIOCommand,MMIOResponse)        mmio;
    interface ReadOnly#(JobControl)                     control;

    (* always_enabled,always_ready *)
    method Action status(UInt#(64) ah_jerror,Bool ah_jrunning);

    (* always_ready *)
    method Action done;

    (* always_ready *)
    method Action tbreq;

    (* always_ready *)
    method Action jcack;

    (* always_ready *)
    method PSL_Description description;
endinterface

// Static PSL descriptor passed to AFU; static from reset to done, may change in between
typedef struct {
    UInt#(8)    croom;              // Number of supported in-flight commands
} PSL_Description deriving(Bits);

import "BVI" psl_sim_wrapper = module mkPSL#(AFUAttributes afudesc)(PSL);
    default_reset no_reset;
    default_clock (CLK) <- exposeCurrentClock;

    interface ServerARU command;
        interface Put request;
            method put(ah_command_struct) enable (ah_cvalid);
        endinterface

        interface ReadOnly response;
            method ha_response_struct _read ready(ha_rvalid);
        endinterface
    endinterface

    method ha_psl_description description();

    interface PSLBufferInterfaceWithParity buffer;
        interface ClientU writedata;
            interface ReadOnly request;
                method ha_buffer_read_struct _read() ready(ha_brvalid);
            endinterface

            interface Put response;
                method put(ah_buffer_read_struct) enable((*unused*)dummy);
            endinterface
        endinterface

        interface ReadOnly readdata;
            method ha_buffer_write_struct _read() ready(ha_bwvalid);
        endinterface
    endinterface


    interface ClientU mmio;
        interface ReadOnly request;
            method ha_mmio_struct _read() ready(ha_mmval);
        endinterface

        interface Put response;
            method put(ah_mmio_struct) enable(ah_mmack);
        endinterface
    endinterface

    interface ReadOnly control;
        method ha_control_struct _read() ready(ha_jval);
    endinterface

    method status(ah_jerror,ah_jrunning) enable((*unused*)dummy0);
    method done()  enable(ah_jdone);
    method jcack() enable(ah_jcack);
    method yield() enable(ah_jyield);
    method tbreq() enable(ah_tbreq);


    // AFU description wires (static after initialization)
    port ah_paren  = afudesc.pargen;
    port ah_brlat  = afudesc.brlat;

    // command interface conflict-free with everything else
    schedule (status,command.request.put,command.response._read,yield,done,tbreq,jcack) CF
        (mmio.request._read,mmio.response.put,buffer.readdata._read,buffer.writedata.request._read,
        control._read,description);
    schedule (command.request.put,command.response._read,jcack)   CF  command.response._read;
    schedule command.request.put        C   command.request.put;
    schedule status CF (done,yield,tbreq,jcack);

    // buffer interface conflict-free with everything else
    schedule (buffer.readdata._read,buffer.writedata.request._read,buffer.writedata.response.put,status,done,yield,tbreq,jcack) CF
        (mmio.response.put,mmio.request._read,command.request.put,command.response._read,control._read,description);

    schedule buffer.writedata.response.put  C   buffer.writedata.response.put;

    schedule (buffer.writedata.request._read,buffer.readdata._read,status,done,yield,tbreq,jcack) CF
        (buffer.writedata.request._read,buffer.readdata._read,buffer.writedata.response.put);

    schedule mmio.response.put  C   mmio.response.put;
    schedule (mmio.response.put,mmio.request._read) CF
        (control._read,description,mmio.request._read,done,yield,tbreq);

    schedule control._read         CF  (control._read,description);

    // get methods do not self-conflict
    schedule buffer.writedata.request._read CF buffer.writedata.request._read;
    schedule command.response._read         CF command.response._read;
    schedule buffer.writedata.request._read CF buffer.writedata.response.put;
    schedule mmio.request._read             CF mmio.response.put;
    schedule description                    CF description;

    schedule yield                          CF (done,tbreq,jcack);
    schedule tbreq                          CF (done,jcack);
    schedule done                           CF jcack;

    schedule yield                          C yield;
    schedule tbreq                          C tbreq;
    schedule done                           C done;
    schedule status                         C status;
    schedule jcack                          C jcack;

    schedule buffer.writedata.request._read CF buffer.writedata.response.put;
endmodule 

endpackage
