; Lemmings In-Game Level Editor V2.1.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Objects of a custom level. O in the editor switches between the terrain
; brush and the objects. The left and right arrows choose an object of the
; level's graphics style and F its drawing mode; the object follows the
; cursor. The left button places it, or, pressed on an object, moves that
; object while it is held; the right button deletes the object under the
; cursor. Every object is outlined. With snap on (G), a placed or moved
; object joins the side of the nearest object of the same type.
;
; Objects keep their slots in custom_record. A new object takes a free slot:
; one with a trigger area (an exit, a trap) the lowest of the first 16 slots,
; the only ones the game gives trigger cells ($2476), any other the lowest of
; slots 16..31, or of the first 16 when these are full. A position must stay
; inside the game's limits: x > 0 (x = 0 is an empty slot), y >= 0 and, in the
; first 16 slots, the trigger area inside the attribute grid; at most four
; entrances. The top must also be above the panel (y < 160), so that the
; object can be selected again. After every change level_apply sets the game
; up from the record.
;
; The game draws each object with its record position as x - scroll and y in
; the view's back buffer ($23D8, $2414); the preview uses the same blitter
; routine ($704C) and the same coordinates.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

OBJECTS         equ $c5c6               ; the game's copy of the objects
OBJECT_DESC     equ $70                 ; descriptors in the style's leveldata
OBJECT_SIZE     equ $22
MAX_ENTRANCES   equ 4

; D0: object type. Return its descriptor in A0.
object_desc:
        movea.l $fc(a5),a0
        lea OBJECT_DESC(a0),a0
        mulu #OBJECT_SIZE,d0
        adda.w d0,a0
        rts

; Return the number of object types of the level's style in D0 (the
; descriptors up to the first empty one).
object_count:
        movem.l d1/a0,-(sp)
        moveq #0,d0
.type:  movem.l d0,-(sp)
        bsr.s object_desc
        movem.l (sp)+,d0
        moveq #OBJECT_SIZE/2-1,d1
.word:  tst.w (a0)+
        dbne d1,.word
        beq.s .done
        addq.w #1,d0
        cmp.w #16,d0
        blo.s .type
.done:  movem.l (sp)+,d1/a0
        rts

; D0: left and right arrows (signed count). Choose the object type.
object_cycle:
        tst.b d0
        beq.s .done
        ext.w d0
        move.w d0,d1
        bsr.s object_count
        add.w obj_type(a4),d1
.low:   tst.w d1
        bpl.s .high
        add.w d0,d1
        bra.s .low
.high:  cmp.w d0,d1
        blo.s .set
        sub.w d0,d1
        bra.s .high
.set:   move.w d1,obj_type(a4)
        or.b #1,status_dirty(a4)
        st dirty(a4)
.done:  rts

; F: the next drawing mode: normal, only on terrain, behind terrain, both.
object_draw_mode:
        add.w #$4000,obj_flags(a4)
        or.b #1,status_dirty(a4)
        st dirty(a4)
        rts

; From the frame hook in the objects mode: the mouse buttons.
object_input:
        movem.l d0-d7/a0-a2,-(sp)
        bsr object_hover
        moveq #0,d7
        move.b obj_drag(a4),d7
        beq.s .right
        ; The dragged object follows the cursor in the game's record.
        subq.w #1,d7
        move.w brush_x(a4),d0
        sub.w obj_dx(a4),d0
        move.w brush_y(a4),d1
        subq.w #4,d1
        sub.w obj_dy(a4),d1
        move.w d7,d3
        lsl.w #3,d7
        lea custom_record+$20(pc),a1
        move.w 4(a1,d7.w),d2
        bsr object_snap
        lea (OBJECTS).l,a1
        adda.w d7,a1
        move.w d0,(a1)
        move.w d1,2(a1)
