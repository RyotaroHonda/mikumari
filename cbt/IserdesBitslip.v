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
        bitslip_dec,
        bitslipNum,
        iserdes_out,
        bitslip_out,
        cdcmUpRx,
        dataOutRxShift
    );
    
    parameter kDevW = 8;
    parameter kSelCount = 3;
    parameter kDataShift_en = 0;    //1->True. 0->False
            
    input clkDivIn;
    input rst;
    input bitslip;
    input bitslip_dec;
    output [kSelCount-1:0] bitslipNum;
    input [kDevW-1:0] iserdes_out;
    output [kDevW-1:0] bitslip_out;
    input cdcmUpRx;
    output [1:0] dataOutRxShift;
    
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
        else if(bitslip_dec)begin
            sel_MP[kSelCount-1:0] <= sel_MP[kSelCount-1:0] - 1'b1;
        end          
    end

    assign bitslipNum[kSelCount-1:0] = sel_MP[kSelCount-1:0];

    wire [kDevW-1:0] iserdes_out_level3[kDevW-1:0];

    assign iserdes_out_level3[0][kDevW-1:0] = iserdes_out[kDevW-1:0];
    genvar i;
    generate
        for (i = 1; i < kDevW; i = i + 1) begin : MP_loop
            assign iserdes_out_level3[i][kDevW-1:0] = {iserdes_out[kDevW-1-i:0], iserdes_out_old[kDevW-1:kDevW-i]};
        end
    endgenerate    
    
    //assign bitslip_out[kDevW-1:0] = iserdes_out_level3[sel_MP][kDevW-1:0];
    
    
    reg [1:0] reg_dataOutRxShift;
    
    localparam shift_up = 2'b01;
    localparam shift_down = 2'b10;

    always@(posedge clkDivIn)begin
        if(bitslip && sel_MP[kSelCount-1:0] == (kDevW-1))begin
            reg_dataOutRxShift <= shift_up;
        end
        else if(bitslip_dec && sel_MP[kSelCount-1:0] == 0)begin
            reg_dataOutRxShift <= shift_down;
        end
        else begin
            reg_dataOutRxShift <= 2'b00;
        end
    end
    
    assign dataOutRxShift = reg_dataOutRxShift;
    
    reg [kDevW-1:0] elastic_buffer[7:0];    
    
    always@(posedge clkDivIn)begin
        elastic_buffer[0] <= iserdes_out_level3[sel_MP];
        elastic_buffer[1] <= elastic_buffer[0];
        elastic_buffer[2] <= elastic_buffer[1];
        elastic_buffer[3] <= elastic_buffer[2];
        elastic_buffer[4] <= elastic_buffer[3];
        elastic_buffer[5] <= elastic_buffer[4];
        elastic_buffer[6] <= elastic_buffer[5];
        elastic_buffer[7] <= elastic_buffer[6];
    end
    
    localparam shift_sel_buffer_num = 3;        //3bit
    localparam sel_buffer_central = 3;      //central of 0~7
    reg [shift_sel_buffer_num-1:0] shift_sel;
    
    
    always@(posedge clkDivIn)begin
        if(rst)begin
            shift_sel <= 3'd0;
        end
        else if(cdcmUpRx)begin
            if(bitslip && sel_MP[kSelCount-1:0] == (kDevW-1))begin
                shift_sel <= shift_sel + 1'b1;
            end
            else if(bitslip_dec && sel_MP[kSelCount-1:0] == 0)begin
                shift_sel <= shift_sel - 1'b1;
            end
        end
    end  
    
    wire [shift_sel_buffer_num-1:0] shift_sel_level2;
    assign shift_sel_level2 = shift_sel + sel_buffer_central;
        
    assign bitslip_out[kDevW-1:0] = elastic_buffer[shift_sel_level2][kDevW-1:0];

endmodule
