quit -sim
vsim -voptargs="+acc" -t ps wave.tb_qspi

add wave -divider tb:
add wave tb_qspi/*

add wave -divider qspi:
add wave tb_qspi/qspi_if/*

#add wave -divider flash:
#add wave tb_qspi/flash_model/*

run 400 us