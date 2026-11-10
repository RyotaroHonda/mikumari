library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_MISC.ALL;
use ieee.numeric_std.all;

library mylib;
use mylib.defCDCM.all;
use mylib.defMikumari.all;

entity MikumariTx is
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
    -- SYSTEM port --
    srst        : in std_logic; -- Asynchronous assert, synchronous de-assert reset. (active high)
    clkPar      : in std_logic; -- From BUFG

    -- Status --
    mikuTxUp    : out std_logic;

    -- Data I/F --
    dataIn      : in CbtUDataType;  -- User data input.
    validIn     : in std_logic;     -- Indicate dataIn is valid.
    frameLastIn : in std_logic;     -- Indicate current dataIn is a last character in a normal frame.
    txAck       : out std_logic;    -- Acknowledge to validIn signal.

    pulseIn     : in std_logic;     -- Pulse input. Must be one-shot signal.
    pulseType   : in MikumariPulseType;  -- 3-bit short message to be sent with pulse.
    pulseReg    : in MikumariHpmRegType; -- 4-bit additional pulse message; used only in High-Precision mode.
    busyPulseTx : out std_logic;    -- Under transmission of previous pulse. If high, pulseIn is ignored.

    -- Back channel --
    instRx      : in MikumariBackChannelType;

    -- Cbt ports --
    isKtypeOut  : out std_logic;    -- Connect to CbtTx.
    cbtDataOut  : out CbtUDataType; -- Connect to CbtTx.
    cbtValidOut : out std_logic;    -- Connect to CbtTx.
    cbtTxAck    : in std_logic;     -- Connect to CbtTx.
    cbtTxBeat   : in std_logic      -- Connect to CbtTx.
  );
end MikumariTx;

