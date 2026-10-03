; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Undo and redo. U undoes the last edit of the level, Shift+U redoes the last
; undone one, up to UNDO_STEPS steps. The history keeps the entries in order
; in undo_entries: undo_count of them can be undone, the redo_count after
; them redone. An entry is swapped, not copied: undoing it puts the level's
; current state into it, so the same entry redoes it. A new edit drops the
; entries that could have been redone; an edit that changes nothing leaves
; the history as it is. The history survives test plays and saving; opening a
; level from the list clears it.
;
; Two kinds of entries:
; - A range of custom_record (the header, the objects, the steel areas or the
;   title), taken by undo_record before the edit into the spare entry after
;   the history. level_apply puts it into the history when the edit changed
;   the range and forgets it otherwise. Changes of one parameter in a row
;   share one entry (the tag); an undo, a redo, a save or a level start ends
;   the row (undo_break).
; - A terrain piece. Pieces are appended to the level, so undoing one removes
;   the level's last piece (the last placement, or after a test play or a
;   save the record's last one) and rebuilds the terrain under it; redoing it
;   appends it again.
; - A deleted terrain piece and its number in the level's list (delete.s).
;   Undoing it puts the piece back at that number, redoing it deletes it
;   again; the terrain under it is rebuilt.
; The history is undone in order, so the level's list is always as it was
; right after the edit whose entry is undone.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

UNDO_STEPS      equ 3
UNDO_DATA       equ 256                 ; the largest range: the objects
UNDO_ENTRY      equ 8+UNDO_DATA         ; kind, offset, length, tag, data
UNDO_RANGE      equ 1
UNDO_PIECE      equ 2
UNDO_DELETE     equ 3
UNDO_TAKEN      equ 1                   ; undo_open: the range is in the spare entry
UNDO_MERGED     equ 2                   ; undo_open: it shares the top entry
UNDO_LOST_OLDEST equ 1                  ; undo_lost: the oldest entry, dropped
UNDO_LOST_NEXT  equ 2                   ; undo_lost: the first redo entry, overwritten

; A0: offset of the range in custom_record, D0: its length (at most
; UNDO_DATA), D1: tag, nonzero for changes that share an entry with the
; previous change of the same tag. Take the range before an edit.
undo_record:
        movem.l d0-d2/a0-a2,-(sp)
        tst.w d1
        beq .new
        tst.b redo_count(a4)
        bne .new
        moveq #0,d2
        move.b undo_count(a4),d2
        beq .new
        subq.w #1,d2
        bsr undo_entry
        cmpi.w #UNDO_RANGE,(a1)
        bne .new
        cmp.w 6(a1),d1
        bne .new
        move.b #UNDO_MERGED,undo_open(a4) ; the same parameter again
        bra .done
.new:   moveq #UNDO_STEPS,d2            ; the spare entry
        bsr undo_entry
        move.w #UNDO_RANGE,(a1)+
        move.w a0,(a1)+
        move.w d0,(a1)+
        move.w d1,(a1)+
        lea custom_record(pc),a2
        adda.w a0,a2
        subq.w #1,d0
.copy:  move.b (a2)+,(a1)+
        dbra d0,.copy
        move.b #UNDO_TAKEN,undo_open(a4)
.done:  movem.l (sp)+,d0-d2/a0-a2
        rts

; After a piece has been placed: an entry for it.
undo_piece:
        movem.l d0-d2/a0-a2,-(sp)
        tst.w (LEVEL_RECORD+$1c).l                 ; a special background has no pieces
        bne .done
        bsr undo_new
        move.w #UNDO_PIECE,(a1)
        clr.b undo_open(a4)
.done:  movem.l (sp)+,d0-d2/a0-a2
        rts

; After a piece has been deleted: D0 its number in the level's list, D1 the
; piece. An entry for it.
undo_deleted:
        movem.l d2/a1-a2,-(sp)
        bsr.s undo_new
        move.w #UNDO_DELETE,(a1)
        move.w d0,2(a1)
        clr.w 6(a1)
        move.l d1,8(a1)
        clr.b undo_open(a4)
        movem.l (sp)+,d2/a1-a2
        rts

