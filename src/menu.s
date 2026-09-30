; Lemmings In-Game Level Editor V2.0
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The editor's menu: saving a custom level (S) and its title (N), with
; messages and disk prompts (level_save.s), and the question before leaving a
; level with unsaved changes (Esc). The menu covers the paused level
; view: it is drawn with the editor's font into the displayed viewport buffer
; while disk transfers borrow the other buffer, and copper colours 0..4 of the
; level view are replaced while it is open. It runs from the frame hook; the
; game loop is idle until the menu closes. The key queue also serves the
; custom level list (levels.s).
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

M_MESSAGE       equ 1
M_PROMPT_DISK2  equ 2
M_TITLE         equ 3
M_PROMPT_LEVEL  equ 4
M_LEAVE         equ 5

PANEL_FG        equ 1
PANEL_BAR       equ 2
PANEL_HELP      equ 4
VIEW_PALETTE    equ $850e               ; copper value word of COLOR00

KEY_RETURN      equ $44
KEY_ENTER       equ $43
KEY_ESC         equ $45
KEY_BACKSPACE   equ $41
KEY_UP          equ $4c
KEY_DOWN        equ $4d
KEY_RIGHT       equ $4e
KEY_LEFT        equ $4f
KEY_N           equ $36
KEY_E           equ $12

; ---------------------------------------------------------------------------
; Opening and closing

; D0: 0 = saving the level, 1 = its title only, 2 = leaving it.
; Take over the keys, the mouse buttons and the view's colours.
menu_begin:
        move.b d0,menu_kind(a4)
        clr.b native_used(a4)
        clr.b key_head(a4)
        clr.b key_tail(a4)
        clr.b shift(a4)
        ifd WHDLOAD
        st native_drive(a4)             ; no floppy drives
        else
        move.b 2(a5),d0                 ; CIA bit of the game's disk 2 drive
        subq.b #3,d0
        move.b d0,native_drive(a4)
        endif
        btst #6,$bfe001
        seq last_left(a4)
        btst #2,$16(a6)
        seq last_right(a4)
        lea (VIEW_PALETTE).l,a0
        lea palette_save(a4),a1
        lea menu_colours(pc),a2
        moveq #4,d0
.palette:
        move.w (a0),(a1)+
        move.w (a2)+,(a0)
        addq.l #4,a0
        dbra d0,.palette
        rts

; Close the menu, restore the level colours and let the editor redraw.
menu_close:
        movem.l d0/a0-a1,-(sp)
        lea (VIEW_PALETTE).l,a0
        lea palette_save(a4),a1
        moveq #4,d0
.palette:
        move.w (a1)+,(a0)
        addq.l #4,a0
        dbra d0,.palette
        clr.b menu_mode(a4)
        st disk_redraw(a4)
        btst #6,$bfe001
        seq last_left(a4)
        btst #2,$16(a6)
        seq last_right(a4)
        movem.l (sp)+,d0/a0-a1
        rts

; Leave the menu. If a disk was taken from the drive that holds disk 2, ask
; for disk 2 first; the game needs it for the next level.
menu_leave:
        tst.b native_used(a4)
        beq.s menu_close
        bra menu_prompt_disk2

; ---------------------------------------------------------------------------
; Frame handler: consume queued keys and mouse clicks, then act.

menu_frame:
        movem.l d0-d7/a0-a3,-(sp)
.keys:  bsr menu_next_key
        tst.w d0
        bmi.s .mouse
        bsr menu_key
        tst.b menu_mode(a4)
        beq.s .done
        bra.s .keys
.mouse: btst #2,$16(a6)
        seq d0
        cmp.b last_right(a4),d0
        beq.s .left
        move.b d0,last_right(a4)
        tst.b d0
        beq.s .left
        moveq #KEY_ESC,d0               ; right button: back / cancel
        bsr menu_key
        tst.b menu_mode(a4)
        beq.s .done
.left:  btst #6,$bfe001
        seq d0
        cmp.b last_left(a4),d0
        beq.s .done
        move.b d0,last_left(a4)
        tst.b d0
        beq.s .done
        cmp.b #M_TITLE,menu_mode(a4)    ; a click continues a message or prompt
        beq.s .done
        cmp.b #M_LEAVE,menu_mode(a4)    ; but never discards the level
        beq.s .done
        moveq #KEY_RETURN,d0
        bsr menu_key
.done:  movem.l (sp)+,d0-d7/a0-a3
        rts