.right: btst #2,$16(a6)
        seq d0
        cmp.b last_right(a4),d0
        beq.s .left
        move.b d0,last_right(a4)
        tst.b d0
        beq.s .left
        tst.b obj_drag(a4)
        bne.s .left
        move.w obj_hover(a4),d0
        bmi.s .left
        bsr object_undo
        lea custom_record+$20(pc),a1
        lsl.w #3,d0
        clr.l 0(a1,d0.w)                ; delete it
        clr.l 4(a1,d0.w)
        bsr level_apply
        move.w #-1,obj_hover(a4)        ; no longer under the cursor
.left:  btst #6,$bfe001
        seq d0
        cmp.b last_left(a4),d0
        beq.s .done
        move.b d0,last_left(a4)
        tst.b d0
        beq.s .release
        cmpi.w #160,($9dac).l
        bhs.s .done                     ; not over the panel
        move.w obj_hover(a4),d0
        bmi.s .place
        ; Pressed on an object: drag it.
        bsr object_undo                 ; dropped where it was, nothing to undo
        move.b d0,obj_drag(a4)
        addq.b #1,obj_drag(a4)
        lea custom_record+$20(pc),a1
        lsl.w #3,d0
        adda.w d0,a1
        move.w brush_x(a4),d0
        sub.w (a1),d0
        move.w d0,obj_dx(a4)
        move.w brush_y(a4),d0
        subq.w #4,d0
        sub.w 2(a1),d0
        move.w d0,obj_dy(a4)
        bra.s .done
.place: bsr object_place
        bra.s .done
.release:
        tst.b obj_drag(a4)
        beq.s .done
        bsr object_drop
.done:  movem.l (sp)+,d0-d7/a0-a2
        rts

; The object under the cursor: the last slot whose object covers the cursor's
; pixel, or -1. The status block shows it.
object_hover:
        movem.l d0-d7/a0-a1,-(sp)
        moveq #-1,d7
        move.w ($9daa).l,d2
        add.w #16,d2                    ; cursor in the back buffer
        move.w ($9dac).l,d3
        cmp.w #160,d3
        bhs.s .found
        lea (OBJECTS+31*8).l,a1
        moveq #31,d6
.slot:  move.w (a1),d4
        beq.s .next
        sub.w ($9da8).l,d4              ; left
        move.w 2(a1),d5                 ; top
        move.w 4(a1),d0
        bsr object_desc
        cmp.w d4,d2
        blt.s .next
        cmp.w d5,d3
        blt.s .next
        add.w 6(a0),d4
        cmp.w d4,d2
        bge.s .next
        add.w 8(a0),d5
        cmp.w d5,d3
        bge.s .next
        move.w d6,d7
        bra.s .found
.next:  subq.l #8,a1
        dbra d6,.slot
.found: cmp.w obj_hover(a4),d7
        beq.s .done
        move.w d7,obj_hover(a4)
        or.b #1,status_dirty(a4)
        st dirty(a4)                    ; the preview shows only off objects
.done:  movem.l (sp)+,d0-d7/a0-a1
        rts

; Place an object of the selected type, centred on the cursor, into a free
; slot if it fits there.
object_place:
        move.w obj_type(a4),d0
        bsr object_desc
        movea.l a0,a2
        cmp.w #1,obj_type(a4)           ; type 1 is an entrance
        bne.s .slot
        lea custom_record+$20(pc),a1    ; every slot of type 1 counts, as
        moveq #31,d1                    ; for the game's entrance table
        moveq #0,d2
.entrance:
        cmpi.w #1,4(a1)
        bne.s .other
        addq.w #1,d2
.other: addq.l #8,a1
        dbra d1,.entrance
        cmp.w #MAX_ENTRANCES,d2
        bhs.s .done
.slot:  ; The lowest free slot: of the first 16 for a trigger area,
        ; otherwise from slot 16 on, then of the first 16.
        lea custom_record+$20(pc),a1
        moveq #0,d3
        tst.w $18(a2)
        bne.s .first
        moveq #16,d3
