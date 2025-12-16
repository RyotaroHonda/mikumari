library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library mylib;
use mylib.defCDCM.all;

-- ----------------------------------------------------------------------------------
-- == Clock network ==
-- Master (recovery) clock ---> BUFG ---> clkPar
-- Fast clock              ---> BUFG ---> clkSer
-- (Fast clock is 5x faster than master clock)
-- Skew of these clocks must be adjusted.
--
-- selMode:
--   Select Tx operation mode.
--   "00": Normal mode. Transmit wfPattern.
--   "01": CDCM initialization mode. Transmit  B00001_11111
--   "10": Idle mode. Transmit idle pattern of B00000_11111.
--   "11": Disable Tx. Transmit all zero pattern.
-- ----------------------------------------------------------------------------------

entity CdcmTx is
  generic
  (
    kFamily        : string;
    kIoStandard    : string;  -- IOSTANDARD of OBUFDS
    kTxPolarity    : boolean; -- true: inverse polarity
    kCdcmModWidth  : integer  -- # of time slices of the CDCM signal
  );
  port
  (
    -- SYSTEM port --
    srst        : in std_logic; -- Asynchronous assert, synchronous de-assert reset. (active high)
    clkSer      : in std_logic; -- From BUFG (5 x clkPar freq.)
    clkPar      : in std_logic; -- From BUFG
    selMode     : in TxModeType; -- Select operation mode (async)
    offsetTable : out SerdesOffsetType;

    -- CDCM output port --
    TXP         : out std_logic; -- Connect to TOPLEVEL port
    TXN         : out std_logic; -- Connect to TOPLEVEL port
    wfPattern   : in  CdcmPatternType -- CDCM waveform pattern
  );
end CdcmTx;

architecture RTL of CdcmTx is
  -- OSERDES --
  signal running_disparity    : std_logic:= '0';
  signal reg_init_patt        : CdcmPatternType;

  signal original_pattern     : CdcmPatternType;
  signal din_oserdes          : CdcmPatternType;
  constant kInverse           : CdcmPatternType:= (others => '1');

--debug
  attribute mark_debug : boolean;
  attribute mark_debug of original_pattern : signal is true;
  attribute mark_debug of selMode : signal is true;
  attribute mark_debug of srst : signal is true;
  attribute mark_debug of wfPattern : signal is true;

begin
  -- ======================================================================
  --                                 body
  -- ======================================================================

  u_disparity : process(clkPar)
  begin
    if(clkPar'event and clkpar = '1') then
      running_disparity   <= not running_disparity;

      if(running_disparity = '0') then
        reg_init_patt   <= kInitMCDCM;
      else
        reg_init_patt   <= kInitPCDCM;
      end if;
    end if;
  end process;

  original_pattern <=  kAllZeroCDCM   when(selMode = kDisaTx) else
                       kIdleCDCM      when(selMode = kIdleTx) else
                       reg_init_patt  when(selMode = kInitTx) else
                       wfPattern      when(selMode = kNormalTx) else
                       wfPattern;

  gen_invin : if kTxPolarity = TRUE generate
  begin
    din_oserdes   <= original_pattern xor kInverse;
  end generate;

  gen_in : if kTxPolarity = FALSE generate
  begin
      din_oserdes   <= original_pattern;
  end generate;

  gen_cdcm10 : if kCdcmModWidth = 10 generate
    u_cdcm_tx_oserdes : entity mylib.CdcmTxImpl
      generic map
      (-- width of the data for the system
        kSysW       => kWidthSys,
        -- width of the data for the device
        kDevW       => kWidthDev,
        -- IOSTANDARD
        kIoStandard => kIoStandard
      )
      port map
      (
        -- From the device out to the system
        dInFromDevice   => din_oserdes,
        dOutToPinP      => TXP,
        dOutToPinN      => TXN,

        -- Phase Offset --
        offsetTable     => offsetTable,
        scanFinished    => open,

        -- Clock and reset signals
        clkIn           => clkSer,
        clkDivIn        => clkPar,
        ioReset         => srst
      );
  end generate;

  gen_cdcm8 : if kCdcmModWidth = 8 generate

    g_us : if kFamily = "US" generate
    begin

      u_cdcm_tx_oserdes : entity mylib.Cdcm8TxImpl_US
        generic map
        (-- width of the data for the system
          kSysW       => kWidthSys,
          -- width of the data for the device
          kDevW       => kWidthDev-2,
          -- IOSTANDARD
          kIoStandard => kIoStandard
        )
        port map
        (
          -- From the device out to the system
          dInFromDevice   => din_oserdes(8 downto 1),
          dOutToPinP      => TXP,
          dOutToPinN      => TXN,

          -- Phase Offset --
          offsetTable     => offsetTable,
          scanFinished    => open,

          -- Clock and reset signals
          clkIn           => clkSer,
          clkDivIn        => clkPar,
          ioReset         => srst
        );
    end generate;

    g_7s : if kFamily = "7S" generate
    begin

      u_cdcm_tx_oserdes : entity mylib.Cdcm8TxImpl
        generic map
        (-- width of the data for the system
          kSysW       => kWidthSys,
          -- width of the data for the device
          kDevW       => kWidthDev-2,
          -- IOSTANDARD
          kIoStandard => kIoStandard
        )
        port map
        (
          -- From the device out to the system
          dInFromDevice   => din_oserdes(8 downto 1),
          dOutToPinP      => TXP,
          dOutToPinN      => TXN,

          -- Phase Offset --
          offsetTable     => offsetTable,
          scanFinished    => open,

          -- Clock and reset signals
          clkIn           => clkSer,
          clkDivIn        => clkPar,
          ioReset         => srst
        );
    end generate;

  end generate;

end RTL;
