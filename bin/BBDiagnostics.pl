#!/usr/bin/perl -w
# Copyright (c) 2013-2014 Apple Inc. All rights reserved.
#
# Edit History
# -------------------------------------------------------------------------------------------------------
# when      who       version   what, where, why
# --------  -------   --------  -------------------------------------------------------------------------
# 12/26/13  sun_yu    V1.0      Initial Created
# 05/15/14  sun_yu    V2.0      Sync code change from Daniel Song
#                               Decode mode capability and band capability
#                               Fix bug when generate html report
#                               Always return 0
# 27/06/14  sun_yu    V3.0      Fix the layout problem in N56, N61, J82
#                               Get rid of the NV mismatch items
# 14/07/14  sun_yu    V4.0      Add all PRI/GRI NV/EFS to ignore list
#                               Disable PRI/GRI push for Mav10
#                               Add basic info in NV Diagnostic report
# 23/07/14  sun_yu    V5.0      Loop check whether diag disabled after stop diag trace
#                               Don't show PRI result for Mav10
# 06/08/14  sun_yu    V5.1      Get HWConfig/Version info from AP side
# 26/09/14  sun_yu    V5.2      Add NV 6828, 22605, 24203 into ignore list
##########################################################################################################

use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use Env qw(USER);

my $gStartTime;
my $gDiagTraceOn = 0;
my $gFullLog = 0;
my $gLogHandler;
my $gOutHandler;
my $gTxtReportHandler;

my $OutFormat = "\t%-16s\t: %s\n";
my $MaxElementPerLine = 4;
my $OutFormatN56 = "\t%-16s\t: %s\n";
my $MaxElementPerLineN56 = 4;
my $OutFormatN61 = "\t%-16s\t: %s\n";
my $MaxElementPerLineN61 = 4;
my $OutFormatJ82 = "\t%-16s\t: %s\n";
my $MaxElementPerLineJ82 = 4;
my $OutFormatJ97 = "\t%-16s\t: %s\n";
my $MaxElementPerLineJ97 = 4;
my $OutFormatJ99 = "\t%-16s\t: %s\n";
my $MaxElementPerLineJ99 = 4;

my $OutFolder = "/var/$USER/Library/Logs/BBDiagnostics/";

my $TOO_SHORT = 0xDEADABCD;
my $gNvResult = "NA";
my $gNvCategory = "NA";
my $gNvType = "NA";
my $gNvLen = "NA";
my $gEfsPath = "NA";
my $gNvId = "NA";
my $gNvExpVal = "NA";
my $gNvRealVal = "NA";
my $gPrevDecodeLocation = "gNvRealVal";

my $gProdName = 'NA';
my $gIsPhoneActivated = 1;
  
my $gHWConfig = 'NA';
my $gHWVersion = 'NA';
my $gCarrierBundleName;
my $gCarrierBundleVersion;
my $gCarrierBundle;
my $gMCC;
my $gMNC;
my $gBBVersion;
  
my %gRFCalNVList = ( );
my %gNVIdNamePair = ( );

my @Mav10Prod = ('N56', 'N61', 'J82', 'J97', 'J99');
my %gProdList = ('MAV10'=>\@Mav10Prod);

my @gEfsIgnoreList = (
    #Below efs path are defined in mav_qmi_bsp.c and configured by QMI dynamically. 
    '/nv/item_files/modem/nas/imsi_switch',
    '/nv/item_files/data/3gpp/ds_3gpp_multi_pdn_same_apn',
    '/nv/item_files/modem/nas/mav_hplmn_prov_info',
    '/nv/item_files/modem/nas/mav_lte_band_regulation_eu',
    '/nv/item_files/modem/nas/mav_lte_band_regulation_na',
    '/nv/item_files/modem/nas/mav_lte_band_regulation_asia',
    '/nv/item_files/modem/nas/mav_lte_band_regulation_ocean',
    '/nv/item_files/modem/nas/mav_lte_band_regulation_africa',
    '/nv/item_files/modem/nas/mav_lte_band_regulation_la',
     
     #iPLMN is configured according to current network info
    '/nv/item_files/modem/nas/iPLMN', 
    
    #From plistparser.c
    "/nv/item_files/jcdma/jcdma_mode",
    "/nv/item_files/modem/nas/imsi_switch",
    "/nv/item_files/modem/nas/mav_lte_band_regulation_eu",
    "/nv/item_files/modem/nas/mav_lte_band_regulation_na",
    "/nv/item_files/modem/nas/mav_lte_band_regulation_asia",
    "/nv/item_files/modem/nas/mav_lte_band_regulation_ocean",
    "/nv/item_files/modem/nas/mav_lte_band_regulation_africa",
    "/nv/item_files/modem/nas/mav_lte_band_regulation_la",
    "/nv/item_files/modem/nas/mav_gw_band_regulation_eu",
    "/nv/item_files/modem/nas/mav_gw_band_regulation_na",
    "/nv/item_files/modem/nas/mav_gw_band_regulation_asia",
    "/nv/item_files/modem/nas/mav_gw_band_regulation_ocean",
    "/nv/item_files/modem/nas/mav_gw_band_regulation_africa",
    "/nv/item_files/modem/nas/mav_gw_band_regulation_la",
    "/nv/item_files/modem/nas/mav_lte_band_per_plmn",
    "/nv/item_files/modem/nas/mav_gw_band_per_plmn",
    "/nv/item_files/modem/nas/lte_spc_rv_plmn_list",
    "/nv/item_files/modem/lte/common/ca_allowed_plmn",
    "/nv/item_files/modem/nas/lte_nas_temp_fplmn_backoff_time",
    "/nv/item_files/ims/IMS_enable",
    "/nv/item_files/modem/lte/rrc/csp/lte_redir_test",
    "/nv/item_files/modem/data/3gpp/lteps/attach_profile",
    "/nv/item_files/modem/mmode/ue_usage_setting",
    "/nv/item_files/cdma/1xcp/1xadvanced_capability",
    "/nv/item_files/cdma/1xcp/so73_cop0_supported",
    "/nv/item_files/modem/nas/isr",
    "/nv/item_files/modem/mmode/voice_domain_pref",
    "/nv/item_files/modem/mmode/lte_disable_duration",
    "/nv/item_files/modem/hdr/cp/ovhd/d2lresel",
    "/nv/item_files/ims/qipcall_dan_enable",
    "/nv/item_files/ims/qipcall_dan_needed",
    "/nv/item_files/ims/qipcall_dan_hysterisis_timer_duration",
    "/nv/item_files/ims/qipcall_1xsmsandvoice",
    "/nv/item_files/data/3gpp2/ehrpd_partial_context",
    "/nv/item_files/modem/lte/rrc/cap/fgi",
    "/nv/item_files/modem/lte/rrc/cap/lte_rx_config_1xrtt",
    "/nv/item_files/modem/nas/max_validate_sim_counter",
    "/nv/item_files/modem/nas/forced_irat",
    "/nv/item_files/modem/nas/irat_search_timer",
    "/nv/item_files/modem/lte/lte_3gpp_release_ver",
    "/nv/item_files/ims/mav_lqefa_audio_client_enabled",
    "/nv/item_files/modem/tdd_test_mode",
    "/nv/item_files/modem/mmode/sms_domain_pref_list",
    "/nv/item_files/modem/mmode/qmi/mav_pri_allow_auto_answer",
    "/nv/item_files/modem/nas/csg_wcdma_search_band_pref",
    "/nv/item_files/modem/nas/mav_t3417_ext_value",
    "/ds/atcop/atcop_cops_auto_mode.txt",
    "/nv/item_files/modem/uim/mmgsdi/features_status_list",
    "/nv/item_files/modem/uim/mmgsdi/refresh_retry",
    "/SUPL/cert0",
    "/nv/item_files/modem/nas/mav_managed_roaming_retry_lu_manual",
    "/nv/item_files/modem/nas/cc15_special_handling",
    "/nv/item_files/modem/nas/nas_srvcc_support",
    "/nv/item_files/modem/tdscdma/rrc/special_test_setting_enabled",
    "/nv/item_files/modem/data/3gpp/lteps/mav_roaming_profile_id",
    "/nv/item_files/data/3gpp2/tethered_nai_prefix",
    "/nv/item_files/data/dsd/ds_apn_switching",
    "/nv/item_files/modem/sms/pri_disable_cb_dup_detection",
    "/nv/item_files/modem/lte/rrc/csp/lte_mode_priority",
    "/nv/item_files/modem/hdr/cp/ovhd/mccnops",
    "/nv/item_files/modem/lte/rrc/lte_rrc_1xcsfb_enabled",
    "/nv/item_files/modem/lte/ML1/cdrx_opt_info",
    "/mmode/cmph/sglte_device",
    "/mmode/cmph/gsm_srlte_test_mode",
    "/mmode/cmph/sglte_plmn_list",
    "/nv/item_files/modem/nas/ignore_uplmn",
    "/nv/item_files/ims/mav_iaj_protocol_client_enabled",
    "/nv/item_files/ims/mav_iaj_protocol_client_ho_lifetime",
    "/nv/item_files/ims/mav_iaj_protocol_client_ho_dj_delay",
    "/nv/item_files/modem/lte/rrc/rohc_supported",
    "/nv/item_files/wcdma/rrc/wcdma_rrc_csfb_skip_sib11_opt",
    "/nv/item_files/modem/nas/mav_enable_zuc",
    "/nv/item_files/modem/lte/rrc/cap/fgi_r10",
    "/nv/item_files/modem/lte/rrc/cap/fgi_tdd",
    "/nv/item_files/modem/lte/rrc/cap/fgi_tdd_rel9",
    "/nv/item_files/modem/lte/rrc/cap/fgi_tdd_rel10",
    "/nv/item_files/modem/lte_connection_control",
    "/nv/item_files/modem/lte/rrc/cap/ca_bc_config.txt",
    "/nv/item_files/modem/lte/rrc/cep/conn_control_barring_optmz_enable",
    "/nv/item_files/modem/data/3gpp/call_orig_allowed_before_ps_attach",
    "/nv/item_files/wcdma/rrc/wcdma_rrc_wtol_tdd_ps_ho_support",
    "/nv/item_files/modem/nas/mav_srlte_plmn",
    "/nv/item_files/modem/data/3gpp/umts_nw_initiated_qos_support",
    "/nv/item_files/modem/sms/mmgsdi_refresh_vote_ok",
    "/nv/item_files/modem/nas/iplmn_preferred",
    "/nv/item_files/modem/nas/enable_international_cdma_roaming",
    "/nv/item_files/modem/mmode/mav_volte_barring_config",
    "/nv/item_files/modem/data/epc/qmi_qos",
    "/nv/item_files/wcdma/rrc/wcdma_rrc_fast_return_to_lte_after_csfb",
    "/nv/item_files/modem/data/3gpp/lteps/auto_connect_def_pdn",
    "/nv/item_files/modem/mmode/lte_bandpref",
    "/nv/item_files/modem/lte/common/ca_disable",
    "/nv/item_files/modem/lte/common/lte_category",
    "/nv/item_files/modem/nas/csg_support_configuration",
    "/nv/item_files/modem/nas/lte_nas_lsti_config",
    "/nv/item_files/modem/nas/iPLMN",
    "/nv/item_files/modem/lte/ML1/csg_neighbor_opt",
    "/nv/item_files/modem/nas/mav_tdl_allowed_plmn",
    "/nv/item_files/wcdma/rrc/wcdma_rrc_wtol_ps_ho_support",
    "/nv/item_files/modem/data/3gpp/ps/allow_infinite_throt",
    "/nv/item_files/modem/nas/cm_efs_mav_health_monitor_control_pri",
    "/nv/item_files/ims/qp_ims_dpl_config",
    "/nv/item_files/ims/qp_ims_reg_config",
    "/nv/item_files/ims/qp_ims_sms_config",
    "/nv/item_files/ims/qp_ims_sip_extended_0_config",
    "/nv/item_files/ims/ims_operation_mode",
    "/nv/item_files/ims/qipcall_confrd_uri",
    "/nv/item_files/modem/mmode/sms_domain_pref",
    "/nv/item_files/modem/lte/rrc/sec/eia0_allowed",
    "/nv/item_files/modem/geran/grr/g2l_blind_redir_after_csfb_control",
    "/nv/item_files/modem/tdscdma/data/ft_status",
    "/nv/item_files/modem/nas/tdscdma_op_plmn_list",
    "/nv/item_files/modem/nas/aggression_management",
    "/nv/item_files/modem/nas/mm_efs_cancel_frlte_diff_lac",
    "/nv/item_files/modem/data/3gpp/ps/3gpp_rel_version",
    "/nv/item_files/modem/data/3gpp/ps/ser_req_throttle_behavior",
    "/nv/item_files/modem/nas/hplmn_rat_order",
    "/nv/item_files/modem/mmode/sms_only",
    "/nv/item_files/modem/nas/srlte_roaming",
    "/nv/item_files/modem/lte/L2/mac/lte_mac_disable_dormancy",
    "/nv/item_files/modem/mmode/sms_mandatory",
    "/nv/item_files/data/3gpp2/ehrpd_to_hrpd_fallback",
    "/nv/item_files/data/3gpp2/epc_data_context_duration",
    "/nv/item_files/modem/lte/ML1/adaptive_neighbor_meas",
    "/nv/item_files/modem/tdscdma/data/tcp_ack_discard",
    "/nv/item_files/data/3gpp/ds_umts_bcm_support",
    "/nv/item_files/modem/geran/grr/g2l_blind_redir_control",
    "/nv/item_files/modem/nas/nas_lai_change_force_lau_for_emergency",
    "/nv/item_files/modem/lte/rrc/cap/fgi_rel9",
    "/nv/item_files/wcdma/rrc/wcdma_ppac_support",
    "/nv/item_files/wcdma/rrc/wcdma_rrc_feature",
    "/nv/item_files/data/3gpp2/mpit_enable",
    "/nv/item_files/data/3gpp2/max_fb_pdn_failure_count",
    "/nv/item_files/modem/lte/rrc/mav_prox_bar_timer",
    "/nv/item_files/modem/mmode/tds_bandpref",
    "/nv/item_files/modem/nas/imsi_switch"
    );
    
my @gNVIgnoreList = (
    #Not affect user behavior
    50005,                             #NV_MAV_COMM_AP_COREDUMP_MODE_NV_REV_I
    375,                               #RFNV_SMS_BC_USER_PREF_I
    #Configured via QMI dynamically
    830,62022,
    
    # Vary according to roaming status or SIM info
    32, 33,                             #RFNV_MIN
    37,                                 #RFNV_ACCOLC_I
    259,                                #RFNV_HOME_SID_NID_I
    260,                                #NV_OTAPA_ENABLED_I
    579,                                #NV_HDR_AN_AUTH_NAI_I
    475,                                #NV_HDRSCP_SESSION_STATUS_I
    906,                                #NV_PPP_PASSWORD_I
    62002,                              #NV_MAV_CDMA_OTASP_SS_CODES_I
    
    #From plistparser.c
    178,259,255,32,33,176,262,263,177,20,21,
    5,179,285,34,35,36,10,296,304,261,260,258,
    4366,3533,5773,240,297,459,460,461,462,463,546,495,854,465,2825,889,910,906,
    579,1194,1192,298,429,450,300,405,241,562,401,426,423,424,714, 4101,
    4960,4959,3635,62001,62002,37,2953,466,4102,3446,4396,553,4432,4118,4210,62009,62010,
    62011,62012,62013,62014,62015,62018,62003,442,62019,896,
    855,62016,62017,58021,1920,3649,707,
    947,4265,4229,6248,4528,6862,1896,4964,475,7166,6,50023,6850,1907,62024,50025,62026,5895,6247,852,5280,
    441,946,2954,62029,62030,62028,6832,3461,62025,62031,62023,4703,6792,3758,909,58006,6264,62005,62033,
    
    18, 209, 264, 265, 266, 848, 1015, 1017,
    
    # Below three NV are dynamic configured in function : mav_rf_hw_vendor_init_static
    # Function will check RFFE HB asm state, if it is invalid, then configure below 3 NV items
    6828, 22605, 24203
    );

#########################################################################################
# Func:
#    LogPrint
# Description:
#    Save msg to log file and to STDOUT if last parameter is 1
#########################################################################################
sub LogPrint
{
  my ($stuff_to_print, $ShowOut) = @_;
  my @FILEHANDLES = ($gLogHandler);

  my $var = substr($stuff_to_print,length($stuff_to_print)-1,1);
  if( $var ne "\n")
  {
    $stuff_to_print .= "\n";
  }

  #print "stuff_to_print: ".$stuff_to_print."\n";
  #print "ShowOut: ".$ShowOut."\n";
  if(($ShowOut != 0) && ($ShowOut != 1))
  {
    exit(0);
  }

  if($ShowOut == 1)
  {
    push @FILEHANDLES, $gOutHandler;
    print $stuff_to_print;
  }
  foreach my $filehandle (@FILEHANDLES)
  {
    print $filehandle $stuff_to_print;
  }
}

