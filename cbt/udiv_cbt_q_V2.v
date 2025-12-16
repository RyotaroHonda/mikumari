
// ============================================================================
// udiv_q.v  (core)
// Unsigned DW/DW -> QI.QF (truncate). Latency = QI+QF cycles.
// No DSPs; shift/compare/sub only. Verilog-2001 friendly.
// ============================================================================
module udiv_cbt_q_V2 #(
    parameter integer DW = 16,
    parameter integer QI = 16,
    parameter integer QF = 8
)(
    input  wire                clk,
    input  wire                rst,        // sync reset, active-high
    input  wire                start,      // 1-cycle pulse when idle
    input  wire [DW-1:0]       dividend,   // unsigned
    input  wire [DW-1:0]       divisor,    // unsigned
    output reg                 busy,
    output reg                 valid,
    output reg                 div_by_zero,
    output reg  [QI-1:0]       q_int,
    output reg  [QF-1:0]       q_frac,
    output reg  [DW-1:0]       remainder
);
    localparam integer QW   = QI + QF;     // total quotient bits
    localparam integer NUMW = DW + QF;     // scaled dividend width
    localparam integer REMW = DW + 1;      // remainder width (+1 for compare)

    localparam integer CW = (QW > 1) ? $clog2(QW+1) : 1;

    reg [CW-1:0]     cnt;
    reg [NUMW-1:0]   num;     // (dividend << QF)
    reg [REMW-1:0]   rem;     // running remainder
    reg [QW-1:0]     quo;     // building quotient (MSB-first)

    // temps (declare outside always for Verilog-2001)
    reg [REMW-1:0]   rem_shift;
    reg [NUMW-1:0]   num_shift;
    reg [REMW-1:0]   d_wide;

    wire start_ok        = (!busy) && start;
    wire divisor_is_zero = (divisor == {DW{1'b0}});

    always @(posedge clk) begin
        if (rst) begin
            busy        <= 1'b0;
            valid       <= 1'b0;
            div_by_zero <= 1'b0;
            cnt         <= {CW{1'b0}};
            num         <= {NUMW{1'b0}};
            rem         <= {REMW{1'b0}};
            quo         <= {QW{1'b0}};
            q_int       <= {QI{1'b0}};
            q_frac      <= {QF{1'b0}};
            remainder   <= {DW{1'b0}};
        end else begin
            valid <= 1'b0;

            if (start_ok) begin
                busy        <= 1'b1;
                div_by_zero <= divisor_is_zero;
                num         <= {dividend, {QF{1'b0}}}; // scale x 2^QF
                rem         <= {REMW{1'b0}};
                quo         <= {QW{1'b0}};
                cnt         <= QW[CW-1:0];
            end else if (busy) begin
                if (div_by_zero) begin
                    // keep timing uniform; emit zeros at end
                    if (cnt != 0) begin
                        cnt <= cnt - 1'b1;
                    end else begin
                        busy      <= 1'b0;
                        valid     <= 1'b1;
                        q_int     <= {QI{1'b0}};
                        q_frac    <= {QF{1'b0}};
                        remainder <= {DW{1'b0}};
                    end
                end else begin
                    // shift-in next bit and compare/sub
                    rem_shift = {rem[REMW-2:0], num[NUMW-1]};
                    num_shift = {num[NUMW-2:0], 1'b0};
                    d_wide    = {1'b0, divisor};

                    if (rem_shift >= d_wide) begin
                        rem <= rem_shift - d_wide;
                        quo <= {quo[QW-2:0], 1'b1};
                    end else begin
                        rem <= rem_shift;
                        quo <= {quo[QW-2:0], 1'b0};
                    end
                    num <= num_shift;

                    if (cnt != 0) begin
                        cnt <= cnt - 1'b1;
                    end else begin
                        busy    <= 1'b0;
                        valid   <= 1'b1;
                        q_int   <= quo[QW-1:QF];
                        q_frac  <= quo[QF-1:0];
                        remainder <= rem[DW-1:0];
                    end
                end
            end
        end
    end
endmodule
