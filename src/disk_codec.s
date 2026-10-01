; Lemmings In-Game Level Editor V2.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; CPU-only Amiga DD track codec. Buffers must be word-aligned and disjoint.
; These routines neither access disk hardware nor authorize a disk write.
MFM_SECTOR      equ 1088
MFM_WRITE_BYTES equ 12668
MFM_READ_BYTES  equ $3600
MFM_GAP_BYTES   equ MFM_WRITE_BYTES-11*MFM_SECTOR

; A0: 5632 decoded bytes, A1: 12668 output bytes, D0: track 0..159.
; Return D0=0 or -1 (invalid track, output untouched). Preserve other registers.
; Emit zero sector labels, checksums, sync and continuous MFM clock bits.
mfm_encode_track:
        movem.l d1-d7/a0-a4,-(sp)
        cmp.l #160,d0
        bhs .bad
        move.l #$55555555,d7
        move.l d0,d6
        swap d6
        ori.l #$ff000000,d6
        movea.l a1,a4
        move.w #MFM_GAP_BYTES/2-1,d1
.gap:   move.w #$aaaa,(a1)+
        dbra d1,.gap
        moveq #0,d5
        moveq #0,d4                ; preceding data bit
.sector:
        move.l #$aaaaaaaa,d0
        tst.b d4
        beq.s .preamble
        bclr #31,d0
.preamble:
        move.l d0,(a1)+
        move.l #$44894489,(a1)+
        movea.l a1,a2
        move.l d6,d0
        move.w d5,d0
        lsl.w #8,d0
        moveq #11,d1
        sub.w d5,d1
        move.b d1,d0
        move.l d0,d1
        lsr.l #1,d0
        and.l d7,d0
        and.l d7,d1
        move.l d0,(a1)+
        move.l d1,(a1)+
        eor.l d1,d0
        moveq #7,d2
.label: clr.l (a1)+
        dbra d2,.label
        clr.l (a1)+               ; checksum odd half is zero
        move.l d0,(a1)+
        addq.l #8,a1              ; data checksum, filled below
        moveq #0,d3
        moveq #127,d2
.data:  move.l (a0)+,d1
        move.l d1,d0
        lsr.l #1,d0
        and.l d7,d0
        and.l d7,d1
        move.l d0,(a1)
        move.l d1,512(a1)
        addq.l #4,a1
        eor.l d0,d3
        eor.l d1,d3
        dbra d2,.data
        clr.l 48(a2)
        move.l d3,52(a2)
        adda.w #512,a1
        movea.l a2,a3
        move.w #539,d2
        moveq #1,d4                ; last bit of sync word
.clock: moveq #0,d0
        move.w (a3),d0
        move.l d4,d1
        swap d1
        or.l d0,d1
        move.l d0,d4
        andi.l #$55555555,d1
        eori.l #$55555555,d1
        move.l d1,d3
        lsl.l #1,d1
        lsr.l #1,d3
        and.l d3,d1
        or.w d1,d0
        move.w d0,(a3)+
        dbra d2,.clock
        and.w #1,d4
        addq.w #1,d5
        cmp.w #11,d5
        blo .sector
        tst.b d4
        beq.s .ok
        move.w #$2aaa,(a4)        ; continuity across track wrap
.ok:    moveq #0,d0
        bra.s .done
.bad:   moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a0-a4
        rts

; A0: word-synchronized MFM capture, D1: even byte length (2..13824),
; A1: 5632-byte output, D0: expected track 0..159. Return 0 or -1 and
; preserve all other registers. Failure clears the entire decoded output.
; Require all 11 sectors, valid checksums and zero labels. Identical repeated
; sectors are accepted; conflicting duplicates and malformed headers refuse.
; Clock bits are ignored during decoding, as with the native disk checksum.
mfm_decode_track:
        movem.l d1-d7/a0-a6,-(sp)
        movea.l a1,a6
        cmp.l #160,d0
        bhs .bad
        cmp.l #MFM_READ_BYTES,d1
        bhi .bad
        cmp.l #2,d1
        blo .bad
        btst #0,d1
        bne .bad
        move.l d0,d6
        movea.l a0,a5
        adda.l d1,a5
        moveq #0,d5                ; sector bitmap
        move.l #$55555555,d7
.scan:  cmpa.l a5,a0
        bhs .end
        cmpi.w #$4489,(a0)+
        bne.s .scan
.sync:  cmpa.l a5,a0
        bhs .end
        cmpi.w #$4489,(a0)
        bne.s .header
        addq.l #2,a0
        bra.s .sync
.header:
        move.l a5,d0
        sub.l a0,d0
        cmp.l #1080,d0
        blo .end                  ; incomplete final sector is not decoded
        movea.l a0,a2
        bsr .long
        move.l d0,d4
        rol.l #8,d0
        cmp.b #$ff,d0
        bne .bad
        rol.l #8,d0
        cmp.b d6,d0
        bne .bad
        move.w d4,d0
        lsr.w #8,d0
        cmp.w #11,d0
        bhs .bad
        move.l d0,d4              ; sector number
        movea.l a2,a0
        bsr .long
        and.w #255,d0
        beq .bad
        cmp.w #11,d0
        bhi .bad
        move.l (a2),d3
        move.l 4(a2),d0
        eor.l d0,d3
        and.l d7,d3
        lea 8(a2),a0
        moveq #7,d2
.labels:
        move.l (a0)+,d0
        and.l d7,d0
        bne .bad
        dbra d2,.labels
        bsr .long                 ; header checksum at offset 40
        cmp.l d3,d0
        bne .bad
        bsr .long                 ; data checksum at offset 48
        move.l d0,d3
        movea.l a6,a3
        move.l d4,d0
        lsl.l #8,d0
        add.l d0,d0
        adda.l d0,a3
        moveq #127,d2
.data:  move.l (a0),d0
        move.l 512(a0),d1
        and.l d7,d0
        and.l d7,d1
        eor.l d0,d3
        eor.l d1,d3
        add.l d0,d0
        or.l d1,d0
        btst d4,d5
        beq.s .store
        cmp.l (a3),d0
        bne .bad
.store: move.l d0,(a3)+
        addq.l #4,a0
        dbra d2,.data
        tst.l d3
        bne.s .bad
        bset d4,d5
        adda.w #512,a0
        bra .scan
.end:   cmp.w #$7ff,d5
        bne.s .bad
        moveq #0,d0
        bra.s .done
.bad:   move.w #TRACK_BYTES/4-1,d1
.clear: clr.l (a6)+
        dbra d1,.clear
        moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a0-a6
        rts
.long:  move.l (a0)+,d0
        move.l (a0)+,d1
        and.l d7,d0
        and.l d7,d1
        add.l d0,d0
        or.l d1,d0
        rts