; Return the next queued raw key code in D0, or -1.
menu_next_key:
        move.l a0,-(sp)
        moveq #-1,d0
        move.w sr,-(sp)
        ori.w #$0700,sr
        moveq #0,d1
        move.b key_tail(a4),d1
        cmp.b key_head(a4),d1
        beq.s .empty
        lea key_queue(a4),a0
        moveq #0,d0
        move.b (a0,d1.w),d0
        addq.b #1,d1
        and.b #15,d1
        move.b d1,key_tail(a4)
.empty: move.w (sp)+,sr
        movea.l (sp)+,a0
        rts

; Called by the keyboard interrupt while the menu or the list is open.
; D0: raw code.
menu_queue_key:
        cmp.b #$60,d0
        beq.s .shift
        cmp.b #$61,d0
        beq.s .shift
        cmp.b #$e0,d0
        beq.s .unshift
        cmp.b #$e1,d0
        beq.s .unshift
        tst.b d0
        bmi.s .done
        movem.l d1/a0,-(sp)
        lea key_queue(a4),a0
        moveq #0,d1
        move.b key_head(a4),d1
        move.b d0,(a0,d1.w)
        addq.b #1,d1
        and.b #15,d1
        cmp.b key_tail(a4),d1
        beq.s .full                     ; queue full: drop the key
        move.b d1,key_head(a4)
.full:  movem.l (sp)+,d1/a0
.done:  rts
.shift: st shift(a4)
        rts
.unshift:
        clr.b shift(a4)
        rts

; D0: raw key.
menu_key:
        move.b menu_mode(a4),d1
        cmp.b #M_TITLE,d1
        beq level_title_key
        cmp.b #M_PROMPT_LEVEL,d1
        beq level_prompt_key
        cmp.b #M_MESSAGE,d1
        beq.s .message
        cmp.b #M_LEAVE,d1
        beq.s .leave
        ifnd WHDLOAD
        cmp.b #M_PROMPT_DISK2,d1
        bne.s .done
        bsr.s menu_is_return
        beq menu_disk2_done
        endif
.done:  rts
.message:
        bsr.s menu_is_return
        beq menu_leave
        rts
.leave: cmp.b #KEY_ESC,d0
        beq menu_close
        bsr.s menu_is_return
        bne.s .done
        bsr menu_close
        st leave_now(a4)                ; the frame hook leaves the level
        rts

; Z set when D0 is Return or keypad Enter.
menu_is_return:
        cmp.b #KEY_RETURN,d0
        beq.s .yes
        cmp.b #KEY_ENTER,d0
.yes:   rts

; ---------------------------------------------------------------------------
; Messages and prompts

; A0: message text. Return closes the menu (asking for disk 2 if needed).
menu_message:
        move.l a0,menu_msg(a4)
        move.b #M_MESSAGE,menu_mode(a4)
        bra menu_draw_message

; From the frame hook: the level has unsaved changes; ask before leaving it.
menu_ask_leave:
        movem.l d0-d7/a0-a3,-(sp)
        moveq #2,d0
        bsr menu_begin
        lea txt_unsaved(pc),a0
        move.l a0,menu_msg(a4)
        move.b #M_LEAVE,menu_mode(a4)
        bsr menu_draw_message
        movem.l (sp)+,d0-d7/a0-a3
        rts

menu_prompt_disk2:
        lea txt_insert_disk2(pc),a0
        move.l a0,menu_msg(a4)
        move.b #M_PROMPT_DISK2,menu_mode(a4)
        bra menu_draw_message

        ifnd WHDLOAD
; Check that disk 2 is back in its drive: its directory starts with Ground1.
menu_disk2_done:
        bsr menu_show_working
        moveq #0,d0
        move.b native_drive(a4),d0
        moveq #0,d1
        bsr disk_read_track
        tst.l d0
        bne.s .again
        lea install(pc),a0
        adda.l #DISK_TRACK+$410,a0
        cmpi.l #'Grou',(a0)
        bne.s .again
        cmpi.l #'nd1'<<8,4(a0)
        bne.s .again
        clr.b native_used(a4)
        bra menu_close
.again: bra menu_prompt_disk2

; D0: drive 0..3. Return D0 = 0 (Z set) when a drive is connected. DF0 is
; always present; DF1..DF3 report a 32-bit drive identification serially on
; /DSKRDY after the motor has been switched off.
drive_present:
        movem.l d1-d3,-(sp)
        tst.w d0
        beq.s .yes
        addq.w #3,d0                    ; CIA-B select bit
        move.b #$ff,$bfd100
        bclr #7,$bfd100                 ; motor on ...
        bclr d0,$bfd100
        bset d0,$bfd100
        bset #7,$bfd100                 ; ... and off, which resets the ID
        bclr d0,$bfd100
        bset d0,$bfd100
        moveq #0,d2
        moveq #31,d1
