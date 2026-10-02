; Lemmings In-Game Level Editor V2.2
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Editing a custom level: the editor's modes (terrain, steel areas, objects,
; parameters), the parameters, the status block, and test play.
;
; The editor edits a custom level only at its start, paused before the first
; lemming is released: E starts a test play of the current edits from the
; beginning, and E or Esc during the test play (or the end of the test play)
; starts the level again in the editor. Esc with the editor open leaves the
; level, asking first when it has unsaved changes. So the game's level state
; never runs ahead of
; the record: after a change of the parameters, the objects or the steel areas
; level_apply sets the game up from custom_record as a level start does.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

PARAMS          equ 13                  ; parameters in param_table

; D0: raw key press while a custom level is edited. Take the keys of the
; custom level editor: T, O and P switch modes, N edits the title, S saves,
; the up and down arrows choose a parameter. Z set when the key is not one of
; them; with the editor closed every key goes to the game.
custom_key:
        tst.b active(a4)
        beq.s .other
        moveq #1,d1
        cmp.b #$14,d0                   ; T: steel areas
        beq.s .mode
        moveq #2,d1
        cmp.b #$18,d0                   ; O: objects
        beq.s .mode
        moveq #3,d1
        cmp.b #$19,d0                   ; P: parameters
        beq.s .mode
        moveq #1,d1
        cmp.b #$21,d0                   ; S: save
        beq.s .menu
        moveq #2,d1
        cmp.b #KEY_N,d0                 ; N: title
        beq.s .menu
        cmp.b #$24,d0                   ; G: snap
        beq.s .snap
        cmp.b #$37,d0                   ; M: the two-player marker
        beq.s .marker
        cmp.b #$16,d0                   ; U: undo, with shift redo
        beq.s .undo
        moveq #-1,d1
        cmp.b #KEY_UP,d0
        beq.s .select
        moveq #1,d1
        cmp.b #KEY_DOWN,d0
        beq.s .select
.other: moveq #0,d1                     ; Z
        rts
.mode:  move.b d1,pending_mode(a4)
        rts
.menu:  move.b d1,pending_menu(a4)
        rts
.snap:  st pending_snap(a4)
        moveq #1,d1                     ; NZ
        rts
.marker:
        st pending_marker(a4)
        moveq #1,d1
        rts
.undo:  moveq #1,d1
        tst.b shift(a4)
        beq.s .undo_set
        moveq #2,d1
.undo_set:
        move.b d1,pending_undo(a4)
        rts
.select:
        add.b d1,pending_select(a4)
        moveq #1,d1                     ; NZ
        rts

; From the frame hook: T, O or P switches between the terrain brush and that
; mode. An object being dragged goes back to its place.
mode_switch:
        move.b pending_mode(a4),d0
        beq.s .done
        clr.b pending_mode(a4)
        cmp.b edit_mode(a4),d0
        bne.s .set
        moveq #0,d0
.set:   move.b d0,edit_mode(a4)
        clr.b steel_drag(a4)
        tst.b obj_drag(a4)
        beq.s .drawn
        clr.b obj_drag(a4)
        bsr level_apply
.drawn: st dirty(a4)
        st status_dirty(a4)
.done:  rts

; Before the menu takes the input: a drag in progress ends (a dragged object
; goes back to its place), and input the frame hook has not taken yet is
; dropped, so that it does not act after the menu. Preserves every register.
input_reset:
        clr.b steel_drag(a4)
        tst.b obj_drag(a4)
        beq.s .pending
        clr.b obj_drag(a4)
        bsr level_apply
.pending:
        move.w sr,-(sp)
        ori.w #$0700,sr
        clr.w pending_toggle(a4)        ; and pending_cycle
        clr.b pending_flip(a4)
        clr.b pending_select(a4)
        clr.b pending_escape(a4)
        clr.b pending_mode(a4)
        clr.b pending_menu(a4)
        clr.b pending_snap(a4)
        clr.b pending_behind(a4)
        clr.b pending_marker(a4)
        clr.b pending_undo(a4)
        move.w (sp)+,sr
        rts

