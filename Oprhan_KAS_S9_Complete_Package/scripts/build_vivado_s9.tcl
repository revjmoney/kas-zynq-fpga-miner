# build_vivado_s9.tcl - Automated Vivado 2023.2+ Project & Block Design Builder for S9 (XC7Z010)
# Run: vivado -mode batch -source scripts/build_vivado_s9.tcl

set proj_name "oprhan_kas_s9"
set proj_dir  "./vivado_proj"
set part_name "xc7z010clg400-1"

create_project $proj_name $proj_dir -part $part_name -force

# Add RTL and Constraints
add_files [glob ./rtl/*.v]
add_files -fileset constrs_1 ./constraints/oprhan_kas_parallel.xdc
update_compile_order -fileset sources_1

# Create Zynq Block Design
create_bd_design "system"
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} [get_bd_cells ps7]

# Configure Zynq PS: Enable M_AXI_GP0, S_AXI_HP0 (64-bit), IRQ_F2P, and 100 MHz FCLK_CLK0
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] [get_bd_cells ps7]

# Add RTL Top Module
create_bd_cell -type module -reference kas_top_parallel kas_core_0

# Automate AXI Connections
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/ps7/FCLK_CLK0 (100 MHz)} \
    Clk_slave {/ps7/FCLK_CLK0 (100 MHz)} \
    Clk_xbar {Auto} \
    Master {/ps7/M_AXI_GP0} \
    Slave {/kas_core_0/s_axi} \
    ddr_seg {Auto} \
    intc_ip {New AXI Interconnect} \
    master_apm {0} \
} [get_bd_intf_pins kas_core_0/s_axi]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/ps7/FCLK_CLK0 (100 MHz)} \
    Clk_slave {/ps7/FCLK_CLK0 (100 MHz)} \
    Clk_xbar {Auto} \
    Master {/kas_core_0/m_axi_hp0} \
    Slave {/ps7/S_AXI_HP0} \
    ddr_seg {Auto} \
    intc_ip {New AXI Interconnect} \
    master_apm {0} \
} [get_bd_intf_pins ps7/S_AXI_HP0]

# Set exact 0x43C00000 base address & connect IRQ_F2P
set_property offset 0x43C00000 [get_bd_addr_segs {ps7/Data/SEG_kas_core_0_reg0}]
set_property range 4K [get_bd_addr_segs {ps7/Data/SEG_kas_core_0_reg0}]
connect_bd_net [get_bd_pins kas_core_0/irq] [get_bd_pins ps7/IRQ_F2P]

validate_bd_design
save_bd_design

make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/system/hdl/system_wrapper.v
set_property top system_wrapper [current_fileset]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

write_cfgmem -format bin -interface smapx32 -disablebitswap -loadbit "up 0x0 $proj_dir/$proj_name.runs/impl_1/system_wrapper.bit" -file "./oprhan_kas_4core.bin" -force
puts "DONE! Generated ./oprhan_kas_4core.bin"
