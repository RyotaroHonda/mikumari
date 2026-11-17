`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/09/2025 05:47:51 PM
// Design Name: 
// Module Name: BUFG_CLR_DEV
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


module BUFG_CLR_DEV(
        input clk_CLR,
        output BUFDIV_CLR,
        output BUFDIV_CE,
        input mmcm_cdcm_locked,
        output mmcm_cdcm_locked_level2
    );
    
    
    reg [1:0] mmcm_cdcm_locked_old;
    always@(posedge clk_CLR)begin
        mmcm_cdcm_locked_old[0] <= mmcm_cdcm_locked;
        mmcm_cdcm_locked_old[1] <= mmcm_cdcm_locked_old[0];
    end
    
    wire reset_clk_on;
    assign reset_clk_on = mmcm_cdcm_locked_old[0] & ~mmcm_cdcm_locked_old[1];
    
    
    reg [6:0] reset_clk_on_old;
    always@(posedge clk_CLR)begin
        reset_clk_on_old[0] <= reset_clk_on;
        reset_clk_on_old[1] <= reset_clk_on_old[0];
        reset_clk_on_old[2] <= reset_clk_on_old[1];
        reset_clk_on_old[3] <= reset_clk_on_old[2];
        reset_clk_on_old[4] <= reset_clk_on_old[3];
        reset_clk_on_old[5] <= reset_clk_on_old[4];
        reset_clk_on_old[6] <= reset_clk_on_old[5];
    end
    
    reg locked_en;
    always@(posedge clk_CLR)begin
        if(reset_clk_on)begin
            locked_en <= 1'b0;
        end
        else if(reset_clk_on_old[6])begin
            locked_en <= 1'b1;       
        end
    end
    
    assign mmcm_cdcm_locked_level2 = mmcm_cdcm_locked & mmcm_cdcm_locked_old[0] & mmcm_cdcm_locked_old[1] & locked_en;

    wire BUFDIV_CE_level1;
    wire BUFDIV_CLR_level1;
    assign BUFDIV_CE_level1 = (reset_clk_on_old[4:0] != 5'h0) ? 1'b0 : 1'b1;
    assign BUFDIV_CLR_level1 = (reset_clk_on_old[4:0] == 5'b00100) ? 1'b1 : 1'b0;

    (* keep = "true" *) reg BUFDIV_CE_level2;
    (* keep = "true" *) reg BUFDIV_CLR_level2;
    (* keep = "true" *) reg BUFDIV_CE_level3;
    (* keep = "true" *) reg BUFDIV_CLR_level3;    
    always@(posedge clk_CLR)begin
        BUFDIV_CE_level2 <= BUFDIV_CE_level1;
        BUFDIV_CLR_level2 <= BUFDIV_CLR_level1;
        BUFDIV_CE_level3 <= BUFDIV_CE_level2;
        BUFDIV_CLR_level3 <= BUFDIV_CLR_level2;
    end
    
    
    assign BUFDIV_CE = BUFDIV_CE_level3;
    assign BUFDIV_CLR = BUFDIV_CLR_level3;
    
endmodule
