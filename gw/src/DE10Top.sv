`timescale 1ns / 1ps


module DE10Top (
    input logic pll_clk,
    input logic rst_n,
    input logic mode_spi,

    input  logic uart_rx,
    output logic uart_tx,

    output logic tck,
    output logic tms,
    output logic tdi,
    input  logic tdo,

    output logic spi_sclk,
    output logic spi_ssel,
    output logic spi_mosi,
    input  logic spi_miso,

    output logic clk_out,

	// I2C bus
    inout  wire  scl,
    inout  wire  sda

);

    localparam CLK_FREQ = 10_000_000; // 10 MHz
    localparam OUTPUT_CLK_FREQ = 100_000; // 100 kHz


    logic clk;

	pll_clk clkgen_i(
		.inclk0(pll_clk),
		.c0(clk)
	);

    // CDC logic for UART RX signal
    logic [1:0] uart_rx_sync;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            uart_rx_sync <= 2'b11; // idle state (line is high)
        end else begin
            uart_rx_sync <= {uart_rx_sync[0], uart_rx};
        end
    end

	 dac_commander #(
        .CLK_FREQ(CLK_FREQ)
     ) dac_commander_inst (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .o_done(),  // Not used. It can be connected to an LED or left unconnected.
        .o_ack_error(),  // Not used. It can be connected to an LED or left unconnected.
        .scl(scl),
        .sda(sda)
    );

    // Instantiate the JTAG-UART bridge
    jtag_uart_bridge #(
        .CLK_FREQ(CLK_FREQ)
    ) jtag_uart_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .mode_spi  (mode_spi),
        .uart_rx  (uart_rx_sync[1]),
        .uart_tx  (uart_tx),
        .TCK      (tck),
        .TMS      (tms),
        .TDI      (tdi),
        .TDO      (tdo),
        .spi_sclk  (spi_sclk),
        .spi_ssel  (spi_ssel),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso)
    );

    /////////////////////////////////// LED signals (for debugging)
    ////     Quartus PLL IP generator might not work properly. 
    ////     Check the clock output frequency matches the expected value (10 MHz).

    localparam COUNTER_TOP = CLK_FREQ / (2 * OUTPUT_CLK_FREQ); // Number of input clock cycles for half period of output clock
    logic [$clog2(COUNTER_TOP)-1:0] clk_counter;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            clk_counter <= 0;
            clk_out <= 0;
        end else begin
            clk_counter <= clk_counter + 1;
            if(clk_counter == COUNTER_TOP - 1) begin
                clk_counter <= 0;
                clk_out <= ~clk_out; 
            end
        end
    end

endmodule
