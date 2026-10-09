library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library mylib;
use mylib.defCDCM.all;
use mylib.defMikumari.all;

entity MikumariRx is
  generic
  (
    -- CBT --
    kNumEncodeBits    : integer:= 2;
    -- MIKUMARI --
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
    cbtUpIn     : in std_logic;  -- Cbt lane up signal
    mikuRxUp    : out std_logic; -- Mikumari RX is up.

    -- Data I/F --
    dataOut     : out CbtUDataType; -- User data output.
    validOut    : out std_logic;    -- Indicate current dataOut is valid.
    frameLast   : out std_logic;    -- Indicate current dataOut is the last data in a normal frame.
    checksumErr : out std_logic;    -- Check-sum error is happened in the present normal frame.
    frameBroken : out std_logic;    -- Frame start position is not correctly detected
    recvTermnd  : out std_logic;    -- Frame end position of the previsou frame is not correctly detected

    pulseOut    : out std_logic;    -- Reproduced one-shot pulse output.
    pulseType   : out MikumariPulseType;  -- 3-bit short message accompanying the pulse.
    pulseReg    : out MikumariHpmRegType; -- 4-bit additional pulse message; zero in Low-Latency mode.

    -- Back channel --
    instRx      : out MikumariBackChannelType;

    -- Cbt ports --
    isKtypeIn   : in std_logic;     -- Connect to CbtRx.
    cbtDataIn   : in CbtUDataType;  -- Connect to CbtRx.
    cbtValidIn  : in std_logic      -- Connect to CbtRx.

  );
end MikumariRx;

