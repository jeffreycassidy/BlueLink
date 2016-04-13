package CmdArbiter;

import Vector::*;
import CmdTagManager::*;

import ClientServerU::*;
import ProgrammableLUT::*;
import HList::*;
import PSLTypes::*;
import DReg::*;
import GetPut::*;

module mkCmdPriorityArbiter#(CmdTagManagerClientPort tagMgr)(Vector#(nPorts,CmdTagManagerClientPort))
    provisos (
        Alias#(UInt#(4),clientIndex),
        Bits#(RequestTag,nbRequestTag),
        NumAlias#(brlat,2));

    Vector#(nPorts,CmdTagManagerClientPort) clients;

    let syn = hCons(AlteraStratixV,hNil);

    MultiReadLookup#(nbRequestTag,clientIndex) tagClientMap <- mkMultiReadZeroLatencyLookup(syn,3,64);

    // client indices for the various input ports
    Reg#(Maybe#(Tuple2#(clientIndex,CacheResponse))) cmdResponseClient <- mkDReg(tagged Invalid);

    RWire#(clientIndex) brRequestClient <- mkRWire;
    Reg#(Maybe#(Tuple2#(clientIndex,BufferWrite))) bwClient <- mkReg(tagged Invalid);
    Reg#(Vector#(brlat,Maybe#(clientIndex))) brRequestClientD <- mkReg(replicate(tagged Invalid));

    rule getClientIndexForCmdResponse;
        let cl <- tagClientMap.lookup[0](tagMgr.response.rtag);
        cmdResponseClient <= tagged Valid tuple2(cl,tagMgr.response);
    endrule

    rule getClientIndexForBufRead;
        let cl <- tagClientMap.lookup[1](tagMgr.writedata.request.brtag);
        brRequestClient.wset(cl);
    endrule

    rule getClientIndexForBufWrite;
        let cl <- tagClientMap.lookup[2](tagMgr.readdata.bwtag);
        bwClient <= tagged Valid tuple2(cl,tagMgr.readdata);
    endrule

    rule shiftRegForBufReadDelay;
        brRequestClientD <= shiftInAt0(brRequestClientD,brRequestClient.wget);
    endrule


    // the client ports
    function Bool read(PulseWire pw) = pw;

    Vector#(nPorts,PulseWire) pwGrant <- replicateM(mkPulseWire);

    Vector#(nPorts,Bool) clientGrant = map (read,pwGrant);

    Vector#(TAdd#(nPorts,1),Bool) block = scanl(
        ( \|| ) ,
        False,
        clientGrant);


    for(Integer i=0;i<valueOf(nPorts);i=i+1)
    begin
        clients[i] = interface CmdTagManagerClientPort;
            method ActionValue#(RequestTag) issue(CmdWithoutTag cmd) if (!block[i]);
                pwGrant[i].send;
                let tag <- tagMgr.issue(cmd);
                tagClientMap.write(tag,fromInteger(i));
                return tag;
            endmethod

            method CacheResponse response if (cmdResponseClient matches tagged Valid { .cl, .resp } &&& cl == fromInteger(i)) =
                resp;

            interface ClientU writedata;
                interface ReadOnly request;
                    method BufferReadRequest _read if (brRequestClient.wget matches tagged Valid .cl &&& cl == fromInteger(i)) = tagMgr.writedata.request;
                endinterface

                interface Put response;
                    method Action put(Bit#(512) resp) if (last(brRequestClientD) matches tagged Valid .cl &&& cl == fromInteger(i)) = tagMgr.writedata.response.put(resp);
                endinterface
            endinterface

            interface ReadOnly readdata;
                method BufferWrite _read if (bwClient matches tagged Valid { .cl, .bw } &&& cl == fromInteger(i)) = bw;
            endinterface
        endinterface;
    end

    return clients;
endmodule

endpackage
