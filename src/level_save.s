; Lemmings In-Game Level Editor V2.1.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Saving a custom level. S in the editor, while a custom level is edited,
; asks for the level's title and stores the level: on floppy into its slot of
; the level disk (a new level into the lowest free slot), under WHDLoad as a
; .lvl file in the directory Levels (a new level as LevelNNN.lvl). The saved
; record is the edited level's record with the editor's placements after its
; terrain pieces; it must pass the game's checks. The menu of menu.s shows
; the steps.
;
; On the level disk the data track is written and verified before the index
; on track 0, which is read again and compared with its snapshot first.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

LEVEL_FULL      equ -11                 ; no free slot on the level disk
LEVEL_OTHER     equ -12                 ; the slot holds another level

; From the frame hook: open the menu and ask for the title, starting with the
; current one. D0: 0 saves the level (S), 1 only renames it (N).
level_save_open:
        movem.l d0-d7/a0-a3,-(sp)
        bsr menu_begin
        lea custom_record+$7e0(pc),a0
        lea title_buf(pc),a1
        moveq #31,d0
        moveq #0,d1                     ; length without trailing spaces
        moveq #0,d2
.copy:  addq.w #1,d2
        move.b (a0)+,d3
        move.b d3,(a1)+
        cmp.b #' ',d3
        beq.s .next
        move.w d2,d1
.next:  dbra d0,.copy
        clr.b (a1)
        move.b d1,title_len(a4)
        lea title_buf(pc),a1
        clr.b (a1,d1.w)
        move.b #M_TITLE,menu_mode(a4)
        bsr level_draw_title
        movem.l (sp)+,d0-d7/a0-a3
        rts

; D0: raw key in the title entry.
level_title_key:
        cmp.b #KEY_ESC,d0
        beq menu_leave
        lea title_buf(pc),a0
        bsr menu_is_return
        beq.s .accept
        moveq #0,d1
        move.b title_len(a4),d1
        cmp.b #KEY_BACKSPACE,d0
        bne.s .char
        tst.w d1
        beq.s .done
        subq.w #1,d1
        clr.b (a0,d1.w)
        move.b d1,title_len(a4)
        bra level_draw_title
.char:  cmp.w #32,d1
        bhs.s .done
        cmp.b #$40,d0
        bhi.s .done                     ; character keys and space only
        lea ($a526).l,a1                ; the game's raw-key to ASCII tables
        tst.b shift(a4)
        beq.s .table
        lea ($a586).l,a1
.table: move.b (a1,d0.w),d0
        cmp.b #32,d0
        blo.s .done
        cmp.b #126,d0
        bhi.s .done
        move.b d0,(a0,d1.w)
        addq.b #1,d1
        clr.b (a0,d1.w)
        move.b d1,title_len(a4)
        bra level_draw_title
.accept:
        moveq #0,d1
        move.b title_len(a4),d1
        subq.w #1,d1
        bmi.s .done
.visible:
        cmpi.b #' ',(a0)+
        bne level_save_go
        dbra d1,.visible
.done:  rts

level_draw_title:
        movem.l d0-d4/a0,-(sp)
        bsr menu_clear
        bsr menu_draw_frame
        moveq #7,d1
        moveq #4,d2
        moveq #PANEL_FG,d3
        moveq #0,d4
        lea txt_title(pc),a0
        bsr menu_text
        moveq #9,d1
        moveq #PANEL_BAR,d4
        bsr menu_fill_row
        lea title_buf(pc),a0
        moveq #0,d0
        move.b title_len(a4),d0
        move.b #'_',(a0,d0.w)           ; cursor; the terminator follows
        moveq #4,d2
        bsr menu_text
        clr.b (a0,d0.w)
        moveq #19,d1
        moveq #0,d2
        moveq #PANEL_HELP,d3
        moveq #0,d4
        lea txt_help_name(pc),a0
        tst.b menu_kind(a4)
        beq.s .help
        lea txt_help_title(pc),a0
.help:  bsr menu_text
        movem.l (sp)+,d0-d4/a0
        rts

; Build the record and store it, or rename the level.
level_save_go:
        tst.b menu_kind(a4)
        bne level_rename
        bsr level_build
        tst.l d0
        beq.s .valid
        lea txt_level_invalid(pc),a0
        bra level_save_message
.valid: ifd WHDLOAD
        bsr menu_show_working
        bsr level_store_file
        bra level_saved
        else
        bra level_find_disk
        endif

; D0: result of storing. Show it; on success the saved record becomes the
; edited level's base, and its title the game's title, which the status block
; and the menu show.
level_saved:
        tst.l d0
        bne .error
        lea save_record+$7e0(pc),a0     ; a new title can be undone
        lea custom_record+$7e0(pc),a1
        moveq #31,d0
