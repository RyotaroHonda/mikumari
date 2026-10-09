`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/03/2026 08:56:40 PM
// Design Name: 
// Module Name: DynamicReAdjust
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


module DynamicReAdjust(
        clkPar,
        rst,
        reqIdelayShift,
        reqReAdjustOut,
        permitReadjust,
        doneReAdjustOut,
        tap_value_out,
        tap_value_readjust,
        cdcm_rx_up,
        bitslip_inc,
        bitslip_dec,
        tap_readjust_reset
    );
    
    parameter kFreqFastClk = 500;    //MHz
    parameter kCdcmModWidth = 8;
    parameter kFreqRefClk = 200;
    parameter kReqIdelayShiftBits = 2; 
    parameter kWidthTap = 5;
    
    parameter kWaitTime = 16'hFFFF;
    parameter kTapCheckTimeout = 16'hFFFF;
    
    //parameter

        input clkPar;
        input rst;
        input [kReqIdelayShiftBits-1:0] reqIdelayShift;
        output      reqReAdjustOut;
        input       permitReadjust;
        output      doneReAdjustOut;
        input [kWidthTap-1:0] tap_value_out;
        output [kWidthTap-1:0] tap_value_readjust;
        input cdcm_rx_up;
        output bitslip_inc;
        output bitslip_dec;
        output tap_readjust_reset;

    
    reg [3:0] state_adjust;


    localparam kTapIncrease = 2'b01;
    localparam kTapDecrease = 2'b10;    
    
    localparam [kWidthTap-1:0] kTapMax = 5'd31;
    localparam [kWidthTap-1:0] kTapMin = 5'd0;
    
    
    function integer GetTapDelay;
        input integer freq_idelayctrl_ref;
        begin
            if ((190 < freq_idelayctrl_ref) && (freq_idelayctrl_ref < 210)) begin
                GetTapDelay = 78;
            end
            else if ((290 < freq_idelayctrl_ref) && (freq_idelayctrl_ref < 310)) begin
                GetTapDelay = 52;
            end
            else if ((390 < freq_idelayctrl_ref) && (freq_idelayctrl_ref < 410)) begin
                GetTapDelay = 39;
            end
            else begin
                GetTapDelay = 0;
            end
        end
    endfunction    
    localparam kDelayIdelayTap = GetTapDelay(kFreqRefClk);
    
    
    // state definition
    localparam Init     = 4'd0;
    localparam Wait     = 4'd1;
    localparam BitShift  = 4'd2;
    localparam BitShiftFin = 4'd3;
    localparam TapShift  = 4'd4;
    localparam TapJump = 4'd5;
    localparam TapLoad      = 4'd6;
    localparam TapOutCheck  = 4'd7;  
    localparam WaitAfterConfig = 4'd8; 
    localparam AdjustFin    = 4'd9;   
    localparam ReAdjustError = 4'd10; 
    
    reg [kWidthTap-1:0] reg_tap_value_readjust;
    reg reg_tap_readjust_reset;
    reg [15:0] wait_counter;
    reg [15:0] tap_check_timeout_counter;   
    
    reg req_readjust_out;
    reg done_readjust; 
    reg reg_bitslip_inc;
    reg reg_bitslip_dec;
  
    wire [kWidthTap-1:0] tap_jump_carryup;
    wire [kWidthTap-1:0] tap_jump_carrydown;
  
    localparam TapStatusOneIncrease = 2'b00;  //1 tap increase, no bit shift
    localparam TapStatusOneDecrease = 2'b01;  //1 tap decrease, no bit shift
    localparam TapStatusJumpIncrease = 2'b10; //tap jump, 1 bit increase
    localparam TapStatusJumpDecrease = 2'b11; //tap jump, 1 bit decrease
    reg [1:0] tap_status;
    reg [23:0] calib_period;

    reg signed [23:0]  next_calib_period_decrease;
    reg signed [23:0]  next_calib_period_increase;    
    reg signed [23:0]  next_calib_period_total;
      
    always@(posedge clkPar)begin
        if(rst)begin
            state_adjust <= Init;
            reg_tap_value_readjust <= 5'd0;
            reg_tap_readjust_reset <= 1'b0;
            wait_counter <= kWaitTime;
            tap_check_timeout_counter <= kTapCheckTimeout;    
            req_readjust_out <= 1'b0;  
            done_readjust <= 1'b0;
            tap_status <= 2'h0;
            reg_bitslip_inc <= 1'b0;
            reg_bitslip_dec <= 1'b0;
            calib_period <= 24'h0;
            next_calib_period_total <= 24'h0;
        end            
        else begin
            case (state_adjust) 
                Init : begin
                    if(cdcm_rx_up)begin
                        state_adjust <= Wait;
                        reg_tap_value_readjust <= tap_value_out;
                    end
                    else begin
                        reg_tap_value_readjust <= tap_value_out;
                    end
                end
                
                Wait : begin                
                    if(reqIdelayShift == kTapIncrease)begin
                        if(tap_value_out == kTapMax)begin
                            state_adjust <= TapJump;
                            req_readjust_out <= 1'b1;
                            tap_status <= TapStatusJumpIncrease;
                        end
                        else begin
                            state_adjust <= TapShift;
                            tap_status <= TapStatusOneIncrease;
                        end
                    end
                    else if(reqIdelayShift == kTapDecrease)begin
                        if(tap_value_out == kTapMin)begin
                            state_adjust <= TapJump;
                            req_readjust_out <= 1'b1;
                            tap_status <= TapStatusJumpDecrease;
                        end
                        else begin
                            state_adjust <= TapShift;
                            tap_status <= TapStatusOneDecrease;
                        end
                    end
                end
  
                TapJump : begin
                    if(permitReadjust)begin
                        state_adjust <= TapLoad;
                        //next_calib_period_total <= next_calib_period_total + next_calib_period;
                        
                        if(tap_status == TapStatusJumpIncrease)begin
                            reg_tap_value_readjust <= (tap_jump_carryup + 1'b1);
                            next_calib_period_total <= next_calib_period_total + next_calib_period_increase;
                        end 
                        else if(tap_status == TapStatusJumpDecrease)begin
                            reg_tap_value_readjust <= (tap_jump_carrydown - 1'b1);
                            next_calib_period_total <= next_calib_period_total - next_calib_period_decrease;
                        end                       
                    end
                end
  
                TapShift : begin
                    if(tap_status == TapStatusOneIncrease)begin
                        reg_tap_value_readjust <= tap_value_out + 1'b1;
                    end 
                    else if(tap_status == TapStatusOneDecrease)begin
                        reg_tap_value_readjust <= tap_value_out - 1'b1;
                    end              
                    
                    state_adjust <= TapLoad;
                end
                
                TapLoad : begin
                    reg_tap_readjust_reset <= 1'b1;
                    tap_check_timeout_counter <= kTapCheckTimeout;
                    state_adjust <= TapOutCheck;    
                end           
                
                TapOutCheck : begin
                    if(tap_value_out == reg_tap_value_readjust)begin
                        wait_counter <= kWaitTime;
                        reg_tap_readjust_reset <= 1'b0;
        
                        if((tap_status == TapStatusJumpIncrease) ||
                            (tap_status == TapStatusJumpDecrease) )begin
                             state_adjust <= BitShift;
                        end                        
                        else begin   
                            state_adjust <= WaitAfterConfig;                    
                        end                         
                    end
                    else if(tap_check_timeout_counter == 0)begin
                        reg_tap_readjust_reset <= 1'b0;
                        state_adjust <= ReAdjustError;
                    end
                    else begin
                        tap_check_timeout_counter <= tap_check_timeout_counter - 1'b1;
                    end
                end
                
                BitShift : begin
                    if(tap_status == TapStatusJumpIncrease)begin
                        reg_bitslip_inc <= 1'b1;
                    end
                    else if(tap_status ==  TapStatusJumpDecrease)begin
                        reg_bitslip_dec <= 1'b1;
                    end                      
                    
                    state_adjust <= BitShiftFin;
                end                
               
                BitShiftFin : begin
                    reg_bitslip_inc <= 1'b0;
                    reg_bitslip_dec <= 1'b0;
                    done_readjust <= 1'b1;
                    state_adjust <= WaitAfterConfig;
                end
               
                
                WaitAfterConfig : begin
                    done_readjust <= 1'b0;
                    req_readjust_out <= 1'b0;
                    
                    if(wait_counter == 0)begin
                        state_adjust <= AdjustFin;
                    end
                    else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                
                AdjustFin : begin
                    state_adjust <= Wait;
                    reg_tap_readjust_reset <= 1'b0;
                    wait_counter <= kWaitTime;
                    tap_check_timeout_counter <= kTapCheckTimeout;    
                    req_readjust_out <= 1'b0;  
                    done_readjust <= 1'b0;
                    tap_status <= 2'h0;   
                    reg_bitslip_inc <= 1'b0;
                    reg_bitslip_dec <= 1'b0;                             
                end
                
                ReAdjustError :begin
                    state_adjust <= ReAdjustError;
                end
                
                default : state_adjust <= Init;
                
            endcase
        end
    end
    
    assign tap_value_readjust = reg_tap_value_readjust;
    assign tap_readjust_reset = reg_tap_readjust_reset;
    assign doneReAdjustOut = done_readjust;
    assign reqReAdjustOut = req_readjust_out;
    assign bitslip_inc = reg_bitslip_inc;
    assign bitslip_dec = reg_bitslip_dec;   
    
    
    // Calculate the time per bit .
    //  (1sec / freq ) = (10^12 [ps] / (kFreqFastClk[MHz] x 2 x 10^6 ) 
    // = 1000*1000 / (kFreqFastClk x 2) 
    localparam integer kPeriod = 1000*1000 / (2*kFreqFastClk);   //ps
    wire [15:0] divisor;
    assign divisor = kDelayIdelayTap;     
    
    wire signed [24:0] period_decrease_tmp;
    assign period_decrease_tmp = $signed(kPeriod) + next_calib_period_total;

    wire [15:0] period_decrease;
    assign period_decrease = period_decrease_tmp[15:0];

    wire [15:0] cal_int_decrease;
    wire [7:0] cal_frac_decrease;
    udiv_q_cbt_axis #(
        .DW(16), .QI(16), .QF(8)
    ) cal_tap_init_decrease (
        .clk(clkPar),
        .rst(rst),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_dividend(period_decrease[15:0]),
        .s_axis_divisor(divisor[15:0]),
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_div_by_zero(),
        .m_axis_q_int(cal_int_decrease),
        .m_axis_q_frac(cal_frac_decrease),
        .m_axis_remainder()
    );

    assign tap_jump_carrydown = cal_frac_decrease[7] ? cal_int_decrease + 1 : cal_int_decrease;   //Rounding off
    always@(posedge clkPar)begin
        next_calib_period_decrease <= kDelayIdelayTap*tap_jump_carrydown - kPeriod;    
    end  

    wire signed [24:0] period_increase_tmp;
    assign period_increase_tmp = $signed(kPeriod) - next_calib_period_total;

    wire [15:0] period_increase;
    assign period_increase = period_increase_tmp[15:0];

    wire [15:0] cal_int_increase;
    wire [7:0] cal_frac_increase;
    udiv_q_cbt_axis #(
        .DW(16), .QI(16), .QF(8)
    ) cal_tap_init_increase (
        .clk(clkPar),
        .rst(rst),
        .s_axis_tvalid(1'b1),
        .s_axis_tready(),
        .s_axis_dividend(period_increase[15:0]),
        .s_axis_divisor(divisor[15:0]),
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_div_by_zero(),
        .m_axis_q_int(cal_int_increase),
        .m_axis_q_frac(cal_frac_increase),
        .m_axis_remainder()
    );
   
    wire [kWidthTap-1:0] tap_jump_carryup_level0;
    assign tap_jump_carryup_level0 = cal_frac_increase[7] ? cal_int_increase + 1 : cal_int_increase;   //Rounding off
    assign tap_jump_carryup = kTapMax - tap_jump_carryup_level0;
    always@(posedge clkPar)begin
        next_calib_period_increase <= kDelayIdelayTap*tap_jump_carryup_level0 - kPeriod;    
    end  

endmodule



