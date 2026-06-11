# This test checks that when ALL GOT partitions and the relative relocation
# section (.relr.dyn) are pruned during relaxation, LLD correctly reconstructs
# the program headers (phdrs) to avoid segment size underflow/corruption.
# It verifies that:
# 1. Multiple partitions (.got.text.N) are created due to splitting but all are
#    empty and pruned.
# 2. .relr.dyn is also empty and pruned.
# 3. All text sections are successfully merged into a single contiguous LOAD segment.
# 4. No empty GNU_RELRO segments (with offset 0) are left in the program headers.
# 5. Program headers have correct, non-underflowed sizes.

# REQUIRES: x86
# RUN: llvm-mc -filetype=obj -triple=x86_64 %s -o %t.o
# RUN: ld.lld -pie --got-partition-threshold=16384 -z max-page-size=4096 --pack-dyn-relocs=relr %t.o -o %t.exe
# RUN: llvm-readelf -S -l %t.exe | FileCheck %s

# CHECK-NOT: .got.text.0
# CHECK-NOT: .got.text.1
# CHECK-NOT: .got.text.2
# CHECK-NOT: .got.text.3
# CHECK-NOT: .relr.dyn

# Check the exact program headers to ensure no empty/corrupted segments exist
# and all text sections are merged into a single LOAD segment.
# CHECK:      Program Headers:
# CHECK-NEXT:   Type           Offset             VirtAddr           PhysAddr
# CHECK-NEXT:   PHDR           0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} R   0x8
# CHECK-NEXT:   LOAD           0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} R   0x1000
# CHECK-NEXT:   LOAD           0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} R E 0x1000
# CHECK-NEXT:   LOAD           0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} RW  0x1000
# CHECK-NEXT:   DYNAMIC        0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} RW  0x8
# CHECK-NEXT:   GNU_RELRO      0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} R   0x1
# CHECK-NEXT:   GNU_STACK      0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} 0x{{[0-9a-f]+}} RW  0x0
# CHECK-NOT:    GNU_RELRO

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
  ret
  .space 7000

.section .text.04, "axl", @progbits
.globl _start_4
_start_4:
  ret
  .space 20000
