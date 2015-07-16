`ifndef AFU_MODULE_TYPE
`error "AFU_MODULE_TYPE must be defined!"
`endif

module reset_wrapper(ha_pclock,

		 ah_com,
		 ah_cvalid,

		 ah_compar,

		 ah_cabt,

		 ah_cea,

		 ah_ceapar,

		 ah_cch,

		 ah_csize,

		 ah_ctag,

		 ah_ctagpar,

		 ha_rtag,
		 ha_rtagpar,
		 ha_response,
		 ha_rcredits,
		 ha_rcachestate,
		 ha_rcachepos,
		 ha_rvalid,

		 ha_brtag,
		 ha_brtagpar,
		 ha_brad,
		 ha_brvalid,

		 ah_brdata,

		 ah_brpar,

		 ha_bwtag,
		 ha_bwtagpar,
		 ha_bwad,
		 ha_bwdata,
		 ha_bwpar,
		 ha_bwvalid,

		 ha_mmcfg,
		 ha_mmrnw,
		 ha_mmdw,
		 ha_mmad,
		 ha_mmadpar,
		 ha_mmdata,
		 ha_mmdatapar,
		 ha_mmval,

		 ah_mmdata,
		 ah_mmack,

		 ah_mmdatapar,

		 ha_jcom,
		 ha_jcompar,
		 ha_jea,
		 ha_jeapar,
		 ha_jval,

		 ah_tbreq,

		 ah_jyield,

		 ah_jcack,

		 ah_jerror,

		 ah_jrunning,

		 ah_jdone,

		 ah_brlat,

		 ah_paren,

		 ha_croom);

  input  ha_pclock;

  // value method hwcommand_hwrequest_ah_com
  output [12 : 0] ah_com;
  output ah_cvalid;

  // value method hwcommand_hwrequest_ah_compar
  output ah_compar;

  // value method hwcommand_hwrequest_ah_cabt
  output [2 : 0] ah_cabt;

  // value method hwcommand_hwrequest_ah_cea
  output [63 : 0] ah_cea;

  // value method hwcommand_hwrequest_ah_ceapar
  output ah_ceapar;

  // value method hwcommand_hwrequest_ah_cch
  output [15 : 0] ah_cch;

  // value method hwcommand_hwrequest_ah_csize
  output [11 : 0] ah_csize;

  // value method hwcommand_hwrequest_ah_ctag
  output [7 : 0] ah_ctag;

  // value method hwcommand_hwrequest_ah_ctagpar
  output ah_ctagpar;

  // action method hwcommand_hwresponse_putCacheResponse
  input  [7 : 0] ha_rtag;
  input  ha_rtagpar;
  input  [7 : 0] ha_response;
  input  [8 : 0] ha_rcredits;
  input  [1 : 0] ha_rcachestate;
  input  [12 : 0] ha_rcachepos;
  input  ha_rvalid;

  // action method hwbuffer_hwread_hwrequest_putBR
  input  [7 : 0] ha_brtag;
  input  ha_brtagpar;
  input  [5 : 0] ha_brad;
  input  ha_brvalid;

  // value method hwbuffer_hwread_hwresponse_ah_brdata
  output [511 : 0] ah_brdata;

  // value method hwbuffer_hwread_hwresponse_ah_brpar
  output [7 : 0] ah_brpar;

  // action method hwbuffer_hwwrite_putBufferWriteRequest
  input  [7 : 0] ha_bwtag;
  input  ha_bwtagpar;
  input  [5 : 0] ha_bwad;
  input  [511 : 0] ha_bwdata;
  input  [7 : 0] ha_bwpar;
  input  ha_bwvalid;

  // action method hwmmio_hwrequest_putMMIO
  input  ha_mmcfg;
  input  ha_mmrnw;
  input  ha_mmdw;
  input  [23 : 0] ha_mmad;
  input  ha_mmadpar;
  input  [63 : 0] ha_mmdata;
  input  ha_mmdatapar;
  input  ha_mmval;

  // value method hwmmio_hwresponse_ah_mmdata
  output [63 : 0] ah_mmdata;
  output ah_mmack;

  // value method hwmmio_hwresponse_ah_mmdatapar
  output ah_mmdatapar;

  // action method hwcontrol_put
  input  [7 : 0] ha_jcom;
  input  ha_jcompar;
  input  [63 : 0] ha_jea;
  input  ha_jeapar;
  input  ha_jval;

  // value method hwstatus_ah_tbreq
  output ah_tbreq;

  // value method hwstatus_ah_jyield
  output ah_jyield;

  // value method hwstatus_ah_jcack
  output ah_jcack;

  // value method hwstatus_ah_jerror
  output [63 : 0] ah_jerror;

  // value method hwstatus_ah_jrunning
  output ah_jrunning;

  // value method hwstatus_ah_jdone
  output ah_jdone;

  // value method hwstatus_ah_brlat
  output [3 : 0] ah_brlat;

  // value method hwstatus_ah_paren
  output ah_paren;

  // action method hwpsldesc_putPSLDescription
  input  [7 : 0] ha_croom;

    reg afu_rst = 1'b1;
    reg start_master = 1'b0;

  always@(posedge ha_pclock)
  begin
    // send reset signal to AFU; AFU is responsible for sending back a done pulse
    if (ha_jcom == 8'h80 && ha_jval == 1'b1)
        afu_rst <= 1'b0;
    else
        afu_rst <= 1'b1;
    start_master <= afu_rst;
  end

  wire [12:0] ah_com_i;
  wire [2:0] ah_cabt_i;
  wire [63:0] ah_cea_i;
  wire [15:0] ah_cch_i;
  wire [11:0] ah_csize_i;
  wire [7:0] ah_ctag_i;
  wire [511:0] ah_brdata_i;
  wire [7:0] ah_brpar_i;
  wire [63:0] ah_mmdata_i;
  wire [63:0] ah_jerror_i;
  wire [3:0] ah_brlat_i;

  `AFU_MODULE_TYPE afu (
        .RST_N(afu_rst),
        .ha_pclock(ha_pclock),

		 .ah_com(ah_com_i),
		 .ah_cvalid(ah_cvalid_i),

		 .ah_compar(ah_compar_i),

		 .ah_cabt(ah_cabt_i),

		 .ah_cea(ah_cea_i),

		 .ah_ceapar(ah_ceapar_i),

		 .ah_cch(ah_cch_i),

		 .ah_csize(ah_csize_i),

		 .ah_ctag(ah_ctag_i),

		 .ah_ctagpar(ah_ctagpar_i),

		 .ha_rtag(ha_rtag),
		 .ha_rtagpar(ha_rtagpar),
		 .ha_response(ha_response),
		 .ha_rcredits(ha_rcredits),
		 .ha_rcachestate(ha_rcachestate),
		 .ha_rcachepos(ha_rcachepos),
		 .ha_rvalid(ha_rvalid),

		 .ha_brtag(ha_brtag),
		 .ha_brtagpar(ha_brtagpar),
		 .ha_brad(ha_brad),
		 .ha_brvalid(ha_brvalid),

		 .ah_brdata(ah_brdata_i),

		 .ah_brpar(ah_brpar_i),

		 .ha_bwtag(ha_bwtag),
		 .ha_bwtagpar(ha_bwtagpar),
		 .ha_bwad(ha_bwad),
		 .ha_bwdata(ha_bwdata),
		 .ha_bwpar(ha_bwpar),
		 .ha_bwvalid(ha_bwvalid),

		 .ha_mmcfg(ha_mmcfg),
		 .ha_mmrnw(ha_mmrnw),
		 .ha_mmdw(ha_mmdw),
		 .ha_mmad(ha_mmad),
		 .ha_mmadpar(ha_mmadpar),
		 .ha_mmdata(ha_mmdata),
		 .ha_mmdatapar(ha_mmdatapar),
		 .ha_mmval(ha_mmval),

		 .ah_mmdata(ah_mmdata_i),
		 .ah_mmack(ah_mmack_i),

		 .ah_mmdatapar(ah_mmdatapar_i),

		 .ha_jcom(ha_jcom),
		 .ha_jcompar(ha_jcompar),
		 .ha_jea(ha_jea),
		 .ha_jeapar(ha_jeapar),
		 .ha_jval(ha_jval),

		 .ah_tbreq(ah_tbreq_i),

		 .ah_jyield(ah_jyield_i),

		 .ah_jcack(ah_jcack_i),

		 .ah_jerror(ah_jerror_i),

		 .ah_jrunning(ah_jrunning_i),

		 .ah_jdone(ah_jdone_i),

		 .ah_brlat(ah_brlat_i),

		 .ah_paren(ah_paren_i),

		 .ha_croom(ha_croom)
  );


endmodule
