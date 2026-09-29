; Lemmings In-Game Level Editor V1.2
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Lemmings in-game terrain editor (68000, position independent).
;
; Loaded by the bootstrap into a reserved block of slow RAM and entered once at
; "install", which patches jumps into the game's main loop, keyboard interrupt
; and level setup. All game addresses refer to the supported game version,
; whose disk images patch.py identifies by SHA-256. Inside the hooks A4 points
; to the editor's own state and A5 to the game's global variables.
GFX             equ $8000
GFX_MAX_BYTES   equ 42200
EDITOR_RESERVE  equ $20000
; CPU-only disk workspace after the largest Ground resource. These buffers
; are initialized by their producers, not by the pre-Ground storage clear.
DISK_WORK       equ $12800
DISK_TRACK      equ DISK_WORK
DISK_VERIFY     equ DISK_TRACK+TRACK_BYTES
DISK_HEADER     equ DISK_VERIFY+TRACK_BYTES
DISK_ROWS       equ DISK_HEADER+TRACK_BYTES
DISK_REINDEX    equ DISK_ROWS+32*20
DISK_WORK_END   equ DISK_REINDEX+INDEX_BYTES
        xdef GFX_MAX_BYTES,EDITOR_RESERVE,DISK_WORK_END
CHIP_TEXT       equ $21d00            ; above the bootstrap appended to Code
CHIP_COPPER     equ $22c00
        xdef CHIP_TEXT,CHIP_COPPER
TEXT_BYTES      equ 3840
active          equ 0
old_pause       equ 1
last_key        equ 2
negative        equ 3
last_left       equ 4
last_right      equ 5
piece_id        equ 6
piece_count     equ 8
brush_x         equ 10
brush_y         equ 12
width           equ 14
height          equ 16
stride          equ 18
plane_size      equ 20
image_ptr       equ 24
mask_ptr        equ 28
gfx_ptr         equ 32
mode            equ 36
origin_x        equ 38
origin_y        equ 40
origin_q        equ 42              ; destination byte column of the piece's left edge
source_y        equ 44
valid           equ 46
paint_count     equ 48
pending_toggle  equ 52
pending_cycle   equ 53
dirty           equ 54
last_x          equ 56
last_y          equ 58
last_scroll     equ 60
suppress_mouse  equ 62
render_count    equ 64
flipped         equ 68
pending_flip    equ 69
dplane          equ 72              ; destination plane stride
dest_ptr        equ 76              ; destination surface base
row_stride      equ 80
dest_height     equ 82
clip_lo         equ 84              ; first writable destination byte column
clip_span       equ 86              ; number of writable byte columns
shown_x         equ 88              ; values currently drawn in the status block
shown_y         equ 90
shown_piece     equ 92
shown_sign      equ 94
shown_flip      equ 95
original_count  equ 96
remaining       equ 98
shown_remaining equ 100
level_id        equ 102
base_crc        equ 104
load_pending    equ 108             ; accepted request, retained across level capture
load_reopen     equ 109             ; return to the editor after original startup
load_error      equ 110             ; freshly loaded base rejected the request
disk_busy       equ 112             ; synchronous ownership of the back buffer
disk_cancel     equ 113
disk_committing equ 114             ; finish verification even if Esc is pressed
disk_raw        equ 116
disk_old_adk    equ 120
disk_old_dma    equ 122
disk_old_int    equ 124
disk_drive      equ 126             ; CIA-B select bit, 3..6
disk_cylinder   equ 127
disk_redraw     equ 128
disk_track_no   equ 130
disk_free       equ 132
disk_rows       equ 134
menu_mode       equ 136             ; 0 = closed, otherwise the menu's state
menu_kind       equ 137             ; 0 = save, 1 = load
menu_sel        equ 138             ; selected row
menu_rows       equ 140
menu_new        equ 142             ; the first row is "new save"
save_drive      equ 143             ; drive of the last save disk + 1, or 0
menu_drive      equ 144
native_drive    equ 145             ; drive the game reads disk 2 from
native_used     equ 146             ; a disk was taken from that drive
pending_menu    equ 147             ; S or L pressed: 1 = save, 2 = load
key_head        equ 148
key_tail        equ 149
key_queue       equ 150             ; 16 raw key codes
shift           equ 166
name_len        equ 167
name            equ 168             ; 16 characters, NUL padded
name_end        equ 184             ; always NUL
menu_action     equ 185
menu_after      equ 186
menu_prompt     equ 187             ; drive shown in the save-disk prompt
menu_msg        equ 188
palette_save    equ 192             ; five copper colour values
menu_slot       equ 202
list_ok         equ 204             ; the list reflects a successful scan
menu_line       equ 206             ; 42-character text line
STATE_SIZE      equ 248
MAX_PLACEMENTS  equ 400

        org 0
