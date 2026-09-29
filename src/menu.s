; Lemmings In-Game Level Editor V1.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Save/load menu. S or L in the editor opens it for the current level. The
; menu covers the paused level view: it is drawn with the editor's font into
; the displayed viewport buffer while disk transfers borrow the other buffer,
; and copper colours 0..4 of the level view are replaced while it is open.
; It runs from the frame hook; the game loop is idle until the menu closes.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

M_LIST          equ 1
M_NAME          equ 2
M_CONFIRM       equ 3
M_MESSAGE       equ 4
M_PROMPT_SAVE   equ 5
M_PROMPT_DISK2  equ 6

A_OVERWRITE     equ 1
A_DELETE        equ 2
A_LOAD          equ 3
A_INIT          equ 4
A_REBUILD       equ 5

AF_LIST         equ 1
AF_PROMPT_SAVE  equ 2
AF_CLOSE        equ 3
AF_LOAD         equ 4

ROWS_PER_PAGE   equ 16
LIST_ROW        equ 2
VIEW_PALETTE    equ $850e               ; copper value word of COLOR00
PANEL_FG        equ 1
PANEL_BAR       equ 2
PANEL_HELP      equ 4

KEY_RETURN      equ $44
KEY_ENTER       equ $43
KEY_ESC         equ $45
KEY_BACKSPACE   equ $41
KEY_DEL         equ $46
KEY_UP          equ $4c
KEY_DOWN        equ $4d
KEY_RIGHT       equ $4e
KEY_LEFT        equ $4f
KEY_Y           equ $15
KEY_N           equ $36
KEY_R           equ $13

; ---------------------------------------------------------------------------
; Opening and closing

; D0: 1 = save menu, 2 = load menu.
menu_open:
        movem.l d0-d7/a0-a3,-(sp)
        subq.b #1,d0
        move.b d0,menu_kind(a4)
        clr.w menu_sel(a4)
        clr.b native_used(a4)
        clr.b key_head(a4)
        clr.b key_tail(a4)
        clr.b shift(a4)
        move.b 2(a5),d0                 ; CIA bit of the game's disk 2 drive
        subq.b #3,d0
        move.b d0,native_drive(a4)
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
        clr.b list_ok(a4)
        move.b #M_MESSAGE,menu_mode(a4)
        bsr menu_clear
        bsr menu_draw_frame
        lea txt_searching(pc),a0
        bsr menu_show_message_only
        bsr menu_find_disk
        movem.l (sp)+,d0-d7/a0-a3
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
        move.b #AF_CLOSE,menu_after(a4)
        bra menu_prompt_disk2

; ---------------------------------------------------------------------------
; Finding the save disk

; Try the drive used last time, then every other connected drive except the
; one holding disk 2. Otherwise ask for the save disk.
menu_find_disk:
        moveq #0,d0
        move.b save_drive(a4),d0
        beq.s .others
        subq.b #1,d0
        cmp.b native_drive(a4),d0
        beq.s .others
        bsr menu_try_drive
        tst.l d0
        beq .done
.others:
        moveq #0,d7
.drive: cmp.b native_drive(a4),d7
        beq.s .next
        move.l d7,d0
        bsr drive_present
        bne.s .next
        move.l d7,d0
        bsr menu_try_drive
        tst.l d0
        beq.s .done
        cmp.l #DISK_CANCELLED,d0
        beq menu_leave
.next:  addq.w #1,d7
        cmp.w #4,d7
        blo.s .drive
        ; No save disk found: ask for it in the first free drive, or in the
        ; drive that holds disk 2 when there is no other drive.
        move.b native_drive(a4),menu_prompt(a4)
        moveq #0,d7
.spare: cmp.b native_drive(a4),d7
        beq.s .skip
        move.l d7,d0
        bsr drive_present
        bne.s .skip
        move.b d7,menu_prompt(a4)
        bra.s .prompt
.skip:  addq.w #1,d7
        cmp.w #4,d7
        blo.s .spare
.prompt:
        bsr menu_prompt_save
.done:  rts

; D0: drive. Read the save disk index and the current level's saves.
; Return 0 when the list is ready (or the index needs rebuilding and the menu
; has asked for it), otherwise the transport error.
menu_try_drive:
        move.b d0,menu_drive(a4)
        cmp.b native_drive(a4),d0
        bne.s .scan
        st native_used(a4)
.scan:  bsr menu_show_working
        moveq #0,d0
        move.b menu_drive(a4),d0
        bsr disk_scan_level
        tst.l d0
        beq.s .found
        cmp.l #DISK_INDEX,d0
        bne.s .done
        bsr.s .remember
        move.b #A_REBUILD,menu_action(a4)
        lea txt_index_bad(pc),a0
        bsr menu_confirm
        moveq #0,d0
        rts