architecture RTL of MikumariTx is

  -- System --
  signal tx_flag              : std_logic_vector(kNumTxFlag-1 downto 0):= (others=>'0');

  -- Cbt --
  signal reg_cbt_tx_ack, reg_cbt_tx_beat  : std_logic;
  signal cbt_ktype_out, cbt_valid         : std_logic;
  signal is_ktype_out, cbt_valid_out      : std_logic;
  signal cbt_data                         : CbtUDataType;
  signal cbt_data_out                     : CbtUDataType;

  -- Data I/F --
  signal ifbuf_data_in        : CbtUDataType;
  signal ifbuf_valid_in       : std_logic;
  signal ifbuf_frame_last     : std_logic;
  signal is_reserved          : std_logic;
  signal ifbuf_read           : std_logic;
  signal data_is_ready        : std_logic;

  signal reg_data_in          : CbtUDataType;
  signal scramble_data_in     : CbtUDataType;
  signal reg_valid_in         : std_logic;

  signal reg_check_sum        : std_logic_vector(kWidthCheckSum-1 downto 0);
  signal complement_check_sum : std_logic_vector(kWidthCheckSum-1 downto 0);
  signal scramble_check_sum   : std_logic_vector(kWidthCheckSum-1 downto 0);
  signal tx_ack               : std_logic;


  -- pulse --
  signal pulse_in             : std_logic;
  signal pulse_busy           : std_logic;
  signal reg_pulse_type       : EncodedPulseType;
  signal pulse_count          : std_logic_vector(kWidthPulseCount-1 downto 0);
  signal pulse_count_delay    : std_logic_vector(pulse_count'range);
  signal reg_pulse_count      : std_logic_vector(pulse_count'range);
  signal pulse_ktype_char     : CbtUDataType;
  -- High-precision mode --
  signal reg_pulse_type_hpm   : EncodedHpmPulseType;
  signal pulse_message        : HpmPulseMessageType;
  signal encoded_4b           : std_logic_vector(3 downto 0);
  signal encoded_6b           : std_logic_vector(5 downto 0);
  signal running_disparity    : std_logic;
  signal done_1st_char        : std_logic;
  signal reg_pulse_message    : std_logic_vector(HpmPulseMessageType'high+2 downto 0);
  signal reg_hpm_pulse_char   : CbtUDataType;

  -- Initialize --
  signal reg_uinit            : std_logic_vector(1 downto 0);
  signal init_ktype_char      : CbtUDataType;
  signal req_first_fsk        : std_logic;
  signal first_fsk_sent       : std_logic;

  -- Scrambler --
  signal set_seed             : std_logic;
  signal en_prbs_clk          : std_logic;
  constant kPrbsLength        : positive:= 16;
  signal prbs_out             : std_logic_vector(kPrbsLength-1 downto 0);
  signal state_seed           : SetSeedType;

  -- debug --
  attribute mark_debug  : boolean;
  attribute mark_debug  of reg_cbt_tx_ack   : signal is enDEBUG;
  attribute mark_debug  of reg_cbt_tx_beat  : signal is enDEBUG;
  attribute mark_debug  of pulse_in         : signal is enDEBUG;
  attribute mark_debug  of pulse_count      : signal is enDEBUG;
  attribute mark_debug  of state_seed       : signal is enDEBUG;
  attribute mark_debug  of en_prbs_clk      : signal is enDEBUG;
  attribute mark_debug  of ifbuf_read       : signal is enDEBUG;
  attribute mark_debug  of data_is_ready    : signal is enDEBUG;
  attribute mark_debug  of is_reserved      : signal is enDEBUG;
  attribute mark_debug  of cbtTxAck         : signal is enDEBUG;
  attribute mark_debug  of tx_flag          : signal is enDEBUG;

begin
  -- ======================================================================
  --                                 body
  -- ======================================================================

  mikuTxUp  <= first_fsk_sent;

  -- Data I/F --
  txAck   <= tx_ack;

  u_userif_reg : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1' or first_fsk_sent = '0') then
        ifbuf_data_in     <= (others => '0');
        ifbuf_valid_in    <= '0';
        ifbuf_frame_last  <= '0';
        tx_ack            <= '0';
        is_reserved       <= '0';
        ifbuf_read        <= '0';
        data_is_ready     <= '0';

        reg_data_in       <= (others => '0');
        reg_valid_in      <= '0';
      else
        if(cbtTxBeat = '1') then
          if(is_reserved = '0') then
            ifbuf_data_in     <= dataIn;
            ifbuf_valid_in    <= validIn and not isBusyIFBuf(tx_flag);
            ifbuf_frame_last  <= frameLastIn;
            tx_ack            <= validIn and not isBusyIFBuf(tx_flag);
            --is_reserved       <= validIn and not isBusyIFBuf(tx_flag);
          end if;
        else
          tx_ack  <= '0';

        end if;

        if(tx_ack = '1') then
          is_reserved   <= '1';
        elsif(ifbuf_read = '1') then
          is_reserved   <= '0';
        end if;

        if(is_reserved = '1' and data_is_ready = '0') then
          reg_data_in               <= ifbuf_data_in;
          reg_valid_in              <= ifbuf_valid_in;
          tx_flag(kLastData.Index)  <= ifbuf_frame_last;
          ifbuf_read  <= '1';

        elsif(data_is_ready = '0') then
          reg_valid_in              <= '0';
          tx_flag(kLastData.Index)  <= '0';
          ifbuf_read  <= '0';
        else
          ifbuf_read  <= '0';
        end if;

        if(ifbuf_read = '1') then
          data_is_ready   <= '1';
        elsif(data_is_ready = '1' and tx_flag(kUserDataTx.Index) = '1' and cbtTxAck = '1') then
          data_is_ready   <= '0';
        end if;


        tx_flag(kUserDataTx.Index)  <= (not isBusyTx(tx_flag));-- and reg_valid_in;
      end if;
    end if;
  end process;

  -- pulse Tx --
  pulse_busy    <= tx_flag(kPulseReserve.index) or tx_flag(kPulseTx.index);
  busyPulseTx   <= pulse_busy;
  pulse_in      <= pulseIn and not pulse_busy;

  -- Cbt port --
  isKtypeOut    <= is_ktype_out;
  cbtDataOut    <= cbt_data_out;
  cbtValidOut   <= cbt_valid_out;

  u_cbt_reg : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      reg_cbt_tx_ack  <= cbtTxAck;
      reg_cbt_tx_beat <= cbtTxBeat;

      is_ktype_out    <= cbt_ktype_out;
      cbt_data_out    <= cbt_data;
      cbt_valid_out   <= cbt_valid;
    end if;
  end process;

  cbt_ktype_out  <= '1' when(tx_flag(kPulseTx.index) = '1') else
                    '1' when(tx_flag(kInitMikuTx.index) = '1') else
                    '0' when(tx_flag(kCheckSumTx.index) = '1') else
                    '1' when(tx_flag(kFskTx.index) = '1') else
                    '1' when(tx_flag(kFekTx.index) = '1') else '0';

  cbt_data    <= pulse_ktype_char     when(tx_flag(kPulseTx.index) = '1') else
                 init_ktype_char      when(tx_flag(kInitMikuTx.index) = '1') else
                 scramble_check_sum   when(tx_flag(kCheckSumTx.index) = '1') else
                 kMikumariFsk         when(tx_flag(kFskTx.index) = '1') else
                 kMikumariFek         when(tx_flag(kFekTx.index) = '1') else
                 scramble_data_in;

  cbt_valid   <= '1' when(tx_flag(kPulseTx.index) = '1') else
                 '1' when(tx_flag(kInitMikuTx.index) = '1') else
                 '1' when(tx_flag(kCheckSumTx.index) = '1') else
                 '1' when(tx_flag(kFskTx.index) = '1') else
                 '1' when(tx_flag(kFekTx.index) = '1') else
                  reg_valid_in when(tx_flag(kUserDataTx.Index) = '1') else '0';

  -- Link up process --------------------------------------------------------------------------
  u_init_process : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        tx_flag(kInitMikuTx.index)  <= '0';
      else
        if(instRx = WaitCbtUp and cbtTxBeat = '1') then
          tx_flag(kInitMikuTx.index)  <= '0';
        elsif(instRx = SendInitK1 and cbtTxBeat = '1') then
          init_ktype_char   <= GetInitK1(kNumEncodeBits);
          tx_flag(kInitMikuTx.index)  <= '1';
        elsif(instRx = SendInitK2 and cbtTxBeat = '1') then
          init_ktype_char   <= GetInitK2(kNumEncodeBits);
          tx_flag(kInitMikuTx.index)  <= '1';
        elsif(instRx = MikumariRxUp and cbtTxBeat = '1') then
          tx_flag(kInitMikuTx.index)  <= '0';
        end if;
      end if;

    end if;
  end process;

  -- Send first fsk --
  u_first_fst : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        req_first_fsk   <= '0';
        reg_uinit       <= (others => '0');
      else
        reg_uinit   <= reg_uinit(0) & tx_flag(kInitMikuTx.index);
        if(reg_uinit = "10") then
          req_first_fsk <= '1';
        elsif(tx_flag(kFskTx.index) = '1') then
          req_first_fsk <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Normal frame ---------------------------------------------------------------------------
  complement_check_sum  <= not reg_check_sum;

  u_check_sum : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        reg_check_sum   <= (others => '0');
--      elsif(cbtTxAck = '1' and tx_flag(kUserDataTx.index) = '1') then
      elsif(tx_ack = '1') then -- and tx_flag(kUserDataTx.index) = '1') then
        --reg_check_sum   <= std_logic_vector(unsigned(reg_check_sum) + unsigned(reg_data_in));
        reg_check_sum   <= std_logic_vector(unsigned(reg_check_sum) + unsigned(ifbuf_data_in));
      elsif(tx_flag(kFekTx.index) = '1' or first_fsk_sent = '0') then
        reg_check_sum   <= (others => '0');
      end if;
    end if;
  end process;

  -- Transmit  check-sum and k-char --
  u_check_sum_tx : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        tx_flag(kCheckSumTx.index)  <= '0';
        tx_flag(kFskTx.index)      <= '0';
        tx_flag(kFekTx.index)      <= '0';
      elsif((tx_flag(kLastData.index) = '1' and cbtTxAck = '1') or (tx_flag(kCsReserve.index) = '1' and cbtTxBeat = '1')) then
        if(tx_flag(kPulseReserve.index) = '1') then
          tx_flag(kCsReserve.index) <= '1';
        elsif(tx_flag(kPulseTx.index) = '1') then
          null;
        else
          tx_flag(kCsReserve.index)   <= '0';
          tx_flag(kCheckSumTx.index)  <= '1';
          tx_flag(kFskTx.index)       <= '0';
          tx_flag(kFekTx.index)       <= '0';
        end if;
      elsif((tx_flag(kCheckSumTx.index) = '1' and cbtTxAck = '1') or (tx_flag(kFekReserve.index) = '1' and cbtTxBeat = '1')) then
        if(tx_flag(kPulseReserve.index) = '1') then
          tx_flag(kFekReserve.index) <= '1';
          tx_flag(kCheckSumTx.index) <= '0';
        elsif(tx_flag(kPulseTx.index) = '1') then
          null;
        else
          tx_flag(kFekReserve.index)  <= '0';
          tx_flag(kCheckSumTx.index)  <= '0';
          tx_flag(kFekTx.index)       <= '1';
         end if;
      elsif((tx_flag(kFekTx.index) = '1' and cbtTxAck = '1') or (tx_flag(kFskReserve.index) = '1' and cbtTxBeat = '1') or req_first_fsk = '1') then
        if(tx_flag(kPulseReserve.index) = '1') then
          tx_flag(kFskReserve.index) <= '1';
          tx_flag(kFekTx.index)      <= '0';
        elsif(tx_flag(kPulseTx.index) = '1') then
          null;
        else
          tx_flag(kFskReserve.index) <= '0';
          tx_flag(kFekTx.index)      <= '0';
          tx_flag(kFskTx.index)      <= '1';
        end if;
      elsif((tx_flag(kFskTx.index) = '1' and cbtTxAck = '1') or (tx_flag(kFskReserve.index) = '1' and cbtTxBeat = '1')) then
        if(tx_flag(kPulseReserve.index) = '1') then
          null;
--          tx_flag(kFskReserve.index) <= '1';
        elsif(tx_flag(kPulseTx.index) = '1') then
          null;
        else
          tx_flag(kCheckSumTx.index)  <= '0';
          tx_flag(kFskTx.index)      <= '0';
          tx_flag(kFekTx.index)      <= '0';
        end if;
      end if;
    end if;
  end process;


  -- Pulse transfer -------------------------------------------------------------------------
  u_pulse_timing : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(cbtTxBeat = '1') then
        pulse_count   <= (others => '0');
      else
        pulse_count   <= std_logic_vector(unsigned(pulse_count) +1);
      end if;
    end if;
  end process;

  -- Pulse K-char generate --
  -- Low-Latency Mode (default) --
  gen_pkc_llm : if kHighPrecision = false generate
  begin
    u_pulse_gen : process(clkPar)
    begin
      if(clkPar'event and clkPar = '1') then
        if(srst = '1') then
          tx_flag(kPulseTx.index)       <= '0';
          tx_flag(kPulseReserve.index)  <= '0';
        else
          if(pulse_in = '1') then
            tx_flag(kPulseReserve.index)   <= '1';
            reg_pulse_count   <= pulse_count;
            reg_pulse_type    <= encodePulseType(pulseType);
          end if;

          if(reg_cbt_tx_beat = '1' and tx_flag(kPulseReserve.index) = '1') then
            tx_flag(kPulseReserve.index)           <= '0';
            tx_flag(kPulseTx.index)  <= '1';
          elsif(tx_flag(kPulseTx.index) = '1' and reg_cbt_tx_ack = '1') then
            tx_flag(kPulseTx.index)  <= '0';
          end if;

        end if;
      end if;
    end process;

    pulse_ktype_char  <= reg_pulse_type & reg_pulse_count;
  end generate;

  -- High-Precision Mode --
  gen_pkc_hpm : if kHighPrecision = true generate
  begin
    pulse_message   <= pulse_count & pulseReg;
    encoded_4b      <= encode3b4b(pulse_message(7 downto 5), running_disparity);
    encoded_6b      <= encode5b6b(pulse_message(4 downto 0), running_disparity);

    u_pulse_gen : process(clkPar)
    begin
      if(clkPar'event and clkPar = '1') then
        if(srst = '1') then
          tx_flag(kPulseTx.index)       <= '0';
          tx_flag(kPulseReserve.index)  <= '0';
          running_disparity             <= '0';
          done_1st_char                 <= '0';
        else
          if(pulse_in = '1') then
            tx_flag(kPulseReserve.index)   <= '1';
            reg_pulse_message   <= encoded_6b & encoded_4b;
            reg_pulse_type_hpm  <= encodePulseTypeHPM(pulseType, running_disparity);
            running_disparity   <= not running_disparity;
          end if;

          if(reg_cbt_tx_beat = '1' and tx_flag(kPulseReserve.index) = '1') then
            tx_flag(kPulseReserve.index)  <= '0';
            tx_flag(kPulseTx.index)       <= '1';
            -- 1st K-character --
            done_1st_char                 <= '0';
            reg_hpm_pulse_char            <= reg_pulse_type_hpm & reg_pulse_message(9 downto 8);
          elsif(tx_flag(kPulseTx.index) = '1' and reg_cbt_tx_ack = '1') then
            done_1st_char                 <= '1';
            -- 2nd K-character --
            reg_hpm_pulse_char            <= reg_pulse_message(7 downto 0);
            if(done_1st_char = '1') then
              tx_flag(kPulseTx.index) <= '0';
            end if;
          end if;

        end if;
      end if;
    end process;

    pulse_ktype_char  <= reg_hpm_pulse_char;
  end generate;

  -- Scrambler ------------------------------------------------------------------------------

  u_set_seed : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        first_fsk_sent  <= '0';
        set_seed        <= '0';
        state_seed      <= WaitLinkUp;
      else
        case state_seed is
          when WaitLinkUp =>
            first_fsk_sent  <= '0';
            set_seed        <= '0';
            if(req_first_fsk = '1') then
              state_seed  <= SendFirstFsk;
            end if;

          when SendFirstFsk =>
            if(cbtTxAck = '1' and tx_flag(kFskTx.Index) = '1') then
              state_seed  <= SetSeed;
            end if;

          when SetSeed =>
            set_seed    <= '1';
            state_seed  <= SeedIsSet;

          when SeedIsSet =>
            first_fsk_sent  <= '1';
            set_seed        <= '0';
            if(instRx = WaitCbtUp) then
              state_seed  <= WaitLinkUp;
            end if;

          when others =>
            null;

        end case;
      end if;
    end if;
  end process;

  gen_scrambler : if enScrambler = true generate
  begin

    u_prbs_en : process(clkPar)
    begin
      if(clkPar'event and clkPar = '1') then
        if(is_ktype_out = '0' and cbtTxAck = '1' and state_seed = SeedIsSet) then
          en_prbs_clk   <= '1';
        else
          en_prbs_clk   <= '0';
        end if;
      end if;
    end process;

    u_prbs : entity mylib.PRBS16
      port map
      (
        setSeed   => set_seed,
        clk       => clkPar,
        enClk     => en_prbs_clk,
        dataOut   => prbs_out
      );

      scramble_data_in    <= reg_data_in xor prbs_out(reg_data_in'range);
      scramble_check_sum  <= complement_check_sum xor prbs_out(complement_check_sum'range);
  end generate;

  gen_noscrambler : if enScrambler = false generate
  begin
    scramble_data_in    <= reg_data_in;
    scramble_check_sum  <= complement_check_sum;
  end generate;


end RTL;
