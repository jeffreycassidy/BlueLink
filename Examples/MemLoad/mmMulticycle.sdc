# Multicycle path for MMIO-based block RAM reads from port B only
set_multicycle_path -from "*dut_br_*q_b*" -to "*dut_mmReadbackReg*" -start -setup 5
set_multicycle_path -from "*dut_br_*q_b*" -to "*dut_mmReadbackReg*" -hold 9 -end

# Path from mmMemRead via mux and barrel shift (mmMemRead static throughout)
set_multicycle_path -from "*mmMemRead|D_OUT*" -to "*dut_mmReadbackReg*" -start -setup 9
set_multicycle_path -from "*mmMemRead|D_OUT*" -to "*dut_mmReadbackReg*" -hold 9 -end
