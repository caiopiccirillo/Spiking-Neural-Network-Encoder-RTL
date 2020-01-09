set_global_assignment -entity "snand_pll" -library "lib_snand_pll" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "snand_pll" -library "lib_snand_pll" -name IP_TOOL_VERSION "18.1"
set_global_assignment -entity "snand_pll" -library "lib_snand_pll" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_snand_pll" -name SPD_FILE [file join $::quartus(sip_path) "snand_pll.spd"]

set_global_assignment -library "lib_snand_pll" -name MISC_FILE [file join $::quartus(sip_path) "snand_pll_sim/snand_pll.vo"]
