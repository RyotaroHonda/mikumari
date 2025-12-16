# MIKUMARI

Official repository of MIKUMARI.

Stable version: 3.0

[Change log](ChangeLog.md)

## [User Guide](https://ryotarohonda.github.io/ug-mikumari/)

## Test condition

Currently, only the AMD FPGAs are supported.

### Tested FPGAs and condition

| FPGA              | Vender | Product number | Reference cock freq. | Comments                              |
| ---               | ---    | ---            | ---                  | ---                                   |
| Kintex-7          | AMD    | XC7K160T-2     | Up to 125 MHz        | CDCM-10-1.5, 2.5, and CDCM-8-1.5, 2.5 |
| Artix-7           | AMD    | XC7A200T-1     | 100 MHz              | CDCM-10-1.5, CDCM-8-1.5               |
| Artix UltraScale+ | AMD    | XCAU25P-1      | Up to 125 MHz        | CDCM-8-1.5                            |

## Installation

Tested with Vivado 2023.1.1 or before. Please add sources to your Vivado project or use gitsubmodule.

### VHDL-2008

Until v1.1, defMIKUMARI.vhd is described with VHDL-2008. You need to change the file type to VHDL 2008 after adding the source files.

From v2.0, No source file written by VHDL-2008

## License

This project is dual licensed under the Apache License Version 2.0 and Mozilla Public License Version 2.0.

For details, see [the license notice](LICENSE.md).