.same:  cmpm.b (a0)+,(a1)+
        dbne d0,.same
        beq.s .record
        bsr title_undo
        bsr undo_commit
        clr.b undo_open(a4)
.record:
        bsr undo_break                  ; a change after the save is a new step
        lea save_record(pc),a0
        lea custom_record(pc),a1
        move.w #LEVEL_SIZE/4-1,d0
.copy:  move.l (a0)+,(a1)+
        dbra d0,.copy
        lea custom_record+$7e0(pc),a0
        lea ($cd86).l,a1
        moveq #32/4-1,d0
.title: move.l (a0)+,(a1)+
        dbra d0,.title
        lea custom_record+$120(pc),a0   ; and its pieces, which snap and undo
        lea ($c6c6).l,a1                ; read from the game's copy
        move.w #$640/4-1,d0
.pieces:
        move.l (a0)+,(a1)+
        dbra d0,.pieces
        or.b #1,status_dirty(a4)
        ; The placements are part of the record now.
        bsr count_placements
        clr.l paint_count(a4)
        bsr level_remember
        lea txt_level_saved(pc),a0
        bra level_save_message
.error: lea txt_level_full(pc),a0
        cmp.l #LEVEL_FULL,d0
        beq.s level_save_message
        lea txt_level_other(pc),a0
        cmp.l #LEVEL_OTHER,d0
        beq.s level_save_message
        bsr menu_error_text

; A0: text. Show it; Return closes the menu (asking for disk 2 if needed).
level_save_message:
        bra menu_message

; The entered title becomes the edited level's title.
level_rename:
        bsr.s title_undo
        lea custom_record+$7e0(pc),a1
        bsr.s level_title_to
        bsr level_apply
        bra menu_close

; Take the title for undo before it changes. Preserves every register.
title_undo:
        movem.l d0-d1/a0,-(sp)
        movea.w #$7e0,a0
        moveq #32,d0
        moveq #0,d1
        bsr undo_record
        movem.l (sp)+,d0-d1/a0
        rts

; A1: 32 bytes. Store title_buf there, padded with spaces.
level_title_to:
        movem.l d0-d1/a0-a1,-(sp)
        lea title_buf(pc),a0
        moveq #31,d1
.char:  move.b (a0)+,d0
        bne.s .put
        subq.l #1,a0                    ; spaces after the end
        moveq #' ',d0
.put:   move.b d0,(a1)+
        dbra d1,.char
        movem.l (sp)+,d0-d1/a0-a1
        rts

; Build save_record from custom_record: its terrain pieces, then the
; placements, the title from title_buf. Return 0 when it passes the checks.
level_build:
        movem.l d1-d2/a0-a2,-(sp)
        lea custom_record(pc),a0
        lea save_record(pc),a1
        move.w #LEVEL_SIZE/4-1,d0
.copy:  move.l (a0)+,(a1)+
        dbra d0,.copy
        lea save_record(pc),a1
        bsr append_placements
        bne.s .bad
        lea save_record+$7e0(pc),a1
        bsr.s level_title_to
        lea save_record(pc),a0
        bsr check_level_record
        bra.s .done
.bad:   moveq #DISK_REFUSED,d0
.done:  movem.l (sp)+,d1-d2/a0-a2
        rts

        ifnd WHDLOAD
; Find the level disk in a drive, or ask for it, and store the level there.
; Esc while a drive is read cancels the save.
level_find_disk:
        moveq #0,d7
.drive: move.l d7,d0
        bsr drive_present
        bne.s .next
        bsr menu_show_working
        move.l d7,d0
        moveq #0,d1
        bsr disk_read_track
        bsr.s native_check
        tst.l d0
        beq.s .read
        cmp.l #DISK_CANCELLED,d0
        beq level_saved
        bra.s .next
.read:  lea install(pc),a0
        adda.l #DISK_TRACK,a0
        bsr validate_level_header
        tst.l d0
        beq.s .found
        cmp.l #DISK_INDEX,d0
        beq level_saved
.next:  addq.w #1,d7
        cmp.w #4,d7
        blo.s .drive
        st native_used(a4)              ; disk 2 may be taken out for it
        move.b #M_PROMPT_LEVEL,menu_mode(a4)
        lea txt_insert_level(pc),a0
        move.l a0,menu_msg(a4)
        bra menu_draw_message
.found: bsr menu_show_working
        move.l d7,d0
        move.w custom_slot(a4),d1
        ext.l d1
        bsr disk_store_level
        tst.l d0
        bne level_saved
        move.w d1,custom_slot(a4)
        addq.w #1,d1                    ; its number in the list
        move.w d1,custom_number(a4)
        bra level_saved

