`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/20/2026 02:02:03 PM
// Design Name: 
// Module Name: IserdesBitslip
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


module IserdesBitslip(
        clkDivIn,
        rst,
        bitslip,
        iserdes_out,
        bitslip_out
    );
    
    parameter kDevW = 8;
    parameter kSelCount = 3;
    
    input clkDivIn;
    input rst;
    input bitslip;
    input [kDevW-1:0] iserdes_out;
    output [kDevW-1:0] bitslip_out;
    
    reg [kDevW-1:0] iserdes_out_old;
    always@(posedge clkDivIn)begin
        iserdes_out_old[kDevW-1:0]  <= iserdes_out[kDevW-1:0] ;
    end

    reg [kSelCount-1:0] sel_MP;
    always@(posedge clkDivIn)begin
        if(rst)begin
            sel_MP[kSelCount-1:0] <= 0;
        end
        else if(bitslip)begin
            sel_MP[kSelCount-1:0] <= sel_MP[kSelCount-1:0] + 1'b1;
        end
    end

    wire [kDevW-1:0] iserdes_out_level3[kDevW-1:0];

    assign iserdes_out_level3[0][kDevW-1:0] = iserdes_out[kDevW-1:0];
    genvar i;
    generate
        for (i = 1; i < kDevW; i = i + 1) begin : MP_loop
            assign iserdes_out_level3[i][kDevW-1:0] = {iserdes_out[kDevW-1-i:0], iserdes_out_old[kDevW-1:kDevW-i]};
        end
    endgenerate    
    
    assign bitslip_out[kDevW-1:0] = iserdes_out_level3[sel_MP][kDevW-1:0];
    
endmodule
