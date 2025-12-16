library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_MISC.ALL;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.VComponents.all;

library mylib;
use mylib.defCDCM.all;
use mylib.defMikumari.all;

entity MikumariBlock is
  generic (
    kFamily          : string;
    -- CBT generic -------------------------------------------------------------
    -- CDCM-Mod-Pattern --
    kCdcmModWidth    : integer; -- # of time slices of the CDCM signal
    -- CDCM-TX --
    kIoStandardTx    : string;  -- IO standard of OBUFDS
    kTxPolarity      : boolean; -- If true, inverse Tx polarity
    -- CDCM-RX --
    genIDELAYCTRL    : boolean; -- If TRUE, IDELAYCTRL is instantiated.
    kDiffTerm        : boolean; -- IBUF DIFF_TERM
    kRxPolarity      : boolean; -- If true, inverts Rx polarity
    kIoStandardRx    : string;  -- IOSTANDARD of IBUFDS
    kIoDelayGroup    : string;  -- IODELAY_GROUP for IDELAYCTRL and IDELAY
    kFixIdelayTap    : boolean; -- If TRUE, value on tapValueIn is set to IDELAY
    kFreqFastClk     : real;    -- Frequency of SERDES fast clock (MHz).
    kFreqRefClk      : real;    -- Frequency of refclk for IDELAYCTRL (MHz).
    kBitslice0       : boolean;
    -- Encoder/Decoder
    kNumEncodeBits   : integer:= 2;  -- 1:CDCM-10-1.5 or 2:CDCM-10-2.5
    -- Master/Slave
    kCbtMode         : string;
    -- DEBUG --
    enDebugCBT       : boolean:= false;

    -- MIKUMARI generic --------------------------------------------------------
    enScrambler      : boolean:= true;
    kHighPrecision   : boolean:= false;
    -- DEBUG --
    enDebugMikumari  : boolean:= false
  );
  Port (
    -- System ports -----------------------------------------------------------
    rst           : in std_logic;          -- Asynchronous reset input
    pwrOnRst      : in std_logic;          -- Reset logics driven by clkIndep and clkIdctrl
    clkSerTx      : in std_logic;          -- Slow clock
    clkSerRx      : in std_logic;          -- Slow clock
    clkPar        : in std_logic;          -- Fast clock
    clkIndep      : in std_logic;          -- Independent clock for monitor in CBT
    clkIdctrl     : in std_logic;          -- Reference clock for IDELAYCTRL (if exist)
    initIn        : in std_logic;          -- Redo the initialize process
    tapValueIn    : in std_logic_vector(kWidthTap-1 downto 0); -- IDELAY TAP value input (active when kFixIdelayTap is true)

    TXP           : out std_logic;         -- CDCM TXP port. Connect to toplevel port
    TXN           : out std_logic;         -- CDCM TXN port. Connect to toplevel port
    RXP           : in std_logic;          -- CDCM RXP port. Connect to toplevel port
    RXN           : in std_logic;          -- CDCM RXN port. Connect to toplevel port
    modClk        : out std_logic;         -- Modulated clock output
    txBeat        : out std_logic;

    -- CBT ports ------------------------------------------------------------
    laneUp        : out std_logic;         -- CBT link connection is established
    idelayErr     : out std_logic;         -- Attempted bitslip but the expected pattern was not found.
    bitslipErr    : out std_logic;         -- Bit pattern which does not match the CDCM rule is detected.
    pattErr       : out std_logic;         -- CDCM waveform pattern is broken
    watchDogErr   : out std_logic;         -- Watchdog timer alert

    tapValueOut   : out std_logic_vector(kWidthTap-1 downto 0); -- IDELAY TAP value output
    bitslipNum    : out std_logic_vector(kWidthBitSlipNum-1 downto 0); -- Number of bitslip made
    serdesOffset  : out signed(kWidthSerdesOffset-1 downto 0);
    firstBitPatt  : out CdcmPatternType; -- ISERDES output pattern after finishing the idelay adjustment
    cntValueOutInit : out std_logic_vector(kCNTVALUEbit-1 downto 0);
    cntValueOutSlaveInit : out std_logic_vector(kCNTVALUEbit-1 downto 0);

    -- Mikumari ports -------------------------------------------------------
    linkUp        : out std_logic;         -- MIKUMARI link connection is established

    -- Data IF TX --
    dataInTx      : in CbtUDataType;       -- User data input.
    validInTx     : in std_logic;          -- Indicate dataIn is valid.
    frameLastInTx : in std_logic;          -- Indicate current dataIn is a last character in a normal frame.
    txAck         : out std_logic;         -- Acknowledge to validIn signal.

    pulseIn       : in std_logic;          -- Pulse input. Must be one-shot signal.
    pulseTypeTx   : in MikumariPulseType;  -- 3-bit short message to be sent with pulse.
    pulseRegTx    : in MikumariHpmRegType; -- 4-bit additional message transferred by the pulse
    busyPulseTx   : out std_logic;         -- Under transmission of previous pulse. If high, pulseIn is ignored.

    -- Data IF RX --
    dataOutRx     : out CbtUDataType;      -- User data output.
    validOutRx    : out std_logic;         -- Indicate current dataOut is valid.
    frameLastRx   : out std_logic;         -- Indicate current dataOut is the last data in a normal frame.
    checksumErr   : out std_logic;         -- Check-sum error is happened in the present normal frame.
    frameBroken   : out std_logic;           -- Frame start position is not correctly detected
    recvTermnd    : out std_logic;           -- Frame end position of the previsou frame is not correctly detected

    pulseOut      : out std_logic;         -- Reproduced one-shot pulse output.
    pulseTypeRx   : out MikumariPulseType; -- Short message accompanying the pulse.
    pulseRegRx    : out MikumariHpmRegType -- 4-bit additional message transferred by the pulse

  );
