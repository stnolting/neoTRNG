// #################################################################################################
// # << neoTRNG Test (TRNG Peripheral of the NEORV32 RISC-V Processor)                             #
// # ********************************************************************************************* #
// # NEORV32 HQ: https://github.com/stnolting/neorv32                                              #
// # ********************************************************************************************* #
// # BSD 3-Clause License                                                                          #
// #                                                                                               #
// # Copyright (c) 2021, Stephan Nolting. All rights reserved.                                     #
// #                                                                                               #
// # Redistribution and use in source and binary forms, with or without modification, are          #
// # permitted provided that the following conditions are met:                                     #
// #                                                                                               #
// # 1. Redistributions of source code must retain the above copyright notice, this list of        #
// #    conditions and the following disclaimer.                                                   #
// #                                                                                               #
// # 2. Redistributions in binary form must reproduce the above copyright notice, this list of     #
// #    conditions and the following disclaimer in the documentation and/or other materials        #
// #    provided with the distribution.                                                            #
// #                                                                                               #
// # 3. Neither the name of the copyright holder nor the names of its contributors may be used to  #
// #    endorse or promote products derived from this software without specific prior written      #
// #    permission.                                                                                #
// #                                                                                               #
// # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS   #
// # OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF               #
// # MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE    #
// # COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     #
// # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE #
// # GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED    #
// # AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     #
// # NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  #
// # OF THE POSSIBILITY OF SUCH DAMAGE.                                                            #
// # ********************************************************************************************* #
// # neoTRNG - https://github.com/stnolting/neoTRNG                            (c) Stephan Nolting #
// #################################################################################################

#include <neorv32.h>


/**********************************************************************//**
 * User configuration
 **************************************************************************/
#define UART0_BAUD 19200 // console
#define UART1_BAUD 2000000 // data output


/**********************************************************************//**
 * Get average number of clock cycles required to get a single random byte
 **************************************************************************/
uint32_t get_avg_sample_time(void) {

  int i;
  const uint32_t runs = 4096;
  uint8_t raw;

  neorv32_cpu_csr_write(CSR_MCYCLE, 0);

  for (i=0; i<runs; i++) {
    while(neorv32_trng_get(&raw));
  }

  return neorv32_cpu_csr_read(CSR_MCYCLE)/runs;
}


/**********************************************************************//**
 * Main function
 **************************************************************************/
int main() {

  // initialize the neorv32 runtime environment
  // this will take care of handling all CPU traps (interrupts and exceptions)
  neorv32_rte_setup();


  // setup console UART
  if (neorv32_uart0_available() == 0) {
    return 1;
  }
  neorv32_uart0_setup(UART0_BAUD, PARITY_NONE, FLOW_CONTROL_NONE);
  neorv32_uart0_printf("neoTRNG V2 - Test Program\n\n");


  // setup data output UART
  if (neorv32_uart1_available() == 0) {
    neorv32_uart0_printf("ERROR! UART1 not synthesized!\n");
    return 1;
  }
  neorv32_uart1_setup(UART1_BAUD, PARITY_NONE, FLOW_CONTROL_CTS);


  // TRNG available?
  if (neorv32_trng_available() == 0) {
    neorv32_uart0_printf("ERROR! TRNG not synthesized!\n");
    return 1;
  }


  // check if TRNG is using simulation mode
  if (neorv32_trng_check_sim_mode() != 0) {
    neorv32_uart0_printf("WARNING! TRNG uses simulation-only mode implementing a pseudo-RNG (LFSR)\n");
    neorv32_uart0_printf("         instead of the physical entropy sources!\n");
  }


  // start TRNG and print average sample time
  neorv32_uart0_printf("Starting TRNG...\n");
  neorv32_trng_enable(); // enable TRNG
  neorv32_cpu_delay_ms(2000); // warm-up TRNG
  uint32_t tmp_clock = NEORV32_SYSINFO.CLK;
  uint32_t tmp_cycles = get_avg_sample_time();
  neorv32_uart0_printf("Average throughput: %u bytes/s (%u cycles/byte @ %u MHz)\n", tmp_clock/tmp_cycles, tmp_cycles, tmp_clock);

  neorv32_uart0_printf("Starting RND data stream (UART1, CTS flow-control)...\n");

  // stream loop
  uint32_t rnd = 0;
  while(1) {

    // wait for free space in UART1 TX buffer
    while ((NEORV32_UART1.CTRL & (1 << UART_CTRL_TX_FULL)));

    // wait for valid random data
    rnd = 0;
    do {
      rnd = NEORV32_TRNG.CTRL;
    } while ((rnd & (1 << TRNG_CTRL_VALID)) == 0); // valid?

    // send data (lowest 8-bit)
    NEORV32_UART1.DATA = rnd;
  }

  neorv32_uart0_printf("done\n");
  return 0;
}
