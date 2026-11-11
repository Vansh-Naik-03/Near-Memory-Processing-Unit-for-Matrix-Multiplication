# =============================================================================
# ModelSim / QuestaSim Simulation Script for NMPU Project
# =============================================================================

# Create and map work library
vlib work
vmap work work

# Compile RTL source files
vlog -work work ../rtl/pe.v
vlog -work work ../rtl/accumulator_tree.v
vlog -work work ../rtl/pe_array.v
vlog -work work ../rtl/sram_bank.v
vlog -work work ../rtl/fsm_controller.v
vlog -work work ../rtl/nmpu_top.v

# Compile Testbenches
vlog -work work ../tb/tb_pe.v
vlog -work work ../tb/tb_accumulator_tree.v
vlog -work work ../tb/tb_pe_array.v
vlog -work work ../tb/tb_sram_bank.v
vlog -work work ../tb/tb_fsm_controller.v
vlog -work work ../tb/tb_nmpu_top.v

# Run Full-System Simulation
vsim -t 1ps -lib work tb_nmpu_top

# Add Waves for Debugging
add wave -divider "Control & Clocks"
add wave -color cyan /tb_nmpu_top/clk
add wave -color red  /tb_nmpu_top/rst_n
add wave -color yellow /tb_nmpu_top/start
add wave -color green  /tb_nmpu_top/done
add wave -color orange /tb_nmpu_top/busy

add wave -divider "FSM State & Counters"
add wave -color magenta /tb_nmpu_top/dut/u_fsm/state
add wave -radix decimal /tb_nmpu_top/dut/u_fsm/i_cnt
add wave -radix decimal /tb_nmpu_top/dut/u_fsm/j_cnt
add wave -radix decimal /tb_nmpu_top/dut/u_fsm/k_cnt

add wave -divider "Near-Memory SRAMs"
add wave -radix decimal /tb_nmpu_top/dut/sram_a_dout
add wave -radix decimal /tb_nmpu_top/dut/sram_b_dout
add wave -radix decimal /tb_nmpu_top/dut/sram_c_dout
add wave -color yellow /tb_nmpu_top/dut/fsm_sram_c_we

add wave -divider "PE Accumulator Core"
add wave -color cyan /tb_nmpu_top/dut/pe_clear
add wave -color green /tb_nmpu_top/dut/pe_enable
add wave -radix decimal /tb_nmpu_top/dut/pe_acc_out

# Run to completion
run -all
