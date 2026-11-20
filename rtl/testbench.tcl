catch {quit -sim}

if {![file exists work]} {
vlib work
}
vmap work work

vlog -sv sha256_core.v sha256_demo.v testbench.v
vsim -voptargs=+acc work.tb_sha256_demo
onfinish stop

add wave sim:/tb_sha256_demo/key
add wave sim:/tb_sha256_demo/dut/start
add wave sim:/tb_sha256_demo/dut/done
add wave -radix hexadecimal sim:/tb_sha256_demo/dut/hash
add wave -radix binary sim:/tb_sha256_demo/leds

run -all
wave zoom full