.found: bsr.s .remember
        st list_ok(a4)
        bsr menu_list
        moveq #0,d0
.done:  rts
.remember:
        moveq #0,d1
        move.b menu_drive(a4),d1
        addq.b #1,d1
        move.b d1,save_drive(a4)
        rts

; The user has inserted a disk into the prompt drive and pressed Return.
menu_prompt_done:
        moveq #0,d0
        move.b menu_prompt(a4),d0
        bsr menu_try_drive
        tst.l d0
        beq .done
        cmp.l #DISK_CANCELLED,d0
        beq menu_prompt_save
        cmp.l #DISK_WRONG,d0
        bne.s .unreadable
        ; A readable disk that is not a save disk. Never offer to erase a
        ; Lemmings game disk; its directory starts with "Reserved".
        lea install(pc),a0
        adda.l #DISK_HEADER+$400,a0
        cmpi.l #'Rese',(a0)
        bne.s .offer
        cmpi.l #'rved',4(a0)
        bne.s .offer
        lea txt_game_disk(pc),a0
        move.b #AF_PROMPT_SAVE,menu_after(a4)
        bra menu_message
.unreadable:
        cmp.l #DISK_READ_ERROR,d0
        beq.s .offer
        bsr menu_error_text
        move.b #AF_PROMPT_SAVE,menu_after(a4)
        bra menu_message
.offer: move.b #A_INIT,menu_action(a4)
        lea txt_init(pc),a0
        bra menu_confirm
.done:  rts

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
        bsr menu_click
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

; Called by the keyboard interrupt while the menu is open. D0: raw code.
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
        cmp.b #M_LIST,d1
        beq menu_list_key
        cmp.b #M_NAME,d1
        beq menu_name_key
        cmp.b #M_CONFIRM,d1
        beq menu_confirm_key
        cmp.b #M_MESSAGE,d1
        beq menu_message_key
        cmp.b #M_PROMPT_SAVE,d1
        beq.s .prompt_save
        cmp.b #M_PROMPT_DISK2,d1
        beq.s .prompt_disk2
        rts
.prompt_save:
        cmp.b #KEY_ESC,d0
        beq menu_leave
        bsr menu_is_return
        beq menu_prompt_done
        rts
.prompt_disk2:
        bsr menu_is_return
        beq menu_disk2_done
        rts

; Z set when D0 is Return or keypad Enter.
menu_is_return:
        cmp.b #KEY_RETURN,d0
        beq.s .yes
        cmp.b #KEY_ENTER,d0
.yes:   rts

; ---------------------------------------------------------------------------
; The list of saves for the current level

; Build the rows from the scan and show the list.
menu_list:
        clr.b menu_new(a4)
        move.w disk_rows(a4),d0
        tst.b menu_kind(a4)
        bne.s .count
        cmp.w #32,d0
        bhs.s .count
        tst.w disk_free(a4)
        beq.s .count
        st menu_new(a4)
        addq.w #1,d0
.count: move.w d0,menu_rows(a4)
        move.w menu_sel(a4),d1
        cmp.w d0,d1
        blo.s .shown
        clr.w menu_sel(a4)
.shown: move.b #M_LIST,menu_mode(a4)
        bra menu_draw_list

; D0: raw key in the list.
menu_list_key:
        cmp.b #KEY_ESC,d0
        beq menu_leave
        move.w menu_sel(a4),d1
        move.w menu_rows(a4),d2
        cmp.b #KEY_UP,d0
        bne.s .down
        subq.w #1,d1
        bpl.s .select
        move.w d2,d1
        subq.w #1,d1
        bra.s .select
.down:  cmp.b #KEY_DOWN,d0
        bne.s .page_up
        addq.w #1,d1
        cmp.w d2,d1
        blo.s .select
        moveq #0,d1
        bra.s .select
.page_up:
        cmp.b #KEY_LEFT,d0
        bne.s .page_down
        sub.w #ROWS_PER_PAGE,d1
        bpl.s .select
        moveq #0,d1
        bra.s .select
.page_down:
        cmp.b #KEY_RIGHT,d0
        bne.s .other
        add.w #ROWS_PER_PAGE,d1
        cmp.w d2,d1
        blo.s .select
        move.w d2,d1
        subq.w #1,d1
.select:
        tst.w d2
        beq.s .done
        move.w d1,menu_sel(a4)
        bra menu_draw_list
