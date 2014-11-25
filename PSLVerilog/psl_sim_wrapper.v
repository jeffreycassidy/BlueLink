// Copyright 2014 International Business Machines
//
// Modifications copyright 2014 Jeffrey Cassidy
//      Outlined top.v into a submodule psl_sim.v
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
//

module psl_sim_wrapper (
    input CLK,

    // Accelerator command interface
    input           ah_cvalid,
    input   [0:118] ah_command_struct,


    // Acclerator buffer interface
    // read
    output          ha_brvalid,
    output  [0:14]  ha_buffer_read_struct,
    input   [0:519] ah_buffer_read_struct,

    // write
    output          ha_bwvalid,
    output  [0:534] ha_buffer_write_struct,


    // Response interface
    output          ha_rvalid,
    output  [0:40]  ha_response_struct,


    // Accelerator MMIO interface
    output          ha_mmval,
    output  [0:92]  ha_mmio_struct,

    input           ah_mmack,
    input   [0:64]  ah_mmio_struct,


    // Accelerator command interface
    output          ha_jval,
    output  [0:73]  ha_control_struct,

    input           ah_jrunning,
    input   [0:63]  ah_jerror,
    input           ah_jdone,
    input           ah_jcack,
    input           ah_jyield,
    input           ah_tbreq,

    // static config description
    input           ah_paren,
    input   [0:3]   ah_brlat,
    output  [0:31]  ha_psl_description,

    input           dummy,
    input           dummy0
);


// AFU->PSL command request (enable with ah_cvalid)
wire    [0:7]   ah_ctag;
wire            ah_ctagpar;
wire    [0:12]  ah_com;
wire            ah_compar;
wire    [0:2]   ah_cabt;
wire    [0:63]  ah_cea;
wire            ah_ceapar;
wire    [0:15]  ah_cch;
wire    [0:11]  ah_csize;
assign { ah_ctag, ah_ctagpar, ah_com, ah_compar, ah_cabt, ah_cea, ah_ceapar, ah_cch, ah_csize } = ah_command_struct;

// Buffer read request (ready when ha_brvalid)
wire    [0:7]   ha_brtag;
wire            ha_brtagpar;
wire    [0:5]   ha_brad;
assign ha_buffer_read_struct = { ha_brtag, ha_brtagpar, ha_brad };


// Buffer read response (must be valid brlat cycles after ha_brvalid)
wire    [0:511] ah_brdata;
wire    [0:7]   ah_brpar;
assign { ah_brdata, ah_brpar } = ah_buffer_read_struct;


// Buffer write request (ready with ha_bwvalid)
wire    [0:7]   ha_bwtag;
wire            ha_bwtagpar;
wire    [0:5]   ha_bwad;
wire    [0:511] ha_bwdata;
wire    [0:7]   ha_bwpar;
assign ha_buffer_write_struct = { ha_bwtag, ha_bwtagpar, ha_bwad, ha_bwdata, ha_bwpar };


// Command response (ready with ha_rvalid)
wire    [0:7]   ha_rtag;
wire            ha_rtagpar;
wire    [0:7]   ha_response;
wire    [0:8]   ha_rcredits;
wire    [0:1]   ha_rcachestate;
wire    [0:12]  ha_rcachepos;
assign ha_response_struct = { ha_rtag, ha_rtagpar, ha_response, ha_rcredits, ha_rcachestate, ha_rcachepos };


// MMIO command (ready on ha_mmval)
wire            ha_mmcfg;
wire            ha_mmrnw;
wire            ha_mmdw;
wire    [0:23]  ha_mmad;
wire            ha_mmadpar;
wire    [0:63]  ha_mmdata;
wire            ha_mmdatapar;
assign ha_mmio_struct = { ha_mmcfg, ha_mmrnw, ha_mmdw, ha_mmad, ha_mmadpar, ha_mmdata, ha_mmdatapar };


// MMIO response (enable on ah_mmack)
wire    [0:63]  ah_mmdata;
wire            ah_mmdatapar;
assign { ah_mmdata, ah_mmdatapar } = ah_mmio_struct;


// Job control interface (ready on ha_jval)
wire            ha_jval_o;
wire    [0:7]   ha_jcom;
wire            ha_jcompar;
wire    [0:63]  ha_jea;
wire            ha_jeapar;
assign ha_control_struct = { ha_jcom, ha_jcompar, ha_jea, ha_jeapar };

// Pass the PSL descriptor through, no enable or valid
wire    [0:7]   ha_croom;
wire    [0:4]   ha_lop;
wire    [0:6]   ha_lsize;
assign ha_psl_description = { ha_croom, ha_lop, ha_lsize };


psl_sim wrapped (
  .CLK(CLK),

  // Accelerator command interface
  .ah_cvalid(ah_cvalid),
  .ah_ctag(ah_ctag),    
  .ah_ctagpar(ah_ctagpar),
  .ah_com(ah_com),        
  .ah_compar(ah_compar),
  .ah_cabt(ah_cabt),        
  .ah_cea(ah_cea),
  .ah_ceapar(ah_ceapar),
  .ah_cch(ah_cch),
  .ah_csize(ah_csize),   


  // Accelerator buffer interface
  .ha_brvalid(ha_brvalid),     
  .ha_brtag(ha_brtag),       
  .ha_brtagpar(ha_brtagpar),
  .ha_brad(ha_brad),        

  .ah_brdata(ah_brdata),      
  .ah_brpar(ah_brpar),       

  .ha_bwvalid(ha_bwvalid),     
  .ha_bwtag(ha_bwtag),       
  .ha_bwtagpar(ha_bwtagpar),
  .ha_bwad(ha_bwad),        
  .ha_bwdata(ha_bwdata),      
  .ha_bwpar(ha_bwpar),


  // Response interface
  .ha_rvalid(ha_rvalid),      
  .ha_rtag(ha_rtag),        
  .ha_rtagpar(ha_rtagpar),
  .ha_response(ha_response),
  .ha_rcredits(ha_rcredits),    
  .ha_rcachestate(ha_rcachestate), 
  .ha_rcachepos(ha_rcachepos),   

  
  // MMIO interface
  .ha_mmval(ha_mmval),
  .ha_mmcfg(ha_mmcfg),
  .ha_mmrnw(ha_mmrnw),       
  .ha_mmdw(ha_mmdw),
  .ha_mmad(ha_mmad),
  .ha_mmadpar(ha_mmadpar),
  .ha_mmdata(ha_mmdata),  
  .ha_mmdatapar(ha_mmdatapar),

  .ah_mmack(ah_mmack),       
  .ah_mmdata(ah_mmdata),
  .ah_mmdatapar(ah_mmdatapar),


  // Control interface
  .ha_jval(ha_jval_o),
  .ha_jcom(ha_jcom),
  .ha_jcompar(ha_jcompar),
  .ha_jea(ha_jea),
  .ha_jeapar(ha_jeapar),

  .ah_jrunning(ah_jrunning),    
  .ah_jdone(ah_jdone),       
  .ah_jerror(ah_jerror),      
  .ah_jcack(ah_jcack),
  .ah_jyield(ah_jyield),      
  .ah_tbreq(ah_tbreq),

  .ah_paren(ah_paren),
  .ah_brlat(ah_brlat),     
  .ha_croom(ha_croom)
);

assign ha_jval = ha_jval_o;

endmodule
