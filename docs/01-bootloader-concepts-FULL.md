# Phase 1 — Bootloader Concepts (FULL Edition)

> **What is this document?**
> A complete, self-contained explanation of *every* concept behind our first
> bootloader (`phases/01-bootloader/boot.asm`). It assumes no prior OS or
> assembly knowledge. Read it top to bottom — each section builds on the
> previous one. When you finish, you should be able to answer, in full detail:
>
> **"What happens from power-on to the execution of our first byte of code?"**

---

## Table of Contents

1. [Hex Addresses and Why They Matter](#1-hex-addresses-and-why-they-matter)
2. [CPU Real Mode vs Protected Mode](#2-cpu-real-mode-vs-protected-mode)
3. [The Boot Sequence: Power-On to Our Code](#3-the-boot-sequence-power-on-to-our-code)
4. [NASM Assembly Fundamentals for This Bootloader](#4-nasm-assembly-fundamentals-for-this-bootloader)
5. [BIOS Interrupts and `int 0x10`](#5-bios-interrupts-and-int-0x10)
6. [The Boot Sector Layout and Padding](#6-the-boot-sector-layout-and-padding)
7. [The Infinite Halt Loop](#7-the-infinite-halt-loop)
8. [Building and Testing](#8-building-and-testing)
9. [Conceptual Summary Checklist (Quiz)](#9-conceptual-summary-checklist-quiz)
- [Appendix A: Quiz Answers](#appendix-a-quiz-answers)
- [Appendix B: Glossary](#appendix-b-glossary)

---

## 1. Hex Addresses and Why They Matter

### 1.1 What hexadecimal is

Humans count in **base 10** (decimal): ten digits, `0`–`9`. When we run out of
digits we carry: `9` → `10`.

Computers think in **base 2** (binary): two digits, `0` and `1`. One binary
digit is one **bit**.

**Hexadecimal ("hex") is base 16**: sixteen digits. We reuse `0`–`9`, then
borrow six letters:

| Hex | Decimal | Hex | Decimal |
|-----|---------|-----|---------|
| `0` | 0       | `8` | 8       |
| `1` | 1       | `9` | 9       |
| `2` | 2       | `A` | 10      |
| `3` | 3       | `B` | 11      |
| `4` | 4       | `C` | 12      |
| `5` | 5       | `D` | 13      |
| `6` | 6       | `E` | 14      |
| `7` | 7       | `F` | 15      |

Counting in hex goes: `0, 1, 2, … 9, A, B, C, D, E, F, 10, 11, …` — where hex
`10` means sixteen, hex `100` means 256, and hex `1000` means 4096.

By convention, hex numbers are written with a **`0x` prefix** so nobody
confuses them with decimal: `0x10` is sixteen, not ten. (NASM also accepts the
`10h` suffix style, but we'll use `0x` everywhere.)

### 1.2 The killer feature: 1 hex digit = exactly 4 bits

Base 16 is 2⁴. That means **every hex digit is exactly four binary bits** (a
"nibble"), with a clean one-to-one mapping:

```
hex:  0     1     2     3     4     5     6     7
bin: 0000  0001  0010  0011  0100  0101  0110  0111

hex:  8     9     A     B     C     D     E     F
bin: 1000  1001  1010  1011  1100  1101  1110  1111
```

Consequences that make hex indispensable:

- **2 hex digits = 1 byte (8 bits).** `0x55` = `0101 0101`. `0xAA` =
  `1010 1010`. You can see the bits *through* the hex.
- **4 hex digits = 16 bits** — exactly one 16-bit value, the natural size in
  Real Mode.

### 1.3 Why OS/microcontroller developers use hex instead of decimal

1. **Compactness.** The address `0x7C00` is 4 characters. In binary it's
   `0111110000000000` — 16 characters you *will* eventually mis-type.
2. **Aligned to bytes.** Because 2 digits = 1 byte, hex lines up perfectly
   with how memory is organized. A hexdump of memory reads naturally in hex;
   in decimal it would be noise.
3. **Matches the hardware.** CPU manuals, datasheets, and memory maps all
   speak hex. Register values, port numbers, and interrupt numbers (`int
   0x10`) are documented in hex.
4. **Exposes bit patterns and alignment.** Round-looking hex numbers are round
   in binary too. `0x7C00` ends in two zeros → it's a multiple of `0x100`
   (256) → it sits on a clean 256-byte boundary. Decimal `31744` hides all of
   that. Flags and bitmasks (e.g. `0x0E` = `0000 1110`) are also *visible* in
   hex and invisible in decimal.

> **Rule of thumb:** when you see `0x…`, read it as "a raw bit pattern the
> machine cares about," not as a quantity of things.

### 1.4 Worked example: `0x7C00` three ways

`0x7C00` is the physical memory address where the BIOS loads our bootloader.
The same value in all three bases:

**Hex → decimal** (each digit's place value is a power of 16):

```
0x7C00 = 7×16³ + 12×16² + 0×16¹ + 0×16⁰
       = 7×4096 + 12×256 + 0 + 0
       = 28672 + 3072
       = 31744
```

**Hex → binary** (just substitute each digit with its 4-bit pattern — no
arithmetic needed):

```
hex:    7      C      0      0
bin:  0111   1100   0000   0000
```

So:

| Base    | Value                |
|---------|----------------------|
| Hex     | `0x7C00`             |
| Decimal | `31744`              |
| Binary  | `0111 1100 0000 0000`|

### 1.5 Little-endian byte order

A **byte order** question appears whenever a value is bigger than one byte:
which byte goes into memory *first* (at the lower address)?

x86 CPUs are **little-endian**: the **least significant byte** (the "little
end") is stored at the **lowest address**, and higher bytes follow at higher
addresses.

Take the 16-bit word `0xAA55`:

- High byte: `0xAA`
- Low byte: `0x55`

Stored little-endian, the low byte comes first:

```
address 510:  0x55     ← low byte first
address 511:  0xAA     ← high byte second
```

This is exactly why the boot signature behaves the way it does. The BIOS
requires byte 510 = `0x55` and byte 511 = `0xAA`. When we write the NASM line
`dw 0xAA55` ("define word"), the assembler emits the word in little-endian
order — so the bytes on disk are `55` **then** `AA`. The source looks
"backwards" compared to the bytes, but both describe the same word.

```
dw 0xAA55   ──assembles to──►   ... 55 AA      (in the file, and in RAM)
```

(The opposite convention, most-significant-byte-first, is called
**big-endian** and is used by e.g. network protocols. Not x86.)

---

## 2. CPU Real Mode vs Protected Mode

### 2.1 What "mode" means for a CPU

A CPU **mode** is a complete set of rules the processor operates under:

- how wide the registers and instructions are (16-bit? 32-bit? 64-bit?),
- how memory addresses are computed,
- whether memory protection and privilege levels exist,
- which features are available.

The same physical chip can run in several modes. An x86 PC **always powers on
in Real Mode** — for backwards compatibility with the 1981 IBM PC — and an
operating system may later *switch* it into Protected Mode (and then Long
Mode). Mode is not a label; it changes how the silicon interprets every
instruction and every address.

### 2.2 Real Mode — where every PC starts

Real Mode is the 16-bit mode of the original Intel 8086, kept alive in every
x86 CPU since:

- **16-bit.** General-purpose registers are 16 bits wide: `AX`, `BX`, `CX`,
  `DX`, `SI`, `DI`, `BP`, `SP`. Each of `AX`–`DX` splits into a high and low
  byte (`AH`/`AL`, `BH`/`BL`, …).
- **20-bit address bus → 1 MiB of addressable memory.** 2²⁰ = 1,048,576
  bytes, addresses `0x00000`–`0xFFFFF`. Note the bus can express 20 bits even
  though registers are only 16 bits wide — that's why the segment trick below
  exists.
- **Segment:offset addressing.** A 16-bit register alone can only count to
  65,535 (`0xFFFF`), far short of 1 MiB. So every memory access combines two
  16-bit values:

  ```
  physical address = (segment × 16) + offset
  ```

  Example: `CS:IP = 0x0000:0x7C00` → `0x0000×16 + 0x7C00` = `0x07C00`.
  (Segments overlap: `0x07C0:0x0000` is the *same* physical address
  `0x07C00`. Many segment:offset pairs can name one location.)
- **No protection.** Any running code can read or write any byte of RAM, any
  hardware port, even the BIOS's own memory. No isolation, no supervisor
  boundary — one wild pointer can take down the whole machine.
- **BIOS interrupts are available.** The BIOS pre-loads a library of routines
  (print to screen, read disk, read keyboard, …) that you call with the `int`
  instruction. This is a huge freebie for a bootloader.
- **It is the power-on state.** After reset, every x86 CPU is in Real Mode.
  Our bootloader's first instruction executes in Real Mode whether we like it
  or not.

### 2.3 Protected Mode — where modern OSes live

Protected Mode (introduced with the 80286, made useful by the 80386) is the
32-bit mode modern 32-bit OSes run in:

- **32-bit.** Registers widen to `EAX`, `EBX`, …; a **32-bit address bus**
  addresses 2³² = 4 GiB of memory.
- **Flat memory model.** Programs can use a single 32-bit address directly —
  no segment arithmetic in the common case.
- **Paging / virtual memory.** The OS builds page tables so each program gets
  its own private virtual address space, translated to physical RAM by the
  CPU on every access.
- **Privilege levels (rings 0–3).** The kernel runs in ring 0 (full power);
  applications run in ring 3 (restricted). The CPU itself blocks a ring-3
  program from touching kernel memory or hardware.
- **No BIOS interrupts.** The BIOS's interrupt handlers are 16-bit Real Mode
  code. Once the CPU switches to Protected Mode, `int 0x10` and friends are
  off the table — the OS must drive the hardware itself.

(64-bit **Long Mode** is a further step, entered *from* Protected Mode.)

### 2.4 Why our bootloader must be 16-bit (for now)

1. **The CPU starts in Real Mode.** That's the hardware reset state; our
   first instruction is a 16-bit instruction whether we planned it or not.
2. **The BIOS only works in Real Mode.** Printing via `int 0x10` — our entire
   Phase-1 program — is a BIOS service. We get it for free precisely because
   we're still in Real Mode.
3. **Switching is a deliberate, multi-step process** (build a Global
   Descriptor Table, disable interrupts, set the PE bit in `CR0`, perform a
   far jump to flush the pipeline, reload segment registers, set up a 32-bit
   stack). That is a *later phase*. Phase 1 stays in Real Mode and squeezes
   the BIOS for everything it offers.

---

## 3. The Boot Sequence: Power-On to Our Code

Here is the exact chain of events between pressing the power button and the
CPU executing the first byte of `boot.asm`.

### Step 1 — Power applied, CPU resets to a fixed state

The power supply stabilizes and releases the CPU's RESET pin. The CPU
responds by loading a **hardwired reset state** into its registers — in
particular the instruction pointer and code segment:

```
CS = 0xF000
IP = 0xFFF0
```

The very first instruction fetch uses the segment:offset formula from
Section 2:

```
physical address = (0xF000 × 16) + 0xFFF0
                 = 0xF0000 + 0xFFF0
                 = 0xFFFF0
```

`0xFFFF0` is **16 bytes below the top of the 1 MiB Real Mode address space**
(`0x100000 − 0x10 = 0xFFFF0`). This address is called the **reset vector**.
It doesn't point at RAM — the hardware maps it onto the **BIOS ROM chip**. In
those 16 bytes sits a jump instruction that leaps to the BIOS's real entry
point. The CPU has now begun executing BIOS code.

> **Fine print (for the curious, safe to skip):** the original 8086 expressed
> the same reset state as `CS=0xFFFF, IP=0x0000`, which also computes to
> `0xFFFF0`. Modern CPUs actually fetch their first instruction at
> `0xFFFFFFF0` (near 4 GiB) using a hidden segment base, and that ROM region
> is *aliased* down to `0xFFFF0` for the classic 1 MiB view. All three
> descriptions agree on the part that matters to us: **the CPU's first
> instruction comes from the BIOS ROM, 16 bytes below the top of the legacy
> 1 MiB map.**

### Step 2 — BIOS runs POST

The BIOS performs the **Power-On Self-Test (POST)**:

- initializes the chipset and basic hardware,
- checks RAM, keyboard, and other devices,
- detects connected storage,
- builds the **Interrupt Vector Table (IVT)** at physical addresses
  `0x00000`–`0x003FF` — 256 entries of 4 bytes each, each entry a
  `segment:offset` pointer to a BIOS handler routine (this is what makes
  `int 0x10` work later).

### Step 3 — BIOS picks a boot device

Following the configured **boot order** (classically: floppy first, then the
MBR of the first hard disk, then CD/USB), the BIOS probes each device for
something bootable.

### Step 4 — BIOS reads sector 0 into memory at `0x07C00`

From the first bootable device, the BIOS reads **sector 0 — the first 512
bytes** of the disk (this sector is called the **boot sector**, or **MBR**,
Master Boot Record) — and copies it, byte for byte, into physical RAM starting
at address **`0x07C00`**.

Why `0x07C00`? Pure historical convention from the original IBM PC. It's not
special electrically — it's simply the address every BIOS agreed to use, so
every bootloader can rely on it.

The 512 bytes occupy `0x07C00`–`0x07DFF` (`0x7C00 + 512 = 0x7E00`).

### Step 5 — BIOS checks the boot signature

The BIOS examines the **last two bytes** of the 512-byte sector:

```
byte 510 must be 0x55
byte 511 must be 0xAA
```

Read as a 16-bit little-endian word, those two bytes are the value `0xAA55` —
the **boot signature**. If the signature is missing, the BIOS declares the
device not bootable and tries the next one (or gives up with an error like
"No bootable device").

### Step 6 — BIOS far-jumps to our code

Signature valid. The BIOS loads:

```
CS = 0x0000
IP = 0x7C00
```

and performs a **far jump** (`JMP FAR`) to `CS:IP = 0x0000:0x7C00`, i.e.
physical address `0x07C00` — the first byte of the sector it just loaded. (It
also leaves the boot drive number in register `DL`, which will matter when we
load more sectors in later phases.)

### Step 7 — Our code is running

From this instant, the CPU is executing **our** bytes, starting at `0x7C00`,
in 16-bit Real Mode, with the BIOS interrupt library still available. The
full journey:

```
[Power on]
   → [CPU reset: first fetch at 0xFFFF0 → BIOS ROM]
   → [BIOS POST: init hardware, build IVT]
   → [BIOS picks boot device by boot order]
   → [BIOS reads sector 0 (512 bytes) → RAM at 0x07C00]
   → [BIOS checks bytes 510/511 = 0x55 0xAA]
   → [BIOS far-jumps to 0x0000:0x7C00]
   → OUR BOOTLOADER RUNS
```

### Memory map at the moment our code starts

```
Physical
address
0x00000  ┌───────────────────────────────┐
         │ Interrupt Vector Table (IVT)  │  256 × 4 bytes = 1 KiB
         │ (pointers to BIOS handlers)   │
0x00400  ├───────────────────────────────┤
         │ BIOS Data Area                │  BIOS keeps its variables here
0x00500  ├───────────────────────────────┤
         │                               │
         │      free conventional        │
         │           memory              │
         │                               │
0x07C00  ├───────────────────────────────┤ ◄── BIOS loads the MBR (sector 0,
         │   OUR BOOT SECTOR — 512 bytes │     512 bytes) here and jumps to
         │   bytes 0–509: code + padding │     the first byte (CS:IP =
         │   byte 510: 0x55              │     0x0000:0x7C00)
         │   byte 511: 0xAA              │
0x07E00  ├───────────────────────────────┤
         │                               │
         │      free conventional        │
         │      memory (up to ~0x7FFFF)  │
         │                               │
0x80000  ├───────────────────────────────┤
         │ Extended BIOS Data Area /     │
         │ video memory / ROMs           │
0xA0000  ├───────────────────────────────┤
         │ Video RAM (e.g. text at       │
         │ 0xB8000)                      │
0xC0000  ├───────────────────────────────┤
         │ Option ROMs, BIOS ROM         │
0xFFFF0  │  ← reset vector (CPU's first  │
         │    fetch) lives in BIOS ROM   │
0xFFFFF  └───────────────────────────────┘  top of the 1 MiB Real Mode map
```

Two takeaways:

- We get exactly **512 bytes**, and 2 of them are reserved for the signature,
  leaving **510 usable bytes**. Anything bigger must be loaded from disk by
  our own code (a later phase).
- The CPU is in **Real Mode**, so the BIOS interrupt library is available.
  Phase 1 spends that freebie on printing text.

---

## 4. NASM Assembly Fundamentals for This Bootloader

Our bootloader is written for **NASM** (the Netwide Assembler). An assembler
translates human-readable mnemonics (`mov`, `int`, `hlt`) into raw machine
bytes. NASM also understands **directives** — commands to the assembler
itself that emit no CPU instructions. Here is every directive and symbol our
bootloader uses.

### 4.1 `bits 16` — generate 16-bit code

```asm
bits 16
```

Tells NASM: "the CPU that runs this code will be in **16-bit mode** (Real
Mode) — encode every instruction accordingly."

This matters because the *same* bytes can decode differently in 16-bit vs
32-bit mode, and many instructions have different encodings per mode. If we
assembled for 32-bit and the 16-bit CPU tried to decode it, the bytes would
mean something else entirely. `bits 16` keeps the assembler's output in sync
with the CPU's reality at boot time.

It is a directive: it emits zero bytes into the output file.

### 4.2 `org 0x7C00` — declare where the code will live

```asm
org 0x7C00
```

**Org** = "origin." Recall from Section 3 that the BIOS loads our file at
physical address `0x7C00`. But NASM builds a flat binary whose first byte is,
from the file's point of view, offset 0. Those two facts collide the moment
the program references *any address in itself* — e.g. the address of a string
to print.

`org 0x7C00` tells NASM: "when you compute the address of any label, assume
the file's first byte sits at `0x7C00`." So a label 40 bytes into the file
gets the address `0x7C00 + 40 = 0x7C28`, which is exactly where it will be in
RAM at runtime. Without `org`, that same label would be computed as `0x0028`
— and the CPU would read garbage from the wrong place.

Our tiny Phase-1 program references no data labels, so you can't *feel* `org`
yet — but remove it in the next phase (when we print a string) and the
bootloader breaks. Set it now, always.

### 4.3 `$` and `$$` — here, and where here started

- **`$`** = the address of the **current output position** — the next byte to
  be written.
- **`$$`** = the address of the **start of the current section** — for our
  flat binary, the start of the file, which `org` has set to `0x7C00`.

Therefore:

```
$ - $$  =  (current position) − (start)  =  number of bytes emitted so far
```

This little expression is the key to the padding calculation in Section 6.

### 4.4 `times N db 0` — repeat a byte

```asm
times 498 db 0
```

- `db` = "define byte": emit one byte into the output.
- `times N <anything>` = repeat that line `N` times.

So `times 498 db 0` emits 498 zero bytes. We use it for **padding** — filling
the unused middle of the boot sector with zeros (Section 6). In our file the
repeat count isn't a literal number; it's the computed expression
`510 - ($ - $$)`.

### 4.5 `dw 0xAA55` — define a 16-bit word

```asm
dw 0xAA55
```

- `dw` = "define word": emit a 16-bit (2-byte) value into the output.
- Because x86 is **little-endian** (Section 1.5), the word `0xAA55` is stored
  low-byte-first: byte `0x55`, then byte `0xAA`.

That lands the boot signature exactly where the BIOS looks for it: byte 510 =
`0x55`, byte 511 = `0xAA`.

### 4.6 The program these directives frame

For reference, the complete file (`phases/01-bootloader/boot.asm`):

```asm
bits 16                 ; Real Mode: tell NASM to emit 16-bit code
org 0x7C00              ; BIOS loads us at 0x7C00 — base all addresses on that

start:
    mov ah, 0x0E        ; int 0x10 function 0x0E: teletype (TTY) output
                        ; (set once — AH keeps its value between calls)

    mov al, 'H'         ; AL = character to print
    int 0x10            ; BIOS call: print 'H' and advance the cursor

    mov al, 'i'         ; next character
    int 0x10            ; print 'i'  -> screen now shows "Hi"

.hang:                  ; park the CPU: never fall through into garbage memory
    hlt                 ; sleep until the next hardware interrupt (low power)
    jmp .hang           ; woke up (e.g. keypress)? go straight back to sleep

times 510 - ($ - $$) db 0   ; zero-pad up to byte 510
dw 0xAA55                   ; boot signature (little-endian -> bytes 55 AA)
```

---

## 5. BIOS Interrupts and `int 0x10`

### 5.1 What an interrupt is

An **interrupt** is a controlled detour: the CPU **pauses** what it's doing,
**saves** enough state to come back later, and **calls a pre-registered
handler routine**. When the handler finishes, it executes `iret` (interrupt
return), the saved state is restored, and the interrupted program resumes on
the next instruction as if nothing happened.

Interrupts come in two flavors:

- **Hardware interrupts** — raised by devices (keyboard pressed, timer tick,
  disk finished a read). These can arrive at any moment.
- **Software interrupts** — raised *deliberately* by a program with the `int`
  instruction. This is a call mechanism, and it's how we ask the BIOS for
  services.

When `int 0x10` executes, the CPU:

1. Pushes `FLAGS`, `CS`, and `IP` onto the stack (the saved state),
2. Looks up entry `0x10` in the **Interrupt Vector Table**,
3. Jumps to the handler address found there,
4. Runs the BIOS handler, which ends with `iret` — popping the saved state
   and returning to the instruction after our `int`.

### 5.2 The Interrupt Vector Table (IVT)

The IVT lives at physical addresses **`0x00000`–`0x003FF`** (the first 1 KiB
of RAM). It holds **256 entries** (interrupt numbers `0x00`–`0xFF`), each
**4 bytes**: a 2-byte offset, then a 2-byte segment — together the
`segment:offset` address of that interrupt's handler.

The BIOS fills in this table during POST (Section 3, Step 2), pointing its
entries at its own routines in ROM. So by the time our bootloader runs, the
"phone book" is already published; `int 0x10` is simply "call the handler
listed in slot `0x10`."

```
0x00000 ┌──────────────────────┐
        │ vector 0x00 → handler│  4 bytes: offset, segment
        │ vector 0x01 → handler│
        │        ...           │
        │ vector 0x10 → BIOS   │  ◄── int 0x10 looks here: video services
        │   video handler      │
        │        ...           │
        │ vector 0xFF → handler│
0x003FF └──────────────────────┘
```

### 5.3 `int 0x10` — video services, with `AH` as the function selector

Interrupt `0x10` is the BIOS **video services** interrupt. One interrupt
number offers many functions; you select which one by putting a **function
number in register `AH`**, and you pass arguments in other registers. It's an
API call, assembly-style:

```asm
mov ah, 0x0E    ; select function 0x0E of interrupt 0x10
mov al, 'H'     ; argument: the character to print
int 0x10        ; make the call
```

### 5.4 Function `AH=0x0E` — teletype (TTY) output

Function `0x0E` writes **one character** to the screen in teletype fashion.
The register contract:

| Register | Value | Meaning                                   |
|----------|-------|-------------------------------------------|
| `AH`     | `0x0E`| function number: teletype output          |
| `AL`     | char  | the ASCII character to write              |
| `BH`     | `0`   | video page number (page 0 is the default) |
| `BL`     | color | foreground color — **graphics modes only**; ignored in text mode |

Behavior:

- Writes the character in `AL` at the current cursor position.
- **Advances the cursor automatically** — like an old teletype/typewriter,
  which is where the name comes from.
- Honors control characters: `0x0D` (carriage return) and `0x0A` (line feed);
  a newline is normally the pair `"\r\n"`.
- Returns nothing.

### 5.5 Why we set `AH` only once

Look at the print sequence in `boot.asm`:

```asm
mov ah, 0x0E        ; AH = 0x0E ... set ONCE

mov al, 'H'
int 0x10            ; prints 'H'

mov al, 'i'         ; only AL changes
int 0x10            ; prints 'i'
```

The **function number stays the same** for every character we print — only
the *argument* (`AL`) changes. Registers keep their values until something
overwrites them, and the `AH=0x0E` teletype handler doesn't clobber `AH`. So
we load `AH` a single time before the first call and reuse it for every
subsequent call. Two bytes saved per character — a real economy when your
entire program must fit in 510 bytes.

> **Remember:** all of this works only in **Real Mode**. After we switch to
> Protected Mode in a later phase, the IVT's 16-bit BIOS handlers are
> unreachable, and we'll print by writing directly to video memory at
> `0xB8000` instead.

---

## 6. The Boot Sector Layout and Padding

### 6.1 Exactly 512 bytes — no more, no less

The BIOS reads **exactly one sector** from the boot device: 512 bytes. Not
"up to" 512 — exactly. Our entire Phase-1 world must fit inside:

```
[ our code ][ zero padding ][ signature ]
            └──────── 512 bytes total ────────┘
```

- Our code today is tiny: **12 bytes** of machine code.
- The signature must occupy the **final two bytes** (510 and 511).
- Everything in between must be filled — a file shorter than 512 bytes would
  put the signature at the wrong offset, and the BIOS would never find it.

### 6.2 The padding formula

```asm
times 510 - ($ - $$) db 0
```

Decode it piece by piece (Section 4.3–4.4):

- `$$` = start of the file (`0x7C00`, thanks to `org`),
- `$` = current output position,
- `$ - $$` = **bytes emitted so far** — the size of our code,
- `510 - ($ - $$)` = **how many zero bytes are needed** so that code + zeros
  together reach byte 510,
- `times N db 0` = emit `N` zero bytes.

Plugging in our real numbers — the code assembles to 12 bytes:

```
510 - 12 = 498 zero bytes of padding
```

So the line reads: *"whatever size the code is, pad with zeros until we're
standing at byte 510."* The formula automatically absorbs future edits: add
an instruction, get one fewer padding byte. And if the code ever grows past
510 bytes, `times` gets a negative count and **NASM fails at build time** — a
free safety check that we can never produce an oversized boot sector.

### 6.3 The final layout, byte by byte

Here's the actual `boot.img` (verified with `xxd`):

```
offset    bytes                         meaning
──────────────────────────────────────────────────────────────
0x000     B4 0E                         mov ah, 0x0E
0x002     B0 48                         mov al, 'H'
0x004     CD 10                         int 0x10
0x006     B0 69                         mov al, 'i'
0x008     CD 10                         int 0x10
0x00A     F4                            hlt
0x00B     EB FD                         jmp .hang   (jump back 3 bytes)
0x00D     00 00 00 ... 00               498 bytes of zero padding
0x1FE     55                            byte 510: signature low byte
0x1FF     AA                            byte 511: signature high byte
──────────────────────────────────────────────────────────────
total: 0x200 = 512 bytes exactly
```

(`0x1FE` = 510 and `0x1FF` = 511 — another place hex makes offsets obvious.)

Graphically:

```
sector offset
0x000  ┌──────────────────────────┐
       │  our code (12 bytes)     │  ← CPU starts executing here (0x7C00)
0x00D  ├──────────────────────────┤
       │                          │
       │  zero padding (498 B)    │  ← times 510 - ($ - $$) db 0
       │                          │
0x1FE  │  0x55                    │  ← ┐
0x1FF  │  0xAA                    │  ← ┴─ dw 0xAA55 (little-endian)
       └──────────────────────────┘
       total: exactly 512 bytes
```

### 6.4 What the BIOS checks

After loading the sector to `0x7C00`, the BIOS compares:

- byte at offset 510 == `0x55`?
- byte at offset 511 == `0xAA`?

Both yes → bootable → far jump to `0x0000:0x7C00`. This is why `dw 0xAA55`
and not `dw 0x55AA`: little-endian storage flips the written word into the
byte order the BIOS demands (Section 1.5).

---

## 7. The Infinite Halt Loop

After printing "Hi", our program has nothing left to do. But the CPU doesn't
know that — a CPU **never stops on its own**; it just keeps fetching and
executing whatever the next bytes in memory happen to be. Past our 12 bytes
lie 498 zeros, then the signature, then… whatever was already in RAM. Zeros
decode as instructions too (`00 00` is `add [bx+si], al`), so "running off
the end" means executing unintended instructions on uninitialized memory —
**undefined behavior**: corrupted memory, a hung machine, or a triple fault
and reboot.

The fix is to park the CPU deliberately:

```asm
.hang:
    hlt
    jmp .hang
```

### `hlt` — the power-management halt

`hlt` (halt) stops the CPU's instruction execution **until the next hardware
interrupt arrives** (a keypress, a timer tick, …). While halted, the CPU
executes nothing and draws very little power — it's a power-management
instruction, not a busy-wait. A naive `jmp $` spin loop would also "stop"
the program, but it would burn 100% of a CPU core forever; `hlt` naps.

### `jmp .hang` — back to sleep

A halted CPU isn't dead: the next hardware interrupt **wakes it**, and after
the interrupt handler returns, execution resumes at the instruction *after*
`hlt`. If that were the end of our code, we'd be falling into garbage again.
So the very next instruction is `jmp .hang`, which jumps right back to the
`hlt`. Together they form an infinite loop:

```
wake up (keypress/timer) → next instruction → jmp .hang → hlt → sleep → …
```

The CPU is parked forever, politely, at nearly zero power. (The label name is
arbitrary — `.hang`, `.halt`, `.loop` all work; the leading dot just makes it
a NASM **local label** under `start:`.)

**Without this loop**, the CPU would march past our 512-byte sector into
uninitialized memory and execute random bytes as code — undefined behavior,
and in an emulator usually an instant reset. With it, the machine sits
stable with "Hi" on screen until you close it.

---

## 8. Building and Testing

### 8.1 Assemble with NASM

```bash
cd phases/01-bootloader
nasm -f bin boot.asm -o boot.img
```

- `nasm` — the assembler.
- `-f bin` — output format: **flat binary**. Raw machine-code bytes, no ELF
  headers, no sections, no metadata. The first byte of `boot.img` is
  literally the first instruction the CPU executes. A boot sector *must* be
  this raw — the BIOS understands no file format.
- `boot.asm` — input source.
- `-o boot.img` — output file name.

### 8.2 Verify the image

Two things must be true before QEMU even starts:

```bash
ls -l boot.img          # size must be EXACTLY 512 bytes
xxd boot.img | tail -2  # the final two bytes must be: 55 aa
```

Expected output:

```
-rw-rw-r-- 1 ubuntu ubuntu 512 ... boot.img
000001f0: 0000 0000 0000 0000 0000 0000 0000 55aa
```

- **512 bytes** — because the BIOS loads exactly one sector, and our padding
  formula guarantees the size (Section 6).
- **`55 aa` at the end** — the little-endian boot signature the BIOS checks
  (Sections 1.5 and 6.4).

### 8.3 Run in QEMU

QEMU emulates a complete PC — including a real BIOS that performs the exact
boot sequence of Section 3. Zero risk to your actual machine.

```bash
qemu-system-i386 -fda boot.img
```

- `qemu-system-i386` — emulate a 32-bit x86 PC.
- `-fda boot.img` — attach `boot.img` as the **floppy disk A:**. Floppy is
  convenient: QEMU boots it directly, no partition table needed.

This also works:

```bash
qemu-system-x86_64 -fda boot.img
```

An x86-64 machine still **powers on in Real Mode** (Section 2.2) and runs
16-bit code fine — the "64-bit" part only appears after an OS switches modes,
which we never do in Phase 1. Either emulator binary is correct.

Headless variant (no GUI window, BIOS screen rendered in the terminal):

```bash
qemu-system-i386 -fda boot.img -display curses
```

### 8.4 Expected result

A window (or terminal) opens, the emulated BIOS runs its POST, loads our
sector, checks the signature, jumps to `0x7C00` — and the screen shows:

```
Hi
```

…followed by a peacefully halted CPU. That two-letter word traveled the whole
path: power-on → reset vector → BIOS POST → sector read → signature check →
far jump → your `int 0x10` calls. 🎉

### 8.5 Installing the tools (if missing)

```bash
sudo apt update
sudo apt install nasm qemu-system-x86
```

---

## 9. Conceptual Summary Checklist (Quiz)

Five questions. Answer each **before** peeking — answers are in
[Appendix A](#appendix-a-quiz-answers), not inline.

### Q1 — Hex and binary

The address `0x7C00` is where the BIOS loads the boot sector. Which
statement is **true**?

- A) `0x7C00` = decimal 31,744 and binary `0111 1100 0000 0000`
- B) `0x7C00` = decimal 7,200 and binary `0111 0010 0000 0000`
- C) `0x7C00` = decimal 31,744 and binary `1110 0011 1111 1111`
- D) `0x7C00` = decimal 40,960 and binary `1010 0000 0000 0000`

### Q2 — The boot signature

Why does the source line `dw 0xAA55` produce the on-disk bytes `55 AA`?

- A) NASM always reverses the bytes of every `dw` value
- B) x86 is little-endian: the low byte (`0x55`) is stored at the lower
  address, the high byte (`0xAA`) at the higher one
- C) The BIOS flips the bytes when loading the sector
- D) `0xAA55` and `0x55AA` are the same number in hexadecimal

### Q3 — The boot sequence

Immediately after the BIOS verifies the boot signature, it:

- A) Switches the CPU to Protected Mode, then jumps to `0x7C00`
- B) Copies the sector from `0x7C00` to `0xFFFF0` and jumps there
- C) Sets `CS=0x0000`, `IP=0x7C00` and far-jumps to `0x0000:0x7C00`, still
  in Real Mode
- D) Reads the *second* sector of the disk into memory

### Q4 — NASM directives

In `times 510 - ($ - $$) db 0`, the expression `$ - $$` means:

- A) The size of the boot signature in bytes
- B) The number of bytes emitted so far (current position minus start of
  file) — i.e. the size of our code
