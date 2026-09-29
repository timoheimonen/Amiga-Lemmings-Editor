; Lemmings In-Game Level Editor V1.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Track-zero allocation index. All entry points preserve registers except
; D0/CCR. Three-byte entries are accessed as bytes for 68000 alignment.
INDEX_BYTES equ 318*3
INDEX_END   equ 64+INDEX_BYTES

; A0: complete track zero. The immutable header, header CRC and track padding
; must pass even when recovering an index. Return 0 or DISK_WRONG.
validate_disk_identity:
        movem.l d1-d7/a0-a2,-(sp)
        movea.l a0,a2
        lea disk_header(pc),a1
        moveq #7,d1
.header:
        move.l (a0)+,d0
        cmp.l (a1)+,d0
        bne.s .bad
        dbra d1,.header
        addq.l #4,a0
        moveq #5,d1
.reserved:
        tst.l (a0)+
        bne.s .bad
        dbra d1,.reserved
        lea INDEX_END(a2),a0
        move.w #(TRACK_BYTES-INDEX_END)/2-1,d1
.zero:  tst.w (a0)+
        bne.s .bad
        dbra d1,.zero
        movea.l a2,a0
        moveq #64,d0
        moveq #60,d1
        bsr crc32
        cmp.l 60(a2),d0
        bne.s .bad
        moveq #0,d0
        bra.s .done
.bad:   moveq #DISK_WRONG,d0
.done:  movem.l (sp)+,d1-d7/a0-a2
        rts

; A0: complete track zero. In addition to identity, require the index CRC,
; entry bounds and at most 32 entries per level. Return 0, DISK_WRONG or
; DISK_INDEX. An index failure is not permission to initialize the disk.
validate_disk_header:
        bsr validate_disk_identity
        tst.l d0
        bne .return
        movem.l d1-d7/a0-a2,-(sp)
        movea.l a0,a2
        lea -120(sp),sp
        movea.l sp,a1
        moveq #29,d1
.clear: clr.l (a1)+
        dbra d1,.clear
        lea 64(a2),a0
        move.l #INDEX_BYTES,d0
        moveq #-1,d1
        bsr crc32
        cmp.l 32(a2),d0
        bne.s .bad
        lea 64(a2),a0
        movea.l sp,a1
        move.w #317,d3
.entry: moveq #0,d0
        move.b (a0)+,d0
        moveq #0,d1
        move.b (a0)+,d1
        lsl.w #8,d1
        move.b (a0)+,d1
        cmp.b #255,d0
        bne.s .used
        tst.w d1
        bne.s .bad
        bra.s .next
.used:  cmp.w #120,d0
        bhs.s .bad
        cmp.w #400,d1
        bhi.s .bad
        addq.b #1,0(a1,d0.w)
        cmpi.b #32,0(a1,d0.w)
        bhi.s .bad
.next:  dbra d3,.entry
        moveq #0,d0
        bra.s .done
.bad:   moveq #DISK_INDEX,d0
.done:  lea 120(sp),sp
        movem.l (sp)+,d1-d7/a0-a2
.return:
        rts

; Seal a changed index and its header. A0 addresses a complete track zero.
seal_disk_index:
        movem.l d1-d7/a0-a2,-(sp)
        movea.l a0,a2
        lea 64(a2),a0
        move.l #INDEX_BYTES,d0
        moveq #-1,d1
        bsr crc32
        move.l d0,32(a2)
        movea.l a2,a0
        moveq #64,d0
        moveq #60,d1
        bsr crc32
        move.l d0,60(a2)
        moveq #0,d0
        movem.l (sp)+,d1-d7/a0-a2
        rts

; A0: slot. D0 returns $FF0000 for a completely empty slot, or level<<16 |
; edit count for a valid record. Invalid records return DISK_REFUSED.
disk_slot_entry:
        movem.l d1/a1,-(sp)
        movea.l a0,a1
        move.w #511,d1
.empty: tst.l (a1)+
        bne.s .used
        dbra d1,.empty
        move.l #$ff0000,d0
        bra.s .done
.used:  bsr validate_any_record
        tst.l d0
        bne.s .done
        move.l 16(a0),d0
.done:  movem.l (sp)+,d1/a1
        rts

; A0: decoded data track, D0: track 1..159. Validate both slots, index
; agreement and reserved sectors against DISK_HEADER. Preserve A0 and D7.
disk_check_index_track:
        movem.l d1-d7/a0-a2,-(sp)
        subq.w #1,d0
        mulu #6,d0
        lea install(pc),a2
        adda.l #DISK_HEADER+64,a2
        adda.l d0,a2
        moveq #1,d6
.slot:  bsr disk_slot_entry
        tst.l d0
        bmi.s .bad
        moveq #0,d1
        move.b (a2)+,d1
        lsl.l #8,d1
        move.b (a2)+,d1
        lsl.l #8,d1
        move.b (a2)+,d1
        cmp.l d1,d0
        bne.s .bad
        adda.w #2048,a0
        dbra d6,.slot
        move.w #1536/4-1,d1
.zero:  tst.l (a0)+
        bne.s .bad
        dbra d1,.zero
        moveq #0,d0
        bra.s .done
.bad:   moveq #DISK_INDEX,d0
.done:  movem.l (sp)+,d1-d7/a0-a2
        rts

