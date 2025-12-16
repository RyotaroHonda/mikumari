library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

Library UNISIM;
use UNISIM.vcomponents.all;

library UNIMACRO;
use UNIMACRO.Vcomponents.all;

library mylib;
use mylib.defCDCM.all;

--

entity Cdcm8TxImpl_7s is
  generic
  (
    kSysW        : integer:= 1;  -- width of the ata for the system
    kDevW        : integer:= 8; -- width of the ata for the device
    kIoStandard  : string:= "LVDS" -- IOSTANDARD of OBUFDS
  );
  port
  (
    -- From the device to the system
    dInFromDevice   : in std_logic_vector(kDevW-1 downto 0);
    dOutToPinP      : out std_logic;
    dOutToPinN      : out std_logic;
    -- Phase Offset --
    offsetTable     : out SerdesOffsetType;
    scanFinished    : out std_logic;
    -- Clock and reset
    clkIn           : in std_logic;
    clkDivIn        : in std_logic;
    ioReset         : in std_logic
  );
end Cdcm8TxImpl_7s;

architecture RTL of Cdcm8TxImpl_7s is
  constant kMaxBit  : integer:= 14;
  signal din_oserdes          : std_logic_vector(kMaxBit-1 downto 0);
  signal reg_din_from_device  : std_logic_vector(dInFromDevice'range);
  signal din_from_device      : std_logic_vector(dInFromDevice'range);
  signal ocascade_sm_d, ocascade_sm_t : std_logic;

  signal  data_out_to_pin   : std_logic;

  -- Feedback -------------------------------------------------------
  signal clk_in, clk_in_inv   : std_logic;
  signal feedback_out : std_logic;
  signal iserdes_q    : std_logic_vector(13 downto 0);
  signal rx_output    : std_logic_vector(dInFromDevice'range);

  signal reg_scan_finished    : std_logic;
  signal set_additional_delay : std_logic;
  signal waveform_in          : std_logic_vector(dInFromDevice'range);
  signal reg_iserdes_out      : std_logic_vector(dInFromDevice'range);
  signal bit_slip             : std_logic;

  signal coarse_count         : signed(kWidthScanTdc-1 downto 0);
  signal tdc_coarse           : signed(kWidthScanTdc-1 downto 0);
  signal tdc_fine             : signed(kWidthScanTdc-1 downto 0);
  signal reg_tdc              : SerdesOffsetType;
  signal reg_reftdc           : signed(kWidthScanTdc-1 downto 0);
  signal serdes_latency       : signed(kWidthScanTdc-1 downto 0);
  signal reg_offset           : SerdesOffsetType;

  type ScanStateType is (Idle, MeasureTdc, BitSlip, WaitState, CalcOffset, Done);
  signal state_scan : ScanStateType;

--  attribute mark_debug  : string;
--  attribute mark_debug of waveform_in : signal is "true";
--  attribute mark_debug of rx_output   : signal is "true";
--  attribute mark_debug of bit_slip    : signal is "true";
--  attribute mark_debug of state_scan  : signal is "true";
--  attribute mark_debug of reg_tdc     : signal is "true";
--  attribute mark_debug of reg_offset  : signal is "true";

begin

  u_Tx_OBUFDS_inst : OBUFDS
    generic map
    (
      IOSTANDARD => kIoStandard, -- Specify the output I/O standard
      SLEW       => "FAST"     -- Specify the output slew rate
    )
    port map
    (
      O  => dOutToPinP,      -- Diff_p output (connect directly to top-level port)
      OB => dOutToPinN,      -- Diff_n output (connect directly to top-level port)
      I  => data_out_to_pin  -- Buffer input
    );



  u_OSERDESE2_master : OSERDESE2
    generic map (
       DATA_RATE_OQ => "DDR",    -- DDR, SDR
       DATA_RATE_TQ => "SDR",    -- DDR, BUF, SDR
       DATA_WIDTH   => kDevW,    -- Parallel data width (2-8,10,14)
       SERDES_MODE  => "MASTER", -- MASTER, SLAVE
       TRISTATE_WIDTH => 1       -- 3-state converter width (1,4)
    )
    port map (
       OFB => feedback_out,             -- 1-bit output: Feedback path for data
       OQ => data_out_to_pin,               -- 1-bit output: Data path output
       -- SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
       SHIFTOUT1 => open,
       SHIFTOUT2 => open,
       TBYTEOUT => open,   -- 1-bit output: Byte group tristate
       TFB => open,             -- 1-bit output: 3-state control
       TQ => open,               -- 1-bit output: 3-state control
       CLK => clkIn,             -- 1-bit input: High speed clock
       CLKDIV => clkDivIn,       -- 1-bit input: Divided clock
       -- D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
       D1 => din_oserdes(13),
       D2 => din_oserdes(12),
       D3 => din_oserdes(11),
       D4 => din_oserdes(10),
       D5 => din_oserdes(9),
       D6 => din_oserdes(8),
       D7 => din_oserdes(7),
       D8 => din_oserdes(6),
       OCE => '1',             -- 1-bit input: Output data clock enable
       RST => ioReset,             -- 1-bit input: Reset
       -- SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
       SHIFTIN1 => '0',
       SHIFTIN2 => '0',
       -- T1 - T4: 1-bit (each) input: Parallel 3-state inputs
       T1 => '0',
       T2 => '0',
       T3 => '0',
       T4 => '0',
       TBYTEIN => '0',     -- 1-bit input: Byte group tristate
       TCE => '0'              -- 1-bit input: 3-state clock enable
    );


  u_extra_delay : process(clkDivIn)
  begin
    if(clkDivIn'event and clkDivIn = '1') then
      if(set_additional_delay = '1') then
        reg_din_from_device   <= dInFromDevice;
      end if;
    end if;
  end process;

  din_from_device   <= reg_din_from_device when(set_additional_delay = '1') else dInFromDevice;

  u_swap : for i in 0 to kDevW-1 generate
  begin
    din_oserdes(kMaxBit-i-1)     <= waveform_in(kDevW-1-i) when(reg_scan_finished = '0') else din_from_device(i);
    rx_output(i)   <= iserdes_q(i);
  end generate;
  din_oserdes(kMaxBit-kDevW-1 downto 0)  <= (others => '0');

  -- Feedback ISERDES --------------------------------------------------------
  clk_in      <= clkIn;
  clk_in_inv  <= not clkIn;

  offsetTable   <= reg_offset;
  scanFinished  <= reg_scan_finished;

  u_ISERDESE2_FB : ISERDESE2
    generic map (
       DATA_RATE          => "DDR",         -- DDR, SDR
       DATA_WIDTH         => kDevW,         -- Parallel data width (2-8,10,14)
       DYN_CLKDIV_INV_EN  => "FALSE",       -- Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
       DYN_CLK_INV_EN     => "FALSE",       -- Enable DYNCLKINVSEL inversion (FALSE, TRUE)
       INTERFACE_TYPE     => "NETWORKING",  -- MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
       IOBDELAY           => "NONE",         -- NONE, BOTH, IBUF, IFD
       NUM_CE             => 2,             -- Number of clock enables (1,2)
       OFB_USED           => "TRUE",       -- Select OFB path (FALSE, TRUE)
       SERDES_MODE        => "MASTER"       -- MASTER, SLAVE
    )
    port map (
       O => open,                       -- 1-bit output: Combinatorial output
       -- Q1 - Q8: 1-bit (each) output: Registered data outputs
       Q1 => iserdes_q(0),
       Q2 => iserdes_q(1),
       Q3 => iserdes_q(2),
       Q4 => iserdes_q(3),
       Q5 => iserdes_q(4),
       Q6 => iserdes_q(5),
       Q7 => iserdes_q(6),
       Q8 => iserdes_q(7),
       -- SHIFTOUT1, SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
       SHIFTOUT1 => open,
       SHIFTOUT2 => open,
       BITSLIP => bit_slip,           -- 1-bit input: The BITSLIP pin performs a Bitslip operation synchronous to
                                     -- CLKDIV when asserted (active High). Subsequently, the data seen on the
                                     -- Q1 to Q8 output ports will shift, as in a barrel-shifter operation, one
                                     -- position every time Bitslip is invoked (DDR operation is different from
                                     -- SDR).

       -- CE1, CE2: 1-bit (each) input: Data register clock enable inputs
       CE1 => '1',
       CE2 => '1',
       CLKDIVP => '0',           -- 1-bit input: TBD
       -- Clocks: 1-bit (each) input: ISERDESE2 clock input ports
       CLK => clk_in,                   -- 1-bit input: High-speed clock
       CLKB => clk_in_inv,                 -- 1-bit input: High-speed secondary clock
       CLKDIV => clkDivIn,             -- 1-bit input: Divided clock
       OCLK => '0',                 -- 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY"
       -- Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
       DYNCLKDIVSEL => '0', -- 1-bit input: Dynamic CLKDIV inversion
       DYNCLKSEL => '0',       -- 1-bit input: Dynamic CLK/CLKB inversion
       -- Input Data: 1-bit (each) input: ISERDESE2 data input ports
       D => '0',                       -- 1-bit input: Data input
       DDLY => '0',                 -- 1-bit input: Serial data from IDELAYE2
       OFB => feedback_out,                   -- 1-bit input: Data feedback from OSERDESE2
       OCLKB => '0',               -- 1-bit input: High speed negative edge output clock
       RST => ioReset,                   -- 1-bit input: Active high asynchronous reset
       -- SHIFTIN1, SHIFTIN2: 1-bit (each) input: Data width expansion input ports
       SHIFTIN1 => '0',
       SHIFTIN2 => '0'
    );

  u_scan_fasm : process(ioReset, clkDivIn)
    variable bitslip_count  : integer range -1 to kDevW:=0;
    variable wait_count     : integer range -1 to 24:=0;
    variable tmp_coarse     : signed(tdc_coarse'range);
  begin
    if(ioReset = '1') then
      waveform_in           <= X"F0";
      bitslip_count         := 0;
      wait_count            := 23;
      bit_slip              <= '0';
      reg_scan_finished     <= '0';
      set_additional_delay  <= '0';
      state_scan            <= Idle;
    elsif(clkDivIn'event and clkDivIn = '1') then
      case state_scan is
        when Idle =>
          reg_scan_finished   <= '0';
          wait_count          := wait_count-1;
          if(wait_count = 0) then
            reg_iserdes_out   <= rx_output;
            waveform_in       <= X"F8";
            coarse_count      <= (others => '0');
            state_scan        <= MeasureTdc;
          end if;

        when MeasureTdc =>
          coarse_count  <= coarse_count +1;
          if(reg_iserdes_out /= rx_output) then
            tdc_fine    <= TdcFineCount(rx_output);
            tdc_coarse  <= coarse_count;
            state_scan  <= BitSlip;
          end if;

        when BitSlip =>
          tmp_coarse  := tdc_coarse(tdc_coarse'high-3 downto 0) & "000"; -- Multiply 8
          reg_tdc(bitslip_count)   <= tmp_coarse + tdc_fine;
          if(rx_output = X"F8") then
            reg_reftdc      <= tmp_coarse + tdc_fine;
            serdes_latency  <= tdc_coarse;
          end if;

          tdc_coarse    <= (others => '0');
          coarse_count  <= (others => '0');
          waveform_in   <= X"F0";
          if(bitslip_count = 7) then
            state_scan  <= CalcOffset;
          else
            bitslip_count := bitslip_count +1;
            bit_slip    <= '1';
            wait_count  := 23;
            state_scan  <= WaitState;
          end if;

        when WaitState =>
          bit_slip  <= '0';
          if(wait_count = 0) then
            reg_iserdes_out <= rx_output;
            waveform_in     <= X"F8";
            state_scan      <= MeasureTdc;
          end if;
          wait_count  := wait_count -1;

        when CalcOffset =>
          for i in 0 to kDevW-1 loop
            reg_offset(i)   <= reg_tdc(i) - reg_reftdc;
          end loop;
          if(to_integer(serdes_latency) /= kRefLatency) then
            set_additional_delay  <= '1';
          end if;
          state_scan  <= Done;

        when Done =>
          reg_scan_finished   <= '1';

        when others =>
          state_scan  <= Idle;

      end case;
    end if;
  end process;


end RTL;