.free:  move.w d3,d0
        lsl.w #3,d0
        tst.w 0(a1,d0.w)
        beq.s .found
        addq.w #1,d3
        cmp.w #32,d3
        blo.s .free
        moveq #0,d3
.first: move.w d3,d0
        lsl.w #3,d0
        tst.w 0(a1,d0.w)
        beq.s .found
        addq.w #1,d3
        cmp.w #16,d3
        blo.s .first
        bra.s .done
.found: move.w 6(a2),d0
        lsr.w #1,d0
        neg.w d0
        add.w brush_x(a4),d0
        move.w 8(a2),d1
        lsr.w #1,d1
        neg.w d1
        add.w brush_y(a4),d1
        subq.w #4,d1
        move.w obj_type(a4),d2
        move.w d3,-(sp)
        moveq #-1,d3
        bsr object_snap
        move.w (sp)+,d3
        bsr object_fits
        bne.s .done
        bsr object_undo
        move.w d3,d4
        lsl.w #3,d4
        adda.w d4,a1
        move.w d0,(a1)+
        move.w d1,(a1)+
        move.w d2,(a1)+
        move.w obj_flags(a4),(a1)
        bsr level_apply
.done:  rts

; M: put the two-player marker (object type 2; the game's marker is the
; first slot of type 2, empty or not, $2D80) beside the exit under the cursor,
; where the game's own two-player levels have it: 16 pixels right of and 24
; above the exit, which makes that exit the green player's
; (two_player_level). The first slot of type 2 moves there; without one, a new
; one takes a free slot from 16 on (it has no trigger area), then of the
; first 16.
object_marker:
        movem.l d0-d4/a0-a2,-(sp)
        move.w obj_hover(a4),d0
        bmi .done
        lea custom_record+$20(pc),a1
        lsl.w #3,d0
        lea 0(a1,d0.w),a2
        tst.w (a2)                      ; deleted since the cursor was on it
        beq .done
        move.w 4(a2),d0
        bsr object_desc
        cmpi.w #1,$18(a0)               ; an exit
        bne.s .done
        move.w (a2),d0
        add.w #16,d0
        move.w 2(a2),d1
        sub.w #24,d1
        bpl.s .find
        moveq #0,d1
.find:  moveq #0,d3
.marker:
        move.w d3,d4
        lsl.w #3,d4
        cmpi.w #2,4(a1,d4.w)
        beq.s .put
        addq.w #1,d3
        cmp.w #32,d3
        blo.s .marker
        moveq #16,d3
.free:  move.w d3,d4
        lsl.w #3,d4
        tst.w 0(a1,d4.w)
        beq.s .put
        addq.w #1,d3
        cmp.w #32,d3
        blo.s .free
        moveq #0,d3
.first: move.w d3,d4
        lsl.w #3,d4
        tst.w 0(a1,d4.w)
        beq.s .put
        addq.w #1,d3
        cmp.w #16,d3
        blo.s .first
        bra.s .done
.put:   moveq #2,d2
        bsr object_fits
        bne.s .done
        bsr object_undo
        lea 0(a1,d4.w),a0
        tst.w (a0)                      ; an empty slot becomes a marker
        bne.s .move                     ; drawn normally
        move.w d2,4(a0)
        move.w #$000f,6(a0)
.move:  move.w d0,(a0)+
        move.w d1,(a0)
        bsr level_apply
.done:  movem.l (sp)+,d0-d4/a0-a2
        rts

; Take the objects for undo before an edit of them. Preserves every register.
object_undo:
        movem.l d0-d1/a0,-(sp)
        movea.w #$20,a0
        move.w #$100,d0
        moveq #0,d1
        bsr undo_record
        movem.l (sp)+,d0-d1/a0
        rts