#########################################################################################
# Func:
#    WriteToReport
# Description:
#    Write result to report file
#########################################################################################
sub WriteToReport
{
  my ($stuff_to_print, $ShowOut) = @_;
  my @FILEHANDLES = ($gTxtReportHandler, $gLogHandler);

  my $var = substr($stuff_to_print,length($stuff_to_print)-1,1);
  if( $var ne "\n")
  {
    $stuff_to_print .= "\n";
  }

  if($ShowOut == 1)
  {
    push @FILEHANDLES, $gOutHandler;
    print $stuff_to_print;
  }
  foreach my $filehandle (@FILEHANDLES)
  {
    print $filehandle $stuff_to_print;
  }
}

#########################################################################################
# Func:
#    trim
# Description:
#    Trim space of string
#########################################################################################
sub trim
{
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}

#########################################################################################
# Func:
#    AsciiToHex
# Description:
#    Convert ascii code to hex value
#########################################################################################
sub AsciiToHex
{
  my ($asciiStr) = @_;
  my @hexDatas = unpack ("(H2 )*", $asciiStr);
  my $hexStr = '';
  LogPrint("AsciiToHex", 0);
  LogPrint("\t  Ascii: ".$asciiStr, 0);

  foreach my $hexData (@hexDatas)
  {
    $hexStr .= $hexData.' ';
  }
  LogPrint("\tHexData: ".$hexStr, 0);
  return trim($hexStr);
}