- C) The physical address where the BIOS will jump
- D) The number of padding bytes to emit

### Q5 — The halt loop

Why does the bootloader end with `hlt` inside a `jmp` loop instead of just
letting execution run past the last instruction?

- A) `hlt` is required by the BIOS before it will print anything
- B) The loop keeps the cursor blinking
- C) Without it, the CPU would keep executing whatever bytes follow in
  memory (padding, signature, uninitialized RAM) as if they were
  instructions — undefined behavior
- D) `jmp .hang` reloads the boot sector from disk

---

## Appendix A: Quiz Answers

**Q1 — A.**
`0x7C00 = 7×4096 + 12×256 = 28672 + 3072 = 31744`. And nibble-by-nibble:
`7`=`0111`, `C`=`1100`, `0`=`0000`, `0`=`0000` → `0111 1100 0000 0000`.
(Section 1.4.)

**Q2 — B.**
x86 is little-endian: multi-byte values are stored least-significant-byte
first. The word `0xAA55` has low byte `0x55` and high byte `0xAA`, so the
bytes land as `55` then `AA` — exactly the byte order the BIOS checks at
offsets 510/511. (Sections 1.5, 6.4.)

**Q3 — C.**
With the signature verified, the BIOS sets `CS=0x0000`, `IP=0x7C00` and
performs a far jump to physical address `0x07C00`. The CPU is still in Real
Mode — nothing has switched it. (Section 3, Step 6.)

