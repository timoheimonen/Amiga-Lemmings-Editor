; Lemmings In-Game Level Editor V2.2
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Steel areas of a custom level. T in the editor, while a custom level is
; edited, switches between the brush and steel areas. In steel mode a drag
; with the left button adds an area of 4 x 4 pixel cells (at most 16 x 16
; cells, inside the attribute grid, at most 32 areas) and the right button
; removes the area under the cursor. The areas are the ones of custom_record,
; which saving stores; the game's attribute grid follows every change
; (level_apply in params.s).
;
; The areas are outlined in the view, and the cursor cell is boxed.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

STEEL_CODE      equ 9
GRID            equ $58800              ; 408 x 42 cells, one byte each
GRID_WIDTH      equ 408
GRID_ROWS       equ 42
GAME_ROWS       equ $a3c0               ; the game's A4: row y at y * 204
VIEW_ROW        equ 44                  ; the level view, 320 x 160 from x 16
VIEW_PLANE      equ $2100

; From the frame hook in steel mode: the mouse buttons. The cursor's world
; position is in brush_x/brush_y.
steel_input:
        movem.l d0-d3,-(sp)
        move.w brush_x(a4),d2
        asr.w #2,d2                     ; cell column
        move.w brush_y(a4),d3
        asr.w #2,d3                     ; grid row
        btst #2,$16(a6)
        seq d0
        cmp.b last_right(a4),d0
        beq.s .left
        move.b d0,last_right(a4)
        tst.b d0
        beq.s .left
        move.w d2,d0
        move.w d3,d1
        bsr steel_remove
        st dirty(a4)
.left:  btst #6,$bfe001
        seq d0
        cmp.b last_left(a4),d0
        beq.s .done
        move.b d0,last_left(a4)
        st dirty(a4)
        tst.b d0
        beq.s .release
        cmpi.w #160,($9dac).l
        bhs.s .done                     ; not over the panel
        move.w d2,drag_col(a4)
        move.w d3,drag_row(a4)
        st steel_drag(a4)
        bra.s .done
.release:
        tst.b steel_drag(a4)
        beq.s .done
        clr.b steel_drag(a4)
        move.w drag_col(a4),d0
        move.w drag_row(a4),d1
        bsr steel_add
.done:  movem.l (sp)+,d0-d3
        rts

; D0/D1: the first corner (column, grid row), D2/D3: the other. Return the
; area between them in D0/D1 (first column and row) and D2/D3 (last ones):
; at most 16 cells each way from the first corner, then inside the grid
; (columns 0..407, rows 1..41). N set when nothing of it is inside.
; Clobbers D4.
steel_corners:
        move.w d0,d4                    ; the other corner within 15 cells
        sub.w #15,d4
        cmp.w d4,d2
        bge.s .left
        move.w d4,d2
.left:  add.w #30,d4
        cmp.w d4,d2
        ble.s .rows
        move.w d4,d2
.rows:  move.w d1,d4
        sub.w #15,d4
        cmp.w d4,d3
        bge.s .top
        move.w d4,d3
.top:   add.w #30,d4
        cmp.w d4,d3
        ble.s .order
        move.w d4,d3
.order: cmp.w d0,d2                     ; D0 <= D2
        bge.s .cols
        exg d0,d2
.cols:  cmp.w d1,d3
        bge.s .grid
        exg d1,d3
.grid:  tst.w d0
        bpl.s .x0
        moveq #0,d0
.x0:    cmp.w #GRID_WIDTH-1,d2
        ble.s .x1
        move.w #GRID_WIDTH-1,d2
.x1:    cmp.w #1,d1                     ; row 0 cannot be steel
        bge.s .y0
        moveq #1,d1
.y0:    cmp.w #GRID_ROWS-1,d3
        ble.s .y1
        moveq #GRID_ROWS-1,d3
.y1:    cmp.w d0,d2
        blt.s .none
        cmp.w d1,d3
        blt.s .none
        moveq #0,d4                     ; N clear
        rts
.none:  moveq #-1,d4
        rts

; D0/D1: the first corner (column, row), D2/D3: the other. Add the area
; between them (steel_corners).
steel_add:
        movem.l d0-d7/a0,-(sp)
        bsr.s steel_corners
        bmi.s .done
        sub.w d0,d2                     ; width - 1
        sub.w d1,d3                     ; height - 1
        lea custom_record+$760(pc),a0
        moveq #31,d4
.free:  tst.l (a0)
        beq.s .store
        addq.l #4,a0
        dbra d4,.free
        bra.s .done                     ; 32 areas already
.store: bsr.s steel_undo
        lsl.w #7,d0
        subq.w #1,d1
        or.w d1,d0
        move.w d0,(a0)+
        lsl.w #4,d2
        or.w d3,d2
        lsl.w #8,d2
        move.w d2,(a0)
        bsr level_apply
.done:  movem.l (sp)+,d0-d7/a0
        rts

