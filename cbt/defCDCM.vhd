library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package defCDCM is

  -- SerDes parameter --
  constant kWidthSys        : integer:= 1;
  constant kWidthDev        : integer:= 10;
  subtype CdcmPatternType is std_logic_vector(kWidthDev-1 downto 0);

  constant kWidthPayload    : integer:= 4;
  constant kPaylowdPos      : std_logic_vector(kWidthDev-4 downto 3):= "0011";

  -- SerDes pattern --
  constant kCDCMPattern     : CdcmPatternType:= "000----111"; -- Center 4-bits are payload.
  constant kAllZeroCDCM     : CdcmPatternType:= (others => '0');
  constant kInitPCDCM       : CdcmPatternType:= B"000_0111_111";
  constant kInitMCDCM       : CdcmPatternType:= B"000_0001_111";
  constant kIdleCDCM        : CdcmPatternType:= B"000_0011_111";

  -- TX ---------------------------------------------------------------------------------
  subtype  TxModeType is std_logic_vector(1 downto 0);
  constant kDisaTx          : TxModeType:= "11";
  constant kIdleTx          : TxModeType:= "10";
  constant kInitTx          : TxModeType:= "01";
  constant kNormalTx        : TxModeType:= "00";

  -- Latency scan --
  constant kRefLatency      : integer:= 4;
  constant kWidthScanTdc    : integer:= 8;
  type SerdesOffsetType is array(7 downto 0) of signed(kWidthScanTdc-1 downto 0);
  function TdcFineCount(bit_patt : std_logic_vector) return signed;

  -- RX ---------------------------------------------------------------------------------
  subtype  RxInitStatusType is std_logic_vector(2 downto 0);
  constant kWaitClkReady      : RxInitStatusType:= "000";
  constant kAdjustingIdelay   : RxInitStatusType:= "001";
  constant kTryingBitslip     : RxInitStatusType:= "010";
  constant kInitFinish        : RxInitStatusType:= "011";
  constant kUndefinedRx       : RxInitStatusType:= "111";

  -- IDELAY
  constant kInitialDelayTime : real:= 1000.0;
  constant kWidthTap        : integer:= 5;
  --constant kWidthTap        : integer:= 9;
  constant kCNTVALUEbit     : integer:= 9;

  constant kNumTaps         : integer:= 32;
  constant kMaxIdelayCheck  : integer:= 4096; --256;
  constant kSuccThreshold   : integer:= 4000; --230;

  --constant kWidthCheckCount : integer:= 8;
  --constant kLoadWait        : integer:= 4;
  constant kLoadWait        : integer:= 4;
  constant kLoadWait_US     : integer:= 12;     -- 10 + 2 yobi
  constant kWaitRDY         : integer:= 4096;

  constant kAcceptUnstableLength  : integer:= 4;
  constant kMaxRetryWait    : integer:= 65535;

  function GetTapDelay(freq_idelayctrl_ref : real) return real;
  function GetPlateauLength(tap_delay       : real;
                            freq_fast_clock : real) return integer;


  procedure GetPlateauLengthUltrascale(
    signal  CNTVALUEOUTInit : in std_logic_vector(kCNTVALUEbit-1 downto 0);
    signal result_out : out integer;
    freq_fast_clock : real
  );


   type IdelayInitType is (
    Idle,
    Init,
    Read,
    Check,
    Done
   );

   type IdelayControlProcessType is (
    Init,
    RetryWait,
    Check,
    NumTrialCheck,
    Increment,
    Decrement,
    WaitState,
    IdelayAdjusted,
    IdelayFailure
    );

   type IdelayControlProcessType_US is (
    Idle,
    Init,
    RetryWait,
    Check,
    NumTrialCheck,
    Increment,
    EnVtcChangeIncrement,
    EnVtcChangeDecrement,
    Decrement,
    WaitState,
    IdelayAdjusted,
    IdelayFailure
    );

  -- BITSLIP
  constant kMaxPattCheck    : integer:= 32;
  --constant kPattOkThreshold : integer:= 10;
  constant kPattOkThreshold : integer:= 16;

  constant kWidthBitSlipNum   : integer:= 4;
  constant kWidthSerdesOffset : integer:= 4;

  type BitslipControlProcessType is (
    Init,
    WaitStart,
    CheckIdlePatt,
    --NumTrialCheck,
    BitSlip,
    WaitState,
    BitslipFinished,
    BitslipFailure
    );

  -- Pattern match --
  constant kNumPattMatchCycle : integer:= 16;

  -- CBT --------------------------------------------------------------------------------
  -- CBT character : (MSB) 2-bit header + 8-bit data (LSB)

  constant kNumCbtHeaderBits : integer:= 2;
  constant kNumUserDataBits  : integer:= 8;
  constant kNumCbtCharBits   : integer:= kNumCbtHeaderBits + kNumUserDataBits;

  subtype CbtHeaderType is std_logic_vector(kNumCbtHeaderBits-1 downto 0);
  constant kKtype   : CbtHeaderType:= "00";
  constant kDtypeP  : CbtHeaderType:= "01";
  constant kDtypeM  : CbtHeaderType:= "10";
  constant kTtype   : CbtHeaderType:= "11";

  subtype  CbtCharType is std_logic_vector(kNumCbtCharBits-1 downto 0);
  -- For CDCM-10-1.5 --
  constant kTTypeCharInit1_1P5   : CbtCharType:= kTtype & B"0001_0110";
  constant kTTypeCharInit2_1P5   : CbtCharType:= kTtype & B"0010_1001";
  constant kTTypeCharDogfood     : CbtCharType:= kTtype & B"0110_1001";
  -- For CDCM-10-2.5 --
  constant kTTypeCharInit1_2P5   : CbtCharType:= kTtype & B"0001_0111";
  constant kTTypeCharInit2_2P5   : CbtCharType:= kTtype & B"0010_1000";

  function GetInit1Char(payload_width: integer) return CbtCharType;
  function GetInit2Char(payload_width: integer) return CbtCharType;


  subtype  CbtUDataType is std_logic_vector(kNumUserDataBits-1 downto 0);

  -- CBT back channel instruction --
  type CbtBackChannelType is (
    SendZero,
    SendIdle,
    SendInitPattern,
    SendTCharI1,
    SendTCharI2,
    StateCbtRxUp,
    DelayReinit
  );

  -- Watch dog timer --
  constant kWidthWatchDogTimer  : integer:= 20;
  constant kMaxWDT              : std_logic_vector(kWidthWatchDogTimer-1 downto 0):= X"FFFFF";

  -- RX quality check --
  constant kCheckFrameLength    : integer:= 512;
  constant kLowQualityTh        : integer:= integer(0.01*real(kCheckFrameLength)); -- 1%
  constant kSyncLength          : integer:= 4;

  -- Primary wait --
  constant kWidthInitDelay      : integer:= 18;

