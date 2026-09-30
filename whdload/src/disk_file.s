; Lemmings In-Game Level Editor V2.0
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; File access of the WHDLoad version, included by disk_io.s in place of the
; floppy disk transport. The custom levels are the .lvl files of the directory
; Levels, read and written through WHDLoad (levels.s, level_save.s).
;
; The WHDLoad slave leaves a mailbox directly above the editor block:
;   +0  'WHDL'
;   +4  resload base

        include "whdload_api.i"

MB_RESLOAD      equ 4

; A3: mailbox, A2: resload base. Return with Z set, or DISK_REFUSED when the
; mailbox is missing. D0 is preserved on success.
file_mailbox:
        lea install(pc),a3
        adda.l #EDITOR_RESERVE,a3
        cmpi.l #'WHDL',(a3)
        bne.s .missing
        movea.l MB_RESLOAD(a3),a2
        cmp.b d0,d0
        rts
.missing:
        moveq #DISK_REFUSED,d0
        rts
