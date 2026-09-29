; Lemmings In-Game Level Editor V1.0
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Bootstrap appended to the game's main program. It runs only during start-up,
; before the game uses this memory for anything else.
;
; "reserve" is reached from the game's file cache setup ($3916): it keeps the
; top 128 KiB of slow RAM for the editor. "load_editor" is reached from the
; start-up code ($548): it loads the Editor file from disk 2 into that block
; and runs its installer. Without enough slow RAM the editor is skipped and the
; game runs unchanged.
        org $21b4c
reserve:
        adda.l 8.w,a1
        cmpi.l #$24000,8.w
        blo.s unavailable
        suba.l #$20000,a1
unavailable:
        move.l a1,$f8(a5)
        jmp $391e
load_editor:
        jsr $3d48                 ; displaced metadata load
        cmpi.l #$24000,8.w
        blo.s menu
        lea filename(pc),a0
        movea.l $f8(a5),a1
        moveq #0,d1
        jsr $3286
        movea.l $f8(a5),a0
        jsr (a0)
menu:
        jsr $2c7e
        jmp $550
filename:
        dc.b 'Editor',0
        even