; Install the hooks: keyboard interrupt ($174E), frame start ($654), gameplay
; input ($680), level setup ($2762) and end of frame drawing ($688). Also
; prepares the font and the copper list continuation for the status block.
install:
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        movea.l a4,a0
        move.w #(storage_end-state)/2-1,d0
.clear: clr.w (a0)+
        dbra d0,.clear
        movea.l $f8(a5),a0
        adda.l #GFX,a0
        move.l a0,gfx_ptr(a4)
        lea keyboard(pc),a0
        move.l a0,$1750
        move.w #$4ef9,$174e
        move.l #$4e714e71,$1754
        move.w #$4e71,$1758
        bsr prepare_font
        lea frame(pc),a0
        move.l a0,$656
        move.w #$4ef9,$654
        move.w #$4e71,$65a
        lea actions(pc),a0
        move.l a0,$682
        move.w #$4ef9,$680
        move.w #$4e71,$686
        lea capture(pc),a0
        move.l a0,$2764
        move.w #$4ef9,$2762
        move.w #$4e71,$2768
        lea overlay(pc),a0
        move.l a0,$68a
        move.w #$4ef9,$688
        move.w #$4e71,$68e
        bsr install_load_hooks
        lea copper_template(pc),a0
        lea CHIP_COPPER,a1
        move.w #(copper_end-copper_template)/2-1,d0
.copy:  move.w (a0)+,(a1)+
        dbra d0,.copy
        movem.l (sp)+,d0-d7/a0-a6
        rts

; Level setup hook. Resets the editor, loads and unpacks the level's Ground
; graphics into editor memory (the game later overwrites its own copy with
; sound data) and counts the terrain pieces of the level's graphics set.
capture:
        jsr $280a
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        bsr hide_status
        clr.b active(a4)
        clr.b load_error(a4)
        clr.b valid(a4)
        clr.b negative(a4)
        clr.w flipped(a4)       ; orientation and queued F press
        clr.w pending_toggle(a4)
        clr.b pending_menu(a4)
        clr.w piece_id(a4)
        clr.l paint_count(a4)
        move.w $42(a5),level_id(a4)
        bsr count_placements
        lea $c5a6,a0
        move.l #2048,d0
        moveq #-1,d1
        bsr crc32
        move.l d0,base_crc(a4)
        move.b $26(a5),last_key(a4)
        lea ground_name(pc),a0
        move.w $c5c0,d0
        cmp.w #4,d0
        bhi.s .done
        add.b #'1',d0
        move.b d0,6(a0)
        movea.l gfx_ptr(a4),a1
        moveq #0,d1
        jsr $3286
        movea.l gfx_ptr(a4),a0
        movea.l a0,a1
        move.l d1,d0
        jsr $3934
        movea.l $fc(a5),a0
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
.done:  bsr check_loaded_base
        movem.l (sp)+,d0-d7/a0-a6
        jsr $2826
        jmp $276a

; Capture press edges before the original CIA acknowledgement. Releases never
; overwrite queued presses, so a quick tap survives a long brush render.
keyboard:
        move.b d0,$26(a5)
        lea state(pc),a4
        tst.b disk_busy(a4)
        beq.s .menu
        cmp.b #$45,d0                  ; Esc cancels a disk operation
        bne.s .ack
        st disk_cancel(a4)
        bra.s .ack
