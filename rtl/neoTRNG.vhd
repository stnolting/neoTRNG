-- ============================================================================================= --
-- neoTRNG - A Tiny and Platform-Independent True Random Number Generator (Version 3.3)          --
-- https://github.com/stnolting/neoTRNG                                                          --
-- ============================================================================================= --
-- The neoTNG true-random number generator samples free-running ring-oscillators (combinatorial  --
-- loops) to obtain *phase noise* hat is used as entropy source. The individual ring-oscillators --
-- are based on plain inverter chains that are decoupled using individually-enabled latches in   --
-- order to prevent the synthesis tool from trimming parts of the logic.                         --
--                                                                                               --
-- Hence, the TRNG provides a platform- agnostic architecture that can be implemented for any    --
-- FPGA/ASIC without requiring primitive instantiation or technology-specific attributes or      --
-- platform-specific synthesis options.                                                          --
--                                                                                               --
-- The random output from each entropy cells is synchronized and XOR-ed with the other cell's    --
-- outputs before it is and fed into a simple 2-bit "John von Neumann randomness extractor"      --
-- (extracting edges). <NUM_RAW_BITS> de-biased bits are combined using an CRC-style shift       --
-- register (entropy compression) to generate one final random data byte.                        --
-- ============================================================================================= --
-- BSD 3-Clause License                                                                          --
--                                                                                               --
-- Copyright (c) 2025, Stephan Nolting. All rights reserved.                                     --
--                                                                                               --
-- Redistribution and use in source and binary forms, with or without modification, are          --
-- permitted provided that the following conditions are met:                                     --
--                                                                                               --
-- 1. Redistributions of source code must retain the above copyright notice, this list of        --
--    conditions and the following disclaimer.                                                   --
--                                                                                               --
-- 2. Redistributions in binary form must reproduce the above copyright notice, this list of     --
--    conditions and the following disclaimer in the documentation and/or other materials        --
--    provided with the distribution.                                                            --
--                                                                                               --
-- 3. Neither the name of the copyright holder nor the names of its contributors may be used to  --
--    endorse or promote products derived from this software without specific prior written      --
--    permission.                                                                                --
--                                                                                               --
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS   --
-- OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF               --
-- MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE    --
-- COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     --
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE --
-- GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED    --
-- AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     --
-- NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  --
-- OF THE POSSIBILITY OF SUCH DAMAGE.                                                            --
-- ============================================================================================= --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

architecture neoTRNG_rtl of neoTRNG is

  -- round_up[log2(x)] --
  function clog2_f(x : natural) return natural is
  begin
    for i in 0 to natural'high loop
      if (2**i >= x) then
        return i;
      end if;
    end loop;
    return 0;
  end function clog2_f;

  -- entropy source cell --
  component neoTRNG_cell
    generic (
      NUM_INV  : natural range 3 to 999 := 3; -- number of inverters, has to be odd, min 3
      SIM_MODE : boolean := false -- enable simulation mode (no physical random if enabled!)
    );
    port (
      clk_i  : in  std_ulogic; -- clock
      rstn_i : in  std_ulogic; -- reset, low-active, async, optional
      en_i   : in  std_ulogic; -- enable-chain input
      en_o   : out std_ulogic; -- enable-chain output
      rnd_o  : out std_ulogic  -- random data (sync)
    );
  end component;

  -- entropy cell interconnect --
  signal cell_en_in  : std_ulogic_vector(NUM_CELLS-1 downto 0); -- enable-sreg input
  signal cell_en_out : std_ulogic_vector(NUM_CELLS-1 downto 0); -- enable-sreg output
  signal cell_rnd    : std_ulogic_vector(NUM_CELLS-1 downto 0); -- cell random output
  signal cell_sum    : std_ulogic; -- combined random data

  -- de-biasing --
  signal debias_sreg  : std_ulogic_vector(1 downto 0); -- sample buffer
  signal debias_state : std_ulogic; -- process de-biasing every second cycle
  signal debias_valid : std_ulogic; -- result bit valid
  signal debias_data  : std_ulogic; -- result bit

  -- sampling control --
  signal sample_en   : std_ulogic; -- global enable
  signal sample_sreg : std_ulogic_vector(7 downto 0); -- shift-register / de-serializer
  signal sample_cnt  : std_ulogic_vector(clog2_f(NUM_RAW_BITS) downto 0); -- bits-per-sample counter

  -- CRC polynomial (tap mask) --
  constant poly_c : std_ulogic_vector(7 downto 0) := "00000111"; -- CRC-8: x^8 + x^2 + x^1 + x^0

