/** 
 *
 *  `define MODULENAME
 *
 * Creates a module `MODULENAME_wrapper with ports reversed and reset logic inserted for use in
 *
 *
 * RESET STRATEGY
 *
 *      Power-on reset
 *
 *      Interception of PSL Reset job command
 *
 * 
 * PORT NUMBERING
 *      Reverses the direction of bit vectors from [0 : N-1] in the PSL to [N-1 : 0] per Bluespec convention
 * 
 */

`define WRAPMODULENAME(name) ``name``_wrapper

module `WRAPMODULENAME(`MODULENAME) (
	input  [   0:   5]  ha_brad,
	output ah_cvalid,
	input  [   0:   7]  ha_brtag,
	input  [   0:   7]  ha_bwpar,
	input  [   0: 511]  ha_bwdata,
	input  ha_rtagpar,
	input  [   0:   5]  ha_bwad,
	input  ha_pclock,
	input  ha_brvalid,
	input  [   0:  12]  ha_rcachepos,
	input  ha_mmval,
	input  ha_bwtagpar,
	input  ha_bwvalid,
	input  [   0:   7]  ha_croom,
	output ah_jrunning,
	input  ha_brtagpar,
	output [   0:   7]  ah_ctag,
	output ah_ctagpar,
	output [   0:  12]  ah_com,
	output ah_compar,
	output [   0:   2]  ah_cabt,
	output [   0:  63]  ah_cea,
	output ah_ceapar,
	output [   0:  15]  ah_cch,
	output [   0:  11]  ah_csize,
	output ah_paren,
	input  [   0:   7]  ha_rtag,
	input  ha_mmcfg,
	input  ha_mmdw,
	input  [   0:   7]  ha_response,
	input  [   0:   1]  ha_rcachestate,
	input  ha_mmrnw,
	input  ha_mmadpar,
	input  [   0:  63]  ha_mmdata,
	output ah_mmack,
	input  ha_mmdatapar,
	input  ha_rvalid,
	output [   0:  63]  ah_mmdata,
	output ah_mmdatapar,
	input  [   0:   7]  ha_bwtag,
	input  [   0:   7]  ha_jcom,
	input  [   0:  23]  ha_mmad,
	input  ha_jcompar,
	output ah_jcack,
	input  [   0:  63]  ha_jea,
	input  ha_jeapar,
	input  ha_jval,
	input  [   0:   8]  ha_rcredits,
	output [   0: 511]  ah_brdata,
	output [   0:   7]  ah_brpar,
	output ah_tbreq,
	output ah_jyield,
	output ah_jdone,
	output [   0:  63]  ah_jerror,
	output [   0:   3]  ah_brlat
);

  wire [   5:   0] ha_brad_rev;
  wire ah_cvalid_i;
  wire [   7:   0] ha_brtag_rev;
  wire [   7:   0] ha_bwpar_rev;
  wire [ 511:   0] ha_bwdata_rev;
  wire [   5:   0] ha_bwad_rev;
  wire [  12:   0] ha_rcachepos_rev;
  wire [   7:   0] ha_croom_rev;
  wire ah_jrunning_i;
  wire [   7:   0] ah_ctag_rev;
  wire ah_ctagpar_i;
  wire [  12:   0] ah_com_rev;
  wire ah_compar_i;
  wire [   2:   0] ah_cabt_rev;
  wire [  63:   0] ah_cea_rev;
  wire ah_ceapar_i;
  wire [  15:   0] ah_cch_rev;
  wire [  11:   0] ah_csize_rev;
  wire ah_paren_i;
  wire [   7:   0] ha_rtag_rev;
  wire [   7:   0] ha_response_rev;
  wire [   1:   0] ha_rcachestate_rev;
  wire [  63:   0] ha_mmdata_rev;
  wire ah_mmack_i;
  wire [  63:   0] ah_mmdata_rev;
  wire ah_mmdatapar_i;
  wire [   7:   0] ha_bwtag_rev;
  wire [   7:   0] ha_jcom_rev;
  wire [  23:   0] ha_mmad_rev;
  wire ah_jcack_i;
  wire [  63:   0] ha_jea_rev;
  wire [   8:   0] ha_rcredits_rev;
  wire [ 511:   0] ah_brdata_rev;
  wire [   7:   0] ah_brpar_rev;
  wire ah_tbreq_i;
  wire ah_jyield_i;
  wire ah_jdone_i;
  wire [  63:   0] ah_jerror_rev;
  wire [   3:   0] ah_brlat_rev;


  // power-on reset generation (hold RST_N low for 1 cycle, and delay for 4 cycles when a reset is provided)
  // delay enables register duplication to ease fanout pressures

  // active-high reset signal from PSL
  assign rst_in = ha_jval && ha_jcom == 8'h80;

  // delayed active-low reset signal from PSL
  reg [1:4] rstN_delay = 4'b0000;

  always@(posedge ha_pclock)
  begin
    rstN_delay <= { ~rst_in, rstN_delay[1:3] };
  end

  assign rst_out = rstN_delay[4];


  `MODULENAME afurev(
    .RST_N(rst_out),
	.ha_brad(ha_brad_rev),
	.ah_cvalid(ah_cvalid_i),
	.ha_brtag(ha_brtag_rev),
	.ha_bwpar(ha_bwpar_rev),
	.ha_bwdata(ha_bwdata_rev),
	.ha_rtagpar(ha_rtagpar),
	.ha_bwad(ha_bwad_rev),
	.ha_pclock(ha_pclock),
	.ha_brvalid(ha_brvalid),
	.ha_rcachepos(ha_rcachepos_rev),
	.ha_mmval(ha_mmval),
	.ha_bwtagpar(ha_bwtagpar),
	.ha_bwvalid(ha_bwvalid),
	.ha_croom(ha_croom_rev),
	.ah_jrunning(ah_jrunning_i),
	.ha_brtagpar(ha_brtagpar),
	.ah_ctag(ah_ctag_rev),
	.ah_ctagpar(ah_ctagpar_i),
	.ah_com(ah_com_rev),
	.ah_compar(ah_compar_i),
	.ah_cabt(ah_cabt_rev),
	.ah_cea(ah_cea_rev),
	.ah_ceapar(ah_ceapar_i),
	.ah_cch(ah_cch_rev),
	.ah_csize(ah_csize_rev),
	.ah_paren(ah_paren_i),
	.ha_rtag(ha_rtag_rev),
	.ha_mmcfg(ha_mmcfg),
	.ha_mmdw(ha_mmdw),
	.ha_response(ha_response_rev),
	.ha_rcachestate(ha_rcachestate_rev),
	.ha_mmrnw(ha_mmrnw),
	.ha_mmadpar(ha_mmadpar),
	.ha_mmdata(ha_mmdata_rev),
	.ah_mmack(ah_mmack_i),
	.ha_mmdatapar(ha_mmdatapar),
	.ha_rvalid(ha_rvalid),
	.ah_mmdata(ah_mmdata_rev),
	.ah_mmdatapar(ah_mmdatapar_i),
	.ha_bwtag(ha_bwtag_rev),
	.ha_jcom(ha_jcom_rev),
	.ha_mmad(ha_mmad_rev),
	.ha_jcompar(ha_jcompar),
	.ah_jcack(ah_jcack_i),
	.ha_jea(ha_jea_rev),
	.ha_jeapar(ha_jeapar),
	.ha_jval(ha_jval),
	.ha_rcredits(ha_rcredits_rev),
	.ah_brdata(ah_brdata_rev),
	.ah_brpar(ah_brpar_rev),
	.ah_tbreq(ah_tbreq_i),
	.ah_jyield(ah_jyield_i),
	.ah_jdone(ah_jdone_i),
	.ah_jerror(ah_jerror_rev),
	.ah_brlat(ah_brlat_rev)
);



  assign ha_brad_rev = ha_brad;
  assign ah_cvalid = ah_cvalid_i;
  assign ha_brtag_rev = ha_brtag;
  assign ha_bwpar_rev = ha_bwpar;
  assign ha_bwdata_rev = ha_bwdata;
  assign ha_bwad_rev = ha_bwad;
  assign ha_rcachepos_rev = ha_rcachepos;
  assign ha_croom_rev = ha_croom;
  assign ah_jrunning = ah_jrunning_i;
  assign ah_ctag = ah_ctag_rev;
  assign ah_ctagpar = ah_ctagpar_i;
  assign ah_com = ah_com_rev;
  assign ah_compar = ah_compar_i;
  assign ah_cabt = ah_cabt_rev;
  assign ah_cea = ah_cea_rev;
  assign ah_ceapar = ah_ceapar_i;
  assign ah_cch = ah_cch_rev;
  assign ah_csize = ah_csize_rev;
  assign ah_paren = ah_paren_i;
  assign ha_rtag_rev = ha_rtag;
  assign ha_response_rev = ha_response;
  assign ha_rcachestate_rev = ha_rcachestate;
  assign ha_mmdata_rev = ha_mmdata;
  assign ah_mmack = ah_mmack_i;
  assign ah_mmdata = ah_mmdata_rev;
  assign ah_mmdatapar = ah_mmdatapar_i;
  assign ha_bwtag_rev = ha_bwtag;
  assign ha_jcom_rev = ha_jcom;
  assign ha_mmad_rev = ha_mmad;
  assign ah_jcack = ah_jcack_i;
  assign ha_jea_rev = ha_jea;
  assign ha_rcredits_rev = ha_rcredits;
  assign ah_brdata = ah_brdata_rev;
  assign ah_brpar = ah_brpar_rev;
  assign ah_tbreq = ah_tbreq_i;
  assign ah_jyield = ah_jyield_i;
  assign ah_jdone = ah_jdone_i;
  assign ah_jerror = ah_jerror_rev;
  assign ah_brlat = ah_brlat_rev;
endmodule
