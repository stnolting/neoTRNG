# :game_die: neoTRNG - V2

**A Tiny and Platform-Independent True Random Number Generator for _any_ FPGA.**

[![License](https://img.shields.io/github/license/stnolting/neoTRNG)](https://github.com/stnolting/neoTRNG/blob/main/LICENSE)
[![DOI](https://zenodo.org/badge/430418414.svg)](https://zenodo.org/badge/latestdoi/430418414)

* [Introduction](#Introduction)
* [Top Entity](#Top-Entity)
* [Theory of Operation](#Theory-of-Operation)
* [Evaluation](#Evaluation)
* [References](#References)
* [Simulation](#Simulating-the-neoTRNG)


## Introduction

The neoTRNG provides a small and high-quality _true random number generator_ (TRNG) that is based on free-running
and cross-coupled ring-oscillators. The architecture provides a technology-agnostic implementation that allows to
synthesize the TRNG for _any_ FPGA platform.

:information_source: This project is a "spin-off" project of the
[NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32),
where the neoTRNG is implemented as a default processor SoC module.

**:loudspeaker: Feedback from the community is highly appreciated!**

**Key features**

* [x] high quality random numbers
* [x] high throughput
* [x] tiny hardware footprint (less than 100 LUTs!)
* [x] technology, vendor and platform agnostic
* [x] easy to use, simple integration

[[back to top](#game_die-neoTRNG---V2)]


## Top Entity

The whole design is based on a single VHDL file
([`rtl/neoTRNG.vhd`](https://github.com/stnolting/neoTRNG/blob/main/rtl/neoTRNG.vhd)).
The top entity is `neoTRNG`, which can be instantiated directly without the need for any special libraries
or packages.

```vhdl
entity neoTRNG is
  generic (
    NUM_CELLS     : natural; -- total number of ring-oscillator cells
    NUM_INV_START : natural; -- number of inverters in first cell (short path), has to be odd
    NUM_INV_INC   : natural; -- number of additional inverters in next cell (short path), has to be even
    NUM_INV_DELAY : natural; -- additional inverters to form cell's long path, has to be even
    POST_PROC_EN  : boolean; -- implement post-processing for advanced whitening when true
    IS_SIM        : boolean  -- for simulation only!
  );
  port (
    clk_i    : in  std_ulogic; -- global clock line
    enable_i : in  std_ulogic; -- unit enable (high-active), reset unit when low
    data_o   : out std_ulogic_vector(7 downto 0); -- random data byte output
    valid_o  : out std_ulogic  -- data_o is valid when set
  );
end neoTRNG;
```

### Interface

The neoTRNG uses a single clock domain driven by `clk_i`. This clock is also used to sample the entropy sources.
The `valid_o` signal indicates that `data_o` contains a valid random byte. It is the task of the user logic to
_sample_ the module's data output into a register or buffer as `valid_o` is high for only one cycle.

:information_source: The neoTRNG does not use a dedicated reset to keep the hardware requirements at a minimum
(might provide area-savings on some FPGAs). Instead, the `enable_i` signal is used to control operation and
to reset all (relevant) FFs. Before the TRNG is used, this signal should be kept low for at least some 1000
clock cycles to ensure that all bits of the internal shift registers are cleared. As soon as `enable_i` is set
and `valid_o` also becomes set for the first time the TRNG is operational.

:warning: Keeping the neoTRNG _permanently enabled_ will increase dynamic power consumption and might also
cause local heating of the FPGA chip. Of course this highly depends on the actual configuration of the TRNG.

[[back to top](#game_die-neoTRNG---V2)]


## Theory of Operation

The neoTRNG is based on a configurable number of technology-agnostic ["entropy cells"](#Entropy-Cells). The
sampling of free-running ring oscillators is used as the actual source of entropy. The number of implemented
cells is defined by the `NUM_CELLS` generic. The final random data is de-serialized by the
["Sampling Unit"](#Sampling-Unit) and optionally [post-processed](#Post-Processing) to improve whitening.

### Entropy Cells

Each entropy cell consists of two ring-oscillator ("RO"), which are implemented as self-feedback chains consisting
of an odd number of inverters. The first RO implements a **short chain** oscillating at a "high" frequency. The
second RO features `NUM_INV_INC` additional inverters implementing a **long chain** oscillating running at a "low"
frequency. A multiplexer that is controlled by a cell-external signal selects which chain is used as cell output.
The selected output is also used as _local feedback_ to drive both chain's inputs.

The length (= number of inverters) of the **shor**_ chain is defined by `NUM_INV_START + i * NUM_INV_INC`, where
`NUM_INV_START` defines the number of inverters in the very first cell (`i=0`) in cell `i`. `NUM_INV_INC` defines
the number of additional inverters for each further cell. 

The length of the **long** chain is defined by `NUM_INV_START + i * NUM_INV_INC + NUM_INV_DELAY`. Here, `NUM_INV_DELAY`
defines the number of _additional_ inverters (compared to the short chain) to form the long chain. This parameter
is constant for all cells.

To **avoid "locking"** of any RO to a specific frequency, which would reduce entropy, the active chain length is
randomly modified during runtime by either selecting the _short_ chain or the _long_ chain. This is accomplished by
**cross-coupling** all entropy cells. The output of the very last entropy cell is used as "final random" data output.
This single-bit signal is synchronized to the unit's clock domain using two consecutive FFs to remove metastability.
The state of the first synchronizer FF (which has a high probability of being in a metastable state) is also used to
switch the **connection mode** of the entropy cells:

* if FF is zero, the output of cell `i` is used to select the path length of cell `i+1` (wrapping around); this is the "forward mode"
* if FF is one, the output of cell `i+1` is used to select the path length of cell `i` (wrapping around); this is the "reverse mode"

[[back to top](#game_die-neoTRNG---V2)]


### Entropy Cells - Implementation

Asynchronous elements like ring-oscillators are hard to implement on FPGAs as they normally require the use of
device-specific or vendor-specific primitives or attributes. In order to provide a technology-agnostic architecture,
which can be synthesized for any FPGA and that also ensures correct functionality on any platform, a special technique
is required.

The neoTRNG implements the inverters of each RO as **inverting latches**. Each latch provides a chain input (driven by the
previous latch), a chain output (driving the next latch), a global reset to bring the latch into a defined state and an enable
signal to switch the latch to _transparent_ mode_. 

The reset signal is globally applied to all latches when the neoTRNG is disabled by setting `enable_i` low. The individual
"latch enables" are controlled by a long **enable shift register** that features a distinct FF for every single latch in the
design. When the module is enabled, this shift register starts to fill with ones. Thus, each latch is individually and
consecutively enabled making it impossible for the synthesis tool to trim the logic ("optimize away").

The following figure shows the Intel Quartus Prime **RTL View** of the very first entropy cell. In this setup the short path consists
of 3 inverting latches (`inv_chain_s`, bottom) and the long path consists of 5 inverting latches (`inv_chain_l`, top). Both chains are
connected to a multiplexer to select either of them as cell output and as input for both chains.

![cell_rtl_view](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neoTRNG_cell_inst0_rtl.png)

The enable shift register in this cell is build by chaining two smaller shift register: a 3-bit one for the short chain and a
consecutive 5-bit shift register to enable the long chain. The LSB of the resulting 8-bit shift register is driven by the cell's
enable input and the resulting MSB of the shift register drives the cell's enable output. This allows to daisy-chain the enable
shift registers of _all_ cells.

The following image shows a cut-out from the Intel Quartus Prime **Technology Viewer** showing the same entropy cell as in the RTL
diagram above. The right top of the image shows the three inverting latches that form the short RO chain (`inv_chain_s`).
All three latches were successfully mapped to single LUTs. The gate equivalent of the highlighted LUT is shown on the left.
As previously described, each LUT implements an inverting latch using four inputs:

* `DATAD`: latch reset driven by global enable signal
* `DATAC`: latch enable signal (to make the latch transparent) driven by the enable shift register
* `DATAB`: latch-internal state feedback
* `DATAA`: output of the previous latch to form the actual _ring_ oscillator

![cell_map_view](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neoTRNG_cell_inst0_map.png)

[[back to top](#game_die-neoTRNG---V2)]


### Sampling Unit

As soon as the last bit of the daisy-chained enable shift register is set the sampling unit gets enabled. This unit implements
a simple "John von Neumann Randomness Extractor" to de-bias the obtained random data. The extractor implements a 2-bit shift register
that samples the **final random bit**, which is the output of the very last entropy cell in the chain. In every
second cycle the extractor evaluates the two sampled bits to check non-overlapping pairs of bits for _edges_.

If a rising edge is detected (`01`) a `0` is sampled by the final data byte shift register. If a falling edge is detected
(`10`) a `1` is sampled by the final data byte shift register. In both cases a 3-bit wide bit counter is also increment.
If no edge is detected, the data sampling shift register and the bit counter stay unaffected. A final random data sample is
available when 8 edges have been sampled.

[[back to top](#game_die-neoTRNG---V2)]


### Post-Processing

The neoTRNG provides an _optional_ post-processing logic that aims to improve the quality of the random data (whitening).
When enabled (`POST_PROC_EN` = true) the post-processing logic takes 8 _raw_ random data bytes from the sampling unit and
_combines_ them. For this, the raw samples are right-rotated by one position and summed-up to "combine/mixs" each bit of the raw
64-bit with any other bit. Evaluations show that this post-processing can increase the entropy of the final random data
but at the cost of additional hardware resources and increased latency.

[[back to top](#game_die-neoTRNG---V2)]


## Evaluation

The neoTRNG is evaluated as part of the [NEORV32](https://github.com/stnolting/neorv32) processor, where the neoTRNG is
available as standard SoC module. The processor was synthesized for an Intel Cyclone IV `EP4CE22F17C6N` FPGA running at 100MHz.

For the evaluation a very small configuration has been selected that just implements three entropy cells. The first
RO (short paths) uses 5 inverters, the second one uses 7 inverters and the last one uses 9 inverters. The long
paths of the ROs are 2 inverters longer than the according short paths. The evaluation setup also uses the
internal post-processing module.

```
NUM_CELLS     = 3
NUM_INV_START = 3
NUM_INV_INC   = 2
NUM_INV_DELAY = 2
POST_PROC_EN  = true
IS_SIM        = false
```

The NEORV32 test program used to sample and send random data to a host computer can be found in the
[`sw`](https://github.com/stnolting/neoTRNG/blob/main/sw) folder. The program uses NEORV32.UART0 as status console
and NEORV32.UART1 (using CTS flow-control) to send random data at 2000000 baud. On the host computer side the data
has been sampled using `dd`:

```bash
$ sudo stty -F /dev/ttyS4 raw 2000000 cs8 crtscts
$ dd if=/dev/ttyS4 of=entropy.bin bs=1M count=64 iflag=fullblock
```

:floppy_disk: A total amount of **64MB** of random data has been sampled for this evaluation. The sampled data is available as
"entropy.bin" binary file in the [release](https://github.com/stnolting/neoTRNG/releases) assets.

[[back to top](#game_die-neoTRNG---V2)]


#### Entropy per Byte

```
$ ent entropy.bin
Entropy = 7.994350 bits per byte.

Optimum compression would reduce the size
of this 67108864 byte file by 0 percent.

Chi square distribution for 67108864 samples is 263466.53, and randomly
would exceed this value less than 0.01 percent of the times.

Arithmetic mean value of data bytes is 127.8948 (127.5 = random).
Monte Carlo value for Pi is 3.136194535 (error 0.17 percent).
Serial correlation coefficient is -0.000113 (totally uncorrelated = 0.0).
```

#### FIPS 140-2 RNG Tests

```
$ rngtest < entropy.bin
rngtest 5
Copyright (c) 2004 by Henrique de Moraes Holschuh
This is free software; see the source for copying conditions.  There is NO warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

rngtest: starting FIPS tests...
rngtest: entropy source drained
rngtest: bits received from input: 536870912
rngtest: FIPS 140-2 successes: 26820
rngtest: FIPS 140-2 failures: 23
rngtest: FIPS 140-2(2001-10-10) Monobit: 5
rngtest: FIPS 140-2(2001-10-10) Poker: 3
rngtest: FIPS 140-2(2001-10-10) Runs: 11
rngtest: FIPS 140-2(2001-10-10) Long run: 4
rngtest: FIPS 140-2(2001-10-10) Continuous run: 0
rngtest: input channel speed: (min=66.925; avg=1154.609; max=2384.186)Mibits/s
rngtest: FIPS tests speed: (min=13.702; avg=100.584; max=112.197)Mibits/s
rngtest: Program run time: 5650707 microseconds
```


#### Dieharder Battery of Random Tests

:construction: Work in progress.


### Throughput

The sampling logic of the neoTRNG samples random data in chunks of 8-bit. Since the randomness extractor uses
2 non-overlapping bits, a total number of 16 clock cycles is required to sample one final **raw byte** of random data.
If the internal post-processing logic is enabled, it will sample 8 raw bytes to generate one final
**processed byte** of random data. In this case the neoTRNG requires 128 clock cycles to generate one output byte.

:information_source: The randomness extractor only passes _valid_ bits to the sampling shift register.
The amount of valid bits per cycle is not static as this is defined entirely by the entropy source.

[[back to top](#game_die-neoTRNG---V2)]


### Hardware Utilization

Mapping results for the neoTRNG top entity and it's entropy cells wrapped in the NEORV32 TRNG module.

##### Intel Cyclone IV `EP4CE22F17C6N` @100MHz

```
Hierarchy                                                 Logic Cells   Logic Registers
---------------------------------------------------------------------------------------
neoTRNG:neoTRNG_inst                                          86 (41)           70 (34)
  neoTRNG_cell:\neoTRNG_cell_inst:0:neoTRNG_cell_inst_i       17 (17)            8  (8)
  neoTRNG_cell:\neoTRNG_cell_inst:1:neoTRNG_cell_inst_i       17 (17)           12 (12)
  neoTRNG_cell:\neoTRNG_cell_inst:2:neoTRNG_cell_inst_i       19 (19)           16 (16)
```

[[back to top](#game_die-neoTRNG---V2)]


## Simulating the neoTRNG

Since the asynchronous ring-oscillators cannot be rtl-simulated (at least not with common simulators), the
neoTRNG module provides a dedicated simulation option that is enabled by the `IS_SIM` generic. When enabled,
the entropy sources (= ring-oscillators) are replaced by a **pseudo random number generator** (LFSRs).

:warning: The simulation mode is intended for simulation/debugging only! Synthesized setups with enabled
simulation mode will **not** generate _true_ random numbers!!

The [`sim`](https://github.com/stnolting/neoTRNG/sim) folder of this repository provides a simple testbench for
the neoTRNG using the default configuration. The testbench will output the obtained random bytes as decimal values
via the simulator console. The testbench can be simulated by GHDL using the provided script:

```
neoTRNG/sim$ sh ghdl.sh
../rtl/neoTRNG.vhd:134:3:@0ms:(assertion note): << neoTRNG V2 - A Tiny and Platform-Independent True Random Number Generator for any FPGA >>
../rtl/neoTRNG.vhd:135:3:@0ms:(assertion note): neoTRNG note: Post-processing enabled.
../rtl/neoTRNG.vhd:440:5:@0ms:(assertion warning): neoTRNG WARNING: Implementing simulation-only PRNG (LFSR)!
../rtl/neoTRNG.vhd:440:5:@0ms:(assertion warning): neoTRNG WARNING: Implementing simulation-only PRNG (LFSR)!
../rtl/neoTRNG.vhd:440:5:@0ms:(assertion warning): neoTRNG WARNING: Implementing simulation-only PRNG (LFSR)!
195
67
201
30
41
152
8
82
116
157
43
86
159
118
205
76
165
29
99
250
74
248
218
12
212
132
188
123
50
195
161
238
114
144
35
195
253
33
171
/usr/bin/ghdl-mcode:info: simulation stopped by --stop-time @200us
```

The GHDL waveform data is stored to `sim/neoTRNG_tb.ghw` and can be viewed using _gtkwave_:

```
neoTRNG/sim$ gtkwave neoTRNG_tb.ghw
```

[[back to top](#game_die-neoTRNG---V2)]


## References

* Kumar, Sandeep S., et al. "The butterfly PUF protecting IP on every FPGA." 2008 IEEE International Workshop
on Hardware-Oriented Security and Trust. IEEE, 2008.
* Tuncer, Taner, et al. "Implementation of non-periodic sampling true random number generator on FPGA."
Informacije Midem 44.4 (2014): 296-302.
* Brown, Robert G., Dirk Eddelbuettel, and David Bauer. "Dieharder." Duke University Physics Department Durham,
NC (2018): 27708-0305.

[[back to top](#game_die-neoTRNG---V2)]
