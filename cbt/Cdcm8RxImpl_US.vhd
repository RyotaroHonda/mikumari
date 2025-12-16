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

entity Cdcm8RxImpl_US is
  generic
  (
    kSysW         : integer:= 1;  -- width of the ata for the system
    kDevW         : integer:= 8; -- width of the ata for the device
    kSelCount     : integer:= 3; -- Selects the counter to use for IDELAYCTRL
    kDiffTerm     : boolean:= TRUE;
    kRxPolarity   : boolean:= FALSE;    -- If true, inverts Rx polarity
    kIoStandard   : string:= "LVDS";    -- IOSTANDARD of OBUFDS
    kIoDelayGroup : string:= "cdcm_rx"; -- IODELAY_GROUP
    kFreqRefClk   : real;            -- Frequency of refclk for IDELAYCTRL (MHz).
    kBitslice0    : boolean   -- Set true if the signal line is connected to the pad on bitslice 0

  );
  port
  (
    pwrOnRst          : in  std_logic;

    -- IBUFDS
    dInFromPinP       : in  std_logic;
    dInFromPinN       : in  std_logic;

    -- IDELAY
    rstIDelay         : in  std_logic;
    ceIDelay          : in  std_logic;
    incIDelay         : in  std_logic;

    -- ISERDES
    cdOutFromO        : out std_logic;
    dOutToDevice      : out std_logic_vector(kDevW-1 downto 0);
    bitslip           : in  std_logic;
    tapIn             : in  std_logic_vector(4 downto 0);
    tapOut            : out std_logic_vector(4 downto 0);
    CNTVALUEOUT       : out std_logic_vector(kCNTVALUEbit-1 downto 0);
    CNTVALUEOUT_slave : out std_logic_vector(kCNTVALUEbit-1 downto 0);

    enVtc             : in  std_logic;

    -- Clock and reset
    clkIn             : in  std_logic;
    clkDivIn          : in  std_logic;
    ioReset           : in  std_logic;
    --ioReset           => '0',

    readyCtrl         : in std_logic;
    idelayInitDoneOut : out std_logic;
    cntValueOutLevel2Out      : out std_logic_vector(kCNTVALUEbit-1 downto 0);
    cntValueSlaveOutLevel2Out : out std_logic_vector(kCNTVALUEbit-1 downto 0)
  );
end Cdcm8RxImpl_US;

architecture RTL of Cdcm8RxImpl_US is
  function to_string(b : boolean) return string is
  begin
    if b then
      return "TRUE";
    else
      return "FALSE";
    end if;
  end function;

  component Cdcm8RxImpl_US_verilog
    generic (
        kSysW         : integer := 1;
        kDevW         : integer := 8;
        kSelCount     : integer := 3;
        kDiffTerm     : string  := "TRUE";
        kRxPolarity   : string  := "FALSE";
        kIoStandard   : string := "LVDS";
        kIoDelayGroup : string := "cdcm_rx";
        kFreqRefClk   : integer := 500;
        kBitslice0    : boolean := FALSE
    );
   port (
        pwrOnRst          : in  std_logic;
        dInFromPinP      : in  std_logic;
        dInFromPinN      : in  std_logic;
        rstIDelay        : in  std_logic;
        ceIDelay         : in  std_logic;
        incIDelay        : in  std_logic;
        cdOutFromO      : out std_logic;
        dOutToDevice    : out std_logic_vector(kDevW-1 downto 0);
        bitslip         : in  std_logic;
        tapIn           : in  std_logic_vector(4 downto 0);
        tapOut          : out std_logic_vector(4 downto 0);
        CNTVALUEOUT     : out std_logic_vector(kCNTVALUEbit-1 downto 0);
        CNTVALUEOUT_slave : out std_logic_vector(kCNTVALUEbit-1 downto 0);
        enVtc           : in  std_logic;
        clkIn           : in  std_logic;
        clkDivIn       : in  std_logic;
        ioReset         : in  std_logic;
        readyCtrl       : in std_logic;
        idelayInitDoneOut : out std_logic;
        cntValueOutLevel2Out      : out std_logic_vector(kCNTVALUEbit-1 downto 0);
        cntValueSlaveOutLevel2Out : out std_logic_vector(kCNTVALUEbit-1 downto 0)
    );
   end component;


begin

    u_cdcm_rx_iserdes: Cdcm8RxImpl_US_verilog
    generic map (
        kSysW         => kSysW,
        kDevW         => kDevW,
        kSelCount     => kSelCount,
        kDiffTerm     => to_string(kDiffTerm),
        kRxPolarity   => to_string(kRxPolarity),
        kIoStandard   => kIoStandard,
        kIoDelayGroup => kIoDelayGroup,
        kFreqRefClk   => integer(kFreqRefClk),
        kBitslice0    => kBitslice0
    )
    port map (
        pwrOnRst          => pwrOnRst,
        dInFromPinP      => dInFromPinP,
        dInFromPinN      => dInFromPinN,
        rstIDelay        => rstIDelay,
        ceIDelay         => ceIDelay,
        incIDelay        => incIDelay,
        cdOutFromO      => cdOutFromO,
        dOutToDevice    => dOutToDevice,
        bitslip         => bitslip,
        tapIn           => tapIn,
        tapOut          => tapOut,
        CNTVALUEOUT     => CNTVALUEOUT,
        CNTVALUEOUT_slave => CNTVALUEOUT_slave,
        enVtc           => enVtc,
        clkIn           => clkIn,
        clkDivIn       => clkDivIn,
        ioReset         => ioReset,
        readyCtrl       => readyCtrl,
        idelayInitDoneOut => idelayInitDoneOut,
        cntValueOutLevel2Out      => cntValueOutLevel2Out,
        cntValueSlaveOutLevel2Out => cntValueSlaveOutLevel2Out
    );



end RTL;
