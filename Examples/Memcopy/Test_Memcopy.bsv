// Connects the AFU to the PSL with a SnoopConmnection (prints all events to stdout)

package Test_Memcopy;

import PSLTypes::*;
import Connectable::*;
import PSLInterface::*;
import Memcopy::*;
import SnoopConnection::*;
import CmdBuf::*;

module mkMemcopyTB();
	AFU#(1) afu <- mkMemcopy;
    CmdBuf#(8) cbuf <- mkCmdBuf(CmdBufOptions { autoRetryPaged: True, notifyOnPagedRetry: False, showErrors: True });
	let 	psl <- mkPSL(afu.description);


    Wire#(CacheCommandWithParity)  ocmd  <- mkWire;
    Wire#(CacheResponseWithParity) iresp <- mkWire;

    rule bufRequest;
        let req <- cbuf.psl.request.get;
        ocmd <= parity_x(req);
    endrule

	mkSnoopConnection("PSL",psl,"BUF",
        interface AFU#(1);
            interface ClientU command;
                interface Put       response;
                    method Action put(CacheResponseWithParity rp) = cbuf.psl.response.put(ignore_parity(rp));
                endinterface
                interface ReadOnly request;
                    method CacheCommandWithParity _read = ocmd;
                endinterface
            endinterface

            interface AFUBufferInterfaceWithParity buffer = afu.buffer;
            interface ServerARU mmio = afu.mmio;
            interface Put control = afu.control;
            method Bool tbreq = afu.tbreq;
            method Bool yield = afu.yield;
            method AFU_Status status = afu.status;
            method AFU_Description description = afu.description;
        endinterface);


    rule afuResponse;
        let resp <- cbuf.afu.response.get;
        afu.command.response.put(parity_x(resp));
        
    endrule

    rule afuRequest;
        let req = afu.command.request;
        cbuf.afu.request.put(ignore_parity(req));
    endrule
endmodule

endpackage
