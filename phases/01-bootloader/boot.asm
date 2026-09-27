; ============================================================================
; boot.asm - Minimal 16-bit x86 bootloader (Phase 1)
;
; The BIOS loads this 512-byte sector to physical address 0x7C00 in real
; mode, checks the 0xAA55 signature, then jumps to our first byte.
; See docs/01-bootloader-concepts.md for the full explanation.
; ============================================================================

bits 16                 ; CPU starts in 16-bit real mode
org 0x7C00              ; BIOS loads us at 0x7C00: labels are relative to it

start:
    ; Print 'H' using BIOS teletype output (int 0x10, AH=0x0E)
    mov ah, 0x0E        ; AH = function 0x0E: teletype output
    mov al, 'H'         ; AL = character to print
    int 0x10            ; BIOS video interrupt: prints AL, advances cursor

    ; Print 'i' (AH is still 0x0E, so only AL needs reloading)
    mov al, 'i'
    int 0x10

.halt:                  ; Stop forever: halt until an interrupt, then halt again
    hlt
    jmp .halt

; Pad with zeros up to byte 510, then the 2-byte boot signature.
; $ = current address, $$ = start of file, so ($ - $$) = bytes emitted so far.
times 510 - ($ - $$) db 0
dw 0xAA55               ; Boot signature at bytes 510-511 (stored as 55 AA)
