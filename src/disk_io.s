; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Synchronous PAL disk transport for the level disk, called from the paused
; editor's main task or from the custom level list on the title screen.
; Interrupts remain enabled. In a level the non-displayed viewport is borrowed
; until the call returns; no drawing or buffer swap may run inside a transport
; call. All public calls preserve every register except D0/CCR. A5 is game
; globals. The versions with level files (FILES) have no level disk; they
; include disk_file.s (WHDLoad) or dos_file.s instead.
DISK_REFUSED    equ -1
DISK_CANCELLED  equ -2
DISK_NO_MEDIA   equ -3
DISK_READ_ERROR equ -4
DISK_WRONG      equ -5
DISK_PROTECTED  equ -6
DISK_CHANGED    equ -7
DISK_DAMAGED    equ -8
DISK_INDEX      equ -9
DISK_INDEX_WRITE equ -10
RAW_TITLE       equ $58800            ; the game's raw track buffer, idle on the title screen

        ifd FILES
        ifd WHDLOAD
        include "disk_file.s"
        else
        include "dos_file.s"
        endif
        else

; D0: drive 0..3, D1: track 0..159. Output: DISK_TRACK, cleared on failure.
; Reads do not establish permission for a later write.
disk_read_track:
        movem.l d1-d7/a0-a6,-(sp)
        lea state(pc),a4
        lea install(pc),a1
        adda.l #DISK_TRACK,a1
        cmp.l #160,d1
        bhs.s .refuse
        move.l d1,d7
        bsr disk_acquire
        tst.l d0
        bne.s .clear
        bsr disk_select
        tst.l d0
        bne.s .release
        move.l d7,d0
        bsr disk_read_decoded
.release:
        bsr disk_release
        tst.l d0
        beq.s .done
        bra.s .clear
.refuse:
        moveq #DISK_REFUSED,d0
.clear: move.w #TRACK_BYTES/4-1,d1
.zero:  clr.l (a1)+
        dbra d1,.zero
.done:  movem.l (sp)+,d1-d7/a0-a6
        rts

; Internal whole-track commit. A0: desired image of the already-read track
; at disk_track_no. The caller establishes identity, validation and permission.
; Retain drive/buffer ownership and defer cancellation through verification.
disk_write_decoded:
        movem.l d1-d7/a0-a3,-(sp)
        movea.l a0,a3
        movea.l disk_raw(a4),a1
        moveq #0,d0
        move.w disk_track_no(a4),d0
        bsr mfm_encode_track
        ; Rotate one gap word to the end. Paula may lose the last three bits
        ; of a write; they must belong to the gap, never to sector payload.
        move.w (a1),MFM_WRITE_BYTES(a1)
        addq.l #2,a1
        bsr disk_check_media
        tst.l d0
        bne.s .done
        btst #3,$bfe001
        beq.s .protected
        move.w #$7f00,$9e(a6)
        move.w #$9100,d0          ; MFMPREC and FAST; no WORDSYNC
        cmpi.b #40,disk_cylinder(a4)
        blo.s .precomp
        or.w #$2000,d0            ; 140 ns precompensation
.precomp:
        move.w d0,$9e(a6)
        st disk_committing(a4)
        move.w #$c000+MFM_WRITE_BYTES/2,d0
        bsr disk_dma
        move.l d0,d6
        moveq #33,d0              ; at least 2 ms after any write attempt
        bsr disk_delay
        tst.l d6
        bne.s .damaged
        lea install(pc),a1
        adda.l #DISK_VERIFY,a1
        moveq #0,d0
        move.w disk_track_no(a4),d0
        bsr disk_read_decoded
        tst.l d0
        bne.s .damaged
        movea.l a3,a0
        bsr disk_compare
        bne.s .damaged
        moveq #0,d0
        bra.s .done
.protected:
        moveq #DISK_PROTECTED,d0
        bra.s .done
.damaged:
        moveq #DISK_DAMAGED,d0
.done:  movem.l (sp)+,d1-d7/a0-a3
        rts

; Return comparison flags without changing A0/A1.
disk_compare:
        movem.l d1/a0-a1,-(sp)
        move.w #TRACK_BYTES/4-1,d1