; A new entry at the top of the history, in A1. Drops the redo entries and,
; when the history is full, its oldest entry. The entry it drops or
; overwrites is kept in undo_lost with the redo count, so that a row of
; changes that ends where it started can give it back (undo_check).
; Clobbers D2/A1-A2.
undo_new:
        move.b redo_count(a4),undo_lost_redo(a4)
        clr.b redo_count(a4)
        moveq #0,d2
        move.b undo_count(a4),d2
        cmp.w #UNDO_STEPS,d2
        blo .next
        move.b #UNDO_LOST_OLDEST,undo_lost_kind(a4)
        moveq #0,d2
        bsr.s undo_keep
        lea undo_entries(pc),a1         ; move the others down one entry
        lea UNDO_ENTRY(a1),a2
        move.w #(UNDO_STEPS-1)*UNDO_ENTRY/2-1,d2
.move:  move.w (a2)+,(a1)+
        dbra d2,.move
        moveq #UNDO_STEPS-1,d2
        move.b d2,undo_count(a4)
        bra.s .top
.next:  move.b #UNDO_LOST_NEXT,undo_lost_kind(a4)
        bsr.s undo_keep
.top:   addq.b #1,undo_count(a4)

; D2: entry number. Return its address in A1.
undo_entry:
        lea undo_entries(pc),a1
        mulu #UNDO_ENTRY,d2
        adda.l d2,a1
        rts

; D2: entry number. Keep a copy of the entry in undo_lost. Clobbers A1-A2.
undo_keep:
        move.w d2,-(sp)
        bsr.s undo_entry
        lea undo_lost(pc),a2
        move.w #UNDO_ENTRY/2-1,d2
.copy:  move.w (a1)+,(a2)+
        dbra d2,.copy
        move.w (sp)+,d2
        rts

; From level_apply: settle the range taken for the edit. A range the edit
; changed goes into the history; one it left as it was is forgotten, and so is
; a shared top entry that the changes have brought back to its state.
undo_check:
        tst.b undo_open(a4)
        beq .done
        movem.l d0-d2/a0-a2,-(sp)
        moveq #UNDO_STEPS,d2            ; the spare entry
        cmpi.b #UNDO_MERGED,undo_open(a4)
        bne.s .entry
        moveq #0,d2                     ; the top entry
        move.b undo_count(a4),d2
        beq.s .end
        subq.w #1,d2
.entry: bsr undo_entry
        lea custom_record(pc),a2
        adda.w 2(a1),a2
        move.w 4(a1),d0
        subq.w #1,d0
        lea 8(a1),a0
.compare:
        cmpm.b (a0)+,(a2)+
        bne.s .changed
        dbra d0,.compare
        cmpi.b #UNDO_MERGED,undo_open(a4)
        bne.s .end
        subq.b #1,undo_count(a4)
        bsr.s undo_give_back
        bra.s .end
.changed:
        cmpi.b #UNDO_TAKEN,undo_open(a4)
        bne.s .end
        bsr.s undo_commit
.end:   clr.b undo_open(a4)
        movem.l (sp)+,d0-d2/a0-a2
.done:  rts

; The shared top entry of a row of changes was forgotten: the row ended where
; it started. Give back the entry that its first change dropped or overwrote
; (undo_new), and the redo steps. Clobbers D0-D2/A0-A2.
undo_give_back:
        move.b undo_lost_kind(a4),d0
        beq.s .done
        clr.b undo_lost_kind(a4)
        moveq #0,d2
        move.b undo_count(a4),d2
        cmp.b #UNDO_LOST_OLDEST,d0
        bne.s .put
        moveq #0,d1                     ; the entries up one place
        move.b d2,d1
        mulu #UNDO_ENTRY/2,d1
        bsr undo_entry
        lea UNDO_ENTRY(a1),a2
        bra.s .more
.up:    move.w -(a1),-(a2)
.more:  dbra d1,.up
        addq.b #1,undo_count(a4)
        moveq #0,d2                     ; and the oldest one first
.put:   bsr undo_entry
        lea undo_lost(pc),a0
        move.w #UNDO_ENTRY/2-1,d1