**Q4 — B.**
`$` is the current output position and `$$` is the start of the file, so
`$ - $$` is the number of bytes emitted so far — the code size. `510` minus
that is the padding count (answer D describes the *result* of the whole
expression, not `$ - $$` itself). (Sections 4.3, 6.2.)

**Q5 — C.**
A CPU never stops on its own; it executes whatever bytes come next. Past our
code lie zeros (which decode as instructions), the signature, and
uninitialized RAM — executing them is undefined behavior. `hlt` parks the CPU
until a hardware interrupt, and `jmp .hang` sends it back to sleep if it ever
wakes. (Section 7.)

---

## Appendix B: Glossary

- **Address** — the number of a byte-sized "box" in memory. `0x7C00` is box
  number 31,744.
- **BIOS** — firmware built into the PC; runs first at power-on, performs
  POST, loads the boot sector, and offers interrupt-based services.
- **Boot sector / MBR** — the first 512-byte sector of a disk; bootable only
  if it ends with the bytes `0x55 0xAA`.
- **Boot signature** — the word `0xAA55` stored little-endian at bytes
  510–511; the BIOS's proof that a sector is bootable.
- **`0x7C00`** — the physical RAM address where every BIOS loads the boot
  sector. Pure convention, universal agreement.
- **Real Mode** — the 16-bit CPU mode active at power-on: 1 MiB addressable,
  segment:offset addressing, no protection, BIOS available.