; From the frame hook in the objects and parameters modes. D0: left and right
; arrows (signed count), D5: up and down arrows.
mode_keys:
        cmp.b #2,edit_mode(a4)
        beq object_cycle
        cmp.b #3,edit_mode(a4)
        bne.s .done
        bsr.s param_select
        bra.s param_change
.done:  rts

; D5: move the parameter selection, wrapping around.
param_select:
        tst.b d5
        beq.s .done
        move.b param_sel(a4),d1
        add.b d5,d1
.low:   bpl.s .high
        add.b #PARAMS,d1
        bra.s .low
.high:  cmp.b #PARAMS,d1
        blo.s .set
        sub.b #PARAMS,d1
        bra.s .high
.set:   move.b d1,param_sel(a4)
        or.b #1,status_dirty(a4)
        st dirty(a4)
.done:  rts

; D0: change the selected parameter by D0 steps (ten with shift) within the
; game's limits. To save follows a smaller number of lemmings. A new start
; position scrolls the view there.
param_change:
        tst.b d0
        beq .done
        movem.l d0-d3/a0-a1,-(sp)
        ext.w d0
        moveq #0,d1
        move.b param_sel(a4),d1
        lea param_table(pc),a0
        mulu #6,d1
        adda.w d1,a0
        moveq #0,d1
        move.b 1(a0),d1                 ; step
        tst.b shift(a4)
        beq.s .step
        mulu #10,d1
.step:  muls d1,d0
        lea custom_record(pc),a1
        moveq #0,d1
        move.b (a0),d1
        adda.w d1,a1                    ; the field
        move.w 4(a0),d2                 ; maximum, 0: the lemmings
        bne.s .max
        move.w custom_record+2(pc),d2
.max:   add.w (a1),d0
        cmp.w 2(a0),d0
        bge.s .min
        move.w 2(a0),d0
.min:   cmp.w d2,d0
        ble.s .set
        move.w d2,d0
.set:   movem.l d0-d1/a0,-(sp)          ; changes of one parameter share an entry
        suba.l a0,a0
        moveq #$1a,d0
        moveq #1,d1
        add.b param_sel(a4),d1
        bsr undo_record
        movem.l (sp)+,d0-d1/a0
        move.w d0,(a1)
        lea custom_record(pc),a1
        move.w 2(a1),d0
        cmp.w 4(a1),d0
        bhs.s .apply
        move.w d0,4(a1)                 ; to save at most the lemmings
.apply: bsr level_apply
        cmpi.b #PARAMS-1,param_sel(a4)
        bne.s .restore
        move.w $18(a1),($9da8).l
.restore:
        movem.l (sp)+,d0-d3/a0-a1
.done:  rts

; Parameters in the order of the status block: record offset, step, minimum,
; maximum (0: the number of lemmings). The game's limits are those of
; check_level_record.
param_table:
        dc.b $00,1
        dc.w 0,99                       ; release rate
        dc.b $02,1
        dc.w 1,160                      ; lemmings
        dc.b $04,1
        dc.w 0,0                        ; to save
        dc.b $06,1
        dc.w 1,9                        ; minutes
        dc.b $08,1
        dc.w 0,99                       ; climbers
        dc.b $0a,1
        dc.w 0,99                       ; floaters
        dc.b $0c,1
        dc.w 0,99                       ; bombers
        dc.b $0e,1
        dc.w 0,99                       ; blockers
        dc.b $10,1
        dc.w 0,99                       ; builders
        dc.b $12,1
        dc.w 0,99                       ; bashers
        dc.b $14,1
        dc.w 0,99                       ; miners
        dc.b $16,1
        dc.w 0,99                       ; diggers
        dc.b $18,16
        dc.w 0,1280                     ; start position, the view's fast step

