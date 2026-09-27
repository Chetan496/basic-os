# Phase 1 — Bootloader Concepts

This document explains everything behind our first 512 bytes of code: how the PC
starts, why the magic address `0x7C00` exists, how we talk to the screen through
the BIOS, and exactly what every line of `boot.asm` does.

---

## 1. Hexadecimal Addresses

### What is `0x7C00`?

`0x7C00` is a **memory address** written in hexadecimal (base 16). The `0x`
prefix is the C-style convention that means "the digits that follow are hex."

The same number in three bases:

| Base        | Value                              | Notes                              |
|-------------|------------------------------------|------------------------------------|
| Hexadecimal | `0x7C00`                           | digits 0–9, then A–F (A=10 … F=15) |
| Decimal     | `31744`                            | base 10, what humans count in      |
| Binary      | `0111 1100 0000 0000`              | base 2, what the hardware sees     |

Converting `0x7C00` to decimal by hand:

```
0x7C00 = 7×16³ + C×16² + 0×16¹ + 0×16⁰
       = 7×4096 + 12×256 + 0 + 0
       = 28672 + 3072
       = 31744
```

And each hex digit maps to exactly 4 binary bits (a *nibble*), which makes
hex↔binary conversion trivial:

```
  7      C      0      0
0111   1100   0000   0000
```

### Why hex is used in low-level OS development

1. **One hex digit = exactly 4 bits.** A 16-bit address is always 4 hex digits,
   a 32-bit address is always 8. No other base lines up this cleanly with
   bytes (8 bits = 2 hex digits).
2. **Alignment is visible at a glance.** `0x7C00` clearly ends in two zeros,
   so it's aligned to a 256-byte boundary. In decimal, `31744` tells you
   nothing. Hardware addresses, page tables, and sector boundaries are almost
   always "round" in hex.
3. **It matches the hardware's structure.** Registers, memory dumps, and
   datasheets all speak hex. Reading a hex dump like `7C00: B4 0E B0 48 ...`
   lets you decode bytes directly into instructions.
4. **Decimal hides bit patterns.** Whether bit 11 is set in `31744` requires
   mental long division; in `0x7C00` you can see it instantly.

You'll see hex everywhere from now on: addresses (`0x7C00`), interrupt numbers
(`0x10`), signatures (`0xAA55`), and register values (`0x0E`).

---

## 2. Physical vs Virtual Memory, Real Mode vs Protected Mode

### Physical vs Virtual memory

- **Physical memory** is the actual RAM chips in the machine. A physical
  address is a real electrical location on the memory bus. When the BIOS loads
  our bootloader to `0x7C00`, byte 0 of our file really sits at physical byte
  31744 of RAM.
- **Virtual memory** is an illusion the CPU creates for running programs once
  *paging* is enabled. Each program gets its own private address space
  (e.g. every program can believe it starts at address `0x00400000`), and the
  CPU's Memory Management Unit (MMU) translates virtual addresses to physical
  ones on every access, using page tables set up by the OS.

Right now there is **no OS** — our bootloader *is* the only software running —
so we deal purely with physical addresses. Virtual memory becomes relevant in
later phases when we enable paging.

### Real Mode (16-bit)

Real mode is the CPU state every x86 processor wakes up in, kept for backward
compatibility all the way back to the 1978 Intel 8086:

- **16-bit registers and instructions** (AX, BX, CX, DX, …).
- **1 MiB of addressable memory** (addresses `0x00000`–`0xFFFFF`).
- **Segment:offset addressing.** A physical address is computed as
  `segment × 16 + offset`. The BIOS jumps to our code with
  `CS:IP = 0x0000:0x7C00`, i.e. `0 × 16 + 0x7C00 = 0x7C00`.
- **No memory protection.** Any code can read or write any byte of RAM, or any
  hardware port. There is nothing stopping a bug from wiping out the BIOS
  itself.
- **BIOS services are available** via software interrupts (`int 0x10` for
  video, `0x13` for disk, `0x16` for keyboard, …). This is the one big
  convenience of real mode.

### Protected Mode (32-bit)

Protected mode is the "real" operating state of modern x86 CPUs:

- **32-bit registers** (EAX, EBX, …) and up to 4 GiB of addressable memory.
- **Flat addressing** — with the right segment setup, an address is just an
  offset, no `segment × 16` arithmetic.
