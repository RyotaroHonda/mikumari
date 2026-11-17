################################################################################
# mmcm_cdcm_second2.xdc  -- Constraints for mmcm_cdcm_second2 (500 MHz)
#
# Add this file to your project (read it after the MMCM input clock's create_clock).
# Edit "u_MMCM_CDCM" to match your instance path.
#
# set_clock_groups is not included. Add it in your XDC as needed, e.g.:
#   set_clock_groups -asynchronous \
#     -group [get_clocks {clk_fast clk_slow clk_slow_CLR}] \
#     -group [get_clocks <your_other_clk>]
################################################################################

create_generated_clock -name clk_fast     [get_pins u_MMCM_CDCM/inst/mmcme4_adv_inst/CLKOUT0]
create_generated_clock -name clk_slow_CLR [get_pins u_MMCM_CDCM/inst/mmcme4_adv_inst/CLKOUT3]
create_generated_clock -name clk_slow     [get_pins u_MMCM_CDCM/inst/BUFGCE_DIV_CLK3_inst/O]

# Match CLK/CLKDIV routing delay (minimize skew)
set_property CLOCK_DELAY_GROUP group_mmcm_cdcm_second [get_nets u_MMCM_CDCM/inst/clk_fast_TX]
set_property CLOCK_DELAY_GROUP group_mmcm_cdcm_second [get_nets u_MMCM_CDCM/inst/clk_fast_RX]
set_property CLOCK_DELAY_GROUP group_mmcm_cdcm_second [get_nets u_MMCM_CDCM/inst/clk_slow]