; Take the steel areas for undo before an edit of them. Preserves every
; register.
steel_undo:
        movem.l d0-d1/a0,-(sp)
        movea.w #$760,a0
        move.w #$80,d0
        moveq #0,d1
        bsr undo_record
        movem.l (sp)+,d0-d1/a0
        rts

; D0/D1: column and row. Remove the last area that covers the cell.
steel_remove:
        movem.l d0-d7/a0,-(sp)
        lea custom_record+$760+31*4(pc),a0
        moveq #31,d7
.area:  bsr.s steel_bounds
        bmi.s .next
        cmp.w d2,d0
        blt.s .next
        cmp.w d4,d0
        bgt.s .next
        cmp.w d3,d1
        blt.s .next
        cmp.w d5,d1
        bgt.s .next
        bsr.s steel_undo
        clr.l (a0)
        bsr level_apply
        bra.s .done
.next:  subq.l #4,a0
        dbra d7,.area
.done:  movem.l (sp)+,d0-d7/a0
        rts

; A0: a steel area. Return its first and last column in D2/D4 and grid row
; in D3/D5 (rows y + 1 .. y + height), or N set for an empty record.
steel_bounds:
        move.w (a0),d2
        move.w 2(a0),d5
        move.w d2,d3
        or.w d5,d3
        bne.s .used
        moveq #-1,d3
        rts
.used:  move.w d2,d3
        lsr.w #7,d2
        and.w #127,d3
        addq.w #1,d3
        move.w d5,d4
        rol.w #4,d4
        and.w #15,d4
        add.w d2,d4
        lsr.w #8,d5
        and.w #15,d5
        add.w d3,d5
        tst.w d2                        ; N clear
        rts

; From the overlay: outline every area, the area being dragged and the
; cursor cell in the view's back buffer.
steel_draw:
        movem.l d0-d7/a0-a1,-(sp)
        lea custom_record+$760(pc),a0
        moveq #31,d7
.area:  bsr steel_bounds
        bmi.s .next
        bsr.s steel_cells
.next:  addq.l #4,a0
        dbra d7,.area
        move.w brush_x(a4),d2
        asr.w #2,d2
        move.w brush_y(a4),d3
        asr.w #2,d3
        tst.b steel_drag(a4)
        beq.s .cursor
        move.w drag_col(a4),d0          ; the area the release would add
        move.w drag_row(a4),d1
        bsr steel_corners
        bmi.s .done
        move.w d2,d4
        move.w d3,d5
        move.w d0,d2
        move.w d1,d3
        bsr.s steel_cells
        bra.s .done
.cursor:
        cmpi.w #160,($9dac).l
        bhs.s .done
        move.w d2,d4
        move.w d3,d5
        bsr.s steel_cells
.done:  movem.l (sp)+,d0-d7/a0-a1
        rts

; D2/D4: first and last column, D3/D5: first and last grid row. Outline the
; cells in the view: world x = column * 4, world y = row * 4; view x = world
; x - scroll, view y = world y - 4.
steel_cells:
        movem.l d2-d5,-(sp)
        lsl.w #2,d2
        sub.w ($9da8).l,d2              ; left
        addq.w #1,d4
        lsl.w #2,d4
        subq.w #1,d4
        sub.w ($9da8).l,d4              ; right
        lsl.w #2,d3
        subq.w #4,d3                    ; top
        addq.w #1,d5
        lsl.w #2,d5
        subq.w #5,d5                    ; bottom
        bsr.s outline_box
        movem.l (sp)+,d2-d5
        rts

; D2/D3: left and top, D4/D5: right and bottom view pixel. Invert the border
; of the box in the view's back buffer, where it is visible.
outline_box:
        movem.l d0-d7,-(sp)
        move.w d2,d0
.top:   move.w d3,d1
        bsr.s steel_plot
        move.w d5,d1
        bsr.s steel_plot
        addq.w #1,d0
        cmp.w d4,d0
        ble.s .top
        move.w d3,d1
        addq.w #1,d1
.side:  cmp.w d5,d1
        bge.s .done
        move.w d2,d0
        bsr.s steel_plot
        move.w d4,d0
        bsr.s steel_plot
        addq.w #1,d1
        bra.s .side
.done:  movem.l (sp)+,d0-d7
        rts

; D0/D1: view pixel. Invert it in all four planes when it is visible.
steel_plot:
        cmp.w #16,d0
        blt.s .out
        cmp.w #335,d0
        bgt.s .out
        tst.w d1
        bmi.s .out
        cmp.w #159,d1
        bgt.s .out
        movem.l d0-d2/a0,-(sp)
        movea.l $cc(a5),a0
        move.w d1,d2
        mulu #VIEW_ROW,d2
        adda.l d2,a0
        move.w d0,d2
        lsr.w #3,d2
        adda.w d2,a0
        not.w d0
        and.w #7,d0                     ; bit 7 - (x & 7)
        bchg d0,(a0)
        bchg d0,VIEW_PLANE(a0)
        bchg d0,2*VIEW_PLANE(a0)
        bchg d0,3*VIEW_PLANE(a0)
        movem.l (sp)+,d0-d2/a0
.out:   rts
