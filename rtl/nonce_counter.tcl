catch {quit -sim}

if {![file exists work]} {
    vlib work
}
vmap work work

# Compile this test and its design modules.
vlog -sv nonce_counter.v tb_nonce_counter.v
vsim -voptargs=+acc work.tb_nonce_counter
onfinish stop

# Signals to display in the Wave window.
add wave sim:/tb_nonce_counter/clk
add wave sim:/tb_nonce_counter/rst
add wave sim:/tb_nonce_counter/inc
add wave sim:/tb_nonce_counter/clear
add wave -radix hexadecimal sim:/tb_nonce_counter/nonce
add wave sim:/tb_nonce_counter/found
add wave -radix hexadecimal sim:/tb_nonce_counter/shown

run -all
wave zoom full
