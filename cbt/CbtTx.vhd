library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library mylib;
use mylib.defCDCM.all;

entity CbtTx is
  generic
  (
    kFamily          : string;
    -- CDCM-TX --
    kIoStandard      : string;       -- IO standard of OBUFDS
    kCdcmModWidth    : integer;      -- # of time slices of the CDCM signal
    -- CDCM encoder --
    kNumEncodeBits   : integer:= 2;  -- 1:CDCM-10-1.5 or 2:CDCM-10-2.5
    -- TX Polarity  --
    kTxPolarity      : boolean:= false; -- true: inverse polarity
    -- DEBUG --
    enDEBUG          : boolean:= false
  );
  port
  (
    -- SYSTEM port --
    srst        : in std_logic; -- Asynchronous assert, synchronous de-assert reset. (active high)
    clkSer      : in std_logic; -- From BUFG (5 x clkPar freq.)
    clkPar      : in std_logic; -- From BUFG
    offsetTable : out SerdesOffsetType;

    -- Status --
    cbtTxUp     : out std_logic;

    -- Data I/F --
    isKType     : in std_logic; -- 1: Generate a K type character. 0: D type character.
    dataIn      : in CbtUDataType;
    validIn     : in std_logic; -- 1: charIn is valid. Encode and send it to CDCM-TX.
                                -- 0: Send idle pattern;
    txBeat      : out std_logic; -- Indicate encode cycle.
    txAck       : out std_logic; -- Acknowledge to validIn. Becomes high at the same timing of txBeat.


    -- Back channel --
    instRx      : in CbtBackChannelType; -- Instruction from CBT-RX

    -- CDCM ports --
    cdcmTxp     : out std_logic; -- Connect to TOPLEVEL port
    cdcmTxn     : out std_logic  -- Connect to TOPLEVEL port

  );
end CbtTx;

architecture RTL of CbtTx is
  -- Control --
  signal tx_mode      : TxModeType;

  -- Status --
  signal cbt_tx_up    : std_logic;
  signal send_ttype_char  : std_logic;
  signal req_send_dogfood : std_logic;
  signal dogfood_timer    : std_logic_vector(kWidthWatchDogTimer-1 downto 0);

  -- Data I/F --
  signal encoder_beat    : std_logic;
  signal data_ack        : std_logic;
  signal char_in_encoder : CbtCharType;
  signal ttype_char, ktype_char, dtype_char : CbtCharType;
  signal valid_to_encoder : std_logic;
  signal header_rd        : std_logic;

  -- Core --
  signal waveform_pattern : CdcmPatternType;


  -- debug --
  attribute mark_debug  : boolean;
--  attribute mark_debug  of tx_mode          : signal is enDEBUG;
  attribute mark_debug  of cbt_tx_up        : signal is enDEBUG;
  attribute mark_debug  of char_in_encoder  : signal is enDEBUG;
  attribute mark_debug  of send_ttype_char  : signal is enDEBUG;
--  attribute mark_debug  of header_rd        : signal is enDEBUG;
  attribute mark_debug  of valid_to_encoder : signal is enDEBUG;
  attribute mark_debug  of data_ack         : signal is enDEBUG;
  attribute mark_debug  of encoder_beat     : signal is enDEBUG;
