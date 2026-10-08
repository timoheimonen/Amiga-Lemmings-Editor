; Lemmings In-Game Level Editor V2.3.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Bootstrap appended to the game's main program. It runs only during start-up,
; before the game uses this memory for anything else.
;
; The editor image is stored packed in the file Editor behind the boot loader
; at the end of disk 1 (tracks the game never reads); the disk 1 directory
; reaches it through a placeholder entry that covers the boot loader, so the
; game's loader finds it by name like any other file. Disk 2 is not changed.
;
; "reserve" is reached from the game's file cache setup (HOOK_RESERVE): it
; keeps the top 128 KiB of slow RAM for the editor.
; "load_editor" replaces the game's check for disk 2 (HOOK_LOAD). Disk 1 is
; still in a drive at this point, also on a single-drive machine. It finds
; disk 1 with the game's own drive search and loader, loads Editor to the
; staging area and unpacks it into the block, and then runs the original
; check, which asks for disk 2 if necessary.
; "install_editor" is reached from the start-up code (HOOK_INSTALL): it runs
; the displaced metadata load and the editor's installer.
; Without enough slow RAM, or if Editor could not be loaded, the editor is
; skipped and the game runs unchanged. patch.py writes the three jumps.
        include "game_lemmings.i"

PACKED_OFFSET   equ $b000            ; staging area above code and state
; The loader's directory buffer (DIR_BUFFER) and the raw track buffer
; (RAW_TRACK) are both unused during start-up.

        org $21b4c
reserve:
        adda.l 8.w,a1
        cmpi.l #$24000,8.w
        blo.s unavailable
        suba.l #$20000,a1
unavailable:
        move.l a1,G_CACHE_END(a5)
        jmp RESERVE_DONE

load_editor:
        movem.l d0-d7/a0-a4,-(sp)
        lea loaded(pc),a0
        tst.b (a0)
        bne.s .done               ; start-up runs once; never reload
        cmpi.l #$24000,8.w
        blo.s .done
        lea DIR_BUFFER,a0
        lea RAW_TRACK,a1
        moveq #-1,d0              ; search all drives
        moveq #5,d1               ; for a disk whose first file starts "main"
        move.l #'main',d2
        jsr DISK_LOADER
        tst.l d0
        bne.s .done
        lea filename(pc),a0
        movea.l G_CACHE_END(a5),a1
        adda.l #PACKED_OFFSET,a1
        moveq #0,d1               ; load a file by name from that disk
        jsr DISK_LOADER
        tst.l d0
        bne.s .done
        movea.l G_CACHE_END(a5),a1
        movea.l a1,a0
        adda.l #PACKED_OFFSET,a0
        move.l d1,d0
        jsr UNPACK
        lea loaded(pc),a0
        st (a0)
.done:  movem.l (sp)+,d0-d7/a0-a4
        jsr FIND_DISK2            ; displaced: look for disk 2
        tst.w d0
        jmp LOAD_DONE

install_editor:
        jsr LOAD_METADATA         ; displaced
        lea loaded(pc),a0
        tst.b (a0)
        beq.s .menu
        movea.l G_CACHE_END(a5),a0
        jsr (a0)
.menu:  jsr LOAD_ICONS
        jmp INSTALL_DONE
filename:
        dc.b 'Editor',0
loaded:
        dc.b 0
        even