.menu:  tst.b menu_mode(a4)
        beq.s .editor
        bsr menu_queue_key
        bra.s .ack
.editor:
        tst.b d0
        bmi.s .ack
        cmp.b #$21,d0                  ; S: save menu
        bne.s .load
        tst.b active(a4)
        beq.s .ack
        move.b #1,pending_menu(a4)
        bra.s .ack
.load:  cmp.b #$28,d0                  ; L: load menu
        bne.s .toggle
        tst.b active(a4)
        beq.s .ack
        move.b #2,pending_menu(a4)
        bra.s .ack
.toggle:
        cmp.b #$12,d0
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
        bne.s .ack
        tst.b active(a4)
        beq.s .ack
        eori.b #1,pending_flip(a4)
.ack:   move.b #0,$bfec01
        jmp $175a

; Frame start hook. Handles E (enter/leave editor mode, saving and restoring
; the game's pause flag), piece cycling, flip, scrolling and the mouse buttons,
; and paints into the level when the left button is pressed. While the editor
; is open the viewport is redrawn only when something visible changed.
frame:
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        tst.b load_pending(a4)
        bne restart_saved_level
        tst.b load_reopen(a4)
        beq.s .input
        clr.b load_reopen(a4)
        move.b #1,pending_toggle(a4)
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
        bsr menu_open
        bra.s .menu_idle
.menu:  bsr menu_frame
.menu_idle:
        movem.l (sp)+,d0-d7/a0-a6
        clr.w $3e(a5)
        jmp $646
.editor_input:
        move.w sr,-(sp)
        ori.w #$0700,sr
        moveq #0,d6
        move.w pending_toggle(a4),d0
        move.b d0,d6
        clr.w pending_toggle(a4)
        move.b pending_flip(a4),d7
        clr.b pending_flip(a4)
        move.w (sp)+,sr
        lsr.w #8,d0
        tst.b d0
        beq.s .cycle
        st dirty(a4)
        tst.b $30(a5)           ; single-player only
        bne .buttons
        tst.b valid(a4)
        beq .buttons
        tst.b $29(a5)           ; no entry during level completion
        bne .buttons
        tst.b $2d(a5)
        bne .buttons
        not.b active(a4)
        beq.s .leave
        move.b $39(a5),old_pause(a4)
        st $39(a5)
        btst #6,$bfe001
        seq last_left(a4)
        btst #2,$16(a6)
        seq last_right(a4)
        clr.l $144f2           ; hide the skill-selection sprite
        bsr show_status
        bra .buttons
.leave: move.b old_pause(a4),$39(a5)
        st suppress_mouse(a4)
        clr.b $27(a5)           ; do not replay editor keys in gameplay
        clr.b $28(a5)
        bsr hide_status
        bra .buttons
.cycle: move.w d6,d0
        tst.b active(a4)
        beq .buttons
        tst.b d0
        beq .buttons
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
        tst.b active(a4)
        beq .done
        st $39(a5)
        tst.b d7
        beq.s .brush
        not.b flipped(a4)
        st dirty(a4)
.brush:
        bsr scroll
        bsr coordinates
        bsr descriptor
        btst #2,$16(a6)
        seq d0
        cmp.b last_right(a4),d0
        beq.s .left
        move.b d0,last_right(a4)
        tst.b d0
        beq.s .left
        not.b negative(a4)
        st dirty(a4)
.left:  btst #6,$bfe001
        seq d0
        cmp.b last_left(a4),d0
        beq .done
        move.b d0,last_left(a4)
        tst.b d0
        beq .done
        cmpi.w #160,$9dac
        bhs .done
        tst.w remaining(a4)
        beq .done
        bsr record_placement
        move.w brush_x(a4),d0
        move.w brush_y(a4),d1
        moveq #0,d2
        bsr composite
        jsr $4b3a
        jsr $4a78
        addq.l #1,paint_count(a4)
        st dirty(a4)
.done:  tst.b active(a4)
        beq.s .game
        tst.b dirty(a4)
        bne.s .redraw
        move.w $9da8,d0
        cmp.w last_scroll(a4),d0
        bne.s .redraw
        move.w $9dac,d0
        cmp.w #160,d0
        blo.s .viewport
        ; Cursor over the panel: there is no preview to move, so only the
        ; coordinates change. Update them without redrawing the viewport,
        ; unless the cursor just left the viewport and its preview must go.
        cmpi.w #160,last_y(a4)
        blo.s .redraw
        move.w d0,last_y(a4)
        move.w $9daa,last_x(a4)
        bsr coordinates
        bsr status_values
        bra.s .idle
.viewport:
        cmp.w last_y(a4),d0
        bne.s .redraw
        move.w $9daa,d0
        cmp.w last_x(a4),d0
        bne.s .redraw
.idle:  movem.l (sp)+,d0-d7/a0-a6
        clr.w $3e(a5)
        jmp $646
.redraw:
        move.w $9daa,last_x(a4)
        move.w $9dac,last_y(a4)
        move.w $9da8,last_scroll(a4)
        movem.l (sp)+,d0-d7/a0-a6
        clr.w $3e(a5)
        jmp $65c
.game:  movem.l (sp)+,d0-d7/a0-a6
        jsr $1898
        clr.w $3e(a5)
        jmp $65c

; Count only the terrain records consumed by normal level construction.
; Special backgrounds bypass the original placement list. The scan is bounded
; by the level record's terrain region even if no sentinel is present.
count_placements:
        moveq #0,d0
        tst.w $c5c2
        bne.s .counted
        lea $c6c6,a0
.scan:  cmpi.l #-1,(a0)+
        beq.s .counted
        addq.w #1,d0
        cmp.w #MAX_PLACEMENTS,d0
        blo.s .scan
.counted:
        move.w d0,original_count(a4)
        neg.w d0
        add.w #MAX_PLACEMENTS,d0
        move.w d0,remaining(a4)
        rts

; Append one placement before changing terrain. The list is separate from the
; game's level record; paint_count bounds its live entries. H holds a 13-bit
; x origin, erase bit 13 and flip bit 14. L holds signed y in bits 7..15 and
; the piece ID in bits 0..5. Negative x origins use 13-bit two's complement;
; replay must sign-extend these, unlike the original unsigned x decoder.
record_placement:
        move.w brush_x(a4),d0
        move.w width(a4),d2
        lsr.w #1,d2
        sub.w d2,d0
        and.w #$1fff,d0
        tst.b negative(a4)
        beq.s .flip
        or.w #$2000,d0
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
        cmpi.w #160,$9dac
        bhs .done
        tst.w $9daa
        bne.s .right
        subi.w #16,$9da8
        bpl.s .done
        clr.w $9da8
        rts
.right: cmpi.w #319,$9daa
        bne.s .done
        addi.w #16,$9da8
        cmpi.w #1280,$9da8
        bls.s .done
        move.w #1280,$9da8
.done:  rts

; Cursor position in level coordinates.
coordinates:
        move.w $9daa,d0
        add.w $9da8,d0
        add.w #16,d0
        move.w d0,brush_x(a4)
        move.w $9dac,d0
        addq.w #4,d0
        move.w d0,brush_y(a4)
        rts

; Size and graphics of the selected piece, from the level's style data.
descriptor:
        movea.l $fc(a5),a0
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
        sub.l #$75578,d1
        move.l 4(a0),d0
        add.l d1,d0
        move.l d0,image_ptr(a4)
        move.l 8(a0),d0
        add.l d1,d0
        move.l d0,mask_ptr(a4)
        rts

; Gameplay input hook: skip the game's mouse and keyboard actions while the
; editor is open, and ignore mouse buttons still held when it closes.
actions:
        lea state(pc),a0
        tst.b active(a0)
        bne.s .skip
        tst.b suppress_mouse(a0)
        beq.s .mouse
        btst #6,$bfe001
        beq.s .keyboard
        btst #2,$16(a6)
        beq.s .keyboard
        clr.b suppress_mouse(a0)
.mouse: jsr $b4a
.keyboard:
        jsr $14e2
.skip:  jmp $688

; End of frame drawing: draw the brush preview and update the status block
; before the new frame is shown.
overlay:
        jsr $1f52
        jsr $4aa4
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        tst.b active(a4)
        beq .done
        tst.b 2(a6)             ; first DMACONR read may be stale on old Agnus
.wait:  btst #6,2(a6)
        bne.s .wait
        bsr coordinates
        bsr descriptor
        cmpi.w #160,$9dac
        bhs.s .status
        move.w $9daa,d0
        add.w #16,d0
        move.w $9dac,d1
        moveq #1,d2
        bsr composite
.status:
        bsr status_values
        addq.l #1,render_count(a4)
        jsr $1898
.done:  movem.l (sp)+,d0-d7/a0-a6
        jmp $690

; CPU masked compositor. D0/D1 identify the cursor in the target surface and
; D2 selects the target: 0 = world terrain, 1 = viewport back buffer (preview).
; The piece is centred on the cursor; for odd dimensions the middle pixel is
; the anchor. The unclamped origin is kept so clipping crops the shape without
; shifting it. Collision guard rows are cleared later by the caller.
;
; Works on whole source bytes: every piece width is a multiple of 8, so each
; mask/image byte covers 8 pixels. The byte is shifted into a 16-bit word that
; spans two destination bytes. Destination clipping is byte-granular because
; both surfaces' visible limits are byte aligned (world 0..1631, viewport
; 16..335). Positive mode replaces masked pixels with the image planes;
; negative mode clears masked pixels in all four planes. A5/A6 are preserved.
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
        tst.w d2
        bne.s .preview
        move.l #$37080,dest_ptr(a4)
        move.l #$85e0,dplane(a4)
        move.w #204,row_stride(a4)
        move.w #168,dest_height(a4)
        clr.w clip_lo(a4)
        move.w #204,clip_span(a4)
        bra.s .setup