architecture RTL of MikumariRx is

  -- System --
  signal mikumari_rx_up       : std_logic;

  -- Cbt --
  signal cbt_up               : std_logic;
  signal data_in              : CbtUDataType;
  signal descranble_data_in   : CbtUDataType;
  signal valid_in             : std_logic;
  signal is_ktype             : std_logic;

  -- Data I/F --
  constant kNumRxStage        : integer:= 3;
  signal frame_end            : std_logic;
  signal frame_valid          : std_logic;
  type DataStageType is array (integer range kNumRxStage-1 downto 0) of CbtUDataType;
  signal reg_data             : DataStageType;
  signal reg_valid            : std_logic_vector(kNumRxStage-1 downto 0);
  signal reg_frame_broken     : std_logic_vector(kNumRxStage-1 downto 0);
  signal recv_terminated      : std_logic;
  signal checksum_error       : std_logic;
  signal reg_check_sum        : std_logic_vector(kWidthCheckSum-1 downto 0);

  -- pulse --
  signal pulse_out, reg_pulse_out  : std_logic;
  signal reg_pulse_type       : MikumariPulseType;
  signal reg_pulse_timing     : std_logic_vector(kWidthPulseCount-1 downto 0);
  signal sr_pulse             : std_logic_vector(kWidthPulseSr-1 downto 0);
  signal decoded_data_in      : std_logic_vector(MikumariPulseType'high+1 downto 0);
  signal is_pulse_char        : std_logic;
  signal decoded_pulse_type   : MikumariPulseType;
  -- High-Precision mode --
  signal decoded_data_in_rdm      : std_logic_vector(MikumariPulseType'high+1 downto 0);
  signal decoded_data_in_rdp      : std_logic_vector(MikumariPulseType'high+1 downto 0);
  signal first_is_pulse_char      : std_logic;
  signal delayed_is_pulse         : std_logic;
  signal decoded_pulse_type_rdm   : MikumariPulseType;
  signal decoded_pulse_type_rdp   : MikumariPulseType;
  signal received_1st_kchar       : std_logic:= '0';
  signal hpm_pulse_error          : std_logic;

  -- Initialize --
  signal mikumari_inst        : MikumariBackChannelType;
  signal first_fsk_recv       : std_logic;

   -- Scrambler --
   signal set_seed             : std_logic;
   signal en_prbs_clk          : std_logic;
   constant kPrbsLength        : positive:= 16;
   signal prbs_out             : std_logic_vector(kPrbsLength-1 downto 0);
   signal state_seed           : SetSeedType;

  -- debug --
  attribute mark_debug  : boolean;
  attribute mark_debug  of frame_end          : signal is enDEBUG;
  attribute mark_debug  of reg_check_sum      : signal is enDEBUG;
  attribute mark_debug  of checksum_error     : signal is enDEBUG;
  attribute mark_debug  of pulse_out          : signal is enDEBUG;
  attribute mark_debug  of reg_pulse_timing   : signal is enDEBUG;
  attribute mark_debug  of mikumari_inst      : signal is enDEBUG;
  attribute mark_debug  of en_prbs_clk        : signal is enDEBUG;
  attribute mark_debug  of state_seed         : signal is enDEBUG;

begin
  -- ======================================================================
  --                                 body
  -- ======================================================================

  cbt_up    <= cbtUpIn;
  mikuRxUp  <= mikumari_rx_up and first_fsk_recv;

  instRx    <= mikumari_inst;

  dataOut   <= reg_data(2);
  validOut  <= reg_valid(2);
  frameLast <= frame_end;
  checksumErr   <= checksum_error;
  frameBroken <= reg_frame_broken(2);
  recvTermnd  <= recv_terminated;

  pulseOut  <= reg_pulse_out;
  pulseType <= reg_pulse_type;

  gen_noscrambler : if enScrambler = false generate
  begin
    descranble_data_in <= cbtDataIn;
  end generate;

  gen_llm_pulse_decode : if kHighPrecision = false generate
  begin
    decoded_data_in     <= decodePulseType(data_in);
    is_pulse_char       <= decoded_data_in(kIsPulseIndex) and is_ktype;
    decoded_pulse_type  <= decoded_data_in(MikumariPulseType'range);
  end generate;

  gen_hpm_pulse_decode : if kHighPrecision = true generate
  begin
    decoded_data_in_rdm <= decodePulseTypeHPM_RDM(data_in);
    decoded_data_in_rdp <= decodePulseTypeHPM_RDP(data_in);

    first_is_pulse_char <= (decoded_data_in_rdm(kIsPulseIndex) or decoded_data_in_rdp(kIsPulseIndex)) and is_ktype;
    is_pulse_char       <= first_is_pulse_char or delayed_is_pulse;
    u_delay_is_pulse : process(clkPar)
    begin
      if(clkPar'event and clkPar = '1') then
        if(valid_in = '1') then
          delayed_is_pulse  <= first_is_pulse_char;
        end if;
      end if;
    end process;

    decoded_pulse_type  <= decoded_data_in_rdm(MikumariPulseType'range) when (decoded_data_in_rdm(kIsPulseIndex) = '1') else decoded_data_in_rdp(MikumariPulseType'range);
  end generate;

  data_in   <= cbtDataIn;
  valid_in  <= cbtValidIn;
  is_ktype  <= isKtypeIn;

  u_output_reg : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        reg_valid         <= (others => '0');
        checksum_error    <= '0';
        frame_valid       <= '0';
        reg_frame_broken  <= (others => '0');
        recv_terminated   <= '0';

      elsif(valid_in = '1' and mikumari_rx_up = '1' and is_pulse_char = '0') then
        if(is_ktype = '0') then
          --reg_data_st1    <= data_in;
          reg_data(0)     <= descranble_data_in;
          reg_valid(0)    <= frame_valid;

          if(frame_valid = '0') then
            reg_frame_broken(0)  <= '1';
          else
            reg_frame_broken(0)  <= '0';
          end if;
        elsif(is_ktype = '1') then
          reg_valid(0)     <= '0';
        end if;

        if(is_ktype = '1' and data_in = kMikumariFsk) then
          frame_valid     <= '1';
          reg_frame_broken(0)   <= '0';
          checksum_error  <= '0';

          if(frame_valid = '1') then
            recv_terminated <= '1';
            reg_valid(1)    <= '0';
          else
            recv_terminated <= '0';
          end if;
        elsif(is_ktype = '1' and data_in = kMikumariFek) then
          reg_valid(1)          <= '0';
          frame_end             <= '1';
          frame_valid           <= '0';
          reg_frame_broken(1)   <= '0';
          recv_terminated       <= '0';

          if(reg_check_sum = X"FF") then
            checksum_error  <= '0';
          elsif(reg_check_sum /= X"FF" and frame_valid = '1') then
            checksum_error  <= '1';
          else
            checksum_error  <= '0';
          end if;

        else
          reg_data(1)           <= reg_data(0);
          reg_valid(1)          <= reg_valid(0);
          frame_end             <= '0';
          reg_frame_broken(1)   <= reg_frame_broken(0);
          recv_terminated       <= '0';
          checksum_error        <= '0';
        end if;

        reg_data(2)           <= reg_data(1);
        reg_valid(2)          <= reg_valid(1);
        reg_frame_broken(2)   <= reg_frame_broken(1);
      else
        reg_valid(2)          <= '0';
        frame_end             <= '0';
        reg_frame_broken(2)   <= '0';
        recv_terminated       <= '0';
      end if;
    end if;
  end process;

  u_checksum : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1' or mikumari_rx_up = '0') then
        reg_check_sum <= (others => '0');
      else
        if(valid_in = '1' and mikumari_rx_up = '1')then
          if(is_ktype = '0') then
            reg_check_sum   <= std_logic_vector(unsigned(reg_check_sum) + unsigned(descranble_data_in));
          elsif(is_ktype = '1' and data_in = kMikumariFsk) then
            reg_check_sum   <= (others => '0');
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Cbt port --

  -- Link up process --
  u_init_sm : process(clkPar)
    constant  kNumCount   : integer:= 63;
    variable  count   : integer range 0 to kNumCount:= 0;
    variable  reserve : std_logic:= '0';
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        mikumari_inst   <= WaitCbtUp;
        mikumari_rx_up  <= '0';
        count           := 0;
        reserve         := '0';
      else
        case mikumari_inst is
          when WaitCbtUp =>
            mikumari_rx_up  <= '0';
            count           := 0;
            reserve         := '0';
            if(cbt_up = '1') then
              mikumari_inst   <= SendInitK1;
            end if;

          when SendInitK1 =>
            if(valid_in = '1') then
              if(data_in = GetInitK1(kNumEncodeBits)) then
                reserve   := '1';
              end if;

              if(cbt_up = '0') then
                mikumari_inst   <= WaitCbtUp;
              elsif(count = kNumCount-1 and reserve = '1') then
                count           := 0;
                reserve         := '0';
                mikumari_inst   <= SendInitK2;
              end if;

              if(count /= kNumCount-1) then
                count   := count +1;
              end if;
            end if;

          when SendInitK2 =>
            if(valid_in = '1') then
              if(data_in = GetInitK2(kNumEncodeBits)) then
                reserve   := '1';
              end if;

              if(cbt_up = '0') then
                mikumari_inst   <= WaitCbtUp;
              elsif(count > 0 and reserve = '1') then
                count           := 0;
                reserve         := '0';
                mikumari_inst   <= MikumariRxUp;
              end if;

              if(count /= kNumCount-1) then
                count   := count +1;
              end if;
            end if;

          when MikumariRxUp =>
            mikumari_rx_up  <= '1';
            if(cbt_up = '0') then
              mikumari_inst   <= WaitCbtUp;
            end if;

        end case;
      end if;
    end if;
  end process;

  -- Pulse recovery --
  -- Low-Lantency mode --
  gen_llm_pulse_recvery : if kHighPrecision = false generate
  begin
    u_pulse_recovery : process(clkPar)
    begin
      if(clkPar'event and clkPar = '1') then
        if(valid_in = '1' and is_pulse_char = '1') then
          reg_pulse_type    <= decoded_pulse_type;
          reg_pulse_timing  <= data_in(kWidthPulseCount-1 downto 0);
          sr_pulse          <= sr_pulse(kWidthPulseSr-2 downto 0) & '1';
        else
          sr_pulse          <= sr_pulse(kWidthPulseSr-2 downto 0) & '0';
        end if;

        reg_pulse_out   <= pulse_out;
      end if;
    end process;

    pulse_out   <= sr_pulse(to_integer(unsigned(reg_pulse_timing)));
    pulseReg    <= (others => '0');
  end generate;

  -- High-Precision mode --
  gen_hpm_pulse_recvery : if kHighPrecision = true generate
  begin
    u_pulse_recovery : process(clkPar)
      variable  encoded_4b      : std_logic_vector(3 downto 0);
      variable  encoded_6b      : std_logic_vector(5 downto 0);
      variable  decoded_3b_rdm  : std_logic_vector(3 downto 0);
      variable  decoded_3b_rdp  : std_logic_vector(3 downto 0);
      variable  decoded_5b_rdm  : std_logic_vector(5 downto 0);
      variable  decoded_5b_rdp  : std_logic_vector(5 downto 0);
      variable  pulse_message   : HpmPulseMessageType;
    begin
      if(clkPar'event and clkPar = '1') then
        if(srst = '1') then
          received_1st_kchar  <= '0';
        elsif(valid_in = '1' and is_pulse_char = '1') then
          if(received_1st_kchar = '0') then
            -- 1st K-character --
            reg_pulse_type          <= decoded_pulse_type;
            encoded_6b(5 downto 4)  := data_in(1 downto 0);
            received_1st_kchar      <= '1';
          else
            encoded_6b(3 downto 0)  := data_in(7 downto 4);
            encoded_4b              := data_in(3 downto 0);
            decoded_3b_rdm          := decode3b4b_RDM(encoded_4b);
            decoded_3b_rdp          := decode3b4b_RDP(encoded_4b);
            decoded_5b_rdm          := decode5b6b_RDM(encoded_6b);
            decoded_5b_rdp          := decode5b6b_RDP(encoded_6b);

            if(decoded_3b_rdm(decoded_3b_rdm'high) = '1' and decoded_5b_rdm(decoded_5b_rdm'high) = '1') then
              pulse_message(7 downto 5) := decoded_3b_rdm(2 downto 0);
              pulse_message(4 downto 0) := decoded_5b_rdm(4 downto 0);
              reg_pulse_timing          <= pulse_message(kPosPulseCount'range);
              pulseReg                  <= pulse_message(kPosPulseReg'range);
            elsif(decoded_3b_rdp(decoded_3b_rdm'high) = '1' and decoded_5b_rdp(decoded_5b_rdm'high) = '1') then
              pulse_message(7 downto 5) := decoded_3b_rdp(2 downto 0);
              pulse_message(4 downto 0) := decoded_5b_rdp(4 downto 0);
              reg_pulse_timing          <= pulse_message(kPosPulseCount'range);
              pulseReg                  <= pulse_message(kPosPulseReg'range);
            else
              hpm_pulse_error           <= '1';
            end if;

            received_1st_kchar      <= '0';
            sr_pulse                <= sr_pulse(kWidthPulseSr-2 downto 0) & '1';
          end if;
        else
          hpm_pulse_error           <= '0';
          sr_pulse                  <= sr_pulse(kWidthPulseSr-2 downto 0) & '0';
        end if;

        reg_pulse_out   <= pulse_out;
      end if;
    end process;

    pulse_out   <= sr_pulse(to_integer(unsigned(reg_pulse_timing)));
  end generate;


  u_set_seed : process(clkPar)
  begin
    if(clkPar'event and clkPar = '1') then
      if(srst = '1') then
        first_fsk_recv  <= '0';
        set_seed        <= '0';
        state_seed      <= WaitLinkUp;
      else
        case state_seed is
          when WaitLinkUp =>
            first_fsk_recv  <= '0';
            set_seed        <= '0';
            if(mikumari_rx_up = '1') then
              state_seed  <= WaitFirstFsk;
            end if;

          when WaitFirstFsk =>
            if(mikumari_rx_up = '0') then
              state_seed  <= WaitLinkUp;
            elsif(valid_in = '1' and is_ktype = '1' and data_in = kMikumariFsk) then
              state_seed  <= SetSeed;
            end if;

          when SetSeed =>
            set_seed    <= '1';
            state_seed  <= SeedIsSet;

          when SeedIsSet =>
            set_seed        <= '0';
            first_fsk_recv  <= '1';
            if(mikumari_rx_up = '0') then
              state_seed  <= WaitLinkUp;
            end if;

          when others =>
            null;

        end case;
      end if;
    end if;
  end process;

  -- Scrambler --
  gen_scrambler : if enScrambler = true generate
  begin

    u_prbs_en : process(clkPar)
    begin
      if(clkPar'event and clkPar = '1') then
        if(is_ktype = '0' and valid_in = '1' and state_seed = SeedIsSet) then
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

      descranble_data_in <= cbtDataIn xor prbs_out(data_in'range);
  end generate;

end RTL;
