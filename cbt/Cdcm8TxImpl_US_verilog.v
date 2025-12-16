`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/30/2024 06:45:04 PM
// Design Name:
// Module Name: Cdcm8TxImpl
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


module Cdcm8TxImpl_US_verilog(
        //From the device to the system
        dInFromDevice,
        dOutToPinP,
        dOutToPinN,

        //Phase Offset
        offsetTable0,
        offsetTable1,
        offsetTable2,
        offsetTable3,
        offsetTable4,
        offsetTable5,
        offsetTable6,
        offsetTable7,
        scanFinished,

        //Clock and reset
        clkIn,
        clkDivIn,
        ioReset
    );

    parameter kSysW = 1;    //width of the ata for the system
    parameter kDevW = 8;    //width of the ata for the device
    parameter kIoStandard = "LVDS"; //IOSTANDARD of OBUFDS
    parameter kWidthScanTdc = 8;    //Latency scan num

    input [kDevW-1:0] dInFromDevice;
    output dOutToPinP;
    output dOutToPinN;

    output [kWidthScanTdc-1:0] offsetTable0;
    output [kWidthScanTdc-1:0] offsetTable1;
    output [kWidthScanTdc-1:0] offsetTable2;
    output [kWidthScanTdc-1:0] offsetTable3;
    output [kWidthScanTdc-1:0] offsetTable4;
    output [kWidthScanTdc-1:0] offsetTable5;
    output [kWidthScanTdc-1:0] offsetTable6;
    output [kWidthScanTdc-1:0] offsetTable7;
    output scanFinished;

    input clkIn;
    input clkDivIn;
    input ioReset;

    wire data_out_to_pin;
    OBUFDS
        #(.IOSTANDARD(kIoStandard),
            .SLEW("FAST")
        )
    u_Tx_OBUFDS_inst(
        .I(data_out_to_pin),
        .O(dOutToPinP),
        .OB(dOutToPinN)
    );

    wire [kDevW-1:0] tmp_waveform_in;
    assign tmp_waveform_in[kDevW-1:0] = 8'hF0;

    wire [kDevW-1:0] OSERDESE3_data;
    assign OSERDESE3_data[kDevW-1:0] = ioReset ? tmp_waveform_in[kDevW-1:0] : dInFromDevice[kDevW-1:0];

    OSERDESE3
    #(
        .DATA_WIDTH(8),
        .SIM_DEVICE            ("ULTRASCALE_PLUS")
    )
    u_OSERDESE3_master(
        .CLK(clkIn),
        .CLKDIV(clkDivIn),
        .D(OSERDESE3_data[kDevW-1:0]),
        .RST(ioReset),
        .T(1'b0),
        .OQ(data_out_to_pin),
        .T_OUT()
    );

    assign offsetTable0[kWidthScanTdc-1:0] = 8'hFB;
    assign offsetTable1[kWidthScanTdc-1:0] = 8'hFC;
    assign offsetTable2[kWidthScanTdc-1:0] = 8'hFD;
    assign offsetTable3[kWidthScanTdc-1:0] = 8'hFE;
    assign offsetTable4[kWidthScanTdc-1:0] = 8'hFF;
    assign offsetTable5[kWidthScanTdc-1:0] = 8'h00;
    assign offsetTable6[kWidthScanTdc-1:0] = 8'h01;
    assign offsetTable7[kWidthScanTdc-1:0] = 8'h02;

    assign scanFinished = ioReset ? 1'b0 : 1'b1;

endmodule