- **Protected Mode** — 32-bit CPU mode: 4 GiB addressable, flat memory,
  paging, privilege rings, no BIOS.
- **Segment:offset** — Real Mode addressing scheme: physical address =
  `segment × 16 + offset`.
- **Reset vector** — `0xFFFF0`, the hardwired address of the CPU's first
  instruction fetch after reset; maps to BIOS ROM.
- **POST** — Power-On Self-Test; the BIOS's hardware initialization and
  check routine.
- **IVT** — Interrupt Vector Table at `0x00000`–`0x003FF`; 256 four-byte
  pointers to interrupt handlers.
- **Interrupt** — a controlled detour: CPU saves state, calls a registered
  handler, then resumes. Software interrupts (`int`) are deliberate calls.
- **`int 0x10` / `AH=0x0E`** — BIOS video interrupt, teletype function:
  prints the character in `AL` and advances the cursor.
- **Little-endian** — x86 byte order: least significant byte at the lowest
  address. Hence `dw 0xAA55` → bytes `55 AA`.
- **`bits 16`** — NASM directive: emit 16-bit (Real Mode) encodings.
- **`org 0x7C00`** — NASM directive: compute all label addresses as if the
  file's first byte lives at `0x7C00`.
- **`$` / `$$`** — NASM symbols: current output position / start of section.
  `$ - $$` = bytes emitted so far.
- **`times N db 0`** — NASM: emit `N` zero bytes (padding).
- **`dw`** — NASM: "define word," emit a 16-bit value (little-endian).
- **`hlt`** — x86 instruction: halt the CPU until the next hardware
  interrupt (low power).
- **Flat binary** — raw machine code with no file-format wrapper; what
  `nasm -f bin` produces and what a boot sector must be.
- **QEMU** — a PC emulator; runs our `boot.img` through a real BIOS boot
  sequence safely.

---

*End of document. Next phase: loading more sectors from disk and printing
strings — where `org 0x7C00` and register `DL` start earning their keep.*
