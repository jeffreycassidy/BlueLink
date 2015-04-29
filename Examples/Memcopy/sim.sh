#export CAPI_AFU_DRIVER=/home/parallels/src/CAPI/pslse/pslse/afu_driver/src/afu_driver.sl
if [ -z "$CAPI_AFU_DRIVER" ]; then echo "You may need to set CAPI_AFU_DRIVER"; fi

/usr/local/Altera/14.1/modelsim_ase/bin/vsim -do "source memcopy_vsim.tcl; com; sim; run 5us" -c | tee sim_out.txt 2> sim_err.txt&
sleep 5
./host_memcopy | tee host_out.txt 2> host_err.txt