.other: cmp.b #KEY_R,d0
        bne.s .delete
        move.b #A_REBUILD,menu_action(a4)
        lea txt_rebuild(pc),a0
        bra menu_confirm
.delete:
        tst.w d2
        beq.s .done
        cmp.b #KEY_DEL,d0
        bne.s .confirm
        bsr menu_selected_row
        move.l a0,d0
        beq.s .done                     ; the "new save" row
        move.b #A_DELETE,menu_action(a4)
        lea txt_delete(pc),a0
        bra menu_confirm
.confirm:
        bsr menu_is_return
        beq.s menu_list_choose
.done:  rts

; Return (or a second click) on the selected row.
menu_list_choose:
        tst.w menu_rows(a4)
        beq.s .done
        bsr menu_selected_row
        tst.b menu_kind(a4)
        bne.s .load
        move.l a0,d0
        beq.s .new
        move.b #A_OVERWRITE,menu_action(a4)
        lea txt_overwrite(pc),a0
        bra menu_confirm
.new:   move.w #-1,menu_slot(a4)
        clr.b name_len(a4)
        lea name(a4),a0
        moveq #16,d0
.clear: clr.b (a0)+
        dbra d0,.clear
        bra menu_name_start
.load:  move.b #A_LOAD,menu_action(a4)
        lea txt_load(pc),a0
        bra menu_confirm
.done:  rts

; A0: DISK_ROWS record of the selected row, or 0 (Z set) for "new save".
menu_selected_row:
        move.w menu_sel(a4),d0
        tst.b menu_new(a4)
        beq.s .row
        subq.w #1,d0
        bpl.s .row
        suba.l a0,a0
        rts
.row:   mulu #20,d0
        lea install(pc),a0
        adda.l #DISK_ROWS,a0
        adda.l d0,a0
        rts

; A left click: on the selected row it acts like Return, on another row it
; selects it; on "<" or ">" it changes the page.
menu_click:
        move.w $9dac,d1
        lsr.w #3,d1                     ; text row
        move.w $9daa,d2
        lsr.w #3,d2                     ; text column
        move.b menu_mode(a4),d0
        cmp.b #M_LIST,d0
        beq.s .list
        cmp.b #M_MESSAGE,d0
        beq.s .return
        cmp.b #M_PROMPT_SAVE,d0
        beq.s .return
        cmp.b #M_PROMPT_DISK2,d0
        beq.s .return
        rts
.return:
        moveq #KEY_RETURN,d0
        bra menu_key
.list:  cmp.w #18,d1
        bne.s .row
        cmp.w #2,d2
        bls.s .previous
        cmp.w #12,d2
        bhs.s .done
        moveq #KEY_RIGHT,d0
        bra menu_key
.previous:
        moveq #KEY_LEFT,d0
        bra menu_key
.row:   sub.w #LIST_ROW,d1
        bmi.s .done
        cmp.w #ROWS_PER_PAGE,d1
        bhs.s .done
        move.w menu_sel(a4),d0
        and.w #-ROWS_PER_PAGE,d0        ; first row of the page
        add.w d0,d1
        cmp.w menu_rows(a4),d1
        bhs.s .done
        cmp.w menu_sel(a4),d1
        beq menu_list_choose
        move.w d1,menu_sel(a4)
        bra menu_draw_list
.done:  rts

; ---------------------------------------------------------------------------
; Name entry

menu_name_start:
        move.b #M_NAME,menu_mode(a4)
        bra menu_draw_name

menu_name_key:
        cmp.b #KEY_ESC,d0
        beq menu_list
        bsr menu_is_return
        beq.s .accept
        moveq #0,d1
        move.b name_len(a4),d1
        cmp.b #KEY_BACKSPACE,d0
        bne.s .char
        tst.w d1
        beq.s .done
        subq.w #1,d1
        lea name(a4),a0
        clr.b (a0,d1.w)
        move.b d1,name_len(a4)
        bra menu_draw_name
.char:  cmp.w #16,d1
        bhs.s .done
        cmp.b #$40,d0
        bhi.s .done                     ; character keys and space only
        lea $a526,a0                    ; the game's raw-key to ASCII tables
        tst.b shift(a4)
        beq.s .table
        lea $a586,a0
.table: move.b (a0,d0.w),d0
        cmp.b #32,d0
        blo.s .done
        cmp.b #126,d0
        bhi.s .done
        lea name(a4),a0
        move.b d0,(a0,d1.w)
        addq.b #1,d1
        move.b d1,name_len(a4)
        bra menu_draw_name
