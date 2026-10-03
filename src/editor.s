; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Lemmings custom level editor (68000, position independent).
;
; Lemmings: loaded by the bootstrap into a reserved block of slow RAM and
; entered once at "install", which patches jumps into the game's main loop,
; keyboard interrupt, level setup and title screen. Holiday Lemmings 1994: two
; hunks of the game's executable, whose hooks patch.py writes; the game's
; start-up enters "install" (holiday94.s). The editor edits custom levels: new
; ones from the title screen's CUSTOM rating and the levels of a level disk
; (under WHDLoad and in Holiday Lemmings 1994 the .lvl files of the directory
; Levels). It opens by itself when an edited level starts; the original levels
; are played unchanged. The game's addresses come from game_lemmings.i or
; game_holiday94.i, for the game versions whose disk images patch.py
; identifies by SHA-256. Inside the hooks A4 points to the editor's own state
; and A5 to the game's global variables.
        ifd HOLIDAY94
        include "game_holiday94.i"
        else
        include "game_lemmings.i"
        endif
        ifd WHDLOAD
        ifnd FILES
FILES           equ 1                   ; custom levels are .lvl files
        endif
        endif

GFX             equ $b000
GFX_MAX_BYTES   equ 42200
EDITOR_RESERVE  equ $20000
; CPU-only disk workspace after the largest Ground resource. These buffers
; are initialized by their producers, not by the storage clear.
DISK_WORK       equ $15800
DISK_TRACK      equ DISK_WORK
DISK_VERIFY     equ DISK_TRACK+TRACK_BYTES
DISK_HEADER     equ DISK_VERIFY+TRACK_BYTES
DISK_WORK_END   equ DISK_HEADER+TRACK_BYTES
        xdef GFX_MAX_BYTES,EDITOR_RESERVE,DISK_WORK_END
        ifd RELOCATED
CHIP_TEXT       equ H5                ; the editor's chip hunk
CHIP_COPPER     equ H5+TEXT_BYTES
CHIP_BYTES      equ TEXT_BYTES+copper_end-copper_template
        xdef CHIP_BYTES
        else
CHIP_TEXT       equ $21d00            ; above the bootstrap appended to Code
CHIP_COPPER     equ $22c00
        endif
        xdef CHIP_TEXT,CHIP_COPPER
TEXT_BYTES      equ 3840
TRACK_BYTES     equ 11*512
MAX_PLACEMENTS  equ 399               ; terrain pieces of a level: the list needs an end marker
DELETED_MAX     equ 32                ; FILES: names deleted in this session (level_delete.s)

; Editor state, relative to "state".
        rsreset
image_ptr       rs.l 1              ; selected piece: colour planes
mask_ptr        rs.l 1              ; and mask
gfx_ptr         rs.l 1              ; the level's Ground graphics in the block
plane_size      rs.l 1
paint_count     rs.l 1              ; pieces placed since the level started
dplane          rs.l 1              ; destination plane stride
dest_ptr        rs.l 1              ; destination surface base
disk_raw        rs.l 1              ; raw MFM buffer of a transfer
menu_msg        rs.l 1              ; message shown by the menu
saved_crc       rs.l 1              ; CRC-32 of custom_record as loaded or last saved
delete_crc      rs.l 1              ; CRC-32 of the slot asked about for deletion (floppy)
piece_id        rs.w 1
piece_count     rs.w 1
brush_x         rs.w 1              ; cursor in level coordinates
brush_y         rs.w 1
width           rs.w 1              ; selected piece
height          rs.w 1
stride          rs.w 1
mode            rs.w 1              ; compositor target
origin_x        rs.w 1
origin_y        rs.w 1
origin_q        rs.w 1              ; destination byte column of the piece's left edge
source_y        rs.w 1
row_stride      rs.w 1
clip_top        rs.w 1              ; first writable destination row
undo_brush      rs.w 3              ; the brush kept while undo redraws pieces
clip_rows       rs.w 1              ; number of writable rows
clip_lo         rs.w 1              ; first writable destination byte column
clip_span       rs.w 1              ; number of writable byte columns
last_x          rs.w 1              ; cursor and scroll of the last redraw
last_y          rs.w 1
last_scroll     rs.w 1
remaining       rs.w 1              ; terrain pieces that may still be placed
shown_x         rs.w 1              ; values currently drawn in the status block
shown_y         rs.w 1
shown_piece     rs.w 1
shown_remaining rs.w 1
shown_sign      rs.b 1
shown_flip      rs.b 1
pending_toggle  rs.b 1              ; E pressed (read together with the next byte)
pending_cycle   rs.b 1              ; left and right arrows, signed count
flipped         rs.b 1              ; brush orientation (cleared together with the next byte)
pending_flip    rs.b 1              ; F pressed
disk_old_adk    rs.w 1
disk_old_dma    rs.w 1
disk_old_int    rs.w 1
disk_track_no   rs.w 1
list_page       rs.w 1
list_sel        rs.w 1              ; selected row on the page
list_count      rs.w 1              ; levels on the level disk
list_hover      rs.w 1              ; text row the pointer was on
custom_number   rs.w 1              ; list number (level disk: slot + 1), 0 for a new level
custom_slot     rs.w 1              ; its slot (level disk), list entry (FILES), -1 new
list_old42      rs.w 1              ; the game's level (G_LEVEL) when the list opened
drag_col        rs.w 1              ; first cell of a steel area being dragged
drag_row        rs.w 1
obj_type        rs.w 1              ; object type placed by the left button (objects.s)
obj_flags       rs.w 1              ; its drawing flags
obj_hover       rs.w 1              ; slot of the object under the cursor, or -1
obj_frame       rs.w 1              ; frame of the preview; -1: the type's start frame
obj_dx          rs.w 1              ; cursor minus the dragged object's position
obj_dy          rs.w 1
snap_x          rs.w 1              ; the nearest position beside a neighbour (snap)
snap_y          rs.w 1
snap_xs         rs.w 1              ; opaque columns and rows of the mask (mask_bounds)
snap_xe         rs.w 1
snap_ys         rs.w 1
snap_ye         rs.w 1
snap_vw         rs.w 1              ; opaque width: the step beside a neighbour
snap_rows       rs.w 6              ; row offsets beside, below, above an upright and a flipped neighbour
snap_reach_x    rs.w 1              ; farther neighbours cannot be snapped to
snap_reach_y    rs.w 1
snap_key        rs.w 1              ; mask of snap_xs..snap_ye: piece + 1, $100 + object type, 0 none
palette_save    rs.w 5              ; view colours replaced by the menu
list_palette_rows rs.w 13           ; palette number of each text row of the list
        ifd FILES
deleted_names   rs.l DELETED_MAX      ; hashes of the file names deleted in this session
deleted_count   rs.w 1
        endif
        ifd RELOCATED
dos_window      rs.l 1              ; the process's requester window (dos_file.s)
        endif
