load_package flow
#load_package timing
#load_package advanced_timing

set PART 5SGXMA7H2F35C2 

set BLUESPECVLIB /usr/local/Bluespec/lib/Verilog

set PROJPATH [pwd]

cd synth

project_new -family "Stratix V" -part $PART synth -overwrite

set_global_assignment -name top_level_entity mkSyn_AFUToHost

# Bluespec sources

#foreach srcfile { FIFO10.v FIFO2.v MakeReset.v FIFO1.v } {
#    puts "**** Synthesizing $srcfile"
#    execute_module -tool map -args "--analysis_and_elaboratio --effort=auto --optimize=speed --part=$PART --source=$BLUESPECVLIB/$srcfile"
#    execute_module -tool map -args "--analyze_file=$BLUESPECVLIB/$srcfile"
#}


# Local library sources

##foreach srcfile { PSLVerilog/mkPOR.v MLAB_0l.v } { 
##    puts "**** Synthesizing $srcfile"
##    execute_module -tool map -args "--analyze_file=$srcfile"
##}

foreach srcfile { FIFO10.v FIFO2.v MakeReset0.v FIFO1.v } {
    set_global_assignment -name VERILOG_FILE $BLUESPECVLIB/$srcfile
}

foreach srcfile { mkPOR.v } {
    set_global_assignment -name VERILOG_FILE $PROJPATH/PSLVerilog/$srcfile
}

foreach srcfile { MLAB_0l.v mkSyn_AFUToHost.v } {
    set_global_assignment -name VERILOG_FILE $PROJPATH/$srcfile
}

set_global_assignment -name SDC_FILE $PROJPATH/clk250m.sdc


foreach srcfile { mkSyn_AFUToHost.v } {
    execute_module -tool map -args "--analysis_and_elaboration --effort=auto --optimize=speed --part=$PART"
# --verilog_macro="foo=bar"

    # Set all pins to be virtual
    set pins [get_names -filter * -node_type pin]

    foreach_in_collection pin $pins {
        set pin_name [get_name_info -info base_name $pin]
        if { $pin_name == "ha_pclock" } { post_message "Clock pin is $pin_name" } else {
            set pin_path [get_name_info -info full_path $pin]
            post_message "Making VIRTUAL_PIN assignment to $pin_path"
            set_instance_assignment -to $pin_path -name VIRTUAL_PIN ON
        }
    }


    # Map & fit

    execute_module -tool map -args "--effort=auto --optimize=speed --part=$PART"

    execute_module -tool fit

    execute_module -tool sta
}