.preview:
        move.l $cc(a5),dest_ptr(a4)
        move.l #$2100,dplane(a4)
        move.w #44,row_stride(a4)
        move.w #160,dest_height(a4)
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
        cmp.w dest_height(a4),d0
        bhs .next_row           ; unsigned compare also rejects negative rows
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
        beq.s .next_byte
        movea.l a0,a3
        moveq #3,d4
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
        bra.s .next_byte
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
        move.w #$24c1,$84ee
        move.l #$00840000+(CHIP_COPPER>>16),$8668
        move.l #$00860000+(CHIP_COPPER&$ffff),$866c
        move.l #$008a0000,$8670
        rts
hide_status:
        move.w #$f4c1,$84ee
        move.l #$f401ff00,$8668
        move.l #$009c8010,$866c
        move.l #$fffffffe,$8670
        rts

; Six 80-character rows in the existing 640x48 hires bitmap. Four aligned
; 20-character columns, a spacer and a footer. Glyphs use 8x8 cells.
; A3 is the text-row base and D4 the horizontal pixel offset.
;
; status_full draws everything once when the editor opens: labels, title and
; the values that cannot change while editing. status_values then redraws only
; the brush fields whose value differs from what is on screen. Every field is
; a fixed-width run of whole cells and glyph overwrites complete cells, so no
; clearing is needed for an update.
status_full:
        lea CHIP_TEXT,a0
        move.w #TEXT_BYTES/4-1,d0