active          rs.b 1              ; the editor is open
negative        rs.b 1              ; the brush erases
last_left       rs.b 1              ; mouse buttons of the last frame
last_right      rs.b 1
valid           rs.b 1              ; the level's pieces are available
dirty           rs.b 1              ; the view must be redrawn
load_reopen     rs.b 1              ; open the editor at the next frame
disk_busy       rs.b 1              ; synchronous ownership of the back buffer
disk_cancel     rs.b 1
disk_committing rs.b 1              ; finish verification even if Esc is pressed
disk_drive      rs.b 1              ; CIA-B select bit, 3..6
disk_cylinder   rs.b 1
disk_redraw     rs.b 1
menu_mode       rs.b 1              ; 0 = closed, otherwise the menu's state
menu_kind       rs.b 1              ; 0 = saving, 1 = the title only
native_drive    rs.b 1              ; drive the game reads disk 2 from
native_used     rs.b 1              ; a disk was taken from that drive
pending_menu    rs.b 1              ; S or N pressed: 1 = save, 2 = title
key_head        rs.b 1
key_tail        rs.b 1
shift           rs.b 1
custom_tier     rs.b 1              ; the title screen shows CUSTOM
list_open       rs.b 1              ; the custom level list takes the keys
list_drive      rs.b 1
title_disk      rs.b 1              ; transport runs on the title screen
list_old32      rs.b 1              ; the game's text mode flag (G_TEXT_MODE)
list_retry      rs.b 1              ; a click searches for the disk again
custom_play     rs.b 1              ; the game plays custom_record
list_played     rs.b 1              ; a custom level was played from the list
list_mode       rs.b 1              ; the list shows 0: levels, 1: graphics styles
list_players    rs.b 1              ; the list is for two players (2 Player in CUSTOM)
custom_edit     rs.b 1              ; the custom level is being edited
custom_test     rs.b 1              ; the next level start is a test play
title_len       rs.b 1              ; characters in title_buf
edit_mode       rs.b 1              ; 0 terrain, 1 steel, 2 objects, 3 parameters
pending_mode    rs.b 1              ; T, O or P pressed: the mode it asks for
pending_select  rs.b 1              ; up and down arrows, signed count
steel_drag      rs.b 1              ; a new steel area is being dragged
obj_drag        rs.b 1              ; dragged slot + 1, or 0
param_sel       rs.b 1              ; selected parameter (params.s)
status_dirty    rs.b 1              ; redraw the status block: 1 values, -1 all
pending_escape  rs.b 1              ; Esc pressed while a custom level is edited
leave_now       rs.b 1              ; the leave menu was confirmed
leaving         rs.b 1              ; the level ends to leave the editor
snap            rs.b 1              ; pieces and objects snap to their neighbours
pending_snap    rs.b 1              ; G pressed
shown_snap      rs.b 1
behind          rs.b 1              ; the brush draws behind the terrain
pending_behind  rs.b 1              ; B pressed
pending_marker  rs.b 1              ; M pressed
pending_undo    rs.b 1              ; U pressed: 1 undo, 2 redo (with shift)
undo_count      rs.b 1              ; entries that can be undone (undo.s)
redo_count      rs.b 1              ; entries after them that can be redone
undo_open       rs.b 1              ; a range was taken for an edit in progress
undo_lost_kind  rs.b 1              ; what undo_lost holds: 0 or UNDO_LOST_OLDEST/_NEXT
undo_lost_redo  rs.b 1              ; redo_count before that entry was lost
delete_mode     rs.b 1              ; Shift in the erasing mode: deleting pieces (delete.s)
        ifd G_TRIES
list_old_tries  rs.b 1              ; the game's failed tries (G_TRIES) when the list opened
        endif
key_queue       rs.b 16             ; raw key codes for the menu and the list
menu_line       rs.b 42             ; a text line
        rseven
STATE_SIZE      rs.b 0

        ifd EDITOR_ORG
        org EDITOR_ORG                  ; patch.py: finds addresses of the editor
        else
        org 0
        endif
; Install the hooks: keyboard interrupt (HOOK_KEYBOARD), frame start
; (HOOK_FRAME), gameplay input (HOOK_ACTIONS), level setup (HOOK_CAPTURE), end
; of frame drawing (HOOK_OVERLAY), the title screen and the custom levels'
; hooks (title.s); in a relocated editor (RELOCATED) patch.py has written the
; hooks into the game's program. Also prepares the font and the copper list
; continuation for the status block.
install:
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        movea.l a4,a0
        move.w #(storage_end-state)/2-1,d0
.clear: clr.w (a0)+
        dbra d0,.clear
        ifd RELOCATED
        lea install(pc),a0
        else
        movea.l G_CACHE_END(a5),a0
        endif
        adda.l #GFX,a0
        move.l a0,gfx_ptr(a4)
        ifd RELOCATED
        bsr prepare_font                ; patch.py has written the hooks
        else
        lea keyboard(pc),a0
        move.w sr,-(sp)
        ori.w #$0700,sr                 ; the keyboard interrupt must never
        move.l a0,HOOK_KEYBOARD+2                 ; run a half-written jump
        move.w #$4ef9,HOOK_KEYBOARD
        move.l #$4e714e71,HOOK_KEYBOARD+6
        move.w #$4e71,HOOK_KEYBOARD+10
        move.w (sp)+,sr
        bsr prepare_font
        lea frame(pc),a0
        move.l a0,HOOK_FRAME+2
        move.w #$4ef9,HOOK_FRAME
        move.w #$4e71,HOOK_FRAME+6
        lea actions(pc),a0
        move.l a0,HOOK_ACTIONS+2
        move.w #$4ef9,HOOK_ACTIONS
        move.w #$4e71,HOOK_ACTIONS+6
        lea capture(pc),a0
        move.l a0,HOOK_CAPTURE+2
        move.w #$4ef9,HOOK_CAPTURE
        move.w #$4e71,HOOK_CAPTURE+6
        lea overlay(pc),a0
        move.l a0,HOOK_OVERLAY+2
        move.w #$4ef9,HOOK_OVERLAY
        move.w #$4e71,HOOK_OVERLAY+6
        bsr title_install
        endif
        lea copper_template(pc),a0
        lea CHIP_COPPER,a1
        move.w #(copper_end-copper_template)/2-1,d0
.copy:  move.w (a0)+,(a1)+
        dbra d0,.copy
        ifd RELOCATED
        move.l #CHIP_TEXT,d0            ; the bitplane pointer of the status block
        move.w d0,CHIP_COPPER+COPPER_TEXT+6
        swap d0
        move.w d0,CHIP_COPPER+COPPER_TEXT+2
        endif
        movem.l (sp)+,d0-d7/a0-a6
        rts

; Level setup hook. Resets the editor. When a custom level is edited, loads
; and unpacks the level's Ground graphics into editor memory (the game later
; overwrites its own copy with sound data), counts the terrain pieces of its
; graphics set and opens the editor at the first frame, except for a test
; play.
capture:
        jsr SELECT_STYLE
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        bsr hide_status
        clr.b active(a4)
        clr.b valid(a4)
        clr.b load_reopen(a4)
        clr.b negative(a4)
        clr.b behind(a4)
        clr.b pending_behind(a4)
        clr.b pending_marker(a4)
        clr.b pending_undo(a4)
        clr.b delete_mode(a4)
        clr.w flipped(a4)       ; orientation and queued F press
        clr.w pending_toggle(a4)
        clr.b pending_menu(a4)
        clr.w piece_id(a4)
        clr.l paint_count(a4)
        clr.b steel_drag(a4)
        clr.b obj_drag(a4)
        clr.b undo_open(a4)             ; a drag's range, taken when it began
        bsr undo_break                  ; a change after a test play is a new step
        move.w #-1,obj_hover(a4)
        move.w #-1,obj_frame(a4)
        clr.b pending_mode(a4)
        clr.b pending_select(a4)
        clr.b pending_escape(a4)
        clr.w snap_key(a4)              ; the style may have changed
        tst.b custom_edit(a4)
        beq .done
        tst.b custom_test(a4)
        seq load_reopen(a4)
        clr.b custom_test(a4)
        bsr count_placements
        lea ground_name(pc),a0
        move.w LEVEL_RECORD+$1a,d0
        cmp.w #STYLES-1,d0
        bhi.s .done
        add.b #'1',d0
        move.b d0,6(a0)
        movea.l gfx_ptr(a4),a1
        moveq #0,d1
        jsr LOAD_FILE
        movea.l gfx_ptr(a4),a0
        movea.l a0,a1
        move.l d1,d0
        jsr UNPACK
        movea.l G_STYLE(a5),a0
        lea $290(a0),a0
        moveq #0,d0
.count: tst.w (a0)
        beq.s .counted
        tst.w 2(a0)
        beq.s .counted
        addq.w #1,d0
        lea 12(a0),a0
        cmp.w #64,d0
        blo.s .count
.counted:
        move.w d0,piece_count(a4)
        sne valid(a4)
.done:  movem.l (sp)+,d0-d7/a0-a6
        jsr INIT_SIMULATION
        jmp CAPTURE_DONE

; Capture press edges before the original CIA acknowledgement. Releases never
; overwrite queued presses, so a quick tap survives a long brush render. Keys
; reach the editor only while a custom level is edited. An Esc for the
; editor, its menu or the list reaches the game as a release, so it never
; ends the level.
keyboard:
        move.b d0,G_RAW_KEY(a5)
        lea state(pc),a4
        bsr editor_shift                ; in every state, so it never sticks
        tst.b disk_busy(a4)
        beq.s .menu
        cmp.b #$45,d0                  ; Esc cancels a disk operation
        bne .ack
        st disk_cancel(a4)
        bra.s .own
.menu:  tst.b menu_mode(a4)
        bne.s .queue
        tst.b list_open(a4)
        beq.s .editor
.queue: bsr menu_queue_key
        bra.s .own
