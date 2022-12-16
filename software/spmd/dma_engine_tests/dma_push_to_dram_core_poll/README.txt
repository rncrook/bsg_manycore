DMA Push while Core polls WB address
--------------------------------------------------
- initialize int and floating point register file
- write sequence to dmem (initialize dmem)
- initialize DMA Push, from dmem to dram
- core polls writeback address (lw t0, 0(wb_address)), waits until a 1 is set
- core reads dram starting at address into floating-point registers (just 16 32-bit words for this test)




