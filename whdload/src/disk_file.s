; Lemmings In-Game Level Editor V1.2
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Save disk transport for the WHDLoad version. Included by disk_io.s in place
; of the floppy hardware routines when WHDLOAD is defined. The save disk is the
; image file Lemmings_SaveDisk.adf in WHDLoad's data directory, in the same
; format as a floppy save disk, so the file can be written to a real disk and
; back. The checks and the update order in disk_io.s stay the same.
;
; Every file access makes WHDLoad switch to the operating system, which blanks
; the display for a moment. The whole image is therefore kept in memory: it is
; loaded with one call on first use, tracks are read from memory, a changed
; track is written back with one call, and a new disk is written in one call.
;
; The WHDLoad slave leaves a mailbox directly above the editor block:
;   +0  'WHDL'
;   +4  resload base
;   +8  address of the 901120-byte image buffer
;   +12 image state: 0 not loaded yet, 1 valid, 2 no usable file

        include "whdload_api.i"

TRACK_BYTES     equ 11*512
SAVE_DISK_SIZE  equ 160*TRACK_BYTES
MB_RESLOAD      equ 4
MB_IMAGE        equ 8
MB_STATE        equ 12

; D0: drive 0..3 (only the number is kept). Check that the editor may use the
; save disk now, as the floppy version does, and that WHDLoad is present.
disk_acquire:
        cmp.l #4,d0
        bhs.s .bad
        tst.b disk_busy(a4)
        bne.s .bad
        tst.b active(a4)
        beq.s .bad
        tst.b $39(a5)
        beq.s .bad
        tst.b $30(a5)
        bne.s .bad
        tst.b load_pending(a4)
        bne.s .bad
        move.l a3,-(sp)
        bsr file_mailbox
        movea.l (sp)+,a3
        bne.s .bad
        addq.b #3,d0
        move.b d0,disk_drive(a4)
        st disk_busy(a4)
        clr.b disk_cancel(a4)
        clr.b disk_committing(a4)
        moveq #0,d0
        rts
.bad:   moveq #DISK_REFUSED,d0
        rts

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

; A3: mailbox, A2: resload base. Load the file into the image buffer once.
; Return D0 = 0 when the image is valid, otherwise DISK_READ_ERROR (a missing
; or truncated file reads as an unformatted disk).
file_image:
        tst.b MB_STATE(a3)
        bne.s .known
        lea save_file(pc),a0
        jsr resload_GetFileSize(a2)
        move.b #2,MB_STATE(a3)
        cmp.l #SAVE_DISK_SIZE,d0
        bne.s .known
        lea save_file(pc),a0
        movea.l MB_IMAGE(a3),a1
        jsr resload_LoadFile(a2)
        move.b #1,MB_STATE(a3)
.known: moveq #0,d0
        cmpi.b #1,MB_STATE(a3)
        beq.s .done
        moveq #DISK_READ_ERROR,d0
.done:  rts

; D0: track. A0: its address in the image buffer (A3: mailbox).
track_address:
        moveq #0,d0
        move.w disk_track_no(a4),d0
        mulu #TRACK_BYTES,d0
        movea.l MB_IMAGE(a3),a0
        adda.l d0,a0
        rts

; There is no drive to select.
disk_select:
        moveq #0,d0
        rts

; D0: track. Remember it for the next write and honour Esc.
disk_seek_track:
        move.w d0,disk_track_no(a4)
        moveq #0,d0
        tst.b disk_committing(a4)
        bne.s .done
        tst.b disk_cancel(a4)
        beq.s .done
        moveq #DISK_CANCELLED,d0
.done:  rts

; D0: track, A1: destination. Preserve every register except D0.
disk_read_decoded:
        bsr disk_seek_track
        tst.l d0
        bne.s .done
        movem.l d1/a0-a3,-(sp)
        move.l a1,-(sp)
        bsr file_mailbox
        bsr file_image
        movea.l (sp)+,a1
        tst.l d0
        bne.s .restore
        bsr track_address
        move.w #TRACK_BYTES/4-1,d1
.copy:  move.l (a0)+,(a1)+
        dbra d1,.copy
        moveq #0,d0
.restore:
        movem.l (sp)+,d1/a0-a3
.done:  rts

; A0: desired image of the track at disk_track_no, which has been read.
; Update the image and write the track to the file. With WHDLF_NoError a
; failing write ends WHDLoad with its requester, so a return is a success.
; Preserve every register except D0.
disk_write_decoded:
        movem.l d1/a0-a3,-(sp)
        st disk_committing(a4)
        movea.l a0,a1
        bsr file_mailbox
        bsr track_address
        move.l a0,-(sp)
        move.w #TRACK_BYTES/4-1,d1
.copy:  move.l (a1)+,(a0)+
        dbra d1,.copy
        moveq #0,d1
        move.w disk_track_no(a4),d1
        mulu #TRACK_BYTES,d1
        move.l #TRACK_BYTES,d0
        lea save_file(pc),a0
        movea.l (sp)+,a1
        jsr resload_SaveFileOffset(a2)
        moveq #0,d0
        movem.l (sp)+,d1/a0-a3
        rts

; D0: drive. Write an empty save disk: data tracks with two empty slots and
; zero reserved sectors, track zero with the header and an empty index. The
; image is built in memory and the file written with one call.
disk_initialize:
        movem.l d1-d7/a0-a6,-(sp)
        bsr disk_acquire
        tst.l d0
        bne.s .done
        bsr file_mailbox
        movea.l MB_IMAGE(a3),a0
        move.l #SAVE_DISK_SIZE/16,d1
.clear: clr.l (a0)+
        clr.l (a0)+
        clr.l (a0)+
        clr.l (a0)+
        subq.l #1,d1
        bne.s .clear
        movea.l MB_IMAGE(a3),a0
        lea disk_header(pc),a1
        moveq #7,d1
.header:
        move.l (a1)+,(a0)+
        dbra d1,.header
        lea 64-32(a0),a1
        move.w #317,d1
.index: move.b #$ff,(a1)
        addq.l #3,a1
        dbra d1,.index
        lea -32(a0),a0
        bsr seal_disk_index
        move.l #SAVE_DISK_SIZE,d0
        lea save_file(pc),a0
        movea.l MB_IMAGE(a3),a1
        jsr resload_SaveFile(a2)
        move.b #1,MB_STATE(a3)
        moveq #0,d0
        bsr disk_release
.done:  movem.l (sp)+,d1-d7/a0-a6
        rts

; One cleanup path for success, cancellation and errors, as on floppy.
disk_release:
        move.l d0,-(sp)
        move.w sr,-(sp)
        ori.w #$0700,sr
        clr.w pending_toggle(a4)
        clr.b pending_flip(a4)
        clr.b disk_busy(a4)
        move.w (sp)+,sr
        btst #6,$bfe001
        seq last_left(a4)
        btst #2,$16(a6)
        seq last_right(a4)
        st disk_redraw(a4)
        move.l (sp)+,d0
        rts

save_file:
        dc.b 'Lemmings_SaveDisk.adf',0
        even