.editor:
        tst.b custom_edit(a4)
        beq .ack
        cmp.b #$45,d0                  ; Esc: leave, or back to the editor
        bne.s .keys
        st pending_escape(a4)
.own:   cmp.b #$45,d0                  ; the game gets the editor's Esc as a release
        bne .ack
        move.b #$c5,d0
        bra .ack
.keys:  tst.b d0
        bmi.s .ack
        bsr custom_key                 ; params.s
        bne.s .ack
        cmp.b #$12,d0                  ; E: test play, or back to the editor
        bne.s .right
        eori.b #1,pending_toggle(a4)
        bra.s .ack
.right: cmp.b #$4e,d0
        bne.s .left
        addq.b #1,pending_cycle(a4)
        bra.s .ack
.left:  cmp.b #$4f,d0
        bne.s .flip
        subq.b #1,pending_cycle(a4)
        bra.s .ack
.flip:  cmp.b #$23,d0           ; F has no original gameplay action
        bne.s .behind
        tst.b active(a4)
        beq.s .ack
        eori.b #1,pending_flip(a4)
        bra.s .ack
.behind:
        cmp.b #$35,d0           ; B: neither has it
        bne.s .ack
        tst.b active(a4)
        beq.s .ack
        eori.b #1,pending_behind(a4)
.ack:   move.b #0,$bfec01
        jmp KEYBOARD_DONE

; D0: raw key. Track the shift keys: steps of ten, redo, deleting pieces and
; the title's shifted characters.
editor_shift:
        cmp.b #$60,d0
        beq.s .down
        cmp.b #$61,d0
        beq.s .down
        cmp.b #$e0,d0
        beq.s .up
        cmp.b #$e1,d0
        bne.s .done
.up:    clr.b shift(a4)
        rts
.down:  st shift(a4)
.done:  rts

; Frame start hook. Opens the editor at the first frame of an edited level,
; pausing the game, and handles E (test play), Esc, G (snap), B (behind), the menus, the mode keys, piece
; cycling, flip, scrolling and the mouse buttons; paints into the level when
; the left button is pressed. While the editor is open the viewport is redrawn
; only when something visible changed.
frame:
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        tst.b load_reopen(a4)
        beq.s .input
        clr.b load_reopen(a4)
        tst.b valid(a4)
        beq.s .input
        st active(a4)
        st G_PAUSE(a5)
        btst #6,$bfe001
        seq last_left(a4)
        btst #2,$16(a6)
        seq last_right(a4)
        clr.l SKILL_SPRITE           ; hide the skill-selection sprite
        bsr show_status
        st disk_redraw(a4)     ; draw the preview even if nothing moves
.input: move.b disk_redraw(a4),dirty(a4)
        clr.b disk_redraw(a4)
        tst.b menu_mode(a4)
        bne.s .menu
        moveq #0,d0
        move.b pending_menu(a4),d0
        beq.s .editor_input
        clr.b pending_menu(a4)
        tst.b active(a4)
        beq.s .editor_input
        subq.b #1,d0                    ; 1: save, 2: title only
        bsr level_save_open
        bra.s .menu_idle
.menu:  bsr menu_frame
        tst.b leave_now(a4)
        beq.s .menu_idle
        clr.b leave_now(a4)
        bsr custom_leave
        bra .game
.menu_idle:
        movem.l (sp)+,d0-d7/a0-a6
        clr.w G_FRAMES(a5)
        ifd FADE_STEP
        jsr FADE_STEP                   ; the level's fade-in goes on
        endif
        jmp FRAME_WAIT
.editor_input:
        move.b pending_undo(a4),d0      ; U: undo, Shift+U: redo
        beq.s .behind_key
        clr.b pending_undo(a4)
        bsr undo_key
.behind_key:
        tst.b pending_behind(a4)        ; B: the brush draws behind the terrain
        beq.s .snap_key
        clr.b pending_behind(a4)
        tst.b edit_mode(a4)
        bne.s .snap_key
        not.b behind(a4)
        clr.b negative(a4)              ; add, erase or behind
        st dirty(a4)
.snap_key:
        tst.b pending_marker(a4)        ; M: the two-player marker
        beq.s .snap_toggle
        clr.b pending_marker(a4)
        cmp.b #2,edit_mode(a4)
        bne.s .snap_toggle
        bsr object_marker
.snap_toggle:
        tst.b pending_snap(a4)          ; G: snap on or off
        beq.s .inputs
        clr.b pending_snap(a4)
        not.b snap(a4)
        st dirty(a4)
.inputs:
        INTS_OFF
        moveq #0,d6
        move.w pending_toggle(a4),d0
        move.b d0,d6
        clr.w pending_toggle(a4)
        move.b pending_flip(a4),d7
        clr.b pending_flip(a4)
        move.b pending_select(a4),d5
        clr.b pending_select(a4)
        move.b pending_escape(a4),d4
        clr.b pending_escape(a4)
        INTS_ON
        lsr.w #8,d0
        tst.b d4
        beq.s .toggle
        moveq #1,d0                     ; Esc during a test play works as E
        tst.b active(a4)
        beq.s .toggle
        bsr custom_escape               ; opens the leave menu or leaves
        tst.b active(a4)
        beq .game
        bra .menu_idle
.toggle:
        tst.b d0
        beq.s .cycle
        tst.b custom_edit(a4)
        beq.s .cycle
        tst.b G_LEVEL_ENDING(a5)           ; not during level completion
        bne.s .cycle
        tst.b G_ALL_OUT(a5)
        beq custom_toggle
.cycle: move.w d6,d0
        tst.b active(a4)
        beq .done
        tst.b edit_mode(a4)
        beq.s .piece
        bsr mode_keys                   ; objects and parameters
        bra.s .buttons
.piece: tst.b d0
        beq.s .buttons
        st dirty(a4)
        ext.w d0
        add.w d0,piece_id(a4)
.wrap_low:
        tst.w piece_id(a4)
        bpl.s .wrap_high
        move.w piece_count(a4),d0
        add.w d0,piece_id(a4)
        bra.s .wrap_low
.wrap_high:
        move.w piece_id(a4),d0
        cmp.w piece_count(a4),d0
        blo.s .buttons
        sub.w piece_count(a4),d0
        move.w d0,piece_id(a4)
        bra.s .wrap_high
.buttons:
        st G_PAUSE(a5)
        bsr mode_switch
        tst.b d7                        ; F
        beq.s .brush
        move.b edit_mode(a4),d0
        beq.s .flip
        subq.b #2,d0
        bne.s .brush
        bsr object_draw_mode
        bra.s .brush
.flip:  not.b flipped(a4)
        st dirty(a4)
.brush:
        bsr scroll
        bsr coordinates
        bsr descriptor
        bsr delete_update
        move.b edit_mode(a4),d0
        beq.s .pieces
        subq.b #2,d0
        bmi.s .steel
        bne .done                       ; parameters: keys only
        bsr object_input
        bsr object_animate
        bra .done
.steel: bsr steel_input
        bra .done
.pieces:
        btst #2,$16(a6)
        seq d0
        cmp.b last_right(a4),d0
        beq.s .left
        move.b d0,last_right(a4)
        tst.b d0
        beq.s .left
        not.b negative(a4)
        clr.b behind(a4)
        st dirty(a4)
.left:  btst #6,$bfe001
        seq d0
        cmp.b last_left(a4),d0
        beq .done
        move.b d0,last_left(a4)
        tst.b d0
        beq .done
        tst.b delete_mode(a4)           ; Shift while erasing: delete a piece
        beq.s .place
        cmpi.w #160,MOUSE_Y
        bhs .done
        bsr piece_delete
        bra .done
.place: bsr brush_snap                  ; where the preview shows the piece
        cmpi.w #160,MOUSE_Y
        bhs .done
        tst.w remaining(a4)
        beq .done
        ; The record holds x unsigned: no piece may start left of the level.
        move.w brush_x(a4),d0
        move.w width(a4),d1
        lsr.w #1,d1
        cmp.w d1,d0
        blt .done
        bsr record_placement
        move.w brush_x(a4),d0
        move.w brush_y(a4),d1
        moveq #0,d2
        bsr composite
        jsr CLEAR_GUARDS
        jsr MINIMAP_REFRESH
        addq.l #1,paint_count(a4)
        bsr undo_piece
        st dirty(a4)
