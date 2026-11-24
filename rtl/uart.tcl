catch {quit -sim}

if {![file exists work]} {
    vlib work
}
vmap work work

# Compile this test and its design modules.
vlog -sv uart.v tb_uart.v
vsim -voptargs=+acc work.tb_uart
onfinish stop

# Signals to display in the Wave window.
add wave sim:/tb_uart/clk
add wave sim:/tb_uart/tx_start
add wave -radix hexadecimal sim:/tb_uart/tx_data
add wave sim:/tb_uart/line
add wave sim:/tb_uart/tx_busy
add wave sim:/tb_uart/rx_valid
add wave -radix hexadecimal sim:/tb_uart/rx_data
add wave sim:/tb_uart/line2
add wave -radix hexadecimal sim:/tb_uart/d2

run -all
wave zoom full
