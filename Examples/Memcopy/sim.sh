export CAPI_AFU_DRIVER=/home/parallels/src/CAPI/pslse/pslse/afu_driver/src/afu_driver.sl
/usr/local/Altera/14.1/modelsim_ase/bin/vsim -do "source memcopy_vsim.tcl; com; sim; run -all"&
sleep 5
./host_memcopy | tee output.txt