.done:  tst.b active(a4)
        beq .game
        tst.b dirty(a4)
        bne.s .redraw
        move.w VIEW_SCROLL,d0
        cmp.w last_scroll(a4),d0
        bne.s .redraw
        move.w MOUSE_Y,d0
        cmp.w #160,d0
        blo.s .viewport
        ; Cursor over the panel: there is no preview to move, so only the
        ; coordinates change. Update them without redrawing the viewport,
        ; unless the cursor just left the viewport and its preview must go.
        cmpi.w #160,last_y(a4)
        blo.s .redraw
        move.w d0,last_y(a4)
        move.w MOUSE_X,last_x(a4)
        bsr coordinates
        bsr status_values
        bra.s .idle
.viewport:
        cmp.w last_y(a4),d0
        bne.s .redraw
        move.w MOUSE_X,d0
        cmp.w last_x(a4),d0
        bne.s .redraw
.idle:  movem.l (sp)+,d0-d7/a0-a6
        clr.w G_FRAMES(a5)
        ifd FADE_STEP
        jsr FADE_STEP                   ; the level's fade-in goes on
        endif
        jmp FRAME_WAIT
.redraw:
        move.w MOUSE_X,last_x(a4)
        move.w MOUSE_Y,last_y(a4)
        move.w VIEW_SCROLL,last_scroll(a4)
        movem.l (sp)+,d0-d7/a0-a6
        clr.w G_FRAMES(a5)
        jmp FRAME_STEP
.game:  movem.l (sp)+,d0-d7/a0-a6
        jsr SWAP_BUFFERS
        clr.w G_FRAMES(a5)
        jmp FRAME_STEP

; The level's terrain pieces up to the end marker, and the room left for the
; brush: at most MAX_PLACEMENTS pieces in all. A special background has no
; terrain pieces and no room for any: the game does not draw them, and the
; level could not be saved with them.
count_placements:
        move.w #MAX_PLACEMENTS,d0
        tst.w LEVEL_RECORD+$1c
        bne.s .counted
        moveq #0,d0
        lea LEVEL_RECORD+$120,a0
.scan:  cmpi.l #-1,(a0)+
        beq.s .counted
        addq.w #1,d0
        cmp.w #MAX_PLACEMENTS,d0
        blo.s .scan
.counted:
        neg.w d0
        add.w #MAX_PLACEMENTS,d0
        move.w d0,remaining(a4)
        rts

; Append one placement before changing terrain. The list is separate from the
; game's level record; paint_count bounds its live entries. The entries have
; the format of the record's terrain pieces: H holds the 13-bit x origin, erase
; bit 13, flip bit 14 and behind bit 15; L holds signed y in bits 7..15 and the
; piece in bits 0..5.
record_placement:
        move.w brush_x(a4),d0
        move.w width(a4),d2
        lsr.w #1,d2
        sub.w d2,d0
        and.w #$1fff,d0
        tst.b negative(a4)
        beq.s .behind
        or.w #$2000,d0
.behind:
        tst.b behind(a4)
        beq.s .flip
        or.w #$8000,d0
.flip:  tst.b flipped(a4)
        beq.s .y
        or.w #$4000,d0
.y:     move.w brush_y(a4),d1
        move.w height(a4),d2
        lsr.w #1,d2
        sub.w d2,d1
        lsl.w #7,d1
        or.w piece_id(a4),d1
        move.l paint_count(a4),d2
        lsl.w #2,d2
        lea placements(pc),a0
        adda.w d2,a0
        move.w d0,(a0)+
        move.w d1,(a0)
        subq.w #1,remaining(a4)
        rts

; Scroll the level while the cursor touches the left or right screen edge.
scroll:
        cmpi.w #160,MOUSE_Y
        bhs .done
        tst.w MOUSE_X
        bne.s .right
        subi.w #16,VIEW_SCROLL
        bpl.s .done
        clr.w VIEW_SCROLL
        rts
.right: cmpi.w #319,MOUSE_X
        bne.s .done
        addi.w #16,VIEW_SCROLL
        cmpi.w #1280,VIEW_SCROLL
        bls.s .done
        move.w #1280,VIEW_SCROLL
.done:  rts

; Cursor position in level coordinates.
coordinates:
        move.w MOUSE_X,d0
        add.w VIEW_SCROLL,d0
        add.w #16,d0
        move.w d0,brush_x(a4)
        move.w MOUSE_Y,d0
        addq.w #4,d0
        move.w d0,brush_y(a4)
        rts

; With snap on, put the brush beside the nearest terrain piece of the same
; kind (brush_x/brush_y): the level's pieces and the placements.
brush_snap:
        tst.b snap(a4)
        beq .done
        movem.l d0-d7/a0-a3,-(sp)
        move.w width(a4),d2
        move.w height(a4),d3
        movea.l mask_ptr(a4),a0
        move.w piece_id(a4),d0
        addq.w #1,d0
        bsr snap_bounds
        move.w snap_ys(a4),d0           ; upright rows
        move.w snap_ye(a4),d1
        move.w d3,d4                    ; flipped rows
        sub.w d1,d4
        move.w d3,d5
        sub.w d0,d5
        move.w d0,d6                    ; the brush's own rows
        move.w d1,d7
        tst.b flipped(a4)
        beq.s .own
        move.w d4,d6
        move.w d5,d7
.own:   lea snap_rows(a4),a0
        bsr snap_offsets                ; beside an upright neighbour
        move.w d4,d0
        move.w d5,d1
        bsr snap_offsets                ; and a flipped one
        lsr.w #1,d2
        lsr.w #1,d3
        move.w brush_x(a4),d4
        sub.w d2,d4
        move.w brush_y(a4),d5
        sub.w d3,d5
        moveq #-1,d6
        movea.w piece_id(a4),a2         ; kept in a register for the scan
        tst.w LEVEL_RECORD+$1c                     ; a special background has no pieces
        bne.s .placed
        lea LEVEL_RECORD+$120,a0
        lea LEVEL_RECORD+$760,a1
        bsr.s .scan
.placed:
        lea placements(pc),a0
        move.l paint_count(a4),d0
        lsl.l #2,d0
        lea 0(a0,d0.l),a1
        bsr.s .scan
        cmp.w #-1,d6
        beq.s .keep
        move.w snap_x(a4),d0
        add.w d2,d0
        move.w d0,brush_x(a4)
        move.w snap_y(a4),d0
        add.w d3,d0
        move.w d0,brush_y(a4)
.keep:  movem.l (sp)+,d0-d7/a0-a3
.done:  rts
; A0: terrain pieces up to A1 or the end marker. Pieces of another kind and
; pieces out of reach are passed over first, at little cost.
.scan:  cmpa.l a1,a0
        bhs.s .end
        move.l (a0)+,d0
        cmp.l #-1,d0
        beq.s .end
        moveq #$3f,d7
        and.w d0,d7
        cmpa.w d7,a2
        bne.s .scan
        move.w d0,d1
        asr.w #7,d1
        move.w d1,d7
        sub.w d5,d7
        bpl.s .dy
        neg.w d7
.dy:    cmp.w snap_reach_y(a4),d7
        bhi.s .scan
        swap d0
        lea snap_rows(a4),a3
        btst #14,d0
        beq.s .upright
        addq.l #6,a3
.upright:
        and.w #$1fff,d0
        move.w d0,d7
        sub.w d4,d7
        bpl.s .dx
        neg.w d7
.dx:    cmp.w snap_reach_x(a4),d7
        bhi.s .scan
        bsr.s snap_near
        bra.s .scan
.end:   rts

; A0: three row offsets to fill, the step down from a neighbour's corner to
; the new corner beside, below and above it. D0/D1: the neighbour's opaque
; rows, D6/D7: the new one's. A0 returns past them.
snap_offsets:
        move.w d0,(a0)                  ; beside: tops level
        sub.w d6,(a0)+
        move.w d1,(a0)                  ; below: its top at the bottom
        sub.w d6,(a0)+
        move.w d0,(a0)                  ; above: its bottom at the top
        sub.w d7,(a0)+
        rts

; Snap: D0/D1 top left corner of a neighbour of the same kind, A3 its row
; offsets (snap_offsets); D2/D3 half the size, D4/D5 the wanted top left
; corner, D6 the distance of the best position so far (start with -1). The
; new one may join the neighbour at the right or left (snap_vw apart, rows by
; the first offset) or below or above it (left edges level). Keep the nearest
; of these within half the size of the wanted corner in snap_x/snap_y.
; Clobbers D0, D1, D7.
snap_near:
        sub.w d4,d0
        neg.w d0                        ; wanted - neighbour: x
        sub.w d5,d1
        neg.w d1                        ; and y
        movem.w d0-d1,-(sp)
        sub.w (a3),d1                   ; beside it: are the rows near?
        move.w d1,d7
        bpl.s .beside
        neg.w d7
