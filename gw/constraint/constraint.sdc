create_clock -name pll_clk -period 20.000 [get_ports {pll_clk}]

derive_pll_clocks
derive_clock_uncertainty