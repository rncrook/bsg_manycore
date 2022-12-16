
// DMA Push while Core polls WB address
// --------------------------------------------------
// - initialize int and floating point register file
// - write sequence to dmem (initialize dmem)
// - initialize DMA Push, from dmem to dram
// - core polls writeback address (lw t0, 0(wb_address)), waits until a 1 is set
// - core reads dram starting at address into floating-point registers (just 16 32-bit words for this test)

#include "bsg_manycore_arch.h"
#include "bsg_manycore_asm.h"
#define N 1024

// allocate 4KB in DRAM
.section .dram, "aw"
  dram_arr: .space (N*4)


// initialize
.text
li x1, 0
li x2, 0
li x3, 0
li x4, 0
li x5, 0
li x6, 0
li x7, 0
li x8, 0
li x9, 0
li x10,0
li x11,0
li x12,0
li x13,0
li x14,0
li x15,0
li x16,0
li x17,0
li x18,0
li x19,0
li x20,0
li x21,0
li x22,0
li x23,0
li x24,0
li x25,0
li x26,0
li x27,0
li x28,0
li x29,0
li x30,0
li x31,0

fcvt.s.w f0, x0
fcvt.s.w f1, x0
fcvt.s.w f2, x0
fcvt.s.w f3, x0
fcvt.s.w f4, x0
fcvt.s.w f5, x0
fcvt.s.w f6, x0
fcvt.s.w f7, x0
fcvt.s.w f8, x0
fcvt.s.w f9, x0
fcvt.s.w f10,x0
fcvt.s.w f11,x0
fcvt.s.w f12,x0
fcvt.s.w f13,x0
fcvt.s.w f14,x0
fcvt.s.w f15,x0
fcvt.s.w f16,x0
fcvt.s.w f17,x0
fcvt.s.w f18,x0
fcvt.s.w f19,x0
fcvt.s.w f20,x0
fcvt.s.w f21,x0
fcvt.s.w f22,x0
fcvt.s.w f23,x0
fcvt.s.w f24,x0
fcvt.s.w f25,x0
fcvt.s.w f26,x0
fcvt.s.w f27,x0
fcvt.s.w f28,x0
fcvt.s.w f29,x0
fcvt.s.w f30,x0
fcvt.s.w f31,x0

// write to DMEM
li t0, 0
li t1, 0
li t2, N
write_loop:
  sw t1, 0(t0)
  addi t1, t1, 1
  addi t0, t0, 4
  bne t1, t2, write_loop

li t0, 0
li t1, 0xDEADCAFE
sw t1, 0(t0)


// write to dma control registers
li t4, 4096          // base tile-memory map offset

li t0, 0          // local dmem addr
sw t0, 0(t4)
la t0, dram_arr   // remote dmem pointer
sw t0, 4(t4)
li t0, 128        // num_bytes
sw t0, 8(t4)
li t0, 0x0ABC00A5  // wb_addr: ABC, match_id:A, push_not_pull: 1'b1, go: 1'b1
sw t0, 12(t4)


// poll wb_address
li t0, 0xABC
li t1, 1

writeback_poll:
  lw t2, 0(t0)
  bne t2, t1, writeback_poll

li t0, 0
li t1, 10

wait1:
  addi t0, t0, 1
  bne t0, t1, wait1


la t1, dram_arr

flw f0, 0(t1)
flw f1, 4(t1)
flw f2, 8(t1)
flw f3, 12(t1)
flw f4, 16(t1)
flw f5, 20(t1)
flw f6, 24(t1)
flw f7, 28(t1)
flw f8, 32(t1)
flw f9, 36(t1)
flw f10, 40(t1)
flw f11, 44(t1)
flw f12, 48(t1)
flw f13, 52(t1)
flw f14, 56(t1)
flw f15, 60(t1)
flw f16, 64(t1)
flw f17, 68(t1)
flw f18, 72(t1)
flw f19, 76(t1)
flw f20, 80(t1)
flw f21, 84(t1)
flw f22, 88(t1)
flw f23, 92(t1)
flw f24, 96(t1)
flw f25, 100(t1)
flw f26, 104(t1)
flw f27, 108(t1)
flw f28, 112(t1)
flw f29, 116(t1)
flw f30, 120(t1)
flw f31, 124(t1)



// wait for remaining loads to return
li t0, 0
li t1, 100

wait2:
  addi t0, t0, 1
  bne t0, t1, wait2



















pass:
  bsg_asm_finish(IO_X_INDEX, 0)

pass_loop:
  beq x0, x0, pass_loop

fail:
  bsg_asm_fail(IO_X_INDEX, 0)

fail_loop:
  beq x0, x0, fail_loop
