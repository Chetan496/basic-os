# Phase 1 — Bootloader Basics

Goal: Write the first 512 bytes that the BIOS loads into memory at `0x7C00` and execute.

## Concepts

- BIOS: built-in firmware in your PC. On power-up, it initializes hardware and looks for a boot device.
- MBR (Master Boot Record): first 512 bytes of the boot device. BIOS loads this to physical address `0x7C00` and jumps to it (CS:IP = 0x0000:0x7C00).
- "Real mode": early x86 state — 16-bit, segment:offset addressing, 1MB addressable memory.

## Skeleton bootloader (stage 1)

We'll keep it minimal:

- `bits 16` — tell NASM we're 16-bit
- ORG 0x7C00 — origin address
- Set up a stack
- Print a character via BIOS interrupt `int 0x10` (AH=0x0E, character in AL)
- Pad to 510 bytes
- Boot signature `0xAA55` at bytes 510-511

## Build & Run

```bash
nasm -f bin boot.asm -o boot.img
# Run with QEMU:
qemu-system-i386 -fda boot.img
```

## Files

- `boot.asm` — the assembly source
- `boot.img` — assembled binary
- We'll write notes here as we go.

## Check-in Question

*(I'll ask one at a time — answer when you're comfortable.)*

**Q1:** When you power on your PC, where does the BIOS look for the first code to run? And what address does it load that code into, in memory?
