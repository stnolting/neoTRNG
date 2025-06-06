# The neoTRNG True Random Number Generator

**A Tiny and Platform-Independent True Random Number Generator for _any_ FPGA (and even ASICs).**

[![neoTRNG simulation](https://github.com/stnolting/neoTRNG/actions/workflows/main.yml/badge.svg)](https://github.com/stnolting/neoTRNG/actions/workflows/main.yml)
[![Release](https://img.shields.io/github/v/release/stnolting/neoTRNG)](https://github.com/stnolting/neoTRNG/releases)
[![License](https://img.shields.io/github/license/stnolting/neoTRNG)](https://github.com/stnolting/neoTRNG/blob/main/LICENSE)
[![DOI](https://zenodo.org/badge/430418414.svg)](https://zenodo.org/badge/latestdoi/430418414)

* [Introduction](#introduction)
* [Top Entity, Integration and Interface](#top-entity)
* [Theory of Operation / Architecture](#architecture)
* [Evaluation](#evaluation)
* [Hardware Utilization](#hardware-utilization)
* [Simulation](#simulation)
* [Acknowledgments](#acknowledgments)
* [References](#references)


## Introduction

The neoTRNG aims to be a small and **platform-agnostic** TRUE random number generator (TRNG) that
can be synthesized for _any_ target technology (FPGAs and even ASICs). It is based on simple free-running
ring-oscillators, which are enhanced by a _special technique_ in order to allow synthesis for any platform.
The _phase noise_ that occurs when sampling free-running ring-oscillators is used as physical entropy source.

This project is a "spin-off" from the [NEORV32 RISC-V Processor](https://github.com/stnolting/neorv32) where
the neoTRNG is implemented as default SoC module.

**Key Features**

* [x] technology, vendor and platform/technology independent - can be synthesized for **any** platform
* [x] tiny hardware footprint (less than 100 LUT4s/FFs for the standard configuration)
* [x] high throughput (for a physical TRNG)
* [x] fully open source with a [permissive license](https://github.com/stnolting/neoTRNG/blob/main/LICENSE)
* [x] full-digital design; single-file VHDL module without any dependencies
* [x] very high operating frequency to ease timing closure
* [x] easy to use / simple integration
* [x] full documentation down to rtl level + evaluation

> [!CAUTION]
> It is possible that there might be at least _some_ cross correlations between internal/external
signals/events and the generated random numbers. Hence, there is **no guarantee at all** the neoTRNG provides
_perfect or even cryptographically secure_ random numbers! See the provided evaluation results or (even better)
test it by yourself. Furthermore, there is no tampering detection mechanism or online health monitoring available
yet to check for integrity/quality of the generated random data.

> [!WARNING]
> Keeping the neoTRNG _permanently enabled_ will increase dynamic power consumption and might also cause
local heating of the chip (when using very large configurations). Furthermore, additional electromagnetic
interference (EMI) might be emitted by the design.


## Top Entity

The whole design is implemented as a single VHDL file
[`rtl/neoTRNG.vhd`](https://github.com/stnolting/neoTRNG/blob/main/rtl/neoTRNG.vhd) that
has no dependencies at all (like special libraries, packages or submodules).

```vhdl
entity neoTRNG is
  generic (
    NUM_CELLS     : natural range 1 to 99   := 3; -- number of ring-oscillator cells
    NUM_INV_START : natural range 3 to 99   := 5; -- number of inverters in first ring-oscillator cell, has to be odd
    NUM_RAW_BITS  : natural range 1 to 4096 := 64; -- number of XOR-ed raw bits per random sample byte (has to be a power of 2)
    SIM_MODE      : boolean                 := false -- enable simulation mode (no physical random if enabled!)
  );
  port (
    clk_i    : in  std_ulogic; -- module clock
    rstn_i   : in  std_ulogic; -- module reset, low-active, async, optional
    enable_i : in  std_ulogic; -- module enable (high-active)
    valid_o  : out std_ulogic; -- data_o is valid when set (high for one cycle)
    data_o   : out std_ulogic_vector(7 downto 0) -- random data byte output
  );
end neoTRNG;
```

### Interface and Configuration

The neoTRNG uses a single clock domain driven by the `clk_i` signal. The module's reset signal `rstn_i`
is _optional_ (tie to `'1'` if not used). Random data is obtained by using a simple data/valid interface:
whenever a new valid random byte is available the `valid_o` output will be high for exactly one cycle so
the `data_o` output can be sampled by the user logic.

The `enable_i` signal is used to initialize and start the TRNG. Before the TRNG can be used this signal
should be kept low for at least several 100 clock cycles (depending on the configuration) to ensure that
all bits of the internal shift registers are cleared again. When `enable_i` is set and `valid_o` becomes
set for the first time the TRNG is operational. Disabling the TRNG also requires `enable_i` being low for
the same amount of clock cycles. When `enable_i` gets low all ring-oscillators will be stopped reducing
dynamic switching activity and power consumption.

Three generics are provided to configure the neoTRNG. `NUM_CELLS` defines the total number of entropy
cells. `NUM_INV_START` defines the number of inverters (= the length of the ring-oscillator) in the very
first cell. These two generics are further described in the [Architecture](#architecture) section below.
`NUM_RAW_BITS` defines the number of raw entropy bits that get XOR-ed into the final random sample byte.
The last generic `SIM_MODE` can be set to allow [simulating](#simulation) of the TRNG within a plain RTL
simulation.


## Architecture

![neoTRNG architecture](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neotrng_architecture.png)

The neoTRNG is based on a configurable number (`NUM_CELLS`) of [entropy cells](#entropy-cells). Each cell
provides a simple a ring-oscillator ("RO") that is built using an odd number of inverters. The oscillation
frequency of the RO is defined by the propagation delay of the elements within the ring. This frequency is
not static as it is subject to minimal fluctuations caused by thermal noise electronic shot noise. The
state of the RO's last inverter is sampled into a flip flop by using a static clock (`clk_i`). As the RO's
frequency chaotically varies over time the inherent **phase noise** of the sampled data is used as actual
entropy source.

Each entropy cell generates a 1-bit stream of random data. The outputs of all cells are mixed using a wide
XOR gate before the stream is [de-biased](#de-biasing) by a simple randomness extractor. Several de-biased
bits are sampled / de-serialized by the [sampling unit](#sampling-unit) to provide byte-wide random number.
The sampling unit also applies a simple post-processing in order to improve the spectral distribution of
the random numbers.

### Entropy Cells

Each entropy cell consists of a ring-oscillator that is build from an odd number of **inverting latches**.
The length of ring in the very first entropy cell is defined by the `NUM_INV_START` generic. Every
additional entropy cell adds another 2 inverters to this initial chain length. Hence, each additional
entropy cell oscillates at a lower frequency then the one before.

Asynchronous elements like ring-oscillators are hard to implement in a platform-independent way as they
usually require the use of platform-/technology-specific primitives, attributes or synthesis settings. In
order to provide a real target-agnostic architecture, which can be synthesized for any target technology,
a special technique is applied: each inverter inside the RO is followed by a **latch** that provides a
global reset and also an individual latch-enable to switch the latch to transparent mode.

The individual latch-enables are controlled by a long shift register that features a distinct FF for every
single latch in the RO chain. When the TRNG is enabled, this shift register starts to fill with ones. Thus,
the latches are individually enabled one-by-one making it impossible for the synthesis tool to trim any
logic/elements from the RO chain as the start-up states of each latch can (theoretically) be monitored by
external logic. The enable shift register of all entropy cells are daisy-chained to continue this start-up
procedure across the entire entropy array.

The following image shows the simplified schematic of the very first entropy cell consisting of 5
inverter-latch elements for the rings oscillator, 5 flip flops for the enable shift register and another 2
flip flops for the synchronizer.

![neoTRNG entropy cell](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neotrng_ring_oscillator.png)

An image showing the FPGA the mapping result (generated by Intel Quartus Prime) of the very first entropy
cell can be seen [here](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neotrng_cell_map.png).
It shows that all latch+inverter elements of the ring-oscillator chain were successfully mapped to individual
LUT4s.

### De-Biasing

As soon as the last bit of the entropy cell's daisy-chained enable shift register is set the de-biasing
unit gets started. This unit implements a simple "John von Neumann Randomness Extractor" to de-bias the
obtained random data stream. The extractor implements a 2-bit shift register that samples the XOR-ed
random bit from the entropy cell array. In every second cycle the extractor evaluates the two sampled bits
to check a non-overlapping pair of bits for _edges_.

![neoTRNG de-biasing](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neotrng_debiasing.png)

Whenever an edge has been detected a "valid" signal is send to the following sampling unit. A rising-edge
(`01`) emits a `1` data bit and a falling-edge (`10`) emits a `0` data bit. Hence, the de-biasing unit
requires at least two clock cycles to generate a single random bit. If no edge is detected (`00` or `11`)
the valid signal remains low and the sampling unit halts.

### Sampling Unit

The sampling unit implements a 8-bit shift register to convert the serial de-biased bitstream into byte-wide
random numbers. Additionally, the sample unit provides a simple post processing to improve the spectral
distribution of the obtained random samples.

![neoTRNG sampling unit](https://raw.githubusercontent.com/stnolting/neoTRNG/main/img/neotrng_sampling_unit.png)

In order to generate one byte of random data the sampling unit reset its internal shift register to all-zero
and starts consuming single bits from the de-biased random stream. By default, 64 raw entropy bits are used,
but this number can be adjusted by the `NUM_RAW_BITS` generic (using more random bits might improve random
quality at the extend of the final generation rate). The shift register implements a simple 8-bit
[CRC](https://en.wikipedia.org/wiki/Cyclic_redundancy_check) for entropy compression. The following
polynomial is used: `x^8 + x^2 + x^1 + 1`


## Evaluation

The neoTRNG is evaluated as part of the [NEORV32](https://github.com/stnolting/neorv32) processor, where the
neoTRNG is available as standard SoC module. The system was implemented on an AMD Artix-7 (`xc7a35ticsg324-1L`)
FPGA running at 150MHz. For the evaluation the tiny **default configuration** has been used:

```
NUM_CELLS     = 3
NUM_INV_START = 5
NUM_RAW_BITS  = 64
SIM_MODE      = false
```

> [!NOTE]
> A total amount of **32MB** of random data has been obtained for the evaluations. This data set is
available as `data.bin` binary file in the [release](https://github.com/stnolting/neoTRNG/releases) assets.

### Histogram Analysis

For the simple histogram analysis 32MB of random bytes were sampled from the neoTRNG. The obtained bytes
were accumulated according to their occurrence and sorted into bins where each bin represents one specific
byte pattern (1 byte = 8 bits = 256 different patterns). The resulting was then analyzed with regard to
its statistical properties:

* arithmetic mean of all sampled random bytes
* average occurrence across all bit patterns
* min and max occurrences and deviation from the average occurrence

```
[NOTE] integer numbers only
Number of samples: 33554432
Arithmetic mean:   127 (optimum would be 127)

Histogram occurrence
Average:      131072 (optimum would be 33554432/256 = 131072)
Min:          130036 = average - 1036 (deviation) at bin 210 (optimum deviation would be 0)
Max:          132035 = average + 963 (deviation) at bin 163 (optimum deviation would be 0)
Average dev.: +/- 282 (optimum would be 0)
```

### Entropy per Byte

```
Entropy = 7.999995 bits per byte.

Optimum compression would reduce the size
of this 33226752 byte file by 0 percent.

Chi square distribution for 33226752 samples is 243.56, and randomly
would exceed this value 68.61 percent of the times.

Arithmetic mean value of data bytes is 127.4802 (127.5 = random).
Monte Carlo value for Pi is 3.141387759 (error 0.01 percent).
Serial correlation coefficient is 0.000155 (totally uncorrelated = 0.0).
```

### FIPS 140-2 RNG Tests

```
$ rngtest < entropy.bin
rngtest 5
Copyright (c) 2004 by Henrique de Moraes Holschuh
This is free software; see the source for copying conditions.  There is NO warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

rngtest: starting FIPS tests...
rngtest: entropy source drained
rngtest: bits received from input: 265814016
rngtest: FIPS 140-2 successes: 13279
rngtest: FIPS 140-2 failures: 11
rngtest: FIPS 140-2(2001-10-10) Monobit: 1
rngtest: FIPS 140-2(2001-10-10) Poker: 1
rngtest: FIPS 140-2(2001-10-10) Runs: 4
rngtest: FIPS 140-2(2001-10-10) Long run: 5
rngtest: FIPS 140-2(2001-10-10) Continuous run: 0
```

### Hardware Utilization

Mapping results for the neoTRNG implemented within the NEORV32 RISC-V Processor using the default
configuration. Results generated for an Intel Cyclone `EP4CE22F17C6N` FPGA running at 100MHz using Intel
Quartus Prime.

```
Module Hierarchy                                      Logic Cells    Logic Registers
------------------------------------------------------------------------------------
neoTRNG:neoTRNG_inst                                      57 (27)            46 (19)
  neoTRNG_cell:\entropy_source:0:neoTRNG_cell_inst         8  (8)             7  (7)
  neoTRNG_cell:\entropy_source:1:neoTRNG_cell_inst        10 (10)             9  (9)
  neoTRNG_cell:\entropy_source:2:neoTRNG_cell_inst        15 (15)            11 (11)
```

> [!NOTE]
> Synthesis tools might emit a warning that latches and combinatorial loops
have been detected. However, this is no design flaw as this is exactly what we want. :wink:

### Throughput

The neoTRNG's maximum generation rate is defined by two factors:

* A = 2: cycles required by the de-biasing logic to output one raw random bit
* B = NUM_RAW_BITS (default = 64): number of raw random bits required by the sampling unit to generate one random byte

Hence, the neoTRNG requires _at least_ `A * B = 2 * 64 = 128` clock cycles to emit one random byte.
FPGA evaluation has shown that the actual sampling time is around 300 clock cycles. Thus, an
implementation running at 100 MHz can generate approximately 330kB of random data per second.
Higher generation rates can be achieved by running several neoTRNG instances in parallel.


## Simulation

Since the asynchronous ring-oscillators cannot be rtl-simulated (due to the combinatorial loops), the
neoTRNG provides a dedicated simulation mode that is enabled by the `SIM_MODE` generic. When enabled,
a "propagation delay" implemented as simple flip flop is added to the ring-oscillator's inverters.

> [!IMPORTANT]
> The simulation mode is intended for simulation/debugging only!
> Designs with `SIM_MODE` enabled can be synthesized but will **not provide any true/physical random** numbers at all!

The [`sim`](https://github.com/stnolting/neoTRNG/sim) folder provides a simple testbench for the neoTRNG
using the default configuration. The testbench will output the obtained random data bytes as decimal
values to the simulator console. The testbench can be simulated with GHDL by using the provided script:

```
neoTRNG/sim$ sh ghdl.sh
../rtl/neoTRNG.vhd:120:3:@0ms:(assertion note): [neoTRNG] The neoTRNG (v3.3) - A Tiny and Platform-Independent True Random Number Generator, https://github.com/stnolting/neoTRNG
../rtl/neoTRNG.vhd:130:3:@0ms:(assertion warning): [neoTRNG] Simulation-mode enabled (NO TRUE/PHYSICAL RANDOM)!
89
147
99
116
11
55
203
84
97
204
117
196
ghdl:info: simulation stopped by --stop-time @100u
```

The GHDL waveform data is stored to `sim/neoTRNG_tb.ghw` and can be viewed using `gtkwave`:

```
neoTRNG/sim$ gtkwave neoTRNG_tb.ghw
```

A simple simulation run is executed by the [`neoTRNG-sim`](https://github.com/stnolting/neoTRNG/actions)
GitHub actions workflow.


## Acknowledgments

A big thank you to Maarten Baert (@MaartenBaert) who did a great
[evaluation of the neoTRNG (v3.2)](https://github.com/stnolting/neoTRNG/issues/6)
and came up with excellent ideas to improve it.


## References

* Kumar, Sandeep S., et al. "The butterfly PUF protecting IP on every FPGA." 2008 IEEE International Workshop
on Hardware-Oriented Security and Trust. IEEE, 2008.
* Tuncer, Taner, et al. "Implementation of non-periodic sampling true random number generator on FPGA."
Informacije Midem 44.4 (2014): 296-302.