.beside:
        cmp.w d3,d7
        bhi.s .ends
        sub.w snap_vw(a4),d0            ; right
        bsr.s snap_cand
        add.w snap_vw(a4),d0
        add.w snap_vw(a4),d0            ; left
        bsr.s snap_cand
.ends:  movem.w (sp),d0-d1              ; below or above it: is the column near?
        move.w d0,d7
        bpl.s .column
        neg.w d7
.column:
        cmp.w d2,d7
        bhi.s .done
        sub.w 2(a3),d1                  ; below
        bsr.s snap_cand
        move.w 2(sp),d1
        sub.w 4(a3),d1                  ; above
        bsr.s snap_cand
.done:  addq.l #4,sp
        rts

; D0/D1: wanted corner - candidate. Take the candidate if it is near enough
; and nearer than the best one. Clobbers D7.
snap_cand:
        move.w d0,d7
        bpl.s .x
        neg.w d7
.x:     cmp.w d2,d7
        bhi.s .no
        move.w d7,-(sp)
        move.w d1,d7
        bpl.s .y
        neg.w d7
.y:     cmp.w d3,d7
        bhi.s .pop
        add.w (sp),d7
        cmp.w d6,d7
        bhs.s .pop
        move.w d7,d6
        move.w d4,d7
        sub.w d0,d7
        move.w d7,snap_x(a4)
        move.w d5,d7
        sub.w d1,d7
        move.w d7,snap_y(a4)
.pop:   addq.l #2,sp
.no:    rts

; D0: snap_key of the mask A0 of D2 x D3 pixels. Set up snap_xs..snap_ye,
; computing them only for another mask than last time, snap_vw and the reach:
; a candidate lies at most one size away from its neighbour and must be within
; half a size of the wanted corner.
snap_bounds:
        move.l d0,-(sp)
        cmp.w snap_key(a4),d0
        beq.s .known
        move.w d0,snap_key(a4)
        bsr.s mask_bounds
.known: move.w snap_xe(a4),d0
        sub.w snap_xs(a4),d0
        move.w d0,snap_vw(a4)
        move.w d2,d0
        lsr.w #1,d0
        add.w d2,d0
        move.w d0,snap_reach_x(a4)
        move.w d3,d0
        lsr.w #1,d0
        add.w d3,d0
        move.w d0,snap_reach_y(a4)
        move.l (sp)+,d0
        rts

; A0: a one-plane mask of D2 x D3 pixels, D2 / 8 bytes per row. Store its
; opaque columns snap_xs..snap_xe and rows snap_ys..snap_ye (ends exclusive),
; or the whole rectangle when it is empty.
mask_bounds:
        movem.l d0-d7/a0-a1,-(sp)
        move.w d2,d4
        lsr.w #3,d4                     ; bytes per row
        move.w d2,d5                    ; leftmost opaque column
        moveq #0,d6                     ; after the rightmost one
        move.w d3,snap_ys(a4)
        clr.w snap_ye(a4)
        moveq #0,d7                     ; row
.row:   cmp.w d3,d7
        bhs.s .rows
        moveq #0,d1
        movea.l a0,a1
.left:  move.b (a1)+,d0
        bne.s .first
        addq.w #1,d1
        cmp.w d4,d1
        blo.s .left
        bra.s .next                     ; an empty row
.first: lsl.w #3,d1
.lbit:  add.b d0,d0
        bcs.s .lx
        addq.w #1,d1
        bra.s .lbit
.lx:    cmp.w d5,d1
        bhs.s .right
        move.w d1,d5
.right: move.w d4,d1
        lea 0(a0,d4.w),a1
.rbyte: subq.w #1,d1
        move.b -(a1),d0
        beq.s .rbyte
        lsl.w #3,d1
        addq.w #8,d1
.rbit:  lsr.b #1,d0
        bcs.s .rx
        subq.w #1,d1
        bra.s .rbit
.rx:    cmp.w d6,d1
        bls.s .top
        move.w d1,d6
.top:   cmp.w snap_ys(a4),d7
        bhs.s .bottom
        move.w d7,snap_ys(a4)
.bottom:
        move.w d7,d0
        addq.w #1,d0
        move.w d0,snap_ye(a4)
.next:  adda.w d4,a0
        addq.w #1,d7
        bra.s .row
.rows:  cmp.w d5,d6
        bhi.s .store
        moveq #0,d5                     ; empty: the whole rectangle
        move.w d2,d6
        clr.w snap_ys(a4)
        move.w d3,snap_ye(a4)
.store: move.w d5,snap_xs(a4)
        move.w d6,snap_xe(a4)
        movem.l (sp)+,d0-d7/a0-a1
        rts

; Size and graphics of the selected piece, from the level's style data.
descriptor:
        movea.l G_STYLE(a5),a0
        move.w piece_id(a4),d0
        mulu #12,d0
        lea $290(a0),a0
        adda.w d0,a0
        move.w (a0),width(a4)
        move.w 2(a0),height(a4)
        move.w (a0),d0
        lsr.w #3,d0
        move.w d0,stride(a4)
        mulu 2(a0),d0
        move.l d0,plane_size(a4)
        move.l gfx_ptr(a4),d1
        sub.l #GROUND_BASE,d1
        move.l 4(a0),d0
        add.l d1,d0
        move.l d0,image_ptr(a4)
        move.l 8(a0),d0
        add.l d1,d0
        move.l d0,mask_ptr(a4)
        rts

; Gameplay input hook: skip the game's mouse and keyboard actions while the
; editor is open.
actions:
        lea state(pc),a0
        tst.b active(a0)
        bne.s .skip
        jsr PLAY_MOUSE
        jsr PLAY_KEYS
.skip:  jmp HOOK_OVERLAY

; End of frame drawing: draw the brush preview and update the status block
; before the new frame is shown.
overlay:
        jsr PANEL_REFRESH
        jsr MINIMAP_COLUMN
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        tst.b active(a4)
        beq .done
        tst.b 2(a6)             ; first DMACONR read may be stale on old Agnus
.wait:  btst #6,2(a6)
        bne.s .wait
        bsr coordinates
        bsr descriptor
        move.b edit_mode(a4),d0
        beq.s .brush
        subq.b #2,d0
        bmi.s .steel
        bne.s .status                   ; parameters: no preview
        bsr object_draw
        bra.s .status
.steel: bsr steel_draw
        bra.s .status
.brush: cmpi.w #160,MOUSE_Y
        bhs.s .status
        tst.b delete_mode(a4)           ; deleting: the cursor and an outline
        beq.s .preview
        bsr piece_outline
        bra.s .status
.preview:
        bsr brush_snap
        move.w brush_x(a4),d0           ; into the back buffer
        sub.w VIEW_SCROLL,d0
        move.w brush_y(a4),d1
        subq.w #4,d1
        moveq #1,d2
        bsr composite
.status:
        tst.b status_dirty(a4)
        beq.s .values
        bsr status_full
        bra.s .shown
.values:
        bsr status_values
.shown:
        jsr SWAP_BUFFERS
.done:  movem.l (sp)+,d0-d7/a0-a6
        jmp OVERLAY_DONE

; CPU masked compositor. D0/D1 identify the cursor in the target surface and
; D2 selects the target: 0 = world terrain, 1 = viewport back buffer (preview),
; 2 = world terrain inside the window clip_lo/clip_span (byte columns) and
; clip_top/clip_rows set by the caller.
; The piece is centred on the cursor; for odd dimensions the middle pixel is
; the anchor. The unclamped origin is kept so clipping crops the shape without
; shifting it. Collision guard rows are cleared later by the caller.
;
; Works on whole source bytes: every piece width is a multiple of 8, so each
; mask/image byte covers 8 pixels. The byte is shifted into a 16-bit word that
; spans two destination bytes. Destination clipping is byte-granular because
; both surfaces' visible limits are byte aligned (world 0..1631, viewport
; 16..335). Positive mode replaces masked pixels with the image planes;
; negative mode clears masked pixels in all four planes; behind mode, as the
; game's own drawing, adds the image only where the destination's fourth
; plane (solid terrain) is clear. Every piece's image lies inside its mask.
; A5/A6 are preserved.
composite:
        move.w d2,mode(a4)
        move.w width(a4),d3
        lsr.w #1,d3
        sub.w d3,d0
        move.w height(a4),d3
        lsr.w #1,d3
        sub.w d3,d1
        move.w d0,origin_x(a4)
        move.w d1,origin_y(a4)
        cmp.w #1,d2
        beq.s .preview
        move.l #TERRAIN,dest_ptr(a4)
        move.l #TERRAIN_PLANE,dplane(a4)
        move.w #204,row_stride(a4)
        tst.w d2
        bne.s .setup                    ; mode 2: the caller's clip window
        clr.w clip_top(a4)
        move.w #168,clip_rows(a4)
        clr.w clip_lo(a4)
        move.w #204,clip_span(a4)
        bra.s .setup
