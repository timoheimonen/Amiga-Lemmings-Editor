; Lemmings In-Game Level Editor V2.3.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Deleting a terrain piece. In the erasing mode of the terrain brush, Shift
; held switches to deleting: the preview is hidden, the piece under the
; cursor is outlined, and the left button takes it out of the level's list,
; which frees its place. The piece under the cursor is the last of the
; level's pieces (the record's, then the placements) whose mask covers the
; cursor's pixel, erasing and behind pieces included.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

; From the frame hook: deleting while Shift is held in the erasing mode of
; the terrain brush. A change redraws the view and the brush field.
delete_update:
        move.l d0,-(sp)
        moveq #0,d0
        tst.b edit_mode(a4)
        bne.s .set
        tst.b negative(a4)
        beq.s .set
        move.b shift(a4),d0
.set:   cmp.b delete_mode(a4),d0
        beq.s .done
        move.b d0,delete_mode(a4)
        st dirty(a4)
.done:  move.l (sp)+,d0
        rts

; From the frame hook: the left button in the deleting mode. Delete the piece
; under the cursor and rebuild the terrain under it.
piece_delete:
        movem.l d0-d1,-(sp)
        bsr.s piece_hover
        tst.l d0
        bmi.s .done
        bsr terrain_take
        bsr undo_deleted
        move.l d1,d0
        bsr terrain_rebuild
        st dirty(a4)
.done:  movem.l (sp)+,d0-d1
        rts

; From the overlay in the deleting mode: outline the piece under the cursor
; in the view's back buffer.
piece_outline:
        movem.l d0-d5/a0,-(sp)
        bsr.s piece_hover
        tst.l d0
        bmi.s .done
        move.l d1,d0
        swap d0
        and.w #$1fff,d0                 ; x
        move.w d1,d3
        asr.w #7,d3                     ; y, signed
        bsr piece_desc
        move.w d0,d2
        sub.w (VIEW_SCROLL).l,d2              ; left: world x - scroll
        move.w d2,d4
        add.w (a0),d4
        subq.w #1,d4                    ; right
        subq.w #4,d3                    ; top: world y - 4
        move.w d3,d5
        add.w 2(a0),d5
        subq.w #1,d5                    ; bottom
        bsr outline_box
.done:  movem.l (sp)+,d0-d5/a0
        rts

; The piece under the cursor (brush_x/brush_y). Return its number in the
; level's list in D0, or -1, and the piece in D1. A piece is passed over in
; the loop while the cursor is not inside the largest piece of the style at
; its origin; only the others are tested against their size and mask.
piece_hover:
        movem.l d2-d7/a0-a3,-(sp)
        moveq #-1,d6                    ; the last one found
        moveq #0,d7
        moveq #0,d5                     ; number of the next piece
        tst.w (LEVEL_RECORD+$1c).l                 ; a special background has no pieces
        bne.s .done
        movea.l G_STYLE(a5),a1              ; the largest width and height
        lea PIECE_DESC(a1),a1
        move.w piece_count(a4),d2
        subq.w #1,d2
        moveq #0,d0
        moveq #0,d1
.size:  cmp.w (a1),d0
        bhs.s .height
        move.w (a1),d0
.height:
        cmp.w 2(a1),d1
        bhs.s .type
        move.w 2(a1),d1
.type:  lea PIECE_SIZE(a1),a1
        dbra d2,.size
        movea.w d0,a0
        movea.w d1,a1
        move.w brush_x(a4),d3
        move.w brush_y(a4),d4
        lea custom_record+$120(pc),a2
        lea custom_record+$760(pc),a3
        bsr.s .scan
        lea placements(pc),a2
        move.l paint_count(a4),d0
        lsl.l #2,d0
        lea 0(a2,d0.l),a3
        bsr.s .scan
.done:  move.l d6,d0
        move.l d7,d1
        movem.l (sp)+,d2-d7/a0-a3
        rts
; A2: pieces up to A3 or the end marker. D3/D4: the cursor, A0/A1: the
; largest width and height.
.scan:  cmpa.l a3,a2
        bhs.s .end
        move.l (a2)+,d0
        cmpi.l #-1,d0
        beq.s .end
        swap d0
        move.w d0,d1
        swap d0
        and.w #$1fff,d1
        move.w d3,d2
        sub.w d1,d2                     ; cursor x - piece x
        cmp.w a0,d2
        bhs.s .next                     ; left of it, or beyond the widest
        move.w d0,d2
        asr.w #7,d2
        neg.w d2
        add.w d4,d2                     ; cursor y - piece y
        cmp.w a1,d2
        bhs.s .next
        bsr.s piece_covers
        beq.s .next
        move.l d5,d6
        move.l d0,d7
