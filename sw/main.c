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
#define BAUD_RATE_STD   19200 // initial UART baud rate
#define BAUD_RATE_FAST 115200 // fast UART baud rate


/**********************************************************************//**
 * Prototypes
 **************************************************************************/
uint8_t get_rnd(void);
uint32_t average_access_time(void);


/**********************************************************************//**
 * Main function
 **************************************************************************/
int main() {

  // initialize the neorv32 runtime environment
  // this will take care of handling all CPU traps (interrupts and exceptions)
  neorv32_rte_setup();

  // setup UART0 at default baud rate, no parity bits, ho hw flow control
  neorv32_uart0_setup(BAUD_RATE_STD, PARITY_NONE, FLOW_CONTROL_RTSCTS);

  neorv32_uart0_printf("neoTRNG TEST\n");
  neorv32_uart0_printf("build: "__DATE__" "__TIME__"\n");

  // check if TRNG unit is implemented at all
  if (neorv32_trng_available() == 0) {
    neorv32_uart0_printf("No TRNG implemented.");
    return 1;
  }

  neorv32_trng_enable(); // enable TRNG

  neorv32_uart0_printf("Average TRNG system access time: %u cycles @ %uMHz\n", average_access_time(), NEORV32_SYSINFO.CLK);

  neorv32_uart0_printf("Going to %u Baud and starting output in 20s.\n", (uint32_t)BAUD_RATE_FAST);
  while (neorv32_uart0_tx_busy());
  neorv32_uart0_setup(BAUD_RATE_FAST, PARITY_NONE, FLOW_CONTROL_RTSCTS);

  neorv32_cpu_delay_ms(20000); // use this time to "warm-up" TRNG

  while(1) {
    neorv32_uart0_putc((char)get_rnd());
  }

  return 0;
}


/**********************************************************************//**
 * Get raw random byte
 **************************************************************************/
uint8_t get_rnd(void) {

  uint8_t raw;

  while(neorv32_trng_get(&raw));

  return raw;
}


/**********************************************************************//**
 * Get average number of clock cycles required to get random byte
 **************************************************************************/
uint32_t average_access_time(void) {

  int i;
  const uint32_t runs = 4096;
  uint8_t raw;

  neorv32_cpu_csr_write(CSR_MCYCLE, 0);

  for (i=0; i<runs; i++) {
    while(neorv32_trng_get(&raw));
  }

  return neorv32_cpu_csr_read(CSR_MCYCLE)/runs;
}