.preview:
        move.l G_VIEW_BACK(a5),dest_ptr(a4)
        move.l #VIEW_PLANE,dplane(a4)
        move.w #44,row_stride(a4)
        clr.w clip_top(a4)
        move.w #160,clip_rows(a4)
        move.w #2,clip_lo(a4)
        move.w #40,clip_span(a4)
.setup: moveq #7,d5
        and.w d0,d5             ; pixel shift within a destination byte
        neg.w d5
        addq.w #8,d5            ; D5 = 8 - shift: byte << D5 spans two bytes
        asr.w #3,d0             ; floor division also for negative origins
        move.w d0,origin_q(a4)
        movem.l a5-a6,-(sp)
        move.l plane_size(a4),d2
        movea.l dplane(a4),a5
        clr.w source_y(a4)
.row:   move.w origin_y(a4),d0
        add.w source_y(a4),d0
        move.w d0,d3
        sub.w clip_top(a4),d3
        cmp.w clip_rows(a4),d3
        bhs .next_row           ; unsigned compare also rejects rows above
        mulu row_stride(a4),d0
        movea.l dest_ptr(a4),a0
        adda.l d0,a0
        move.w origin_q(a4),d7
        adda.w d7,a0            ; only dereferenced for clipped-in columns
        move.w source_y(a4),d0
        tst.b flipped(a4)
        beq.s .source_row
        neg.w d0                ; flip mask and colours together
        add.w height(a4),d0
        subq.w #1,d0
.source_row:
        mulu stride(a4),d0
        movea.l mask_ptr(a4),a1
        adda.l d0,a1
        movea.l image_ptr(a4),a2
        adda.l d0,a2
        move.w stride(a4),d6
        subq.w #1,d6
.byte:  moveq #0,d0
        move.b (a1)+,d0
        beq .next_byte          ; fully transparent source byte
        lsl.w d5,d0             ; D0 = mask over destination bytes q and q+1
        move.w d7,d3
        sub.w clip_lo(a4),d3
        cmp.w clip_span(a4),d3
        blo.s .high_in
        and.w #$00ff,d0
.high_in:
        addq.w #1,d3
        cmp.w clip_span(a4),d3
        blo.s .low_in
        and.w #$ff00,d0
.low_in:
        tst.w d0
        beq .next_byte
        movea.l a0,a3
        moveq #3,d4
        tst.b behind(a4)
        bne .behind
        tst.b negative(a4)
        bne.s .erase
        movea.l a2,a6
.plane: moveq #0,d1
        move.b (a6),d1
        lsl.w d5,d1
        and.w d0,d1             ; D1 = image bits inside the mask
        move.w d0,d3
        lsr.w #8,d3
        beq.s .low
        not.b d3
        and.b d3,(a3)
        move.w d1,d3
        lsr.w #8,d3
        or.b d3,(a3)
.low:   move.b d0,d3
        beq.s .plane_next
        not.b d3
        and.b d3,1(a3)
        or.b d1,1(a3)
.plane_next:
        adda.l d2,a6
        adda.l a5,a3
        dbra d4,.plane
        bra .next_byte
.erase: move.w d0,d1
        not.w d1                ; D1 = bits to keep in bytes q and q+1
        move.w d1,d3
        lsr.w #8,d3
.erase_plane:
        cmp.w #$00ff,d0         ; only touch clipped-in bytes
        bls.s .erase_low        ; high mask byte is zero
        and.b d3,(a3)
.erase_low:
        tst.b d0
        beq.s .erase_next
        and.b d1,1(a3)
.erase_next:
        adda.l a5,a3
        dbra d4,.erase_plane
        bra.s .next_byte
.behind:
        movea.l a0,a6                   ; the destination's fourth plane is
        adda.l a5,a6                    ; its solid terrain
        adda.l a5,a6
        adda.l a5,a6
        moveq #0,d1
        cmp.w #$00ff,d0                 ; only read clipped-in bytes
        bls.s .solid_low
        move.b (a6),d1
        lsl.w #8,d1
.solid_low:
        tst.b d0
        beq.s .solid
        move.b 1(a6),d1
.solid: not.w d1
        and.w d1,d0                     ; D0 = mask bits over no solid terrain
        beq.s .next_byte
        movea.l a2,a6
.behind_plane:
        moveq #0,d1
        move.b (a6),d1
        lsl.w d5,d1
        and.w d0,d1
        move.w d1,d3
        lsr.w #8,d3
        beq.s .behind_low
        or.b d3,(a3)
.behind_low:
        tst.b d1
        beq.s .behind_next
        or.b d1,1(a3)
.behind_next:
        adda.l d2,a6
        adda.l a5,a3
        dbra d4,.behind_plane
.next_byte:
        addq.l #1,a2
        addq.l #1,a0
        addq.w #1,d7
        dbra d6,.byte
.next_row:
        addq.w #1,source_y(a4)
        move.w source_y(a4),d0
        cmp.w height(a4),d0
        blo .row
        movem.l (sp)+,a5-a6
        rts

; Show or hide the status block by redirecting the end of the game's copper
; list and extending the display window below the skill panel.
show_status:
        movem.l d0-d7/a0-a3,-(sp)  ; the frame hook keeps queued input in D6/D7
        bsr status_full
        movem.l (sp)+,d0-d7/a0-a3
        move.w #$24c1,COPPER_DIWSTOP
        ifd RELOCATED
        move.l #CHIP_COPPER,d1
        move.l d1,d0
        clr.w d0
        swap d0
        or.l #$00840000,d0
        move.l d0,COPPER_END            ; COP2LCH
        and.l #$ffff,d1
        or.l #$00860000,d1
        move.l d1,COPPER_END+4          ; COP2LCL
        else
        move.l #$00840000+(CHIP_COPPER>>16),COPPER_END
        move.l #$00860000+(CHIP_COPPER&$ffff),COPPER_END+4
        endif
        move.l #$008a0000,COPPER_END+8
        rts
hide_status:
        move.w #$f4c1,COPPER_DIWSTOP
        move.l #$f401ff00,COPPER_END
        move.l #$009c8010,COPPER_END+4
        move.l #$fffffffe,COPPER_END+8
        rts

; Six 80-character rows in the existing 640x48 hires bitmap: four aligned
; 20-character columns, the room row and a footer with the level title and the
; credit. Glyphs use 8x8 cells. A3 is the text-row base and D4 the horizontal
; pixel offset. The layout of each mode is in params.s (custom_status).
;
; status_full draws the labels and values; with status_dirty 1 it overwrites
; them without clearing first, which changed values need (every field is a
; fixed-width run of whole cells, and a glyph overwrites its complete cell),
; so the block does not flicker. status_values then redraws only the brush
; fields whose value differs from what is on screen.
status_full:
        move.b status_dirty(a4),d0
        clr.b status_dirty(a4)
        cmp.b #1,d0
        beq custom_status
        lea CHIP_TEXT,a0
        move.w #TEXT_BYTES/4-1,d0
.clear: clr.l (a0)+
        dbra d0,.clear
        bra custom_status

; The level title in the footer, after the snap field.
status_title:
        lea LEVEL_RECORD+$7e0,a2
        lea CHIP_TEXT+5*640,a3
        move.w #17*8,d4
        moveq #31,d6
.title: moveq #0,d0
        move.b (a2)+,d0
        bsr glyph
        addq.w #8,d4
        dbra d6,.title
        rts

status_force:
        moveq #-1,d0            ; force every brush field to be drawn:
        move.w #$8000,shown_x(a4) ; values the fields never have
        move.w #$8000,shown_y(a4)
        move.w d0,shown_piece(a4)
        move.w d0,shown_remaining(a4)
        move.w #$0101,shown_sign(a4)
        move.b #1,shown_snap(a4)