.next:  addq.l #1,d5
        bra.s .scan
.end:   rts

; D0: a terrain piece. Z clear when its mask covers the cursor's pixel
; (brush_x/brush_y). Preserves every register.
piece_covers:
        movem.l d0-d3/a0,-(sp)
        move.w brush_x(a4),d2
        swap d0
        move.w d0,d1
        swap d0
        and.w #$1fff,d1
        sub.w d1,d2                     ; column in the piece
        bmi.s .no
        move.w d0,d3
        asr.w #7,d3
        neg.w d3
        add.w brush_y(a4),d3            ; row in the piece
        bmi.s .no
        move.w d0,d1
        bsr piece_desc
        cmp.w (a0),d2
        bhs.s .no
        cmp.w 2(a0),d3
        bhs.s .no
        swap d0
        btst #14,d0                     ; flipped: the mask's rows reversed
        beq.s .row
        neg.w d3
        add.w 2(a0),d3
        subq.w #1,d3
.row:   move.w (a0),d1
        lsr.w #3,d1
        mulu d3,d1
        move.l gfx_ptr(a4),d0
        sub.l #GROUND_BASE,d0
        add.l 8(a0),d0
        add.l d1,d0
        movea.l d0,a0
        move.w d2,d1
        lsr.w #3,d1
        adda.w d1,a0
        not.w d2
        and.w #7,d2                     ; bit 7 - (column & 7)
        btst d2,(a0)
        movem.l (sp)+,d0-d3/a0
        rts
.no:    cmp.w d0,d0                     ; Z
        movem.l (sp)+,d0-d3/a0
        rts

; Pieces in the record's list, up to its end marker: D2.
record_count:
        move.l a0,-(sp)
        lea custom_record+$120(pc),a0
        moveq #0,d2
.count: cmpi.l #-1,(a0)+
        beq.s .done
        addq.w #1,d2
        bra.s .count
.done:  movea.l (sp)+,a0
        rts

; D0: number of a piece in the level's list. Take it out of the list (the
; record and the game's copy in LEVEL_RECORD, or the placements) and return it in
; D1. The pieces after it move down one place.
terrain_take:
        movem.l d0/d2-d3/a0-a1,-(sp)
        bsr.s record_count
        cmp.w d2,d0
        bhs.s .placed
        lea custom_record+$120(pc),a0
        lea (LEVEL_RECORD+$120).l,a1
        move.w d2,d3
        sub.w d0,d3                     ; the pieces from it to the marker
        subq.w #1,d3
        lsl.w #2,d0
        adda.w d0,a0
        adda.w d0,a1
        move.l (a0),d1
.record:
        move.l 4(a0),(a0)+
        move.l 4(a1),(a1)+
        dbra d3,.record
        bra.s .done
.placed:
        sub.w d2,d0
        move.l paint_count(a4),d3
        sub.w d0,d3
        subq.w #1,d3                    ; the placements after it
        lsl.w #2,d0
        lea placements(pc),a0
        adda.w d0,a0
        move.l (a0),d1
        bra.s .next
.move:  move.l 4(a0),(a0)+
.next:  dbra d3,.move
        subq.l #1,paint_count(a4)
.done:  addq.w #1,remaining(a4)
        movem.l (sp)+,d0/d2-d3/a0-a1
        rts

; D0: number in the level's list, D1: a piece. Put it into the list at that
; number: into the record and the game's copy when the number is not beyond
; the record's pieces, otherwise into the placements.
terrain_put:
        movem.l d0/d2-d4/a0-a1,-(sp)
        bsr.s record_count
        cmp.w d2,d0
        bhi.s .placed
        lea custom_record+$120(pc),a0
        lea (LEVEL_RECORD+$120).l,a1
        move.w d2,d3
        lsl.w #2,d3                     ; the end marker
        move.w d0,d4
        lsl.w #2,d4
.up:    move.l 0(a0,d3.w),4(a0,d3.w)
        move.l 0(a1,d3.w),4(a1,d3.w)
        subq.w #4,d3
        cmp.w d4,d3
        bge.s .up
        move.l d1,0(a0,d4.w)
        move.l d1,0(a1,d4.w)
        bra.s .done
.placed:
        sub.w d2,d0
        lsl.w #2,d0
        move.l paint_count(a4),d3
        lsl.w #2,d3
        lea placements(pc),a0
.pup:   subq.w #4,d3
        cmp.w d0,d3
        blt.s .put
        move.l 0(a0,d3.w),4(a0,d3.w)
        bra.s .pup
.put:   move.l d1,0(a0,d0.w)
        addq.l #1,paint_count(a4)
.done:  subq.w #1,remaining(a4)
        movem.l (sp)+,d0/d2-d4/a0-a1
        rts
