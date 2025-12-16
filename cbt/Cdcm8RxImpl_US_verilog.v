`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/17/2024 04:01:01 PM
// Design Name:
// Module Name: Cdcm8RxImpl
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



module Cdcm8RxImpl_US_verilog(
        pwrOnRst,

        dInFromPinP,
        dInFromPinN,

        rstIDelay,
        ceIDelay,
        incIDelay,
        enVtc,

        tapIn,
        tapOut,
        CNTVALUEOUT,
        CNTVALUEOUT_slave,

        cdOutFromO,
        dOutToDevice,
        bitslip,

        clkIn,
        clkDivIn,
        ioReset,

        readyCtrl,
        idelayInitDoneOut,
        cntValueOutLevel2Out,
        cntValueSlaveOutLevel2Out

    );

    parameter kSysW = 1;
    parameter kDevW = 8;
    parameter kSelCount = 3;
    parameter kDiffTerm = "TRUE";
    parameter kRxPolarity = "FALSE";
    parameter kIoStandard = "LVDS";
    parameter kIoDelayGroup = "cdcm_rx";
    parameter kFreqRefClk = 500;
    parameter kIdelayCtrlclk = 500;
    parameter kCNTVALUEbit = 9;
    parameter kDELAY_VALUE = 1000.0;
    parameter kBitslice0 = 0;

    parameter kCheckCntvalue = 4096;
    parameter kCheckIdelayInit = 65535;

    localparam TRUE  = 1'b1;
    localparam FALSE = 1'b0;
    localparam tap_width = 5;

    input pwrOnRst;

    input dInFromPinP;
    input dInFromPinN;

    input   rstIDelay;
    input   ceIDelay;
    input   incIDelay;
    input   enVtc;
    input [tap_width-1:0] tapIn;
    output [tap_width-1:0] tapOut;
    output [kCNTVALUEbit-1:0] CNTVALUEOUT;
    output [kCNTVALUEbit-1:0] CNTVALUEOUT_slave;

    output cdOutFromO;
    output [kDevW-1:0] dOutToDevice;
    input bitslip;

    input clkIn;
    input clkDivIn;
    input ioReset;

    input readyCtrl;
    output idelayInitDoneOut;
    output [kCNTVALUEbit-1:0] cntValueOutLevel2Out;
    output [kCNTVALUEbit-1:0] cntValueSlaveOutLevel2Out;

    wire data_in_from_pin_P;
    wire data_in_from_pin_N;
    wire idelay_IDATAIN;

generate
  if (kBitslice0 == TRUE) begin : g_ibuf_kBitslice0
    IBUFDS
      #(
        .DIFF_TERM  (kDiffTerm),
        .IOSTANDARD (kIoStandard)
      )             // Differential termination
     ibufds_inst
       (.I          (dInFromPinP),
        .IB         (dInFromPinN),
        .O          (idelay_IDATAIN)
       );
end else begin : g_ibuf
    IBUFDS_DIFF_OUT
      #(
        .DIFF_TERM  (kDiffTerm),
        .IOSTANDARD (kIoStandard)
      )             // Differential termination
     ibufds_inst
       (.I          (dInFromPinP),
        .IB         (dInFromPinN),
        .O          (data_in_from_pin_P),
        .OB         (data_in_from_pin_N)
       );

    assign idelay_IDATAIN = data_in_from_pin_N;
   end
endgenerate

//--------------------------------------------------------
//IDELAY (init cntvalueout)
//--------------------------------------------------------
    reg [kCNTVALUEbit-1:0] cntvalue_out_prev;
    reg [kCNTVALUEbit-1:0] cntvalue_slave_out_prev;

    always @(posedge clkDivIn) begin
        cntvalue_out_prev        <= CNTVALUEOUT;
        cntvalue_slave_out_prev  <= CNTVALUEOUT_slave;
    end

    integer check_cntvalue_out_time;

    reg cntvalue_done;

    always @(posedge clkDivIn) begin
        if (pwrOnRst) begin
            check_cntvalue_out_time <= 0;
            cntvalue_done           <= 1'b0;
        end
        else begin

            if ((CNTVALUEOUT == cntvalue_out_prev) &&
                (CNTVALUEOUT_slave == cntvalue_slave_out_prev) &&
                (CNTVALUEOUT != 0) &&
                (CNTVALUEOUT_slave != 0)
                ) begin
                if (check_cntvalue_out_time == kCheckCntvalue)begin
                    cntvalue_done <= 1'b1;
                end
                else if (!cntvalue_done)begin
                    check_cntvalue_out_time <= check_cntvalue_out_time + 1;
                end
            end else begin
                check_cntvalue_out_time <= 0;
                cntvalue_done <= 1'b0;
            end

        end
    end


    parameter IDLE  = 3'd0;
    parameter INIT  = 3'd1;
    parameter READ  = 3'd2;
    parameter CHECK = 3'd3;
    parameter DONE  = 3'd4;

    reg [2:0] state_init;
    reg idelay_init_done = 1'b0;

    integer check_time;

    reg [kCNTVALUEbit-1:0] cntvalue_out_level2;
    reg [kCNTVALUEbit-1:0] cntvalue_slave_out_level2;

    always @(posedge clkDivIn) begin
        if (pwrOnRst) begin
            state_init                 <= IDLE;
            //idelay_init_done           <= 1'b0;
            check_time                 <= 0;
        end
        else begin
            case (state_init)
                IDLE: begin
                    check_time <= 0;
                    if (idelay_init_done)begin
                        state_init <= DONE;
                    end
                    else begin
                        state_init <= INIT;
                    end
                end

                INIT: begin
                    check_time <= check_time + 1;
                    if (check_time == kCheckIdelayInit)begin
                        state_init <= READ;
                    end
                end

                READ: begin
                    if (readyCtrl && cntvalue_done) begin
                        cntvalue_out_level2        <= CNTVALUEOUT;
                        cntvalue_slave_out_level2  <= CNTVALUEOUT_slave;
                        state_init                 <= CHECK;
                    end else begin
                        state_init <= IDLE;
                    end
                end

                CHECK: begin
                    if ((cntvalue_out_level2        == 0) ||
                        (cntvalue_slave_out_level2  == 0) )begin
                        state_init <= IDLE;
                    end else begin
                        state_init <= DONE;
                    end
                end

                DONE: begin
                    idelay_init_done <= 1'b1;
                end

                default: begin
                    state_init <= IDLE;
                end
            endcase
        end
    end

    assign idelayInitDoneOut = idelay_init_done;
    assign cntValueOutLevel2Out = cntvalue_out_level2;
    assign cntValueSlaveOutLevel2Out = cntvalue_slave_out_level2;

//--------------------------------------------------------
//IDELAY
//--------------------------------------------------------

    wire idelay3_out;

    wire [kCNTVALUEbit-1:0] CNTVALUEIN;
    wire [kCNTVALUEbit-1:0] CNTVALUEIN_slave;
    wire [kCNTVALUEbit-1:0] CNTVALUEOUT_REFCLK;          //sync to REFCLK
    wire [kCNTVALUEbit-1:0] CNTVALUEOUT_slave_REFCLK;    //sync to REFCLK
    assign CNTVALUEIN = {tapIn, 4'h0};
    assign tapOut = CNTVALUEOUT[kCNTVALUEbit-1:tap_width-1];  //CNTVALUEOUT[8:4]
    assign CNTVALUEIN_slave = {tapIn, 4'h0};


    //slaveout refclk to clk_slow--------------------------
    reg [kCNTVALUEbit-1:0] CNTVALUEOUT_level0[1:0];
    reg [kCNTVALUEbit-1:0] CNTVALUEOUT_slave_level0[1:0];
    always@(posedge clkDivIn)begin
        CNTVALUEOUT_level0[0] <= CNTVALUEOUT_REFCLK;
        CNTVALUEOUT_level0[1] <=  CNTVALUEOUT_level0[0];
        CNTVALUEOUT_slave_level0[0] <= CNTVALUEOUT_slave_REFCLK;
        CNTVALUEOUT_slave_level0[1] <= CNTVALUEOUT_slave_level0[0];
    end

    assign CNTVALUEOUT = CNTVALUEOUT_level0[0];
    assign CNTVALUEOUT_slave = CNTVALUEOUT_slave_level0[0];

    wire CASC_OUT;
    wire CASC_RETURN;
    wire idelay_RST;
    assign idelay_RST = ioReset & idelay_init_done;

    (* IODELAY_GROUP = kIoDelayGroup *)
     IDELAYE3
       # (
         .CASCADE("MASTER"),
         .DELAY_FORMAT("TIME"),
         .DELAY_SRC              ("IDATAIN"),                          // IDATAIN, DATAIN
         .DELAY_TYPE            ("VAR_LOAD"),              // FIXED, VARIABLE, or VAR_LOADABLE
         .DELAY_VALUE           (kDELAY_VALUE),
         .REFCLK_FREQUENCY       (kFreqRefClk),
         .SIM_DEVICE            ("ULTRASCALE_PLUS")
       )
       idelaye3_bus_master(
         .CASC_OUT(CASC_OUT), // 1-bit output: Cascade delay output to ODELAY input cascade
         .CNTVALUEOUT(CNTVALUEOUT_REFCLK), // 9-bit output: Counter value output
         .DATAOUT(idelay3_out), // 1-bit output: Delayed data output
         .CASC_IN(1'b0), // 1-bit input: Cascade delay input from slave ODELAY CASCADE_OUT
         .CASC_RETURN(CASC_RETURN), // 1-bit input: Cascade delay returning from slave ODELAY DATAOUT
         .CE(ceIDelay), // 1-bit input: Active high enable increment/decrement input
         .CLK(clkDivIn), // 1-bit input: Clock input
         .CNTVALUEIN(CNTVALUEIN), // 9-bit input: Counter value input
         .DATAIN(1'b0), // 1-bit input: Data input from the logic
         .EN_VTC(enVtc),
         .IDATAIN(idelay_IDATAIN), // 1-bit input: Data input from the IOBUF
         .INC(incIDelay), // 1-bit input: Increment / Decrement tap delay input
         .LOAD(rstIDelay), // 1-bit input: Load DELAY_VALUE input
         .RST(idelay_RST) // 1-bit input: Asynchronous Reset to the DELAY_VALUE
      );

    (* IODELAY_GROUP = kIoDelayGroup *)
     ODELAYE3
       # (
         .CASCADE("SLAVE_END"),
         .DELAY_FORMAT("TIME"),
         .DELAY_TYPE            ("VAR_LOAD"),              // FIXED, VARIABLE, or VAR_LOADABLE
         .DELAY_VALUE           (kDELAY_VALUE),                  // 0 to 31
         .REFCLK_FREQUENCY       (kFreqRefClk),
         .SIM_DEVICE            ("ULTRASCALE_PLUS")
       )
       idelaye3_bus_slave(
         .CASC_OUT(), // 1-bit output: Cascade delay output to ODELAY input cascade
         .CNTVALUEOUT(CNTVALUEOUT_slave_REFCLK), // 9-bit output: Counter value output
         .DATAOUT(CASC_RETURN), // 1-bit output: Delayed data output
         .CASC_IN(CASC_OUT), // 1-bit input: Cascade delay input from slave ODELAY CASCADE_OUT
         .CASC_RETURN(1'b0), // 1-bit input: Cascade delay returning from slave ODELAY DATAOUT
         .CE(ceIDelay), // 1-bit input: Active high enable increment/decrement input
         .CLK(clkDivIn), // 1-bit input: Clock input
         .CNTVALUEIN(CNTVALUEIN_slave), // 9-bit input: Counter value input
         .EN_VTC(enVtc),
         .ODATAIN(),
         .INC(incIDelay), // 1-bit input: Increment / Decrement tap delay input
         .LOAD(rstIDelay), // 1-bit input: Load DELAY_VALUE input
         .RST(idelay_RST) // 1-bit input: Asynchronous Reset to the DELAY_VALUE
      );

//--------------------------------------------------------
//ISERDES
//--------------------------------------------------------

    wire [kDevW-1:0] iserdes_out;
    wire ISERDESE3_RST;
   ISERDESE3 #(
      .DATA_WIDTH(kDevW), // Parallel data width (4,8)
      .FIFO_ENABLE("FALSE"), // Enables the use of the FIFO
      .FIFO_SYNC_MODE("FALSE"), // Always set to FALSE. TRUE is reserved for later use.
      .IS_CLK_B_INVERTED(1'b0), // Optional inversion for CLK_B
      .IS_CLK_INVERTED(1'b0), // Optional inversion for CLK
      .IS_RST_INVERTED(1'b0), // Optional inversion for RST
      .SIM_DEVICE("ULTRASCALE_PLUS") // Set the device version (ULTRASCALE)
   )
   ISERDESE3_inst (
      .FIFO_EMPTY(), // 1-bit output: FIFO empty flag
      .INTERNAL_DIVCLK(), // 1-bit output: Internally divided down clock used when FIFO is
      // disabled (do not connect)
      .Q(iserdes_out[kDevW-1:0]), // 8-bit registered output
      .CLK(clkIn), // 1-bit input: High-speed clock
      .CLKDIV(clkDivIn), // 1-bit input: Divided Clock
      .CLK_B(~clkIn), // 1-bit input: Inversion of High-speed clock CLK
      .D(idelay3_out), // 1-bit input: Serial Data Input
      .FIFO_RD_CLK(1'b0), // 1-bit input: FIFO read clock
      .FIFO_RD_EN(1'b0), // 1-bit input: Enables reading the FIFO when asserted
      .RST(ISERDESE3_RST)
   );

    reg [7:0] ioReset_old;
    always@(posedge clkDivIn)begin
        ioReset_old[7:0] <= {ioReset_old[6:0], ioReset};
    end
    assign ISERDESE3_RST = (ioReset_old[7:0] != 8'hFF && ioReset_old[7:0] != 8'h00 && ioReset_old[7] == 1'b1) ? 1'b1 : 1'b0;



generate
  if (kBitslice0 == TRUE) begin : g_cdOutFromO_master

    reg virtual_clk;
    always@(posedge clkDivIn)begin
        if(iserdes_out != 8'hFF && iserdes_out != 8'h00)begin
            virtual_clk <= ~virtual_clk;
        end
    end

    assign cdOutFromO = virtual_clk;

  end else begin : g_cdOutFromO_slave

    assign cdOutFromO = data_in_from_pin_P;
  end

endgenerate


    wire [kDevW-1:0] iserdes_out_level2;

    genvar j;

    generate
    if (kBitslice0 == TRUE) begin : g_serdesout_kBitslice0
        for (j = 0; j < kDevW; j = j + 1) begin : j_loop
            //When (kBitslice0 == TRUE), the iserdes_out polarity is not inverted.
            if (kRxPolarity == "FALSE") begin
                assign iserdes_out_level2[j] = iserdes_out[j];
            end
            else begin
                assign iserdes_out_level2[j] = ~iserdes_out[j];
            end
    end
    end else begin : g_serdesout

        for (j = 0; j < kDevW; j = j + 1) begin : j_loop
            //When (kBitslice0 == False), the iserdes_out polarity is inverted
            //Therefore, we need inveter for iserdes_out.
            if (kRxPolarity == "FALSE") begin
                assign iserdes_out_level2[j] = ~iserdes_out[j];
            end
            else begin
                assign iserdes_out_level2[j] = iserdes_out[j];
            end
        end
    end
    endgenerate

    reg [kDevW-1:0] iserdes_out_level2_old;
    reg [kDevW-1:0] iserdes_out_level2_old2;

    always@(posedge clkDivIn)begin
        iserdes_out_level2_old[kDevW-1:0]  <= iserdes_out_level2[kDevW-1:0] ;
        iserdes_out_level2_old2[kDevW-1:0]  <= iserdes_out_level2_old[kDevW-1:0] ;
    end

    reg [kSelCount-1:0] sel_MP;
    always@(posedge clkDivIn)begin
        if(ioReset)begin
            sel_MP[kSelCount-1:0] <= 0;
        end
        else if(bitslip)begin
            sel_MP[kSelCount-1:0] <= sel_MP[kSelCount-1:0] + 1'b1;
        end
    end

    wire [kDevW-1:0] iserdes_out_level3[kDevW-1:0];

    assign iserdes_out_level3[0][kDevW-1:0] = iserdes_out_level2_old[kDevW-1:0];
    genvar i;
    generate
        for (i = 1; i < kDevW; i = i + 1) begin : MP_loop
            assign iserdes_out_level3[i][kDevW-1:0] = {iserdes_out_level2_old[kDevW-1-i:0],iserdes_out_level2_old2[kDevW-1:kDevW-i]};
        end
    endgenerate

    assign dOutToDevice[kDevW-1:0] = iserdes_out_level3[sel_MP][kDevW-1:0];


endmodule
