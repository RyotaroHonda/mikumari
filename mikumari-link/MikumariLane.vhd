library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_MISC.ALL;
use ieee.numeric_std.all;

library mylib;
use mylib.defCDCM.all;
use mylib.defMikumari.all;

entity MikumariLane is
  generic
  (
    -- CBT --
    kNumEncodeBits    : integer:= 2;
    -- MIKUMARI-Link --
    enScrambler       : boolean:= true;
    kHighPrecision    : boolean:= false;
    -- DEBUG --
    enDEBUG           : boolean:= false
  );
  port
  (
    -- SYSTEM port --------------------------------------------------------------------------
    srst        : in std_logic; -- Asynchronous assert, synchronous de-assert reset. (active high)
    clkPar      : in std_logic; -- From BUFG
    cbtUpIn     : in std_logic; -- Cbt lane up signal
    linkUp      : out std_logic; -- Mikumari link is up

    -- TX port ------------------------------------------------------------------------------
    -- Data I/F --
    dataInTx      : in CbtUDataType;       -- User data input.
    validInTx     : in std_logic;          -- Indicate dataIn is valid.
    frameLastInTx : in std_logic;          -- Indicate current dataIn is a last character in a normal frame.
    txAck         : out std_logic;         -- Acknowledge to validIn signal.

    pulseIn       : in std_logic;          -- Pulse input. Must be one-shot signal.
    pulseTypeTx   : in MikumariPulseType;  -- 3-bit short message to be sent with pulse.
    pulseRegTx    : in MikumariHpmRegType; -- 4-bit additional pulse message; used only in High-Precision mode.
    busyPulseTx   : out std_logic;         -- Under transmission of previous pulse. If high, pulseIn is ignored.

    -- Cbt ports --
    isKtypeOut  : out std_logic;
    cbtDataOut  : out CbtUDataType;
    cbtValidOut : out std_logic;
    cbtTxAck    : in std_logic;
    cbtTxBeat   : in std_logic;

    -- RX port ------------------------------------------------------------------------------
    -- Data I/F --
    dataOutRx   : out CbtUDataType;        -- User data output.
    validOutRx  : out std_logic;           -- Indicate current dataOut is valid.
    frameLastRx : out std_logic;           -- Indicate current dataOut is the last data in a normal frame.
    checksumErr : out std_logic;           -- Check-sum error is happened in the present normal frame.
    frameBroken : out std_logic;           -- Frame start position is not correctly detected
    recvTermnd  : out std_logic;           -- Frame end position of the previsou frame is not correctly detected

    pulseOut    : out std_logic;           -- Reproduced one-shot pulse output.
    pulseTypeRx : out MikumariPulseType;   -- 3-bit short message accompanying the pulse.
    pulseRegRx  : out MikumariHpmRegType;  -- 4-bit additional pulse message; zero in Low-Latency mode.

    -- Cbt ports --
    isKtypeIn   : in std_logic; --
    cbtDataIn   : in CbtUDataType;
    cbtValidIn  : in std_logic

  );
end MikumariLane;

architecture RTL of MikumariLane is

  -- System --
  signal reset_mikumari       : std_logic;
  signal inst_rx              : MikumariBackChannelType;
  signal mikumari_tx_up       : std_logic;
  signal mikumari_rx_up       : std_logic;
  signal link_up_delay        : std_logic_vector(kWidthLinkDelay-1 downto 0);


begin
  -- ======================================================================
  --                                 body
  -- ======================================================================

  reset_mikumari  <= srst or (not cbtUpIn);

  linkUp  <= link_up_delay(kWidthLinkDelay-1);

  u_link_up : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      link_up_delay <= link_up_delay(kWidthLinkDelay-2 downto 0) & (mikumari_rx_up and mikumari_tx_up);
    end if;
  end process;

  u_mikumari_tx : entity mylib.MikumariTx
    generic map
    (
      -- CBT --
      kNumEncodeBits  => kNumEncodeBits,
      -- MIKUMARI-Link --
      enScrambler     => enScrambler,
      kHighPrecision  => kHighPrecision,
      -- DEBUG --
      enDEBUG         => enDEBUG
    )
    port map
    (
      -- SYSTEM port --
      srst        => reset_mikumari,
      clkPar      => clkPar,
      mikuTxup    => mikumari_tx_up,

      -- Data I/F --
      dataIn      => dataInTx,
      validIn     => validInTx,
      frameLastIn => frameLastInTx,
      txAck       => txAck,

      pulseIn     => pulseIn,
      pulseType   => pulseTypeTx,
      pulseReg    => pulseRegTx,
      busyPulseTx => busyPulseTx,

      -- Back channel --
      instRx      => inst_rx,

      -- Cbt ports --
      isKtypeOut  => isKtypeOut,
      cbtDataOut  => cbtDataOut,
      cbtValidOut => cbtValidOut,
      cbtTxAck    => cbtTxAck,
      cbtTxBeat   => cbtTxBeat
    );

  u_mikumari_rx : entity mylib.MikumariRx
    generic map
    (
      -- CBT --
      kNumEncodeBits  => kNumEncodeBits,
      -- MIKUMARI-Link --
      enScrambler     => enScrambler,
      kHighPrecision  => kHighPrecision,
      -- DEBUG --
      enDEBUG         => enDebug
    )
    port map
    (
      -- SYSTEM port --
      srst        => reset_mikumari,
      clkPar      => clkPar,

      -- Status --
      cbtUpIn     => cbtUpIn,
      mikuRxUp    => mikumari_rx_up,

      -- Data I/F --
      dataOut     => dataOutRx,
      validOut    => validOutRx,
      frameLast   => frameLastRx,
      checksumErr => checksumErr,
      frameBroken => frameBroken,
      recvTermnd  => recvTermnd,

      pulseOut    => pulseOut,
      pulseType   => pulseTypeRx,
      pulseReg    => pulseRegRx,

      -- Back channel --
      instRx      => inst_rx,

      -- Cbt ports --
      isKtypeIn   => isKtypeIn,
      cbtDataIn   => cbtDataIn,
      cbtValidIn  => cbtValidIn

    );

end RTL;