.loop:  cmpm.l (a0)+,(a1)+
        dbne d1,.loop
        movem.l (sp)+,d1/a0-a1
        rts

; Validate ownership before touching hardware. In a level, the two known
; viewport bases must form a back/front pair and the back buffer is borrowed;
; on the title screen (title_disk) the game's idle raw track buffer is used.
; Wait a full PAL field for the copper pointer update to take effect, and
; drain any outstanding blit before borrowing.
disk_acquire:
        cmp.l #4,d0
        bhs .bad
        tst.b disk_busy(a4)
        bne .bad
        move.l #RAW_TITLE,d1
        tst.b title_disk(a4)
        bne.s .idle
        tst.b active(a4)
        beq .bad
        tst.b G_PAUSE(a5)
        beq .bad
        tst.b G_TWO_PLAYERS(a5)
        bne .bad
        move.l G_VIEW_BACK(a5),d1
        move.l #$2bd42,d2
        cmp.l #$23940,d1
        beq.s .front
        move.l #$23942,d2
        cmp.l #$2bd40,d1
        bne .bad
.front: cmp.l G_VIEW_FRONT(a5),d2
        bne .bad
.idle:  move.b $bfd100,d2
        and.b #$78,d2
        cmp.b #$78,d2
        bne .bad                  ; native loader must already be idle
        lea $dff000,a6
        addq.b #3,d0
        move.b d0,disk_drive(a4)
        move.l d1,disk_raw(a4)
        move.w $10(a6),disk_old_adk(a4)
        move.w 2(a6),disk_old_dma(a4)
        move.w $1c(a6),disk_old_int(a4)
        st disk_busy(a4)
        clr.b disk_cancel(a4)
        clr.b disk_committing(a4)
        move.w #2,$9a(a6)          ; poll DSKBLK, do not deliver a level-1 IRQ
        move.w #314,d0
        bsr disk_delay
        tst.b 2(a6)
.blit:  btst #6,2(a6)
        bne.s .blit
        moveq #0,d0
        rts
.bad:   moveq #DISK_REFUSED,d0
        rts

; Select exactly one drive with /MTR already low. A missing /DSKRDY falls
; back after 500 ms; /CHNG, bounded seeking and decoded data decide presence.
disk_select:
        moveq #0,d1
        move.b disk_drive(a4),d1
        move.b #$7f,$bfd100
        bclr d1,$bfd100
        move.w #8000,d2
.ready: btst #5,$bfe001
        beq.s .change
        moveq #1,d0
        bsr disk_delay
        tst.b disk_cancel(a4)
        bne .cancel
        dbra d2,.ready
.change:
        btst #2,$bfe001
        bne.s .home
        bset #1,$bfd100
        btst #4,$bfe001
        bne.s .step
        bclr #1,$bfd100           ; never step outward at track zero
.step:  bsr disk_step
        move.w #286,d0
        bsr disk_delay
.home:  bset #1,$bfd100
        moveq #83,d2
.seek0: btst #4,$bfe001
        beq.s .zero
        bsr disk_step
        dbra d2,.seek0
        moveq #DISK_NO_MEDIA,d0
        rts
.zero:  clr.b disk_cylinder(a4)
        move.w #286,d0
        bsr disk_delay
        bra disk_check_media
.cancel:
        moveq #DISK_CANCELLED,d0
        rts

; D0: track, A1: decoded destination. Preserve A1, D6 and D7. The output is
; only valid on success; public read clears it on any error. All seeks are
; bounded. A track that does not decode is read up to three times.
disk_read_decoded:
        bsr.s disk_seek_track
        tst.l d0
        bne.s .done
        move.l d6,-(sp)
        moveq #2,d6                     ; further attempts
