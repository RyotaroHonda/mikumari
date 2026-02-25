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

entity Cdcm8TxImpl is
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
end Cdcm8TxImpl;

architecture RTL of Cdcm8TxImpl is
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
      reg_din_from_device   <= dInFromDevice;
    end if;
  end process;

  din_from_device   <= dInFromDevice;

  u_swap : for i in 0 to kDevW-1 generate
  begin
    din_oserdes(kMaxBit-i-1)     <= din_from_device(i);
  end generate;
  din_oserdes(kMaxBit-kDevW-1 downto 0)  <= (others => '0');

  -- Feedback ISERDES --------------------------------------------------------
  clk_in      <= clkIn;
  clk_in_inv  <= not clkIn;

  offsetTable(0) <= x"FD";
  offsetTable(1) <= x"FE";
  offsetTable(2) <= x"FF";
  offsetTable(3) <= x"00";
  offsetTable(4) <= x"01";
  offsetTable(5) <= x"02";
  offsetTable(6) <= x"03";
  offsetTable(7) <= x"04";  
  
  scanFinished  <= '1';



end RTL;
