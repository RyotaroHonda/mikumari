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

entity Cdcm8TxImpl_US is
  generic
  (
    kSysW        : integer:= 1;  -- width of the ata for the system
    kDevW        : integer:= 8; -- width of the ata for the device
    kIoStandard  : string:= "LVDS" -- IOSTANDARD of OBUFDS
  );
  port
  (
    -- From the device to the system
    dInFromDevice   : in std_logic_vector(kDevW-1 downto 0);
    dOutToPinP      : out std_logic;
    dOutToPinN      : out std_logic;
    -- Phase Offset --
    offsetTable     : out SerdesOffsetType;
    scanFinished    : out std_logic;
    -- Clock and reset
    clkIn           : in std_logic;
    clkDivIn        : in std_logic;
    ioReset         : in std_logic
  );
end Cdcm8TxImpl_US;

architecture RTL of Cdcm8TxImpl_US is

    component Cdcm8TxImpl_US_verilog
        generic (
            kSysW        : integer := 1;
            kDevW        : integer := 8;
            kIoStandard  : string := "LVDS";
            kWidthScanTdc : integer := 8
        );
        Port (
            -- From the device to the system
            dInFromDevice : in std_logic_vector(7 downto 0);
            dOutToPinP    : out std_logic;
            dOutToPinN    : out std_logic;

            -- Phase Offset
            offsetTable0  : out signed(kWidthScanTdc-1 downto 0);
            offsetTable1  : out signed(kWidthScanTdc-1 downto 0);
            offsetTable2  : out signed(kWidthScanTdc-1 downto 0);
            offsetTable3  : out signed(kWidthScanTdc-1 downto 0);
            offsetTable4  : out signed(kWidthScanTdc-1 downto 0);
            offsetTable5  : out signed(kWidthScanTdc-1 downto 0);
            offsetTable6  : out signed(kWidthScanTdc-1 downto 0);
            offsetTable7  : out signed(kWidthScanTdc-1 downto 0);
            scanFinished  : out std_logic;

            -- Clock and reset
            clkIn         : in std_logic;
            clkDivIn      : in std_logic;
            ioReset       : in std_logic
        );
    end component;


begin

    --u_cdcm_rx_iserdes : entity mylib.Cdcm8TxImpl_verilog
    u_cdcm_rx_iserdes: Cdcm8TxImpl_US_verilog
      generic map
      (-- width of the data for the system
        kSysW       => kSysW,
        -- width of the data for the device
        kDevW       => kDevW,
        -- IOSTANDARD
        kIoStandard => kIoStandard,
        kWidthScanTdc => 8
        )
      port map (
            -- From the device to the system
            dInFromDevice => dInFromDevice,
            dOutToPinP    => dOutToPinP,
            dOutToPinN    => dOutToPinN,

            -- Phase Offset
            offsetTable0  => offsetTable(0),
            offsetTable1  => offsetTable(1),
            offsetTable2  => offsetTable(2),
            offsetTable3  => offsetTable(3),
            offsetTable4  => offsetTable(4),
            offsetTable5  => offsetTable(5),
            offsetTable6  => offsetTable(6),
            offsetTable7  => offsetTable(7),
            scanFinished  => scanFinished,

            -- Clock and reset
            clkIn         => clkIn,
            clkDivIn      => clkDivIn,
            ioReset       => ioReset
        );


end RTL;
