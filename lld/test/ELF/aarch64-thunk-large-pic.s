// REQUIRES: aarch64
// RUN: split-file %s %t
// RUN: llvm-mc -filetype=obj -triple=aarch64 %t/asm -o %t.o
// RUN: ld.lld --script %t/lds --shared %t.o -o %t.so 2>&1
// RUN: llvm-objdump -d --no-show-raw-insn --print-imm-hex %t.so | FileCheck %s

// Check that GOT-based range extension thunks are generated for destinations further than 4GiB.

//--- asm
 .section .text_low, "ax", %progbits
 .globl low_target
 .type low_target, %function
low_target:
 // Need GOT-based thunk to high_target
 bl high_target
 ret
// CHECK: <low_target>:
// CHECK-NEXT:        0:       bl      0x8 <__AArch64ADRPThunk_high_target>
// CHECK-NEXT:                 ret

// CHECK: <__AArch64ADRPThunk_high_target>:
// CHECK-NEXT:        8:       adrp    x16, 0x0
// CHECK-NEXT:                 ldr     x16, [x16]
// CHECK-NEXT:                 br      x16

 .section .text_high, "ax", %progbits
 .globl high_target
 .type high_target, %function
high_target:
 ret

//--- lds
PHDRS {
  low PT_LOAD FLAGS(0x1 | 0x4);
  high PT_LOAD FLAGS(0x1 | 0x4);
}
SECTIONS {
  .text_low : { *(.text_low) } :low
  .text_high 0x100000000 : { *(.text_high) } :high
}
