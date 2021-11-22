# :game_die: neoTRNG

**A Tiny and Platform-Independent True Random Number Generator for _any_ FPGA**

[![License](https://img.shields.io/github/license/stnolting/neoTRNG)](https://github.com/stnolting/neoTRNG/blob/main/LICENSE)

* [Introduction](#Introduction)
* [Top Entity](#Top-Entity)
   * [Interface](#Interface)
* [Theory of Operation](#Theory-of-Operation)
* [Evaluation](#Evaluation)
   * [Entropy per Byte](#Entropy-per-Byte)
   * [Dieharder Battery of Random Tests](#Dieharder-Battery-of-Random-Tests)
   * [Throughput](#Throughput)
   * [Hardware Utilization](#Hardware-Utilization)
* [References](#References)


## Introduction

The neoTRNG provides a small and high-quality _true_ random number generator (TRNG) that is based on free-running
and cross-coupled ring-oscillators. Due to it's high throughput and the technology-agnostic architecture the neoTRNG
can be used in a wide range of setups and applications. 

:information_source: This project is a "spin-off" project of the [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32),
where the neoTRNG is implemented as a default processor SoC module.

**Key features**

* [x] high quality random numbers
* [x] high throughput
* [x] tiny hardware footprint (less than 70 LUTs)
* [x] technology, vendor and platform independent
* [x] easy to use, simple integration


## Top Entity

The top entity is `neoTRNG`. The whole design is based on a single VHDL file
([`rtl/neoTRNG.vhd`](https://github.com/stnolting/neoTRNG/blob/main/rtl/neoTRNG.vhd)).
It can be instantiated directly without the need for any special libraries.

```vhdl
entity neoTRNG is
  generic (
    NUM_CELLS     : natural; -- total number of ring-oscillator cells
    NUM_INV_START : natural; -- number of inverters in first cell (short path), has to be odd
    NUM_INV_INC   : natural; -- number of additional inverters in next cell (short path), has to be even
    NUM_INV_DELAY : natural  -- additional inverters to form cell's long path, has to be even
  );
  port (
    clk_i    : in  std_ulogic; -- global clock line
    enable_i : in  std_ulogic; -- unit enable (high-active), reset unit when low
    data_o   : out std_ulogic_vector(7 downto 0); -- random data byte output
    valid_o  : out std_ulogic  -- data_o is valid when set
  );
end neoTRNG;
```

:warning: Note that the neoTRNG cannot be rtl-simulated due to it's combinatorial loops.

### Interface

The neoTRNG uses a single clock domain driven by `clk_i`. This clock is also used to sample the entropy sources.

The `valid_o` signal is set for one clock cycle indicating that `data_o` contains a valid random byte.
It is the task of the user logic to sample the module's data output into a register when `valid_o` is asserted as it
is driven directly by the TRNG's sampling shift register logic.

:information_source: The neoTRNG does not use a dedicated reset to keep the hardware requirements at a minimum
(this might provide area-saving on some FPGAs). Instead, the `enable_i` signal is used to control operation and
to reset all FFs. Before the TRNG is used, this signal should be kept low for at least some milliseconds to ensure
that all bits of the internal shift registers are cleared. As soon as `enable_i` is set and `valid_o` also becomes set
for the first time the TRNG is operational.


## Theory of Operation

The neoTRNG is based on a configurable number of technology-agnostic ["entropy cells"](#Entropy-Cells). The sampling of
free-running ring oscillators is used as the actual source of entropy. The number of implemented cells is defined by the
`NUM_CELLS` generic. The results from all cells are combined, evaluated and sampled by the [sampling unit](#Sampling-Unit).

### Entropy Cells

Each cell consists of two ring-oscillator ("RO"), which are implemented as self-feedback chains consisting of an
odd number of inverters. The first RO implements a **short chain** oscillating at a "high" frequency. The second RO
implements a **long chain** oscillating at a "low" frequency. A multiplexer that is controlled by a cell-external
signal select which chain is used as cell output and also as **local feedback** to drive both chain's inputs.

The chain length of the _short_ chain is defined by `NUM_INV_START + i * NUM_INV_INC`, where `NUM_INV_START` defines
the number of inverters in the very first cell (`i=0`) and `NUM_INV_INC` defines the number of additional inverters
for each  further cell `i`. 

The chain length of the _long_ chain is defined by `NUM_INV_START + i * NUM_INV_INC + NUM_INV_DELAY`. Here, `NUM_INV_DELAY`
defines the number of _additional_ inverters (compared to the short chain) to form the long chain. This parameter is constant
for all cells.

The selected local feedback is synchronized to the module's clock by two consecutive FFs to avoid metastability in the final
output. This final output is further processed by the [sampling unit](#Sampling-Unit).

To avoid "locking" of any oscillator to a specific frequency, which would reduce entropy, the active chain length is modified
during runtime by either selecting the _short_ chain or the _long_ chain. This is accomplished by **cross-coupling** all
entropy cells. The synchronized random bit of cell `i` is used to control the chain length of the next cell `i+1`. At the end
of the cell array this connection wraps around, so the last cell (`i=NUM_CELLS-1`) controls the chain length of the first cell (`i=0`).

### Implementation

Asynchronous elements like ring-oscillators are hard to implement on FPGAs as they normally require the use of device-specific
primitives or attributes. In order to provide a technology-agnostic architecture, which can be synthesized for any FPGA and that
also ensures correct functionality on any platform, a special technique is required.

The neoTRNG implements the inverters of each RO as **inverting latches**. Each latch provides a chain input (driven by the
previous latch), a chain output (driving the next latch), a global reset to bring the latch into a defined state and an enable
signal to switch the latch to _transparent mode_. 

The reset signal is applied when the TRNG is disabled (setting `enable_i` low). The "latch enable" is controlled by
a long **enable shift register** that features a distinct FF for every single latch in the design. When the module is enabled,
this shift register starts to fill with `1`s. Thus, each latch enabled is individually enabled making it impossible for the
synthesis tool to trim the logic ("optimize away").

The following figure shows the (Intel Quartus) RTL View of the very first entropy cell. The five blocks at the top (`inv_chain_s`)
form the _long_ inverter chain, the three blocks (`inv_chain_s`) on the bottom form the _short_ oscillator chain. Both chains are
connected to a multiplexer to select either of the chain. The selected output is synchronized by two FFs (providing the actual
output of the cell) and is also feed-back to the start of both chains.

![cell_rtl_view](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neoTRNG_cell_inst0_rtl.png)

The enable shift register in this cell is build from a 3-bit shift register to enable the short chain (`enable_sreg_s[2:0]`) and
a consecutive 5-bit shift register to enable the long chain (`enable_sreg_l[4:0]`). The resulting 8-bit shift register is driven by
the cell's enable input (to the shift register's LSB) and drives the cell's enable output (driven by the shift register's MSB).
This allows to daisy-chain the enable shift registers of all cells.

The following image shows a cut-out from the Intel Quartus Technology Viewer. The top of the image shows the three inverting latches
that form the short chain (`inv_chain_s`). All elements are successfully mapped to single LUT4s. The gate element of the highlighted
LUt is shown on the left. As previously described, each LUT4 implements an inverting latch with reset (`DATAD`) and enable input
(`DATAC`). The LUT's `DATAA` is used to construct the actual RO chain. The LUT's `DATAB` provides the latch feedback.

![cell_map_view](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neoTRNG_cell_inst0_map.png)

### Sampling Unit

As soon as the last bit of the _enable shift register_ is set to one the sampling unit is enabled. This unit implements
a "John von Neumann Randomness Extractor" to de-bias the obtained random data. It provides an additional 2-bit shift register
that samples the **final random bit**, which is computed by XORing the synchronous random data outputs of all cells. In every
second cycle the extractor evaluates the two sampled bits.

If an _edge_ is detected (`01` or `10`) the data bit from the extractor is sampled by the final sampling
shift register and a bit counter is incremented. This data bit is set high on a rising edge (`01`) and set low on a falling edge
(`10`). In any other case (`11` and `00`) the data sampling shift register and the bit counter stay unaffected.

Whenever the 8 bits are sampled by the sampling unit the module's `valid_o` signal is set for one clock
cycle indicating a valid data byte in `data_o`.

The RTL diagram (Intel Quartus RTL Viewer) of the whole neoTRNG unit is shown below. The three green blocks are the entropy cells.

![top_rtl_view](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neoTRNG_rtl.png)

:warning: Keeping the neoTRNG _permanently enabled_ will increase dynamic power consumption and might also
cause local heating of the FPGA chip. Of course this highly depends on the actual configuration of the TRNG.


## Evaluation

The neoTRNG is evaluated as part of the [NEORV32](https://github.com/stnolting/neorv32) processor. The setup was synthesized
for an Intel Cyclone IV `EP4CE22F17C6N` FPGA running at 100MHz.
For the evaluation a very small configuration has been selected that just implements three entropy cells.
The first ring-oscillator (short path) uses 3 inverters, the second one uses 5 inverters and the last one uses 7 inverters.
The long paths of the ring-oscillators are 2 inverters longer than the according short paths.

```
NUM_CELLS     = 3
NUM_INV_START = 3
NUM_INV_INC   = 2
NUM_INV_DELAY = 2
```

:warning: This analysis evaluates the **raw TRNG data** obtained directly from the neoTRNG module.
No additional post-processing has been applied to the data at all.

The NEORV32 test program used to sample and send random data via UART (at 115200 baud) to a host computer can be found in the
[`sw`](https://github.com/stnolting/neoTRNG/blob/main/sw) folder. On the host computer side the data has been sampled using `dd`:

```bash
$ stty -F /dev/ttyS6 115200 cs8 -cstopb -parenb
$ dd if=/dev/ttyS6 of=entropy.bin bs=1024 count=64k iflag=fullblock
```

:floppy_disk: A total amount of **64MB** of random data has been sampled for this evaluation. The sampled data is available as
"entropy.bin" binary file in the [release](https://github.com/stnolting/neoTRNG/releases) assets.

### Entropy per Byte

```bash
$ ent entropy.bin
Entropy = 7.916196 bits per byte.

Optimum compression would reduce the size
of this 67108864 byte file by 1 percent.

Chi square distribution for 67108864 samples is 6784171.98, and randomly
would exceed this value less than 0.01 percent of the times.

Arithmetic mean value of data bytes is 130.2560 (127.5 = random).
Monte Carlo value for Pi is 3.050971809 (error 2.88 percent).
Serial correlation coefficient is 0.000763 (totally uncorrelated = 0.0).
```

The average entropy per bit is not perfect but quite close to the optimum (8 bits per byte). This is caused by a small
bias in the raw data that is also indicated by an arithmetic mean value slightly above 255/2.

### Dieharder Battery of Random Tests

```bash
$ dieharder -a < entropy.bin
#=============================================================================#
#            dieharder version 3.31.1 Copyright 2003 Robert G. Brown          #
#=============================================================================#
   rng_name    |rands/second|   Seed   |
        mt19937|  9.34e+07  |2346379052|
#=============================================================================#
        test_name   |ntup| tsamples |psamples|  p-value |Assessment
#=============================================================================#
   diehard_birthdays|   0|       100|     100|0.57731277|  PASSED
      diehard_operm5|   0|   1000000|     100|0.47360622|  PASSED
  diehard_rank_32x32|   0|     40000|     100|0.01305723|  PASSED
    diehard_rank_6x8|   0|    100000|     100|0.95525488|  PASSED
   diehard_bitstream|   0|   2097152|     100|0.73447283|  PASSED
        diehard_opso|   0|   2097152|     100|0.32236885|  PASSED
        diehard_oqso|   0|   2097152|     100|0.94256249|  PASSED
         diehard_dna|   0|   2097152|     100|0.60578360|  PASSED
diehard_count_1s_str|   0|    256000|     100|0.48384753|  PASSED
diehard_count_1s_byt|   0|    256000|     100|0.61394549|  PASSED
 diehard_parking_lot|   0|     12000|     100|0.77403241|  PASSED
    diehard_2dsphere|   2|      8000|     100|0.37287435|  PASSED
    diehard_3dsphere|   3|      4000|     100|0.39671714|  PASSED
     diehard_squeeze|   0|    100000|     100|0.37454481|  PASSED
        diehard_sums|   0|       100|     100|0.67869468|  PASSED
        diehard_runs|   0|    100000|     100|0.98994117|  PASSED
        diehard_runs|   0|    100000|     100|0.64399488|  PASSED
       diehard_craps|   0|    200000|     100|0.73100162|  PASSED
       diehard_craps|   0|    200000|     100|0.87778786|  PASSED
 marsaglia_tsang_gcd|   0|  10000000|     100|0.86913829|  PASSED
 marsaglia_tsang_gcd|   0|  10000000|     100|0.13155970|  PASSED
         sts_monobit|   1|    100000|     100|0.64167609|  PASSED
            sts_runs|   2|    100000|     100|0.98350454|  PASSED
          sts_serial|   1|    100000|     100|0.66552170|  PASSED
          sts_serial|   2|    100000|     100|0.93651771|  PASSED
          sts_serial|   3|    100000|     100|0.76078835|  PASSED
          sts_serial|   3|    100000|     100|0.93540927|  PASSED
          sts_serial|   4|    100000|     100|0.58565484|  PASSED
          sts_serial|   4|    100000|     100|0.23613355|  PASSED
          sts_serial|   5|    100000|     100|0.94133522|  PASSED
          sts_serial|   5|    100000|     100|0.96601777|  PASSED
          sts_serial|   6|    100000|     100|0.36124982|  PASSED
          sts_serial|   6|    100000|     100|0.28559944|  PASSED
          sts_serial|   7|    100000|     100|0.60564556|  PASSED
          sts_serial|   7|    100000|     100|0.20377259|  PASSED
          sts_serial|   8|    100000|     100|0.03958092|  PASSED
          sts_serial|   8|    100000|     100|0.22289932|  PASSED
          sts_serial|   9|    100000|     100|0.00797890|  PASSED
          sts_serial|   9|    100000|     100|0.64151024|  PASSED
          sts_serial|  10|    100000|     100|0.30359554|  PASSED
          sts_serial|  10|    100000|     100|0.38407429|  PASSED
          sts_serial|  11|    100000|     100|0.96115089|  PASSED
          sts_serial|  11|    100000|     100|0.33811291|  PASSED
          sts_serial|  12|    100000|     100|0.81662631|  PASSED
          sts_serial|  12|    100000|     100|0.99710383|   WEAK
          sts_serial|  13|    100000|     100|0.41685341|  PASSED
          sts_serial|  13|    100000|     100|0.30513343|  PASSED
          sts_serial|  14|    100000|     100|0.05525830|  PASSED
          sts_serial|  14|    100000|     100|0.43890313|  PASSED
          sts_serial|  15|    100000|     100|0.23642431|  PASSED
          sts_serial|  15|    100000|     100|0.60388362|  PASSED
          sts_serial|  16|    100000|     100|0.86599811|  PASSED
          sts_serial|  16|    100000|     100|0.69206311|  PASSED
         rgb_bitdist|   1|    100000|     100|0.66608133|  PASSED
         rgb_bitdist|   2|    100000|     100|0.80104566|  PASSED
         rgb_bitdist|   3|    100000|     100|0.05677007|  PASSED
         rgb_bitdist|   4|    100000|     100|0.67146059|  PASSED
         rgb_bitdist|   5|    100000|     100|0.85920028|  PASSED
         rgb_bitdist|   6|    100000|     100|0.12757860|  PASSED
         rgb_bitdist|   7|    100000|     100|0.75950587|  PASSED
         rgb_bitdist|   8|    100000|     100|0.56384920|  PASSED
         rgb_bitdist|   9|    100000|     100|0.93538502|  PASSED
         rgb_bitdist|  10|    100000|     100|0.35318322|  PASSED
         rgb_bitdist|  11|    100000|     100|0.66058683|  PASSED
         rgb_bitdist|  12|    100000|     100|0.69654766|  PASSED
rgb_minimum_distance|   2|     10000|    1000|0.55586515|  PASSED
rgb_minimum_distance|   3|     10000|    1000|0.47680031|  PASSED
rgb_minimum_distance|   4|     10000|    1000|0.24230629|  PASSED
rgb_minimum_distance|   5|     10000|    1000|0.64805418|  PASSED
    rgb_permutations|   2|    100000|     100|0.50669481|  PASSED
    rgb_permutations|   3|    100000|     100|0.14580009|  PASSED
    rgb_permutations|   4|    100000|     100|0.28733396|  PASSED
    rgb_permutations|   5|    100000|     100|0.64700151|  PASSED
      rgb_lagged_sum|   0|   1000000|     100|0.80820241|  PASSED
      rgb_lagged_sum|   1|   1000000|     100|0.45214169|  PASSED
      rgb_lagged_sum|   2|   1000000|     100|0.60658055|  PASSED
      rgb_lagged_sum|   3|   1000000|     100|0.88830082|  PASSED
      rgb_lagged_sum|   4|   1000000|     100|0.70651079|  PASSED
      rgb_lagged_sum|   5|   1000000|     100|0.02757951|  PASSED
      rgb_lagged_sum|   6|   1000000|     100|0.74575163|  PASSED
      rgb_lagged_sum|   7|   1000000|     100|0.95410896|  PASSED
      rgb_lagged_sum|   8|   1000000|     100|0.23388481|  PASSED
      rgb_lagged_sum|   9|   1000000|     100|0.65009833|  PASSED
      rgb_lagged_sum|  10|   1000000|     100|0.39603048|  PASSED
      rgb_lagged_sum|  11|   1000000|     100|0.17852403|  PASSED
      rgb_lagged_sum|  12|   1000000|     100|0.13748031|  PASSED
      rgb_lagged_sum|  13|   1000000|     100|0.29546853|  PASSED
      rgb_lagged_sum|  14|   1000000|     100|0.03381359|  PASSED
      rgb_lagged_sum|  15|   1000000|     100|0.12383323|  PASSED
      rgb_lagged_sum|  16|   1000000|     100|0.27288266|  PASSED
      rgb_lagged_sum|  17|   1000000|     100|0.39596163|  PASSED
      rgb_lagged_sum|  18|   1000000|     100|0.47719282|  PASSED
      rgb_lagged_sum|  19|   1000000|     100|0.92922609|  PASSED
      rgb_lagged_sum|  20|   1000000|     100|0.40272087|  PASSED
      rgb_lagged_sum|  21|   1000000|     100|0.62467797|  PASSED
      rgb_lagged_sum|  22|   1000000|     100|0.32435511|  PASSED
      rgb_lagged_sum|  23|   1000000|     100|0.86656648|  PASSED
      rgb_lagged_sum|  24|   1000000|     100|0.89664457|  PASSED
      rgb_lagged_sum|  25|   1000000|     100|0.33775618|  PASSED
      rgb_lagged_sum|  26|   1000000|     100|0.72428295|  PASSED
      rgb_lagged_sum|  27|   1000000|     100|0.28799125|  PASSED
      rgb_lagged_sum|  28|   1000000|     100|0.47632984|  PASSED
      rgb_lagged_sum|  29|   1000000|     100|0.32182951|  PASSED
      rgb_lagged_sum|  30|   1000000|     100|0.23272664|  PASSED
      rgb_lagged_sum|  31|   1000000|     100|0.52695380|  PASSED
      rgb_lagged_sum|  32|   1000000|     100|0.66699695|  PASSED
     rgb_kstest_test|   0|     10000|    1000|0.57618123|  PASSED
     dab_bytedistrib|   0|  51200000|       1|0.61728909|  PASSED
             dab_dct| 256|     50000|       1|0.87808747|  PASSED
Preparing to run test 207.  ntuple = 0
        dab_filltree|  32|  15000000|       1|0.30607587|  PASSED
        dab_filltree|  32|  15000000|       1|0.73804471|  PASSED
Preparing to run test 208.  ntuple = 0
       dab_filltree2|   0|   5000000|       1|0.46632823|  PASSED
       dab_filltree2|   1|   5000000|       1|0.80942784|  PASSED
Preparing to run test 209.  ntuple = 0
        dab_monobit2|  12|  65000000|       1|0.29772220|  PASSED
```

All tests are passed and only one test shows a "weak" assessment. Now that's a very nice result!


### Throughput

The sampling logic of the neoTRNG samples random data in chunks of 8-bit. Since the randomness extractor uses
2 non-overlapping bits a total number of 16 clock cycles is required to sample one final byte of random data.
So the optimal and maximal output rate of the TRNG module is:

```
100_000_000[cycles/s] / 16[cycles/8bit] = 50_000_000[bit/s] = 50[Mbit/s] = 47.68[Mibit/s]
```

The randomness extractor only passes _valid_ bits to the sampling shift register. The amount of valid
bits per cycle is not static as this is defined by the entropy of the entropy source. For a "real-world" application
that was compile for a `rv32imc` CPU and optimized for size (`Os`) the average number of cycles required for
obtaining a random byte is 41 cycles (including C-overhead). This results in an average throughput of **19.5Mbit/s**:

```
100_000_000[cycles/s] / 41[cycles/8bit] = 19_512_195[bit/s] = 19.5[Mbit/s] = 18.6[Mibit/s]
```

### Hardware Utilization

Mapping results for the neoTRNG top entity and it's entropy cells wrapped in the NEORV32 TRNG module.

##### Lattice ice40 UltraPlus iCE40UP5K-SG48I @24MHz

```
Hierarchy                                                 Logic Cells   Logic Registers
---------------------------------------------------------------------------------------
neoTRNG_inst                                                  46  (7)           58 (16)
  neoTRNG_cell_inst[0].neoTRNG_cell_inst_i                     9  (9)           10 (10)
  neoTRNG_cell_inst[1].neoTRNG_cell_inst_i                    13 (13)           14 (14)
  neoTRNG_cell_inst[2].neoTRNG_cell_inst_i                    17 (17)           18 (18)
```

##### Intel Cyclone IV EP4CE22F17C6N @100MHz

```
Hierarchy                                                 Logic Cells   Logic Registers
---------------------------------------------------------------------------------------
neoTRNG:neoTRNG_inst                                          65 (19)           58 (16)
  neoTRNG_cell:\neoTRNG_cell_inst:0:neoTRNG_cell_inst_i       12 (12)           10 (10)
  neoTRNG_cell:\neoTRNG_cell_inst:1:neoTRNG_cell_inst_i       15 (15)           14 (14)
  neoTRNG_cell:\neoTRNG_cell_inst:2:neoTRNG_cell_inst_i       22 (22)           18 (18)
```

##### Xilinx Artix-7 XC7A35TICSG324-1L @100MHz

```
Hierarchy                                                 Logic Cells   Logic Registers
---------------------------------------------------------------------------------------
neoTRNG_inst (neoTRNG)                                             42                94
  neoTRNG_cell_inst[0].neoTRNG_cell_inst_i (neoTRNG_cell)           9                18
  neoTRNG_cell_inst[1].neoTRNG_cell_inst_i (neoTRNG_cell)          12                26
  neoTRNG_cell_inst[2].neoTRNG_cell_inst_i (neoTRNG_cell)          16                34
```


## References

* :construction: TODO
