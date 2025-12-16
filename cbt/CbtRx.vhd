library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library mylib;
use mylib.defCDCM.all;

entity CbtRx is
  generic
  (
    kFamily            : string;
    -- CDCM-RX --
    genIDELAYCTRL      : boolean; -- If TRUE, IDELAYCTRL is instantiated.
    kDiffTerm          : boolean; -- IBUF DIFF_TERM
    kRxPolarity        : boolean; -- If true, inverts Rx polarity
    kIoStandard        : string;  -- IOSTANDARD of IBUFDS
    kIoDelayGroup      : string;  -- IODELAY_GROUP for IDELAYCTRL and IDELAY
    kFixIdelayTap      : boolean; -- If TRUE, value on tapValueIn is set to IDELAY
    kCdcmModWidth      : integer; -- # of time slices of the CDCM signal
    kFreqFastClk       : real;    -- Frequency of SERDES fast clock (MHz).
    kFreqRefClk        : real;    -- Frequency of refclk for IDELAYCTRL (MHz).
    kBitslice0         : boolean;

    -- CDCM encoder --
    kNumEncodeBits     : integer:= 2;  -- 1:CDCM-10-1.5 or 2:CDCM-10-2.5
    -- CBT --
    kCbtMode           : string;
    -- DEBUG --
    enDEBUG            : boolean:= false

  );
  port
  (
    -- SYSTEM port --
    srst          : in std_logic; -- Reset logics driven by clkPar. Transceiver function reset. (active high)
    pwrOnRst      : in std_logic; -- Reset logics driven by clkIndep and clkIdelayRef. (active high)
    clkSer        : in std_logic; -- From BUFG (5 x clkPar freq.)
    clkPar        : in std_logic; -- From BUFG
    clkIdelayRef  : in std_logic; -- REFCLK input for IDELAYCTRL
    initIn        : in std_logic; -- Re-do the initialization process. Sync with clkPar.
    tapValueIn    : in std_logic_vector(kWidthTap-1 downto 0); -- IDELAY TAP value input (active when kFixIdelayTap is true)
    firstBitPatt  : out CdcmPatternType; -- ISERDES output pattern after finishing the idelay adjustment

    -- Status --
    decoderReady  : out std_logic;
    cbtRxUp       : out std_logic; -- Indicate that CDCM-RX is ready for communication.
    tapValueOut   : out std_logic_vector(kWidthTap-1 downto 0); -- IDELAY TAP value output
    bitslipNum    : out std_logic_vector(kWidthBitSlipNum-1 downto 0); -- Number of bitslip made
    cntValueOutInit : out std_logic_vector(kCNTVALUEbit-1 downto 0);
    cntValueOutSlaveInit : out std_logic_vector(kCNTVALUEbit-1 downto 0);
    -- Error --
    patternErr    : out std_logic; -- Indicates CDCM waveform pattern is collapsed.
    idelayErr     : out std_logic; -- Attempted bitset but the expected pattern was not found.
    bitslipErr    : out std_logic; -- Bit pattern which does not match the CDCM rule is detected.
    watchDogErr   : out std_logic; -- Watch dog can't eat dogfood within specified time. The other side seems to be down.


    -- Data I/F --
    isIdle        : out std_logic; -- Indicates present character is idle.
    isKType       : out std_logic; -- 1: K type character. 0: D type character.
    dataOut       : out CbtUDataType;
    validOut      : out std_logic; -- 1: charOut is valid.

    -- Back channel --
    instRx        : out CbtBackChannelType; -- Instruction from CBT-RX

    -- CDCM ports --
    cdcmRxp       : in std_logic; -- Connect to TOPLEVEL port
    cdcmRxn       : in std_logic; -- Connect to TOPLEVEL port
    modClock      : out std_logic -- Modulated clock.
  );
end CbtRx;

