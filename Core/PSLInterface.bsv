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

package PSLInterface;

// Imports the IBM-provided Verilog PSL simulation module into Bluespec as mkPSL

import FShow::*;
import ClientServer::*;
import GetPut::*;
import Parity::*;
import Connectable::*;

import PSLTypes::*;
import "BVI" psl_sim_wrapper = module mkPSL#(AFU_Description afudesc)(PSL);
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
