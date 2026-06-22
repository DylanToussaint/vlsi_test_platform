`timescale 1ns / 1ps


module DE10Top (
    input logic pll_clk,
    input logic rst_n,

    input  logic uart_rx,
    output logic uart_tx,

    input  logic       pll_check_i,
    output logic [9:0] ledr,
    output logic [6:0] hex0,
    output logic [6:0] hex1,

    //output logic tck,
    //output logic tms,
    //output logic tdi,
    //input  logic tdo,

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

    logic unused_tck;
    logic unused_tms;
    logic unused_tdi;

    logic clk;
    logic spi_busy;
    logic [7:0] spi_last_rx;
    logic uart_rx_event;
    logic uart_tx_event;
    logic dac_done;
    logic dac_ack_error;

	pll_clk clkgen_i(
		.inclk0(pll_clk),
		.c0(clk)
	);

    // CDC logic for pll_check_o
    logic [1:0] pll_check_sync;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pll_check_sync <= 2'b00;
        else
            pll_check_sync <= {pll_check_sync[0], pll_check_i};
    end

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
        .o_done(dac_done),
        .o_ack_error(dac_ack_error),
        .scl(scl),
        .sda(sda)
    );

    // Instantiate the JTAG-UART bridge
    jtag_uart_bridge #(
        .CLK_FREQ(CLK_FREQ)
    ) jtag_uart_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .mode_spi  (1'b1),
        .uart_rx  (uart_rx_sync[1]),
        .uart_tx  (uart_tx),
        .TCK      (unused_tck),
        .TMS      (unused_tms),
        .TDI      (unused_tdi),
        .TDO      (1'b0),
        .spi_sclk  (spi_sclk),
        .spi_ssel  (spi_ssel),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .spi_busy_o(spi_busy),
        .spi_last_rx_o(spi_last_rx),
        .uart_rx_event_o(uart_rx_event),
        .uart_tx_event_o(uart_tx_event)
    );

    // Display the most recently received SPI byte as two hexadecimal digits.
    hex_decoder hex0_i (
        .value    (spi_last_rx[3:0]),
        .segments (hex0)
    );

    hex_decoder hex1_i (
        .value    (spi_last_rx[7:4]),
        .segments (hex1)
    );

    // Stretch UART byte events so they are visible on LEDs.
    localparam integer ACTIVITY_CLKS = CLK_FREQ / 10; // 100 ms
    localparam integer ACTIVITY_W = $clog2(ACTIVITY_CLKS + 1);
    logic [ACTIVITY_W-1:0] uart_rx_activity_count;
    logic [ACTIVITY_W-1:0] uart_tx_activity_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_activity_count <= '0;
            uart_tx_activity_count <= '0;
        end else begin
            if (uart_rx_event)
                uart_rx_activity_count <= ACTIVITY_CLKS;
            else if (uart_rx_activity_count != 0)
                uart_rx_activity_count <= uart_rx_activity_count - 1'b1;

            if (uart_tx_event)
                uart_tx_activity_count <= ACTIVITY_CLKS;
            else if (uart_tx_activity_count != 0)
                uart_tx_activity_count <= uart_tx_activity_count - 1'b1;
        end
    end

    // One-second-period FPGA heartbeat derived from the internal 10 MHz clock.
    localparam integer HEARTBEAT_HALF_CLKS = CLK_FREQ / 2;
    logic [$clog2(HEARTBEAT_HALF_CLKS)-1:0] heartbeat_count;
    logic heartbeat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            heartbeat_count <= '0;
            heartbeat       <= 1'b0;
        end else if (heartbeat_count == HEARTBEAT_HALF_CLKS - 1) begin
            heartbeat_count <= '0;
            heartbeat       <= ~heartbeat;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;
        end
    end

    assign ledr[0] = pll_check_sync[1];
    assign ledr[1] = rst_n;
    assign ledr[2] = spi_busy;
    assign ledr[3] = ~spi_ssel;
    assign ledr[4] = spi_miso;
    assign ledr[5] = (uart_rx_activity_count != 0);
    assign ledr[6] = (uart_tx_activity_count != 0);
    assign ledr[7] = dac_done;
    assign ledr[8] = dac_ack_error;
    assign ledr[9] = heartbeat;

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