architecture RTL of CbtRx is
  -- System --

  -- Initialization instruction --
  constant kWidthResetSmSr    : integer:= 16;
  signal reset_sm_sr          : std_logic_vector(kWidthResetSmSr-1 downto 0);

  signal reset_sm, raw_reset_sm : std_logic;
  signal self_init            : std_logic;
  signal init_rx              : std_logic;
  signal cbt_rx_up            : std_logic;
  signal enable_bit_align     : std_logic;
  signal back_ch_inst         : CbtBackChannelType;

  -- Error --
  signal watchdog_timer       : std_logic_vector(kWidthWatchDogTimer-1 downto 0);
  signal watchdog_timeout     : std_logic;
  signal reg_watchdog_timeout : std_logic;

  -- Decoder --
  constant kNumInitTimeOut  : integer:= 16#FFFFFF#;
  constant kNumDelayInit    : integer:= 10;
  constant kNumMatchCycle   : integer:= 8;
  signal char_is_idle, char_is_collapsed, valid_out, decoder_beat   : std_logic;
  signal cbt_char_is_collapsed, cbt_char_is_idle, cbt_char_is_ktype   : std_logic;
  signal cbt_char_valid       : std_logic;
  signal cbt_char_header      : CbtHeaderType;
  signal cbt_char_data        : CbtUDataType;
  signal reg_data             : CbtUDataType;
  signal decoder_bit_aligned  : std_logic;
  signal header_rd            : std_logic;

  -- CDCM-RX --
  signal payload              : std_logic_vector(kPaylowdPos'length-1 downto 0);
  signal status_init          : RxInitStatusType;
  signal cdcm_rx_up           : std_logic;
  signal cdcm_patt_error      : std_logic;
  signal character_out        : CbtCharType;

  -- CBT character selector --


  -- debug --
  attribute mark_debug  : boolean;
  attribute mark_debug  of cbt_char_header       : signal is enDEBUG;
  attribute mark_debug  of cbt_char_data         : signal is enDEBUG;
  attribute mark_debug  of decoder_bit_aligned   : signal is enDEBUG;
  attribute mark_debug  of back_ch_inst          : signal is enDEBUG;
  attribute mark_debug  of cbt_rx_up             : signal is enDEBUG;
  attribute mark_debug  of cbt_char_is_idle      : signal is enDEBUG;
  attribute mark_debug  of cbt_char_is_ktype     : signal is enDEBUG;
  attribute mark_debug  of cbt_char_is_collapsed : signal is enDEBUG;
  attribute mark_debug  of cdcm_patt_error       : signal is enDEBUG;
  attribute mark_debug  of watchdog_timeout      : signal is enDEBUG;
--  attribute mark_debug  of header_rd             : signal is enDEBUG;
  attribute mark_debug  of valid_out             : signal is enDEBUG;
  attribute mark_debug  of init_rx      : signal is enDEBUG;
  attribute mark_debug  of self_init      : signal is enDEBUG;

begin
  -- ======================================================================
  --                                 body
  -- ======================================================================

  init_rx     <= initIn or watchdog_timeout or self_init;

  decoderReady  <= decoder_bit_aligned;
  cbtRxUp     <= cbt_rx_up;
  patternErr  <= cdcm_patt_error or cbt_char_is_collapsed;
  watchDogErr <= reg_watchdog_timeout;

  isIdle    <= cbt_char_is_idle;
  isKType   <= cbt_char_is_ktype;
  dataOut   <= reg_data;
  validOut  <= cbt_char_valid;

  instRx    <= back_ch_inst;

  raw_reset_sm  <= srst or init_rx;
  reset_sm      <= reset_sm_sr(kWidthResetSmSr-1);

  u_reset_sm_sr : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      reset_sm_sr   <= reset_sm_sr(kWidthResetSmSr-2 downto 0) & raw_reset_sm;
    end if;
  end process;

  -- Character output -----------------------------------------------------
  cbt_char_header   <= character_out(kNumCbtCharBits-1 downto kNumCbtCharBits-kNumCbtHeaderBits);
  cbt_char_data     <= character_out(kNumCbtCharBits-kNumCbtHeaderBits-1 downto 0);

  u_header_rd : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1' or cbt_rx_up = '0') then
        header_rd   <= '0';
      else
        if(cbt_char_valid = '1' and cbt_rx_up = '1' and cbt_char_is_ktype = '0') then
          header_rd   <= not header_rd;
        end if;
      end if;
    end if;
  end process;

  u_char_buf : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(decoder_beat = '1') then
        cbt_char_is_idle        <= char_is_idle;
        cbt_char_is_collapsed   <= char_is_collapsed;

        if(char_is_collapsed = '1') then
          cbt_char_valid      <= '0';
        elsif(cbt_char_header = kTtype and valid_out = '1') then
          cbt_char_valid      <= '0';
        --elsif(cbt_char_header = kKtype) then
        elsif(cbt_char_header = kKtype and valid_out = '1') then
          reg_data            <= cbt_char_data;
          cbt_char_is_ktype   <= '1';
          cbt_char_valid      <= '1';
        elsif(((cbt_char_header = kDtypeP and header_rd = '0') or (cbt_char_header = kDtypeM and header_rd = '1'))
              and valid_out = '1') then
          reg_data            <= cbt_char_data;
          cbt_char_valid      <= '1';
        end if;
      else
        cbt_char_is_idle    <= '0';
        cbt_char_is_ktype   <= '0';
        cbt_char_valid      <= '0';
      end if;
    end if;
  end process;

  -- Watch dog --------------------------------------------------------------
  u_watchdog : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        watchdog_timeout      <= '0';
        reg_watchdog_timeout  <= '0';
      else
        if(cbt_rx_up = '1' and decoder_beat = '1')  then
          if(character_out = kTTypeCharDogfood) then
            watchdog_timer  <= (others => '0');
          else
            watchdog_timer  <= std_logic_vector(unsigned(watchdog_timer) +1);
          end if;
        elsif(cbt_rx_up = '0') then
          watchdog_timer  <= (others => '0');
        end if;

        if(watchdog_timer = kMaxWDT and watchdog_timeout = '0') then
          watchdog_timeout  <= '1';
        else
          watchdog_timeout  <= '0';
        end if;

        if(watchdog_timeout = '1') then
          reg_watchdog_timeout  <= '1';
        elsif(reg_watchdog_timeout = '1' and back_ch_inst = StateCbtRxUp) then
          reg_watchdog_timeout  <= '0';
        end if;
      end if;
    end if;
  end process;



  -- Instruction SM -------------------------------------------------------
  gen_master : if kCbtMode = "Master" generate
  begin
    u_master_sm : process(clkPar)
      variable match_count    : integer range 0 to kNumMatchCycle+1;
      variable initial_timer  : integer range 0 to kNumInitTimeOut+1;
      variable delay_count    : integer range 0 to kNumDelayInit+1;
    begin
      if(clkPar'event and clkPar = '1') then
        if(reset_sm = '1') then
          match_count       := 0;
          cbt_rx_up         <= '0';
          enable_bit_align  <= '0';
          self_init         <= '0';
          back_ch_inst      <= SendIdle;
          initial_timer     := kNumInitTimeOut;
          delay_count       := kNumDelayInit;
          --back_ch_inst      <= SendZero;
        else
          case back_ch_inst is
--            when SendZero =>
--              initial_timer := initial_timer +1;
--              if(initial_timer = kNumInitTimeOut) then
--                back_ch_inst  <= SendIdle;
--                initial_timer   := 0;
--              end if;

            when SendIdle =>
              if(status_init = kInitFinish) then
                initial_timer   := kNumInitTimeOut;
                back_ch_inst  <= SendInitPattern;
              end if;

            when SendInitPattern =>
            initial_timer   := initial_timer -1;
              if(cdcm_rx_up = '1') then
                back_ch_inst  <= SendTCharI1;
              elsif(initial_timer = 0) then
                self_init     <= '1';
                delay_count   := kNumDelayInit;
                back_ch_inst  <= DelayReinit;
              end if;

            when SendTCharI1  =>
            initial_timer   := initial_timer -1;
              enable_bit_align  <= '1';
              if(decoder_bit_aligned = '1') then
                enable_bit_align  <= '0';
                back_ch_inst  <= SendTCharI2;
              elsif(initial_timer = 0) then
                self_init     <= '1';
                delay_count   := kNumDelayInit;
                back_ch_inst  <= DelayReinit;
              end if;

            when SendTCharI2 =>
              initial_timer   := initial_timer -1;
              if(valid_out = '1' and character_out = GetInit2Char(kNumEncodeBits)) then
                match_count       := match_count +1;
              end if;

              if(match_count = kNumMatchCycle) then
                back_ch_inst <= StateCbtRxUp;
              elsif(initial_timer = 0) then
                self_init     <= '1';
                delay_count   := kNumDelayInit;
                back_ch_inst  <= DelayReinit;
              end if;

            when StateCbtRxUp  =>
              cbt_rx_up   <= '1';

            when DelayReinit =>
              delay_count := delay_count -1;
              if(delay_count = 0) then
                self_init     <= '0';
                back_ch_inst  <= SendIdle;
              end if;

            when others =>
              null;

          end case;
        end if;
      end if;
    end process;
  end generate;

  gen_slave : if kCbtMode = "Slave" generate
  begin
    u_slave_sm : process(clkPar)
      variable match_count    : integer range 0 to kNumMatchCycle+1:= 0;
      variable initial_timer  : integer range 0 to kNumInitTimeOut+1:= 0;
      variable delay_count    : integer range 0 to kNumDelayInit+1;
    begin
      if(clkPar'event and clkPar = '1') then
        if(reset_sm = '1') then
          match_count       := 0;
          cbt_rx_up         <= '0';
          enable_bit_align  <= '0';
          self_init         <= '0';
          initial_timer     := kNumInitTimeOut;
          delay_count       := kNumDelayInit;
          back_ch_inst      <= SendZero;
        else
          case back_ch_inst is
            when SendZero =>
              if(status_init = kInitFinish) then
                initial_timer := kNumInitTimeOut;
                back_ch_inst  <= SendIdle;
              end if;

            when SendIdle =>
              initial_timer   := initial_timer -1;
              if(cdcm_rx_up = '1') then
                back_ch_inst  <= SendInitPattern;
              elsif(initial_timer = 0) then
                self_init     <= '1';
                delay_count   := kNumDelayInit;
                back_ch_inst  <= DelayReinit;
              end if;

            when SendInitPattern =>
              initial_timer   := initial_timer -1;
              enable_bit_align  <= '1';
              if(decoder_bit_aligned = '1') then
                enable_bit_align  <= '0';
                back_ch_inst      <= SendTCharI1;
              elsif(initial_timer = 0) then
                self_init     <= '1';
                delay_count   := kNumDelayInit;
                back_ch_inst  <= DelayReinit;
              end if;

            when SendTCharI1  =>
              initial_timer   := initial_timer -1;
              if(valid_out = '1' and character_out = GetInit2Char(kNumEncodeBits)) then
                back_ch_inst  <= SendTCharI2;
              elsif(initial_timer = 0) then
                self_init     <= '1';
                delay_count   := kNumDelayInit;
                back_ch_inst  <= DelayReinit;
              end if;

            when SendTCharI2 =>
              initial_timer   := initial_timer -1;
              if(valid_out = '1' and character_out /= GetInit2Char(kNumEncodeBits)) then
                match_count  := match_count +1;
              end if;

              if(match_count = kNumMatchCycle) then
                back_ch_inst <= StateCbtRxUp;
              elsif(initial_timer = 0) then
                self_init     <= '1';
                delay_count   := kNumDelayInit;
                back_ch_inst  <= DelayReinit;
              end if;

            when StateCbtRxUp  =>
              cbt_rx_up   <= '1';

            when DelayReinit =>
              delay_count := delay_count -1;
              if(delay_count = 0) then
                self_init     <= '0';
                back_ch_inst  <= SendIdle;
              end if;

            when others =>
              null;

          end case;
        end if;
      end if;
    end process;
  end generate;


  -- Core implementation --
  u_decoder : entity mylib.CdcmRxDecoder
    generic map
    (
      kNumEncodeBits  => kNumEncodeBits,
      kNumCharBits    => kWidthDev,
      kRefPattern     => GetInit1Char(kNumEncodeBits)
    )
    port map
    (
      -- SYSTEM port --
      srst        => reset_sm,
      clkPar      => clkPar,
      enBitAlign  => enable_bit_align,

      -- Status --
      bitAligned  => decoder_bit_aligned,

      -- Data I/F --
      charOut     => character_out,
      validOut    => valid_out,
      isIdle      => char_is_idle,
      isCollapsed => char_is_collapsed,
      decoderBeat => decoder_beat,

      -- CDCM ports --
      payloadIn   => payload
    );


  g_us : if kFamily = "US" generate
  begin

  u_cdcm_rx : entity mylib.CdcmRx_US
    generic map
    (
      genIDELAYCTRL      => genIDELAYCTRL,
      kDiffTerm          => kDiffTerm,
      kRxPolarity        => kRxPolarity,
      kIoStandard        => kIoStandard,
      kIoDelayGroup      => kIoDelayGroup,
      kFixIdelayTap      => kFixIdelayTap,
      kCdcmModWidth      => kCdcmModWidth,
      kFreqFastClk       => kFreqFastClk,
      kFreqRefClk        => kFreqRefClk,
      enDEBUG            => enDEBUG,
      kBitslice0         => kBitslice0
    )
    port map
    (
      -- SYSTEM port --
      srst          => srst,
      pwrOnRst      => pwrOnRst,
      clkSer        => clkSer,
      clkPar        => clkPar,
      clkIdelayRef  => clkIdelayRef,
      initIn        => init_rx,
      tapValueIn    => tapValueIn,
      firstBitPatt  => firstBitPatt,

      -- Status --
      statusInit    => status_init,
      cdcmUpRx      => cdcm_rx_up,
      tapValueOut   => tapValueOut,
      bitslipNum    => bitslipNum,
      cntValueOutInit => cntValueOutInit,
      cntValueOutSlaveInit => cntValueOutSlaveInit,

      -- Error status --
      idelayErr     => idelayErr,
      bitslipErr    => bitslipErr,
      patternErr    => cdcm_patt_error,

      -- CDCM input ports
      RXP           => cdcmRxp,
      RXN           => cdcmRxn,
      modClock      => modClock,
      payloadOut    => payload
    );
end generate;

  g_7s : if kFamily = "7S" generate
  begin

  u_cdcm_rx : entity mylib.CdcmRx
    generic map
    (
      genIDELAYCTRL      => genIDELAYCTRL,
      kDiffTerm          => kDiffTerm,
      kRxPolarity        => kRxPolarity,
      kIoStandard        => kIoStandard,
      kIoDelayGroup      => kIoDelayGroup,
      kFixIdelayTap      => kFixIdelayTap,
      kCdcmModWidth      => kCdcmModWidth,
      kFreqFastClk       => kFreqFastClk,
      kFreqRefClk        => kFreqRefClk,
      enDEBUG            => enDEBUG
    )
    port map
    (
      -- SYSTEM port --
      srst          => srst,
      pwrOnRst      => pwrOnRst,
      clkSer        => clkSer,
      clkPar        => clkPar,
      clkIdelayRef  => clkIdelayRef,
      initIn        => init_rx,
      tapValueIn    => tapValueIn,
      firstBitPatt  => firstBitPatt,

      -- Status --
      statusInit    => status_init,
      cdcmUpRx      => cdcm_rx_up,
      tapValueOut   => tapValueOut,
      bitslipNum    => bitslipNum,
      cntValueOutInit => cntValueOutInit,
      cntValueOutSlaveInit => cntValueOutSlaveInit,

      -- Error status --
      idelayErr     => idelayErr,
      bitslipErr    => bitslipErr,
      patternErr    => cdcm_patt_error,

      -- CDCM input ports
      RXP           => cdcmRxp,
      RXN           => cdcmRxn,
      modClock      => modClock,
      payloadOut    => payload
    );
end generate;



end RTL;