begin

  -- Sanity Checks --------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  assert false report
    "[neoTRNG] The neoTRNG (v3.3) - A Tiny and Platform-Independent True Random Number Generator, " &
    "https://github.com/stnolting/neoTRNG" severity note;

  assert (NUM_INV_START mod 2) /= 0 report
    "[neoTRNG] Number of inverters in first cell [NUM_INV_START] has to be odd!" severity error;

  assert 2**clog2_f(NUM_RAW_BITS) = NUM_RAW_BITS report
    "[neoTRNG] Number of pre-processed raw bits [NUM_RAW_BITS] has to be a power of 2!" severity error;

  assert not SIM_MODE report
    "[neoTRNG] Simulation-mode enabled (NO TRUE/PHYSICAL RANDOM)!" severity warning;


  -- Entropy Source -------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  entropy_cell_gen:
  for i in 0 to NUM_CELLS-1 generate
    neoTRNG_cell_inst: neoTRNG_cell
    generic map (
      NUM_INV  => NUM_INV_START + (2 * i), -- increasing (odd) ring-oscillator length
      SIM_MODE => SIM_MODE
    )
    port map (
      clk_i  => clk_i,
      rstn_i => rstn_i,
      en_i   => cell_en_in(i),
      en_o   => cell_en_out(i),
      rnd_o  => cell_rnd(i)
    );
  end generate;

  -- enable-shift-register chain --
  cell_en_in(0) <= sample_en;
  cell_en_in(NUM_CELLS-1 downto 1) <= cell_en_out(NUM_CELLS-2 downto 0);

  -- combine cell outputs --
  combine: process(cell_rnd)
    variable tmp_v : std_ulogic;
  begin
    tmp_v := '0';
    for i in 0 to NUM_CELLS-1 loop
      tmp_v := tmp_v xor cell_rnd(i);
    end loop;
    cell_sum <= tmp_v;
  end process combine;


  -- John von Neumann Randomness Extractor (De-Biasing) -------------------------------------
  -- -------------------------------------------------------------------------------------------
  debiasing: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      debias_sreg  <= (others => '0');
      debias_state <= '0';
    elsif rising_edge(clk_i) then
      debias_sreg <= debias_sreg(0) & cell_sum;
      -- start operation when last cell is enabled and process in every second cycle --
      debias_state <= (not debias_state) and cell_en_out(cell_en_out'left);
    end if;
  end process debiasing;

  -- check groups of two non-overlapping bits from the random stream for edges --
  debias_valid <= debias_state and (debias_sreg(1) xor debias_sreg(0));
  debias_data  <= debias_sreg(0);


  -- Sampling Control -----------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  sampling_control: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      sample_en   <= '0';
      sample_cnt  <= (others => '0');
      sample_sreg <= (others => '0');
    elsif rising_edge(clk_i) then
      sample_en <= enable_i;
      if (sample_en = '0') or (sample_cnt(sample_cnt'left) = '1') then -- start new iteration
        sample_cnt  <= (others => '0');
        sample_sreg <= (others => '0');
      elsif (debias_valid = '1') then -- valid raw random bit
        sample_cnt <= std_ulogic_vector(unsigned(sample_cnt) + 1);
        -- CRC-style sampling shift-register to mix random stream --
        if ((sample_sreg(sample_sreg'left) xor debias_data) = '1') then -- feedback bit
          sample_sreg <= (sample_sreg(sample_sreg'left-1 downto 0) & '0') xor poly_c;
        else
          sample_sreg <= (sample_sreg(sample_sreg'left-1 downto 0) & '0');
        end if;
      end if;
    end if;
  end process sampling_control;

  -- TRNG output stream --
  data_o  <= sample_sreg;
  valid_o <= sample_cnt(sample_cnt'left);

end neoTRNG_rtl;


-- ================================================================================================ --
-- neoTRNG entropy source cell, based on a simple ring-oscillator constructed from an odd number    --
-- of inverter. The inverters are decoupled using individually-enabled latches to prevent synthesis --
-- from "optimizing" (=removing) parts of the oscillator chain.                                     --
-- ================================================================================================ --

library ieee;
use ieee.std_logic_1164.all;

entity neoTRNG_cell is
  generic (
    NUM_INV  : natural range 3 to 999 := 3; -- number of inverters, has to be odd, min 3
    SIM_MODE : boolean := false -- enable simulation mode (no physical random if enabled!)
  );
  port (
    clk_i  : in  std_ulogic; -- clock
    rstn_i : in  std_ulogic; -- reset, low-active, async, optional
    en_i   : in  std_ulogic; -- enable-chain input
    en_o   : out std_ulogic; -- enable-chain output
    rnd_o  : out std_ulogic  -- random data (sync)
  );
end neoTRNG_cell;

architecture neoTRNG_cell_rtl of neoTRNG_cell is

  signal sreg    : std_ulogic_vector(NUM_INV-1 downto 0); -- enable-shift-register
  signal latch   : std_ulogic_vector(NUM_INV-1 downto 0); -- ring oscillator: latches
  signal inv_in  : std_ulogic_vector(NUM_INV-1 downto 0); -- ring oscillator: inverter inputs
  signal inv_out : std_ulogic_vector(NUM_INV-1 downto 0); -- ring oscillator: inverter outputs
  signal sync    : std_ulogic_vector(1 downto 0); -- output synchronizer

begin

  -- Enable Shift-Register ------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- Using individual enable signals from a shift register for each inverter in order to prevent
  -- the synthesis tool from removing all but one inverter (since they implement "logical
  -- identical functions"). This makes the TRNG platform independent as we do not require tool-/
  -- technology-specific primitives, attributes or other options.

  en_shift_reg: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      sreg <= (others => '0');
    elsif rising_edge(clk_i) then
      sreg <= sreg(sreg'left-1 downto 0) & en_i;
    end if;
  end process en_shift_reg;

  -- output for global enable chain --
  en_o <= sreg(sreg'left);


  -- Physical Entropy Source: Ring Oscillator -----------------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- Each cell is based on a simple ring oscillator with an odd number of inverters. Each
  -- inverter is followed by a latch that provides a reset (to start in a defined state) and
  -- a latch-enable to make the latch transparent. Switching to transparent mode is done one by
  -- one by the enable shift register.

  ring_osc_gen:
  for i in 0 to NUM_INV-1 generate

    -- latch with global reset and individual enable --
    latch(i) <= '0' when (en_i = '0') else latch(i) when (sreg(i) = '0') else inv_out(i);

    -- inverter for actual synthesis --
    inverter_phy:
    if not SIM_MODE generate
      inv_out(i) <= not inv_in(i); -- this is one part of the ring oscillator's physical propagation delay
    end generate;

    -- inverter with "propagation delay" (implemented as a simple FF) --
    inverter_sim:
    if SIM_MODE generate -- for SIMULATION ONLY
      inverter_sim_ff: process(clk_i) -- this will NOT generate true random numbers
      begin
        if rising_edge(clk_i) then
          inv_out(i) <= not inv_in(i);
        end if;
      end process inverter_sim_ff;
    end generate;

  end generate;

  -- chaining --
  inv_in(0) <= latch(NUM_INV-1); -- beginning/end of chain
  inv_in(NUM_INV-1 downto 1) <= latch(NUM_INV-2 downto 0); -- inside chain


  -- Output Synchronizer --------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- Sample the actual entropy source (= phase noise) and move it to the system's clock domain.

  synchronizer: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      sync <= (others => '0');
    elsif rising_edge(clk_i) then
      sync <= sync(0) & latch(latch'left);
    end if;
  end process synchronizer;

  -- cell output --
  rnd_o <= sync(1);

end neoTRNG_cell_rtl;