.clear: clr.l (a0)+
        dbra d0,.clear
        lea labels(pc),a2
        lea CHIP_TEXT,a3
        moveq #5,d7
.line:  moveq #0,d4
        moveq #79,d6
.char:  moveq #0,d0
        move.b (a2)+,d0
        cmp.b #' ',d0
        beq.s .blank            ; the bitmap is already clear
        bsr glyph
.blank: addq.w #8,d4
        dbra d6,.char
        lea 640(a3),a3
        dbra d7,.line
        lea CHIP_TEXT+2*640,a3
        move.w #12*8,d4
        move.w $42(a5),d0
        addq.w #1,d0
        bsr number
        lea CHIP_TEXT+3*640,a3
        move.w #12*8,d4
        move.w $c5c0,d0
        addq.w #1,d0
        bsr number
        lea CHIP_TEXT+1*640,a3
        move.w #32*8,d4
        move.w piece_count(a4),d0
        bsr number
        lea CHIP_TEXT+3*640,a3
        move.w #32*8,d4
        move.w $c5c2,d0
        bsr number
        lea CHIP_TEXT+0*640,a3
        move.w #52*8,d4
        move.w $c5a8,d0
        bsr number
        lea CHIP_TEXT+1*640,a3
        move.w #52*8,d4
        move.w $c5aa,d0
        bsr number
        lea CHIP_TEXT+2*640,a3
        move.w #52*8,d4
        move.w $c5ac,d0
        bsr number
        lea $cd86,a2
        lea CHIP_TEXT+5*640,a3
        moveq #0,d4
        moveq #31,d6
