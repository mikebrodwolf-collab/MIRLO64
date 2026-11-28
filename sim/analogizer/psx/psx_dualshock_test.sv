`timescale 1ns/1ps
`default_nettype none

module psx_dualshock_test;
    logic clk = 0;
    always #5 clk = ~clk;

    logic enable = 1;
    logic psx_dat = 1;
    logic psx_ack = 1;
    wire psx_clk, psx_cmd, psx_att1, psx_att2, updated;
    wire [15:0] buttons;

    // Five response bytes from a digital-mode controller. Distinctive active-low button patterns exercise the bit ordering, not just
    // the fact that all 16 output bits can be set.
    logic [7:0] response [0:4];
    integer byte_index = 0;
    integer bit_index = 0;
    integer errors = 0;

    an_psx_dualshock #(.MASTER_CLK_FREQ(1_000_000)) dut (
        .clk, .enable, .psx_dat, .psx_ack,
        .psx_clk, .psx_cmd, .psx_att1, .psx_att2, .buttons, .updated
    );

    // The controller presents each response bit while CLK is low; the
    // receiver samples it on the following rising edge. Data is LSB first.
    always @(negedge psx_att1) begin
        byte_index = 0;
        bit_index = 0;
    end

    always @(negedge psx_clk) begin
        if (!psx_att1) begin
            psx_dat = response[byte_index][bit_index];
            if (bit_index == 7) begin
                bit_index = 0;
                if (byte_index < 4) byte_index = byte_index + 1;
            end else bit_index = bit_index + 1;
        end
    end

    initial begin
        response[0] = 8'hFF;
        response[1] = 8'h41; // digital controller ID
        response[2] = 8'h5A;
        response[3] = 8'hA5;
        response[4] = 8'h5A

        wait (updated);
        #1;
        if (buttons !== 16'h9563) begin
            $display("FAIL: expected mapped button bitmap 9563, got %h", buttons);
            errors = errors + 1;
        end
        if (psx_att1 !== 1'b1 || psx_att2 !== 1'b1) begin
            $display("FAIL: ATT lines were not released after poll");
            errors = errors + 1;
        end

        enable = 0;
        repeat (2) @(posedge clk);
        #1;
        if (buttons !== 16'h0000) begin
            $display("FAIL: buttons did not clear when disabled: %h", buttons);
            errors = errors + 1;
        end

        if (errors == 0) $display("psx_dualshock_test: PASS");
        else $display("psx_dualshock_test: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: timed out waiting for a complete PSX poll");
        $finish;
    end
endmodule

`default_nettype wire