.accept:
        ; The name must contain at least one non-space character.
        lea name(a4),a0
        moveq #0,d1
        move.b name_len(a4),d1
        subq.w #1,d1
        bmi.s .done
.visible:
        cmpi.b #' ',(a0)+
        bne menu_do_save
        dbra d1,.visible
.done:  rts

; ---------------------------------------------------------------------------
; Confirmations and messages

; A0: question text. The action is in menu_action.
menu_confirm:
        move.l a0,menu_msg(a4)
        move.b #M_CONFIRM,menu_mode(a4)
        bra menu_draw_message

menu_confirm_key:
        cmp.b #KEY_Y,d0
        beq.s .yes
        cmp.b #KEY_N,d0
        beq.s .no
        cmp.b #KEY_ESC,d0
        beq.s .no
        rts
.no:    cmp.b #A_INIT,menu_action(a4)
        beq menu_prompt_save
        tst.b list_ok(a4)
        bne menu_list
        bra menu_leave
.yes:   move.b menu_action(a4),d0
        cmp.b #A_OVERWRITE,d0
        beq.s .overwrite
        cmp.b #A_DELETE,d0
        beq menu_do_delete
        cmp.b #A_LOAD,d0
        beq menu_do_load
        cmp.b #A_INIT,d0
        beq menu_do_init
        cmp.b #A_REBUILD,d0
        beq menu_do_rebuild
        rts
.overwrite:
        bsr menu_selected_row
        move.w (a0),menu_slot(a4)
        ; Start from the existing name.
        lea 4(a0),a0
        lea name(a4),a1
        moveq #0,d1
.copy:  move.b (a0)+,d0
        beq.s .copied
        move.b d0,(a1)+
        addq.w #1,d1
        cmp.w #16,d1
        blo.s .copy
.copied:
        move.b d1,name_len(a4)
.clear: cmp.w #16,d1
        bhs menu_name_start
        clr.b (a1)+
        addq.w #1,d1
        bra.s .clear

; A0: message text; menu_after says what follows.
menu_message:
        move.l a0,menu_msg(a4)
        move.b #M_MESSAGE,menu_mode(a4)
        bra menu_draw_message

menu_message_key:
        move.b menu_after(a4),d1
        cmp.b #AF_PROMPT_SAVE,d1
        beq menu_prompt_save
        cmp.b #AF_CLOSE,d1
        beq menu_leave
        cmp.b #AF_LIST,d1
        beq menu_list
        rts

menu_prompt_save:
        lea txt_insert_save(pc),a0
        move.l a0,menu_msg(a4)
        move.b #M_PROMPT_SAVE,menu_mode(a4)
        bra menu_draw_message

; menu_after: AF_CLOSE or AF_LOAD.
menu_prompt_disk2:
        lea txt_insert_disk2(pc),a0
        move.l a0,menu_msg(a4)
        move.b #M_PROMPT_DISK2,menu_mode(a4)
        bra menu_draw_message

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
        cmp.b #AF_LOAD,menu_after(a4)
        beq menu_load_go
        bra menu_close
.again: bra menu_prompt_disk2

; ---------------------------------------------------------------------------
; Disk actions

menu_do_save:
        lea name(a4),a0
        bsr create_record
        tst.l d0
        bne.s .refused
        move.w menu_slot(a4),d1
        bpl.s .write
        bsr choose_slot
        move.w d0,d1
        bmi.s .full
.write: move.w d1,menu_slot(a4)
        lea txt_saved(pc),a2
        bra menu_write_slot
.refused:
        lea txt_cannot_save(pc),a0
        bra.s .message
.full:  lea txt_disk_full(pc),a0
.message:
        move.b #AF_LIST,menu_after(a4)
        bra menu_message

menu_do_delete:
        bsr menu_selected_row
        move.w (a0),menu_slot(a4)
        lea save_record(pc),a0
        move.w #511,d0
.clear: clr.l (a0)+
        dbra d0,.clear
        lea txt_deleted(pc),a2
        ; Fall through.

; Write save_record (or an empty slot) to menu_slot. A2: success message.
; Take a fresh snapshot of the target track first, as the transport requires.
menu_write_slot:
        bsr menu_show_working
        moveq #0,d0
        move.b menu_drive(a4),d0
        moveq #0,d1
        move.w menu_slot(a4),d1
        lsr.w #1,d1
        addq.w #1,d1
        bsr disk_read_track
        tst.l d0
        bne.s menu_result
        moveq #0,d0
        move.b menu_drive(a4),d0
        moveq #0,d1
        move.w menu_slot(a4),d1
        bsr disk_replace_slot