.bit:   bclr d0,$bfd100
        btst #5,$bfe001
        seq d3
        bset d0,$bfd100
        add.l d2,d2
        tst.b d3
        beq.s .next
        addq.l #1,d2
.next:  dbra d1,.bit
        tst.l d2
        beq.s .no
.yes:   moveq #0,d0
        bra.s .done
.no:    moveq #-1,d0
.done:  movem.l (sp)+,d1-d3
        rts
        endif

; D0: transport error. Return A0 = message text.
menu_error_text:
        neg.l d0
        subq.l #1,d0
        cmp.l #10,d0
        blo.s .known
        moveq #0,d0
.known: add.w d0,d0
        lea error_texts(pc),a0
        move.w (a0,d0.w),d0
        lea (a0,d0.w),a0
        rts

; ---------------------------------------------------------------------------
; Drawing. The menu uses the whole 320x160 level view as 20 rows of 40 cells.

; Clear all four planes of the displayed viewport.
menu_clear:
        movem.l d0/a0,-(sp)
        move.l $d0(a5),a0
        subq.l #2,a0
        move.w #4*$2100/4-1,d0
.clear: clr.l (a0)+
        dbra d0,.clear
        movem.l (sp)+,d0/a0
        rts

; D1: row, D2: column, A0: text (NUL ends it, $0A starts the next row at the
; same column), D3: foreground colour, D4: background colour.
menu_text:
        movem.l d0-d7/a0-a3,-(sp)
        move.w d2,d7
.char:  moveq #0,d0
        move.b (a0)+,d0
        beq.s .done
        cmp.b #$0a,d0
        bne.s .draw
        addq.w #1,d1
        move.w d7,d2
        bra.s .char
.draw:  cmp.w #40,d2
        bhs.s .char
        bsr.s menu_cell
        addq.w #1,d2
        bra.s .char
.done:  movem.l (sp)+,d0-d7/a0-a3
        rts

; D0: character, D1: row, D2: column, D3: foreground, D4: background.
menu_cell:
        movem.l d0-d6/a0-a2,-(sp)
        cmp.w #32,d0
        bls.s .blank
        cmp.w #126,d0
        bls.s .known
.blank: moveq #32,d0
.known: sub.w #32,d0
        lsl.w #3,d0
        lea font(pc),a2
        adda.w d0,a2
        move.l $d0(a5),a1
        subq.l #2,a1
        mulu #8*44,d1
        adda.l d1,a1
        addq.w #2,d2                    ; visible bytes start at byte 2
        adda.w d2,a1
        moveq #0,d6                     ; plane
.plane: movea.l a2,a0
        movea.l a1,a3
        moveq #7,d5
.line:  move.b (a0)+,d0
        moveq #0,d2
        btst d6,d3
        beq.s .no_fg
        move.b d0,d2
.no_fg: btst d6,d4
        beq.s .no_bg
        not.b d0
        or.b d0,d2
.no_bg: move.b d2,(a3)
        lea 44(a3),a3
        dbra d5,.line
        adda.l #$2100,a1
        addq.w #1,d6
        cmp.w #4,d6
        blo.s .plane
        movem.l (sp)+,d0-d6/a0-a2
        rts

; D1: row, D4: colour. Fill a whole row.
menu_fill_row:
        movem.l d0/d2/d3,-(sp)
        moveq #' ',d0
        moveq #0,d3
        moveq #39,d2
.cell:  bsr.s menu_cell
        dbra d2,.cell
        movem.l (sp)+,d0/d2/d3
        rts

; Title bar with the menu's name and the level title.
menu_draw_frame:
        movem.l d0-d4/a0-a1,-(sp)
        moveq #0,d1
        moveq #PANEL_BAR,d4
        bsr.s menu_fill_row
        lea txt_save_title(pc),a0
        tst.b menu_kind(a4)
        beq.s .title
        lea txt_title_title(pc),a0
        cmp.b #1,menu_kind(a4)
        beq.s .title
        lea txt_leave_title(pc),a0
.title: moveq #1,d2
        moveq #PANEL_FG,d3
        bsr menu_text
        lea $cd86,a0                    ; level title, 32 characters
        lea menu_line(a4),a1
        moveq #31,d0
