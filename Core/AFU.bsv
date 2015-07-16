package AFU;

import PSLTypes::*;
import DReg::*;


/** Basic AFU interface
 * Numeric type parameter brlat specifies buffer read latency
 *
 * Client module can provide this and connect to the PSL, but other interfaces offer more functionality
 */

interface AFUWithParity#(numeric type brlat);
    interface ClientU#(CacheCommandWithParity,CacheResponseWithParity)  command;
    interface AFUBufferInterfaceWithParity#(brlat)                      buffer;

    interface ServerARU#(MMIOCommandWithParity,DataWithParity#(MMIOResponse,OddParity))  mmio;

    (* always_ready *)
    interface Put#(JobControlWithParity)    control;

    interface AFUStatus                     status;

    (* always_enabled *)
    method AFUAttributes attributes;

    (* always_enabled *)
    method Action pslAttributes(PSLAttributes desc);
endinterface

interface AFU#(numeric type brlat);
    interface ClientU#(CacheCommand,CacheResponse)  command;
    interface AFUBufferInterface#(brlat)                      buffer;

    interface ServerARU#(MMIOCommand,MMIOResponse)  mmio;

    (* always_ready *)
    interface Put#(JobControl)  control;

    interface AFUStatus         status;

    // static method, must not change during operation (once reset done)
    (* always_ready *)
    method AFUAttributes attributes;

    (* always_enabled *)
    method Action pslAttributes(PSLAttributes desc);
endinterface

interface AFUStatus;
    (* always_ready *)
    method Bool tbreq;

    (* always_ready *)
    method Bool jyield;

    (* always_ready *)
    method Bool jrunning;

    (* always_ready *)
    method Bool jdone;

    (* always_ready *)
    method UInt#(64) jerror;

endinterface


// the AFU side is parametrized by its read latency
interface AFUBufferInterfaceWithParity#(numeric type brlat);
    interface ServerAFL#(BufferReadRequestWithParity,DWordWiseOddParity512,brlat)    writedata;

    (* always_ready *)
    interface Put#(BufferWriteWithParity)                                           readdata;
endinterface

interface AFUBufferInterface#(numeric type brlat); 
    interface ServerAFL#(BufferReadRequest,Bit#(512),brlat)                          writedata;

    (* always_ready *)
    interface Put#(BufferWrite)                                                     readdata;
endinterface

function AFUWithParity#(brlat) ignoreParity(AFU#(brlat) afu) = interface AFUWithParity
    interface ClientU command;
        interface ReadOnly request;
            method CacheCommandWithParity _read = parity_x(afu.command.request);
        endinterface 

        interface Put response;
            method Action put(CacheResponseWithParity resp) = afu.command.response.put(ignore_parity(resp));
        endinterface
    endinterface

    interface AFUBufferInterfaceWithParity buffer;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequestWithParity reqp) = afu.buffer.writedata.request.put(ignore_parity(reqp));
            endinterface

            interface ReadOnly response;
                method DWordWiseOddParity512 _read = parity_x(afu.buffer.writedata.response);
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWriteWithParity reqp) = afu.buffer.readdata.put(ignore_parity(reqp));
        endinterface
    endinterface

    interface ServerARU mmio;
        interface Put request;
            method Action put(MMIOCommandWithParity cmd) = afu.mmio.request.put(ignore_parity(cmd));
        endinterface

        interface ReadOnly response;
            method DataWithParity#(MMIOResponse,OddParity) _read = parity_x(afu.mmio.response);
        endinterface
    endinterface

    interface Put control;
        method Action put(JobControlWithParity jcp) = afu.control.put(ignore_parity(jcp));
    endinterface

    interface AFUStatus status = afu.status;
    method AFUAttributes attributes = AFUAttributes {
        parcheck: afu.attributes.parcheck,
        pargen: False,
        brlat: afu.attributes.brlat
    };
    method Action pslAttributes(PSLAttributes desc) = afu.pslAttributes(desc);
endinterface;

// MReg is a "Maybe Reg"
//  write places a valid value in, read carries implicit condition on validity

typedef Reg#(Maybe#(t)) MReg#(type t);

function Reg#(t) toReg(Reg#(Maybe#(t)) r) = interface Reg;
        method t _read if (r matches tagged Valid .v) = v;
        method Action _write(t i) = r._write(tagged Valid i);
    endinterface;


/***********************************************************************************************************************************
 * mkRegShim(afu)
 *
 * Adds registers in the following paths:
 *      accelerator command request
 *      accelerator command response
 *      MMIO command request
 *      MMIO command response
 */

module mkRegShim#(AFU#(brlat) i)(AFU#(brlat)) provisos (Bits#(CacheCommand,nbc));

    Reg#(Bool) afucmdval <- mkDReg(False);
    Reg#(CacheCommand) afucmd <- mkRegU;

    rule getAFUCmd;
        afucmdval <= True;
        afucmd <= i.command.request;
    endrule

    MReg#(CacheResponse) afuresp_m <- mkDReg(tagged Invalid);
    Reg#(CacheResponse) afuresp = toReg(afuresp_m);

    MReg#(MMIOResponse) mmresp_m <- mkDReg(tagged Invalid);
    Reg#(MMIOResponse) mmresp = toReg(mmresp_m);

    MReg#(MMIOCommand) mmcmd_m <- mkDReg(tagged Invalid);
    Reg#(MMIOCommand) mmcmd = toReg(mmcmd_m);

    // Cache command connection to input
    mkConnection(toGet(i.command.request),toPut(asIfc(afucmd)));
    mkConnection(toGet(afuresp),i.command.response);

    // MMIO connection to input
    mkConnection(toGet(mmcmd),i.mmio.request);

    rule getMMIOResp;
        mmresp_m <= tagged Valid i.mmio.response._read;
        $display($time,": MMIO Response ",fshow(i.mmio.response));
    endrule
//    mkConnection(toGet(i.mmio.response),toPut(asIfc(mmresp)));

    interface ClientU command;
        interface ReadOnly request;
            method CacheCommand _read if (afucmdval) = afucmd;
        endinterface
        interface Put response = toPut(asReg(afuresp));
    endinterface

    interface ServerARU mmio;
        interface ReadOnly response = i.mmio.response;
        interface Put request = toPut(asReg(mmcmd));
    endinterface

    interface AFUBufferInterface            buffer = i.buffer;

    interface Put                           control = i.control;

    interface AFUStatus                     status = i.status;

    method attributes = i.attributes;

    method pslAttributes = i.pslAttributes;
    
endmodule
endpackage
