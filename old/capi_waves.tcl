# Provides a series of commands to add waveforms for the CAPI interface

proc wave_capi { path } {
    wave_capi_control   $path
    wave_capi_status    $path
    wave_capi_mmio      $path
	wave_capi_command	$path
    wave_capi_buffer    $path
}

proc wave_capi_control { path } {
	add wave -group Control -noupdate                       ${path}ha_jval
	add wave -group Control -noupdate -radix hexadecimal    ${path}ha_jcom
    add wave -group Control -noupdate                       ${path}ha_jcompar
	add wave -group Control -noupdate -radix hexadecimal    ${path}ha_jea
    add wave -group Control -noupdate                       ${path}ha_jeapar 
}

proc wave_capi_status { path } { 
	add wave -group Status -noupdate                        ${path}ah_jrunning
	add wave -group Status -noupdate                        ${path}ah_jdone
	add wave -group Status -noupdate                        ${path}ah_jcack
	add wave -group Status -noupdate                        ${path}ah_tbreq
	add wave -group Status -noupdate                        ${path}ah_paren
	add wave -group Status -noupdate                        ${path}ah_jyield
	add wave -group Status -noupdate -radix hexadecimal     ${path}ah_jerror
}

proc wave_capi_command { path } {
    wave_capi_command_request $path
    wave_capi_command_response $path
}

proc wave_capi_command_response { path } {
    add wave -group Command -group Response                     ${path}ha_rvalid
    add wave -group Command -group Response -radix hexadecimal  ${path}ha_rtag
    add wave -group Command -group Response                     ${path}ha_rtagpar
    add wave -group Command -group Response -radix hexadecimal  ${path}ha_response
    add wave -group Command -group Response -radix signed       ${path}ha_rcredits
    add wave -group Command -group Response -radix hexadecimal  ${path}ha_rcachestate
    add wave -group Command -group Response -radix hexadecimal  ${path}ha_rcachepos
}

proc wave_capi_command_request { path } {
    add wave -group Command -group Request                      ${path}ah_cvalid
    add wave -group Command -group Request -radix hexadecimal   ${path}ah_com
    add wave -group Command -group Request                      ${path}ah_compar
    add wave -group Command -group Request -radix hexadecimal   ${path}ah_ctag
    add wave -group Command -group Request                      ${path}ah_ctagpar
    add wave -group Command -group Request -radix hexadecimal   ${path}ah_cabt
    add wave -group Command -group Request -radix hexadecimal   ${path}ah_csize
    add wave -group Command -group Request -radix hexadecimal   ${path}ah_cea
    add wave -group Command -group Request                      ${path}ah_ceapar
    add wave -group Command -group Request -radix hexadecimal   ${path}ah_cch
}

proc wave_capi_mmio { path } {
    wave_capi_mmio_request $path
    wave_capi_mmio_response $path
}

proc wave_capi_mmio_request { path } {
	add wave -group MMIO -group Request -noupdate                       ${path}ha_mmval
	add wave -group MMIO -group Request -noupdate                       ${path}ha_mmcfg
	add wave -group MMIO -group Request -noupdate                       ${path}ha_mmrnw
	add wave -group MMIO -group Request -noupdate -radix hexadecimal    ${path}ha_mmdata
	add wave -group MMIO -group Request -noupdate -radix hexadecimal    ${path}ha_mmad
}

proc wave_capi_mmio_response { path } {
	add wave -group MMIO -group Response -noupdate                      ${path}ah_mmack
	add wave -group MMIO -group Response -noupdate -radix hexadecimal   ${path}ah_mmdata
	add wave -group MMIO -group Response -noupdate                      ${path}ah_mmdatapar
}

proc wave_capi_buffer { path } { 
    wave_capi_buffer_read $path
    wave_capi_buffer_write $path
}

proc wave_capi_buffer_read { path } {
    wave_capi_buffer_read_request $path
    wave_capi_buffer_read_response $path
    wave_capi_buffer_write $path
}

proc wave_capi_buffer_read_request { path } {
    add wave -group Buffer -group Read -group Request -noupdate                     ${path}ha_brvalid
    add wave -group Buffer -group Read -group Request -noupdate -radix unsigned     ${path}ha_brtag
    add wave -group Buffer -group Read -group Request -noupdate                     ${path}ha_brtagpar
    add wave -group Buffer -group Read -group Request -noupdate -radix unsigned     ${path}ha_brad
}

proc wave_capi_buffer_read_response { path } {
    global brlatcycles
    add wave -group Buffer -group Read -group Response -noupdate                    ${path}brvalid_delay
    add wave -group Buffer -group Read -group Response -noupdate -radix hexadecimal ${path}brtag_delay
    add wave -group Buffer -group Read -group Response -noupdate -radix hexadecimal ${path}ah_brdata
    add wave -group Buffer -group Read -group Response -noupdate -radix hexadecimal ${path}ah_brpar

    add wave -group Buffer -group Read -group Response -noupdate -radix unsigned    ${path}ah_brlat

    add wave -group Buffer -group Read -group Response -noupdate -radix hexadecimal ${path}ah_brpar
}

proc wave_capi_buffer_write { path } {
    add wave -group Buffer -group Write -noupdate                       ${path}ha_bwvalid
    add wave -group Buffer -group Write -noupdate -radix unsigned       ${path}ha_bwtag
    add wave -group Buffer -group Write -noupdate                       ${path}ha_bwtagpar
    add wave -group Buffer -group Write -noupdate -radix hexadecimal    ${path}ha_bwad
    add wave -group Buffer -group Write -noupdate -radix hexadecimal    ${path}ha_bwdata
    add wave -group Buffer -group Write -noupdate -radix hexadecimal    ${path}ha_bwpar
}


