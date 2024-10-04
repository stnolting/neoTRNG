#!/usr/bin/env bash

set -e

cd $(dirname "$0")

ghdl -a ../rtl/neoTRNG.vhd neoTRNG_tb.vhd
ghdl -r neoTRNG_tb --stop-time=100us --wave=neoTRNG_tb.ghw