; D0: transport result, A2: success message. Show it after a fresh scan.
menu_result:
        tst.l d0
        bne.s .error
        movea.l a2,a0
        bra.s .rescan
.error: bsr menu_error_text
.rescan:
        move.l a0,-(sp)
        bsr menu_show_working
        moveq #0,d0
        move.b menu_drive(a4),d0
        bsr disk_scan_level
        movea.l (sp)+,a0
        move.b #AF_LIST,menu_after(a4)
        tst.l d0
        bne.s .failed
        st list_ok(a4)
        bra menu_message
.failed:
        bsr menu_error_text
        move.b #AF_CLOSE,menu_after(a4)
        bra menu_message

menu_do_load:
        bsr menu_selected_row
        move.w (a0),d1
        move.w d1,menu_slot(a4)
        bsr menu_show_working
        lsr.w #1,d1
        addq.w #1,d1
        moveq #0,d0
        move.b menu_drive(a4),d0
        bsr disk_read_track
        tst.l d0
        bne.s .error
        ; Keep a copy: reading disk 2 back overwrites DISK_TRACK.
        lea install(pc),a0
        adda.l #DISK_TRACK,a0
        btst #0,menu_slot+1(a4)
        beq.s .copy
        adda.w #2048,a0
.copy:  lea save_record(pc),a1
        move.w #511,d0
.words: move.l (a0)+,(a1)+
        dbra d0,.words
        tst.b native_used(a4)
        beq.s menu_load_go
        move.b #AF_LOAD,menu_after(a4)
        bra menu_prompt_disk2
.error: bsr menu_error_text
        move.b #AF_LIST,menu_after(a4)
        bra menu_message

; Disk 2 is available: queue the load and close. The next frame restarts the
; level through the game's own start path and replays the saved edits.
menu_load_go:
        lea save_record(pc),a0
        bsr queue_load
        tst.l d0
        bne.s .refused
        bra menu_close
.refused:
        lea txt_wrong_level(pc),a0
        move.b #AF_CLOSE,menu_after(a4)
        bra menu_message

menu_do_rebuild:
        bsr menu_show_working
        moveq #0,d0
        move.b menu_drive(a4),d0
        bsr disk_rebuild_index
        lea txt_rebuilt(pc),a2
        bra menu_result

menu_do_init:
        bsr menu_show_working
        moveq #0,d0
        move.b menu_drive(a4),d0
        bsr disk_initialize
        lea txt_initialized(pc),a2
        tst.l d0
        bne menu_result
        moveq #0,d1
        move.b menu_drive(a4),d1
        addq.b #1,d1
        move.b d1,save_drive(a4)
        bra menu_result

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

; Paired allocation: the free partner of a slot holding this level, then a
; slot on an entirely free track, then any free slot. Return D0 or -1.
choose_slot:
        movem.l d1-d3/a0,-(sp)
        lea install(pc),a0
        adda.l #DISK_HEADER+64,a0
        move.b level_id+1(a4),d3
        moveq #0,d2                     ; pass
.pass:  moveq #0,d0
.slot:  move.w d0,d1
        mulu #3,d1
        cmpi.b #$ff,(a0,d1.w)
        bne.s .next
        move.w d0,d1
        eori.w #1,d1
        mulu #3,d1
        move.b (a0,d1.w),d1
        tst.w d2
        bne.s .second
        cmp.b d3,d1
        beq.s .done
        bra.s .next
.second:
        cmp.w #1,d2
        bne.s .done
        cmp.b #$ff,d1
        beq.s .done
.next:  addq.w #1,d0
        cmp.w #318,d0
        blo.s .slot
        addq.w #1,d2
        cmp.w #3,d2
        blo.s .pass
        moveq #-1,d0
.done:  movem.l (sp)+,d1-d3/a0
        rts

; D0: drive. Write an empty save disk: every data track, then track zero with
; the header and an empty index, so an interrupted run never leaves a valid
; header in front of unformatted tracks. Each track is verified after writing.
disk_initialize:
        movem.l d1-d7/a0-a6,-(sp)
        bsr disk_acquire
        tst.l d0
        bne .done
        bsr disk_select
        tst.l d0
        bne .release
        moveq #1,d7
.track: lea install(pc),a0
        adda.l #DISK_TRACK,a0
        movea.l a0,a1
        move.w #TRACK_BYTES/4-1,d1
.clear: clr.l (a1)+
        dbra d1,.clear
        cmp.w #160,d7
        bne.s .write
        moveq #0,d7                     ; finally track zero
        lea disk_header(pc),a1
        moveq #7,d1