.title: moveq #0,d0
        move.b (a2)+,d0
        bsr glyph
        addq.w #8,d4
        dbra d6,.title
        moveq #-1,d0            ; force every brush field to be drawn:
        move.w d0,shown_x(a4)   ; -1 and 1 are never valid field values
        move.w d0,shown_y(a4)
        move.w d0,shown_piece(a4)
        move.w d0,shown_remaining(a4)
        move.w #$0101,shown_sign(a4)
status_values:
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
.piece: move.w piece_id(a4),d0
        cmp.w shown_piece(a4),d0
        beq.s .sign
        move.w d0,shown_piece(a4)
        lea CHIP_TEXT+0*640,a3
        move.w #32*8,d4
        bsr number
.sign:  move.b negative(a4),d0
        cmp.b shown_sign(a4),d0
        beq.s .flip
        move.b d0,shown_sign(a4)
        lea CHIP_TEXT+2*640,a3
        move.w #32*8,d4
        moveq #'+',d0
        tst.b negative(a4)
        beq.s .draw_sign
        moveq #'-',d0
.draw_sign:
        bsr glyph
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
; Draw D0 as four decimal digits.
number:
        movem.l d0-d7/a0-a2,-(sp)
        and.l #$ffff,d0
        move.l d0,d2
        jsr $1862
        move.l d0,d5
        moveq #3,d6
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
        dc.w $00e0,CHIP_TEXT>>16,$00e2,CHIP_TEXT&$ffff,$0182,$0fff
        dc.w $ffff,$fffe
copper_end:
ground_name: dc.b 'Ground1',0
flip_off: dc.b 'Off'
flip_on: dc.b 'On '
full_text: dc.b 'Full'
labels:
        dc.b 'X Coord             Piece               Lemmings            LMB: Place          '
        dc.b 'Y Coord             Piece Types         To Save             RMB: Add/Erase      '
        dc.b 'Level               Brush               Minutes             Left/Right: Piece   '
        dc.b 'Ground              Special             Flip                F: Flip   E: Resume '
        dc.b 'Room                                                        S: Save   L: Load   '
        dc.b '                                                    Editor V1.2 by Timo Heimonen'
        even

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

        include "save_load.s"
        include "menu.s"

; The code from here to image_end is stored separately, as the Editor2 file on
; disk 1. The bootstrap loads it before the game asks for disk 2 and unpacks it
; directly behind the first part, so the image in memory is contiguous.
        even
editor2_start:
        ifnd WHDLOAD
        include "disk_codec.s"
        endif
        include "disk_io.s"
        include "disk_index.s"

; Runtime storage follows the file image in the reserved editor block.
; The installer clears it before publishing any hooks.
image_end:
state           equ image_end
placements      equ state+STATE_SIZE
font            equ placements+MAX_PLACEMENTS*4
load_record     equ font+760
save_record     equ load_record+2048
storage_end     equ save_record+2048
