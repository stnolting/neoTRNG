-- simple neoTRNG testbench --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity neoTRNG_tb is
  generic (
    NUM_CELLS     : natural range 1 to 99   := 3; -- number of ring-oscillator cells
    NUM_INV_START : natural range 3 to 99   := 5; -- number of inverters in first ring-oscillator cell, has to be odd
    NUM_RAW_BITS  : natural range 1 to 4096 := 64 -- number of XOR-ed raw bits per random sample byte (has to be a power of 2)
  );
end neoTRNG_tb;

architecture neoTRNG_tb_rtl of neoTRNG_tb is

  -- neoTRNG --
  component neoTRNG
    generic (
      NUM_CELLS     : natural range 1 to 99 := 3;
      NUM_INV_START : natural range 3 to 99 := 5;
      NUM_RAW_BITS  : natural range 1 to 4096 := 64;
      SIM_MODE      : boolean := false
    );
    port (
      clk_i    : in  std_ulogic;
      rstn_i   : in  std_ulogic;
      enable_i : in  std_ulogic;
      valid_o  : out std_ulogic;
      data_o   : out std_ulogic_vector(7 downto 0)
    );
  end component;

  -- generators --
  signal clk_gen, rstn_gen, en_gen : std_ulogic := '0';

  -- interface --
  signal rnd_valid : std_ulogic;
  signal rnd_data  : std_ulogic_vector(7 downto 0);

begin

  -- generators --
  clk_gen  <= not clk_gen after 10 ns;
  rstn_gen <= '0', '1' after 25 ns;
  en_gen   <= '0', '1' after 100 ns;

  -- dut --
  neoTRNG_inst: neoTRNG
  generic map (
    NUM_CELLS     => NUM_CELLS,
    NUM_INV_START => NUM_INV_START,
    NUM_RAW_BITS  => NUM_RAW_BITS,
    SIM_MODE      => true -- this is a simulation
  )
  port map (
    clk_i    => clk_gen,
    rstn_i   => rstn_gen,
    enable_i => en_gen,
    valid_o  => rnd_valid,
    data_o   => rnd_data
  );

  -- console output --
  console_output : process(clk_gen)
    file     output : text open write_mode is "STD_OUTPUT";
    variable line_v : line;
  begin
    if rising_edge(clk_gen) then
      if (rnd_valid = '1') then
        write(line_v, integer'image(to_integer(unsigned(rnd_data))));
        writeline(output, line_v);
      end if;
    end if;
  end process console_output;

end neoTRNG_tb_rtl;