status_values:
        cmp.b #3,edit_mode(a4)          ; the parameters use the first column
        beq .remaining
        move.w brush_x(a4),d0
        cmp.w shown_x(a4),d0
        beq.s .y
        move.w d0,shown_x(a4)
        lea CHIP_TEXT+0*640,a3
        move.w #12*8,d4
        bsr number
.y:     move.w brush_y(a4),d0
        cmp.w shown_y(a4),d0
        beq.s .piece
        move.w d0,shown_y(a4)
        lea CHIP_TEXT+1*640,a3
        move.w #12*8,d4
        bsr number
.piece: tst.b edit_mode(a4)          ; brush fields only with the brush
        bne .remaining
        move.w piece_id(a4),d0
        cmp.w shown_piece(a4),d0
        beq.s .sign
        move.w d0,shown_piece(a4)
        lea CHIP_TEXT+0*640,a3
        move.w #32*8,d4
        bsr number
.sign:  move.b negative(a4),d0          ; 0 add, -1 erase, 2 behind, 3 delete
        tst.b behind(a4)
        beq.s .deleting
        moveq #2,d0
.deleting:
        tst.b delete_mode(a4)
        beq.s .sign_state
        moveq #3,d0
.sign_state:
        cmp.b shown_sign(a4),d0
        beq.s .flip
        move.b d0,shown_sign(a4)
        lea CHIP_TEXT+2*640,a3
        move.w #32*8,d4
        lea brush_add(pc),a2
        tst.b d0
        beq.s .brush_text
        lea brush_erase(pc),a2
        bmi.s .brush_text
        lea brush_behind(pc),a2
        cmp.b #2,d0
        beq.s .brush_text
        lea brush_delete(pc),a2
.brush_text:
        moveq #5,d6
.brush_char:
        moveq #0,d0
        move.b (a2)+,d0
        bsr glyph
        addq.w #8,d4
        dbra d6,.brush_char
        lea status_rmb_add(pc),a2       ; the right button's help
        move.b shown_sign(a4),d0
        bmi.s .erase_help
        cmp.b #3,d0
        bne.s .help
.erase_help:
        lea status_rmb_erase(pc),a2
.help:  bsr status_texts
.flip:  move.b flipped(a4),d0
        cmp.b shown_flip(a4),d0
        beq.s .remaining
        move.b d0,shown_flip(a4)
        lea CHIP_TEXT+3*640,a3
        move.w #52*8,d4
        lea flip_off(pc),a2
        tst.b flipped(a4)
        beq.s .flip_state
        lea flip_on(pc),a2
.flip_state:
        moveq #2,d6
.flip_text:
        moveq #0,d0
        move.b (a2)+,d0
        bsr glyph
        addq.w #8,d4
        dbra d6,.flip_text
.remaining:
        move.b edit_mode(a4),d0         ; snap with the brush and the objects
        beq.s .snap
        cmp.b #2,d0
        bne.s .room_left
.snap:  move.b snap(a4),d0
        cmp.b shown_snap(a4),d0
        beq.s .room_left
        move.b d0,shown_snap(a4)
        lea CHIP_TEXT+5*640,a3
        move.w #12*8,d4
        lea flip_off(pc),a2
        tst.b d0
        beq.s .snap_state
        lea flip_on(pc),a2
.snap_state:
        moveq #2,d6
.snap_text:
        moveq #0,d0
        move.b (a2)+,d0
        bsr glyph
        addq.w #8,d4
        dbra d6,.snap_text
.room_left:
        move.w remaining(a4),d0
        cmp.w shown_remaining(a4),d0
        beq.s .done
        move.w d0,shown_remaining(a4)
        lea CHIP_TEXT+4*640,a3
        move.w #12*8,d4
        tst.w d0
        bne.s .room
        lea full_text(pc),a2
        moveq #3,d6
.full:  moveq #0,d0
        move.b (a2)+,d0
        bsr glyph
        addq.w #8,d4
        dbra d6,.full
        bra.s .done
.room:
        bsr number
.done:  rts
; Draw D0 as four decimal digits, or a negative D0 as a minus and three.
number:
        movem.l d0-d7/a0-a2,-(sp)
        moveq #3,d6                     ; digits after the first
        tst.w d0
        bpl.s .digits
        neg.w d0
        move.w d0,-(sp)
        moveq #'-',d0
        bsr glyph
        addq.w #8,d4
        move.w (sp)+,d0
        moveq #2,d6
.digits:
        and.l #$ffff,d0
        jsr NUMBER_DIGITS                       ; four ASCII digits, changes D0..D3
        move.l d0,d5
        cmp.w #2,d6
        bne.s .loop
        rol.l #8,d5                     ; the thousands are not shown
.loop:  rol.l #8,d5
        moveq #0,d0
        move.b d5,d0
        bsr glyph
        addq.w #8,d4
        dbra d6,.loop
        movem.l (sp)+,d0-d7/a0-a2
        rts

; Copy the editor's 5x7 glyphs into 8x8 cells without resampling. Leave a
; blank top row and one left/two right pixels for sharp, separated letters.
prepare_font:
        lea font(pc),a1
        lea font_source(pc),a0
        moveq #94,d5
.char:  clr.b (a1)+
        moveq #6,d4
.row:   move.b (a0)+,d1
        lsl.b #2,d1
        move.b d1,(a1)+
        dbra d4,.row
        dbra d5,.char
        rts
; Draw character D0 into one 8x8 cell.
glyph:
        movem.l d0-d1/a0-a1,-(sp)
        cmp.w #32,d0
        bls.s .blank
        cmp.w #126,d0
        bls.s .known
.blank: moveq #32,d0            ; the space glyph is all zero
.known: sub.w #32,d0
        lsl.w #3,d0
        lea font(pc),a0
        adda.w d0,a0
        movea.l a3,a1
        move.w d4,d0
        lsr.w #3,d0
        adda.w d0,a1
        moveq #7,d1
.row:   move.b (a0)+,(a1)
        lea 80(a1),a1
        dbra d1,.row
.done:  movem.l (sp)+,d0-d1/a0-a1
        rts

copper_template:
        dc.w $f401,$ff00,$009c,$8010
        dc.w $0100,$9200,$0102,0,$0108,0,$010a,0
COPPER_TEXT     equ *-copper_template
        ifd RELOCATED
        dc.w $00e0,0,$00e2,0,$0182,$0fff ; set by install
        else
        dc.w $00e0,CHIP_TEXT>>16,$00e2,CHIP_TEXT&$ffff,$0182,$0fff
        endif
        dc.w $ffff,$fffe
copper_end:
ground_name: dc.b 'Ground1',0
flip_off: dc.b 'Off'
flip_on: dc.b 'On '
brush_add: dc.b '+     '
brush_erase: dc.b '-     '
brush_behind: dc.b 'Behind'
brush_delete: dc.b 'Delete'
full_text: dc.b 'Full'