.header:
        move.l (a1)+,(a0)+
        dbra d1,.header
        lea 64-32(a0),a1
        move.w #317,d1
.index: move.b #$ff,(a1)
        addq.l #3,a1
        dbra d1,.index
        lea -32(a0),a0
        bsr seal_disk_index
.write: move.l d7,d0
        bsr disk_progress
        bsr disk_seek_track
        tst.l d0
        bne.s .release
        lea install(pc),a0
        adda.l #DISK_TRACK,a0
        bsr disk_write_decoded
        tst.l d0
        bne.s .release
        clr.b disk_committing(a4)       ; allow Esc between tracks
        tst.b disk_cancel(a4)
        bne.s .cancel
        tst.w d7
        beq.s .release
        addq.w #1,d7
        bra.s .track
.cancel:
        moveq #DISK_CANCELLED,d0
.release:
        bsr disk_release
.done:  movem.l (sp)+,d1-d7/a0-a6
        rts

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

; Called by the disk routines before each track. D0: track. Shows the track
; number while the menu is open; the routines run inside a single frame.
disk_progress:
        tst.b menu_mode(a4)
        beq.s .done
        movem.l d0-d7/a0-a3,-(sp)
        lea txt_track(pc),a0
        lea menu_line(a4),a1
.copy:  move.b (a0)+,(a1)+
        bne.s .copy
        subq.l #1,a1
        bsr menu_format3
        clr.b (a1)
        moveq #12,d1
        moveq #14,d2
        moveq #PANEL_FG,d3
        moveq #0,d4
        lea menu_line(a4),a0
        bsr menu_text
        movem.l (sp)+,d0-d7/a0-a3
.done:  rts

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

; D0: 0..999 appended to A1 as three digits (leading zeros kept).
menu_format3:
        movem.l d0-d3,-(sp)
        and.l #$ffff,d0
        move.l d0,d2
        jsr $1862                       ; four ASCII digits in D0
        rol.l #8,d0                     ; drop the thousands digit
        moveq #2,d1
.digit: rol.l #8,d0
        move.b d0,(a1)+
        dbra d1,.digit
        movem.l (sp)+,d0-d3
        rts

; Title bar, drive and free-slot line, and footer.
menu_draw_frame:
        movem.l d0-d4/a0-a1,-(sp)
        moveq #0,d1
        moveq #PANEL_BAR,d4
        bsr.s menu_fill_row
        lea txt_save_title(pc),a0
        tst.b menu_kind(a4)
        beq.s .title
        lea txt_load_title(pc),a0
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

menu_draw_list:
        movem.l d0-d7/a0-a3,-(sp)
        bsr menu_clear
        bsr menu_draw_frame
        ; Drive and free slots.
        lea menu_line(a4),a1
        move.b #'D',(a1)+
        move.b #'F',(a1)+
        moveq #'0',d0
        add.b menu_drive(a4),d0
        move.b d0,(a1)+
        lea txt_free(pc),a0
.free:  move.b (a0)+,(a1)+
        bne.s .free
        subq.l #1,a1
        move.w disk_free(a4),d0
        bsr menu_format3
        lea txt_slots(pc),a0
.slots: move.b (a0)+,(a1)+
        bne.s .slots
        moveq #1,d1
        moveq #1,d2
        moveq #PANEL_HELP,d3
        moveq #0,d4
        lea menu_line(a4),a0
        bsr menu_text
        ; Rows of the current page.
        move.w menu_sel(a4),d7
        and.w #-ROWS_PER_PAGE,d7
        moveq #0,d6
.row:   move.w d7,d0
        add.w d6,d0
        cmp.w menu_rows(a4),d0
        bhs.s .rows_done
        moveq #LIST_ROW,d1
        add.w d6,d1
        moveq #0,d4
        cmp.w menu_sel(a4),d0
        bne.s .plain
        moveq #PANEL_BAR,d4
        bsr menu_fill_row
.plain: bsr menu_row_text
        moveq #1,d2
        moveq #PANEL_FG,d3
        lea menu_line(a4),a0
        bsr menu_text
        addq.w #1,d6
        cmp.w #ROWS_PER_PAGE,d6
        blo.s .row
.rows_done:
        tst.w menu_rows(a4)
        bne.s .footer
        moveq #8,d1
        moveq #7,d2
        moveq #PANEL_FG,d3
        moveq #0,d4
        lea txt_no_saves(pc),a0
        bsr menu_text
.footer:
        ; "< Page n/m >".
        lea menu_line(a4),a1
        lea txt_page(pc),a0