begin
  -- ======================================================================
  --                                 body
  -- ======================================================================

  cbtTxUp       <= cbt_tx_up;

  -- Tx control under initialization process ------------------------------
  u_tx_up : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        cbt_tx_up   <= '0';
      else
        if(instRx /= StateCbtRxUp) then
          cbt_tx_up   <= '0';
        elsif(instRx = StateCbtRxUp and encoder_beat = '1') then
          cbt_tx_up   <= '1';
        end if;
      end if;
    end if;
  end process;

  -- Mask control signal of dat
  -- I/F during initialization --
  txBeat            <= encoder_beat;
  txAck             <= data_ack when(send_ttype_char = '0') else '0';
  valid_to_encoder  <= validIn  when(send_ttype_char = '0') else
                      '1'       when(send_ttype_char = '1' and (instRx = SendTCharI1 or
                                                                instRx = SendTCharI2 or
                                                                instRx = StateCbtRxUp)) else
                      '0'       when(send_ttype_char = '1' and (instRx = SendIdle or instRx = SendInitPattern)) else
                      '0';

  -- Select CDCM-TX mode --
  u_tx_mode : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        tx_mode   <= kDisaTx;
      else
        if(instRx = SendZero) then
          tx_mode   <= kDisaTx;
        elsif(instRx = SendIdle) then
          tx_mode   <= kIdleTx;
        elsif(instRx = SendInitPattern) then
          tx_mode   <= kInitTx;
        else
          tx_mode   <= kNormalTx;
        end if;
      end if;
    end if;
  end process;

  -- Generate CBT character --
  u_gen_tchar  : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      -- T-type char --
      if(instRx = SendTCharI1) then
        ttype_char  <= GetInit1Char(kNumEncodeBits);
      elsif(instRx = SendTCharI2) then
        ttype_char  <= GetInit2Char(kNumEncodeBits);
      else
        ttype_char  <= kTTypeCharDogfood;
      end if;
    end if;
  end process;

  u_header_rd : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1' or cbt_tx_up = '0') then
        header_rd   <= '0';
      else
        if(data_ack = '1' and send_ttype_char = '0' and isKType = '0') then
          header_rd   <= not header_rd;
        end if;
      end if;
    end if;
  end process;

  ktype_char  <= kKtype & dataIn;
  dtype_char  <= kDtypeP & dataIn when(header_rd = '0') else kDtypeM & dataIn;

--  ktype_char  <= kKtype & dataIn;
--  dtype_char  <= kDtype & dataIn;

  send_ttype_char   <= (not cbt_tx_up) or (req_send_dogfood and (not isKType));

  char_in_encoder   <= ttype_char when(send_ttype_char = '1') else
                       ktype_char when(send_ttype_char = '0' and isKType = '1') else
                       dtype_char when(send_ttype_char = '0' and isKType = '0') else
                       ttype_char;

  u_dogfood_timer : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        req_send_dogfood  <= '0';
      else
        if(cbt_tx_up = '1') then
          if(encoder_beat = '1') then
            dogfood_timer   <= std_logic_vector(unsigned(dogfood_timer) +1);

            if(dogfood_timer = X"0EFFF") then
              req_send_dogfood  <= '1';
              dogfood_timer     <= (others => '0');
            elsif(send_ttype_char = '1') then
              req_send_dogfood  <= '0';
            end if;
          end if;
        else
          req_send_dogfood  <= '0';
          dogfood_timer     <= (others => '0');
        end if;
      end if;
    end if;
  end process;

  -- Core implementation -----------------------------------------------
  u_encoder : entity mylib.CdcmTxEncoder
    generic map
    (
      kNumEncodeBits  => kNumEncodeBits
    )
    port map
    (
      -- SYSTEM port --
      srst      => srst ,
      clkPar    => clkPar,

      -- Data I/F --
      charIn      => char_in_encoder,
      validIn     => valid_to_encoder,
      encoderBeat => encoder_beat,
      dataAck     => data_ack,

      -- CDCM ports --
      wfPattern   => waveform_pattern
    );
   
   
  u_cdcm_tx : entity mylib.CdcmTx
    generic map
    (
      kFamily        => kFamily,
      kIoStandard    => kIoStandard,
      kTxPolarity    => kTxPolarity,
      kCdcmModWidth  => kCdcmModWidth
    )
    port map
    (
      -- SYSTEM port --
      srst      => srst,
      clkSer    => clkSer,
      clkPar    => clkPar,
      selMode   => tx_mode,
      offsetTable => offsetTable,

      -- CDCM output port --
      TXP       => cdcmTxp,
      TXN       => cdcmTxn,
      wfPattern => waveform_pattern
    );




end RTL;
