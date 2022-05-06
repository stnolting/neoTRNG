library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity neoTRNG_tb is
end neoTRNG_tb;

architecture neoTRNG_tb_rtl of neoTRNG_tb is

  -- configuration --
  constant num_cells_c     : natural := 3;
  constant num_inv_start_c : natural := 5;
  constant num_inv_inc_c   : natural := 2;
  constant num_inv_delay_c : natural := 2;
  constant post_proc_en_c  : boolean := true;

  -- dut --
  component neoTRNG
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
  end component;

  -- generators --
  signal clk_gen, rstn_gen : std_ulogic := '0';

  -- data output --
  signal rnd_valid : std_ulogic;
  signal rnd_data  : std_ulogic_vector(7 downto 0);

begin

  -- generators --
  clk_gen  <= not clk_gen after 10 ns;
  rstn_gen <= '0', '1' after 60 ns;

  -- dut --
  neoTRNG_inst: neoTRNG
  generic map (
    NUM_CELLS     => num_cells_c,
    NUM_INV_START => num_inv_start_c,
    NUM_INV_INC   => num_inv_inc_c,
    NUM_INV_DELAY => num_inv_delay_c,
    POST_PROC_EN  => post_proc_en_c,
    IS_SIM        => true
  )
  port map (
    clk_i    => clk_gen,
    enable_i => rstn_gen,
    data_o   => rnd_data,
    valid_o  => rnd_valid
  );

  -- console output --
  console_output : process(clk_gen)
    file output : text open write_mode is "STD_OUTPUT";
    variable buf_v : line;
  begin
    if rising_edge(clk_gen) then
      if (rnd_valid = '1') then
        write(buf_v, integer'image(to_integer(unsigned(rnd_data))));
        writeline(output, buf_v);
      end if;
    end if;
  end process console_output;


end neoTRNG_tb_rtl;
