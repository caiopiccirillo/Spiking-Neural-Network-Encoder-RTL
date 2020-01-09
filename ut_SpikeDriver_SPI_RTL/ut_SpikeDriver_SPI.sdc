# Arquivo SYNOPSYS DESIGN CONSTRAINTS (.sdc) para DE10-NANO

# Constrain clock port CLK_50 with a 20-ns requirement (50 MHz)
create_clock -period 20 [get_ports CLK_50]

# Automatically apply a generate clock on the output of phase-locked loops (PLLs) 
# This command can be safely left in the SDC even if no PLLs exist in the design

derive_pll_clocks


# Constrain the input I/O path

set_input_delay -clock CLK_50 -max 3 [all_inputs]

set_input_delay -clock CLK_50 -min 2 [all_inputs]


# Constrain the output I/O path

set_output_delay -clock CLK_50 -max 3 [all_inputs]

set_output_delay -clock CLK_50 -min 2 [all_inputs]

