package ClientServerU;

import Connectable::*;
import ClientServer::*;
import GetPut::*;
import Assert::*;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Interface defintions for dealing with low-level Verilog modules
//
// AR: Always ready (can accept a request at any time)
// U:  Unbuffered (response is presented for one cycle only, no handshake)
// FL: Fixed latency
//
// This differs from normal Bluespec semantics where Get/Put often are connected with FIFOs

interface ServerAFL#(type req_t,type res_t,numeric type lat);
    (* always_ready *)
    interface Put#(req_t)       request;

    interface ReadOnly#(res_t)  response;
endinterface

interface ServerARU#(type req_t,type res_t);
    (* always_ready *)
    interface Put#(req_t)       request;
    interface ReadOnly#(res_t)  response;
endinterface

interface ClientU#(type req_t,type res_t);
    interface ReadOnly#(req_t)  request;

    (* always_ready *)
    interface Put#(res_t)       response;
endinterface


/** Makes a Client into a ClientU, with appropriate assertions.
 *      Requests are unbuffered and always accepted by ClientU, so pull Client request continuously and make available
 *      Responses are always_ready, so always accept and assert that client accepts it
 */

module mkClientUFromClient#(Client#(req_t,res_t) c)(ClientU#(req_t,res_t)) provisos (Bits#(req_t,nr),Bits#(res_t,ns));
    RWire#(req_t) req <- mkRWire;
    RWire#(res_t) res <- mkRWire;
    let pwAccept <- mkPulseWire;

    mkConnection(c.request,toPut(req));

    rule putResponse if (res.wget matches tagged Valid .v);
        pwAccept.send;
        c.response.put(v);
    endrule

    continuousAssert(pwAccept || !isValid(res.wget),
        "mkClientUFromClient: Client is not ready to response despite always_ready requirement at ClientU interface");

    interface Put response = toPut(res);
    interface ReadOnly request;
        method req_t _read if (req.wget matches tagged Valid .v) = v;
    endinterface
endmodule


/** Makes a ClientU into a Client, with appropriate checks.
 *      Requests are unbuffered, so must be consumed when available (assert)
 *      ClientU is always_ready to accept response, so just pass through
 */

module mkClientFromClientU#(ClientU#(req_t,res_t) c)(Client#(req_t,res_t)) provisos (Bits#(req_t,nr),Bits#(res_t,ns));
    RWire#(req_t) req <- mkRWire;
    let pwAck <- mkPulseWire;

    rule getRequest;
        let r = c.request._read;
        req.wset(r);        
    endrule

    continuousAssert(pwAck || !isValid(req.wget),
        "mkClientFromClientU: Client has ignored an unbuffered request which will be discarded");

    interface Get request;
        method ActionValue#(req_t) get if (req.wget matches tagged Valid .v);
            pwAck.send;
            return v;
        endmethod
    endinterface
    

    // ClientU response is already asserted always_ready, so must be OK
    interface Put response = c.response;
endmodule


instance Connectable#(ClientU#(req_t,res_t),ServerARU#(req_t,res_t));
    module mkConnection#(ClientU#(req_t,res_t) client,ServerARU#(req_t,res_t) server)();
        rule reqconnect;
            server.request.put(client.request);
        endrule
        rule resconnect;
            client.response.put(server.response);
        endrule
    endmodule
endinstance


instance Connectable#(ClientU#(req_t,res_t),ServerAFL#(req_t,res_t,lat));
    module mkConnection#(ClientU#(req_t,res_t) client,ServerAFL#(req_t,res_t,lat) server)();
        rule reqconnect;
            server.request.put(client.request);
        endrule
        rule resconnect;
            client.response.put(server.response);
        endrule
    endmodule
endinstance

// Note: client is unbuffered, user must make sure that Server does not ignore a request due to blocking
instance Connectable#(ClientU#(req_t,res_t),Server#(req_t,res_t));
    module mkConnection#(ClientU#(req_t,res_t) client,Server#(req_t,res_t) server)();
        rule reqconn;
            server.request.put(client.request);
        endrule
        mkConnection(server.response,client.response);
    endmodule
endinstance

// Note: client is unbuffered, user must make sure that ServerFL (fixed latency) does not ignore a request due to blocking
//instance Connectable#(ClientU#(req_t,res_t),ServerFL#(req_t,res_t,lat));
//    module mkConnection#(ClientU#(req_t,res_t) client,ServerFL#(req_t,res_t,lat) server)();
//        mkConnection(toGet(asIfc(client.request)),server.request);
//        mkConnection(server.response,client.response);
//    endmodule
//endinstance

endpackage
