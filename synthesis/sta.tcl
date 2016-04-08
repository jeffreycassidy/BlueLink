load_package flow
load_package sta
load_package report

cd synth

project_open synth

execute_module -tool sta -args "--multicorner=on"

# Speed grades -1, -2, -3, (-1 fastest)
# Grades X_HY specify core (X) and transceiver (Y) grade
set SPEEDGRADE 2_H2

set rptfn synth_timing.xml

if { [timing_netlist_exist] } { delete_timing_netlist }

load_report
file delete -force $rptfn
puts [write_xml_report $rptfn]
unload_report

create_timing_netlist -speed $SPEEDGRADE -model slow
read_sdc clk250m.sdc
update_timing_netlist

report_timing -npaths 100 -to_clock ha_pclock -setup -file paths.html

puts "Report clocks"
report_clocks

puts "Report clock fmax"
report_clock_fmax_summary 
