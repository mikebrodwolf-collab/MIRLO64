// Clean-room PlayStation DualShock serial poller for Analogizer R.1, Config B.
// Standard poll: host 01 42 00 00 00 00 00 00 00 (LSB first).
// SCLK idles high; CMD changes while high and DAT is sampled on rising edges.
`default_nettype none
module an_psx_dualshock #(
    parameter integer MASTER_CLK_FREQ = 74_250_000
) (
    input wire clk, enable, psx_dat, psx_ack,
    output logic psx_clk = 1'b1, psx_cmd = 1'b1,
    output logic psx_att1 = 1'b1, psx_att2 = 1'b1,
    output logic [15:0] buttons = 16'd0,
    output logic [31:0] joy = 32'h8080_8080,
    output logic updated = 1'b0
);
    localparam integer HALF_PERIOD = MASTER_CLK_FREQ / 250_000;
    localparam integer START_DELAY = MASTER_CLK_FREQ / 100_000;
    localparam integer BYTE_GAP = MASTER_CLK_FREQ / 200_000;
    localparam integer POLL_PERIOD = MASTER_CLK_FREQ / 60;
    // Keep the counters only as wide as their actual maximum values. The
    // serial timer never exceeds START_DELAY-1; the poll timer counts to
    // POLL_PERIOD-1. Wide 32-bit decrementers needlessly consume FPGA logic.
    localparam integer TIMER_WIDTH = $clog2(START_DELAY + 1);
    localparam integer POLL_TIMER_WIDTH = $clog2(POLL_PERIOD);
    localparam [2:0] ST_IDLE=0, ST_START=1, ST_LOW=2, ST_HIGH=3, ST_GAP=4;
    logic [2:0] state=ST_IDLE;
    logic [TIMER_WIDTH-1:0] timer=0;
    logic [POLL_TIMER_WIDTH-1:0] poll_timer=0;
    logic [3:0] byte_index=0;
    logic [2:0] bit_index=0;
    logic [7:0] tx_byte=8'h01, rx_shift=0, rx_id=8'hFF;
    logic [7:0] rx_buttons_lo=8'hFF, rx_buttons_hi=8'hFF;
    logic [7:0] rx_right_x=8'h80, rx_right_y=8'h80;
    logic [7:0] rx_left_x=8'h80, rx_left_y=8'h80;
    wire [7:0] sampled_byte={psx_dat,rx_shift[6:0]};
    wire [7:0] next_command_byte;
    function automatic [7:0] command_byte(input [3:0] index);
        case(index)
            0: command_byte=8'h01;
            1: command_byte=8'h42;
            default: command_byte=8'h00;
        endcase
    endfunction
    assign next_command_byte=command_byte(byte_index);
    function automatic [15:0] decode_buttons(input [7:0] lo,input [7:0] hi);
        reg [15:0] k;
        begin
            k=0;
            k[0]=~lo[4]; k[1]=~lo[6]; k[2]=~lo[7]; k[3]=~lo[5];
            k[4]=~hi[6]; k[5]=~hi[5]; k[6]=~hi[7]; k[7]=~hi[4];
            k[8]=~hi[2]; k[9]=~hi[3]; k[10]=~hi[0]; k[11]=~hi[1];
            k[12]=~lo[1]; k[13]=~lo[2]; k[14]=~lo[0]; k[15]=~lo[3];
            decode_buttons=k;
        end
    endfunction
    always_ff @(posedge clk) begin
        updated<=0;
        if(!enable) begin
            state<=ST_IDLE; timer<=0; poll_timer<=0; byte_index<=0; bit_index<=0;
            tx_byte<=8'h01; rx_shift<=0; rx_id<=8'hFF;
            rx_buttons_lo<=8'hFF; rx_buttons_hi<=8'hFF;
            rx_right_x<=8'h80; rx_right_y<=8'h80; rx_left_x<=8'h80; rx_left_y<=8'h80;
            psx_clk<=1; psx_cmd<=1; psx_att1<=1; psx_att2<=1;
            buttons<=0; joy<=32'h8080_8080;
        end else begin
            case(state)
                ST_IDLE: begin
                    psx_clk<=1; psx_cmd<=1; psx_att1<=1; psx_att2<=1;
                    if(poll_timer>=POLL_PERIOD-1) begin
                        poll_timer<=0; byte_index<=0; bit_index<=0; tx_byte<=8'h01; rx_shift<=0;
                        rx_id<=8'hFF; rx_buttons_lo<=8'hFF; rx_buttons_hi<=8'hFF;
                        rx_right_x<=8'h80; rx_right_y<=8'h80; rx_left_x<=8'h80; rx_left_y<=8'h80;
                        psx_att1<=0; timer<=START_DELAY-1; state<=ST_START;
                    end else poll_timer<=poll_timer+1'b1;
                end
                ST_START: if(timer==0) begin
                    psx_clk<=1; psx_cmd<=tx_byte[0]; timer<=HALF_PERIOD-1; state<=ST_LOW;
                end else timer<=timer-1'b1;
                ST_LOW: if(timer==0) begin
                    psx_clk<=0; timer<=HALF_PERIOD-1; state<=ST_HIGH;
                end else timer<=timer-1'b1;
                ST_HIGH: if(timer==0) begin
                    psx_clk<=1; rx_shift[bit_index]<=psx_dat;
                    if(bit_index==7) begin
                        case(byte_index)
                            1: rx_id<=sampled_byte;
                            3: rx_buttons_lo<=sampled_byte;
                            4: rx_buttons_hi<=sampled_byte;
                            5: rx_right_x<=sampled_byte;
                            6: rx_right_y<=sampled_byte;
                            7: rx_left_x<=sampled_byte;
                            8: rx_left_y<=sampled_byte;
                            default: ;
                        endcase
                        if(byte_index==8) begin
                            if(rx_id==8'h41 || rx_id==8'h73 || rx_id==8'h79 || rx_id==8'h53) begin
                                buttons<=decode_buttons(rx_buttons_lo,rx_buttons_hi);
                                if(rx_id==8'h73 || rx_id==8'h79 || rx_id==8'h53)
                                    joy<={rx_right_y,rx_right_x,rx_left_y,rx_left_x};
                                else joy<=32'h8080_8080;
                            end else begin
                                buttons<=0; joy<=32'h8080_8080;
                            end
                            psx_att1<=1; psx_cmd<=1; updated<=1; state<=ST_IDLE;
                        end else begin
                            byte_index<=byte_index+1'b1; timer<=BYTE_GAP-1; state<=ST_GAP;
                        end
                    end else begin
                        bit_index<=bit_index+1'b1; psx_cmd<=tx_byte[bit_index+1'b1];
                        timer<=HALF_PERIOD-1; state<=ST_LOW;
                    end
                end else timer<=timer-1'b1;
                ST_GAP: if(timer==0) begin
                    tx_byte<=next_command_byte; bit_index<=0; rx_shift<=0;
                    psx_cmd<=next_command_byte[0]; timer<=HALF_PERIOD-1; state<=ST_LOW;
                end else timer<=timer-1'b1;
                default: state<=ST_IDLE;
            endcase
        end
    end
    // ACK is sampled only as a physical input in this first revision. A fixed
    // inter-byte gap is used; ACK pulse timing will be verified on hardware.
    wire unused_ack=psx_ack;
endmodule