#########################################################################################
# Func:
#    UBYTE
# Description:
#    Extrace 1 byte from array and convert to unsigned byte formate
#########################################################################################
sub UBYTE
{
  my ($pkt) = @_;
  if(@$pkt >= 1)
  {
    my $result = hex(@$pkt[0]);
    shift(@$pkt);
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    BYTE
# Description:
#    Extrace 1 byte from array and convert to byte formate
#########################################################################################
sub BYTE
{
  my ($pkt) = (@_);
  if(@$pkt >= 1)
  {
    my $result = hex(@$pkt[0]);
    my $sign = $result >> 7;
    my $val = $result & 0x7F;
    if($sign)
    {
      $result = -0x80 + $val;
    }
    else
    {
      $result = $val;
    }
    shift(@$pkt);
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    USHORT
# Description:
#    Extrace 2 byte from array and convert to unsigned short formate
#########################################################################################
sub USHORT
{
  my ($pkt) = @_;
  if(@$pkt >= 2)
  {
    my $result = hex(@$pkt[1]) << 8 | hex(@$pkt[0]);
    shift(@$pkt);
    shift(@$pkt);
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    SHORT
# Description:
#    Extrace 2 byte from array and convert to short formate
#########################################################################################
sub SHORT
{
  my ($pkt) = (@_);
  if(@$pkt >= 2)
  {
    my $result = hex(@$pkt[1]) << 8 | hex(@$pkt[0]);
    my $sign = $result >> 15;
    my $val = $result & 0x7FFF;
    if($sign)
    {
      $result = -0x8000 + $val;
    }
    else
    {
      $result = $val;
    }
    shift(@$pkt);
    shift(@$pkt);
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    UINT
# Description:
#    Extrace 4 byte from array and convert to unsigned int formate
#########################################################################################
sub UINT
{
  my ($pkt) = @_;
  if(@$pkt >= 4)
  {
    my $result = hex(@$pkt[3]) << 24 | hex(@$pkt[2]) << 16 | hex(@$pkt[1]) << 8 | hex(@$pkt[0]);
    shift(@$pkt);
    shift(@$pkt);
    shift(@$pkt);
    shift(@$pkt);
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    INT
# Description:
#    Extrace 4 byte from array and convert to int formate
#########################################################################################
sub INT
{
  my ($pkt) = (@_);
  if(@$pkt >= 4)
  {
    my $result = hex(@$pkt[3]) << 24 | hex(@$pkt[2]) << 16 | hex(@$pkt[1]) << 8 | hex(@$pkt[0]);
    my $sign = $result >> 31;
    my $val = $result & 0x7FFFFFFF;
    if($sign)
    {
      $result = -0x80000000 + $val;
    }
    else
    {
      $result = $val;
    }
    shift(@$pkt);
    shift(@$pkt);
    shift(@$pkt);
    shift(@$pkt);
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    ULONG
# Description:
#    Extrace 8 byte from array and convert to unsigned long formate
#########################################################################################
sub ULONG
{
  my ($pkt) = (@_);
  if(@$pkt >= 8)
  {
    my $low_32 = UINT($pkt);
    my $high_32 = UINT($pkt);
    my $result = $high_32 << 32 | $low_32;
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    LONG
# Description:
#    Extrace 8 byte from array and convert to long formate
#########################################################################################
sub LONG
{
  my ($pkt) = (@_);
  if(@$pkt >= 8)
  {
    my $low_32 = INT($pkt);
    my $high_32 = INT($pkt);
    my $result = $high_32 << 32 | $low_32;
    return $result;
  }
  else
  {
    return $TOO_SHORT;
  }
}

#########################################################################################
# Func:
#    STR
# Description:
#    Extrace string from array
#########################################################################################
sub STR
{
  my ($pkt) = (@_);
  my $i = @$pkt - 1;
  while($i>=0)
  {
    if(@$pkt[$i] eq '00')
    {
      last;
    }
    $i = $i - 1;
  }
  if($i < 0)
  {
    return "TOO_SHORT";
  }

  my $result = '';
  while(@$pkt > 0)
  {
    my $char = @$pkt[0];
    shift(@$pkt);
    if($char eq '00')
    {
      last;
    }
    else
    {
      $char = hex($char);
      $result = $result.chr($char);
    }
  }
  return $result;
}

#########################################################################################
# Func:
#    RAW
# Description:
#    Extrace specified byte from array and convert to string
#########################################################################################
sub RAW
{
    my ($size, $pkt) = (@_);
    my $result = "";
    if(@$pkt >= $size)
    {
        while($size > 0)
        {
            $result .= @$pkt[0]." ";
            shift(@$pkt);
            $size = $size - 1;
        }
        return trim($result);
    }
    else
    {
        return "TOO_SHORT";
    }
}

#########################################################################################
# Func:
#    ETLRawCmd
# Description:
#    Execute ETLTool raw command
#########################################################################################
sub ETLRawCmd
{
  LogPrint("\tETLRawCmd", 0);
  my ($cmd, $delay) = (@_);
  my $out = qx($cmd);
  my @out = split('\n', $out);
  my $findResPacket = 0;
  my $payload = "";
  my $line;

  LogPrint("\t  CMD: ".$cmd, 0);
  foreach $line (@out)
  {
    LogPrint("\t  OUT: ".$line, 0);
    if($line =~ m/Received Response/s)
    {
      $findResPacket = 1;
      next;
    }
    if(($line =~ m/root#/s) && ($findResPacket == 1))
    {
      last;
    }
    if($findResPacket == 1)
    {
      my @tmp = $line =~ /([0-9a-fA-f]{4})(.*)    (.*)/;
      if(@tmp > 0)
      {
        $payload .= trim($tmp[1]).' ';
      }
    }
  }
  LogPrint("\t  PAYLOAD: ".$payload, 0);
  return trim($payload);
}

#########################################################################################
# Func:
#    ETLEfsMkDir
# Description:
#    Make directory in baseband EFS
#########################################################################################
sub ETLEfsMkDir
{
  LogPrint("ETLEfsMkDir:", 0);
  my ($dirName) = @_;
  LogPrint("\tDirName:".$dirName, 0);
  my $dirNameSize = length($dirName);
  my $firstReq = sprintf '59 00 %02x ', $dirNameSize+1;
  $firstReq .= AsciiToHex($dirName).' 00';

  my $out = ETLRawCmd('/usr/local/bin/ETLTool raw '.trim($firstReq));
  if((trim(substr($out,0,8)) eq '59 00 00') || (trim(substr($out,0,8)) eq '59 00 07'))
  {
    LogPrint("ETLEfsMkDir - SUCCESS", 0);
    return 1;
  }
  else
  {
    LogPrint("ETLEfsMkDir - FAIL", 0);
    return 0;
  }
}

#########################################################################################
# Func:
#    ETLEfsRemoveFile
# Description:
#    Delete baseband file from EFS
#########################################################################################
sub ETLEfsRemoveFile
{
  LogPrint("ETLEfsRemoveFile:", 0);
  my ($fileName) = @_;
  my $fileNameSize = length($fileName);
  my $firstReq = sprintf '59 06 %02x ', $fileNameSize+1;
  $firstReq .= AsciiToHex($fileName).' 00';

  my $out = ETLRawCmd('/usr/local/bin/ETLTool raw '.trim($firstReq));
  if((trim(substr($out,0,8)) eq '59 06 00') || (trim(substr($out,0,8)) eq '59 06 06'))
  {
    LogPrint("ETLEfsRemoveFile - SUCCESS", 0);
    return 1;
  }
  else
  {
    LogPrint("ETLEfsRemoveFile - FAIL", 0);
    return 0;
  }
}

#########################################################################################
# Func:
#    ETLEfsWriteFile
# Description:
#    Write file to baseband EFS
#########################################################################################
sub ETLEfsWriteFile
{
  my ($localFile, $remoteFile) = @_;
  my $cmd;
  my $out;
  my $hexData;
  my $lines;
  my $header;
  my $pktDataLen = 240;
  my $seqNum = 0;
  my $fileSize;
  my $fileNameSize;
  my $firstReqHeader;
  my $firstReqBody;
  my $firstReq;
  my $nextReqHeader;
  my $nextReqBody;
  my $nextReq;
  my $lastReqHeader;
  my $lastReqBody;
  my $lastReq;

  if(ETLEfsMkDir(dirname($remoteFile)) == 0)
  {
    return 0;
  }

  LogPrint("ETLEfsWriteFile", 0);

  open(my $FILEHANDLER, "<$localFile") || die "Cannot open $localFile!";
  local $/ = undef;
  $lines = <$FILEHANDLER>;

  LogPrint("LocalFile:".$localFile, 0);
  LogPrint("RemoteFile:".$remoteFile, 0);
  LogPrint("LocalFile Data:".$lines, 0);

  #First Req package
  $fileSize = length($lines);
  $fileNameSize = length($remoteFile);
  $firstReqHeader = sprintf '59 05 %02x 01 00 %02x %02x %02x %02x 00 00 00 00 %02x ', $seqNum, ($fileSize & 0xFF), ($fileSize>>8 & 0xFF), ($fileSize>>16 & 0xFF), ($fileSize>>24 & 0xFF), $fileNameSize+1;
  $firstReqHeader .= AsciiToHex($remoteFile).' 00';
  $firstReqBody = ' ';
  if($fileSize > $pktDataLen)
  {
    $firstReqBody .= sprintf '%02x 00 ', $pktDataLen;
    $hexData = AsciiToHex(substr($lines,0, $pktDataLen));
    $fileSize -= $pktDataLen;
    $lines = substr($lines,$pktDataLen,length($lines)-$pktDataLen);
  }
  else
  {
    $firstReqBody .= sprintf '%02x 00 ', $fileSize;
    $hexData = AsciiToHex(substr($lines,0, length($lines)));
    $lines = '';
  }
  $firstReqBody .= $hexData;
  $firstReq = $firstReqHeader.$firstReqBody;
  $out = ETLRawCmd('/usr/local/bin/ETLTool raw '.trim($firstReq));
  if(trim(substr($out,0,8)) ne '59 05 00')
  {
    LogPrint("ETLEfsWriteFile - FAIL (1st REQ)", 0);
    return 0;
  }
  $seqNum += 1;

  #Next Req package
  while(length($lines) > $pktDataLen)
  {
    $nextReqHeader = sprintf '59 05 %02x 01 %02x 00', $seqNum, $pktDataLen;
    $nextReqBody = ' ';
    $nextReqBody .= AsciiToHex(substr($lines,0, $pktDataLen));
    $fileSize -= $pktDataLen;
    $lines = substr($lines,$pktDataLen,length($lines)-$pktDataLen);
    $nextReq = $nextReqHeader.$nextReqBody;
    $out = ETLRawCmd('/usr/local/bin/ETLTool raw '.trim($nextReq));
    if(trim(substr($out,0,8)) ne '59 05 00')
    {
      LogPrint("ETLEfsWriteFile - FAIL (Next REQ)", 0);
      LogPrint($out, 0);
      return 0;
    }
    $seqNum += 1;
  }

  #last Req package
  $lastReqHeader = sprintf '59 05 %02x 00 %02x 00', $seqNum, length($lines);
  $lastReqBody = ' ';
  $lastReqBody .= AsciiToHex(substr($lines,0, length($lines)));
  $lastReq = $lastReqHeader.$lastReqBody;
  $out = ETLRawCmd('/usr/local/bin/ETLTool raw '.trim($lastReq));
  if(trim(substr($out,0,8)) ne '59 05 00')
  {
    LogPrint("ETLEfsWriteFile - FAIL (Last REQ)", 0);
    LogPrint($out, 0);
    return 0;
  }
  LogPrint("ETLEfsWriteFile - SUCCESS", 0);
  return 1;
}

#########################################################################################
# Func:
#    RawCmd
# Description:
#    Execute command
#########################################################################################
sub RawCmd
{
  my ($cmd) = (@_);
  my @out;
  my $payload = "";
  my $line;

  LogPrint("\tRawCmd: ", 0);
  LogPrint("\t  CMD: ".$cmd, 0);
  @out = qx($cmd);

  foreach $line (@out)
  {
    $payload .= $line.' ';
  }
  LogPrint("\t  Payload: ".trim($payload), 0);
  return trim($payload);
}

#########################################################################################
# Func:
#    HasBB
# Description:
#    Determine whether or not baseband existed
#########################################################################################
sub HasBB
{
  my $cmd = '/usr/local/bin/gestalt_query HasBaseband';
  my $out = RawCmd($cmd);
  my @tmp = $out =~ /HasBaseband:(.*)/;
  my $hasBB = "NA";
  if(@tmp > 0)
  {
    $hasBB = uc(trim($tmp[0]));
  }
  LogPrint((sprintf $OutFormat, 'Has BB', $hasBB), 0);
  if($hasBB eq "TRUE")
  {
    return 1;
  }
  else
  {
    LogPrint("Baseband is not existed in this device", 1);
    return 0;
  }
  return;
}

#########################################################################################
# Func:
#    CheckFactoryDebugOption
# Description:
#    Check whether or not FactoryDebug are enabled or not
#########################################################################################
sub CheckFactoryDebugOption
{
  my $out = qx(/usr/local/bin/ETLTool raw 4b fe 00 00);
  if(index($out, '13 4B FE 00 00') != -1)
  {
    print "More baseband information is available by choosing 'Enable Factory Debug' in PR\n\n";
  }
}

#########################################################################################
# Func:
#    GetProdName
# Description:
#    Get product name
#########################################################################################
sub GetProdName
{
  my $cmd = '/usr/sbin/sysctl -a hw.model';
  my $out = RawCmd($cmd);
  my @tmp = $out =~ /hw.model:(.*)/;
  if(@tmp > 0)
  {
    $gProdName = trim($tmp[0]);
    $gProdName =~ s/AP//g;
  }
  LogPrint((sprintf $OutFormat, 'Prod', $gProdName), 0);
  return;
}

#########################################################################################
# Func:
#    BBGetFWVersion
# Description:
#    Get baseband FW version
#########################################################################################
sub BBGetFWVersion
{
  my $cmd = '/usr/local/bin/gestalt_query BasebandFirmwareVersion';
  my $out = RawCmd($cmd);
  my @tmp = $out =~ /BasebandFirmwareVersion:(.*)/;
  my $bbFWVer = "NA";
  if(@tmp > 0)
  {
    $bbFWVer = trim($tmp[0]);
  }
  LogPrint((sprintf $OutFormat, 'Verion', $bbFWVer), 1);
  return;
}

#########################################################################################
# Func:
#    BBGetSN
# Description:
#    Get baseband serial number
#########################################################################################
sub BBGetSN
{
  my $cmd = '/usr/local/bin/gestalt_query BasebandSerialNumber';
  my $out = RawCmd($cmd);
  my @tmp = $out =~ /BasebandSerialNumber: Data\[4\] \((.*)\)/;
  my $bbSN = "NA";

  if(@tmp > 0)
  {
    $bbSN = trim($tmp[0]);
  }
  LogPrint((sprintf $OutFormat, 'BBSN', $bbSN), 1);
  return;
}

#########################################################################################
# Func:
#    BBGetCalType
# Description:
#    Get calibration type
#########################################################################################
sub BBGetCalType
{
  my $cmd = '/usr/local/bin/ETLTool raw 0x4B 0xFB 0x38 0x00';
  my $out = ETLRawCmd($cmd);
  my $BBCalType;

  LogPrint(" ", 1);

  if(length($out) < 12)
  {
    LogPrint("ERR: Rsppkt length is too short", 0);
  }
  else
  {
    my $header = trim(substr($out,0,11));
    my $body = trim(substr($out,length($header),length($out)-length($header)));
    LogPrint("Header: ".$header, 0);
    LogPrint("Body: ".$body, 0);
    if($header ne "4B FB 38 00")
    {
      LogPrint("ERR: Rsppkt header is not 4B FB 38 00", 0);
    }
    else
    {
      my @rsp = split(' ', $body);
      my $status = USHORT(\@rsp);
      my $rcWord = USHORT(\@rsp);
      LogPrint("Status: ".$status, 0);
      LogPrint("RcWord: ".$rcWord, 0);
      if($status == 1)
      {
        if($rcWord == 1)
        {
          $BBCalType = "Factory Cal";
        }
        elsif($rcWord == 0)
        {
          $BBCalType = "Default Cal";
        }
        else
        {
           $BBCalType = "NA";
        }
      }
      LogPrint((sprintf $OutFormat, 'CalType', $BBCalType), 1);
    }
  }
  return;
}

#########################################################################################
# Func:
#    BBGetBandAndCalStatus
# Description:
#    Get baseband supported band and calibration status
#########################################################################################
sub BBGetBandAndCalStatus
{
  my ($silent) = @_;
  my $cmd = '/usr/local/bin/ETLTool raw 0x4B 0xFB 0x30 0x00';
  my $out = ETLRawCmd($cmd);
  my $BBCalType = "NA";
  my $BandDictRef;
  my %BandDict;
  my $BandStatus;
  my $BandCalStatus;
  my $RangeRef;
  my @Range;
  my $idx;
  my $SupportedBand;
  my $RAT;
  my $ii;
  my @caledBand = '';

  if(!$silent)
  {
    LogPrint(" ", 1);
  }

  if(length($out) < 12)
  {
    LogPrint("ERR: Rsppkt length is too short", 0);
  }
  else
  {
    my $header = trim(substr($out,0,11));
    my $body = trim(substr($out,length($header),length($out)-length($header)));
    LogPrint("Header: ".$header, 0);
    LogPrint("Body: ".$body, 0);
    if($header ne "4B FB 30 00")
    {
      LogPrint("ERR: Rsppkt header is not 4B FB 38 00", 0);
    }
    else
    {
      my @rsp = split(' ', $body);
      my $BBCalStatus = USHORT(\@rsp);
      my $GSMCalStatus = USHORT(\@rsp);
      my $CDMACalStatus = UINT(\@rsp);
      my $WCDMACalStatus = UINT(\@rsp);
      my $TDSCalStatus = UINT(\@rsp);
      my $LTECalStatus = ULONG(\@rsp);
      my $GSMBandStatus = USHORT(\@rsp);
      my $CDMABandStatus = UINT(\@rsp);
      my $WCDMABandStatus = UINT(\@rsp);
      my $TDSBandStatus = UINT(\@rsp);
      my $LTEBandStatus = ULONG(\@rsp);

      LogPrint("BBCalStatus: ".sprintf("0x%X", $BBCalStatus), 0);
      LogPrint("GSMCalStatus: ".sprintf("0x%X", $GSMCalStatus), 0);
      LogPrint("CDMACalStatus: ".sprintf("0x%X", $CDMACalStatus), 0);
      LogPrint("WCDMACalStatus: ".sprintf("0x%X", $WCDMACalStatus), 0);
      LogPrint("TDSCalStatus: ".sprintf("0x%X", $TDSCalStatus), 0);
      LogPrint("LTECalStatus: ".sprintf("0x%X", $LTECalStatus), 0);
      LogPrint("GSMBand: ".sprintf("0x%X", $GSMBandStatus), 0);
      LogPrint("CDMABand: ".sprintf("0x%X", $CDMABandStatus), 0);
      LogPrint("WCDMABand: ".sprintf("0x%X", $WCDMABandStatus), 0);
      LogPrint("TDSBand: ".sprintf("0x%X", $TDSBandStatus), 0);
      LogPrint("LTEBand: ".sprintf("0x%X", $LTEBandStatus), 0);

      my %gsmBands = (
                0=>'G_850   ',
                1=>'G_900   ',
                2=>'G_1800 ',
                3=>'G_1900 ',
      );

      my %wcdmaBands = (
                0=>'W_B1    ',
                1=>'W_B2    ',
                2=>'W_B3    ',
                3=>'W_B4    ',
                4=>'W_B5    ',
                5=>'W_B8    ',
                6=>'W_B9    ',
                7=>'W_B11   ',
                8=>'W_B19   ',
      );

      my %cdmaBands = (
                0=>'C_BC0  ',  #0x1
                1=>'C_BC1  ',  #0x2
                2=>'C_BC2  ',  #0x4
                3=>'C_BC3  ',  #0x8
                4=>'C_BC4  ',  #0x10
                5=>'C_BC5  ',  #0x20
                6=>'C_BC6  ',  #0x40
                7=>'C_BC7  ',  #0x80
                8=>'C_BC8  ',  #0x100
                9=>'C_BC9  ',  #0x200
                10=>'C_BC10',  #0x400
                11=>'C_BC11',  #0x800
                12=>'C_BC12',  #0x1000
                13=>'C_BC13',  #0x2000
                14=>'C_BC14',  #0x4000
                15=>'C_BC15',  #0x8000
                16=>'C_BC16',  #0x10000
                17=>'C_BC17',  #0x20000
                18=>'C_BC18',  #0x40000
                19=>'C_BC19',  #0x80000
                20=>'C_BC20',  #0x100000
      );

      my %lteFDDBands = (
                0=>'L_B1     ',  #0x1
                1=>'L_B2     ',  #0x2
                2=>'L_B3     ',  #0x4
                3=>'L_B4     ',  #0x8
                4=>'L_B5     ',  #0x10
                5=>'L_B6     ',  #0x20
                6=>'L_B7     ',  #0x40
                7=>'L_B8     ',  #0x80
                8=>'L_B9     ',  #0x100
                9=>'L_B10    ', #0x200
                10=>'L_B11   ',  #0x400
                11=>'L_B12   ',  #0x800
                12=>'L_B13   ',  #0x1000
                13=>'L_B14   ',  #0x2000
                14=>'L_B15   ',  #0x4000
                15=>'L_B16   ',  #0x8000
                16=>'L_B17   ',  #0x10000
                17=>'L_B18   ',  #0x20000
                18=>'L_B19   ',  #0x40000
                19=>'L_B20   ',  #0x80000
                20=>'L_B21   ',  #0x100000
                21=>'L_B22   ',  #0x200000
                22=>'L_B23   ',  #0x400000
                23=>'L_B24   ',  #0x800000
                24=>'L_B25   ',  #0x1000000
                25=>'L_B26   ',  #0x2000000
                26=>'L_B27   ',  #0x4000000
                27=>'L_B28   ',  #0x8000000
                28=>'L_B29   ',  #0x10000000
                29=>'L_B30   ',  #0x20000000
                30=>'L_B31   ',  #0x40000000
                31=>'L_B32   ',  #0x80000000
                44=>'L_B28_B', #0x100000000000
      );

      my %lteTDDBands = (
                32=>'L_B33   ',  #0x100000000
                33=>'L_B34   ',  #0x200000000
                34=>'L_B35   ',  #0x400000000
                35=>'L_B36   ',  #0x800000000
                36=>'L_B37   ',  #0x1000000000
                37=>'L_B38   ',  #0x2000000000
                38=>'L_B39   ',  #0x4000000000
                39=>'L_B40   ',  #0x8000000000
                40=>'L_B41   ',  #0x10000000000
                41=>'L_B42   ',  #0x20000000000
                42=>'L_B43   ',  #0x40000000000
                43=>'L_B44   ',  #0x80000000000
                45=>'L_B40_B',  #0x200000000000
                46=>'L_B41_B',  #0x400000000000
                47=>'L_B41_C',  #0x800000000000
                48=>'L_B40_NF',#0x1000000000000
                49=>'L_B41_NF',#0x2000000000000
      );

      my %tdsBands = (
                0=>'T_B34   ',
                1=>'T_B36   ',
                2=>'T_B37   ',
                3=>'T_B38   ',
                4=>'T_B40   ',
                5=>'T_B39   ',
      );
      my @GSMRange = (0..15);
      my %GSMCalDict = (
                0=>"GSM",
                1=>\%gsmBands,
                2=>$GSMBandStatus,
                3=>$GSMCalStatus,
                4=>\@GSMRange,
      );

      my @CDMARange = (0..31);
      my %CDMACalDict = (
                0=>"CDMA",
                1=>\%cdmaBands,
                2=>$CDMABandStatus,
                3=>$CDMACalStatus,
                4=>\@CDMARange,
      );

      my @WCDMARange = (0..31);
      my %WCDMACalDict = (
                0=>"WCDMA",
                1=>\%wcdmaBands,
                2=>$WCDMABandStatus,
                3=>$WCDMACalStatus,
                4=>\@WCDMARange,
      );

      my @FDDLTERange = ((0..31), (44));
      my %FDDLTECalDict = (
                0=>"FDD-LTE",
                1=>\%lteFDDBands,
                2=>$LTEBandStatus,
                3=>$LTECalStatus,
                4=>\@FDDLTERange,
      );

      my @TDDLTERange = ((32..43), (45..63));
      my %TDDLTECalDict = (
                0=>"TDD-LTE",
                1=>\%lteTDDBands,
                2=>$LTEBandStatus,
                3=>$LTECalStatus,
                4=>\@TDDLTERange,
      );

      my @TDSRange = (0..31);
      my %TDSCalDict = (
                0=>"TDSCDMA",
                1=>\%tdsBands,
                2=>$TDSBandStatus,
                3=>$TDSCalStatus,
                4=>\@TDSRange,
      );

      my %BBCalDict = (
              0=>\%GSMCalDict,
              1=>\%CDMACalDict,
              2=>\%WCDMACalDict,
              3=>\%FDDLTECalDict,
              4=>\%TDDLTECalDict,
              5=>\%TDSCalDict,
      );

      foreach $ii (sort keys %BBCalDict)
      {
        $RAT = $BBCalDict{$ii}{0};
        $BandDictRef = $BBCalDict{$ii}{1};
        %BandDict = %$BandDictRef;
        $BandStatus = $BBCalDict{$ii}{2};
        $BandCalStatus = $BBCalDict{$ii}{3};
        $RangeRef = $BBCalDict{$ii}{4};
        @Range = @{$RangeRef};
        $SupportedBand = "";
        foreach $idx (@Range)
        {
          if($BandStatus & (1 << $idx))
          {
            if(exists $BandDict{$idx})
            {
              my $bandname = $BandDict{$idx};
              my $bandCalStatus = ($BandCalStatus & (1 << $idx)) >> $idx;
              if($bandCalStatus == 1)
              {
                $SupportedBand .= $bandname.", ";
                push (@caledBand, $bandname);
              }
              else
              {
                $SupportedBand .= $bandname."(NotCal), ";
              }
            }
            else
            {
              if(!$silent)
              {
                  LogPrint("Err: Find unsupported ".$RAT." band - ".$idx, 1);
                }
            }
          }
        }
        $SupportedBand = trim($SupportedBand);
        my $var = substr($SupportedBand,length($SupportedBand)-1,1);
        if( $var eq ",")
        {
          $SupportedBand = substr($SupportedBand, 0, length($SupportedBand)-1);
        }
        if(!$silent)
        {
          my @SupportedBand = split(',', $SupportedBand);
          my $MaxElementPerLine = 4;
          my $firstline = 1; 
          while(@SupportedBand > 0)
          {
            if($#SupportedBand > $MaxElementPerLine)
            {
              if($firstline == 1)
              {
                LogPrint((sprintf $OutFormat, $RAT, trim(join(', ', @SupportedBand[0..$MaxElementPerLine]))), 1);
                $firstline = 0;
              }
              else
              {
                LogPrint((sprintf $OutFormat, "\t", trim(join(', ', @SupportedBand[0..$MaxElementPerLine]))), 1);
              }
              @SupportedBand = @SupportedBand[$MaxElementPerLine+1..$#SupportedBand];
            }
            else
            {
              if($firstline == 1)
              {
                LogPrint((sprintf $OutFormat, $RAT, trim(join(', ', @SupportedBand))), 1);
              }
              else
              {
                LogPrint((sprintf $OutFormat, "\t", trim(join(', ', @SupportedBand))), 1);
              }
              @SupportedBand = ();
            }
          } 
        }
      }
    } #END OF $header ne "4B FB 30 00"
  } #END OF length($out) < 12
  return @caledBand;
}

#########################################################################################
# Func:
#    BBGetBandLockStatus
# Description:
#    Get baseband band lock status
#########################################################################################
sub BBGetBandLockStatus
{
  my $cmd = '/usr/local/bin/ETLTool raw 4B FD 44 00 0E';
  my $out = ETLRawCmd($cmd);
  my $bandLockStatus;
  my %bandLockDict = (
       0x00=>'G_850 ',
       0x01=>'G_900 ',
       0x02=>'G_1800',
       0x03=>'G_1900',

       #UMTS 2 Bytes
       0x10=>'W_BC1 ',
       0x11=>'W_BC2 ',
       0x12=>'W_BC3 ',
       0x13=>'W_BC4 ',
       0x14=>'W_BC5 ',
       0x15=>'W_BC6 ',
       0x16=>'W_BC7 ',
       0x17=>'W_BC8 ',
       0x18=>'W_BC9 ',
       0x19=>'W_BC11',
       0x1A=>'W_BC19',
  
       #C2K 3 Bytes
       0x20=>'C_BC0 ',
       0x21=>'C_BC1 ',
       0x22=>'C_BC2 ',
       0x23=>'C_BC3 ',
       0x24=>'C_BC4 ',
       0x25=>'C_BC5 ',
       0x26=>'C_BC6 ',
       0x27=>'C_BC7 ',
       0x28=>'C_BC8 ',
       0x29=>'C_BC9 ',
       0x2A=>'C_BC10',
       0x2B=>'C_BC11',
       0x2C=>'C_BC12',
       0x2D=>'C_BC13',
       0x2E=>'C_BC14',
       0x2F=>'C_BC15',
       0x30=>'C_BC16',
       0x31=>'C_BC17',
       0x32=>'C_BC18',
       0x33=>'C_BC19',
       0x34=>'C_BC20',
       
       #LTE 6 Bytes
       0x40=>'L_B1  ',
       0x41=>'L_B2  ',
       0x42=>'L_B3  ',
       0x43=>'L_B4  ',
       0x44=>'L_B5  ',
       0x45=>'L_B6  ',
       0x46=>'L_B7  ',
       0x47=>'L_B8  ',
       0x48=>'L_B9  ',
       0x49=>'L_B10 ',
       0x4A=>'L_B11 ',
       0x4B=>'L_B12 ',
       0x4C=>'L_B13 ',
       0x4D=>'L_B14 ',
       0x4E=>'L_B15 ',
       0x4F=>'L_B16 ',
       0x50=>'L_B17 ',
       0x51=>'L_B18 ',
       0x52=>'L_B19 ',
       0x53=>'L_B20 ',
       0x54=>'L_B21 ',
       0x55=>'L_B22 ',
       0x56=>'L_B23 ',
       0x57=>'L_B24 ',
       0x58=>'L_B25 ',
       0x59=>'L_B26 ',
       0x5A=>'L_B27 ',
       0x5B=>'L_B28 ',
       0x5C=>'L_B29 ',
       0x5D=>'L_B30 ',
       0x5E=>'L_B31 ',
       0x5F=>'L_B32 ',
       0x60=>'L_B33 ',
       0x61=>'L_B34 ',
       0x62=>'L_B35 ',
       0x63=>'L_B36 ',
       0x64=>'L_B37 ',
       0x65=>'L_B38 ',
       0x66=>'L_B39 ',
       0x67=>'L_B40 ',
       0x68=>'L_B41 ',
       0x69=>'L_B42 ',
       0x6A=>'L_B43 ',
       0x6B=>'L_B44 ',

       #TDS 1 Byte
       0x80=>'T_B34 ',
       0x81=>'T_B36 ',
       0x82=>'T_B37 ',
       0x83=>'T_B38 ',
       0x84=>'T_B39 ',
       0x85=>'T_B40 ',
  );
    
  LogPrint("BBGetBandLockStatus", 0);
  LogPrint(" ", 1);

  if(length($out) < 12)
  {
    LogPrint("ERR: Rsppkt length is too short", 0);
  }
  else
  {
    my $header = trim(substr($out,0,11));
    my $body = trim(substr($out,length($header),length($out)-length($header)));
    LogPrint("Header: ".$header, 0);
    LogPrint("Body: ".$body, 0);
    if($header ne "4B FD 44 00")
    {
      LogPrint("ERR: Rsppkt header is not 4B FB 44 00", 0);
    }
    else
    {
      my @rsp = split(' ', $body);
      my $status = USHORT(\@rsp);
      my $errCode = USHORT(\@rsp);
      my $bandGWC = ULONG(\@rsp);
      my $bandLTE = ULONG(\@rsp);
      my $bandTDS = ULONG(\@rsp);
      my $lockedBand = '';
      LogPrint("Status: ".$status, 0);
      LogPrint("errCode: ".$errCode, 0);
      LogPrint("bandGWC: ".$bandGWC, 0);
      LogPrint("bandLTE: ".$bandLTE, 0);
      LogPrint("bandTDS: ".$bandTDS, 0);
      if($status == 1)
      {
        if(($bandGWC == 0) && ($bandLTE == 0) && ($bandTDS == 0))
        {
          $lockedBand = 'Disabled';
        }
        else
        {
          my $ii;
          foreach $ii (sort {$a<=>$b} keys %bandLockDict)
          {
            if(($ii < 64) && (($bandGWC & (1 << $ii)) == (1 << $ii)))
            {
              $lockedBand .=  $bandLockDict{$ii}.", ";
            }
            elsif(($ii < 128) && (($bandLTE & (1 << ($ii-64))) == (1 << ($ii-64))))
            {
              $lockedBand .=  $bandLockDict{$ii}.", ";
            }
            elsif(($ii < 192) && (($bandLTE & (1 << ($ii-128))) == (1 << ($ii-128))))
            {
              $lockedBand .=  $bandLockDict{$ii}.", ";
            }
          }
          $lockedBand = trim($lockedBand);
          my $var = substr($lockedBand,length($lockedBand)-1,1);
          if( $var eq ",")
          {
            $lockedBand = substr($lockedBand, 0, length($lockedBand)-1);
          }
        }

        my $MaxElementPerLine = 5;
        my $firstline = 1; 
        my @lockedBand = split(',', $lockedBand);
        while(@lockedBand > 0)
        {
          if($#lockedBand > $MaxElementPerLine)
          {
            if($firstline == 1)
            {
              LogPrint((sprintf $OutFormat, 'BandLock', trim(join(', ', @lockedBand[0..$MaxElementPerLine]))), 1);
              $firstline = 0;
            }
            else
            {
              LogPrint((sprintf $OutFormat, '', trim(join(', ', @lockedBand[0..$MaxElementPerLine]))), 1);
            }
            @lockedBand = @lockedBand[$MaxElementPerLine+1..$#lockedBand];
          }
          else
          {
            if($firstline == 1)
            {
              LogPrint((sprintf $OutFormat, 'BandLock', trim(join(', ', @lockedBand))), 1);
            }
            else
            {
              LogPrint((sprintf $OutFormat, '', trim(join(', ', @lockedBand))), 1);
            }
            @lockedBand = ();
          }
        }
      }
    }
  }
  return;
}

#########################################################################################
# Func:
#    GetSupportedRat
# Description:
#    Get baseband supportted RAT
#########################################################################################
sub GetSupportedRat
{
  my ($ratMask) = @_;
  my %ratDict = (
            1=>'CDMA',
            2=>'HDR',
            4=>'GSM',
            8=>'WCDMA',
            16=>'LTE',
            32=>'TDSCDMA',
  );
  my $ratName = "";
  my $idx = 0;
  while($idx < 16)
  {
    my $ratBit = $ratMask & (1 << $idx);
    if($ratBit)
    {
      $ratName .= $ratDict{$ratBit}.", ";
    }
    $idx = $idx + 1;
  }
  return trim($ratName);
}

#########################################################################################
# Func:
#    BBGetCapability
# Description:
#    Get baseband capability
#########################################################################################
sub BBGetCapability
{
  my $cmd = '/usr/local/bin/ETLTool raw 0x4B 0xFD 0x44 0x00 0x17';
  my $out = ETLRawCmd($cmd);

  LogPrint(" ", 1);

  if(length($out) < 12)
  {
    LogPrint("ERR: Rsppkt length is too short", 0);
  }
  else
  {
    my $header = trim(substr($out,0,11));
    my $body = trim(substr($out,length($header),length($out)-length($header)));
    LogPrint("Header: ".$header, 0);
    LogPrint("Body: ".$body, 0);
    if($header ne "4B FD 44 00")
    {
      LogPrint("ERR: Rsppkt header is not 4B FD 44 00", 0);
    }
    else
    {
      my @rsp = split(' ', $body);
      my $status = USHORT(\@rsp);
      if($status == 1)
      {
        my $hwCapMask = SHORT(\@rsp);
        my $tktCapMask = SHORT(\@rsp);
        my $priCapMask = SHORT(\@rsp);
        LogPrint("hwCapMask: ".sprintf("0x%X", $hwCapMask), 0);
        LogPrint("tktCapMask: ".sprintf("0x%X", $tktCapMask), 0);
        LogPrint("priCapMask: ".sprintf("0x%X", $priCapMask), 0);

        my $hwSupportedRat = GetSupportedRat($hwCapMask);
        my $tktSupportedRat = GetSupportedRat($tktCapMask);
        my $priSupportedRat = GetSupportedRat($priCapMask);
        my $BBSupportedRat = GetSupportedRat($hwCapMask & $tktCapMask & $priCapMask);

        LogPrint((sprintf $OutFormat, 'RAT_CAP(HW)', $hwSupportedRat), 1);
        LogPrint((sprintf $OutFormat, 'RAT_CAP(Ticket)', $tktSupportedRat), 1);
        LogPrint((sprintf $OutFormat, 'RAT_CAP(PRI)', $priSupportedRat), 1);
        LogPrint((sprintf $OutFormat, 'RAT_CAP(Final)', $BBSupportedRat), 1);
      } #END OF $status == 1
    } #END OF $header ne "4B FD 44 00"
  } #END OF length($out) < 12
  return;
}

#########################################################################################
# Func:
#    BBGetSettingStaus
# Description:
#    Get baseband setting status
#########################################################################################
sub BBGetSettingStaus
{
  my $cmd = '/usr/local/bin/ETLTool raw 0x26 0x60 0xC3';
  my $out = ETLRawCmd($cmd);

  LogPrint(" ", 1);

  if(length($out) < 9)
  {
    LogPrint("ERR: Rsppkt length is too short", 0);
  }
  else
  {
    my $header = trim(substr($out,0,8));
    my $body = trim(substr($out,length($header),length($out)-length($header)));
    LogPrint("Header: ".$header, 0);
    LogPrint("Body: ".$body, 0);
    if($header ne "26 60 C3")
    {
      LogPrint("ERR: Rsppkt header is not 26 60 C3", 0);
    }
    else
    {
      my @rsp = split(' ', $body);
      my $setting = USHORT(\@rsp);
      my $settingName = "NA";

      LogPrint("Setting: ".$setting, 0);
      if($setting == 1)
      {
        $settingName = "SHIPPING";
      }
      elsif($setting == 2)
      {
        $settingName = "FACTORY";
      }
      LogPrint((sprintf $OutFormat, 'Setting', $settingName), 1);
    }
  }
  return;
}

#########################################################################################
# Func:
#    GetHWBuildInfo
# Description:
#    Get HW build information
######################################################################################### 
sub GetHWBuildInfo()
{
  if($gHWVersion eq 'NA')
  {
    my $out = qx(/usr/local/bin/memdump -r -a syscfg | grep CFG#);
    if((index($out, ":") != -1))
    {
      my @result = split(':', $out);
      $out = $result[1];
      @result = split('/', $out);
      $gHWConfig = trim($result[0]);
      $gHWVersion = trim($result[1]);
    }      
  }
  
  if($gHWConfig eq 'NA')
  {
    my %hwRevDict = (
    #/* N61 */
    0x0000=>'N61_DEV1',
    0x0001=>'N61_DEV2',
    0x0002=>'N61_DEV3',
    0x0003=>'N61_DEV4',
    0x0004=>'N61_MLB1',
    0x0005=>'N61_MLB2',
    0x0006=>'N61_PROTO_1',
    0x0007=>'N61_PROTO_2',
    0x0008=>'N61_EVT1',
    0x0009=>'N61_EVT2',
    0x000A=>'N61_DVT',
    0x000B=>'N61_PVT',

    #/* N56 */
    0x0100=>'N56_DEV1',
    0x0101=>'N56_DEV2',
    0x0102=>'N56_DEV3',
    0x0103=>'N56_DEV4',
    0x0104=>'N56_MLB1',
    0x0105=>'N56_MLB2',
    0x0106=>'N56_PROTO_1',
    0x0107=>'N56_PROTO_2',
    0x0108=>'N56_EVT1',
    0x0109=>'N56_EVT2',
    0x010A=>'N56_DVT',
    0x010B=>'N56_PVT',

    #/* J82 */
    0x0200=>'J82_DEV1',
    0x0201=>'J82_PROTO_0',
    0x0202=>'J82_PROTO_1',
    0x0203=>'J82_PROTO_2',
    0x0204=>'J82_EVT',
    0x0205=>'J82_DVT',
    0x0206=>'J82_PVT',
    0x0207=>'J82_RSVD',

    #/* J97 */
    0x0300=>'J97_DEV1',
    0x0301=>'J97_BRINGUP',
    0x0302=>'J97_PROTO_0', 
    0x0303=>'J97_PROTO_0B', 
    0x0304=>'J97_PROTO_1',
    0x0305=>'J97_PROTO_2',
    0x0306=>'J97_EVT',
    0x0307=>'J97_DVT',
    0x0308=>'J97_PVT',
    0x0309=>'J97_RSVD',

    #/* J99 */
    0x0400=>'J99_PROTO_0',
    0x0400=>'J99_PROTO_1',
    0x0400=>'J99_PROTO_2', 
    0x0400=>'J99_EVT',
    0x0400=>'J99_DVT',
    0x0400=>'J99_PVT',
    0x0400=>'J99_RSVD',
  
    0x7FFF=>'INVALID',
    );

    my $hwConfig = 'NA';
    my $hwVersion = 'NA';
        
    my $out = ETLRawCmd('/usr/local/bin/ETLTool raw 4b fe 00 00');
    if(length($out) < 12)
    {
      LogPrint("ERR: Rsppkt length is too short", 0);
    }
    else
    {
      my $header = trim(substr($out,0,11));
      my $body = trim(substr($out,length($header),length($out)-length($header)));
      LogPrint("Header: ".$header, 0);
      LogPrint("Body: ".$body, 0);
      if($header ne "4B FE 00 00")
      {
        LogPrint("ERR: Rsppkt header is not 4B FE 00 00", 0);
      }
      else
      {
        my @rsp = split(' ', $body);
        my $status = USHORT(\@rsp);
        if($status == 1)
        {
          $gHWConfig = chr(UBYTE(\@rsp)).chr(UBYTE(\@rsp)).chr(UBYTE(\@rsp));
          my $fourth = chr(UBYTE(\@rsp));
          if($fourth eq 'E')
          {
            $gHWConfig = $gHWConfig.'_EU';
          }
          else
          {
            $gHWConfig = $gHWConfig.$fourth;
          }
          $gHWConfig = trim($gHWConfig);
          $gHWVersion = USHORT(\@rsp);
          if(exists $hwRevDict{$gHWVersion})
          {
            $gHWVersion = $hwRevDict{$gHWVersion};
          }
        
          LogPrint("Status: ".$status, 0);
        }
      }
    }
  }
  
  LogPrint("hwConfig: ".$gHWConfig, 0);
  LogPrint("hwVersion: ".$gHWVersion, 0);
  if((substr($gHWConfig, 0, 3) eq 'N61') || (substr($gHWConfig, 0, 3) eq 'N71'))
  {
    $OutFormat = $OutFormatN61;
    $MaxElementPerLine = $MaxElementPerLineN61;
  }
  elsif((substr($gHWConfig, 0, 3) eq 'N56') || (substr($gHWConfig, 0, 3) eq 'N66'))
  {
    $OutFormat = $OutFormatN56;
    $MaxElementPerLine = $MaxElementPerLineN56;
  }
  elsif(substr($gHWConfig, 0, 3) eq 'J82')
  {
    $OutFormat = $OutFormatJ82;
    $MaxElementPerLine = $MaxElementPerLineJ82;
  }
  elsif(substr($gHWConfig, 0, 3) eq 'J97')
  {
    $OutFormat = $OutFormatJ97;
    $MaxElementPerLine = $MaxElementPerLineJ97;
  }
  elsif(substr($gHWConfig, 0, 3) eq 'J99')
  {
    $OutFormat = $OutFormatJ99;
    $MaxElementPerLine = $MaxElementPerLineJ99;
  }
}

#########################################################################################
# Func:
#    GetPhoneInfo
# Description:
#    Get baseband setting status
######################################################################################### 
sub GetPhoneInfo()
{
  my @out;
  my @result;
  
  LogPrint("*****************************************************************", 1);
  LogPrint("Phone Info ...", 1);
  LogPrint("*****************************************************************", 1);

  GetHWBuildInfo();
  LogPrint((sprintf $OutFormat, 'HW', $gHWConfig.' ('.$gHWVersion.')'), 1);
        
  @out = qx(/usr/local/bin/gestalt_query ModelNumber);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, 'Model', trim($result[1])), 1);

  @out = qx(/usr/local/bin/gestalt_query RegionInfo);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, "Region", trim($result[1])), 1);
  
  @out = qx(/usr/local/bin/gestalt_query SerialNumber);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, "SN\t", trim($result[1])), 1);

  @out = qx(/usr/local/bin/gestalt_query BuildVersion);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, "Bundle", trim($result[1])), 1);

  @out = qx(/usr/local/bin/ETLTool read-meid);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, "MEID", trim($result[1])), 1);

  @out = qx(/usr/local/bin/ETLTool read-imei);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, "IMEI\t", trim($result[1])), 1);

  @out = qx(/usr/local/bin/ETLTool get-iccid);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, 'ICCID', trim($result[1])), 1);
  
  @out = qx(/usr/local/bin/gestalt_query MobileSubscriberCountryCode);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, 'MCC', trim($result[1])), 1);

  @out = qx(/usr/local/bin/gestalt_query MobileSubscriberNetworkCode);
  @result = split(':', $out[0]);
  LogPrint((sprintf $OutFormat, 'MNC', trim($result[1])), 1);
  
  @out = qx(/usr/local/bin/gestalt_query CarrierBundleInfoArray | grep CFBundleIdentifier);
  if((scalar(@out) > 0) && (index($out[0], "=>") != -1))
  {
    @result = split('=>', $out[0]);
    LogPrint((sprintf $OutFormat, 'CBName', trim($result[1])), 1);
  }
  else
  {
    LogPrint((sprintf $OutFormat, 'CBName', 'NA'), 1);
  }
  
  @out = qx(/usr/local/bin/gestalt_query CarrierBundleInfoArray | grep CFBundleVersion);
  if((scalar(@out) > 0) && (index($out[0], "=>") != -1))
  {
    @result = split('=>', $out[0]);
    LogPrint((sprintf $OutFormat, 'CBVer', trim($result[1])), 1);
  }
  else
  {
    LogPrint((sprintf $OutFormat, 'CBVer', 'NA'), 1);
  }
  return
}
      
#########################################################################################
# Func:
#    GetBasebandInfo
# Description:
#    Get baseband basic info
#########################################################################################
sub GetBasebandInfo
{
  LogPrint(" ", 1);
  LogPrint("*****************************************************************", 1);
  LogPrint("Baseband Info ...", 1);
  LogPrint("*****************************************************************", 1);

  BBGetFWVersion();
  BBGetSN();
  BBGetCalType();
  BBGetBandAndCalStatus(0);
  BBGetCapability();
  BBGetSettingStaus();
  
  if($gFullLog == 1)
  {
    BBGetBandLockStatus();
  }
  return;
}

#########################################################################################
# Func:
#    DecodeBandPref
# Description:
#    Decode preferred band to readable format
#########################################################################################
sub DecodeBandPref
{
  my ($prefBand, $type) = @_;
  my %PREF_BAND_DICT = (
  #GSM
        0x00 => ['G_850 ', 0x00000000, 0x00080000],
        0x01 => ['G_900 ', 0x00000000, 0x00000100],
  	    0x02 => ['G_1800', 0x00000000, 0x00000080],
        0x03 => ['G_1900', 0x00000000, 0x00200000],

  #UMTS
        0x10 => ['W_BC1 ', 0x00000000, 0x00400000],
        0x11 => ['W_BC2 ', 0x00000000, 0x00800000], 
        0x12 => ['W_BC3 ', 0x00000000, 0x01000000],
        0x13 => ['W_BC4 ', 0x00000000, 0x02000000],
        0x14 => ['W_BC5 ', 0x00000000, 0x04000000],
        0x15 => ['W_BC6 ', 0x00000000, 0x08000000],
        0x16 => ['W_BC7 ', 0x00010000, 0x00000000],
        0x17 => ['W_BC8 ', 0x00020000, 0x00000000],
        0x18 => ['W_BC9 ', 0x00040000, 0x00000000],
        0x19 => ['W_BC11', 0x00000000, 0x00008000],
        0x1A => ['W_BC19', 0x00040000, 0x00000000],

  #C2K
        0x20 => ['C_BC0 ', 0x00000000, 0x00000001],
        0x21 => ['C_BC1 ', 0x00000000, 0x00000002],
        0x22 => ['C_BC2 ', 0x00000000, 0x00000004],
        0x23 => ['C_BC3 ', 0x00000000, 0x00000008],
        0x24 => ['C_BC4 ', 0x00000000, 0x00000010],
        0x25 => ['C_BC5 ', 0x00000000, 0x00000020],
        0x26 => ['C_BC6 ', 0x00000000, 0x00000040],
        0x27 => ['C_BC7 ', 0x00000000, 0x00000080],
        0x28 => ['C_BC8 ', 0x00000000, 0x00000100],
        0x29 => ['C_BC9 ', 0x00000000, 0x00000200],
        0x2A => ['C_BC10', 0x00000000, 0x00000400],
        0x2B => ['C_BC11', 0x00000000, 0x00000800],
        0x2C => ['C_BC12', 0x00000000, 0x00001000],
        0x2D => ['C_BC13', 0x00000000, 0x00002000],
        0x2E => ['C_BC14', 0x00000000, 0x00004000],
        0x2F => ['C_BC15', 0x00000000, 0x00008000],
        0x30 => ['C_BC16', 0x00000000, 0x00010000],
        0x32 => ['C_BC18', 0x00000000, 0x00040000],
        0x33 => ['C_BC19', 0x00000000, 0x00080000],
    );
    
    my %LTE_PREF_BAND_DICT = (
        0x40 => ['L_B1  ', 0x00000000, 0x00000001],
        0x41 => ['L_B2  ', 0x00000000, 0x00000002],
        0x42 => ['L_B3  ', 0x00000000, 0x00000004],
        0x43 => ['L_B4  ', 0x00000000, 0x00000008],
        0x44 => ['L_B5  ', 0x00000000, 0x00000010],
        0x45 => ['L_B6  ', 0x00000000, 0x00000020],
        0x46 => ['L_B7  ', 0x00000000, 0x00000040],
        0x47 => ['L_B8  ', 0x00000000, 0x00000080],
        0x48 => ['L_B9  ', 0x00000000, 0x00000100],
        0x49 => ['L_B10 ', 0x00000000, 0x00000200],
        0x4A => ['L_B11 ', 0x00000000, 0x00000400],
        0x4B => ['L_B12 ', 0x00000000, 0x00000800],
        0x4C => ['L_B13 ', 0x00000000, 0x00001000],
        0x4D => ['L_B14 ', 0x00000000, 0x00002000],
        0x4E => ['L_B15 ', 0x00000000, 0x00004000],
        0x4F => ['L_B16 ', 0x00000000, 0x00008000],
        0x50 => ['L_B17 ', 0x00000000, 0x00010000],
        0x51 => ['L_B18 ', 0x00000000, 0x00020000],
        0x52 => ['L_B19 ', 0x00000000, 0x00040000],
        0x53 => ['L_B20 ', 0x00000000, 0x00080000],
        0x54 => ['L_B21 ', 0x00000000, 0x00100000],
        0x55 => ['L_B22 ', 0x00000000, 0x00200000],
        0x56 => ['L_B23 ', 0x00000000, 0x00400000],
        0x57 => ['L_B24 ', 0x00000000, 0x00800000],
        0x58 => ['L_B25 ', 0x00000000, 0x01000000],
        0x59 => ['L_B26 ', 0x00000000, 0x02000000],
        0x5A => ['L_B27 ', 0x00000000, 0x04000000],
        0x5B => ['L_B28 ', 0x00000000, 0x08000000],
        0x5C => ['L_B29 ', 0x00000000, 0x10000000],
        0x5D => ['L_B30 ', 0x00000000, 0x20000000],
        0x5E => ['L_B31 ', 0x00000000, 0x40000000],
        0x5F => ['L_B32 ', 0x00000000, 0x80000000],
        0x60 => ['L_B33 ', 0x00000001, 0x00000000],
        0x61 => ['L_B34 ', 0x00000002, 0x00000000],
        0x62 => ['L_B35 ', 0x00000004, 0x00000000],
        0x63 => ['L_B36 ', 0x00000008, 0x00000000],
        0x64 => ['L_B37 ', 0x00000010, 0x00000000],
        0x65 => ['L_B38 ', 0x00000020, 0x00000000],
        0x66 => ['L_B39 ', 0x00000040, 0x00000000],
        0x67 => ['L_B40 ', 0x00000080, 0x00000000],
        0x68 => ['L_B41 ', 0x00000100, 0x00000000],
        0x69 => ['L_B42 ', 0x00000200, 0x00000000],
        0x6A => ['L_B43 ', 0x00000400, 0x00000000],
        0x6B => ['L_B44 ', 0x00000800, 0x00000000],
  );
  
  my %TDS_PREF_BAND_DICT = (
        0x70 => ['T_B34 ', 0x00000000, 0x00000001],
        0x71 => ['T_B39 ', 0x00000000, 0x00000020],
        0x72 => ['T_B40 ', 0x00000000, 0x00000010],
  );
  
  my $band_pref_dict_ref = {};
  
  if ($type eq "BAND_PREF")
  {
    $band_pref_dict_ref = \%PREF_BAND_DICT;
  }
  elsif($type eq "LTE_BAND_PREF")
  {
    $band_pref_dict_ref = \%LTE_PREF_BAND_DICT;
  }
  elsif($type eq "TDS_BAND_PREF")
  {
    $band_pref_dict_ref = \%TDS_PREF_BAND_DICT;
  }
  else
  {
    return "";
  }
  
  my @result;
  my $prefBandName;
  my $prefBandValHigh;
  my $prefBandValLow;
  my @prefBandData;
  my $keyName;
  
  foreach $keyName (sort {$a<=>$b} keys %{$band_pref_dict_ref})
  {
    @prefBandData = ${$band_pref_dict_ref}{$keyName};
    $prefBandName = $prefBandData[0][0];
    $prefBandValHigh = $prefBandData[0][1];
    $prefBandValLow = $prefBandData[0][2];
    #print 'prefBand: '.sprintf('%X', $prefBand)."\n";
    #print 'prefBandName: '.$prefBandName."\n";
    #print 'prefBandValHigh: '.sprintf('%X', $prefBandValHigh)."\n";
    #print 'prefBandValLow: '.sprintf('%X', $prefBandValLow)."\n";
    if(($prefBandValHigh > 0) && ((($prefBand >> 32) & $prefBandValHigh) == $prefBandValHigh))
    {
      push @result, $prefBandName;
    }
    elsif(($prefBandValLow > 0) && (($prefBand & $prefBandValLow) == $prefBandValLow))
    {
      push @result, $prefBandName;
    }
  }
  
  return @result;
}

#########################################################################################
# Func:
#    GetDiagTraceStatus
# Description:
#    Check whether or not diag trace is enabled
#########################################################################################
sub GetDiagTraceStatus
{
  my @out = qx(/usr/local/bin/ETLTool ping | grep 'You have DIAG tracing on, please turn it off');
  if(scalar(@out) > 0)
  {
    $gDiagTraceOn = 1;
  }
}

#########################################################################################
# Func:
#    ConfigDiagTrace
# Description:
#    Check whether or not diag trace is enabled
#########################################################################################
sub ConfigDiagTrace
{ 
  my ($diagTraceConfig) = (@_);
  
  if($diagTraceConfig == 1)
  {
    qx(/usr/local/bin/abmtool diag enable wait);
  }
  else
  {
    qx(/usr/local/bin/abmtool diag disable wait);
    my $retryCnt = 0;
    my @out = qx(/usr/local/bin/ETLTool ping | grep 'You have DIAG tracing on, please turn it off');
    while((scalar(@out) > 0) && $retryCnt < 10)
    {
        qx(/usr/local/bin/abmtool diag disable wait);
        @out = qx(/usr/local/bin/ETLTool ping | grep 'You have DIAG tracing on, please turn it off');
        $retryCnt += 1;
    }
  }
}

#########################################################################################
# Func:
#    ShowBandInfo
# Description:
#    System preferred band and band capability is bit masked. 
#########################################################################################
sub ShowBandInfo
{
  my ($band_pref, $showName) = (@_);
  my $checkName = $showName;
  if(($checkName eq 'prst_band_pref') || ($checkName eq 'band_capability'))
  {
    $checkName = 'BAND_PREF';
  }
  elsif(($checkName eq 'prst_lte_band_pref')  || ($checkName eq 'lte_band_capability'))
  {
    $checkName = 'LTE_BAND_PREF';
  }
  elsif(($checkName eq 'prst_tds_band_pref')  || ($checkName eq 'tds_band_capability'))
  {
    $checkName = 'TDS_BAND_PREF';
  }
  $checkName=~ tr/a-z/A-Z/;
  #LogPrint((sprintf $OutFormat, $showName, sprintf('%X', $band_pref)), 1);
  
  my @bandPrefArr = DecodeBandPref($band_pref, $checkName);
  my $MaxElementPerLine = 5;
  my $firstline = 1; 
  while(@bandPrefArr > 0)
  {
    if($#bandPrefArr > $MaxElementPerLine)
    {
      if($firstline == 1)
      {
        LogPrint((sprintf $OutFormat, $showName, trim(join(', ', @bandPrefArr[0..$MaxElementPerLine]))), 1);
        $firstline = 0;
      }
      else
      {
        LogPrint((sprintf $OutFormat, '', trim(join(', ', @bandPrefArr[0..$MaxElementPerLine]))), 1);
      }
      @bandPrefArr = @bandPrefArr[$MaxElementPerLine+1..$#bandPrefArr];
    }
    else
    {
      if($firstline == 1)
      {
        LogPrint((sprintf $OutFormat, $showName, trim(join(', ', @bandPrefArr))), 1);
      }
      else
      {
        LogPrint((sprintf $OutFormat, '', trim(join(', ', @bandPrefArr))), 1);
      }
      @bandPrefArr = ();
    }
  } 
}

#########################################################################################
# Func:
#    GetBBCMInfo
# Description:
#    Get baseband CM infomation
#########################################################################################
sub GetBBCMInfo
{
  LogPrint(" ", 1);
  LogPrint("*****************************************************************", 1);
  LogPrint("Baseband CM Info ...", 1);
  LogPrint("*****************************************************************", 1);

  my %OPRT_MODE_DICT = (
             0=>'POWROFF',
             1=>'FTM',
             2=>'OFFLINE',
             3=>'AMPS',
             4=>'CDMA',
             5=>'ONLINE',
             6=>'LPM',
             7=>'RESET',
             8=>'NET_TEST_GW',
             9=>'OFFLINE_IF_NOT_FTM',
            10=>'PSEUDO_ONLINE',
            11=>'RESET_MODEM',
            12=>'CAMP_ONLY',
        );

  my %CM_MODE_PREF_DICT = (
            0=>'AMPS_ONLY',
            1=>'DIGITAL_ONLY',
            2=>'AUTOMATIC',
            3=>'EMERGENCY',
            9=>'CDMA_ONLY',
            10=>'HDR_ONLY',
            11=>'CDMA_AMPS_ONLY',
            12=>'GPS_ONLY',
            13=>'GSM_ONLY',
            14=>'WCDMA_ONLY',
            15=>'PERSISTENT',
            16=>'NO_CHANGE',
            17=>'ANY_BUT_HDR',
            18=>'CURRENT_LESS_HDR',
            19=>'GSM_WCDMA_ONLY',
            20=>'DIGITAL_LESS_HDR_ONLY',
            21=>'CURRENT_LESS_HDR_AND_AMPS',
            22=>'CDMA_HDR_ONLY',
            23=>'CDMA_AMPS_HDR_ONLY',
            24=>'CURRENT_LESS_AMPS',
            25=>'WLAN_ONLY',
            26=>'CDMA_WLAN',
            27=>'HDR_WLAN',
            28=>'CDMA_HDR_WLAN',
            29=>'GSM_WLAN',
            30=>'WCDMA_WLAN',
            31=>'GW_WLAN',
            32=>'CURRENT_PLUS_WLAN',
            33=>'CURRENT_LESS_WLAN',
            34=>'CDMA_AMPS_HDR_WLAN_ONLY',
            35=>'CDMA_AMPS_WLAN_ONLY',
            36=>'INTERSECT_OR_FORCE',
            37=>'ANY_BUT_HDR_WLAN',
            38=>'LTE_ONLY',
            39=>'GWL',
            40=>'HDR_LTE_ONLY',
            41=>'CDMA_HDR_LTE_ONLY',
            42=>'CDMA_HDR_GW',
            43=>'CDMA_GW',
            44=>'ANY_BUT_WLAN',
            45=>'GWL_WLAN',
            46=>'CDMA_LTE_ONLY',
            47=>'ANY_BUT_HDR_LTE',
            48=>'ANY_BUT_LTE',
            49=>'DIGITAL_LESS_LTE_ONLY',
            50=>'DIGITAL_LESS_HDR_LTE_ONLY',
            51=>'GSM_LTE',
            52=>'CDMA_GSM_LTE',
            53=>'HDR_GSM_LTE',
            54=>'WCDMA_LTE',
            55=>'CDMA_WCDMA_LTE',
            56=>'HDR_WCDMA_LTE',
            57=>'CDMA_HDR_GSM',
            58=>'CDMA_GSM',
            59=>'TDS_ONLY',
            60=>'TDS_GSM',
            61=>'TDS_GSM_LTE',
            62=>'TDS_GSM_WCDMA_LTE',
            63=>'TDS_GSM_WCDMA',
            64=>'ANY_BUT_HDR_WLAN_LTE',
            65=>'TDS_LTE',
            66=>'CDMA_GW_TDS',
            67=>'CDMA_HDR_GW_TDS',
            68=>'CDMA_HDR_GSM_WCDMA_LTE',
            69=>'CDMA_GSM_WCDMA_LTE',
            70=>'TDS_WCDMA',
            71=>'DISABLE_LTE',
            72=>'ENABLE_LTE',
            73=>'TDS_WCDMA_LTE',
            74=>'ANY_BUT_TDS',
            75=>'ANY_BUT_HDR_TDS',
            76=>'ANY_BUT_LTE_TDS',
            77=>'ANY_BUT_HDR_LTE_TDS',
            78=>'CDMA_HDR_GSM_AMPS',
            79=>'CDMA_GSM_AMPS',
            80=>'CDMA_HDR_GSM_GPS_AMPS',
            81=>'CDMA_GSM_GPS_AMPS',
            82=>'CDMA_HDR_GSM_TDS_LTE',
            83=>'GSM_GPS',
            84=>'WCDMA_GPS',
            85=>'GW_GPS',
            86=>'HDR_GSM',
            87=>'ANY_BUT_CDMA_HDR',
            88=>'TDS_GSM_GPS',
            89=>'TDS_GSM_WCDMA_GPS',
    );

  my %CM_PRL_PREF_DICT = (
            0=>'CM_PRL_PREF_NONE',
            1=>'CM_PRL_PREF_AVAIL_BC0_A',
            2=>'CM_PRL_PREF_AVAIL_BC0_B',
            16383=>'CM_PRL_PREF_ANY',
    );

  my %CM_ROAM_PREF_DICT = (
            0=>'NONE',
            1=>'HOME',
            2=>'ROAM_ONLY',
            3=>'AFFIL',
            255=>'ANY',
    );

  my %CM_HYBR_PREF_DICT = (
            0=>'OFF',
            1=>'CDMA__HDR',
            2=>'NO_CHANGE',
            3=>'PERSISTENT',
            4=>'CDMA__HDR_WCDMA',
            5=>'CDMA__WCDMA',
            6=>'CDMA__LTE__HDR',
            7=>'CDMA__GWL__HDR',
    );
  my %CM_SRV_DOMAIN_PREF_DICT = (
            0=>'CS_ONLY',
            1=>'PS_ONLY',
            2=>'CS_PS',
            3=>'ANY',
            4=>'NO_CHANGE',
            5=>'PS_ATTACH',
            6=>'PS_DETACH',
            7=>'PERSISTENT',
            8=>'PS_LOCAL_DETACH',
    );
    my %CM_SYS_MODE_DICT = (
            0=>'NO_SRV',
            1=>'AMPS',
            2=>'CMDA',
            3=>'GSM',
            4=>'HDR',
            5=>'WCDMA',
            6=>'GPS',
            7=>'GW',
            8=>'WLAN',
            9=>'LTE',
            10=>'GWL',
            11=>'TDS'
    );

    my %CM_ACQ_ORDER_DICT = (
            0=>'AUTOMATIC',
            1=>'GSM_WCDMA',
            2=>'WCDMA_GSM',
            3=>'NO_CHANGE',
            4=>'PERSISTENT',
    );
        
    my %CM_NETWORK_SEL_MODE_DICT = (
            0=>'AUTOMATIC',
            1=>'MANUAL',
            2=>'LIMITED_SRV',
            3=>'NO_CHANGE',
            4=>'PERSISTENT',
            5=>'HPLMN_SRCH',
            6=>'AUTO_LIMITED_SRV',
            7=>'MANUAL_LIMITED_SRV',
            8=>'AUTO_CAMP_ONLY',
            9=>'MANUAL_CAMP_ONLY',
    );
        
    my %CM_SRV_STATUS_DICT = (
            0=>'NO_SRV',
            1=>'LIMITED',
            2=>'SRV_AVAILABLE',
            3=>'LIMITED_REGIONAL',
            4=>'PWR_SAVE',
            5=>'NO_SRV_INFERNAL',
            6=>'LIMITED_INTERNAL',
            7=>'LIMITED_REGIONAL_INTERNAL',
            8=>'PWR_SAVE_INTERNAL'
    );
        
    my %CM_CALL_STATE_DICT = (
            0=>'IDLE',
            1=>'ORIGINATION',
            2=>'INCOMING',
            3=>'CONVERSATION',
            4=>'CALL_CONTROL_IN_PROGRESS',
            5=>'WAITING_RECAL_RSP',
    );
        
  my $cmd = '/usr/local/bin/ETLTool raw 0x4B 0x0F 0x00 0x00';
  my $out = ETLRawCmd($cmd);
  if(length($out) < 12)
  {
    LogPrint("ERR: Rsppkt length is too short", 0);
  }
  else
  {
    my $header = trim(substr($out,0,11));
    my $body = trim(substr($out,length($header),length($out)-length($header)));
    LogPrint("Header: ".$header, 0);
    LogPrint("Body: ".$body, 0);
    if($header ne "4B 0F 00 00")
    {
      LogPrint("ERR: Rsppkt header is not 4B 0F 00 00", 0);
    }
    else
    {
        my @rsp = split(' ', $body);
        my $call_state = UINT(\@rsp);
        if(exists $CM_CALL_STATE_DICT{$call_state})
        {
          $call_state = $CM_CALL_STATE_DICT{$call_state};
        }
        else
        {
          $call_state = "NA";
        }
        LogPrint((sprintf $OutFormat, 'call_state', $call_state), 1);
        
        my $oprt_mode = UINT(\@rsp);
        if(exists $OPRT_MODE_DICT{$oprt_mode})
        {
          $oprt_mode = $OPRT_MODE_DICT{$oprt_mode};
        }
        else
        {
          $oprt_mode = "NA";
        }
        LogPrint((sprintf $OutFormat, 'oprt_mode', $oprt_mode), 1);

        my $sys_mode = UINT(\@rsp);
        if(exists $CM_SYS_MODE_DICT{$sys_mode})
        {
          $sys_mode = $CM_SYS_MODE_DICT{$sys_mode};
        }
        else
        {
          $sys_mode = "NA";
        }
        LogPrint((sprintf $OutFormat, 'sys_mode', $sys_mode), 1);
        
        my $mode_pref = UINT(\@rsp);
        if(exists $CM_MODE_PREF_DICT{$mode_pref})
        {
          $mode_pref = $CM_MODE_PREF_DICT{$mode_pref};
        }
        else
        {
          $mode_pref = "NA";
        }
        LogPrint((sprintf $OutFormat, 'mode_pref', $mode_pref), 1);
        
        my $band_pref = UINT(\@rsp);
        if($gFullLog == 1)
        {
          ShowBandInfo($band_pref, 'band_pref');
        }
        
        my $roam_pref = UINT(\@rsp);
        if(exists $CM_ROAM_PREF_DICT{$roam_pref})
        {
          $roam_pref = $CM_ROAM_PREF_DICT{$roam_pref};
        }
        else
        {
          $roam_pref = "NA";
        }
        LogPrint((sprintf $OutFormat, 'roam_pref', $roam_pref), 1);
 
        my $srv_domain_pref = UINT(\@rsp);
        if(exists $CM_SRV_DOMAIN_PREF_DICT{$srv_domain_pref})
        {
          $srv_domain_pref = $CM_SRV_DOMAIN_PREF_DICT{$srv_domain_pref};
        }
        else
        {
          $srv_domain_pref = "NA";
        }
        LogPrint((sprintf $OutFormat, 'srv_domain_pref', $srv_domain_pref), 1);
        
        my $acq_order = UINT(\@rsp);
        if(exists $CM_ACQ_ORDER_DICT{$acq_order})
        {
          $acq_order = $CM_ACQ_ORDER_DICT{$acq_order};
        }
        else
        {
          $acq_order = "NA";
        }
        LogPrint((sprintf $OutFormat, 'acq_order', $acq_order), 1);

        my $hybr_pref = UINT(\@rsp);
        if(exists $CM_HYBR_PREF_DICT{$hybr_pref})
        {
          $hybr_pref = $CM_HYBR_PREF_DICT{$hybr_pref};
        }
        else
        {
          $hybr_pref = "NA";
        }
        LogPrint((sprintf $OutFormat, 'hybr_pref', $hybr_pref), 1);
        
        my $sel_mode_pref = UINT(\@rsp);
        if(exists $CM_NETWORK_SEL_MODE_DICT{$sel_mode_pref})
        {
          $sel_mode_pref = $CM_NETWORK_SEL_MODE_DICT{$sel_mode_pref};
        }
        else
        {
          $sel_mode_pref = "NA";
        }
        LogPrint((sprintf $OutFormat, 'sel_mode_pref', $sel_mode_pref), 1);

        my $srv_status = UINT(\@rsp);
        if(exists $CM_SRV_STATUS_DICT{$srv_status})
        {
          $srv_status = $CM_SRV_STATUS_DICT{$srv_status};
        }
        else
        {
          $srv_status = "NA";
        }
        LogPrint((sprintf $OutFormat, 'srv_status', $srv_status), 1);
    } #END OF $header ne "4B FD 44 00"
  } #END OF length($out) < 12
  return;
}

#########################################################################################
# Func:
#    Plain2Html
# Description:
#    Convert plain test result to html format
#########################################################################################
sub Plain2Html
{
  my ($txtReportFile, $htmlReportFile) = (@_);
  my $htmlReportHandler;
  my @columns = ();
  my $column;
  my $var;

  LogPrint("-------------------------------------------------", 0);
  LogPrint("Generat HTML test report", 0);
  LogPrint("-------------------------------------------------", 0);

  open($htmlReportHandler, ">$htmlReportFile") || die "Cannot open $htmlReportFile!";

  close ($gTxtReportHandler);

  open($gTxtReportHandler, "<$txtReportFile") || die "Cannot open $txtReportFile!";
  my @lines = <$gTxtReportHandler>;

  print $htmlReportHandler "<html>\n";
  print $htmlReportHandler "<head></head>\n";
  print $htmlReportHandler "<body>\n";

  my $isInHtmlTable = 0;
  foreach my $line (@lines)
  {
    if($line =~ m/\@/s)
    {
      if($isInHtmlTable == 0)
      {
        $isInHtmlTable = 1;
        print $htmlReportHandler "<table border=\"1\">\n";
        print $htmlReportHandler "<tr bgcolor=\"Grey\">\n";
        @columns = split('@', $line);
        foreach $column (@columns)
        {
          if(length(trim($column)) == 0)
          {
            next;
          }
          print $htmlReportHandler "<th>".trim($column)."</th>\n";
        }
        print $htmlReportHandler "</tr>\n"; # write </tr> tag
      }
      else
      {
        print $htmlReportHandler '</table>\n';
        print $htmlReportHandler '<p>\n';
        print $htmlReportHandler '<table border="1">\n';
        print $htmlReportHandler '<tr bgcolor="Grey">\n';
        @columns = split('@', $line);
        foreach $column (@columns)
        {
          if(length(trim($column)) == 0)
          {
            next;
          }
          print $htmlReportHandler "<th>".trim($column)."</th>\n"; # write header columns
        }
        print $htmlReportHandler "</tr>\n"; # write </tr> tag
      }
    }#END OF $line =~ m/\@/s
    elsif ($line =~ m/\$/s)
    {
      if($isInHtmlTable == 0)
      {
        $isInHtmlTable = 1;
        print $htmlReportHandler "<table border=\"1\">\n";
      }
      @columns = split('\$', $line);
      print $htmlReportHandler "<tr>\n";
      foreach $column (@columns)
      {
        $column =~ s/###/<BR>/g;
        my $tmp = uc(trim($column));
        if($tmp =~ m/PASS$/s)
        {
          print $htmlReportHandler "<td><font color=\"Green\" size=4><B>".trim($column)."</B></font></td>\n";
        }
        elsif($tmp =~ m/FAIL$/s)
        {
          print $htmlReportHandler "<td><font color=\"Red\" size=4><B>".trim($column)."</B></font></td>\n";
        }
        elsif($tmp =~ m/PARTIAL$/s)
        {
          print $htmlReportHandler "<td><font color=\"Brown\" size=4><B>".trim($column)."</B></font></td>\n";
        }
        else
        {
          print $htmlReportHandler "<td>".trim($column)."</td>\n";
        }
      }
      print $htmlReportHandler "</tr>\n";
    }
    else
    {
      if($isInHtmlTable == 1)
      {
        $isInHtmlTable = 0;
        print $htmlReportHandler "</table>\n";
        print $htmlReportHandler "<p>\n";
      }
      while(1)
      {
        $var = substr($line,length($line)-1,1);
        if(($var eq '\n') or ($var eq '\r'))
        {
          $line = substr($line, 0, length($line)-1);
          if(length($line) == 0)
          {
            last;
          }
        }
        else
        {
          last;
        }
      }
      $line=~ s/ /&nbsp;/g;
      print $htmlReportHandler $line."<br>\n";
    }
  }

  # write </table> tag
  if($isInHtmlTable == 1)
  {
    $isInHtmlTable = 0;
    print $htmlReportHandler "</table>\n";
  }
  else
  {
    print $htmlReportHandler "</p>\n";
  }
  print $htmlReportHandler "</body>\n";
  print $htmlReportHandler "</html>\n";

  close($htmlReportHandler);

  LogPrint('Success: Generat HTML test report', 0);
  return 1;
}

#########################################################################################
# Func:
#    SyncGRI
# Description:
#    Sync current used PRI file to baseband side
#########################################################################################
sub SyncGRI
{
  my $out;
  my ($justDelete) = @_;
  my $defaultGriPath = '/System/Library/Carrier Bundles/iPhone/Default.bundle/global_setting.gri';
  my $currentGri = "/nv/nv_check/currentGRI.tmp";
  my $cmd;
  my @tmp;
  my $tmp;
  my $dirName;
  my $fileName;
  my $priFile;
  
  #Temporarily comment off GRI check
  return 1;

  LogPrint("SyncGRI", 0);

  my $retryCnt = 5;
  while($retryCnt-- > 0)
  {
    if(ETLEfsRemoveFile($currentGri))
    {
      last;
    }
  }
  if($retryCnt <= 0)
  {
    LogPrint((sprintf '  Deleting Fail (%s) ', $currentGri), 1);
    return 0;
  }

  #Wrtie PRI to BB EFS temp file for check
  if($justDelete == 0)
  {
    if (-e $defaultGriPath)
    {
      LogPrint((sprintf '  Syncing Default %s --> %s', $defaultGriPath, $currentGri), 0);
      if(ETLEfsWriteFile($defaultGriPath, $currentGri))
      {
        return 1;
      }
      else
      {
        LogPrint((sprintf 'PRI (%s) Sync failed', $currentGri), 1);
        return 0;
      }
    }
  } #END OF if($justDelete == 0)

  LogPrint("No GRI file found in AP side", 0);
  return 0;
}

#########################################################################################
# Func:
#    SyncPRI
# Description:
#    Sync current used PRI file to baseband side
#########################################################################################
sub SyncPRI
{
  my ($justDelete) = @_;
  
  my $overridePriPath = $gCarrierBundle.'/overrides*.pri';
  my $carrierPriPath = $gCarrierBundle.'/carrier.pri';
  my $defaultPriPath = '/System/Library/Carrier Bundles/iPhone/Default.bundle/carrier.pri';
  my $currentPri = "/nv/nv_check/currentPRI.tmp";
  my @localProdOverridePri;
  my $cmd;
  my @tmp;
  my $tmp;
  my $dirName;
  my $fileName;
  my $priFile = '';

  #Temporarily comment off PRI check
  return 1;
  
  LogPrint("SyncPRI", 0);

  my $retryCnt = 5;
  while($retryCnt-- > 0)
  {
    if(ETLEfsRemoveFile($currentPri))
    {
      last;
    }
  }
  if($retryCnt <= 0)
  {
    LogPrint((sprintf '  Deleting Fail (%s) ', $currentPri), 0);
    return 0;
  }

  if($justDelete == 1)
  {
    return 0;
  }
  
  #Wrtie PRI to BB EFS temp file for check
  if ($gCarrierBundle)
  {
    # Check override*.pri
    chdir($gCarrierBundle);
    $fileName = basename($overridePriPath);
    LogPrint((sprintf 'find ./ -name %s', $fileName), 0);
    $cmd = 'find ./ -name '.$fileName;
    $tmp = RawCmd($cmd);
    $tmp = basename($tmp);
    @localProdOverridePri = split(' ', $tmp);
    if (@localProdOverridePri > 0)
    {
      if ($#localProdOverridePri > 1)
      {
        LogPrint("ERR: More than one file found", 0);
        foreach $tmp (@localProdOverridePri)
        {
          LogPrint($tmp, 0);
        }
        return 0;
      }
      $priFile = $dirName."/".$localProdOverridePri[0];
      LogPrint("Find ".$priFile, 0);
      @tmp = $localProdOverridePri[0] =~ /overrides_(.*).pri/;
      if(@tmp > 0)
      {
        my @overrideProdList = split('_', $tmp[0]);
        if(grep {/$gProdName/} @overrideProdList)
        {
          $priFile = $priFile;
        }
        else
        {
          $priFile = '';
        }
      }
    }
    
    # Check whether or not carrier.pri exists
    if(($priFile eq '') && (-e $carrierPriPath))
    {
      $priFile = $carrierPriPath;
    }
  }
      
  if(($priFile eq '') && (-e $defaultPriPath))
  {
    $priFile = $defaultPriPath;
  }

  if($priFile ne '')
  {
      LogPrint((sprintf '  Syncing %s --> %s', $priFile, $currentPri), 1);
      if(ETLEfsWriteFile($priFile, $currentPri))
      {
        return 1;
      }
      else
      {
        LogPrint((sprintf 'PRI (%s) Sync failed', $priFile), 1);
        return 0;
      }
  }
  else
  {
    LogPrint("No PRI file found in AP side", 0);
  }
  return 0;
}

#########################################################################################
# Func:
#    GetNVResult
# Description:
#    Get NV check result
#########################################################################################
sub GetNVResult
{
  $gNvResult = BYTE(@_);
  if($gNvResult == $TOO_SHORT)
  {
      LogPrint("gNvResult == TOO_SHORT", 0);
      return 0;
  }
  elsif($gNvResult == 0x11)
  {
    $gNvResult = "FAIL";
  }
  elsif($gNvResult == 0x22)
  {
    $gNvResult = "NOT_ACTIVATED";
  }
  elsif($gNvResult == 0x33)
  {
    $gNvResult = "ACTIVATED";
  }
  else
  {
    $gNvResult = "NA";
  }
  LogPrint("gNvResult: ".$gNvResult, 0);
  $gPrevDecodeLocation = "gNvResult";
  return 1;
}

#########################################################################################
# Func:
#    GetNVCategory
# Description:
#    Get NV category
#########################################################################################
sub GetNVCategory
{
  $gNvCategory = BYTE(@_);
  if($gNvCategory == $TOO_SHORT)
  {
    LogPrint("gNvCategory == TOO_SHORT", 0);
      return 0;
  }
  elsif($gNvCategory == 1)
  {
    $gNvCategory = "SETTING";
  }
  elsif($gNvCategory == 2)
  {
    $gNvCategory = "PRI";
  }
  elsif($gNvCategory == 5)
  {
    $gNvCategory = "RF_COM";
  }
  elsif($gNvCategory == 6)
  {
    $gNvCategory = "RF_PROD";
  }
  elsif($gNvCategory == 7)
  {
    $gNvCategory = "RF_CAL";
  }
  else
  {
    $gNvCategory = "NA";
  }
  LogPrint("gNvCategory: ".$gNvCategory, 0);
  $gPrevDecodeLocation = "gNvCategory";
  return 1;
}

#########################################################################################
# Func:
#    GetNVType
# Description:
#    Get NV Type
#########################################################################################
sub GetNVType
{
  $gNvType = BYTE(@_);
  if($gNvType == $TOO_SHORT)
  {
    LogPrint("gNvType == TOO_SHORT", 0);
      return 0;
  }
  elsif($gNvType == 1)
  {
    $gNvType = "EFS";
  }
  elsif($gNvType == 2)
  {
    $gNvType = "NV";
  }
  else
  {
    $gNvType = "NA";
  }
  LogPrint("gNvType: ".$gNvType, 0);
  $gPrevDecodeLocation = "gNvType";
  return 1;
}

#########################################################################################
# Func:
#    GetNVLen
# Description:
#    Get NV length
#########################################################################################
sub GetNVLen
{
  $gNvLen = SHORT(@_);
  if($gNvLen == $TOO_SHORT)
  {
    LogPrint("gNvLen == TOO_SHORT", 0);
      return 0;
  }
  LogPrint("gNvLen: ".$gNvLen, 0);
  $gPrevDecodeLocation = "gNvLen";
  return 1;
}

#########################################################################################
# Func:
#    GetNvIdEfsPath
# Description:
#    Get NV Id or efs path
#########################################################################################
sub GetNvIdEfsPath
{
  if($gNvType eq "EFS")
  {
    $gEfsPath = STR(@_);
    if($gEfsPath eq "TOO_SHORT")
    {
      LogPrint("gEfsPath == TOO_SHORT", 0);
      return 0;
    }
    LogPrint("gEfsPath: ".$gEfsPath, 0);
  }
  elsif($gNvType eq "NV")
  {
    $gNvId = INT(@_);
    if($gNvId == $TOO_SHORT)
    {
      LogPrint("gNvId == TOO_SHORT", 0);
      return 0;
    }
    LogPrint("gNvId: ".$gNvId, 0);
    $gNvId += 0;
  }
  $gPrevDecodeLocation = "nv_id_efs_path";
  return 1;
}

#########################################################################################
# Func:
#    GetExpVal
# Description:
#    Get expected NV item value
#########################################################################################
sub GetExpVal
{
  if($gNvResult eq "ACTIVATED")
  {
    $gNvExpVal = "NOT_ACTIVATED";
  }
  else
  {
    $gNvExpVal = RAW($gNvLen, @_);
    if($gNvExpVal eq "TOO_SHORT")
    {
      LogPrint("gNvExpVal == TOO_SHORT", 0);
      return 0;
    }
  }
  LogPrint("gNvExpVal: ".$gNvExpVal, 0);
  $gPrevDecodeLocation = "gNvExpVal";
  return 1;
}

#########################################################################################
# Func:
#    GetRealVal
# Description:
#    Get real NV item value
#########################################################################################
sub GetRealVal
{
  if(($gNvResult eq "FAIL") || ($gNvResult eq "ACTIVATED"))
  {
    $gNvRealVal = RAW($gNvLen, @_);
    if($gNvRealVal eq "TOO_SHORT")
    {
      LogPrint("gNvRealVal == TOO_SHORT", 0);
      return 0;
    }
  }
  elsif($gNvResult eq "NOT_ACTIVATED")
  {
    $gNvRealVal = 'NOT_ACTIVATED';
  }
  LogPrint("gNvRealVal: ".$gNvRealVal, 0);
  $gPrevDecodeLocation = "gNvRealVal";
  return 1;
}

#########################################################################################
# Func:
#    DecodeNVCKRspPkt
# Description:
#    Decode NV diagnostic response package
#########################################################################################
sub DecodeNVCKRspPkt
{
  my @rsppkt = (@_);

  if($gPrevDecodeLocation eq "gNvRealVal")
  {
    if(GetNVResult(@_) == 0)
    {
      return 0;
    }
  }
  if($gPrevDecodeLocation eq "gNvResult")
  {
    if(GetNVCategory(@_) == 0)
    {
      return 0;
    }
  }
  if($gPrevDecodeLocation eq "gNvCategory")
  {
    if(GetNVType(@_) == 0)
    {
      return 0;
    }
  }
  if($gPrevDecodeLocation eq "gNvType")
  {
    if(GetNVLen(@_) == 0)
    {
      return 0;
    }
  }
  if($gPrevDecodeLocation eq "gNvLen")
  {
    if(GetNvIdEfsPath(@_) == 0)
    {
      return 0;
    }
  }
  if($gPrevDecodeLocation eq "nv_id_efs_path")
  {
    if(GetExpVal(@_) == 0)
    {
      return 0;
    }
  }
  if($gPrevDecodeLocation eq "gNvExpVal")
  {
    if(GetRealVal(@_) == 0)
    {
      return 0;
    }
  }
  return 1;
}

#########################################################################################
# Func:
#    NVDiagGetInfo
# Description:
#    Get operator information
######################################################################################### 
sub NVDiagGetInfo()
{ 
  my @out;
  my @result;
  
  @out = qx(/usr/local/bin/gestalt_query CarrierBundleInfoArray | grep CFBundleIdentifier);
  if((scalar(@out) > 0) && (index($out[0], "=>") != -1))
  {
    @result = split('=>', $out[0]);
    $gCarrierBundleName = trim($result[1]);
    $gCarrierBundle = $gCarrierBundleName;
    $gCarrierBundle =~ s/com.apple.//g;
    $gCarrierBundle =~ s/"//g;
    LogPrint('CarrierBundleName: '.$gCarrierBundle, 0);
    $gCarrierBundle = '/System/Library/Carrier Bundles/iPhone/'.$gCarrierBundle.'.bundle';
    LogPrint('CarrierBundle: '.$gCarrierBundle, 0);
  }
  else
  {
    $gCarrierBundleName = 'NA';
    $gCarrierBundle = 'NA';
    LogPrint('CarrierBundle: NA', 0);
  }
  
  @out = qx(/usr/local/bin/gestalt_query CarrierBundleInfoArray | grep CFBundleVersion);
  if((scalar(@out) > 0) && (index($out[0], "=>") != -1))
  {
    @result = split('=>', $out[0]);
    $gCarrierBundleVersion = trim($result[1]);
  }
  else
  {
    $gCarrierBundleVersion = 'NA';
  }
  
  @out = qx(/usr/local/bin/gestalt_query MobileSubscriberCountryCode);
  if((scalar(@out) > 0) && (index($out[0], ":") != -1))
  {
    @result = split(':', $out[0]);
    $gMCC = trim($result[1]);
  }
  else
  {
    $gMCC = 'NA';
  }

  @out = qx(/usr/local/bin/gestalt_query MobileSubscriberNetworkCode);
  if((scalar(@out) > 0) && (index($out[0], ":") != -1))
  {
    @result = split(':', $out[0]);
    $gMNC = trim($result[1]);
  }
  else
  {
    $gMNC = 'NA';
  }
  
  @out = qx(/usr/local/bin/gestalt_query BasebandFirmwareVersion);
  if((scalar(@out) > 0) && (index($out[0], ":") != -1))
  {
    @result = split(':', $out[0]);
    $gBBVersion = trim($result[1]);
  }
  else
  {
    $gBBVersion = 'NA';
  }
  
  GetHWBuildInfo();
  
  return;
}

#########################################################################################
# Func:
#    OpenNVDiagReportFile
# Description:
#    Run NV diagnostic in basebabd side
#########################################################################################
sub OpenNVDiagReportFile
{
  my $outFile = $OutFolder."BBDiag-NVDiag.report";
  open($gOutHandler, ">$outFile") || die "Cannot open $outFile!";
}

#########################################################################################
# Func:
#    ExecuteNVCheck
# Description:
#    Run NV diagnostic in basebabd side
#########################################################################################
sub ExecuteNVCheck
{
  LogPrint("*****************************************************************", 0);
  LogPrint("ExecuteNVCheck", 0);
  LogPrint("*****************************************************************", 0);
  
  my $msg;
  my $nv_id_name;
  my $ii=0;

  my $nvItem;
  my $efsItem;
  my %NVItems = ();
  my %EFSItems = ();
  
  my %RFComNVItems = ();
  my %RFComEFSItems = ();
  my %RFComItemDict = (0=>\%RFComNVItems, 1=>\%RFComEFSItems);

  my %RFProdNVItems = ();
  my %RFProdEFSItems = ();
  my %RFProdItemDict = (0=>\%RFProdNVItems, 1=>\%RFProdEFSItems);

  my %RFCalNVItems = ();
  my %RFCalEFSItems = ();
  my %RFCalItemDict = (0=>\%RFCalNVItems, 1=>\%RFCalEFSItems);

  my %SettingNVItems = ();
  my %SettingEFSItems = ();
  my %SettingItemDict = (0=>\%SettingNVItems, 1=>\%SettingEFSItems);

  my %PRINVItems = ();
  my %PRIEFSItems = ();
  my %PRIItemDict = (0=>\%PRINVItems, 1=>\%PRIEFSItems);

  #Always send out STOP command firstly
  my $retryCnt = 5;
  my $cmd = my $out = my $header = my $body = "";
  while ($retryCnt-- > 0)
  {
    $cmd = '/usr/local/bin/ETLTool raw 0x4B 0xFD 0x5F 0x00 0x02';
    $out = ETLRawCmd($cmd, 2);
    $header = trim(substr($out,0,14));
    if($header eq "13 4B FD 5F 00")
    {
      LogPrint("ERR: NVDiag is not supported by this BBFW", 1);
      return 0;
    }
    if(length($out) > 17)
    {
      $header = trim(substr($out,0,17));
      if($header eq "4B FD 5F 00 01 00")
      {
        last;
      }
    }
  }

  if ($retryCnt <= 0)
  {
    LogPrint("ERR: Failed to stop NVDiag", 1);
    return 0;
  }

  #Sync PRI file
  if(!$gIsPhoneActivated)
  {
    LogPrint('Phone is not activated. Can not check PRI info', 0);
  }
  else
  {
    if(SyncPRI(0) == 0)
    {
      LogPrint("Failed to sync PRI", 1);
    }
    if(SyncGRI(0) == 0)
    {
      LogPrint("Failed to sync GRI", 1);
    }    
  }

  #Set NV check profile as ALL
  #'00': RF.
  #'01': SETTING
  #'02': PRI
  #'03': ALL
  my $profileName = '03';
  $retryCnt = 5;
  while($retryCnt-- > 0)
  {
    $cmd = '/usr/local/bin/ETLTool raw 0x4B 0xFD 0x5F 0x00 0x01 0x'.$profileName;
    $out = ETLRawCmd($cmd);
    if(length($out) > 17)
    {
      $header = trim(substr($out,0,17));
      if($header eq "4B FD 5F 00 01 00")
      {
        last;
      }
    }
  }

  if($retryCnt <= 0)
  {
    LogPrint("ERR: Failed to start NVDiag", 1);
    return 0;
  }

  my @nvck_data = ();
  my $total_checked_nv = 0;
  my $get_next_immediately = 0;
  my @rsp = ();
  my $status, my $profile, my $pktlen;
  my $pri_nv_cnt, my $setting_nv_cnt, my $rf_cal_nv_cnt, my $rf_static_common_nv_cnt, my $rf_static_prod_nv_cnt;
  $retryCnt = 5;
  while(1)
  {
    if($get_next_immediately == 0)
    {
      sleep 1;
    }

    $retryCnt = 5;
    while($retryCnt-- > 0)
    {
      $cmd = '/usr/local/bin/ETLTool raw 0x4B 0xFD 0x5F 0x00 0x03';
      $out = ETLRawCmd($cmd);
      if(length($out) > 17)
      {
        $header = trim(substr($out,0,17));
        if($header eq "4B FD 5F 00 01 00")
        {
          last;
        }
      }
    }

    if($retryCnt <= 0)
    {
      LogPrint("ERR: Failed to get NVDiag result", 1);
      return 0;
    }
    $body = trim(substr($out,length($header),length($out)-length($header)));
    LogPrint("Header: ".$header, 0);
    LogPrint("Body: ".$body, 0);
    @rsp = split(' ', $body);

    $status = UBYTE(\@rsp);
    LogPrint("Status: ".$status, 0);

    $profile = UBYTE(\@rsp);
    LogPrint("Profile: ".$profile, 0);

    $pktlen = USHORT(\@rsp);
    LogPrint("Pktlen: ".$pktlen, 0);
    if($pktlen > 0)
    {
      $get_next_immediately = 1;
      LogPrint("get_next_immediately: ".$get_next_immediately, 0);
    }

    if($pktlen > length($body))
    {
      LogPrint((sprintf "pktlen(%d) > length(body)(%d)", $pktlen, length($body)), 1);
      return 0;
    }
    elsif($pktlen < 1024)
    {
      @rsp = @rsp[0 .. $pktlen];
    }

    if($status == 0)
    {
      my $offset = 5 * 2;
      my @tailPkt = @rsp[$#rsp - $offset .. $#rsp];
      @rsp = @rsp[0 .. $#rsp - $offset];
      my $tail = join(" ", @tailPkt);
      LogPrint("tail: ".$tail, 0);
      #Last packet
      $pri_nv_cnt = USHORT(\@tailPkt);
      $setting_nv_cnt = USHORT(\@tailPkt);
      $rf_cal_nv_cnt = USHORT(\@tailPkt);
      $rf_static_common_nv_cnt = USHORT(\@tailPkt);
      $rf_static_prod_nv_cnt = USHORT(\@tailPkt);
      $total_checked_nv = $pri_nv_cnt + $setting_nv_cnt + $rf_cal_nv_cnt + $rf_static_common_nv_cnt + $rf_static_prod_nv_cnt;
      LogPrint("pri_nv_cnt: ".$pri_nv_cnt, 0);
      LogPrint("setting_nv_cnt: ".$setting_nv_cnt, 0);
      LogPrint("rf_cal_nv_cnt: ".$rf_cal_nv_cnt, 0);
      LogPrint("rf_static_common_nv_cnt: ".$rf_static_common_nv_cnt, 0);
      LogPrint("rf_static_prod_nv_cnt: ".$rf_static_prod_nv_cnt, 0);
      LogPrint("total_checked_nv: ".$total_checked_nv, 0);
    }

    @nvck_data = (@nvck_data, @rsp);
    my @nv_diag_result;
    while(scalar(@nvck_data))
    {
      if(DecodeNVCKRspPkt(\@nvck_data) == 0)
      {
        last;
      }
      
      if($gNvType eq "EFS")
      {
        my %tmp = map { $_ => 1 } @gEfsIgnoreList;
        if(!exists $tmp{$gEfsPath})
        {
          if(($gNvCategory eq "RF_CAL") && (!exists $gRFCalNVList{$gEfsPath}))
          {
            next;
          }
          #if($gNvCategory ne "RF_CAL")
          {
             if($gNvRealVal eq 'NOT_ACTIVATED')
             {
               LogPrint((sprintf "  EFS (%s) not activate", $gEfsPath), 0);
               LogPrint("", 0);
               push (@{$EFSItems{$gNvCategory}}, sprintf "- EFS (%s) not activate", $gEfsPath);
             }
             else
             {
                LogPrint((sprintf "  EFS (%s) mismatch", $gEfsPath), 0);
                LogPrint("", 0);
                push (@{$EFSItems{$gNvCategory}}, sprintf "- EFS (%s) mismatch", $gEfsPath);
             }
          }

          if($gNvCategory eq 'RF_COM')
          {
            $RFComEFSItems{$gEfsPath} = sprintf '%10s$%10s$%50s$%60s$%60s', $gNvCategory, 'FAIL', $gEfsPath, $gNvExpVal, $gNvRealVal;
          }
          elsif($gNvCategory eq 'RF_PROD')
          {
            $RFProdEFSItems{$gEfsPath} = sprintf '%10s$%10s$%50s$%60s$%60s', $gNvCategory, 'FAIL', $gEfsPath, $gNvExpVal, $gNvRealVal;
          }
          elsif($gNvCategory eq 'RF_CAL')
          {
            $RFCalEFSItems{$gEfsPath} = sprintf '%10s$%10s$%50s$%60s$%60s', $gNvCategory, 'FAIL', $gEfsPath, "ANY", $gNvRealVal;
          }
          elsif($gNvCategory eq 'SETTING')
          {
            $SettingEFSItems{$gEfsPath} = sprintf '%10s$%10s$%50s$%60s$%60s', "Setting", 'FAIL', $gEfsPath, $gNvExpVal, $gNvRealVal;
          }
          elsif($gNvCategory eq 'PRI')
          {
            $PRIEFSItems{$gEfsPath} = sprintf '%10s$%10s$%50s$%60s$%60s', 'PRI', 'FAIL', $gEfsPath, $gNvExpVal, $gNvRealVal;
          }
          else
          {
            LogPrint((sprintf 'gNvCategory(%d) is invalid', $gNvCategory), 1);
          }
        }
      }#END of if($gNvType eq "EFS")
      elsif($gNvType eq "NV")
      {
        my %tmp = map { $_ => 1 } @gNVIgnoreList;
        if(!exists $tmp{$gNvId})
        {
          if(($gNvCategory eq 'RF_CAL') && (!exists $gRFCalNVList{$gNvId}))
          {
            next;
          }
          #if($gNvCategory ne "RF_CAL")
          {
            if($gNvRealVal eq 'NOT_ACTIVATED')
            {
              LogPrint((sprintf '  NV (%s) not activate', $gNvId), 0);
              LogPrint("", 0);
              push (@{$NVItems{$gNvCategory}}, sprintf '- NV (%s) not activate', $gNvId);
            }
            else
            {
              LogPrint((sprintf '  NV (%s) mismatch', $gNvId), 0);
              LogPrint("", 0);
              push (@{$NVItems{$gNvCategory}}, sprintf '- NV (%s) mismatch', $gNvId);
            }
          }

          if(exists $gNVIdNamePair{$gNvId})
          {
            $nv_id_name = "".$gNvId."###(".$gNVIdNamePair{$gNvId}.")";
          }
          else
          {
            $nv_id_name = "".$gNvId;
          }
          LogPrint((sprintf "NV ID(%s) => Name(%s)", $gNvId, $nv_id_name), 0);

          if($gNvCategory eq 'RF_COM')
          {
            $RFComNVItems{$gNvId} = sprintf '%10s$%10s$%50s$%60s$%60s', $gNvCategory, 'FAIL', $nv_id_name, $gNvExpVal, $gNvRealVal;
          }
          elsif($gNvCategory eq 'RF_PROD')
          {
            $RFProdNVItems{$gNvId} = sprintf '%10s$%10s$%50s$%60s$%60s', $gNvCategory, 'FAIL', $nv_id_name, $gNvExpVal, $gNvRealVal;
          }
          elsif($gNvCategory eq 'RF_CAL')
          {
            $RFCalNVItems{$gNvId} = sprintf '%10s$%10s$%50s$%60s$%60s', $gNvCategory, 'FAIL', $nv_id_name, "ANY", $gNvRealVal;
          }
          elsif($gNvCategory eq 'SETTING')
          {
            $SettingNVItems{$gNvId} = sprintf '%10s$%10s$%50s$%60s$%60s', "Setting", 'FAIL', $nv_id_name, $gNvExpVal, $gNvRealVal;
          }
          elsif($gNvCategory eq 'PRI')
          {
            $PRINVItems{$gNvId} = sprintf '%10s$%10s$%50s$%60s$%60s', 'PRI', 'FAIL', $nv_id_name, $gNvExpVal, $gNvRealVal;
          }
          else
          {
            LogPrint((sprintf 'gNvCategory(%d) is invalid', $gNvCategory), 1);
          }
        }
      } #END of $gNvType eq "NV"
    }#END of while(length(@nvck_data))

    if( $status == 0)
      {
        #NVDiag finished
        last;
      }
  }

    my $pri_failed_nv = (keys %PRINVItems) + (keys %PRIEFSItems);
  if(0)
  {
    # Remove PRI in Mav10
    WriteToReport("", 1);
    WriteToReport((sprintf '%s', 'PRI:', $pri_nv_cnt), 1);
    WriteToReport((sprintf '------------------------------------------'), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total Checked NV Items', $pri_nv_cnt), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total  Failed NV Items', $pri_failed_nv), 1);
    WriteToReport((''), 1);
    foreach $nvItem (@{$NVItems{'PRI'}})
    {
      LogPrint((sprintf '%s', $nvItem), 1);
    }
    foreach $efsItem (@{$EFSItems{'PRI'}})
    {
      LogPrint((sprintf '%s', $efsItem), 1);
    }
    LogPrint("", 1);
    
    if(((keys %PRINVItems) > 0) || ((keys %PRIEFSItems) > 0))
    {
      WriteToReport((sprintf '@%10s@%10s@%50s@%60s@%60s', 'TYPE', 'RESULT', 'NV/EFS', 'EXPECT_VAL', 'REAL_VAL'), 0);
      foreach $ii (sort {$a <=> $b} keys %PRINVItems)
      {
        WriteToReport($PRINVItems{$ii}, 0);
      }
      foreach $ii (sort keys %PRIEFSItems)
      {
        WriteToReport($PRIEFSItems{$ii}, 0);
      }
    }
  }
  
    my $setting_failed_nv = (keys %SettingNVItems) + (keys %SettingEFSItems);
    WriteToReport("", 1);
    WriteToReport((sprintf '%s', 'Shipping / Factory Setting:'), 1);
    WriteToReport((sprintf '------------------------------------------'), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total Checked NV Items', $setting_nv_cnt), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total  Failed NV Items', $setting_failed_nv), 1);
    WriteToReport((''), 1);
    
    foreach $nvItem (@{$NVItems{'SETTING'}})
    {
      LogPrint((sprintf '%s', $nvItem), 1);
    }
    foreach $efsItem (@{$EFSItems{'SETTING'}})
    {
      LogPrint((sprintf '%s', $efsItem), 1);
    }
    LogPrint("", 1);
    
    if(((keys %SettingNVItems) > 0) || ((keys %SettingEFSItems) > 0))
    {
      WriteToReport((sprintf '@%10s@%10s@%50s@%60s@%60s', 'TYPE', 'RESULT', 'NV/EFS', 'EXPECT_VAL', 'REAL_VAL'), 0);
      foreach $ii (sort {$a <=> $b} keys %SettingNVItems)
      {
        WriteToReport($SettingNVItems{$ii}, 0);
      }
      foreach $ii (sort keys %SettingEFSItems)
      {
        WriteToReport($SettingEFSItems{$ii}, 0);
      }
    }

    my $rf_static_prod_failed_nv = (keys %RFProdNVItems) + (keys %RFProdEFSItems);
    WriteToReport("", 1);
    WriteToReport((sprintf '%s', 'RF_PROD:'), 1);
    WriteToReport((sprintf '------------------------------------------'), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total Checked NV Items', $rf_static_prod_nv_cnt), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total  Failed NV Items', $rf_static_prod_failed_nv), 1);
    WriteToReport((''), 1);

    foreach $nvItem (@{$NVItems{'RF_PROD'}})
    {
      LogPrint((sprintf '%s', $nvItem), 1);
    }
    foreach $efsItem (@{$EFSItems{'RF_PROD'}})
    {
      LogPrint((sprintf '%s', $efsItem), 1);
    }
    LogPrint("", 1);
        
    if(((keys %RFProdNVItems) > 0) || ((keys %RFProdEFSItems) > 0))
    {
      WriteToReport((sprintf '@%10s@%10s@%50s@%60s@%60s', 'TYPE', 'RESULT', 'NV/EFS', 'EXPECT_VAL', 'REAL_VAL'), 0);
      foreach $ii (sort {$a <=> $b} keys %RFProdNVItems)
      {
        WriteToReport($RFProdNVItems{$ii}, 0);
      }
      foreach $ii (sort keys %RFProdEFSItems)
      {
        WriteToReport($RFProdEFSItems{$ii}, 0);
      }
    }
    
    my $rf_static_common_failed_nv = (keys %RFComNVItems) + (keys %RFComEFSItems);
    WriteToReport("", 1);
    WriteToReport((sprintf '%s', 'RF_COMMON:'), 1);
    WriteToReport((sprintf '------------------------------------------'), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total Checked NV Items', $rf_static_common_nv_cnt), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total  Failed NV Items', $rf_static_common_failed_nv), 1);
    WriteToReport((''), 1);
    
    foreach $nvItem (@{$NVItems{'RF_COM'}})
    {
      LogPrint((sprintf '%s', $nvItem), 1);
    }
    foreach $efsItem (@{$EFSItems{'RF_COM'}})
    {
      LogPrint((sprintf '%s', $efsItem), 1);
    }
    LogPrint("", 1);
    
    if(((keys %RFComNVItems) > 0) || ((keys %RFComEFSItems) > 0))
    {
      WriteToReport((sprintf '@%10s@%10s@%50s@%60s@%60s', 'TYPE', 'RESULT', 'NV/EFS', 'EXPECT_VAL', 'REAL_VAL'), 0);
      foreach $ii (sort {$a <=> $b} keys %RFComNVItems)
      {
        WriteToReport($RFComNVItems{$ii}, 0);
      }
      foreach $ii (sort keys %RFComEFSItems)
      {
        WriteToReport($RFComEFSItems{$ii}, 0);
      }
    }

    my $rf_cal_failed_nv = (keys %RFCalNVItems) + (keys %RFCalEFSItems);
    WriteToReport("", 1);
    WriteToReport((sprintf '%s', 'RF_CAL:'), 1);
    WriteToReport((sprintf '------------------------------------------'), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total Checked NV Items', $rf_cal_nv_cnt), 1);
    WriteToReport((sprintf '%-20s - %d', 'Total  Failed NV Items', $rf_cal_failed_nv), 1);
    WriteToReport((''), 1);
    foreach $nvItem (@{$NVItems{'RF_CAL'}})
    {
      LogPrint((sprintf '%s', $nvItem), 1);
    }
    foreach $efsItem (@{$EFSItems{'RF_CAL'}})
    {
      LogPrint((sprintf '%s', $efsItem), 1);
    }
    LogPrint("", 1);
        
    if(((keys %RFCalNVItems) > 0) || ((keys %RFCalEFSItems) > 0))
    {
      WriteToReport((sprintf '@%10s@%10s@%50s@%60s@%60s', 'TYPE', 'RESULT', 'NV/EFS', 'EXPECT_VAL', 'REAL_VAL'), 0);
      foreach $ii (sort {$a <=> $b} keys %RFCalNVItems)
      {
        WriteToReport($RFCalNVItems{$ii}, 0);
      }
      foreach $ii (sort keys %RFCalEFSItems)
      {
        WriteToReport($RFCalEFSItems{$ii}, 0);
      }
    }

    my $total_failed_nv = $rf_static_common_failed_nv + $rf_static_prod_failed_nv + $rf_cal_failed_nv + $setting_failed_nv + $pri_failed_nv;
    WriteToReport("", 1);
    WriteToReport("SUMMARY:", 1);
    WriteToReport("--------------------------------------------------", 1);
    WriteToReport((sprintf "  Total Checked NV Items - %d", $total_checked_nv), 1);
    WriteToReport((sprintf "   Total Failed NV Items - %d", $total_failed_nv), 1);
    WriteToReport((sprintf "--------------------------------------------------"), 1);
    
    if($total_failed_nv > 0)
    {
      LogPrint("", 1);
      LogPrint("Please file radar \"Baseband NV Diagnostics report\" to \"Maverick SW | 10\" component, and assign to Yu Sun.\nPlease rsync all files under \"/var/mobile/Library/Logs/BBDiagnostics/\" and attach to radar.", 1);
    }
    return 1;
}

#########################################################################################
# Func:
#    GenNVIdNameDict
# Description:
#    Parse NVIdNamePair and construct gNVIdNamePair
#########################################################################################
sub GenNVIdNameDict
{
  my $NvIdNamePairFile = '/usr/local/share/misc/NVIdNamePair';
  my $NvIdNamePairFileHandler;
  open($NvIdNamePairFileHandler, "<$NvIdNamePairFile") || die "Cannot open $NvIdNamePairFile!";

  my @lines = <$NvIdNamePairFileHandler>;

  foreach my $line (@lines)
  {
    $line = trim($line);
    if(substr($line,0,1) eq '#')
    {
      next;
    }
    my @tmp = $line =~ /(.*):(.*)/;
    if(@tmp > 0)
    {
      my $nvId = trim($tmp[0]);
      my $nvName = trim($tmp[1]);
      if(!exists $gNVIdNamePair{$nvId})
      {
        $gNVIdNamePair{$nvId} = $nvName;
        #LogPrint((sprintf "Add NV ID(%s) Name(%s) pair to gNVIdNamePair", $nvId, $nvName), 0);
      }
      else
      {
        LogPrint((sprintf "ERR: Ambiguity name (%s) Vs (%s) for NV(%s)", $gNVIdNamePair{$nvId}, $nvName, $nvId), 1);
      }
    }
  }
  return 1;
}

#########################################################################################
# Func:
#    GetRFCalNvList
# Description:
#    Read zRFCalNVall.txt which contains calibration NV for each band into gRFCalNVList
#########################################################################################
sub GetRFCalNvList
{
  LogPrint("GetRFCalNvList", 0);
  my $RfCalNvListFile = '/usr/local/share/misc/zRFCalNVall.txt';
  my $RfCalNvListFileHandler;
  open($RfCalNvListFileHandler, "<$RfCalNvListFile") || die "Cannot open $RfCalNvListFile!";
  local $/ = undef;
  my $lines = <$RfCalNvListFileHandler>;
  my @lines = split('\n', $lines);
  my $proj;
  my $rat;
  my $band;
  my $bandName;
  my $rfNvId;
  my $validRfCalNV = 0;
  my $curArrayRef;
  my @caledBand = BBGetBandAndCalStatus(1);
  my $tmp;
  my @tmp;
  my %tmp;

  LogPrint("Caled Band:".join(' ', @caledBand), 0);

  foreach my $line (@lines)
  {
    $line = trim($line);
    if(substr($line,0,1) eq '#')
    {
        next;
    }

    @tmp = $line =~ /\[(.*)_(.*)_(.*)\]/;
    if(@tmp > 0)
    {
      $proj = trim($tmp[0]);
      $rat = trim($tmp[1]);
      $band = trim($tmp[2]);
      LogPrint((sprintf "proj : %s, rat : %s, band : %s", $proj, $rat, $band), 0);
      $tmp = $gProdList{$proj};
      %tmp = map { $_ => 1 } @$tmp;
      if(!exists($tmp{$gProdName}))
      {
        $validRfCalNV = 0;
        next;
      }
      $bandName = $rat.'_'.$band;
      %tmp = map { $_ => 1 } @caledBand;
      if(!exists($tmp{$bandName}))
      {
        $validRfCalNV = 0;
        next;
      }
      $validRfCalNV = 1;
      next;
    }

    if($validRfCalNV == 1)
    {
      $rfNvId = trim($line);
      $gRFCalNVList{$rfNvId} = 1;
      LogPrint((sprintf "Add %s_%s_%s %s to RFCalNvList", $proj, $rat, $band, $rfNvId), 0);
    }
  }
  return 1;
}

#########################################################################################
# Func:
#    NVDiag
# Description:
#    Run NV diagnostic in basebans side.
#    Show result in STDOUT and save to BBDiag=NVDiag.report
#    Save html result into BBDiag-NVDiag.html
#########################################################################################
sub NVDiag
{
    my $logFile = $OutFolder."BBDiag-NVDiag.log";
    my $outFile = $OutFolder."BBDiag-NVDiag.report";
    my $txtReportFile = $OutFolder."BBDiag-NVDiag.txt";
    my $htmlReportFile = $OutFolder."BBDiag-NVDiag.html";
    open($gLogHandler, ">$logFile") || die "Cannot open $logFile!";
    open($gTxtReportHandler, ">$txtReportFile") || die "Cannot open $txtReportFile!";

    open($gOutHandler, ">$outFile") || die "Cannot open $outFile!";
    #print $gOutHandler "NV diagnotic is running. This will take about 10 seconds to finish";
    #close($gOutHandler);
    
    
    if(HasBB() == 0)
    {
      LogPrint("Baseband is not existed", 1);
    }
    else
    {
      LogPrint("\n*****************************************************************\nNVDiag Info ...\n*****************************************************************\n", 1);
    
      NVDiagGetInfo();
      
      WriteToReport((sprintf "%-10s\t: %s\n", 'HW', $gHWConfig.' ('.$gHWVersion.')'), 1);
      WriteToReport((sprintf "%-10s\t: %s\n", 'BBVer', $gBBVersion), 1);
      WriteToReport((sprintf "%-10s\t: %s\n", 'MCC', $gMCC), 1);
      WriteToReport((sprintf "%-10s\t: %s\n", 'MNC', $gMNC), 1);
      WriteToReport((sprintf "%-10s\t: %s\n", 'CBName', $gCarrierBundleName), 1);
      WriteToReport((sprintf "%-10s\t: %s\n", 'CBVer', $gCarrierBundleVersion), 1);
      WriteToReport((''), 1);
      
      GetProdName();

      if(GenNVIdNameDict() == 0)
      {
        return 0;
      }

      if(GetRFCalNvList() == 0)
      {
        return 0;
      }

      if(ExecuteNVCheck() == 0)
      {
        return 0;
      }

      if(Plain2Html($txtReportFile, $htmlReportFile) == 0)
      {
        return 0;
      }

      my $End = time();
      my $diff = $End - $gStartTime;
      LogPrint("", 1);
      LogPrint((sprintf 'Time consuming: %02d:%02d:%02d', $diff/3600, $diff%3600/60, $diff%60), 1);      
    }
    close ($gLogHandler);
    close ($gOutHandler);
    close ($gTxtReportHandler);
    return 1;
}

#########################################################################################
# Func:
#    GetBBInfo
# Description:
#    Show baseband basic information to STDOUT and save result to BBDiag-BBInfo.report
#########################################################################################
sub GetBBInfo
{
    my $logFile = $OutFolder."BBDiag-BBInfo.log";
    my $outFile = $OutFolder."BBDiag-BBInfo.report";
    open($gLogHandler, ">$logFile") || die "Cannot open $logFile!";
    open($gOutHandler, ">$outFile") || die "Cannot open $outFile!";
    if(HasBB() == 0)
    {
      LogPrint("Baseband is not existed", 1);
    }
    else
    {
      CheckFactoryDebugOption();
      GetProdName();
      GetPhoneInfo();
      GetBasebandInfo();
      GetBBCMInfo();
    }
    close ($gLogHandler);
    close ($gOutHandler);
    return 1;
}

#########################################################################################
# Func:
#    BBDiag
#########################################################################################
sub BBDiag
{
  GetBBInfo();
  return NVDiag();
}

#########################################################################################
# Func:
#    UBYTE
# Description:
#    Extrace 1 byte from array and convert to unsigned byte formate
#########################################################################################
sub Usage()
{
   printf("Usage : BBDiagnostics.pl <BBInfo | NVDiag>\n");
   print ("Option: \n");
   print ("    <BBInfo>: Show Baseband info\n");
   print ("    <NVDiag>: Run NVDiag\n");
   print ("If no option specified, will run both BBInfo and NVDiag\n");
   exit(0);
}

####################################################################
# Main #
####################################################################
  my $exitCode = 1;

  if(!-d $OutFolder)
  {
    mkdir $OutFolder
  }
  
  my $testItem;
  $gFullLog = 0;
  
  #Full log option
  if(($#ARGV + 1) == 2)
  {
    $testItem = $ARGV[0];
    if($ARGV[1] eq "FULLLOG")
    {
      $gFullLog = 1;
    }
  }
  elsif (($#ARGV + 1) == 1)
  {
    $testItem = $ARGV[0];
    if($ARGV[0] eq "FULLLOG")
    {
      $gFullLog = 1;
      $testItem = "ALL";
    }
  }
  elsif(($#ARGV + 1) == 0)
  {
    $testItem = "ALL";
  }
  else
  {
    Usage();
  }

  if(($testItem ne "BBInfo") && ($testItem ne "NVDiag") && ($testItem ne "ALL"))
  {
    Usage()
  }
  
  $gStartTime = time();
  print "Collecting data, please wait ...\n\n";
  sleep(1);
  
  GetDiagTraceStatus();
  if($gDiagTraceOn == 1)
  {
    ConfigDiagTrace(0);
  }
  
  if($testItem eq "BBInfo")
  {
    $exitCode = GetBBInfo();
  }
  elsif($testItem eq "NVDiag")
  {
    $exitCode = NVDiag();
  }
  elsif($testItem eq "ALL")
  {
    $exitCode = BBDiag();
  }
  
  if($gDiagTraceOn == 1)
  {
    ConfigDiagTrace(1);
  }
  
  exit(0);

