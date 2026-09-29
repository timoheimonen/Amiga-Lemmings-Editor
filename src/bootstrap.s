; Lemmings In-Game Level Editor V1.2.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Bootstrap appended to the game's main program. It runs only during start-up,
; before the game uses this memory for anything else.
;
; The editor image is stored in two packed files: Editor on disk 2 and Editor2
; (the tail of the image, from editor2_start) on disk 1.
;
; "reserve" is reached from the game's file cache setup ($3916): it keeps the
; top 128 KiB of slow RAM for the editor.
; "load_editor2" replaces the game's check for disk 2 ($50A). Disk 1 is still
; in a drive at this point, also on a single-drive machine. It finds disk 1
; with the game's own drive search and loader, unpacks Editor2 into the block,
; and then runs the original check, which asks for disk 2 if necessary.
; "load_editor" is reached from the start-up code ($548): it loads Editor from
; disk 2, unpacks it in front of Editor2 and runs the installer.
; Without enough slow RAM, or if Editor2 could not be loaded, the editor is
; skipped and the game runs unchanged.
;
; EDITOR2_OFFSET (the offset of editor2_start in the image) is defined by
; patch.py on the assembler command line.
PACKED_OFFSET   equ $7000            ; staging area above code and state
DIR_BUFFER      equ $1e7a2            ; the game's directory and raw disk
RAW_BUFFER      equ $58800            ; buffers, both unused during start-up

        org $21b4c
reserve:
        adda.l 8.w,a1
        cmpi.l #$24000,8.w
        blo.s unavailable
        suba.l #$20000,a1
unavailable:
        move.l a1,$f8(a5)
        jmp $391e

load_editor2:
        movem.l d0-d7/a0-a4,-(sp)
        lea loaded(pc),a0
        tst.b (a0)
        bne.s loaded2             ; start-up runs once; never reload
        cmpi.l #$24000,8.w
        blo.s loaded2
        lea DIR_BUFFER,a0
        lea RAW_BUFFER,a1
        moveq #-1,d0              ; search all drives
        moveq #5,d1               ; for a disk whose first file starts "main"
        move.l #'main',d2
        jsr $7fb2
        tst.l d0
        bne.s loaded2
        lea filename2(pc),a0
        movea.l $f8(a5),a1
        lea PACKED_OFFSET(a1),a1
        moveq #0,d1               ; load a file by name from that disk
        jsr $7fb2
        tst.l d0
        bne.s loaded2
        movea.l $f8(a5),a1
        lea PACKED_OFFSET(a1),a0
        lea EDITOR2_OFFSET(a1),a1
        move.l d1,d0
        jsr $3934
        lea loaded(pc),a0
        st (a0)
loaded2:
        movem.l (sp)+,d0-d7/a0-a4
        jsr $3c6e                 ; displaced: look for disk 2
        tst.w d0
        jmp $510

load_editor:
        jsr $3d48                 ; displaced metadata load
        cmpi.l #$24000,8.w
        blo.s menu
        lea loaded(pc),a0
        tst.b (a0)
        beq.s menu
        lea filename(pc),a0
        movea.l $f8(a5),a1
        lea PACKED_OFFSET(a1),a1
        moveq #0,d1
        jsr $3286
        movea.l $f8(a5),a1
        lea PACKED_OFFSET(a1),a0
        move.l d1,d0
        jsr $3934
        movea.l $f8(a5),a0
        jsr (a0)
menu:
        jsr $2c7e
        jmp $550
filename:
        dc.b 'Editor',0
filename2:
        dc.b 'Editor2',0
loaded:
        dc.b 0
        even
