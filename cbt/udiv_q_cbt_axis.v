// ============================================================================
// udiv_q_axis.v  (AXIS-like, separate ports)
// Unsigned DW/DW -> QI.QF fixed-point quotient
// - No DSPs (shift/compare/sub only), latency = QI+QF cycles
// - Input handshake:  s_axis_tvalid & s_axis_tready
// - Output handshake: m_axis_tvalid & m_axis_tready  
// ============================================================================
module udiv_q_cbt_axis #(
    parameter integer DW = 16,  // dividend/divisor/remainder width
    parameter integer QI = 16,  // integer bits of quotient
    parameter integer QF = 8    // fractional bits of quotient
)(
    input  wire                 clk,
    input  wire                 rst,

    // Input AXIS-like (separate signals)
    input  wire                 s_axis_tvalid,
    output wire                 s_axis_tready,
    input  wire [DW-1:0]        s_axis_dividend,
    input  wire [DW-1:0]        s_axis_divisor,

    // Output AXIS-like
    output wire                 m_axis_tvalid,
    input  wire                 m_axis_tready,   // tie to 1'b1 if no backpressure
    output wire                 m_axis_div_by_zero,
    output wire [QI-1:0]        m_axis_q_int,
    output wire [QF-1:0]        m_axis_q_frac,
    output wire [DW-1:0]        m_axis_remainder
);
    // Core I/F
    wire                core_busy, core_valid, core_dz;
    wire [QI-1:0]       core_qi;
    wire [QF-1:0]       core_qf;
    wire [DW-1:0]       core_rem;

    // Input ready when core is idle and no pending output
    reg out_hold_valid;
    assign s_axis_tready = (!core_busy) && (!out_hold_valid);

    // Start pulse on accept
    wire in_fire = s_axis_tvalid && s_axis_tready;
    reg  core_start;
    always @(posedge clk) begin
        if (rst) core_start <= 1'b0;
        else     core_start <= in_fire; // 1-cycle pulse
    end

    // Core divider (iterative, truncate fractional part)
    udiv_cbt_q_V2 #(
        .DW(DW), .QI(QI), .QF(QF)
    ) core (
        .clk       (clk),
        .rst       (rst),
        .start     (core_start),
        .dividend  (s_axis_dividend),
        .divisor   (s_axis_divisor),
        .busy      (core_busy),
        .valid     (core_valid),
        .div_by_zero(core_dz),
        .q_int     (core_qi),
        .q_frac    (core_qf),
        .remainder (core_rem)
    );

    // 1-deep output holding register (skid)
    reg                 hold_dz;
    reg [QI-1:0]        hold_qi;
    reg [QF-1:0]        hold_qf;
    reg [DW-1:0]        hold_rem;

    assign m_axis_tvalid      = out_hold_valid;
    assign m_axis_div_by_zero = hold_dz;
    assign m_axis_q_int       = hold_qi;
    assign m_axis_q_frac      = hold_qf;
    assign m_axis_remainder   = hold_rem;

    wire out_fire = m_axis_tvalid && m_axis_tready;

    always @(posedge clk) begin
        if (rst) begin
            out_hold_valid <= 1'b0;
            hold_dz        <= 1'b0;
            hold_qi        <= {QI{1'b0}};
            hold_qf        <= {QF{1'b0}};
            hold_rem       <= {DW{1'b0}};
        end else begin
            if (out_fire)
                out_hold_valid <= 1'b0;

            if (core_valid) begin
                out_hold_valid <= 1'b1;
                hold_dz        <= core_dz;
                hold_qi        <= core_qi;
                hold_qf        <= core_qf;
                hold_rem       <= core_rem;
            end
        end
    end
endmodule