; The dragged object is released: keep its new position if it fits there,
; otherwise it goes back.
object_drop:
        moveq #0,d3
        move.b obj_drag(a4),d3
        clr.b obj_drag(a4)
        subq.w #1,d3
        move.w d3,d4
        lsl.w #3,d4
        lea (OBJECTS).l,a1
        move.w 0(a1,d4.w),d0
        move.w 2(a1,d4.w),d1
        lea custom_record+$20(pc),a1
        move.w 4(a1,d4.w),d2
        bsr object_fits
        bne.s .back
        move.w d0,0(a1,d4.w)
        move.w d1,2(a1,d4.w)
.back:  bra level_apply

; D0/D1: position (top left corner) of an object of type D2, D3: its slot or
; -1. With snap on, return the position beside the nearest other object of the
; same type (snap_near) instead, when the position is near one. The opaque
; part of the type's first frame decides where two objects touch.
object_snap:
        tst.b snap(a4)
        beq .done
        movem.l d2-d7/a0-a3,-(sp)
        move.w d0,d4
        move.w d1,d5
        lea custom_record+$20(pc),a1
        suba.l a3,a3                    ; the slot to skip, if any
        tst.w d3
        bmi.s .size
        move.w d3,d6
        lsl.w #3,d6
        lea 0(a1,d6.w),a3
.size:  movea.w d2,a2
        move.w d2,d0
        bsr object_desc
        move.w 6(a0),d2
        move.w 8(a0),d3
        move.w 2(a0),d6                 ; the mask of its first frame
        mulu $a(a0),d6
        movea.l $1a(a0),a1
        adda.l d6,a1
        adda.w $c(a0),a1
        movea.l a1,a0
        move.w a2,d0
        add.w #$100,d0
        bsr snap_bounds
        move.w snap_ys(a4),d0           ; objects are never flipped
        move.w snap_ye(a4),d1
        move.w d0,d6
        move.w d1,d7
        lea snap_rows(a4),a0
        bsr snap_offsets
        movea.l a3,a0                   ; the slot to skip
        lea snap_rows(a4),a3
        lsr.w #1,d2
        lsr.w #1,d3
        moveq #-1,d6
        lea custom_record+$20(pc),a1
        pea 32*8(a1)                    ; the end of the objects
.slot:  cmpa.l a0,a1
        beq.s .next
        tst.w (a1)
        beq.s .next
        cmpa.w 4(a1),a2
        bne.s .next
        move.w (a1),d0
        move.w 2(a1),d1
        move.w d0,d7                    ; out of reach?
        sub.w d4,d7
        bpl.s .dx
        neg.w d7
.dx:    cmp.w snap_reach_x(a4),d7
        bhi.s .next
        move.w d1,d7
        sub.w d5,d7
        bpl.s .dy
        neg.w d7
.dy:    cmp.w snap_reach_y(a4),d7
        bhi.s .next
        bsr snap_near
.next:  addq.l #8,a1
        cmpa.l (sp),a1
        blo.s .slot
        addq.l #4,sp
        move.w d4,d0
        move.w d5,d1
        cmp.w #-1,d6
        beq.s .keep
        move.w snap_x(a4),d0
        move.w snap_y(a4),d1
.keep:  movem.l (sp)+,d2-d7/a0-a3
.done:  rts

; D0/D1: position, D2: type, D3: slot. Z set when the object fits there:
; its top inside the rows of the view, where it can be selected again.
object_fits:
        movem.l d0-d2/a0,-(sp)
        tst.w d0
        ble.s .bad
        tst.w d1
        bmi.s .bad
        cmp.w #160,d1
        bge.s .bad
        cmp.w #16,d3
        bhs.s .good
        move.w d0,-(sp)
        move.w d2,d0
        bsr object_desc
        move.w (sp)+,d0
        lsr.w #2,d0
        add.w $10(a0),d0
        add.w $14(a0),d0
        cmp.w #408,d0
        bhi.s .bad
        lsr.w #2,d1
        add.w $12(a0),d1
        add.w $16(a0),d1
        cmp.w #42,d1
        bhi.s .bad
.good:  moveq #0,d0
        bra.s .done
.bad:   moveq #-1,d0
.done:  movem.l (sp)+,d0-d2/a0
        rts

