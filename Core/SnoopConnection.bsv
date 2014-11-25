// This file is part of BlueLink, a Bluespec library supporting the IBM CAPI coherent POWER8-FPGA link
// github.com/jeffreycassidy/BlueLink
//
// Copyright 2014 Jeffrey Cassidy
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package SnoopConnection;

// This module defines a typeclass SnoopConnection, which is similar to Connectable#() except that it prints the contents of
// all messages flowing back and forth. It contains all instances necessary for monitoring an AFU-PSL connection.

import Connectable::*;
import FShow::*;
import GetPut::*;
import ClientServer::*;
import ClientServerFL::*;
import Convenience::*;

import PSLTypes::*;

typeclass SnoopConnection#(type ifc_a,type ifc_b) provisos (Connectable#(ifc_a,ifc_b));
    module mkSnoopConnection#(String name_a,ifc_a a,String name_b,ifc_b b)();
        mkConnection(a,b);
    endmodule
endtypeclass

instance SnoopConnection#(PSL,AFU#(brlat));
    module mkSnoopConnection#(String name_a,PSL psl,String name_b,AFU#(brlat) afu)();
        mkSnoopConnection(name_b,afu.command,name_a,psl.command);
        mkSnoopConnection(name_a,psl.buffer,name_b,afu.buffer);
        mkSnoopConnection(name_a,psl.mmio,name_b,afu.mmio);
        mkSnoopConnection(name_a,toGet(psl.control),name_b,afu.control);

        mkDoIf(afu.status.done,psl.done);
        mkDoIf(afu.status.done,$display($time,": AFU done"));

        rule sendstatus;
            psl.status(afu.status.errcode,afu.status.running);
        endrule
    endmodule
endinstance

instance SnoopConnection#(Get#(t),Put#(t)) provisos (FShow#(t));
    module mkSnoopConnection#(String name_a,Get#(t) a,String name_b,Put#(t) b)();
        rule getputandshow;
            t v <- a.get;
            $display($time,": %s==>%s ",name_a,name_b,fshow(v));
            b.put(v);
        endrule
    endmodule
endinstance

instance SnoopConnection#(ClientU#(req_t,res_t),ServerARU#(req_t,res_t)) provisos (FShow#(req_t),FShow#(res_t));
    module mkSnoopConnection#(String name_a,ClientU#(req_t,res_t) c,String name_b,ServerARU#(req_t,res_t) s)();
        mkSnoopConnection(name_a,toGet(asIfc(c.request)), name_b,s.request);
        mkSnoopConnection(name_b,toGet(asIfc(s.response)),name_a,c.response);
    endmodule
endinstance

instance SnoopConnection#(ClientU#(req_t,res_t),ServerFL#(req_t,res_t,lat)) provisos (FShow#(req_t),FShow#(res_t));
    module mkSnoopConnection#(String name_a,ClientU#(req_t,res_t) c,String name_b,ServerFL#(req_t,res_t,lat) s)();
        mkSnoopConnection(name_a,toGet(asIfc(c.request)), name_b,s.request);
        mkSnoopConnection(name_b,toGet(asIfc(s.response)),name_a,c.response);
    endmodule
endinstance

instance SnoopConnection#(PSLBufferInterfaceWithParity,AFUBufferInterfaceWithParity#(brlat));
    module mkSnoopConnection#(String name_a,PSLBufferInterfaceWithParity pslbuf,String name_b,AFUBufferInterfaceWithParity#(brlat) afubuf)(); 
        mkSnoopConnection(name_a,toGet(asIfc(pslbuf.readdata)),name_b,afubuf.readdata);
        mkSnoopConnection(name_a,pslbuf.writedata,name_b,afubuf.writedata);
    endmodule

endinstance

endpackage