.copy:  move.w (a0)+,(a1)+
        dbra d1,.copy
        move.b undo_lost_redo(a4),redo_count(a4)
.done:  rts

; Put the spare entry on top of the history. Preserves every register.
undo_commit:
        movem.l d2/a1-a2,-(sp)
        bsr undo_new
        lea undo_entries+UNDO_STEPS*UNDO_ENTRY(pc),a2
        move.w #UNDO_ENTRY/2-1,d2
.copy:  move.w (a2)+,(a1)+
        dbra d2,.copy
        movem.l (sp)+,d2/a1-a2
        rts

; Clear the history (a level opened from the list).
undo_clear:
        clr.b undo_count(a4)
        clr.b redo_count(a4)
        clr.b undo_open(a4)
        clr.b undo_lost_kind(a4)
        rts

; From the frame hook: D0 = 1 undo, 2 redo. Not while an object or a steel
; area is being dragged.
undo_key:
        tst.b obj_drag(a4)
        bne .done
        tst.b steel_drag(a4)
        bne .done
        movem.l d0-d7/a0-a3,-(sp)
        moveq #0,d2
        cmp.b #1,d0
        bne .redo
        move.b undo_count(a4),d2
        beq .end
        subq.b #1,d2
        move.b d2,undo_count(a4)
        addq.b #1,redo_count(a4)
        bsr undo_entry
        cmpi.w #UNDO_PIECE,(a1)
        bne.s .put
        bsr terrain_pop
        move.l d0,8(a1)
        cmp.l #-1,d0                    ; no piece; a behind piece is
        beq .lost                       ; negative as a long
        bsr terrain_rebuild
        bra .end
.put:   cmpi.w #UNDO_DELETE,(a1)        ; a deleted piece back at its place
        bne .swap
        moveq #0,d0
        move.w 2(a1),d0
        bsr pieces_count
        cmp.w d2,d0                     ; at most after the last piece,
        bhi .lost
        tst.w remaining(a4)             ; with room for it
        beq .lost
        move.l 8(a1),d1
        bsr terrain_put
        move.l d1,d0
        bsr terrain_rebuild
        bra .end
.redo:  move.b redo_count(a4),d1
        beq .end
        move.b undo_count(a4),d2
        addq.b #1,undo_count(a4)
        subq.b #1,redo_count(a4)
        bsr undo_entry
        cmpi.w #UNDO_PIECE,(a1)
        bne.s .take
        move.l 8(a1),d0
        cmp.l #-1,d0
        beq .lost
        tst.w remaining(a4)
        beq .lost
        bsr terrain_push
        bra .end
.take:  cmpi.w #UNDO_DELETE,(a1)        ; the piece deleted again
        bne .swap
        moveq #0,d0
        move.w 2(a1),d0
        bsr pieces_count
        cmp.w d2,d0
        bhs .lost
        bsr terrain_take
        move.l d1,d0
        bsr terrain_rebuild
        bra .end
.swap:  movea.l a1,a3
        lea custom_record(pc),a2        ; exchange the range with the record
        adda.w 2(a1),a2
        move.w 4(a1),d0
        subq.w #1,d0
        lea 8(a1),a1
.byte:  move.b (a2),d1
        move.b (a1),(a2)+
        move.b d1,(a1)+
        dbra d0,.byte
        clr.b undo_open(a4)
        bsr level_apply
        tst.w 2(a3)                     ; the header: a new start position
        bne.s .end                      ; scrolls the view there, as a change
        move.w custom_record+$18(pc),d0 ; of the parameter does
        cmp.w 8+$18(a3),d0
        beq.s .end
        move.w d0,(VIEW_SCROLL).l
        bra.s .end
        ; The history no longer matches the level's pieces (never expected,
        ; the steps are undone in order): it is dropped.
.lost:  bsr undo_clear
.end:   bsr.s undo_break
        or.b #1,status_dirty(a4)
        st dirty(a4)
        movem.l (sp)+,d0-d7/a0-a3
.done:  rts

; D2: the level's pieces, those of the record and the placements.
pieces_count:
        bsr record_count
        add.w paint_count+2(a4),d2
        rts