- **Memory protection and privilege rings.** The CPU can stop user programs
  from touching kernel memory (this is what makes a real OS stable).
- **Paging becomes available**, enabling virtual memory.
- **The BIOS interrupts are gone.** Switching to protected mode means losing
  `int 0x10` and friends — the OS must talk to hardware directly (VGA memory,
  disk controllers, …) or temporarily switch back.

The roadmap for this project: boot in **real mode** (phase 1), use BIOS
services to load more code, then make the jump to **protected mode** in a
later phase.

---

## 3. The Boot Sequence, Step by Step

What happens between pressing the power button and our code running:

1. **Power-on / reset.** The power supply stabilizes and the motherboard
   asserts the CPU's RESET pin. The CPU initializes its registers to fixed
   values, including `CS:IP = 0xF000:0xFFF0`.
2. **First instruction fetch.** That address maps to physical `0xFFFF0` — 16
   bytes below the top of the 1 MiB real-mode space. This region is ROM, not
   RAM: it's the BIOS chip. The instruction there is a jump into the main
   BIOS code.
3. **POST (Power-On Self-Test).** The BIOS initializes and tests hardware:
   memory, keyboard, video card, disks. It also builds the interrupt vector
   table at physical address `0x00000` so that software interrupts like
   `int 0x10` work.
4. **Boot device search.** The BIOS walks its configured boot order (floppy,
   hard disk, USB, …) looking for a **bootable** device.
5. **Loading sector 0.** For each candidate device, the BIOS reads the very
   first 512-byte sector (the *boot sector* / MBR) into physical memory at
   **`0x7C00`**. (Why `0x7C00`? Historical convention from the original IBM
   PC — it leaves room below for the interrupt vector table and BIOS data,
   and above for the bootloader to grow.)
6. **Checking the `0xAA55` signature.** The BIOS verifies that the last two
   bytes of the sector are `0x55` at offset 510 and `0xAA` at offset 511
   (which, as a little-endian 16-bit word, reads as `0xAA55`). If the
   signature is missing, the device is not bootable and the BIOS moves on to
   the next one.
7. **Jumping to `0x7C00`.** With a valid signature, the BIOS jumps to
   `0x0000:0x7C00` — the first byte of our code. The CPU is in **real mode**,
   and the boot drive number is passed in register `DL`. From this instant,
   *we* are in control of the machine. There is no operating system below us
   — only our 512 bytes and the BIOS services.

```
Power-on
   │
   ▼
CPU reset ──► BIOS ROM (0xFFFF0)
   │
   ▼
POST: hardware init + interrupt table
   │
   ▼
Read sector 0 of boot device ──► memory at 0x7C00
   │
   ▼
Bytes 510–511 == 0xAA55 ? ──no──► try next device
   │ yes
   ▼
JMP 0x0000:0x7C00  ← our bootloader starts running here
```

---

## 4. BIOS Interrupts: `int 0x10` with `AH=0x0E`

In real mode, the BIOS exposes its services through **software interrupts**.
The `int` instruction makes the CPU look up a handler in the interrupt vector
table and call it — like calling a function built into the machine.

- **`int 0x10`** is the **video services** interrupt. Which service you get is
  selected by the value in the `AH` register (the high byte of AX).
- **`AH = 0x0E`** selects **teletype output**: "print the character in `AL`
  to the screen at the cursor position, then advance the cursor." It behaves
  like an old teletype terminal — characters appear one after another, and
  the screen scrolls when full.

Register contract for teletype output:

| Register | Value          | Meaning                          |
|----------|----------------|----------------------------------|
| `AH`     | `0x0E`         | function number: teletype output |
| `AL`     | character      | the ASCII character to print     |

So printing `H` is three instructions:

```asm
mov ah, 0x0E    ; select function 0x0E (teletype)
mov al, 'H'     ; character to print
int 0x10        ; ask the BIOS to do it
```

Setting `AH` once is enough — it stays `0x0E` until we change it — so printing
a second character only needs a new `AL` and another `int 0x10`. This is how
our bootloader prints `Hi` without any operating system, drivers, or
libraries: the BIOS does all the VGA work for us.

---

## 5. `boot.asm`, Line by Line

File: `phases/01-bootloader/boot.asm`