.name:  move.b (a0)+,(a1)+
        dbra d0,.name
        clr.b (a1)
        lea menu_line(a4),a0
        moveq #7,d2
        bsr menu_text
        movem.l (sp)+,d0-d4/a0-a1
        rts

; Message or prompt in menu_msg, with the key help.
menu_draw_message:
        movem.l d0-d4/a0,-(sp)
        bsr menu_clear
        bsr menu_draw_frame
        moveq #7,d1
        moveq #2,d2
        moveq #PANEL_FG,d3
        moveq #0,d4
        movea.l menu_msg(a4),a0
        bsr menu_text
        cmp.b #M_PROMPT_DISK2,menu_mode(a4)
        bne.s .help
        ; The disk 2 prompt names the drive.
        moveq #0,d1
        move.b native_drive(a4),d1
        lea menu_line(a4),a0
        move.b #'D',(a0)
        move.b #'F',1(a0)
        add.b #'0',d1
        move.b d1,2(a0)
        move.b #':',3(a0)
        clr.b 4(a0)
        moveq #13,d1
        bsr menu_text
.help:  moveq #19,d1
        moveq #0,d2
        moveq #PANEL_HELP,d3
        lea txt_help_continue(pc),a0
        cmp.b #M_PROMPT_LEVEL,menu_mode(a4)
        bne.s .leave
        lea txt_help_prompt(pc),a0
.leave: cmp.b #M_LEAVE,menu_mode(a4)
        bne.s .draw
        lea txt_help_leave(pc),a0
.draw:  bsr menu_text
        movem.l (sp)+,d0-d4/a0
        rts

; Shown before every disk operation; the drive may take a few seconds.
menu_show_working:
        movem.l d0-d4/a0,-(sp)
        bsr menu_clear
        bsr menu_draw_frame
        moveq #7,d1
        moveq #2,d2
        moveq #PANEL_FG,d3
        moveq #0,d4
        lea txt_working(pc),a0
        bsr menu_text
        moveq #19,d1
        moveq #0,d2
        moveq #PANEL_HELP,d3
        lea txt_help_working(pc),a0
        bsr menu_text
        movem.l (sp)+,d0-d4/a0
        rts

; ---------------------------------------------------------------------------
; Colours for the menu: background, text, selection bar, (unused), help.
menu_colours:
        dc.w $0112,$0fff,$036b,$0fff,$0fc4

error_texts:
        dc.w txt_e_refused-error_texts
        dc.w txt_e_cancelled-error_texts
        dc.w txt_e_no_disk-error_texts
        dc.w txt_e_read-error_texts
        dc.w txt_e_wrong-error_texts
        dc.w txt_e_protected-error_texts
        dc.w txt_e_changed-error_texts
        dc.w txt_e_damaged-error_texts
        dc.w txt_e_index-error_texts
        dc.w txt_e_index_write-error_texts

txt_save_title:         dc.b 'SAVE',0
txt_title_title:        dc.b 'TITLE',0
txt_leave_title:        dc.b 'LEAVE',0
txt_unsaved:            dc.b 'This level has unsaved changes.',$0a
                        dc.b 'Leaving the editor discards them.',0
txt_working:            dc.b 'Working with the disk...',0
txt_insert_disk2:       dc.b 'Insert LEMMINGS DISK 2 into',$0a
                        dc.b 'the drive below and press Return.',0
txt_e_refused:          dc.b 'The operation was refused.',0
txt_e_cancelled:        dc.b 'Cancelled.',0
txt_e_no_disk:          dc.b 'There is no disk in the drive.',0
txt_e_read:             dc.b 'The disk cannot be read.',0
txt_e_wrong:            dc.b 'This is not a level disk.',0
txt_e_protected:        dc.b 'The disk is write-protected.',0
txt_e_changed:          dc.b 'The disk has changed. Try again.',0
txt_e_damaged:          dc.b 'Writing failed. This level and the',$0a
                        dc.b 'one next to it may be damaged.',0
txt_e_index:            dc.b 'The index of the level disk is',$0a
                        dc.b 'damaged. Repair it with savedisk.py',$0a
                        dc.b 'rebuild-index.',0
txt_e_index_write:      dc.b 'Saved, but the index was not',$0a
                        dc.b 'updated. Repair it with savedisk.py',$0a
                        dc.b 'rebuild-index.',0
txt_help_continue:      dc.b 'Return: continue',0
txt_help_prompt:        dc.b 'Return: continue   Esc: cancel',0
txt_help_working:       dc.b 'Esc: cancel',0
txt_help_leave:         dc.b 'Return: leave without saving   Esc: back',0
        even