; End the row of changes that share the top entry, so that the next change
; of a parameter takes an entry of its own. Preserves every register.
undo_break:
        movem.l d2/a1,-(sp)
        moveq #0,d2
        move.b undo_count(a4),d2
        beq.s .done
        subq.w #1,d2
        bsr undo_entry
        clr.w 6(a1)                     ; the tag
.done:  movem.l (sp)+,d2/a1
        rts

; Remove the level's last terrain piece: the last placement, otherwise the
; last piece of the record (also in the game's copy of it). Return it in D0,
; or -1 when the level has no piece.
terrain_pop:
        movem.l d1/a0-a1,-(sp)
        move.l paint_count(a4),d1
        beq .record
        subq.l #1,d1
        move.l d1,paint_count(a4)
        lsl.w #2,d1
        lea placements(pc),a0
        move.l 0(a0,d1.w),d0
        bra .found
.record:
        lea custom_record+$120(pc),a0
        moveq #0,d1
.end:   cmpi.l #-1,0(a0,d1.w)
        beq .last
        addq.w #4,d1
        bra .end
.last:  moveq #-1,d0
        tst.w d1
        beq .done
        subq.w #4,d1
        move.l 0(a0,d1.w),d0
        move.l #-1,0(a0,d1.w)
        lea (LEVEL_RECORD+$120).l,a1
        move.l #-1,0(a1,d1.w)
.found: addq.w #1,remaining(a4)
.done:  movem.l (sp)+,d1/a0-a1
        rts

; D0: a terrain piece. Append it as a placement and stamp it.
terrain_push:
        movem.l d0-d7/a0-a3,-(sp)
        tst.w remaining(a4)
        beq .done
        move.l paint_count(a4),d1
        lsl.w #2,d1
        lea placements(pc),a0
        move.l d0,0(a0,d1.w)
        addq.l #1,paint_count(a4)
        subq.w #1,remaining(a4)
        bsr brush_save
        bsr piece_brush
        moveq #0,d2
        bsr composite
        bsr brush_restore
        jsr CLEAR_GUARDS
        jsr MINIMAP_REFRESH
.done:  movem.l (sp)+,d0-d7/a0-a3
        rts

; D0: the terrain piece just removed. Rebuild the terrain under it: clear its
; rectangle (whole bytes, all planes, inside the level) and compose again
; every remaining piece that overlaps it, in the level's order, clipped to
; the rectangle (composite mode 2). The game's own terrain build cannot be
; used: its Ground graphics have become sound data.
terrain_rebuild:
        movem.l d0-d7/a0-a3,-(sp)
        bsr brush_save
        bsr piece_rect                  ; D0..D3: first, last byte column and row
        tst.w d0
        bpl .left
        moveq #0,d0
.left:  cmp.w #203,d1
        ble .right
        move.w #203,d1
.right: tst.w d2
        bpl .top
        moveq #0,d2
.top:   cmp.w #167,d3
        ble .bottom
        move.w #167,d3
.bottom:
        cmp.w d0,d1
        blt .restore
        cmp.w d2,d3
        blt .restore
        move.w d0,clip_lo(a4)
        move.w d1,d4
        sub.w d0,d4
        addq.w #1,d4
        move.w d4,clip_span(a4)
        move.w d2,clip_top(a4)
        move.w d3,d4
        sub.w d2,d4
        addq.w #1,d4
        move.w d4,clip_rows(a4)
        ; Clear the rectangle in the four planes.
        moveq #3,d7
        lea (TERRAIN).l,a1
.plane: move.w clip_top(a4),d5
        move.w clip_rows(a4),d6
        subq.w #1,d6
.row:   move.w d5,d4
        mulu #204,d4
        lea 0(a1,d4.l),a0
        adda.w clip_lo(a4),a0
        move.w clip_span(a4),d4
        subq.w #1,d4
.byte:  clr.b (a0)+
        dbra d4,.byte
        addq.w #1,d5
        dbra d6,.row
        adda.l #TERRAIN_PLANE,a1
        dbra d7,.plane
        ; The record's pieces, then the placements, clearing the guard rows
        ; as they were: after the level's pieces (the game's build)
        ; and after every placement (the stamp). A behind piece depends on
        ; them.
        lea custom_record+$120(pc),a2
