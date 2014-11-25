//
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

`timescale 1ns / 1ns

module psl_sim (
    input CLK,

  // Command interface
  input             ah_cvalid,      // Command valid
  input     [0:7]   ah_ctag,        // Command tag
  input             ah_ctagpar,     // Command tag parity
  input     [0:12]  ah_com,         // Command code
  input             ah_compar,      // Command code parity
  input     [0:2]   ah_cabt,        // Command address translation ordering
  input     [0:63]  ah_cea,         // Command address
  input             ah_ceapar,      // COmmand address parity
  input     [0:15]  ah_cch,         // NEW context handle for AFU-directed context mode (drive 0 for dedicated process)
  input     [0:11]  ah_csize,       // Command size


  // Buffer interface
  output            ha_brvalid,     // Buffer Read valid
  output    [0:7]   ha_brtag,       // Buffer Read tag
  output            ha_brtagpar,    // Buffer Read tag parity
  output    [0:5]   ha_brad,        // Buffer Read address

  input     [0:511] ah_brdata,      // Buffer Read data
  input     [0:7]   ah_brpar,       // Buffer Read parity

  output            ha_bwvalid,     // Buffer Write valid
  output    [0:7]   ha_bwtag,       // Buffer Write tag
  output            ha_bwtagpar,    // Buffer Write tag parity
  output    [0:5]   ha_bwad,        // Buffer Write address
  output    [0:511] ha_bwdata,      // Buffer Write data
  output    [0:7]   ha_bwpar,       // Buffer Write parity (presented one cycle after bwdata)


  // Response interface
  output            ha_rvalid,      // Response valid
  output    [0:7]   ha_rtag,        // Response tag
  output            ha_rtagpar,     // Response tag parity
  output    [0:7]   ha_response,    // Response
  output    [0:8]   ha_rcredits,    // Response credits
  output    [0:1]   ha_rcachestate, // Response cache state (RESERVED)
  output    [0:12]  ha_rcachepos,   // Response cache pos (RESERVED)


  // MMIO interface
  output            ha_mmval,       // A valid MMIO is present
  output            ha_mmcfg,       // Access is to AFU descriptor space
  output            ha_mmrnw,       // 1 = read, 0 = write
  output            ha_mmdw,        // 1 = doubleword, 0 = word
  output    [0:23]  ha_mmad,        // mmio address
  output            ha_mmadpar,     // mmio address parity
  output    [0:63]  ha_mmdata,      // Write data
  output            ha_mmdatapar,   // Write data parity

  input             ah_mmack,       // Write is complete or Read is valid
  input     [0:63]  ah_mmdata,      // Read data
  input             ah_mmdatapar,   // Read data parity


  // Control interface
  output            ha_jval,        // Job valid
  output    [0:7]   ha_jcom,        // Job command
  output            ha_jcompar,     // Job command parity
  output    [0:63]  ha_jea,         // Job address
  output            ha_jeapar,      // Job address parity

  input             ah_jrunning,    // Job running
  input             ah_jdone,       // Job done
  input     [0:63]  ah_jerror,      // Job error code
  input             ah_jcack,       // Job control ACK? (RESERVED, drive to 0 for dedicated AFU mode)
  input             ah_jyield,      // Job yield (RESERVED, drive to 0 for dedicated AFU mode)
  input             ah_tbreq,       // Timebase command request (single-cycle pulse)

  // Static descriptors
  input             ah_paren,       // AFU supports parity generator (will be checked by PSL)
  input     [0:3]   ah_brlat,       // Buffer Read latency (must be constant after reset)
  output    [0:7]   ha_croom        // Command room, must be captured once device is enabled

);

    // big hack! ha_pclock needs to be in a reg to make the afu driver behave, but clock is driven in from outside
//    reg ha_pclock=1'b0;

//    always @(CLK)
//        ha_pclock <= CLK;

  // Input
  reg    [0:7]    ha_croom_top;
  reg             ha_brvalid_top;
  reg    [0:7]    ha_brtag_top;
  reg             ha_brtagpar_top;
  reg             ha_bwvalid_top;
  reg    [0:7]    ha_bwtag_top;
  reg             ha_bwtagpar_top;
  reg    [0:1023] ha_bwdata_top;
  reg    [0:15]   ha_bwpar_top;
  reg             ha_rvalid_top;
  reg    [0:7]    ha_rtag_top;
  reg             ha_rtagpar_top;
  reg    [0:7]    ha_response_top;
  reg    [0:8]    ha_rcredits_top;
  reg             ha_mmval_top;
  reg             ha_mmcfg_top;
  reg             ha_mmrnw_top;
  reg             ha_mmdw_top;
  reg    [0:23]   ha_mmad_top;
  reg             ha_mmadpar_top;
  reg    [0:63]   ha_mmdata_top;
  reg             ha_mmdatapar_top;
  reg             ha_jval_top;
  reg    [0:7]    ha_jcom_top;
  reg             ha_jcompar_top;
  reg    [0:63]   ha_jea_top;
  reg             ha_jeapar_top;

  // Output
  reg             ah_cvalid_top;
  reg    [0:7]    ah_ctag_top;
  reg             ah_ctagpar_top;
  reg    [0:12]   ah_com_top;
  reg             ah_compar_top;
  reg    [0:2]    ah_cabt_top;
  reg    [0:63]   ah_cea_top;
  reg             ah_ceapar_top;
  reg    [0:15]   ah_cch_top;
  reg    [0:11]   ah_csize_top;
  wire   [0:1023] ah_brdata_top;
  wire   [0:15]   ah_brpar_top;
  wire            ah_brvalid_top;
  reg    [0:7]    ah_brtag_top;
  reg    [0:3]    ah_brlat_top;
  reg             ah_mmack_top;
  reg    [0:63]   ah_mmdata_top;
  reg             ah_mmdatapar_top;
  reg             ah_jdone_top;
  reg             ah_jcack_top;
  reg    [0:63]   ah_jerror_top;
  reg             ah_jyield_top;
  reg             ah_tbreq_top;
  reg             ah_paren_top;

  // Registers
  reg             ah_jrunning_l;
  reg             ha_brvalid_o;
  reg             ha_bwvalid_l;
  reg             ha_bwvalid_o;
  reg    [0:7]    ha_bwtag_l;
  reg             ha_bwtagpar_l;
  reg    [0:7]    ha_bwtag_o;
  reg             ha_bwtagpar_o;
  reg    [0:511]  ha_bwdata_o;
  reg    [0:7]    ha_bwpar_o;
  reg    [0:5]    ha_bwad_o;
  reg    [0:7]    ha_brtag_o;
  reg             ha_brtagpar_o;
  reg             ha_rvalid0;
  reg             ha_rvalid1;
  reg             ha_rvalid2;
  reg             ha_rvalid_o;
  reg    [0:7]    ha_rtag0;
  reg    [0:7]    ha_rtag1;
  reg    [0:7]    ha_rtag2;
  reg    [0:7]    ha_rtag_o;
  reg             ha_rtagpar0;
  reg             ha_rtagpar1;
  reg             ha_rtagpar2;
  reg             ha_rtagpar_o;
  reg    [0:7]    ha_response0;
  reg    [0:7]    ha_response1;
  reg    [0:7]    ha_response2;
  reg    [0:7]    ha_response_o;
  reg    [0:8]    ha_rcredits0;
  reg    [0:8]    ha_rcredits1;
  reg    [0:8]    ha_rcredits2;
  reg    [0:8]    ha_rcredits_o;
  reg    [0:5]    bw_wr_ptr;
  reg    [0:5]    bw_rd_ptr;
  reg    [0:5]    bw_rd_ptr_l;
  reg             bwhalf;
  reg    [0:1023] bwdata;
  reg    [0:15]   bwpar;
  reg    [0:5]    br_wr_ptr;
  reg    [0:5]    br_rd_ptr;
  reg    [0:16]   brvalid_delay;
  reg    [0:7]    bwtag_array  [0:63];
  reg    [0:63]   bwtagpar_array;
  reg    [0:1023] bwdata_array [0:63];
  reg    [0:15]   bwpar_array  [0:63];
  reg    [0:7]    brtag_array  [0:63];
  reg    [0:63]   brtagpar_array;
  reg    [0:7]    brtag_delay  [0:16];
  reg             brhalf;
  reg    [0:511]  brdata_delay;
  reg    [0:7]    brpar_delay;

  // Wires
  wire            ha_brvalid_ul;
  wire            ha_bwvalid_ul;
  wire            ah_jrunning_top;

  // Integers

  integer         i;

  // C code interface registration

  initial begin
    br_wr_ptr <= 0;
    br_rd_ptr <= 0;
    bw_wr_ptr <= 0;
    bw_rd_ptr <= 0;
    ha_jval_top <= 0;
    ha_brvalid_top <= 0;
    ha_bwvalid_top <= 0;
    ha_rvalid_top <= 0;
    ha_mmval_top <= 0;
    ha_croom_top <= 0;
    ha_brtag_top <= 0;
    ha_brtagpar_top <= 0;
    ha_bwtag_top <= 0;
    ha_bwtagpar_top <= 0;
    ha_bwdata_top <= 0;
    ha_bwpar_top <= 0;
    ha_rtag_top <= 0;
    ha_rtagpar_top <= 0;
    ha_response_top <= 0;
    ha_rcredits_top <= 0;
    ha_mmval_top <= 0;
    ha_mmcfg_top <= 0;
    ha_mmrnw_top <= 0;
    ha_mmdw_top <= 0;
    ha_mmad_top <= 0;
    ha_mmadpar_top <= 0;
    ha_mmdata_top <= 0;
    ha_mmdatapar_top <= 0;
    ha_jval_top <= 0;
    ha_jcom_top <= 0;
    ha_jcompar_top <= 0;
    ha_jea_top <= 0;
    ha_jeapar_top <= 0;
    $afu_init;
#20;
    $register_clock(CLK);
    $register_control(ha_jval_top, ha_jcom_top, ha_jcompar_top, ha_jea_top,
                      ha_jeapar_top, ah_jrunning_top, ah_jdone_top,
                      ah_jcack_top, ah_jerror_top, ah_brlat_top, ah_jyield,
                      ah_tbreq_top, ah_paren_top);
    $register_mmio(ha_mmval_top, ha_mmcfg_top, ha_mmrnw_top, ha_mmdw_top,
                   ha_mmad_top, ha_mmadpar_top, ha_mmdata_top, ha_mmdatapar_top,
                   ah_mmack_top, ah_mmdata_top, ah_mmdatapar_top);
    $register_command(ha_croom_top, ah_cvalid_top, ah_ctag_top, ah_ctagpar_top,
                      ah_com_top, ah_compar_top, ah_cabt_top,
                      ah_cea_top, ah_ceapar_top, ah_cch_top, ah_csize_top);
    $register_rd_buffer(ha_brvalid_top, ha_brtag_top, ha_brtagpar_top,
                        ah_brdata_top, ah_brpar_top, ah_brvalid_top,
                        ah_brtag_top, ah_brlat_top);
    $register_wr_buffer(ha_bwvalid_top, ha_bwtag_top, ha_bwtagpar_top,
                        ha_bwdata_top, ha_bwpar_top);
    $register_response(ha_rvalid_top, ha_rtag_top, ha_rtagpar_top,
                       ha_response_top, ha_rcredits_top);
  end

  // Currently unused inputs

  assign ha_rcachestate = 0;
  assign ha_rcachepos   = 0;

  // Passthrough signals

  assign ha_croom   = ha_croom_top;
  assign ha_mmval   = ha_mmval_top;
  assign ha_mmcfg   = ha_mmcfg_top;
  assign ha_mmrnw   = ha_mmrnw_top;
  assign ha_mmdw    = ha_mmdw_top;
  assign ha_mmad    = ha_mmad_top;
  assign ha_mmdata  = ha_mmdata_top;
  assign ha_jval    = ha_jval_top;
  assign ha_jcom    = ha_jcom_top;
  assign ha_jcompar = ha_jcompar_top;
  assign ha_jea     = ha_jea_top;
  assign ha_jeapar  = ha_jeapar_top;

  always @ (posedge CLK) begin
    ah_jrunning_l <= ah_jrunning;
  end

  assign ah_jrunning_top = ah_jrunning_l;

  // Latch top level signals

  always @ (posedge CLK) begin
    ah_ctag_top <= ah_ctag;
    ah_ctagpar_top <= ah_ctagpar;
    ah_com_top <= ah_com;
    ah_compar_top <= ah_compar;
    ah_cabt_top <= ah_cabt;
    ah_cea_top <= ah_cea;
    ah_ceapar_top <= ah_ceapar;
    ah_cch_top <= ah_cch;
    ah_csize_top <= ah_csize;
    ah_mmdata_top <= ah_mmdata;
    ah_jerror_top <= ah_jerror;
    ah_jdone_top <= ah_jdone;
    ah_brlat_top <= ah_brlat;
    ah_jyield_top <= ah_jyield;
    ah_tbreq_top <= ah_tbreq;
    ah_paren_top <= ah_paren;
    ah_cvalid_top <= ah_cvalid;
    ah_mmack_top <= ah_mmack;
    ah_jcack_top <= ah_jcack;
  end

  // Breakpoint output, need at least 1 output or Quartus will optimize away
  // and fail to compile.

  assign breakpoint = ah_mmack_top | ah_cvalid_top | ah_brvalid_top |
                      ah_jdone | ah_jcack | (ah_jrunning & !ah_jrunning_l);

  // Buffer write

  always @ (posedge CLK) begin
    if (ha_bwvalid_top)
      bw_wr_ptr <= bw_wr_ptr+6'h01;
    else
      bw_wr_ptr <= bw_wr_ptr;
  end

  always @ (posedge CLK) begin
    if (ha_bwvalid_l & !bwhalf)
      bw_rd_ptr <= bw_rd_ptr+6'h01;
    else
      bw_rd_ptr <= bw_rd_ptr;
  end

  always @ (posedge CLK)
    bw_rd_ptr_l <= bw_rd_ptr;

  always @ (posedge CLK) begin
    if (ha_bwvalid_top)
      bwtag_array[bw_wr_ptr] <= ha_bwtag_top;
  end

  always @ (posedge CLK) begin
    if (ha_bwvalid_top)
      bwtagpar_array[bw_wr_ptr] <= ha_bwtagpar_top;
  end

  assign ha_bwvalid_ul = (bw_rd_ptr==bw_wr_ptr) ? 1'b0 : 1'b1;

  always @ (posedge CLK) begin
    if (ha_bwvalid_ul)
      ha_bwtag_l <= bwtag_array[bw_rd_ptr];
    else
      ha_bwtag_l <= 8'b0;
  end

  always @ (posedge CLK) begin
    if (ha_bwvalid_ul)
      ha_bwtagpar_l <= bwtagpar_array[bw_rd_ptr];
    else
      ha_bwtagpar_l <= 1'b1;
  end

  always @ (posedge CLK)
    ha_bwtag_o <= ha_bwtag_l;

  always @ (posedge CLK)
    ha_bwtagpar_o <= ha_bwtagpar_l;

  always @ (posedge CLK) begin
    if (ha_bwvalid_top)
      bwdata_array[bw_wr_ptr] <= ha_bwdata_top;
  end

  always @ (posedge CLK) begin
    if (ha_bwvalid_ul)
      bwdata <= bwdata_array[bw_rd_ptr];
  end

  always @ (posedge CLK) begin
    if (ha_bwvalid_top)
      bwpar_array[bw_wr_ptr] <= ha_bwpar_top;
  end

  always @ (posedge CLK) begin
    if (ha_bwvalid_ul)
      bwpar <= bwpar_array[bw_rd_ptr_l];
  end

  always @ (posedge CLK)
    ha_bwvalid_l <= ha_bwvalid_ul;

  always @ (posedge CLK)
    ha_bwvalid_o <= ha_bwvalid_l;

  always @ (posedge CLK) begin
    if (ha_bwvalid_l & !bwhalf)
      bwhalf <= 1;
    else
      bwhalf <= 0;
  end

  always @ (posedge CLK)
    ha_bwad_o <= {5'b0, bwhalf};

  always @ (posedge CLK) begin
    if (!bwhalf)
      ha_bwdata_o <= bwdata[0:511];
    else
      ha_bwdata_o <= bwdata[512:1023];
  end

  always @ (posedge CLK) begin
    if (bwhalf)
      ha_bwpar_o <= bwpar[0:7];
    else
      ha_bwpar_o <= bwpar[8:15];
  end

  // Buffer read

  always @ (posedge CLK) begin
    if (ha_brvalid_top)
      br_wr_ptr <= br_wr_ptr+6'h01;
    else
      br_wr_ptr <= br_wr_ptr;
  end

  always @ (posedge CLK) begin
    if (ha_brvalid_o & !brhalf)
      br_rd_ptr <= br_rd_ptr+6'h01;
    else
      br_rd_ptr <= br_rd_ptr;
  end

  always @ (posedge CLK) begin
    for (i = 0; i <= 16; i = i + 1) begin
      if (i == ah_brlat+1) begin
        brvalid_delay[i] <= ha_brvalid_o & !brhalf;
        brtag_delay[i] <= ha_brtag_o;
      end else if (i == 16) begin
        brvalid_delay[16] <= 1'b0;
        brtag_delay[16] <= 8'h00;
      end else begin
        brvalid_delay[i] <= brvalid_delay[i+1];
        brtag_delay[i] <= brtag_delay[i+1];
      end
    end
  end

  always @ (posedge CLK) begin
    if (ha_brvalid_top)
      brtag_array[br_wr_ptr] <= ha_brtag_top;
  end

  always @ (posedge CLK) begin
    if (ha_brvalid_top)
      brtagpar_array[br_wr_ptr] <= ha_brtagpar_top;
  end

  assign ha_brvalid_ul = (br_rd_ptr==br_wr_ptr) ? 1'b0 : 1'b1;

  always @ (posedge CLK) begin
    if (ha_brvalid_ul)
      ha_brtag_o <= brtag_array[br_rd_ptr];
  end

  always @ (posedge CLK) begin
    if (ha_brvalid_ul)
      ha_brtagpar_o <= brtagpar_array[br_rd_ptr];
  end

  always @ (posedge CLK) begin
    if (br_rd_ptr==br_wr_ptr)
      ha_brvalid_o <= 1'b0;
    else
      ha_brvalid_o <= 1'b1;
  end

  always @ (posedge CLK) begin
    if (ha_brvalid_o & !brhalf)
      brhalf <= 1'b1;
    else
      brhalf <= 1'b0;
  end

  assign ha_brad = {5'b0, brhalf};

  always @ (posedge CLK) begin
    brdata_delay <= ah_brdata;
  end

  always @ (posedge CLK) begin
    brpar_delay <= ah_brpar;
  end

  assign ah_brdata_top = {brdata_delay, ah_brdata};
  assign ah_brpar_top = {brpar_delay, ah_brpar};
  assign ah_brvalid_top = brvalid_delay[0];

  // Response delay

  always @ (posedge CLK) begin
    ha_rvalid0 <= ha_rvalid_top;
    ha_rvalid1 <= ha_rvalid0;
    ha_rvalid2 <= ha_rvalid1;
    ha_rvalid_o <= ha_rvalid2;
    ha_rtag0 <= ha_rtag_top;
    ha_rtag1 <= ha_rtag0;
    ha_rtag2 <= ha_rtag1;
    ha_rtag_o <= ha_rtag2;
    ha_rtagpar0 <= ha_rtagpar_top;
    ha_rtagpar1 <= ha_rtagpar0;
    ha_rtagpar2 <= ha_rtagpar1;
    ha_rtagpar_o <= ha_rtagpar2;
    ha_response0 <= ha_response_top;
    ha_response1 <= ha_response0;
    ha_response2 <= ha_response1;
    ha_response_o <= ha_response2;
    ha_rcredits0 <= ha_rcredits_top;
    ha_rcredits1 <= ha_rcredits0;
    ha_rcredits2 <= ha_rcredits1;
    ha_rcredits_o <= ha_rcredits2;
  end

  assign ha_response = ha_response_o;
  assign ha_bwvalid  = ha_bwvalid_o;
  assign ha_brvalid  = ha_brvalid_o;
  assign ha_bwtag    = ha_bwtag_o;
  assign ha_bwtagpar = ha_bwtagpar_o;
  assign ha_bwdata   = ha_bwdata_o;
  assign ha_bwpar    = ha_bwpar_o;
  assign ha_bwad     = ha_bwad_o;
  assign ha_brtag    = ha_brtag_o;
  assign ha_brtagpar = ha_brtagpar_o;
  assign ha_rvalid   = ha_rvalid_o;
  assign ha_rtag     = ha_rtag_o;
  assign ha_rtagpar  = ha_rtagpar_o;
  assign ha_rcredits = ha_rcredits_o;

endmodule