.page:  move.b (a0)+,(a1)+
        bne.s .page
        subq.l #1,a1
        move.w menu_sel(a4),d0
        lsr.w #4,d0
        addq.w #1,d0
        add.b #'0',d0
        move.b d0,(a1)+
        move.b #'/',(a1)+
        move.w menu_rows(a4),d0
        add.w #ROWS_PER_PAGE-1,d0
        lsr.w #4,d0
        bne.s .pages
        moveq #1,d0
.pages: add.b #'0',d0
        move.b d0,(a1)+
        move.b #' ',(a1)+
        move.b #'>',(a1)+
        clr.b (a1)
        moveq #18,d1
        moveq #0,d2
        moveq #PANEL_HELP,d3
        moveq #0,d4
        lea menu_line(a4),a0
        bsr menu_text
        moveq #19,d1
        lea txt_help_save(pc),a0
        tst.b menu_kind(a4)
        beq.s .help
        lea txt_help_load(pc),a0
.help:  bsr menu_text
        movem.l (sp)+,d0-d7/a0-a3
        rts

; D0: list index. Build " nn  name  nnn edits" in menu_line.
menu_row_text:
        movem.l d0-d2/a0-a1,-(sp)
        lea menu_line(a4),a1
        tst.b menu_new(a4)
        beq.s .save
        tst.w d0
        bne.s .older
        lea txt_new_save(pc),a0
.new:   move.b (a0)+,(a1)+
        bne.s .new
        bra.s .done
.older: subq.w #1,d0
.save:  move.w d0,d2
        addq.w #1,d0
        bsr menu_format3
        move.b -2(a1),-3(a1)            ; keep two digits
        move.b -1(a1),-2(a1)
        subq.l #1,a1
        move.b #' ',(a1)+
        move.b #' ',(a1)+
        mulu #20,d2
        lea install(pc),a0
        adda.l #DISK_ROWS,a0
        adda.l d2,a0
        move.w 2(a0),d2                 ; edit count
        lea 4(a0),a0
        moveq #15,d1
.name:  move.b (a0)+,d0
        bne.s .char
        moveq #' ',d0
        subq.l #1,a0                    ; stay on the terminator
.char:  move.b d0,(a1)+
        dbra d1,.name
        move.b #' ',(a1)+
        move.b #' ',(a1)+
        move.w d2,d0
        bsr menu_format3
        lea txt_edits(pc),a0
.edits: move.b (a0)+,(a1)+
        bne.s .edits
.done:  movem.l (sp)+,d0-d2/a0-a1
        rts

menu_draw_name:
        movem.l d0-d4/a0,-(sp)
        bsr menu_clear
        bsr menu_draw_frame
        moveq #7,d1
        moveq #4,d2
        moveq #PANEL_FG,d3
        moveq #0,d4
        lea txt_name(pc),a0
        bsr menu_text
        moveq #9,d1
        moveq #PANEL_BAR,d4
        bsr menu_fill_row
        lea name(a4),a0
        moveq #0,d0
        move.b name_len(a4),d0
        move.b #'_',(a0,d0.w)           ; cursor; the terminator follows
        moveq #4,d2
        bsr menu_text
        clr.b (a0,d0.w)
        moveq #19,d1
        moveq #0,d2
        moveq #PANEL_HELP,d3
        moveq #0,d4
        lea txt_help_name(pc),a0
        bsr menu_text
        movem.l (sp)+,d0-d4/a0
        rts

; Message, question or prompt in menu_msg, with the key help for the mode.
menu_draw_message:
        movem.l d0-d4/a0,-(sp)
        bsr menu_clear
        bsr menu_draw_frame
        bsr.s menu_message_body
        moveq #19,d1
        moveq #0,d2
        moveq #PANEL_HELP,d3
        moveq #0,d4
        lea txt_help_continue(pc),a0
        move.b menu_mode(a4),d0
        cmp.b #M_CONFIRM,d0
        bne.s .prompt
        lea txt_help_yes_no(pc),a0
.prompt:
        cmp.b #M_PROMPT_SAVE,d0
        bne.s .help
        lea txt_help_prompt(pc),a0
.help:  bsr menu_text
        movem.l (sp)+,d0-d4/a0
        rts

menu_message_body:
        movem.l d1-d4/a0,-(sp)
        moveq #7,d1
        moveq #2,d2
        moveq #PANEL_FG,d3
        moveq #0,d4
        movea.l menu_msg(a4),a0
        bsr menu_text
        ; Prompts name the drive.
        move.b menu_mode(a4),d0
        moveq #0,d1
        cmp.b #M_PROMPT_SAVE,d0
        bne.s .disk2
        move.b menu_prompt(a4),d1
        bra.s .drive