; Original 5x7 ASCII bitmap font, authored for the editor.
; Seven rows per glyph; the low five bits run left to right.
font_source:
        dc.b $00,$00,$00,$00,$00,$00,$00 ; $20 space
        dc.b $04,$04,$04,$04,$04,$00,$04 ; $21 !
        dc.b $0a,$0a,$0a,$00,$00,$00,$00 ; $22 "
        dc.b $0a,$1f,$0a,$0a,$1f,$0a,$00 ; $23 #
        dc.b $04,$0f,$14,$0e,$05,$1e,$04 ; $24 $
        dc.b $19,$1a,$02,$04,$08,$0b,$13 ; $25 %
        dc.b $0c,$12,$14,$0c,$15,$12,$0d ; $26 &
        dc.b $04,$04,$08,$00,$00,$00,$00 ; $27 '
        dc.b $02,$04,$08,$08,$08,$04,$02 ; $28 (
        dc.b $08,$04,$02,$02,$02,$04,$08 ; $29 )
        dc.b $00,$15,$0e,$1f,$0e,$15,$00 ; $2a *
        dc.b $00,$04,$04,$1f,$04,$04,$00 ; $2b +
        dc.b $00,$00,$00,$00,$04,$04,$08 ; $2c ,
        dc.b $00,$00,$00,$1f,$00,$00,$00 ; $2d -
        dc.b $00,$00,$00,$00,$00,$00,$04 ; $2e .
        dc.b $01,$02,$02,$04,$08,$08,$10 ; $2f /
        dc.b $0e,$11,$13,$15,$19,$11,$0e ; $30 0
        dc.b $04,$0c,$04,$04,$04,$04,$0e ; $31 1
        dc.b $0e,$11,$01,$02,$04,$08,$1f ; $32 2
        dc.b $1e,$01,$01,$0e,$01,$01,$1e ; $33 3
        dc.b $02,$06,$0a,$12,$1f,$02,$02 ; $34 4
        dc.b $1f,$10,$10,$1e,$01,$01,$1e ; $35 5
        dc.b $0e,$10,$10,$1e,$11,$11,$0e ; $36 6
        dc.b $1f,$01,$02,$04,$08,$08,$08 ; $37 7
        dc.b $0e,$11,$11,$0e,$11,$11,$0e ; $38 8
        dc.b $0e,$11,$11,$0f,$01,$01,$0e ; $39 9
        dc.b $00,$04,$00,$00,$04,$00,$00 ; $3a :
        dc.b $00,$04,$00,$00,$04,$04,$08 ; $3b ;
        dc.b $02,$04,$08,$10,$08,$04,$02 ; $3c <
        dc.b $00,$00,$1f,$00,$1f,$00,$00 ; $3d =
        dc.b $08,$04,$02,$01,$02,$04,$08 ; $3e >
        dc.b $0e,$11,$01,$02,$04,$00,$04 ; $3f ?
        dc.b $0e,$11,$17,$15,$17,$10,$0f ; $40 @
        dc.b $0e,$11,$11,$1f,$11,$11,$11 ; $41 A
        dc.b $1e,$11,$11,$1e,$11,$11,$1e ; $42 B
        dc.b $0f,$10,$10,$10,$10,$10,$0f ; $43 C
        dc.b $1e,$11,$11,$11,$11,$11,$1e ; $44 D
        dc.b $1f,$10,$10,$1e,$10,$10,$1f ; $45 E
        dc.b $1f,$10,$10,$1e,$10,$10,$10 ; $46 F
        dc.b $0f,$10,$10,$17,$11,$11,$0e ; $47 G
        dc.b $11,$11,$11,$1f,$11,$11,$11 ; $48 H
        dc.b $0e,$04,$04,$04,$04,$04,$0e ; $49 I
        dc.b $01,$01,$01,$01,$11,$11,$0e ; $4a J
        dc.b $11,$12,$14,$18,$14,$12,$11 ; $4b K
        dc.b $10,$10,$10,$10,$10,$10,$1f ; $4c L
        dc.b $11,$1b,$15,$15,$11,$11,$11 ; $4d M
        dc.b $11,$19,$15,$13,$11,$11,$11 ; $4e N
        dc.b $0e,$11,$11,$11,$11,$11,$0e ; $4f O
        dc.b $1e,$11,$11,$1e,$10,$10,$10 ; $50 P
        dc.b $0e,$11,$11,$11,$15,$12,$0d ; $51 Q
        dc.b $1e,$11,$11,$1e,$14,$12,$11 ; $52 R
        dc.b $0f,$10,$10,$0e,$01,$01,$1e ; $53 S
        dc.b $1f,$04,$04,$04,$04,$04,$04 ; $54 T
        dc.b $11,$11,$11,$11,$11,$11,$0e ; $55 U
        dc.b $11,$11,$11,$11,$11,$0a,$04 ; $56 V
        dc.b $11,$11,$11,$15,$15,$1b,$11 ; $57 W
        dc.b $11,$11,$0a,$04,$0a,$11,$11 ; $58 X
        dc.b $11,$11,$0a,$04,$04,$04,$04 ; $59 Y
        dc.b $1f,$01,$02,$04,$08,$10,$1f ; $5a Z
        dc.b $0e,$08,$08,$08,$08,$08,$0e ; $5b [
        dc.b $10,$08,$08,$04,$02,$02,$01 ; $5c \
        dc.b $0e,$02,$02,$02,$02,$02,$0e ; $5d ]
        dc.b $04,$0a,$11,$00,$00,$00,$00 ; $5e ^
        dc.b $00,$00,$00,$00,$00,$00,$1f ; $5f _
        dc.b $08,$04,$00,$00,$00,$00,$00 ; $60 `
        dc.b $00,$00,$0e,$01,$0f,$11,$0f ; $61 a
        dc.b $10,$10,$1e,$11,$11,$11,$1e ; $62 b
        dc.b $00,$00,$0e,$10,$10,$10,$0e ; $63 c
        dc.b $01,$01,$0f,$11,$11,$11,$0f ; $64 d
        dc.b $00,$00,$0e,$11,$1f,$10,$0f ; $65 e
        dc.b $06,$08,$08,$1e,$08,$08,$08 ; $66 f
        dc.b $00,$0f,$11,$11,$0f,$01,$0e ; $67 g
        dc.b $10,$10,$1e,$11,$11,$11,$11 ; $68 h
        dc.b $04,$00,$0c,$04,$04,$04,$0e ; $69 i
        dc.b $02,$00,$06,$02,$02,$12,$0c ; $6a j
        dc.b $10,$10,$12,$14,$18,$14,$12 ; $6b k
        dc.b $0c,$04,$04,$04,$04,$04,$0e ; $6c l
        dc.b $00,$00,$1a,$15,$15,$15,$11 ; $6d m
        dc.b $00,$00,$1e,$11,$11,$11,$11 ; $6e n
        dc.b $00,$00,$0e,$11,$11,$11,$0e ; $6f o
        dc.b $00,$1e,$11,$11,$1e,$10,$10 ; $70 p
        dc.b $00,$0f,$11,$11,$0f,$01,$01 ; $71 q
        dc.b $00,$00,$16,$18,$10,$10,$10 ; $72 r
        dc.b $00,$00,$0f,$10,$0e,$01,$1e ; $73 s
        dc.b $08,$08,$1e,$08,$08,$08,$06 ; $74 t
        dc.b $00,$00,$11,$11,$11,$11,$0f ; $75 u
        dc.b $00,$00,$11,$11,$11,$0a,$04 ; $76 v
        dc.b $00,$00,$11,$11,$15,$15,$0a ; $77 w
        dc.b $00,$00,$11,$0a,$04,$0a,$11 ; $78 x
        dc.b $00,$11,$11,$11,$0f,$01,$0e ; $79 y
        dc.b $00,$00,$1f,$02,$04,$08,$1f ; $7a z
        dc.b $03,$04,$04,$08,$04,$04,$03 ; $7b {
        dc.b $04,$04,$04,$04,$04,$04,$04 ; $7c |
        dc.b $18,$04,$04,$02,$04,$04,$18 ; $7d }
        dc.b $00,$00,$09,$16,$00,$00,$00 ; $7e ~
        even

        even

; In Lemmings the image is stored packed in the file Editor on disk 1, behind
; the boot loader, and the bootstrap unpacks it into the reserved block; in
; Holiday Lemmings 1994 it is a hunk of the game's program.
        ifnd FILES
        include "disk_codec.s"
        endif
        include "disk_io.s"
        include "menu.s"
        ifd HOLIDAY94
        include "holiday94.s"
        else
        include "title.s"
        endif
        include "levels.s"
        include "level_save.s"
        include "level_delete.s"
        include "steel.s"
        include "objects.s"
        include "undo.s"
        include "delete.s"
        include "params.s"

; Runtime storage follows the file image in the reserved editor block.
; The installer clears it before publishing any hooks.
image_end:
state           equ image_end
placements      equ state+STATE_SIZE
font            equ placements+MAX_PLACEMENTS*4
save_record     equ font+760
level_slots     equ save_record+2048 ; occupied level disk slots in order
level_status    equ level_slots+318*2
level_titles    equ level_status+320
list_text       equ level_titles+318*32
list_path       equ list_text+600   ; FILES: Levels/ and a name of up to 107 characters
custom_record   equ list_path+116   ; the custom level being played
title_buf       equ custom_record+2048 ; 32 characters, NUL, and a spare NUL
custom_file     equ title_buf+34    ; FILES: the file name of the edited level
undo_entries    equ custom_file+108 ; UNDO_STEPS entries and a spare one (undo.s)
undo_lost       equ undo_entries+(UNDO_STEPS+1)*UNDO_ENTRY ; dropped by undo_new
storage_end     equ undo_lost+UNDO_ENTRY