; D0: drive. Read the index and only current-level tracks, retaining drive
; ownership throughout. Output: disk_free, disk_rows and up to 32 DISK_ROWS
; records (slot word, count word, 16 name bytes). Errors clear both counts.
disk_scan_level:
        movem.l d1-d7/a0-a6,-(sp)
        lea state(pc),a4
        clr.w disk_free(a4)
        clr.w disk_rows(a4)
        bsr disk_acquire
        tst.l d0
        bne .done
        bsr disk_select
        tst.l d0
        bne .release
        lea install(pc),a1
        adda.l #DISK_HEADER,a1
        moveq #0,d0
        bsr disk_read_decoded
        tst.l d0
        bne .release
        movea.l a1,a0
        bsr validate_disk_header
        tst.l d0
        bne .release
        lea 64(a1),a3
        lea install(pc),a2
        adda.l #DISK_ROWS,a2
        moveq #0,d7
        moveq #-1,d6
.entry: moveq #0,d0
        move.b (a3),d0
        cmp.b #255,d0
        bne.s .used
        addq.w #1,disk_free(a4)
        bra.s .next
.used:  cmp.w level_id(a4),d0
        bne.s .next
        move.l d7,d0
        lsr.w #1,d0
        addq.w #1,d0
        cmp.w d6,d0
        beq.s .row
        move.w d0,d6
        bsr disk_progress
        lea install(pc),a1
        adda.l #DISK_TRACK,a1
        bsr disk_read_decoded
        tst.l d0
        bne.s .release
        movea.l a1,a0
        move.w d6,d0
        bsr disk_check_index_track
        tst.l d0
        bne.s .release
.row:   movea.l a1,a0
        btst #0,d7
        beq.s .copy
        adda.w #2048,a0
.copy:  move.w d7,(a2)+
        move.w 18(a0),(a2)+
        lea 24(a0),a0
        moveq #3,d1
.name:  move.l (a0)+,(a2)+
        dbra d1,.name
        addq.w #1,disk_rows(a4)
.next:  addq.l #3,a3
        addq.w #1,d7
        cmp.w #318,d7
        blo .entry
        moveq #0,d0
.release:
        bsr disk_release
.done:  tst.l d0
        beq.s .return
        clr.w disk_free(a4)
        clr.w disk_rows(a4)
.return:
        movem.l (sp)+,d1-d7/a0-a6
        rts

; D0: drive. Recover an index from every physical slot, retaining ownership.
; Invalid records, reserved bytes or more than 32 saves for a level refuse.
; Only track zero is written, after checking its original snapshot again.
disk_rebuild_index:
        movem.l d1-d7/a0-a6,-(sp)
        lea state(pc),a4
        clr.w disk_free(a4)
        clr.w disk_rows(a4)
        bsr disk_acquire
        tst.l d0
        bne .done
        bsr disk_select
        tst.l d0
        bne .release
        lea install(pc),a1
        adda.l #DISK_HEADER,a1
        moveq #0,d0
        bsr disk_read_decoded
        tst.l d0
        bne .release
        movea.l a1,a0
        bsr validate_disk_identity
        tst.l d0
        bne .release
        lea install(pc),a2
        adda.l #DISK_REINDEX,a2
        moveq #1,d7
.track: lea install(pc),a1
        adda.l #DISK_TRACK,a1
        move.l d7,d0
        bsr disk_progress
        bsr disk_read_decoded
        tst.l d0
        bne .release
        movea.l a1,a0
        moveq #1,d6
.slot:  bsr disk_slot_entry
        tst.l d0
        bmi .bad
        move.b d0,2(a2)
        lsr.l #8,d0
        move.b d0,1(a2)
        lsr.l #8,d0
        move.b d0,(a2)
        addq.l #3,a2
        adda.w #2048,a0
        dbra d6,.slot
        move.w #1536/4-1,d1
.zero:  tst.l (a0)+
        bne.s .bad
        dbra d1,.zero
        addq.w #1,d7
        cmp.w #160,d7
        blo.s .track
        lea install(pc),a1
        adda.l #DISK_VERIFY,a1
        moveq #0,d0
        bsr disk_read_decoded
        tst.l d0
        bne.s .release
        lea install(pc),a0
        adda.l #DISK_HEADER,a0
        bsr disk_compare
        bne.s .changed
        lea 64(a0),a1
        lea install(pc),a2
        adda.l #DISK_REINDEX,a2
        move.w #INDEX_BYTES/2-1,d1
.copy:  move.w (a2)+,(a1)+
        dbra d1,.copy
        bsr seal_disk_index
        bsr validate_disk_header
        tst.l d0
        bne.s .release
        bsr disk_write_decoded
        cmp.l #DISK_DAMAGED,d0
        bne.s .release
        moveq #DISK_INDEX_WRITE,d0
        bra.s .release
.changed:
        moveq #DISK_CHANGED,d0
        bra.s .release
.bad:   moveq #DISK_INDEX,d0
.release:
        bsr disk_release
.done:  movem.l (sp)+,d1-d7/a0-a6
        rts

disk_header:
        dc.b 'LEMSAVE',0
        dc.w 1,64
        dc.l $00010001
        dc.w 512,11,160,2048,318,32,3,INDEX_BYTES
