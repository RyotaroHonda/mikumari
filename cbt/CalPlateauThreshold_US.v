`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 11/27/2024 11:19:24 AM
// Design Name:
// Module Name: CalPlateauThreshold_US
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module CalPlateauThreshold_US(
        CLK,
        cntValueOutInit,
        cntValueOutSlaveInit,
        plateauThreshold
    );

    parameter kCNTVALUEbit = 9;
    parameter kNumTaps = 32;
    parameter kDELAY_VALUE = 1000.0;
    parameter kAlignDelay = 54;
    parameter kStableRange = 0.65;      // = 0.65
    parameter kFreqFastClk = 500;
    parameter kBitPut = 4;      //4bit
    parameter kDivTapShift = 8;       //div_tap -> fractual is 8bit
    parameter kExpectedStableLength = (1.0/(2.0*kFreqFastClk)*1000.0*1000.0*kStableRange);

    input CLK;
    input [kCNTVALUEbit-1:0] cntValueOutInit;
    input [kCNTVALUEbit-1:0] cntValueOutSlaveInit;
    output [kNumTaps-1:0] plateauThreshold;


    localparam DELAY_VALUE_width = 16;
    wire [DELAY_VALUE_width-1:0] DELAY_VALUE_set;
    assign DELAY_VALUE_set[DELAY_VALUE_width-1:0] = kDELAY_VALUE; // = 1000 (ps)

    localparam quotient_integer_width = 16;
    localparam quotient_fractional_width = 8;
    wire [quotient_integer_width+quotient_fractional_width-1:0] tap_master;
    wire [quotient_integer_width+quotient_fractional_width-1:0] tap_slave;


    udiv_q_cbt_axis #(
        .DW(DELAY_VALUE_width), .QI(quotient_integer_width), .QF(quotient_fractional_width)
    ) div_tap_master (
        .clk(CLK),
        .rst(1'b0),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_dividend(DELAY_VALUE_set),
        .s_axis_divisor(cntValueOutInit - kAlignDelay),
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_div_by_zero(),
        .m_axis_q_int(tap_master[quotient_integer_width+quotient_fractional_width-1:quotient_fractional_width]),
        .m_axis_q_frac(tap_master[quotient_fractional_width-1:0]),
        .m_axis_remainder()
    );
    udiv_q_cbt_axis #(
        .DW(DELAY_VALUE_width), .QI(quotient_integer_width), .QF(quotient_fractional_width)
    ) div_tap_slave (
        .clk(CLK),
        .rst(1'b0),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_dividend(DELAY_VALUE_set),
        .s_axis_divisor(cntValueOutSlaveInit),
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_div_by_zero(),
        .m_axis_q_int(tap_slave[quotient_integer_width+quotient_fractional_width-1:quotient_fractional_width]),
        .m_axis_q_frac(tap_slave[quotient_fractional_width-1:0]),
        .m_axis_remainder()
    );



    wire [quotient_integer_width+quotient_fractional_width-1:0] tap_delay;
    assign tap_delay  = tap_master + tap_slave;

    reg [quotient_integer_width+quotient_fractional_width-1:0] tap_delay_old;
    always@(posedge CLK)begin
        tap_delay_old <= (tap_delay << kBitPut);
    end

    wire [quotient_integer_width+quotient_fractional_width-1:0] ExpectedStableLength_wire;
    assign ExpectedStableLength_wire = kExpectedStableLength;

    wire [quotient_integer_width+quotient_fractional_width-1:0] ExpectedStableLength_wire_level2;
    assign  ExpectedStableLength_wire_level2= (ExpectedStableLength_wire << kDivTapShift);


    localparam divider_out_width = quotient_integer_width+quotient_fractional_width*2; //16+8*2 = 32;

    wire [divider_out_width-1:0] divider_out;

    udiv_q_cbt_axis #(
        .DW(quotient_integer_width+quotient_fractional_width),  //24
        .QI(quotient_integer_width+quotient_fractional_width),  //24
        .QF(quotient_fractional_width)                          //8
    ) divider (
        .clk(CLK),
        .rst(1'b0),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_dividend(ExpectedStableLength_wire_level2),
        .s_axis_divisor(tap_delay_old),
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_div_by_zero(),
        .m_axis_q_int(divider_out[divider_out_width-1:quotient_fractional_width]),
        .m_axis_q_frac(divider_out[quotient_fractional_width-1:0]),
        .m_axis_remainder()
    );


    reg [quotient_integer_width+quotient_fractional_width-1:0] divider_level2;
    always@(posedge CLK)begin
        divider_level2 <= divider_out[quotient_integer_width+quotient_fractional_width-1:quotient_fractional_width];       //Round down
    end

    assign plateauThreshold = divider_level2;


endmodule