end package defCDCM;
-- ----------------------------------------------------------------------------------
-- Package body
-- ----------------------------------------------------------------------------------
package body defCDCM is

  -- TdcFineCount --------------------------------------------------------------
  function TdcFineCount(bit_patt : std_logic_vector) return signed is
  begin
    case bit_patt is
      when X"8f" => return to_signed(-4, kWidthScanTdc);
      when X"C7" => return to_signed(-3, kWidthScanTdc);
      when X"E3" => return to_signed(-2, kWidthScanTdc);
      when X"F1" => return to_signed(-1, kWidthScanTdc);
      when X"F8" => return to_signed(0, kWidthScanTdc);
      when X"7C" => return to_signed(1, kWidthScanTdc);
      when X"3E" => return to_signed(2, kWidthScanTdc);
      when X"1F" => return to_signed(3, kWidthScanTdc);
      when others => return to_signed(-7, kWidthScanTdc);
    end case;
  end TdcFineCount;

  -- GetTapDelay --------------------------------------------------------------
  function GetTapDelay(freq_idelayctrl_ref : real) return real is
    -- Argument : Frequency of refclk for IDELAYCTRL (MHz). Integer number.
    -- Return   : Delay per tap in IDELAY (ps). Real number.
    variable result : real;
  begin
    if (190.0 < freq_idelayctrl_ref and freq_idelayctrl_ref < 210.0) then
      result  := 78.0;
    elsif(290.0 < freq_idelayctrl_ref and freq_idelayctrl_ref < 310.0) then
      result  := 52.0;
    elsif(390.0 < freq_idelayctrl_ref and freq_idelayctrl_ref < 410.0) then
      result  := 39.0;
    else
      result  := 0.0;
    end if;

    return result;

  end GetTapDelay;


  -- GetPlateauLength ---------------------------------------------------------
  function GetPlateauLength(tap_delay       : real;
                            freq_fast_clock : real) return integer is
                            -- tap_delay : IDELAY tap delay (ps).
                            -- freq_fast_clock : Frequency of SERDES fast clock (MHz)
    constant kStableRange          : real:= 0.65;
    constant kExpectedStableLength : real:= 1.0/(2.0*freq_fast_clock)*1000.0*1000.0*kStableRange; -- [ps]
    constant kMaxLength            : integer:= 12;
    variable result                : integer:= integer(kExpectedStableLength/tap_delay);
  begin
    if(result > kMaxLength) then
      result  := kMaxLength;
    end if;
    return result;
  end GetPlateauLength;

  procedure GetPlateauLengthUltrascale(
    signal  CNTVALUEOUTInit : in std_logic_vector(kCNTVALUEbit-1 downto 0);
    signal result_out : out integer;
    freq_fast_clock : real
  ) is

    constant kStableRange          : real:= 0.65;
    constant kExpectedStableLength : real:= 1.0/(2.0*freq_fast_clock)*1000.0*1000.0*kStableRange; -- [ps]
    constant kMaxLength            : integer:= 12;
    variable CNTVALUEOUTInt : integer;
    variable k32tap_delay : real;
    variable result : integer;
  begin

  if CNTVALUEOUTInt /= 0 then
    k32tap_delay := kInitialDelayTime / (real(CNTVALUEOUTInt) - 54.0) * 32.0 ;
  else
    k32tap_delay := 1.0;
  end if;

  result   :=  integer(kExpectedStableLength/k32tap_delay);


    if(result > kMaxLength) then
      result_out  <= kMaxLength;
    else
      result_out <= integer(kExpectedStableLength/k32tap_delay);
    end if;

  end procedure;


  function GetPlateauLengthUltrascale2(CNTVALUEOUTInit       : real;
                            freq_fast_clock : real) return integer is
                            -- tap_delay : IDELAY tap delay (ps).
                            -- freq_fast_clock : Frequency of SERDES fast clock (MHz)
    constant kStableRange          : real:= 0.65;
    constant kExpectedStableLength : real:= 1.0/(2.0*freq_fast_clock)*1000.0*1000.0*kStableRange; -- [ps]
    constant kMaxLength            : integer:= 12;

    -- 32 -->The lower 4 bits are 0.
    constant k32tap_delay          : real:=  real(kInitialDelayTime) / (CNTVALUEOUTInit * 32.0);
    variable result                : integer:= integer(kExpectedStableLength/k32tap_delay);
  begin
    if(result > kMaxLength) then
      result  := kMaxLength;
    end if;
    return result;
  end GetPlateauLengthUltrascale2;

  -- GetInit1Char -------------------------------------------------------------
  function GetInit1Char(payload_width: integer) return CbtCharType is
  begin
    case payload_width is
      when 1      => return(kTTypeCharInit1_1P5);
      when 2      => return(kTTypeCharInit1_2P5);
      when others => return(kTTypeCharInit1_1P5);
    end case;
  end GetInit1Char;

  -- GetInit2Char -------------------------------------------------------------
  function GetInit2Char(payload_width: integer) return CbtCharType is
  begin
    case payload_width is
      when 1      => return(kTTypeCharInit2_1P5);
      when 2      => return(kTTypeCharInit2_2P5);
      when others => return(kTTypeCharInit2_1P5);
    end case;
  end GetInit2Char;


end package body defCDCM;
