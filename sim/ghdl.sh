#!/usr/bin/env bash

set -e

# Analyze sources
ghdl -a --std=08 ../rtl/neoTRNG.vhd
ghdl -a --std=08 neoTRNG_tb.vhd

# Elaborate top entity
ghdl -e --std=08 neoTRNG_tb

# Run simulation
ghdl -e --std=08 neoTRNG_tb
ghdl -r --std=08 neoTRNG_tb --stop-time=100us --wave=neoTRNG_tb.ghw
