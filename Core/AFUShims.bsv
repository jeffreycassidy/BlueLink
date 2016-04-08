package AFUShims;

import ClientServerU::*;
import PSLTypes::*;
import AFU::*;

/** Adds a zero-latency shim that prints out the traffic going to/from an AFU.
 */

module mkAFUShimSnoop#(AFUWithParity#(brlat) afu)(AFUWithParity#(brlat));

    rule cmdRequest;
        $display($time,": Command request ",fshow(afu.command.request));
    endrule

    rule bufReadResponse;
        $display($time,": Buffer read response ",fshow(afu.buffer.writedata.response));
    endrule

    rule mmioResponse;
        $display($time,": MMIO response ",fshow(afu.mmio.response));
    endrule

    interface ClientU command;
        interface Put response;
            method Action put(CacheResponseWithParity presp);
                $display($time,": ",fshow(presp));
                afu.command.response.put(presp);
            endmethod
        endinterface

        interface ReadOnly request = afu.command.request;
    endinterface

    interface AFUBufferInterfaceWithParity buffer;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequestWithParity pbr);
                    afu.buffer.writedata.request.put(pbr);
                    $display($time,": ",fshow(pbr));
                endmethod
            endinterface

            interface ReadOnly response = afu.buffer.writedata.response;
        endinterface

        interface Put readdata;
            method Action put(BufferWriteWithParity pbw);
                afu.buffer.readdata.put(pbw);
                $display($time,": ",fshow(pbw));
            endmethod
        endinterface
    endinterface

    interface ServerARU mmio;
        interface Put request;
            method Action put(MMIOCommandWithParity pcmd);
                $display($time,": ",fshow(pcmd));
                afu.mmio.request.put(pcmd);
            endmethod
        endinterface

        interface ReadOnly response = afu.mmio.response;
    endinterface 

    interface Put control;
        method Action put(JobControlWithParity pjc);
            $display($time,": ",fshow(pjc));
            afu.control.put(pjc);
        endmethod
    endinterface

    method AFUStatus status = afu.status;

    method Bool paren=afu.paren;
endmodule




/** AFU shim to strip off the parity bits without checking
 */

function AFUWithParity#(brlat) afuParityWrapper(AFU#(brlat) afu) = interface AFUWithParity;
    interface ClientU command;
        interface Put response;
            method Action put(CacheResponseWithParity pResp) = afu.command.response.put(ignore_parity(pResp));
        endinterface
        interface ReadOnly request;
            method CacheCommandWithParity _read = make_parity_struct(False,afu.command.request._read);
        endinterface
    endinterface

    interface AFUBufferInterfaceWithParity buffer;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequestWithParity pBR) = afu.buffer.writedata.request.put(ignore_parity(pBR));
            endinterface

            interface ReadOnly response;
                method DWordWiseOddParity512 _read = make_parity_struct(False,afu.buffer.writedata.response._read);
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWriteWithParity pBW) = afu.buffer.readdata.put(ignore_parity(pBW));
        endinterface
    endinterface

    interface ServerARU mmio;
        interface Put request;
            method Action put(MMIOCommandWithParity pMM) = afu.mmio.request.put(ignore_parity(pMM));
        endinterface

        interface ReadOnly response;
            method MMIOResponseWithParity _read = make_parity_struct(False,afu.mmio.response._read);
        endinterface
    endinterface

    interface Put control;
        method Action put(JobControlWithParity pJC) = afu.control.put(ignore_parity(pJC));
    endinterface

    method AFUStatus status = afu.status;

    method Bool paren=False;
endinterface;

endpackage
