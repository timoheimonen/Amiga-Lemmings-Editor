; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The parts of the WHDLoad slave interface the slaves use, as described in the
; WHDLoad autodoc: slave flags, termination reasons, the offsets of the
; resload functions from the resload base passed to the slave in A0, and the
; tags of resload_Relocate.

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
resload_Relocate        equ $50
resload_DeleteFile      equ $58

WHDLTAG_CHIPPTR         equ $88100000   ; resload_Relocate: chip hunks go here
WHDLTAG_ALIGN           equ $88100002   ; hunk lengths rounded up to this
WHDLTAG_LOADSEG         equ $88100003   ; build a segment list like LoadSeg