end MikumariBlock;

architecture Behavioral of MikumariBlock is
  attribute mark_debug : string;

  -- System --
  signal sync_reset           : std_logic;
  constant kWidthResetSync    : integer:= 16;
  signal reset_shiftreg       : std_logic_vector(kWidthResetSync-1 downto 0);

  attribute async_reg : string;
  attribute async_reg of u_sync_reset : label is "true";

  -- CBT --
  signal cbt_lane_up          : std_logic;

  signal data_tx, data_rx     : CbtUDataType;
  signal valid_tx, valid_rx   : std_logic;
  signal is_idle_rx, is_ktype_rx, is_ktype_tx  : std_logic;
  signal tx_beat, tx_ack      : std_logic;
  signal idelay_error         : std_logic;
  signal bitslip_error        : std_logic;
  signal pattern_error        : std_logic;
  signal watchdog_error       : std_logic;

begin
  -- ===================================================================================
  -- body
  -- ===================================================================================

  txBeat        <= tx_beat;

  laneUp        <= cbt_lane_up;

  idelayErr     <= idelay_error;
  bitslipErr    <= bitslip_error;
  pattErr       <= pattern_error;
  watchDogErr   <= watchdog_error;


  u_CbtLane : entity mylib.CbtLane
    generic map
    (
      kFamily          => kFamily,
      -- CDCM-Mod-Pattern --
      kCdcmModWidth    => kCdcmModWidth,
      -- CDCM-TX --
      kIoStandardTx    => kIoStandardTx,
      kTxPolarity      => kTxPolarity,
      -- CDCM-RX --
      genIDELAYCTRL    => genIDELAYCTRL,
      kDiffTerm        => kDiffTerm,
      kRxPolarity      => kRxPolarity,
      kIoStandardRx    => kIoStandardRx,
      kIoDelayGroup    => kIoDelayGroup,
      kFixIdelayTap    => kFixIdelayTap,
      kFreqFastClk     => kFreqFastClk,
      kFreqRefClk      => kFreqRefClk,
      kBitslice0       => kBitslice0,
      -- Encoder/Decoder
      kNumEncodeBits   => kNumEncodeBits,
      -- Master/Slave
      kCbtMode         => kCbtMode,
      -- DEBUG --
      enDEBUG          => enDebugCBT
    )
  port map
    (
      -- SYSTEM port --
      srst          => sync_reset,
      pwrOnRst      => pwrOnRst,
      clkSerTx      => clkSerTx,
      clkSerRx      => clkSerRx,
      clkPar        => clkPar,
      clkIndep      => clkIndep,
      clkIdelayRef  => clkIdctrl,
      initIn        => initIn,
      tapValueIn    => tapValueIn,

      -- Status --
      cbtLaneUp     => cbt_lane_up,
      tapValueOut   => tapValueOut,
      bitslipNum    => bitslipNum,
      serdesOffset  => serdesOffset,
      firstBitPatt  => firstBitPatt,
      cntValueOutInit => cntValueOutInit,
      cntValueOutSlaveInit => cntValueOutSlaveInit,

      -- Error --
      patternErr    => pattern_error,
      idelayErr     => idelay_error,
      bitslipErr    => bitslip_error,
      watchDogErr   => watchdog_error,

      -- Data I/F --
      isKTypeTx     => is_ktype_tx,
      dataInTx      => data_tx,
      validInTx     => valid_tx,
      txBeat        => tx_beat,
      txAck         => tx_ack,

      isIdleRx      => is_idle_rx,
      isKTypeRx     => is_ktype_rx,
      dataOutRx     => data_rx,
      validOutRx    => valid_rx,

      -- CDCM ports --
      cdcmTxp       => TXP,
      cdcmTxn       => TXN,
      cdcmRxp       => RXP,
      cdcmRxn       => RXN,
      modClock      => modClk

      );

  u_Mikumari : entity mylib.MikumariLane
    generic map
    (
      -- CBT --
      kNumEncodeBits => kNumEncodeBits,
      -- MIKUMARI-Link --
      enScrambler    => enScrambler,
      kHighPrecision => kHighPrecision,
      -- DEBUG --
      enDEBUG        => enDebugMikumari
    )
    port map
    (
      -- SYSTEM port --------------------------------------------------------------------------
      srst        => sync_reset,
      clkPar      => clkPar,
      cbtUpIn     => cbt_lane_up,
      linkUp      => linkUp,

      -- TX port ------------------------------------------------------------------------------
      -- Data I/F --
      dataInTx      => dataInTx,
      validInTx     => validInTx,
      frameLastInTx => frameLastInTx,
      txAck         => txAck,

      pulseIn       => pulseIn,
      pulseTypeTx   => pulseTypeTx,
      pulseRegTx    => pulseRegTx,
      busyPulseTx   => busyPulseTx,

      -- Cbt ports --
      isKtypeOut  => is_ktype_tx,
      cbtDataOut  => data_tx,
      cbtValidOut => valid_tx,
      cbtTxAck    => tx_ack,
      cbtTxBeat   => tx_beat,

      -- RX port ------------------------------------------------------------------------------
      -- Data I/F --
      dataOutRx   => dataOutRx,
      validOutRx  => validOutRx,
      frameLastRx => frameLastRx,
      checksumErr => checksumErr,
      frameBroken => frameBroken,
      recvTermnd  => recvTermnd,

      pulseOut    => pulseOut,
      pulseTypeRx => pulseTypeRx,
      pulseRegRx  => pulseRegRx,

      -- Cbt ports --
      isKtypeIn   => is_ktype_rx,
      cbtDataIn   => data_rx,
      cbtValidIn  => valid_rx
  );

  -- Reset sequence --
  sync_reset  <= reset_shiftreg(kWidthResetSync-1);
  u_sync_reset : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      reset_shiftreg  <= reset_shiftreg(kWidthResetSync-2 downto 0) & rst;
    end if;
  end process;

end Behavioral;
