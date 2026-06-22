`timescale 1ns/1ps
module spi_master #(
    parameter integer CLK_FREQ_HZ = 10_000_000,
    parameter integer SPI_FREQ_HZ = 5_000_000
)(
    input  logic clk,
    input  logic rst_n,

    // UART RX FIFO->SPI
    input  logic       rx_empty,
    output logic       rx_rd_en,
    input  logic [7:0] rx_rd_data,

    // SPI -> UART TX FIFO
    input  logic       tx_full,
    output logic       tx_wr_en,
    output logic [7:0] tx_wr_data,

    //SPI mode 0 pins
    output logic spi_sclk,
    output logic spi_ssel,
    output logic spi_mosi,
    input  logic spi_miso,

    output logic busy
);

    localparam integer HALF_PERIOD_CLKS = CLK_FREQ_HZ / (2 * SPI_FREQ_HZ);

    localparam integer TIMER_W = (HALF_PERIOD_CLKS <= 1) ? 1 : $clog2(HALF_PERIOD_CLKS);

    logic [TIMER_W-1:0] timer;

    logic [15:0] transfer_length;
    logic [15:0] bytes_remaining;

    logic [7:0] tx_shift;
    logic [7:0] rx_shift;
    logic [2:0] bit_index;

    logic first_byte;

    typedef enum logic [3:0] {
        GET_LENGTH_HI,
        GET_LENGTH_LO,
        WAIT_BYTE,
        LOW_PHASE,
        HIGH_PHASE,
        PUSH_BYTE
    } state_t;

    state_t state;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state            <= GET_LENGTH_HI;
            rx_rd_en         <= 1'b0;
            tx_wr_en         <= 1'b0;
            tx_wr_data       <= 8'h00;

            transfer_length  <= 16'h0000;
            bytes_remaining  <= 16'h0000;

            tx_shift         <= 8'h00;
            rx_shift         <= 8'h00;
            bit_index        <= 3'd7;
            timer            <= '0;

            spi_sclk         <= 1'b0;
            spi_ssel         <= 1'b1;
            spi_mosi         <= 1'b0;

            busy             <= 1'b0;
            first_byte       <= 1'b1;
        end else begin
            rx_rd_en <= 1'b0;
            tx_wr_en <= 1'b0;

            case (state)

                // First two input bytes contain transfer length.
                GET_LENGTH_HI: begin
                    busy      <= 1'b0;
                    spi_sclk  <= 1'b0;
                    spi_ssel  <= 1'b1;
                    spi_mosi  <= 1'b0;
                    first_byte <= 1'b1;

                    if (!rx_empty) begin
                        transfer_length[15:8] <= rx_rd_data;
                        rx_rd_en <= 1'b1;
                        state    <= GET_LENGTH_LO;
                    end
                end

                GET_LENGTH_LO: begin
                    if (!rx_empty) begin
                        transfer_length[7:0] <= rx_rd_data;
                        bytes_remaining <= {
                            transfer_length[15:8],
                            rx_rd_data
                        };

                        rx_rd_en <= 1'b1;

                        if ({transfer_length[15:8],
                             rx_rd_data} == 16'd0) begin
                            state <= GET_LENGTH_HI;
                        end else begin
                            busy  <= 1'b1;
                            state <= WAIT_BYTE;
                        end
                    end
                end

                // Wait for one byte from the UART RX FIFO.
                WAIT_BYTE: begin
                    if (!rx_empty && !tx_full) begin
                        tx_shift  <= rx_rd_data;
                        rx_shift  <= 8'h00;
                        bit_index <= 3'd7;

                        // Mode 0: MOSI is valid before rising edge.
                        spi_mosi <= rx_rd_data[7];
                        spi_sclk <= 1'b0;

                        if (first_byte) begin
                            spi_ssel   <= 1'b0;
                            first_byte <= 1'b0;
                        end

                        rx_rd_en <= 1'b1;
                        timer    <= HALF_PERIOD_CLKS - 1;
                        state    <= LOW_PHASE;
                    end
                end

                // Wait with SCLK low, then create rising edge.
                LOW_PHASE: begin
                    if (timer == 0) begin
                        spi_sclk <= 1'b1;

                        // Mode 0 samples MISO on rising edge.
                        rx_shift[bit_index] <= spi_miso;

                        timer <= HALF_PERIOD_CLKS - 1;
                        state <= HIGH_PHASE;
                    end else begin
                        timer <= timer - 1'b1;
                    end
                end

                // Wait with SCLK high, then create falling edge.
                HIGH_PHASE: begin
                    if (timer == 0) begin
                        spi_sclk <= 1'b0;

                        if (bit_index == 0) begin
                            state <= PUSH_BYTE;
                        end else begin
                            bit_index <= bit_index - 1'b1;

                            // Prepare the next MOSI bit while SCLK is low.
                            spi_mosi <= tx_shift[bit_index - 1'b1];

                            timer <= HALF_PERIOD_CLKS - 1;
                            state <= LOW_PHASE;
                        end
                    end else begin
                        timer <= timer - 1'b1;
                    end
                end

                // Return one received byte through the TX FIFO.
                PUSH_BYTE: begin
                    if (!tx_full) begin
                        tx_wr_data <= rx_shift;
                        tx_wr_en   <= 1'b1;

                        bytes_remaining <= bytes_remaining - 1'b1;

                        if (bytes_remaining == 16'd1) begin
                            // End the complete SPI transaction.
                            spi_ssel <= 1'b1;
                            spi_mosi <= 1'b0;
                            busy     <= 1'b0;
                            state    <= GET_LENGTH_HI;
                        end else begin
                            // CS remains low between bytes.
                            state <= WAIT_BYTE;
                        end
                    end
                end

                default: begin
                    state <= GET_LENGTH_HI;
                end
            endcase

        end
    end



endmodule