; Make the game follow custom_record after a change of its parameters,
; objects, steel areas or title, as a level start sets it up: the record's
; header, objects, steel areas and title are copied to the game's record at
; $C5A6, the simulation is set up again ($2826: object instances, entrances,
; parameters and skill counters) and the attribute grid is rebuilt ($24FE
; steel, $2476 trigger areas, with the game's A4). No lemming has been
; released, so nothing else refers to the old state. The pause flag, the
; startup counter and the view's scroll stay; the skill selection sprite stays
; hidden.
level_apply:
        bsr undo_check                  ; an edit that changed nothing
        movem.l d0-d7/a0-a6,-(sp)
        lea custom_record(pc),a0
        lea ($c5a6).l,a1
        move.w #$120/4-1,d0
.head:  move.l (a0)+,(a1)+
        dbra d0,.head
        lea custom_record+$760(pc),a0
        lea ($cd06).l,a1
        moveq #$a0/4-1,d0
.tail:  move.l (a0)+,(a1)+
        dbra d0,.tail
        move.b $39(a5),-(sp)
        move.l $dc(a5),-(sp)
        move.w ($9da8).l,-(sp)
        lea (GAME_ROWS).l,a4
        jsr $2826
        move.w (sp)+,($9da8).l
        move.l (sp)+,$dc(a5)
        move.b (sp)+,$39(a5)
        clr.l ($144f2).l
        jsr $24fe
        jsr $2476
        movem.l (sp)+,d0-d7/a0-a6
        st dirty(a4)
        or.b #1,status_dirty(a4)
        rts

; ---------------------------------------------------------------------------
; Test play

; From the frame hook, with its registers on the stack: E while a custom
; level is edited. With the editor open, start a test play of the current
; edits; during a test play, start the level again in the editor.
custom_toggle:
        tst.b active(a4)
        beq.s .editor
        lea custom_record(pc),a1
        bsr append_placements
        bne.s .test
        clr.l paint_count(a4)           ; the pieces are in the record now
.test:  st custom_test(a4)
        bra.s restart_level
.editor:
        clr.b custom_test(a4)

; Entered from the frame hook with its register frame still on the stack.
; Start the level again through the game's loader, where the custom level
; hook puts custom_record in, and its normal start path.
restart_level:
        bsr hide_status
        st $2b(a5)
        move.w #$0010,$9a(a6)
        move.w #$8020,$9a(a6)
        clr.b $2f(a5)
        jsr $1ae0
        moveq #-1,d0
        jsr $17268
        move.w #-1,$76(a5)
        jsr $2632
        movem.l (sp)+,d0-d7/a0-a6
        jmp $56a

; ---------------------------------------------------------------------------
; Leaving the editor

; From the frame hook: Esc with the editor open. Leave at once when the level
; has no unsaved changes, otherwise ask first (menu.s).
custom_escape:
        bsr.s level_changed
        beq.s custom_leave
        bra menu_ask_leave

; Close the editor and end the level with the game's own Esc action ($1598).
; The game fades the level out; its result screen hook (custom_ended, levels.s)
; then returns to the list.
custom_leave:
        bsr hide_status
        clr.b active(a4)
        st leaving(a4)
        jmp $1598

; Z clear when the edited level differs from the one loaded or last saved:
; custom_record with the placements after its terrain pieces, as a save would
; store it (built in save_record), against the CRC of the saved state.
level_changed:
        movem.l d0-d5/a0-a1,-(sp)
        lea custom_record(pc),a0
        tst.l paint_count(a4)
        beq.s .crc
        lea save_record(pc),a1
        move.w #LEVEL_SIZE/4-1,d0
.copy:  move.l (a0)+,(a1)+
        dbra d0,.copy
        lea save_record(pc),a1
        bsr.s append_placements
        bne.s .done                     ; they do not fit: changed
        lea save_record(pc),a0
.crc:   bsr.s record_crc
        cmp.l saved_crc(a4),d0
.done:  movem.l (sp)+,d0-d5/a0-a1
        rts

; Take custom_record as the level's saved state.
level_remember:
        movem.l d0-d5/a0,-(sp)
        bsr.s level_crc
        move.l d0,saved_crc(a4)
        movem.l (sp)+,d0-d5/a0
        rts

; D0: CRC-32 of custom_record. Clobbers D1-D5/A0.
level_crc:
        lea custom_record(pc),a0

; A0: a level record. D0: its CRC-32. Clobbers D1-D5/A0.
record_crc:
        move.l #LEVEL_SIZE,d0
        moveq #-1,d1
        bra crc32

; A1: level record. Append the editor's placements to its terrain pieces;
; an end marker must remain. Z set on success.
append_placements:
        movem.l d0/a0-a2,-(sp)
        lea $760(a1),a2
        lea $120(a1),a1
.skip:  cmpa.l a2,a1
        bhs.s .bad
        cmpi.l #-1,(a1)
        beq.s .end
        addq.l #4,a1
        bra.s .skip
.end:   move.l paint_count(a4),d0
        lea placements(pc),a0
        bra.s .more
.copy:  move.l (a0)+,(a1)+
.more:  subq.l #1,d0
        bmi.s .check
        cmpa.l a2,a1
        blo.s .copy
.check: cmpa.l a2,a1
        bhs.s .bad
        moveq #0,d0
        bra.s .done
.bad:   moveq #-1,d0
.done:  movem.l (sp)+,d0/a0-a2
        rts

; ---------------------------------------------------------------------------
; Status block of a custom level

; From status_full: the labels of the mode and its values, then the footer.
custom_status:
        lea status_custom(pc),a2
        cmp.b #3,edit_mode(a4)
        bne.s .labels
        lea status_params(pc),a2
.labels:
        bsr status_texts
        moveq #0,d0
        move.b edit_mode(a4),d0
        add.w d0,d0
        lea status_modes(pc),a2
        adda.w 0(a2,d0.w),a2
        bsr status_texts
        move.b edit_mode(a4),d0
        cmp.b #3,d0
        beq .params
        ; Level, style and the level's numbers.
        move.w custom_number(a4),d0
        moveq #2,d1
        moveq #0,d2
        bsr status_number
        move.w ($c5c0).l,d0
        addq.w #1,d0
        moveq #3,d1
        bsr status_number
        lea custom_record(pc),a0
        moveq #0,d1
        moveq #40,d2
.counts:
        move.w 2(a0),d0
        bsr status_number
        addq.l #2,a0
        addq.w #1,d1
        cmp.w #3,d1
        blo.s .counts
        move.b edit_mode(a4),d0
        beq.s .terrain
        subq.b #2,d0
        bmi.s .steel
        bsr object_status
        bra .footer
.terrain:
        move.w piece_count(a4),d0
        moveq #1,d1
        moveq #20,d2
        bsr status_number
        move.w ($c5c2).l,d0
        moveq #3,d1
        bsr status_number
        bra .footer
.steel: lea custom_record+$760(pc),a0
        moveq #31,d1
        moveq #0,d0
.area:  tst.l (a0)+
        beq.s .empty
        addq.w #1,d0
.empty: dbra d1,.area
        moveq #0,d1
        moveq #20,d2
        bsr status_number
        bra .footer
.params:
        ; Thirteen values, four per column; ">" marks the selection.
        lea param_table(pc),a0
        lea custom_record(pc),a1
        moveq #0,d3
.param: move.w d3,d1
        and.w #3,d1
        move.w d3,d2
        lsr.w #2,d2
        mulu #20,d2
        moveq #0,d0
        move.b (a0),d0
        move.w 0(a1,d0.w),d0
        bsr status_number
        movem.l d1-d2,-(sp)
        add.w #11,d2
        bsr status_cell
        moveq #' ',d0
        cmp.b param_sel(a4),d3
        bne.s .mark
        moveq #'>',d0
.mark:  bsr glyph
        movem.l (sp)+,d1-d2
        addq.l #6,a0
        addq.w #1,d3
        cmp.w #PARAMS,d3
        blo.s .param
.footer:
        lea status_footer(pc),a2
        bsr status_texts
        bsr status_title
        bra status_force

; D0: value, D1: row, D2: first column of the field's label. Draw D0 with four
; digits at column D2 + 12.
status_number:
        movem.l d1-d2/d4/a3,-(sp)
        add.w #12,d2
        bsr.s status_cell
        bsr number
        movem.l (sp)+,d1-d2/d4/a3
        rts

; D1: row, D2: column. Return the cell in A3 (text row) and D4 (pixel).
status_cell:
        move.l d1,-(sp)
        lea CHIP_TEXT,a3
        mulu #640,d1
        adda.l d1,a3
        move.w d2,d4
        lsl.w #3,d4
        move.l (sp)+,d1
        rts

; A2: text entries (row, column, text, NUL), ended by $FF. Draw them.
status_texts:
        movem.l d0-d2/d4/a3,-(sp)
.entry: moveq #0,d1
        move.b (a2)+,d1
        cmp.b #$ff,d1
        beq.s .done
        moveq #0,d2
        move.b (a2)+,d2
        bsr.s status_cell
.char:  moveq #0,d0
        move.b (a2)+,d0
        beq.s .entry
        bsr glyph
        addq.w #8,d4
        bra.s .char
.done:  movem.l (sp)+,d0-d2/d4/a3
        rts

status_footer:
        dc.b 5,50,'Editor V2.2 by Timo Heimonen',0,$ff
status_modes:
        dc.w status_terrain-status_modes,status_steel-status_modes
        dc.w status_objects-status_modes,status_none-status_modes

status_custom:
        dc.b 0,0,'X Coord',0,1,0,'Y Coord',0,2,0,'Level',0,3,0,'Ground',0
        dc.b 0,40,'Lemmings',0,1,40,'To Save',0,2,40,'Minutes',0
        dc.b 4,0,'Room',0
        dc.b 4,20,'E:Test T:Steel O:Objects P:Params N:Title S:Save U:Undo',0
status_none:
        dc.b $ff
status_params:
        dc.b 0,0,'Release',0,1,0,'Lemmings',0,2,0,'To Save',0,3,0,'Minutes',0
        dc.b 0,20,'Climbers',0,1,20,'Floaters',0,2,20,'Bombers',0,3,20,'Blockers',0
        dc.b 0,40,'Builders',0,1,40,'Bashers',0,2,40,'Miners',0,3,40,'Diggers',0
        dc.b 0,60,'Start X',0,1,60,'Shift: Steps x10',0
        dc.b 2,60,'Up/Down: Field',0,3,60,'Left/Right: Value',0
        dc.b 4,0,'Room',0,4,20,'E:Test P:Terrain N:Title S:Save U:Undo',0,$ff
status_terrain:
        dc.b 0,20,'Piece',0,1,20,'Piece Types',0,2,20,'Brush',0,3,20,'Special',0
        dc.b 3,40,'Flip',0,0,60,'LMB: Place',0
        dc.b 2,60,'Left/Right: Piece',0,3,60,'F: Flip  B: Behind',0,5,0,'G: Snap',0,$ff
; The right button's help follows the brush (status_values): Shift deletes
; pieces only while erasing. Both texts are 20 cells wide.
status_rmb_add:
        dc.b 1,60,'RMB: Add/Erase      ',0,$ff
status_rmb_erase:
        dc.b 1,60,'RMB: Add  Shift: Del',0,$ff
status_steel:
        dc.b 0,20,'Steel Areas',0,0,60,'LMB Drag: Add',0,1,60,'RMB: Remove',0
        dc.b 3,60,'T: Terrain',0,$ff
status_objects:
        dc.b 0,20,'Object',0,1,20,'2 Players',0,2,20,'Object Slot',0
        dc.b 3,20,'Objects',0,3,40,'Draw',0,0,60,'LMB: Place/Move',0
        dc.b 1,60,'RMB: Delete  M: 2P',0,2,60,'Left/Right: Object',0
        dc.b 3,60,'F: Draw  O: Terrain',0,5,0,'G: Snap',0,$ff
        even