; From the overlay: the selected object at the cursor, unless the cursor is on
; an object or over the panel, then an outline around every object.
object_draw:
        movem.l d0-d7/a0-a3,-(sp)
        tst.b obj_drag(a4)
        bne.s .outline
        tst.w obj_hover(a4)
        bpl.s .outline
        cmpi.w #160,($9dac).l
        bhs.s .outline
        move.w obj_type(a4),d0
        bsr object_desc
        move.w brush_x(a4),d0           ; where object_place puts it
        move.w 6(a0),d6
        lsr.w #1,d6
        sub.w d6,d0
        move.w brush_y(a4),d1
        subq.w #4,d1
        move.w 8(a0),d6
        lsr.w #1,d6
        sub.w d6,d1
        move.w obj_type(a4),d2
        moveq #-1,d3
        bsr object_snap
        sub.w ($9da8).l,d0              ; into the back buffer
        move.w 6(a0),d2
        move.w 8(a0),d3
        move.w 2(a0),d6                 ; its first frame, as the game shows it
        mulu $a(a0),d6
        movea.l $1a(a0),a1
        adda.l d6,a1
        movea.l a1,a2
        adda.w $c(a0),a2                ; mask
        move.w obj_flags(a4),d5
        moveq #4,d4
        movea.l $cc(a5),a0
        jsr $704c
        tst.b 2(a6)
.blit:  btst #6,2(a6)
        bne.s .blit
.outline:
        lea (OBJECTS).l,a1
        moveq #31,d7
.slot:  move.w (a1),d2
        beq.s .next
        sub.w ($9da8).l,d2
        move.w 2(a1),d3
        move.w 4(a1),d0
        bsr object_desc
        move.w d2,d4
        add.w 6(a0),d4
        subq.w #1,d4
        move.w d3,d5
        add.w 8(a0),d5
        subq.w #1,d5
        bsr outline_box
.next:  addq.l #8,a1
        dbra d7,.slot
        movem.l (sp)+,d0-d7/a0-a3
        rts

; From custom_status: the objects mode's values.
object_status:
        move.w obj_type(a4),d0
        moveq #0,d1
        moveq #20,d2
        bsr status_number
        moveq #1,d1                     ; valid for two players
        movem.l d2,-(sp)
        add.w #12,d2
        bsr status_cell
        lea custom_record(pc),a0
        lea txt_no(pc),a2
        bsr two_player_level
        bne.s .players
        lea txt_yes(pc),a2
.players:
        bsr.s .text
        movem.l (sp)+,d2
        moveq #2,d1
        move.w obj_hover(a4),d0
        bmi.s .none
        bsr status_number
        bra.s .used
.none:  movem.l d2,-(sp)
        add.w #12,d2
        bsr status_cell
        lea txt_none(pc),a2
        bsr.s .text
        movem.l (sp)+,d2
.used:  lea custom_record+$20(pc),a1
        moveq #31,d1
        moveq #0,d0
.slot:  tst.w (a1)
        beq.s .free
        addq.w #1,d0
.free:  addq.l #8,a1
        dbra d1,.slot
        moveq #3,d1
        bsr status_number
        moveq #52,d2
        bsr status_cell
        move.w obj_flags(a4),d0
        rol.w #2,d0
        and.w #3,d0
        mulu #9,d0
        lea txt_draw_modes(pc),a2
        adda.w d0,a2
.text:  moveq #0,d0
        move.b (a2)+,d0
        beq.s .done
        bsr glyph
        addq.w #8,d4
        bra.s .text
.done:  rts

txt_none:       dc.b 'None',0
txt_yes:        dc.b 'Yes ',0
txt_no:         dc.b 'No  ',0
; Drawing modes by flag bits 15..14: $000F, $400F, $800F, $C00F.
txt_draw_modes: dc.b 'Normal ',0,0,'Terrain',0,0,'Behind ',0,0,'Both   ',0,0
        even
