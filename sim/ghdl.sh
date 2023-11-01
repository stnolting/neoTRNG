#!/usr/bin/env bash

set -e

# Analyze sources
ghdl -a ../rtl/neoTRNG.vhd
ghdl -a neoTRNG_tb.vhd

# Elaborate top entity
ghdl -e neoTRNG_tb

# Run simulation
ghdl -e neoTRNG_tb
ghdl -r neoTRNG_tb --stop-time=100us --wave=neoTRNG_tb.ghw
