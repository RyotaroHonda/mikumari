
// file: clk_wiz_1.v
// 
// (c) Copyright 2008 - 2013 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
//----------------------------------------------------------------------------
// User entered comments
//----------------------------------------------------------------------------
// None
//
//----------------------------------------------------------------------------
//  Output     Output      Phase    Duty Cycle   Pk-to-Pk     Phase
//   Clock     Freq (MHz)  (degrees)    (%)     Jitter (ps)  Error (ps)
//----------------------------------------------------------------------------
// clk_fast_TX__500.00000______0.000______50.0_______97.082_____98.575
// clk_fast_RX__500.00000______0.000______50.0_______97.082_____98.575
// clk_slow__125.00000______0.000______50.0______125.247_____98.575
// clk_slow_CLR__125.00000______0.000______50.0______125.247_____98.575
//
//----------------------------------------------------------------------------
// Input Clock   Freq (MHz)    Input Jitter (UI)
//----------------------------------------------------------------------------
// __primary_____________100___________100.000

`timescale 1ps/1ps


module mmcm_cdcm 
 (
  // Clock out ports
  output        clk_fast_TX,
  output        clk_fast_RX,
  output        clk_slow,
  output        clk_slow_CLR,
  // Status and control signals
  input         reset,
  output        locked,
 // Clock in ports
  input         clk_in1,
  input         BUFDIV_CE,
  input         BUFDIV_CLR    
 );

  mmcm_cdcm_clk_wiz inst
  (
  // Clock out ports  
  .clk_fast_TX(clk_fast_TX),
  .clk_fast_RX(clk_fast_RX),
  .clk_slow(clk_slow),
  .clk_slow_CLR(clk_slow_CLR),
  // Status and control signals               
  .reset(reset), 
  .locked(locked),
 // Clock in ports
  .clk_in1(clk_in1),
  .BUFDIV_CE(BUFDIV_CE),
  .BUFDIV_CLR(BUFDIV_CLR)
  );

endmodule
