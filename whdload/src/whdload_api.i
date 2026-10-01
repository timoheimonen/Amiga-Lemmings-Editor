; Lemmings In-Game Level Editor V2.1.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The parts of the WHDLoad slave interface this slave uses, as described in the
; WHDLoad autodoc: slave flags, termination reasons and the offsets of the
; resload functions from the resload base passed to the slave in A0.

WHDLF_NoError           equ 1<<1        ; resload errors quit with a requester
WHDLF_EmulTrap          equ 1<<2        ; forward TRAP #n to the program's vectors
WHDLF_ClearMem          equ 1<<12       ; clear BaseMem and ExpMem instead of filling

TDREASON_OK             equ -1
TDREASON_WRONGVER       equ 9

resload_Abort           equ $04
resload_LoadFile        equ $08
resload_SaveFile        equ $0c
resload_ListFiles       equ $14
resload_FlushCache      equ $20
resload_GetFileSize     equ $24
resload_DiskLoad        equ $28
resload_SaveFileOffset  equ $38
resload_LoadFileOffset  equ $4c
