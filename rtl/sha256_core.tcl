catch {quit -sim}

if {![file exists work]} {
    vlib work
}
vmap work work

# Compile this test and its design modules.
vlog -sv sha256_core.v tb_sha256_core.v
vsim -voptargs=+acc work.tb_sha256_core
onfinish stop

# Signals to display in the Wave window.
add wave sim:/tb_sha256_core/clk
add wave sim:/tb_sha256_core/start
add wave sim:/tb_sha256_core/busy
add wave sim:/tb_sha256_core/done
add wave -radix hexadecimal sim:/tb_sha256_core/hout
add wave -radix unsigned sim:/tb_sha256_core/dut/t
add wave sim:/tb_sha256_core/dut/state

run -all
wave zoom full