.disk2: cmp.b #M_PROMPT_DISK2,d0
        bne.s .done
        move.b native_drive(a4),d1
.drive: lea menu_line(a4),a0
        move.b #'D',(a0)
        move.b #'F',1(a0)
        add.b #'0',d1
        move.b d1,2(a0)
        move.b #':',3(a0)
        clr.b 4(a0)
        moveq #13,d1
        moveq #2,d2
        bsr menu_text
.done:  movem.l (sp)+,d1-d4/a0
        rts

; A0: text shown alone, used while searching.
menu_show_message_only:
        move.l a0,menu_msg(a4)
        bra.s menu_message_body

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
txt_load_title:         dc.b 'LOAD',0
txt_free:               dc.b ':  ',0
txt_slots:              dc.b ' free save slots',0
txt_page:               dc.b '< Page ',0
txt_new_save:           dc.b '-- New save --',0
txt_edits:              dc.b ' edits',0
txt_no_saves:           dc.b 'No saves for this level.',0
txt_track:              dc.b 'Track ',0
txt_name:               dc.b 'Name for this save:',0
txt_searching:          dc.b 'Looking for the save disk...',0
txt_working:            dc.b 'Working with the disk...',0
txt_insert_save:        dc.b 'Insert the SAVE DISK into',$0a
                        dc.b 'the drive below and press Return.',$0a,$0a
                        dc.b 'A new disk can be initialized.',0
txt_insert_disk2:       dc.b 'Insert LEMMINGS DISK 2 into',$0a
                        dc.b 'the drive below and press Return.',0
txt_game_disk:          dc.b 'This is a Lemmings game disk,',$0a
                        dc.b 'not a save disk.',0
txt_init:               dc.b 'This is not a save disk.',$0a,$0a
                        dc.b 'Initialize it as a save disk?',$0a
                        dc.b 'ALL DATA ON IT WILL BE LOST.',0
txt_index_bad:          dc.b 'The save index is damaged.',$0a,$0a
                        dc.b 'Rebuild it from the saves?',$0a
                        dc.b 'This reads the whole disk.',0
txt_rebuild:            dc.b 'Rebuild the save index?',$0a
                        dc.b 'This reads the whole disk.',0
txt_overwrite:          dc.b 'Replace this save?',0
txt_delete:             dc.b 'Delete this save?',0
txt_load:               dc.b 'Load this save?',$0a,$0a
                        dc.b 'The level restarts from the',$0a
                        dc.b 'beginning with the saved terrain.',0
txt_saved:              dc.b 'Saved.',0
txt_deleted:            dc.b 'Deleted.',0
txt_rebuilt:            dc.b 'The save index was rebuilt.',0
txt_initialized:        dc.b 'The disk is now an empty save disk.',0
txt_cannot_save:        dc.b 'These edits cannot be saved.',0
txt_disk_full:          dc.b 'The save disk is full.',0
txt_wrong_level:        dc.b 'This save does not match the level.',0
txt_e_refused:          dc.b 'The operation was refused.',0
txt_e_cancelled:        dc.b 'Cancelled.',0
txt_e_no_disk:          dc.b 'There is no disk in the drive.',0
txt_e_read:             dc.b 'The disk cannot be read.',0
txt_e_wrong:            dc.b 'This is not a save disk.',0
txt_e_protected:        dc.b 'The disk is write-protected.',0
txt_e_changed:          dc.b 'The disk has changed. Try again.',0
txt_e_damaged:          dc.b 'Writing failed. This save and the',$0a
                        dc.b 'one next to it may be damaged.',$0a
                        dc.b 'Rebuild the index (R).',0
txt_e_index:            dc.b 'The save index is damaged.',$0a
                        dc.b 'Rebuild it (R).',0
txt_e_index_write:      dc.b 'Saved, but the index was not',$0a
                        dc.b 'updated. Rebuild it (R).',0
txt_help_save:          dc.b 'Ret:Save  Del:Delete  R:Index  Esc:Exit',0
txt_help_load:          dc.b 'Ret:Load  Del:Delete  R:Index  Esc:Exit',0
txt_help_name:          dc.b 'Return: save   Esc: back',0
txt_help_yes_no:        dc.b 'Y: yes   N: no',0
txt_help_continue:      dc.b 'Return: continue',0
txt_help_prompt:        dc.b 'Return: continue   Esc: cancel',0
txt_help_working:       dc.b 'Esc: cancel',0
        even
