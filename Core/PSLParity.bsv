package PSLParity;

import PSLTypes::*;

module mkParityShim#(Bool pargen,Bool parcheck,PSL psl)(PSL);

    interface ServerARU command;
        interface Put request;
            method Action put(CacheCommand cmd) = pargen ? parity_calc(cmd) : parity_x(cmd);
        endinterface

        interface ReadOnly response;
            method ReadOnly _read if (!parcheck || parity_ok()) = parity_ignore(psl.command.response);
        endinterface
    endinterface

    interface PSLBufferInterface buffer;
        interface ClientU writedata;
            interface Put response;
                method Action put(BufferReadRequest req) = psl.buffer.writedata.put(
                    pargen ? parity_calc(req) : parity_x(req));
            endinterface

            interface ReadOnly request;
                method DWordWiseOddParity512 _read if (!parcheck || parity_ok(psl.buffer.writedata.response))
                    = psl.buffer.writedata.response;
            endinterface
        endinterface

        interface ReadOnly readdata;
            method DataWithParity#(Bit#(512),WordWiseOddParity) _read if (!parcheck || parity_ok()) =
                parity_ignore(psl.buffer.readdata);
        endinterface
    endinterface

    interface ClientU mmio;
        interface Put response;
            method Action put(MMIOCommand mmcmd) = pargen ? parity_calc(mmcmd) : parity_x(mmcmd);
        endinterface

        interface ReadOnly request;
            method MMIOCommand _read if (!parcheck || parity_ok(psl.mmio.request)) = parity_ignore(psl.mmio.request);
        endinterface
    endinterface

    interface ReadOnly control;
        method JobControl _read if (!parcheck || parity_ok(psl.control)) = parity_ignore(psl.control);
    endinterface

    method Action status(UInt#(64) ah_jerror,Bool ah_jrunning) = psl.stats(ah_jerror,ah_jrunning);

    method Action yield = psl.yield;
    method Action tbreq = psl.tbreq;
    method Action jcack = psl.jcack;
    method PSL_Description description = psl.description;
endmodule

endpackage
