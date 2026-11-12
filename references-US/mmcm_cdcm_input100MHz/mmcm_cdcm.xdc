################################################################################
# mmcm_cdcm.xdc  -- Constraints for mmcm_cdcm (500 MHz)
#
# Add this file to your project (read it before your timing XDC).
# Edit "u_mmcm_cdcm" to match your instance path.
#
# set_clock_groups is not included. Add it in your XDC as needed, e.g.:
#   set_clock_groups -asynchronous \
#     -group [get_clocks {clk_fast clk_slow clk_slow_CLR}] \
#     -group [get_clocks <your_other_clk>]
################################################################################

create_generated_clock -name clk_slow_CLR [get_pins u_mmcm_cdcm/inst/mmcme4_adv_inst/CLKOUT3]
create_generated_clock -name clk_slow     [get_pins u_mmcm_cdcm/inst/BUFGCE_DIV_CLK3_inst/O]
create_generated_clock -name clk_fast     [get_pins u_mmcm_cdcm/inst/mmcme4_adv_inst/CLKOUT0]

# Match CLK/CLKDIV routing delay (minimize skew)
set_property CLOCK_DELAY_GROUP mikumari_cdcm_clk [get_nets u_mmcm_cdcm/inst/clk_fast_TX]
set_property CLOCK_DELAY_GROUP mikumari_cdcm_clk [get_nets u_mmcm_cdcm/inst/clk_fast_RX]
set_property CLOCK_DELAY_GROUP mikumari_cdcm_clk [get_nets u_mmcm_cdcm/inst/clk_slow]
