// from IBM VHDL code
//component afu
//  port (
//    ah_cvalid      : out std_ulogic;
//    ah_ctag        : out std_ulogic_vector(0 to 7);
//    ah_com         : out std_ulogic_vector(0 to 12);
//    ah_cabt        : out std_ulogic_vector(0 to 2);
//    ah_cea         : out std_ulogic_vector(0 to 63);
//    ah_cch         : out std_ulogic_vector(0 to 15);
//    ah_csize       : out std_ulogic_vector(0 to 11);
//    ha_croom       : in  std_ulogic_vector(0 to 7);
//    ah_ctagpar     : out std_ulogic;
//    ah_compar      : out std_ulogic;
//    ah_ceapar      : out std_ulogic;
//    ha_brvalid     : in  std_ulogic;
//    ha_brtag       : in  std_ulogic_vector(0 to 7);
//    ha_brad        : in  std_ulogic_vector(0 to 5);
//    ah_brlat       : out std_ulogic_vector(0 to 3);
//    ah_brdata      : out std_ulogic_vector(0 to 511);
//    ah_brpar       : out std_ulogic_vector(0 to 7);
//    ha_bwvalid     : in  std_ulogic;
//    ha_bwtag       : in  std_ulogic_vector(0 to 7);
//    ha_bwad        : in  std_ulogic_vector(0 to 5);
//    ha_bwdata      : in  std_ulogic_vector(0 to 511);
//    ha_bwpar       : in  std_ulogic_vector(0 to 7);
//    ha_brtagpar    : in  std_ulogic;
//    ha_bwtagpar    : in  std_ulogic;
//    ha_rvalid      : in  std_ulogic;
//    ha_rtag        : in  std_ulogic_vector(0 to 7);
//    ha_response    : in  std_ulogic_vector(0 to 7);
//    ha_rcredits    : in  std_ulogic_vector(0 to 8);
//    ha_rcachestate : in  std_ulogic_vector(0 to 1);
//    ha_rcachepos   : in  std_ulogic_vector(0 to 12);
//    ha_rtagpar     : in  std_ulogic;
//    ha_mmval       : in  std_ulogic;
//    ha_mmrnw       : in  std_ulogic;
//    ha_mmdw        : in  std_ulogic;
//    ha_mmad        : in  std_ulogic_vector(0 to 23);
//    ha_mmdata      : in  std_ulogic_vector(0 to 63);
//    ha_mmcfg       : in  std_ulogic;
//    ah_mmack       : out std_ulogic;
//    ah_mmdata      : out std_ulogic_vector(0 to 63);
//    ha_mmadpar     : in  std_ulogic;
//    ha_mmdatapar   : in  std_ulogic;
//    ah_mmdatapar   : out std_ulogic;
//    ha_jval        : in  std_ulogic;
//    ha_jcom        : in  std_ulogic_vector(0 to 7);
//    ha_jea         : in  std_ulogic_vector(0 to 63);
//    ah_jrunning    : out std_ulogic;
//    ah_jdone       : out std_ulogic;
//    ah_jcack       : out std_ulogic;
//    ah_jerror      : out std_ulogic_vector(0 to 63);
//    ah_tbreq       : out std_ulogic;
//    ah_jyield      : out std_ulogic;
//    ha_jeapar      : in  std_ulogic;
//    ha_jcompar     : in  std_ulogic;
//    ah_paren       : out std_ulogic;
//    ha_pclock      : in  std_ulogic);
//end component;
//

module afu_syn_wrapped (
    input CLK,

    

// from IBM VHDL code
//component afu
//  port (
//    ah_cvalid      : out std_ulogic;
//    ah_ctag        : out std_ulogic_vector(0 to 7);
//    ah_com         : out std_ulogic_vector(0 to 12);
//    ah_cabt        : out std_ulogic_vector(0 to 2);
//    ah_cea         : out std_ulogic_vector(0 to 63);
//    ah_cch         : out std_ulogic_vector(0 to 15);
//    ah_csize       : out std_ulogic_vector(0 to 11);

//    ha_croom       : in  std_ulogic_vector(0 to 7);
//    ah_ctagpar     : out std_ulogic;
//    ah_compar      : out std_ulogic;
//    ah_ceapar      : out std_ulogic;
//    ha_brvalid     : in  std_ulogic;
//    ha_brtag       : in  std_ulogic_vector(0 to 7);
//    ha_brad        : in  std_ulogic_vector(0 to 5);
//    ah_brlat       : out std_ulogic_vector(0 to 3);
//    ah_brdata      : out std_ulogic_vector(0 to 511);
//    ah_brpar       : out std_ulogic_vector(0 to 7);
//    ha_bwvalid     : in  std_ulogic;
//    ha_bwtag       : in  std_ulogic_vector(0 to 7);
//    ha_bwad        : in  std_ulogic_vector(0 to 5);
//    ha_bwdata      : in  std_ulogic_vector(0 to 511);
//    ha_bwpar       : in  std_ulogic_vector(0 to 7);
//    ha_brtagpar    : in  std_ulogic;
//    ha_bwtagpar    : in  std_ulogic;
//    ha_rvalid      : in  std_ulogic;
//    ha_rtag        : in  std_ulogic_vector(0 to 7);
//    ha_response    : in  std_ulogic_vector(0 to 7);
//    ha_rcredits    : in  std_ulogic_vector(0 to 8);
//    ha_rcachestate : in  std_ulogic_vector(0 to 1);
//    ha_rcachepos   : in  std_ulogic_vector(0 to 12);
//    ha_rtagpar     : in  std_ulogic;
//    ha_mmval       : in  std_ulogic;
//    ha_mmrnw       : in  std_ulogic;
//    ha_mmdw        : in  std_ulogic;
//    ha_mmad        : in  std_ulogic_vector(0 to 23);
//    ha_mmdata      : in  std_ulogic_vector(0 to 63);
//    ha_mmcfg       : in  std_ulogic;
//    ah_mmack       : out std_ulogic;
//    ah_mmdata      : out std_ulogic_vector(0 to 63);
//    ha_mmadpar     : in  std_ulogic;
//    ha_mmdatapar   : in  std_ulogic;
//    ah_mmdatapar   : out std_ulogic;
//    ha_jval        : in  std_ulogic;
//    ha_jcom        : in  std_ulogic_vector(0 to 7);
//    ha_jea         : in  std_ulogic_vector(0 to 63);
//    ah_jrunning    : out std_ulogic;
//    ah_jdone       : out std_ulogic;
//    ah_jcack       : out std_ulogic;
//    ah_jerror      : out std_ulogic_vector(0 to 63);
//    ah_tbreq       : out std_ulogic;
//    ah_jyield      : out std_ulogic;
//    ha_jeapar      : in  std_ulogic;
//    ha_jcompar     : in  std_ulogic;
//    ah_paren       : out std_ulogic;
//    ha_pclock      : in  std_ulogic);
//end component;
//


