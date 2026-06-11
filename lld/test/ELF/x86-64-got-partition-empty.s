# This test checks that LLD correctly prunes empty GOT partitions
# during relaxation.
# It verifies that:
# 1. Multiple partitions (.got.text.N) are created due to section splitting.
# 2. Only the partitions that actually contain active GOT entries (needed by
#    relocations) are kept in the final binary (.got.text.1).
# 3. All other empty partitions (.got.text.0, .got.text.2) are successfully
#    pruned and do not appear in the section headers.

# REQUIRES: x86
# RUN: llvm-mc -filetype=obj -triple=x86_64 %s -o %t.o
# RUN: ld.lld -pie --got-partition-threshold=16384 -z max-page-size=4096 --pack-dyn-relocs=relr %t.o -o %t.exe
# RUN: llvm-readelf -S -r %t.exe | FileCheck %s

# CHECK-NOT: .got.text.0
# CHECK:     [{{[ 0-9]+}}] .got.text.1 PROGBITS [[#%x,GOT_ADDR:]]
# CHECK-NOT: .got.text.2
# CHECK:     Relocation section '.relr.dyn'
# CHECK:     [[#%x,GOT_ADDR]]

.section .text.01, "axl", @progbits
.globl _start
_start:
  ret
  .space 7000

.section .text.02, "axl", @progbits
.globl _start_2
_start_2:
  ret
  .space 7000

.section .text.03, "axl", @progbits
.globl _start_3
_start_3:
  movq foo@GOTPCREL(%rip), %rax
  .space 7000

.section .text.04, "axl", @progbits
.globl _start_4
_start_4:
  ret
  .space 20000

.section .data, "aw", @progbits
.hidden foo
foo:
  .quad 0