.try:   move.l a1,-(sp)
        move.w #$7f00,$9e(a6)
        move.w #$9500,$9e(a6)     ; MFMPREC, WORDSYNC, FAST
        move.w #$4489,$7e(a6)
        movea.l disk_raw(a4),a1
        move.w #$8000+MFM_READ_BYTES/2,d0
        bsr disk_dma
        movea.l (sp)+,a1
        tst.l d0
        bne.s .end
        movea.l disk_raw(a4),a0
        move.l #MFM_READ_BYTES-2,d1 ; exclude Paula's possibly missing last word
        moveq #0,d0
        move.w disk_track_no(a4),d0
        bsr mfm_decode_track
        tst.l d0
        beq.s .read
        dbra d6,.try
        moveq #DISK_READ_ERROR,d0
        bra.s .end
.read:  bsr disk_check_media
.end:   move.l (sp)+,d6
.done:  rts

; D0: track. Step to its cylinder, select its side, let the head settle and
; check the media. Return 0 or an error. Preserve A1 and D7.
disk_seek_track:
        move.w d0,disk_track_no(a4)
        move.w d0,d3
        lsr.w #1,d3
        moveq #0,d2
        move.b disk_cylinder(a4),d2
        sub.w d2,d3
        beq.s .side
        bclr #1,$bfd100
        tst.w d3
        bpl.s .steps
        bset #1,$bfd100
        neg.w d3
.steps: subq.w #1,d3
.seek:  bsr disk_step
        dbra d3,.seek
.side:  move.w disk_track_no(a4),d0
        lsr.w #1,d0
        move.b d0,disk_cylinder(a4)
        bset #2,$bfd100
        btst #0,disk_track_no+1(a4)
        beq.s .settle
        bclr #2,$bfd100
.settle:
        move.w #286,d0
        bsr disk_delay
        bra disk_check_media

; A1: chip buffer, D0: DSKLEN. One bounded DMA attempt. Cancellation is
; deferred once a write starts, including throughout its read-back check.
disk_dma:
        move.w #$8210,$96(a6)
        move.w #$4000,$24(a6)
        move.l a1,$20(a6)
        move.w #2,$9c(a6)
        move.w d0,$24(a6)
        move.w d0,$24(a6)
        move.w #16000,d2          ; at least one second, PAL raster timing
.wait:  btst #1,$1f(a6)
        bne.s .complete
        bsr disk_check_media
        tst.l d0
        bne.s .stop
        moveq #1,d0
        bsr disk_delay
        dbra d2,.wait
        moveq #DISK_READ_ERROR,d0
        bra.s .stop
.complete:
        bsr disk_check_media
.stop:  move.w #$4000,$24(a6)
        move.w #2,$9c(a6)
        rts

disk_check_media:
        btst #2,$bfe001
        beq.s .missing
        tst.b disk_committing(a4)
        bne.s .ok
        tst.b disk_cancel(a4)
        bne.s .cancel
.ok:    moveq #0,d0
        rts
.missing:
        moveq #DISK_NO_MEDIA,d0
        rts
.cancel:
        moveq #DISK_CANCELLED,d0
        rts

disk_step:
        bclr #0,$bfd100
        bset #0,$bfd100
        moveq #49,d0             ; at least 3 ms between steps
disk_delay:
        move.b 6(a6),d1
.line:  cmp.b 6(a6),d1
        beq.s .line
        move.b 6(a6),d1
        subq.w #1,d0
        bne.s .line
        rts

; One cleanup path for success, cancellation and all hardware errors. Latch
; motor off by deselecting, raising /MTR, then selecting and deselecting again.
; Native disk reads home when $83C2 is negative; the drive variable is intact.
disk_release:
        move.l d0,-(sp)
        move.w #$4000,$24(a6)
        move.w #2,$9c(a6)
        moveq #0,d1
        move.b disk_drive(a4),d1
        move.b #$ff,$bfd100
        bclr d1,$bfd100
        bset d1,$bfd100
        st $83c2
        move.w #$7f00,$9e(a6)
        move.w disk_old_adk(a4),d0
        and.w #$7f00,d0
        or.w #$8000,d0
        move.w d0,$9e(a6)
        move.w #$10,$96(a6)
        move.w disk_old_dma(a4),d0
        and.w #$10,d0
        or.w #$8000,d0
        move.w d0,$96(a6)
        move.w disk_old_int(a4),d0
        and.w #2,d0
        or.w #$8000,d0
        move.w d0,$9a(a6)
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
        endif
