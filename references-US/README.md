# references

Clock generators for the MIKUMARI CDCM SERDES (500 MHz) and their helper module.

| Directory / File         | Module              | Input   | XDC                     | Default instance |
|--------------------------|---------------------|---------|-------------------------|------------------|
| `mmcm_cdcm_input100MHz/` | `mmcm_cdcm`         | 100 MHz | `mmcm_cdcm.xdc`         | `u_mmcm_cdcm`    |
| `mmcm_cdcm_input125MHz/` | `mmcm_cdcm_second2` | 125 MHz | `mmcm_cdcm_second2.xdc` | `u_MMCM_CDCM`    |
| `BUFG_CLR_DEV.v`         | `BUFG_CLR_DEV`      | -       | -                       | -                |

Both MMCMs output:

| Clock          | Frequency | Role          |
|----------------|-----------|---------------|
| `clk_fast`     | 500 MHz   | SERDES CLK    |
| `clk_slow`     | 125 MHz   | SERDES CLKDIV |
| `clk_slow_CLR` | 125 MHz   | Clock for `BUFG_CLR_DEV` |

## Usage

1. Add the two `.v` files of **one** of the `mmcm_cdcm_input*` directories, and `BUFG_CLR_DEV.v`.
2. Add the XDC in that directory (read it before your timing XDC).
   Edit the instance name in the XDC to match your instance path.
3. Connect `BUFG_CLR_DEV`:
   - `clk_CLR` <- `clk_slow_CLR`, `mmcm_cdcm_locked` <- `locked`
   - `BUFDIV_CE` / `BUFDIV_CLR` -> `BUFDIV_CE` / `BUFDIV_CLR` of the MMCM module
   - Use `mmcm_cdcm_locked_level2` as the locked signal for your logic.

`set_clock_groups` is not included. Add it in your XDC as needed, e.g.:

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks {clk_fast clk_slow clk_slow_CLR}] \
  -group [get_clocks <your_other_clk>]
```