; D7: drive just read, D0: the result, with its track 0 in DISK_TRACK. When
; it is the drive the game reads disk 2 from and disk 2 is not there (its
; directory starts with Ground1), disk 2 must come back before the menu
; closes. Preserves every register.
native_check:
        cmp.b native_drive(a4),d7
        bne.s .done
        move.l a0,-(sp)
        tst.l d0
        bne.s .other
        lea install(pc),a0
        adda.l #DISK_TRACK+$410,a0
        cmpi.l #'Grou',(a0)
        bne.s .other
        cmpi.l #'nd1'<<8,4(a0)
        beq.s .disk2
.other: st native_used(a4)
.disk2: movea.l (sp)+,a0
.done:  rts

; The level disk prompt: Return looks again, Esc leaves.
level_prompt_key:
        cmp.b #KEY_ESC,d0
        beq menu_leave
        bsr menu_is_return
        beq level_find_disk
        rts

; D0: drive, D1: slot 0..317, or -1 for the lowest free one. Store
; save_record there. Return D0 = 0 and D1 = the slot, or an error. A new
; level passes over a slot that the index calls free but that holds data (an
; earlier save that could not update the index): it is never overwritten.
disk_store_level:
        movem.l d2-d7/a0-a6,-(sp)
        lea state(pc),a4
        move.l d1,d7
        move.l d1,d6                    ; negative: a new level
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
        bsr validate_level_header
        tst.l d0
        bne .release
        tst.l d7
        bpl.s .slot
        ; The lowest free slot by the index.
        moveq #0,d7
.free:  cmp.w #LEVEL_SLOTS,d7
        bhs.s .full
        lea install(pc),a2
        adda.l #DISK_HEADER+64,a2
        move.w d7,d0
        add.w d0,d0
        tst.b (a2,d0.w)
        beq.s .slot
.taken: addq.w #1,d7
        bra.s .free
.full:  moveq #LEVEL_FULL,d0
        bra .release
.slot:  cmp.l #LEVEL_SLOTS,d7
        bhs .refuse
        lea install(pc),a1
        adda.l #DISK_TRACK,a1
        move.l d7,d0
        lsr.w #1,d0
        addq.w #1,d0
        bsr disk_read_decoded
        tst.l d0
        bne .release
        move.l d7,d0
        and.w #1,d0
        mulu #LEVEL_SLOT_SIZE,d0
        lea 0(a1,d0.w),a2
        ; A slot the index calls free must be empty on the disk.
        lea install(pc),a0
        adda.l #DISK_HEADER+64,a0
        move.w d7,d0
        add.w d0,d0
        tst.b (a0,d0.w)
        bne.s .occupied
        movea.l a2,a0
        move.w #LEVEL_SLOT_SIZE/4-1,d0
.empty: tst.l (a0)+
        dbne d0,.empty
        bne .changed
        bra.s .write
        ; An occupied slot must still hold the edited level as it was
        ; loaded or last saved: another level disk has other levels there.
.occupied:
        movea.l a2,a0
        move.l #LEVEL_SIZE,d0
        moveq #-1,d1
        bsr crc32
        cmp.l saved_crc(a4),d0
        bne .other
.write: lea save_record(pc),a0
        move.w #LEVEL_SIZE/4-1,d0
.copy:  move.l (a0)+,(a2)+
        dbra d0,.copy
        move.w #(LEVEL_SLOT_SIZE-LEVEL_SIZE)/4-1,d0
.pad:   clr.l (a2)+
        dbra d0,.pad
        movea.l a1,a0
        bsr disk_write_decoded
        tst.l d0
        bne .release
        ; The data track is durable before the index is changed. Re-read
        ; track zero and refuse any changed snapshot before updating it.
        lea install(pc),a1
        adda.l #DISK_VERIFY,a1
        moveq #0,d0
        bsr disk_read_decoded
        tst.l d0
        bne.s .index_failed
        lea install(pc),a0
        adda.l #DISK_HEADER,a0
        bsr disk_compare
        bne.s .index_failed
        movea.l a0,a2
        lea save_record(pc),a0          ; state 2: valid for two players
        moveq #1,d1
        bsr two_player_level
        bne.s .state
        moveq #2,d1
.state: move.w d7,d0
        add.w d0,d0
        move.b d1,64(a2,d0.w)
        move.b save_record+$1b(pc),65(a2,d0.w)
        movea.l a2,a0
        bsr seal_level_index
        bsr disk_write_decoded
        tst.l d0
        beq.s .release
.index_failed:
        moveq #DISK_INDEX_WRITE,d0
        bra.s .release
.changed:
        tst.l d6
        bmi .taken                      ; a new level: the next free slot
        moveq #DISK_CHANGED,d0
        bra.s .release
.other: moveq #LEVEL_OTHER,d0
        bra.s .release