```asm
bits 16
```
Tells NASM to assemble for a **16-bit** CPU. The processor starts in real
mode, so instructions must be encoded the 16-bit way (e.g. `mov ah, 0x0E`
uses 8/16-bit registers, not 32-bit ones).

```asm
org 0x7C00
```
**Origin directive.** Tells NASM "assume this code will live at address
`0x7C00` when it runs." All label addresses are computed relative to this
origin. It does *not* move the code anywhere — the BIOS does that — it just
makes the assembler's address math match reality.

```asm
start:
```
A label marking the entry point. Since the BIOS jumps to the first byte of
the sector, execution begins right here.

```asm
    mov ah, 0x0E
```
Load `AH` with `0x0E` — select the BIOS **teletype output** function for the
upcoming `int 0x10`.

```asm
    mov al, 'H'
```
Load `AL` with the ASCII code for the character `H` (0x48). NASM accepts
character literals in single quotes.

```asm
    int 0x10
```
Trigger BIOS video service interrupt `0x10`. With `AH=0x0E` and `AL='H'`,
the BIOS prints `H` at the cursor and advances it.

```asm
    mov al, 'i'
    int 0x10
```
Print `i` the same way. `AH` still holds `0x0E`, so we only reload `AL`.
The screen now shows `Hi`.

```asm
.halt:
    hlt
    jmp .halt
```
- `hlt` stops the CPU until the next hardware interrupt — it sits idle
  instead of burning cycles.
- `.halt` is a **local label** (belongs to `start:`), and `jmp .halt` jumps
  back to it. Together they form an infinite loop: if an interrupt ever wakes
  the CPU from `hlt`, it immediately halts again. Without this, execution
  would fall off the end of our code into the zero padding and the CPU would
  wander through memory executing garbage.

```asm
times 510 - ($ - $$) db 0
```
Zero-padding to fill the sector. NASM's special symbols:
- `$$` = address of the start of the file (here, `0x7C00` because of `org`).
- `$` = current assembly address.
- `$ - $$` = how many bytes we've emitted so far.
- `times N db 0` repeats `db 0` (define one zero byte) N times.

So this emits zeros until the file is exactly **510 bytes** long — leaving
room for the 2-byte signature to land at offsets 510–511.

```asm
dw 0xAA55
```
Define one 16-bit word: the **boot signature**. x86 is little-endian, so this
word is stored as byte `0x55` at offset 510 and byte `0xAA` at offset 511 —
exactly what the BIOS checks for. Without these two bytes, the BIOS would
reject our sector and refuse to boot it.

The result: a file of exactly **512 bytes** — one complete boot sector.

---

## 6. Build & Run

### Assemble

```bash
nasm -f bin boot.asm -o boot.img
```

- `nasm` — the Netwide Assembler.
- `-f bin` — output a **flat binary**: raw machine code with no headers,
  metadata, or relocation info. Exactly the bytes the CPU will execute, which
  is what a boot sector must be.
- `boot.asm` — the source file.
- `-o boot.img` — write the result to `boot.img`, our bootable disk image.

### Run in QEMU

```bash
qemu-system-i386 -fda boot.img
```

- `qemu-system-i386` — emulate a 32-bit x86 PC.
- `-fda boot.img` — attach `boot.img` as the **floppy disk A:**. QEMU's BIOS
  will find its `0xAA55` signature, load it at `0x7C00`, and jump to it —
  exactly like real hardware.

Expected result: a QEMU window showing `Hi` in the top-left corner, with the
CPU halted in our infinite loop. Close the window (or press `Ctrl+Alt+Q` /
kill the process) to exit.

---

## Recap

- Hex is the native language of low-level work; `0x7C00` = 31744 =
  `0111 1100 0000 0000`.
- We boot in **real mode** (16-bit, 1 MiB, physical addresses, BIOS services);
  **protected mode** (32-bit, paging, protection) comes later.
- Boot flow: power-on → BIOS POST → sector 0 loaded at `0x7C00` → `0xAA55`
  signature check → jump to `0x7C00`.
- `int 0x10` with `AH=0x0E` prints one character from `AL` — our only "screen
  driver" for now.
- `boot.asm` prints `Hi`, halts in a loop, pads to 510 bytes, and ends with
  the `0xAA55` signature — exactly 512 bytes.
- Build with `nasm -f bin`, test with `qemu-system-i386 -fda boot.img`.
