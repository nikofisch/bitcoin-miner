catch {quit -sim}

if {![file exists work]} {
    vlib work
}
vmap work work

# Compile this test and its design modules.
vlog -sv sha256_core.v uart.v nonce_counter.v top_miner.v tb_top_miner.v
vsim -voptargs=+acc work.tb_top_miner
onfinish stop

# Signals to display in the Wave window.
add wave sim:/tb_top_miner/clk
add wave -radix unsigned sim:/tb_top_miner/dut/state
add wave -radix hexadecimal sim:/tb_top_miner/dut/nonce
add wave sim:/tb_top_miner/dut/hit
add wave sim:/tb_top_miner/LEDR
add wave sim:/tb_top_miner/UART_TX
add wave -radix hexadecimal sim:/tb_top_miner/dut/shown

run -all
wave zoom full