.refuse:
        moveq #DISK_REFUSED,d0
.release:
        bsr disk_release
.done:  move.l d7,d1
        movem.l (sp)+,d2-d7/a0-a6
        rts

; A0: complete level disk track 0. Seal a changed index and its header.
seal_level_index:
        movem.l d0-d5/a0-a2,-(sp)
        movea.l a0,a2
        lea 64(a2),a0
        move.l #LEVEL_SLOTS*2,d0
        moveq #-1,d1
        bsr crc32
        move.l d0,32(a2)
        movea.l a2,a0
        moveq #64,d0
        moveq #60,d1
        bsr crc32
        move.l d0,60(a2)
        movem.l (sp)+,d0-d5/a0-a2
        rts
        endif

        ifd WHDLOAD
; There is no level disk to ask for.
level_prompt_key:
        rts

; Store save_record as a file in Levels: the edited level's own file, or for
; a new level the first free name LevelNNN.lvl. Return D0 = 0, or an error.
level_store_file:
        movem.l d1-d7/a0-a3,-(sp)
        bsr file_mailbox
        bne.s .fail
        tst.w custom_slot(a4)
        bpl.s .save
        bsr level_new_name
        bne.s .done
.save:  bsr.s level_file_path
        move.l #LEVEL_SIZE,d0
        lea save_record(pc),a1
        jsr resload_SaveFile(a2)
        clr.w custom_slot(a4)           ; saved under custom_file from now on
        moveq #0,d0
        bra.s .done
.fail:  moveq #DISK_REFUSED,d0
.done:  movem.l (sp)+,d1-d7/a0-a3
        rts

; Put Levels/ and custom_file into list_path. Return A0 = list_path.
level_file_path:
        lea list_path(pc),a1
        lea levels_dir(pc),a0
.dir:   move.b (a0)+,(a1)+
        bne.s .dir
        move.b #'/',-1(a1)
        lea custom_file(pc),a0
.name:  move.b (a0)+,(a1)+
        bne.s .name
        lea list_path(pc),a0
        rts

; A2: resload base. Put the first name LevelNNN.lvl that is not in Levels
; into custom_file: not in the listing, and checked once more by its size,
; since the listing holds only the names that fit into its buffer. Return
; D0 = 0 (Z set), or LEVEL_FULL when Level001..Level999 are all taken.
level_new_name:
        move.l #LIST_NAMES_SIZE-1,d0
        lea levels_dir(pc),a0
        lea install(pc),a1
        adda.l #LIST_NAMES,a1
        movea.l a1,a3
        clr.b LIST_NAMES_SIZE-1(a1)
        jsr resload_ListFiles(a2)
        move.l d0,d6                    ; names in the list
        moveq #1,d5
.number:
        lea custom_file(pc),a1
        lea txt_new_file(pc),a0
.prefix:
        move.b (a0)+,(a1)+
        bne.s .prefix
        subq.l #1,a1
        move.l d5,d0
        bsr list_format3
        move.b #'.',(a1)+
        move.b #'l',(a1)+
        move.b #'v',(a1)+
        move.b #'l',(a1)+
        clr.b (a1)
        ; Is it in the list?
        movea.l a3,a0
        move.l d6,d4
        bra.s .more
.entry: lea custom_file(pc),a1
        bsr list_compare
        beq.s .taken
.skip:  tst.b (a0)+
        bne.s .skip
.more:  subq.l #1,d4
        bpl.s .entry
        bsr level_file_path             ; not listed; is there such a file?
        jsr resload_GetFileSize(a2)
        tst.l d0
        beq.s .done
.taken: addq.w #1,d5
        cmp.w #999,d5
        bls.s .number
        moveq #LEVEL_FULL,d0
.done:  rts

txt_new_file:           dc.b 'Level',0
        endif

txt_title:              dc.b 'Title for this level:',0
txt_help_name:          dc.b 'Return: save   Esc: back',0
txt_help_title:         dc.b 'Return: accept   Esc: back',0
txt_level_saved:        dc.b 'The level was saved.',0
txt_level_invalid:      dc.b 'The level cannot be saved: it is',$0a
                        dc.b 'outside the limits of the game.',0
        ifd WHDLOAD
txt_level_full:         dc.b 'There is no free name from',$0a
                        dc.b 'Level001.lvl to Level999.lvl.',0
        else
txt_level_full:         dc.b 'The level disk is full.',0
        endif
txt_level_other:        dc.b 'The level disk holds another level',$0a
                        dc.b 'in this place. Insert the disk the',$0a
                        dc.b 'level came from.',0
        ifnd WHDLOAD
txt_insert_level:       dc.b 'Insert the LEVEL DISK into a drive',$0a
                        dc.b 'and press Return.',0
        endif
        even