.record:
        move.l (a2)+,d0
        cmpi.l #-1,d0
        beq .placements
        bsr .piece
        bra .record
.placements:
        bsr .guard
        lea placements(pc),a2
        move.l paint_count(a4),d6
        bra .next
.placed:
        move.l (a2)+,d0
        bsr .piece
        tst.w d7                        ; the guard rows are clear unless
        beq.s .next                     ; this placement reached them
        bsr .guard
.next:  subq.l #1,d6
        bpl .placed
        jsr MINIMAP_REFRESH
.restore:
        bsr brush_restore
        movem.l (sp)+,d0-d7/a0-a3
        rts
.guard: movem.l d6/a2/a4,-(sp)
        jsr CLEAR_GUARDS
        movem.l (sp)+,d6/a2/a4
        rts
; D0: a piece. Compose it when it overlaps the window. D7 returns nonzero
; when it was composed and reaches the guard rows (0..3, 164..167).
.piece: movem.l d0/d6/a2,-(sp)
        move.l d0,d7
        bsr piece_rect
        cmp.w clip_lo(a4),d1
        blt .skip
        move.w clip_lo(a4),d4
        add.w clip_span(a4),d4
        cmp.w d4,d0
        bge .skip
        cmp.w clip_top(a4),d3
        blt .skip
        move.w clip_top(a4),d4
        add.w clip_rows(a4),d4
        cmp.w d4,d2
        bge .skip
        moveq #1,d4
        cmp.w #4,d2
        blt.s .guarded
        cmp.w #164,d3
        bge.s .guarded
        moveq #0,d4
.guarded:
        move.w d4,-(sp)
        move.l d7,d0
        bsr piece_brush
        moveq #2,d2
        bsr composite
        move.w (sp)+,d7
        bra.s .done
.skip:  moveq #0,d7
.done:  movem.l (sp)+,d0/d6/a2
        rts

; D0: a terrain piece. Return its rectangle: D0/D1 first and last byte
; column, D2/D3 first and last row (not clipped). Clobbers A0.
piece_rect:
        movem.l d4-d5,-(sp)
        move.l d0,d4
        swap d4
        and.w #$1fff,d4                 ; x
        move.w d0,d5
        asr.w #7,d5                     ; y, signed
        and.w #$3f,d0
        movea.l G_STYLE(a5),a0
        lea $290(a0),a0
        mulu #12,d0
        adda.w d0,a0
        move.w d4,d0
        add.w (a0),d4
        subq.w #1,d4
        move.w d4,d1
        asr.w #3,d0
        asr.w #3,d1
        move.w d5,d2
        move.w d5,d3
        add.w 2(a0),d3
        subq.w #1,d3
        movem.l (sp)+,d4-d5
        rts

; D0: a terrain piece. Set the brush to it (piece, erase, flip and behind
; bits) and return in D0/D1 the centre composite takes. Clobbers D2-D3/A0.
piece_brush:
        move.l d0,d3
        swap d3
        btst #13,d3
        sne negative(a4)
        btst #14,d3
        sne flipped(a4)
        btst #15,d3
        sne behind(a4)
        and.w #$1fff,d3                 ; x
        move.w d0,d2
        asr.w #7,d2                     ; y, signed
        and.w #$3f,d0
        move.w d0,piece_id(a4)
        bsr descriptor                  ; clobbers D0/D1/A0
        move.w width(a4),d0
        lsr.w #1,d0
        add.w d3,d0
        move.w height(a4),d1
        lsr.w #1,d1
        add.w d2,d1
        rts

; Keep the brush (piece and its bits) across the drawing of other pieces.
brush_save:
        move.w piece_id(a4),undo_brush(a4)
        move.b negative(a4),undo_brush+2(a4)
        move.b flipped(a4),undo_brush+3(a4)
        move.b behind(a4),undo_brush+4(a4)
        rts
brush_restore:
        move.w undo_brush(a4),piece_id(a4)
        move.b undo_brush+2(a4),negative(a4)
        move.b undo_brush+3(a4),flipped(a4)
        move.b undo_brush+4(a4),behind(a4)
        bra descriptor
