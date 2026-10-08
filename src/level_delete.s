; Lemmings In-Game Level Editor V2.3.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Deleting a custom level. Del in the custom level list of the CUSTOM rating
; (not Lemmings' two-player list) reads the selected level afresh and asks
; before deleting it; only Return deletes. On a level disk the level's slot is
; cleared in the disk's update order: the data track is written and verified
; before the index entry on track 0 is cleared. With level files (FILES) its
; .lvl file in the directory Levels is deleted.
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

LEVEL_KEPT      equ -13                 ; the file is still there after deleting it

; From the list's input loop. The selected level is read afresh and named in
; a question: Return deletes it, Esc or the right button keeps it, and a
; click does nothing. After a deletion the list is read again at the same
; place; a failure shows its message as list_failed does.
list_delete:
        bsr list_delete_read
        tst.l d0
        bne list_failed
        bsr list_delete_ask
        bsr latch_buttons
.wait:  jsr WAIT_FRAME
        bsr menu_next_key
        tst.w d0
        bmi.s .mouse
        cmp.b #KEY_ESC,d0
        beq.s .keep
        bsr menu_is_return
        beq.s .delete
        bra.s .wait
.mouse: bsr right_edge
        bmi.s .keep
        btst #6,$bfe001                 ; a click does nothing, here or later
        seq last_left(a4)
        bra.s .wait
.keep:  bsr list_show
        bsr latch_buttons
        bra list_loop
.delete:
        lea txt_list_deleting(pc),a0
        bsr list_message
        bsr list_entry
        ifd FILES
        bsr level_delete_file
        else
        move.w d0,d3
        bsr list_status_entry
        moveq #0,d0
        move.b list_drive(a4),d0
        moveq #0,d1
        move.w d5,d1
        bsr disk_delete_level
        endif
        tst.l d0
        bne.s .failed
        bsr list_search
        bra list_loop
.failed:
        bsr level_delete_text
        bra list_failed

; Read the selected level afresh for the question: its title, or damaged.
; On floppy its track must decode, because a deletion writes the whole track
; back, and delete_crc keeps the CRC-32 of its slot. Return D0 = 0, or an
; error with A0 pointing to its message.
list_delete_read:
        movem.l d1-d7/a1-a3,-(sp)
        bsr list_entry
        move.w d0,d3
        bsr list_status_entry
        move.w d5,d6
        lea level_status(pc),a0
        clr.b 0(a0,d6.w)
        ifd FILES
        bsr list_read_level
        moveq #0,d0
        else
        bsr read_slot_track
        tst.l d0
        bne.s .error
        move.w d5,d0
        bsr slot_in_track
        movea.l a0,a2
        move.l #LEVEL_SLOT_SIZE,d0
        moveq #-1,d1
        bsr crc32
        move.l d0,delete_crc(a4)
        movea.l a2,a0
        bsr list_take_slot
        moveq #0,d0
        bra.s .done
.error: bsr menu_error_text
        moveq #-1,d0
        endif
.done:  movem.l (sp)+,d1-d7/a1-a3
        rts

; Show the question for the selected level, as list_delete_read read it.
list_delete_ask:
        movem.l d0-d7/a0-a3,-(sp)
        lea txt_list_head(pc),a0
        bsr list_text_begin
        lea txt_delete_ask(pc),a0
        bsr list_append
        move.b #2,(a1)+                 ; the level's row as the list shows it
        move.b #6,(a1)+
        bsr list_entry
        move.w d0,d3
        bsr list_status_entry
        bsr list_number
        bsr list_title
        clr.b (a1)+
        ifd FILES
        move.b #2,(a1)+                 ; row 7: the file name, up to 38
        move.b #7,(a1)+                 ; characters
        lea level_slots(pc),a0
        add.w d3,d3
        move.w 0(a0,d3.w),d0
        lea install(pc),a0
        adda.l #LIST_NAMES,a0
        adda.w d0,a0
        moveq #37,d0
.name:  move.b (a0)+,(a1)+
        dbeq d0,.name
        beq.s .ended
        clr.b (a1)+
.ended:
        endif
        bsr list_text_draw
        lea list_palette_rows(a4),a0
        move.w #PAL_HEAD,4*2(a0)
        move.w #PAL_HEAD,9*2(a0)
        move.w #PAL_SELECTED,6*2(a0)
        ifd FILES
        move.w #PAL_SELECTED,7*2(a0)
        endif
        bsr list_palettes
        movem.l (sp)+,d0-d7/a0-a3
        rts

; D0: error of a deletion. A0 returns its message.
level_delete_text:
        ifd FILES
        lea txt_delete_kept(pc),a0
        cmp.l #LEVEL_KEPT,d0
        beq.s .done
        else
        lea txt_delete_index(pc),a0
        cmp.l #DISK_INDEX_WRITE,d0
        beq.s .done
        lea txt_delete_damaged(pc),a0
        cmp.l #DISK_DAMAGED,d0
        beq.s .done
        endif
        bra menu_error_text
.done:  rts

        ifnd FILES
; D0: drive, D1: slot 0..317. Delete the level in the slot: its index entry
; must still be a level, and the slot must still hold what the question was
; asked about (delete_crc), so another level disk is never changed. The slot
; is cleared and its track written and verified before the index entry is
; cleared (disk_commit_slot). A slot that is already empty, left by an
; interrupted deletion, is not written again; only its entry is cleared.
; Return D0; every other register is preserved.
disk_delete_level:
        movem.l d1-d7/a0-a6,-(sp)
        lea state(pc),a4
        move.l d1,d7
        bsr level_disk_open
        bne.s .done
        cmp.l #LEVEL_SLOTS,d7
        bhs.s .refuse
        bsr index_entry
        tst.b (a0)                      ; a level by the index
        beq.s .changed
        bsr level_disk_track
        tst.l d0
        bne.s .release
        move.l d7,d0
        bsr slot_in_track
        movea.l a0,a2
        move.l #LEVEL_SLOT_SIZE,d0
        moveq #-1,d1
        bsr crc32
        cmp.l delete_crc(a4),d0
        bne.s .changed
        moveq #0,d2                     ; set when the slot holds data
        move.w #LEVEL_SLOT_SIZE/4-1,d0
.clear: tst.l (a2)
        beq.s .zero
        moveq #1,d2
.zero:  clr.l (a2)+
        dbra d0,.clear
        moveq #0,d3                     ; the entry of an empty slot
        bsr disk_commit_slot
        bra.s .release
.changed:
        moveq #DISK_CHANGED,d0
        bra.s .release
.refuse:
        moveq #DISK_REFUSED,d0
.release:
        bsr disk_release
.done:  movem.l (sp)+,d1-d7/a0-a6
        rts
        endif

        ifd FILES
; D0: list entry. Delete its file in Levels. From a read-only file system,
; or with SavePath for a file that is not in the save path, WHDLoad returns
; without deleting it, so the file must be gone afterwards. With its write
; cache WHDLoad deletes a preloaded file only when it quits, and until then
; resload_ListFiles still lists it: the name's hash is kept in deleted_names
; for list_deleted (when the table is full, such a file is listed as damaged
; until WHDLoad quits). Through dos.library the call itself reports a file it
; could not delete; its size alone cannot tell, as it is 0 for an empty file
; and on any error. Return D0 = 0, LEVEL_KEPT, or DISK_REFUSED without the
; mailbox.
level_delete_file:
        movem.l d1-d7/a0-a3,-(sp)
        lea level_slots(pc),a0
        add.w d0,d0
        move.w 0(a0,d0.w),d0
        lea install(pc),a0
        adda.l #LIST_NAMES,a0
        adda.w d0,a0
        move.l a0,d7
        bsr name_hash
        move.l d0,d6
        movea.l d7,a0
        bsr list_name_path
        bsr file_mailbox
        bne.s .done
        lea list_path(pc),a0
        jsr resload_DeleteFile(a2)
        ifnd WHDLOAD
        tst.l d0                        ; the system reports a failure
        beq.s .kept
        endif
        lea list_path(pc),a0
        jsr resload_GetFileSize(a2)
        tst.l d0
        bne.s .kept
        move.w deleted_count(a4),d1
        cmp.w #DELETED_MAX,d1
        bhs.s .done
        lsl.w #2,d1
        lea deleted_names(a4),a0
        move.l d6,0(a0,d1.w)
        addq.w #1,deleted_count(a4)
        bra.s .done
.kept:  moveq #LEVEL_KEPT,d0
.done:  movem.l (sp)+,d1-d7/a0-a3
        rts

; A0: a listed name. Z clear when it is to be left out of the list: this
; session deleted a file of that name (deleted_names), and it is not there.
; A name whose hash matches is checked with resload_GetFileSize, so another
; file of the same hash stays. Preserves every register.
list_deleted:
        tst.w deleted_count(a4)
        beq.s .end                      ; Z set: listed
        movem.l d0-d7/a0-a3,-(sp)
        movea.l a0,a3
        bsr.s name_hash
        lea deleted_names(a4),a1
        move.w deleted_count(a4),d1
        subq.w #1,d1
.find:  cmp.l (a1)+,d0
        dbeq d1,.find
        bne.s .listed
        movea.l a3,a0
        bsr list_name_path
        bsr file_mailbox
        bne.s .listed
        jsr resload_GetFileSize(a2)
        tst.l d0
        seq d0                          ; no such file: Z clear
        tst.b d0
        bra.s .done
.listed:
        cmp.b d0,d0
.done:  movem.l (sp)+,d0-d7/a0-a3
.end:   rts

; A0: a file name. D0 returns its hash for deleted_names. A0 ends past the
; name.
name_hash:
        move.l d1,-(sp)
        moveq #0,d0
.char:  moveq #0,d1
        move.b (a0)+,d1
        beq.s .done
        rol.l #5,d0
        eor.l d1,d0
        bra.s .char
.done:  move.l (sp)+,d1
        rts
        endif

; Text entries for the game's text routine (column, row, text, NUL; $FF
; ends a list) and messages; the game's font has no ':'.
        ifd FILES
txt_delete_ask:         dc.b 9,4,'This deletes the file',0
        else
txt_delete_ask:         dc.b 9,4,'This deletes the level',0
        endif
                        dc.b 7,9,'It cannot be brought back.',0
                        dc.b 3,12,'Return deletes, right button keeps',0,$ff
        ifd FILES
txt_list_deleting:      dc.b 'Deleting the file...',0
txt_delete_kept:        dc.b 'The file could not be deleted.',0
        else
txt_list_deleting:      dc.b 'Deleting the level...',0
txt_delete_index:       dc.b 'Deleted, but the index was not',$0a
                        dc.b 'updated. Delete the level again, or',$0a
                        dc.b 'repair it with savedisk.py',$0a
                        dc.b 'rebuild-index.',0
txt_delete_damaged:     dc.b 'Writing failed. The level next to',$0a
                        dc.b 'this one may be damaged.',0
        endif
        even
