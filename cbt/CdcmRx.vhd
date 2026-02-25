library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

Library UNISIM;
use UNISIM.vcomponents.all;

library mylib;
use mylib.defCDCM.all;

-- ----------------------------------------------------------------------------------
-- == Clock network ==
-- Master (recovery) clock ---> BUFG ---> clkPar
-- Fast clock              ---> BUFG ---> clkSer
-- (Fast clock is 5x/4x faster than master clock)
-- Skew of these clocks must be adjusted.
--
--
-- readyRx:
--   Its logic high indicates that the initialization process, idelay adjust and bit-slip,
--   is finished.
-- ----------------------------------------------------------------------------------


entity CdcmRx is
  generic
  (
    genIDELAYCTRL      : boolean; -- If TRUE, IDELAYCTRL is instantiated.
    kDiffTerm          : boolean; -- IBUF DIFF_TERM
    kRxPolarity        : boolean; -- If true, inverts Rx polarity
    kIoStandard        : string;  -- IOSTANDARD of IBUFDS
    kIoDelayGroup      : string;  -- IODELAY_GROUP for IDELAYCTRL and IDELAY
    kFixIdelayTap      : boolean; -- If TRUE, value on tapValueIn is set to IDELAY
    kCdcmModWidth      : integer; -- # of time slices of the CDCM signal
    kFreqFastClk       : real;    -- Frequency of SERDES fast clock (MHz).
    kFreqRefClk        : real;    -- Frequency of refclk for IDELAYCTRL (MHz).
    enDEBUG            : boolean:= false
  );
  port
  (
    -- SYSTEM port --
    srst          : in std_logic; -- Reset logics driven by clkPar. Transceiver function reset. (active high)
    pwrOnRst      : in std_logic; -- Reset logics driven by clkIndep and clkIdelayRef. (active high)
    clkSer        : in std_logic; -- From BUFG (5 x clkPar freq.)
    clkPar        : in std_logic; -- From BUFG
    clkIdelayRef  : in std_logic; -- 200 MHz ref. clock.
    initIn        : in std_logic; -- Re-do the initialization process. Sync with clkPar.
    tapValueIn    : in std_logic_vector(kWidthTap-1 downto 0); -- IDELAY TAP value input (active when kFixIdelayTap is true)
    firstBitPatt  : out CdcmPatternType; -- ISERDES output pattern after finishing the idelay adjustment

    -- Status --
    statusInit    : out RxInitStatusType; -- Status of initialization. Sync with clkPar
    cdcmUpRx      : out std_logic; -- Indicate that CDCM-RX is ready for communication.
    tapValueOut   : out std_logic_vector(kWidthTap-1 downto 0); -- IDELAY TAP value output
    bitslipNum    : out std_logic_vector(kWidthBitSlipNum-1 downto 0); -- Number of bitslip made
    cntValueOutInit : out std_logic_vector(kCNTVALUEbit-1 downto 0);
    cntValueOutSlaveInit : out std_logic_vector(kCNTVALUEbit-1 downto 0);

    -- Error status --
    idelayErr     : out std_logic; -- IDELAY auto adjust was failed.
    bitslipErr    : out std_logic; -- Attempted bitslip but the expected pattern was not found.
    patternErr    : out std_logic; -- Bit pattern which does not match the CDCM rule is detected.

    -- CDCM input ports
    RXP           : in std_logic;  -- Connect to TOPLEVEL port
    RXN           : in std_logic;  -- Connect to TOPLEVEL port
    modClock      : out std_logic; -- Modulated clock. Output from IBUFDS (before IDELAYE2)
    payloadOut    : out std_logic_vector(kPaylowdPos'length-1 downto 0) -- CDCM payload
  );
end CdcmRx;

architecture RTL of CdcmRx is
  -- System --
  constant kPlateauThreshold  : integer:= GetPlateauLength(GetTapDelay(kFreqRefClk), kFreqFastClk);
  constant kNumTaps           : integer:= 32;

  signal cdcm_pattern_ok      : std_logic;
  signal ready_ctrl           : std_logic;
  signal rst_all              : std_logic;

  signal cdcm_rx_up           : std_logic;
  signal status_init          : RxInitStatusType;

  signal pattern_error        : std_logic;
  signal idelay_error         : std_logic;
  signal bitslip_error        : std_logic;

  -- IDELAY --
  signal serdes_reset   : std_logic;
  signal idelay_reset   : std_logic;
  signal idelay_check_count : integer range 0 to kMaxIdelayCheck;
  signal idelay_tap_load    : std_logic;

  signal tap_value_in         : integer range 0 to kNumTaps-1;
  signal tap_value_out        : std_logic_vector(kWidthTap-1 downto 0);

  signal left_edge_tap       : integer range 0 to kNumTaps-1;
  signal right_edge_tap      : integer range 0 to kNumTaps-1;

  signal en_idelay_check      : std_logic;
  signal idelay_is_adjusted   : std_logic;
  signal state_idelay         : IdelayControlProcessType;

  -- ISERDES --
  signal dout_serdes          : CdcmPatternType;
  signal reg_dout_serdes      : CdcmPatternType;
  signal prev_data            : CdcmPatternType;
  signal first_bit_pattern    : CdcmPatternType;

  signal success_vector       : std_logic_vector(32 downto 0);
  signal boudary_vector       : std_logic_vector(32 downto 0);
  signal island_vector        : std_logic_vector(32 downto 0);

  signal reg_prev_serdes_out  : CdcmPatternType;
  signal en_bitslip           : std_logic;
  signal en_idle_check        : std_logic;
  signal idle_patt_count      : integer range 0 to kMaxPattCheck;
  signal bit_aligned          : std_logic;
  signal bitslip_failure      : std_logic;
  signal state_bitslip        : BitslipControlProcessType;

  -- IODELAY_GROUP --
  attribute IODELAY_GROUP : string;

  attribute mark_debug        : boolean;
  attribute mark_debug of status_init     : signal is enDEBUG;
  attribute mark_debug of state_bitslip   : signal is enDEBUG;
  attribute mark_debug of state_idelay    : signal is enDEBUG;
  attribute mark_debug of reg_dout_serdes : signal is enDEBUG;
  attribute mark_debug of tap_value_in    : signal is enDEBUG;
  attribute mark_debug of tap_value_out   : signal is enDEBUG;
  attribute mark_debug of success_vector  : signal is enDEBUG;
  attribute mark_debug of boudary_vector  : signal is enDEBUG;
  attribute mark_debug of island_vector   : signal is enDEBUG;
  attribute mark_debug of left_edge_tap   : signal is enDEBUG;
  attribute mark_debug of right_edge_tap  : signal is enDEBUG;


-- debug ---------------------------------------------------------------

begin
  -- ======================================================================
  --                                 body
  -- ======================================================================

  cntValueOutInit <= (others => '0');
  cntValueOutSlaveInit <= (others => '0');

  payloadOut    <= reg_dout_serdes(kPaylowdPos'range);
  tapValueOut   <= tap_value_out;
  firstBitPatt  <= first_bit_pattern;

  -- ISerDes implementation ---------------------------------------------------------
  gen_idelayctrl : if genIDELAYCTRL = TRUE generate
    attribute IODELAY_GROUP of IDELAYCTRL_inst : label is kIoDelayGroup;
  begin
    IDELAYCTRL_inst : IDELAYCTRL
      port map (
        RDY     => ready_ctrl,
        REFCLK  => clkIdelayRef,
        RST     => pwrOnRst
      );

    rst_all  <= srst or (not ready_ctrl);
  end generate;

  nogen : if genIDELAYCTRL = FALSE generate
  begin
    rst_all   <= srst;
  end generate;

  gen_cdcm10 : if kCdcmModWidth = 10 generate
    u_cdcm_rx_iserdes : entity mylib.CdcmRxImpl
      generic map
      (
        kSysW         => kWidthSys,
        kDevW         => kWidthDev,
        kDiffTerm     => kDiffTerm,
        kRxPolarity   => kRxPolarity,
        kIoStandard   => kIoStandard,
        kIoDelayGroup => kIoDelayGroup,
        kFreqRefClk   => kFreqRefClk
      )
      port map
      (
        -- IBUFDS
        dInFromPinP       => RXP,
        dInFromPinN       => RXN,

        -- IDELAY
        rstIDelay         => idelay_reset,
        ceIDelay          => '0',
        incIDelay         => '1',
        tapIn             => std_logic_vector(to_unsigned(tap_value_in, kWidthTap)),
        tapOut            => tap_value_out,

        -- ISERDES
        cdOutFromO        => modClock,
        dOutToDevice      => dout_serdes,
        bitslip           => en_bitslip,

        -- Clock and reset
        clkIn             => clkSer,
        clkDivIn          => clkPar,
        ioReset           => serdes_reset
      );
  end generate;

  gen_cdcm8 : if kCdcmModWidth = 8 generate
    u_cdcm_rx_iserdes : entity mylib.Cdcm8RxImpl
      generic map
      (
        kSysW         => kWidthSys,
        kDevW         => kWidthDev-2,
        kDiffTerm     => kDiffTerm,
        kRxPolarity   => kRxPolarity,
        kIoStandard   => kIoStandard,
        kIoDelayGroup => kIoDelayGroup,
        kFreqRefClk   => kFreqRefClk
      )
      port map
      (
        -- IBUFDS
        dInFromPinP       => RXP,
        dInFromPinN       => RXN,

        -- IDELAY
        rstIDelay         => idelay_reset,
        ceIDelay          => '0',
        incIDelay         => '1',

        -- ISERDES
        cdOutFromO        => modClock,
        dOutToDevice      => dout_serdes(8 downto 1),
        bitslip           => en_bitslip,
        tapIn             => std_logic_vector(to_unsigned(tap_value_in, kWidthTap)),
        tapOut            => tap_value_out,

        -- Clock and reset
        clkIn             => clkSer,
        clkDivIn          => clkPar,
        ioReset           => serdes_reset
      );

      dout_serdes(0)  <= '1';
      dout_serdes(9)  <= '0';
  end generate;

  u_bufdout : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      reg_dout_serdes <= dout_serdes;
    end if;
  end process;

  u_bitpattern : process(srst, clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
       if(srst = '1') then
         cdcm_pattern_ok <= '0';
       else
        if(bit_aligned = '1') then
          if(std_match(reg_dout_serdes, "000----111")) then
            cdcm_pattern_ok   <= '1';
          else
            cdcm_pattern_ok   <= '0';
          end if;
        else
          cdcm_pattern_ok     <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Idelay control -----------------------------------------------------------------
  serdes_reset  <= rst_all or initIn;
  idelay_reset  <= rst_all or idelay_tap_load;

  u_idelay_check : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(en_idelay_check = '1') then
        prev_data   <= reg_dout_serdes;
        if(prev_data = reg_dout_serdes) then
          idelay_check_count  <= idelay_check_count + 1;
        else
          idelay_check_count  <= 0;
        end if;
      else
        idelay_check_count  <= 0;
      end if;
    end if;
  end process;

  u_gen_fixedtap : if kFixIdelayTap = TRUE generate
  begin

    u_idelay_sm : process(clkPar)
      variable elapsed_time           : integer range 0 to kMaxIdelayCheck;
      variable wait_count             : integer range 0 to kLoadWait;
    begin
      if(clkPar'event and clkPar = '1') then
        if(serdes_reset = '1') then

          elapsed_time        := 0;

          en_idelay_check     <= '0';
          tap_value_in        <= 0;
          idelay_tap_load     <= '0';

          idelay_is_adjusted  <= '0';
          state_idelay        <= Init;
        else
          case state_idelay is
            when Init =>
              tap_value_in      <= to_integer(unsigned(tapValueIn));
              state_idelay      <= Increment;

            when Increment =>
              elapsed_time    := 0;
              idelay_tap_load <= '1';
              wait_count      := kLoadWait-1;
              state_idelay    <= WaitState;

            when WaitState =>
              idelay_tap_load <= '0';
              if(wait_count = 0) then
                en_idelay_check <= '1';
                state_idelay    <= Check;
              end if;
              wait_count  := wait_count-1;

            when Check =>
              elapsed_time      := elapsed_time +1;
              if(idelay_check_count = kSuccThreshold) then
                state_idelay      <= IdelayAdjusted;
              elsif(elapsed_time  = kMaxIdelayCheck-1) then
                -- Time out
                state_idelay      <= IdelayFailure;
              end if;

            when IdelayAdjusted =>
              en_idelay_check     <= '0';
              idelay_is_adjusted  <= '1';

            when IdelayFailure =>
              -- Abnormal state. Should not fall in this state.
              en_idelay_check     <= '0';
              elapsed_time        := 0;
              state_idelay        <= Init;

            when others =>
              state_idelay  <= Init;

          end case;
        end if;
      end if;
    end process;
  end generate;

  u_ungen : if kFixIdelayTap = FALSE generate
  begin

    u_idelay_sm : process(clkPar)
      variable index_tap              : integer range -1 to kNumTaps;
      variable elapsed_time           : integer range 0 to kMaxIdelayCheck;
      variable wait_count             : integer range 0 to kLoadWait;
      variable retry_wait_count       : integer range 0 to kMaxRetryWait;
      variable island_length          : integer range 0 to kNumTaps;
      variable checkbit_patt          : std_logic_vector(2 downto 0);
    begin
      if(clkPar'event and clkPar = '1') then
        if(serdes_reset = '1') then
--          elapsed_time        := 0;
--          index_tap           := 0;
          retry_wait_count    := kMaxRetryWait;
--          island_length       := 0;

--          en_idelay_check     <= '0';
--          tap_value_in        <= 0;
--          idelay_tap_load     <= '0';
--
--          success_vector      <= (others => '0');
--          boudary_vector      <= (others => '0');
--          island_vector       <= (others => '0');
--          reg_prev_serdes_out <= (others => '0');
          idelay_is_adjusted  <= '0';
          state_idelay        <= Init;
        else
          case state_idelay is
            when Init =>
              --en_idelay_check   <= '1';
              state_idelay      <= RetryWait;

            when RetryWait =>
              retry_wait_count  := retry_wait_count -1;
              if(retry_wait_count = 0) then
                en_idelay_check     <= '1';
                state_idelay        <= Check;
              else
                elapsed_time            := 0;
                index_tap               := 0;
                island_length           := 0;

                en_idelay_check     <= '0';
                tap_value_in        <= 0;
                idelay_tap_load     <= '0';

                success_vector      <= (others => '0');
                boudary_vector      <= (others => '0');
                island_vector       <= (others => '0');
                reg_prev_serdes_out <= (others => '0');
                idelay_is_adjusted  <= '0';
              end if;

            when Check =>
              idelay_tap_load   <= '0';
              elapsed_time      := elapsed_time +1;
              if(idelay_check_count = kSuccThreshold) then
                success_vector(tap_value_in+1)  <= '1';

                if(tap_value_in /= 0 and (success_vector(tap_value_in) = '0' or reg_prev_serdes_out /= reg_dout_serdes)) then
                  -- Reached to the boundary of the region --
                  boudary_vector(tap_value_in+1)  <= '1';
                  island_vector(tap_value_in+1)   <= not island_vector(tap_value_in);

                  reg_prev_serdes_out     <= reg_dout_serdes;
                  en_idelay_check         <= '0';
                  state_idelay            <= NumTrialCheck;
                else
                  -- IDELAY tap value is in the stable region --
                  boudary_vector(tap_value_in+1)  <= '0';
                  island_vector(tap_value_in+1)   <= island_vector(tap_value_in);

                  reg_prev_serdes_out     <= reg_dout_serdes;
                  en_idelay_check         <= '0';
                  state_idelay            <= NumTrialCheck;
                end if;
              elsif(elapsed_time  = kMaxIdelayCheck-1) then
                -- This IDELAY tap setting is not appropriate --
                success_vector(tap_value_in+1)  <= '0';
                boudary_vector(tap_value_in+1)  <= '0';
                island_vector(tap_value_in+1)   <= island_vector(tap_value_in);

--                reg_prev_serdes_out     <= (others => '0');
                en_idelay_check         <= '0';
                state_idelay            <= NumTrialCheck;
              end if;

            when NumTrialCheck  =>
              elapsed_time  := 0;
              if(tap_value_in = kNumTaps-1) then
                index_tap       := 0;
                state_idelay    <= SearchLeftEdge;
              else
                tap_value_in    <= tap_value_in +1;
                state_idelay    <= Increment;
              end if;

            when Increment =>
              idelay_tap_load <= '1';
              wait_count      := kLoadWait-1;
              state_idelay    <= WaitState;

            when SearchLeftEdge =>
              checkbit_patt     := success_vector(index_tap+1) &
                                   boudary_vector(index_tap+1) &
                                   island_vector(index_tap+1);
              if(index_tap = kNumTaps) then
                -- Could not find any appropriate tap value --
                state_idelay    <= IdelayFailure;
              elsif(checkbit_patt = "111") then
                -- Found the left edge of the first plateau --
                left_edge_tap   <= index_tap;
                island_length   := 0;
                index_tap       := index_tap+1;
                state_idelay    <= SearchRightEdge;
              else
                index_tap   := index_tap +1;
              end if;

            when SearchRightEdge =>
              checkbit_patt     := success_vector(index_tap+1) &
                                   boudary_vector(index_tap+1) &
                                   island_vector(index_tap+1);
              if(index_tap = kNumTaps) then
                -- Could not find any appropriate tap value --
                state_idelay    <= IdelayFailure;
              elsif(checkbit_patt = "101") then
                -- Inside the plateau --
                index_tap      := index_tap +1;
                island_length  := island_length +1;
              elsif(checkbit_patt /= "101" and island_length > kPlateauThreshold) then
                -- Found the right edge of the first plateau --
                right_edge_tap  <= index_tap-1;
                index_tap       := 0;
                state_idelay    <= SetCenter;
              else
                index_tap   := index_tap +1;
              end if;

            when SetCenter =>
              tap_value_in        <= (left_edge_tap + right_edge_tap) / 2;
              idelay_tap_load     <= '1';
              wait_count          := kLoadWait-1;
              state_idelay        <= IdelayAdjusted;

            when WaitState =>
              idelay_tap_load <= '0';
              if(wait_count = 0) then
                en_idelay_check <= '1';
                state_idelay    <= Check;
              end if;
              wait_count  := wait_count-1;

            when IdelayAdjusted =>
              reg_prev_serdes_out <= (others => '0');
              idelay_tap_load     <= '0';
              if(wait_count = 0) then
                idelay_is_adjusted  <= '1';
              end if;
              wait_count  := wait_count-1;

            when IdelayFailure =>
              -- Abnormal state. Should not fall in this state.
              elapsed_time            := 0;
              index_tap               := 0;
              retry_wait_count        := kMaxRetryWait;
              island_length           := 0;

              reg_prev_serdes_out     <= (others => '0');
              tap_value_in            <= 0;
              idelay_tap_load         <= '1';

              state_idelay            <= RetryWait;

            when others =>
              state_idelay  <= Init;

          end case;

        end if;
      end if;
    end process;

  end generate;


  -- Bit Slip --------------------------------------------------------------
  u_check_idle : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(en_idle_check = '1') then
        if(kIdleCDCM = reg_dout_serdes) then
          idle_patt_count  <= idle_patt_count + 1;
        else
          idle_patt_count  <= 0;
        end if;
      else
        idle_patt_count  <= 0;
      end if;
    end if;
  end process;

  u_bitslip_sm : process(clkPar)
    variable num_patt_check       : integer range 0 to kWidthDev;
    variable elapsed_time         : integer range 0 to kMaxPattCheck;
    variable wait_count           : integer range 0 to kLoadWait;
  begin
    if(clkPar'event and clkPar = '1') then
      if(serdes_reset = '1') then
        elapsed_time    := 0;
        num_patt_check  := 0;
        en_bitslip      <= '0';
        bit_aligned     <= '0';
        first_bit_pattern <= (others => '0');

        state_bitslip   <= Init;

      else
        case state_bitslip is
          when Init =>
            state_bitslip   <= WaitStart;

          when WaitStart =>
            if(idelay_is_adjusted = '1') then
              first_bit_pattern   <= reg_dout_serdes;
              en_idle_check       <= '1';
              state_bitslip       <= CheckIdlePatt;
            end if;

          when CheckIdlePatt =>
            elapsed_time  := elapsed_time +1;
            if(idle_patt_count = kPattOkThreshold) then
              en_idle_check   <= '0';
              bit_aligned     <= '1';
              state_bitslip   <= BitslipFinished;
            elsif(elapsed_time = kMaxPattCheck-1) then
              num_patt_check  := num_patt_check +1;
              en_bitslip      <= '1';
              state_bitslip   <= BitSlip;
            end if;

          when BitSlip =>
            en_bitslip    <= '0';
            if(num_patt_check = kWidthDev) then
              state_bitslip <= BitslipFailure;
            else
              wait_count    := kLoadWait-1;
              state_bitslip <= WaitState;
            end if;

          when WaitState =>
            if(wait_count = 0) then
              elapsed_time  := 0;
              state_bitslip <= CheckIdlePatt;
            end if;
            wait_count  := wait_count-1;

          when BitslipFinished =>
            null;

          when BitslipFailure =>
            elapsed_time    := 0;
            en_idle_check   <= '0';
            state_bitslip   <= Init;

          when others =>
            state_bitslip     <= Init;
        end case;

        bitslipNum  <= std_logic_vector(to_unsigned(num_patt_check, kWidthBitSlipNum));
      end if;
    end if;

  end process;

  -- Status register --------------------------------------------------------------
  -- For initialize process --
  cdcmUpRx    <= cdcm_rx_up;
  statusInit  <= status_init;

  u_init_status : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(serdes_reset = '1') then
        status_init   <= kWaitClkReady;
      else
        if(state_idelay = Init and state_bitslip = WaitStart) then
          status_init  <= kWaitClkReady;
        elsif(state_idelay /= IdelayAdjusted and state_bitslip = WaitStart) then
          status_init  <= kAdjustingIdelay;
        elsif(state_idelay = IdelayAdjusted and state_bitslip /= BitSlipFinished) then
          status_init  <= kTryingBitslip;
        elsif(state_idelay = IdelayAdjusted and state_bitslip = BitslipFinished) then
          status_init  <= kInitFinish;
        else
          status_init  <= kUndefinedRx;
        end if;
      end if;
    end if;
  end process;

  u_cdcm_up : process(clkPar)
    variable init_patt_count  : integer range 0 to kNumPattMatchCycle+10:= 0;
  begin
    if(clkPar'event and clkPar = '1') then
      if(serdes_reset = '1') then
        init_patt_count   := 0;
        cdcm_rx_up        <= '0';
      else
        if(status_init = kInitFinish
        and (reg_dout_serdes = kInitPCDCM or reg_dout_serdes = kInitMCDCM)) then
          init_patt_count   := init_patt_count +1;
        elsif(cdcm_rx_up  = '1') then
          init_patt_count   := 0;
        end if;

        if(init_patt_count = kNumPattMatchCycle) then
          cdcm_rx_up  <= '1';
        end if;
      end if;
    end if;
  end process;

  -- For error signal --
  idelayErr  <= idelay_error;
  bitslipErr <= bitslip_error;
  patternErr <= pattern_error;

  u_error_sig : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      pattern_error   <= not cdcm_pattern_ok;

      if(state_idelay = IdelayFailure)  then
        idelay_error  <= '1';
      else
        idelay_error  <= '0';
      end if;

      if(state_bitslip = BitslipFailure)  then
        bitslip_error  <= '1';
      else
        bitslip_error  <= '0';
      end if;
    end if;
  end process;

end RTL;
