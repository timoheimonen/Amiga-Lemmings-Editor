; Lemmings In-Game Level Editor V2.3.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Custom level list. The title screen's play button in the CUSTOM rating
; ("1 Player" in Lemmings, PLAY in Holiday Lemmings 1994) opens it in place of
; the title screen, on the game's own text screen (the one of the level
; briefing): 13 rows of 40 characters in the game's font, each row with its
; own palette. It lists the custom levels ten per page and returns to the
; title screen with the right mouse button or Esc. A click or Return plays the
; selected level through the game's own level start and briefing; when it
; ends, the game returns to the list. In Lemmings "2 Player" opens the same
; list with only the levels that are valid for two players
; (two_player_level), played in the game's two-player mode as a match of one
; level.
;
; The list runs at the top level of the game's main flow: entered from the
; title screen it drops the title routine's return address, and it leaves
; through the game's own way back to the title screen (TITLE_LOOP) or into a
; level (ENTER_LEVEL), as the game does after its result screens. The game
; keeps A4 at its row offset table (GAME_ROWS) everywhere; the list sets it
; back before leaving.
;
; A custom level is the Amiga game's bare 2048-byte level record. The floppy
; version of Lemmings keeps the levels on a level disk, read with the editor's
; track transport; on the title screen the transport borrows the game's raw
; track buffer, which is idle there. The other versions (FILES) keep them as
; .lvl files in a directory Levels, listed sorted by name: the WHDLoad
; versions in the install's directory (disk_file.s), the floppy version of
; Holiday Lemmings 1994 in the current directory (dos_file.s).
;
; A4 is the editor state, A5 the game globals and A6 the custom chip base.

LIST_ROWS       equ 10                  ; levels per page
LIST_FIRST      equ 2                   ; text row of the first level
TEXT_ROWS       equ 13
COPPER_GROUP    equ 68
PAL_HEAD        equ 1                   ; red
PAL_PAGE        equ 6                   ; cyan
PAL_LEVEL       equ 4                   ; blue
PAL_SELECTED    equ 3                   ; orange
PAL_HELP        equ 5                   ; green
LEVEL_SLOTS     equ 318
LEVEL_SLOT_SIZE equ 2816
LEVEL_SIZE      equ 2048
        ifd FILES
LIST_NAMES      equ $1a100              ; free part of the editor block
LIST_NAMES_SIZE equ $5e00
NAME_MAX        equ 107                 ; the longest AmigaDOS file name
        endif
LEVEL_INDEX_END equ 64+LEVEL_SLOTS*2
LS_UNKNOWN      equ 0                   ; level_status values
LS_OK           equ 1
LS_DAMAGED      equ 2

; Entered with a jump from the title screen (title.s, holiday94.s; inside the
; title routine called from the game's main flow): the play button lists every
; custom level, Lemmings' 2 Player the ones valid for two players
; (two_player_level).
level_list:
        addq.l #4,sp                    ; the title routine does not return
        lea state(pc),a4
        clr.b list_players(a4)
        ifd TWO_PLAYER
        bra.s list_enter
level_list_two:
        addq.l #4,sp
        lea state(pc),a4
        st list_players(a4)
        endif
list_enter:
        bsr list_begin

; Entered with a jump after a custom level, at the top level; the screen is
; black. The page and selection stay.
level_list_return:
        lea state(pc),a4
        lea $dff000,a6
        clr.b list_mode(a4)
        clr.w list_count(a4)
        clr.b key_head(a4)
        clr.b key_tail(a4)
        st list_open(a4)
        st title_disk(a4)
        lea txt_list_searching(pc),a0
        bsr list_message
        bsr list_fade_in
        bsr list_search

; The list's input loop, for the levels and for the graphics styles of a new
; level. D0 from the key and mouse handlers: -1 leave, 1 play, 2 edit,
; 3 delete.
list_loop:
.loop:  jsr WAIT_FRAME
        bsr menu_next_key
        tst.w d0
        bmi.s .mouse
        cmp.b #KEY_ESC,d0
        beq.s .leave
        bsr list_key
        bra.s .act
.mouse: bsr list_mouse
.act:   tst.w d0
        bmi.s .leave
        beq.s .loop
        cmp.w #3,d0
        beq.s .delete
        tst.b list_mode(a4)
        bne list_new_level
        move.w d0,d6
        cmp.w #2,d6
        bne.s .load
        tst.b list_players(a4)          ; the editor is for one player
        bne.s .loop
.load:  bsr list_load_level
        tst.l d0
        bne list_failed
        cmp.w #2,d6
        beq list_edit
        bra list_play
.delete:
        tst.b list_mode(a4)             ; not in the styles of New Level
        bne.s .loop
        tst.b list_players(a4)          ; nor for two players, like E
        bne.s .loop
        bra list_delete
.leave:
        ifnd FILES
        ; The title screen and the game's own levels load files by the
        ; directory of disk 2 too: disk 2 must be back in the game's drive.
        bsr list_disk2
        beq.s .fade
        bsr latch_buttons
        tst.b list_mode(a4)
        bne.s .styles
        bsr list_search                 ; cancelled: the list again
        bra list_loop
.styles:
        bsr list_show
        bra list_loop
.fade:
        endif
        bsr fade_black
        bsr list_close
        clr.b custom_play(a4)
        clr.b custom_edit(a4)
        move.w #RATINGS-1,G_RATING(a5)       ; the title screen's CUSTOM follows the last rating
        move.w list_old42(a4),G_LEVEL(a5)   ; and its level, which the tunes changed
        ifd G_TRIES
        move.b list_old_tries(a4),G_TRIES(a5) ; and the tries of its access code
        endif
        tst.b list_played(a4)
        beq.s .title
        clr.b list_played(a4)
        jsr LOAD_ICONS                       ; reload Icons, as the game does after a level
.title: lea (GAME_ROWS).l,a4             ; the game's A4 throughout
        jmp TITLE_LOOP

; From the title screen: keep the game's state that the list changes, to
; give it back when the list returns to the title screen (list_loop), start
; at the first page and fade the title screen out.
list_begin:
        clr.w list_page(a4)
        clr.w list_sel(a4)
        move.b G_TEXT_MODE(a5),list_old32(a4)
        move.w G_LEVEL(a5),list_old42(a4)
        ifd G_TRIES
        move.b G_TRIES(a5),list_old_tries(a4)
        endif

; Fade the screen to black.
fade_black:
        lea (FADE_BLACK).l,a0
        jmp FADE

; A0: message. Show it with the hint that a click looks for the levels
; again, and continue in the list's input loop.
list_failed:
        lea txt_list_again(pc),a3
        bsr list_message_more
        bsr latch_buttons
        st list_retry(a4)
        clr.w list_count(a4)
        bra list_loop

; Give the keys and the text mode back to the game.
list_close:
        clr.b list_open(a4)
        clr.b title_disk(a4)
        move.b list_old32(a4),G_TEXT_MODE(a5)
        rts

; Edit the level in custom_record: play it with the editor open from the
; first frame (load_reopen). custom_slot remembers where it came from: the
; level disk slot, or with level files (FILES) the list entry.
list_edit:
        bsr list_entry
        lea level_slots(pc),a0
        add.w d0,d0
        ifd FILES
        move.w 0(a0,d0.w),d0            ; the file name, kept for saving
        lea install(pc),a0
        adda.l #LIST_NAMES,a0
        adda.w d0,a0
        lea custom_file(pc),a1
        moveq #NAME_MAX-1,d0            ; the list holds no longer names
.name:  move.b (a0)+,(a1)+
        dbeq d0,.name
        clr.b (a1)
        bsr list_entry
        else
        move.w 0(a0,d0.w),d0
        endif
        move.w d0,custom_slot(a4)
        st custom_edit(a4)
        st load_reopen(a4)
        bsr list_entry
        bra.s list_start

; Play the level in custom_record: start it as the title screen's play button does
; with the level number chosen for its tune, then continue in the game's main
; flow at ENTER_LEVEL (level set-up, briefing, play).
list_play:
        clr.b custom_edit(a4)
        bsr list_entry

; D0: list entry (0-based), or -1 for a new level.
list_start:
        ifnd FILES
        bsr list_disk2
        beq.s .disk2
        clr.b custom_edit(a4)           ; cancelled: back to the list
        clr.b load_reopen(a4)
        bsr list_show
        bsr latch_buttons
        bra list_loop
.disk2:
        endif
        st custom_play(a4)
        st list_played(a4)
        bsr undo_clear                  ; a history per opened level
        clr.b edit_mode(a4)             ; the editor starts with the terrain
        clr.w obj_type(a4)
        move.w #$000f,obj_flags(a4)
        clr.b param_sel(a4)
        clr.b custom_test(a4)
        clr.b leaving(a4)
        bsr level_remember
        ifnd FILES
        tst.w d0
        bmi.s .number
        lea level_slots(pc),a0          ; the slot, whose number the list shows
        add.w d0,d0
        move.w 0(a0,d0.w),d0
        endif
.number:
        addq.w #1,d0
        move.w d0,custom_number(a4)
        subq.w #1,d0
        bpl.s .tune
        moveq #0,d0
.tune:  ext.l d0
        divu #17,d0
        swap d0                         ; the tune rotation of 17 by its number
        move.w d0,G_LEVEL(a5)
        clr.w G_RATING(a5)
        bsr fade_black
        bsr list_close
        ifd TWO_PLAYER
        tst.b list_players(a4)
        bne.s .two
        endif
        clr.b G_TWO_PLAYERS(a5)
        tst.b G_PANEL(a5)
        beq.s .panel
        jsr PANEL_ONE                       ; the one-player panel
        ifd TWO_PLAYER
        bra.s .panel
.two:   st G_TWO_PLAYERS(a5)                      ; as 2 Player does ($342C..$3450)
        clr.w G_WINS_BLUE(a5)                  ; no lemmings carried over, no wins
        clr.w G_WINS_GREEN(a5)
        clr.w G_SAVED_BLUE(a5)
        clr.w G_SAVED_GREEN(a5)
        tst.b G_PANEL(a5)
        bmi.s .panel
        jsr PANEL_TWO                       ; the two-player panel
        endif
.panel: lea (GAME_ROWS).l,a4             ; the game's A4 throughout
        jsr LOAD_LEVEL
        jsr TITLE_PREPARE
        jmp ENTER_LEVEL

        ifnd FILES
; Before a level starts, and before the list returns to the title screen.
; The game loads its files through the directory of
; disk 2 it read at start-up, from the drive it found disk 2 in ($2(A5)),
; without checking which disk is there, and keeps them in its file cache
; only once loaded. With one drive that drive may hold the level disk, and a
; file not loaded yet (the two-player panel, a style) would be read from it.
; Ask for disk 2 until its directory is back (the first file Ground1).
; Return Z set when disk 2 is there, clear when the right mouse button or
; Esc cancels. Preserves every register.
list_disk2:
        movem.l d0-d2/a0,-(sp)
        st title_disk(a4)               ; the transport uses the raw track buffer
.check: moveq #0,d0
        move.b G_DRIVE(a5),d0           ; CIA bit of the game's drive
        subq.b #3,d0
        moveq #0,d1
        bsr disk_read_track
        tst.l d0
        bne.s .ask
        bsr is_disk2
        beq.s .done
.ask:   move.b G_DRIVE(a5),d0
        add.b #'0'-3,d0
        lea txt_list_disk2_drive(pc),a0
        move.b d0,(a0)
        lea txt_list_disk2(pc),a0
        bsr list_message
        bsr latch_buttons
.wait:  jsr WAIT_FRAME
        bsr menu_next_key
        cmp.w #KEY_ESC,d0
        beq.s .cancel
        bsr right_edge
        bmi.s .cancel
        bsr left_edge
        bpl.s .wait
        lea txt_list_searching_disk2(pc),a0
        bsr list_message
        bra .check
.cancel:
        moveq #-1,d0                    ; Z clear
.done:  movem.l (sp)+,d0-d2/a0
        rts
        endif

; ---------------------------------------------------------------------------
; Playing a custom level: hooks in the game's level start, briefing and
; result screens. Each one does exactly the game's work unless custom_play is
; set.

; Replaces two instructions at HOOK_INJECT in the level loader (LOAD_LEVEL),
; after the level record has been copied to LEVEL_RECORD and before the loader
; reads its graphics style and
; special background: put the custom record there. The level bank cache
; (G_BANK) no longer matches LEVEL_RECORD, so the next original level
; reloads it.
custom_inject:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_play(a4)
        beq.s .game
        movem.l d0/a0-a1,-(sp)
        lea custom_record(pc),a0
        lea (LEVEL_RECORD).l,a1
        move.w #LEVEL_SIZE/4-1,d0
.copy:  move.l (a0)+,(a1)+
        dbra d0,.copy
        move.w #-1,G_BANK(a5)
        movem.l (sp)+,d0/a0-a1
.game:  movea.l (sp)+,a4
        lea (LEVEL_RECORD).l,a0
        move.w $1a(a0),d0
        jmp INJECT_DONE

; Replaces the briefing's two calls at HOOK_BRIEFING: the texts (BRIEF_TEXTS)
; and the level preview (BRIEF_PREVIEW). For a custom level the briefing shows its list
; number, the rating Custom, and ';' for any ':' in the title (the game's
; text routine takes ':' as a control character).
custom_brief:
        jsr BRIEF_TEXTS
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_play(a4)
        beq .done
        movem.l d0-d3/a0-a1,-(sp)
        lea (BRIEF_LEVEL).l,a1                ; "Level 00", 8 characters
        lea txt_brief_level(pc),a0
        move.w custom_number(a4),d0
        bne.s .number
        lea txt_brief_new(pc),a0
        bra.s .copy_new
.number:
        cmp.w #100,d0
        blo.s .name
        lea txt_brief_lvl(pc),a0
.name:  move.b (a0)+,(a1)+
        bne.s .name
        subq.l #1,a1
        and.l #$ffff,d0
        jsr NUMBER_DIGITS                       ; four ASCII digits in D0
        moveq #3,d2                     ; digits after the current one
.lead:  rol.l #8,d0                     ; skip leading zeros, keep the last digit
        tst.w d2
        beq.s .digits
        cmp.b #'0',d0
        bne.s .digits
        subq.w #1,d2
        bra.s .lead
.digits:
        move.b d0,(a1)+
        rol.l #8,d0
        dbra d2,.digits
        bra.s .pad
.copy_new:
        move.b (a0)+,(a1)+
        bne.s .copy_new
        subq.l #1,a1
.pad:   cmpa.l #BRIEF_LEVEL+8,a1
        bhs.s .rating
        move.b #' ',(a1)+
        bra.s .pad
.rating:
        lea (BRIEF_RATING).l,a1                ; the rating name, 8 characters
        lea txt_brief_rating(pc),a0
        moveq #7,d0
.copy:  move.b (a0)+,(a1)+
        dbra d0,.copy
        lea (BRIEF_TITLE).l,a1                ; the title, 32 characters
        moveq #31,d0
.title: cmpi.b #':',(a1)+
        bne.s .next
        move.b #';',-1(a1)
.next:  dbra d0,.title
        movem.l (sp)+,d0-d3/a0-a1
.done:  movea.l (sp)+,a4
        jmp BRIEF_PREVIEW

; Replaces HOOK_WON on the result screen when enough lemmings were saved.
; The game would continue with the next level; a custom level shows the
; result and returns to the list, or after a test play to the editor.
custom_won:
        clr.b G_RESULT_SHOWN(a5)
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_play(a4)
        movea.l (sp)+,a4
        bne.s .custom
        move.w G_LEVEL(a5),d0
        jmp WON_DONE
.custom:
        jsr RESULT_COMMENT                        ; the comment on the result
        jsr PRESS_BUTTON                       ; "Press mouse button to continue"
        lea (FADE_RESULT).l,a0
        jsr FADE
        jsr WAIT_CLICK
        bsr fade_black
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_edit(a4)
        movea.l (sp)+,a4
        beq level_list_return
        jsr LOAD_LEVEL                       ; the level again, in the editor
        jmp ENTER_LEVEL

; Replaces HOOK_QUIT, the right mouse button on the result screen after a
; failed level: back to the list instead of the title screen for a custom
; level, and back to the editor after a test play (the left button retries it
; through the level loader, as the game does).
custom_quit:
        bsr fade_black
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_edit(a4)
        bne.s .editor
        tst.b custom_play(a4)
        movea.l (sp)+,a4
        bne level_list_return
        jmp QUIT_DONE
.editor:
        movea.l (sp)+,a4
        jsr LOAD_LEVEL                       ; the level again, in the editor
        jmp ENTER_LEVEL

; Replaces HOOK_ENDED after the level has ended and faded out, before the
; result screen (RESUME_ENDED). When the editor was
; left with Esc, go to the list without a result screen.
custom_ended:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b leaving(a4)
        beq.s .game
        clr.b leaving(a4)
        clr.b custom_edit(a4)
        movea.l (sp)+,a4
        ifd G_MUSIC
        clr.b G_MUSIC(a5)               ; as the replaced instructions do
        endif
        bsr fade_black
        bra level_list_return
.game:  movea.l (sp)+,a4
        RESUME_ENDED

        ifd TWO_PLAYER
; Replaces $918..$91F in the two-player result, after the level's win has
; been counted: BSR $9CA (the wins) / ADDQ.W #1,$42(A5) (the next level). A
; custom level is a match of one level: show the winner as at the end of the
; game's own match ($96A..$9BC) instead of going on to the next level and its
; access code.
custom_match:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_play(a4)
        movea.l (sp)+,a4
        bne.s .custom
        jsr MATCH_WINS
        addq.w #1,G_LEVEL(a5)
        jmp MATCH_NEXT
.custom:
        jmp MATCH_WINNER

; Replaces $9BE..$9C5 at the end of the two-player match, after the fade to
; black: CLR.B $38(A5) / CLR.W $42(A5), then back to the title screen. A
; custom level returns to the list.
custom_match_end:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_play(a4)
        movea.l (sp)+,a4
        bne level_list_return
        clr.b G_TITLE_FLAG(a5)
        clr.w G_LEVEL(a5)
        jmp MATCH_END_DONE
        endif

; Replaces HOOK_BRIEF_WAIT at the end of the briefing: the click wait (WAIT_CLICK)
; and the following LEA. An edited custom level (in the editor or a test
; play) starts at once.
briefing_wait:
        move.l a0,-(sp)
        lea state(pc),a0
        tst.b custom_edit(a0)
        movea.l (sp)+,a0
        bne.s .done
        jsr WAIT_CLICK
.done:  lea (FADE_BLACK).l,a0
        jmp BRIEF_WAIT_DONE

txt_brief_level:        dc.b 'Level ',0
txt_brief_lvl:          dc.b 'Lvl ',0
txt_brief_new:          dc.b 'New',0
txt_brief_rating:       dc.b 'Custom  '
        even

; ---------------------------------------------------------------------------
; A new level. New Level in CUSTOM (title.s, holiday94.s) jumps here from
; inside the title routine, like the play button. The list shows the game's
; graphics styles, in Lemmings then the same for two players; the chosen one
; starts an empty level in the editor, with an entrance and an exit, or for
; two players with an entrance, an exit for each player and the marker.

level_new:
        addq.l #4,sp                    ; the title routine does not return
        lea state(pc),a4
        lea $dff000,a6
        clr.b list_players(a4)
        bsr list_begin
        st list_mode(a4)
        clr.b key_head(a4)
        clr.b key_tail(a4)
        clr.b list_retry(a4)
        st list_open(a4)
        clr.b title_disk(a4)
        lea level_slots(pc),a0
        lea level_status(pc),a1
        lea level_titles(pc),a2
        ifd TWO_PLAYER
        ; The styles for one player, then for two players.
        moveq #0,d0
.style: move.w d0,(a0)+
        move.b #LS_OK,(a1)+
        moveq #31,d2
.pad:   move.b #' ',(a2)+
        dbra d2,.pad
        lea -32(a2),a2
        lea txt_styles(pc),a3
        move.w d0,d2
        cmp.w #STYLES,d2
        blo.s .skip
        subq.w #STYLES,d2
        bra.s .skip
.names: tst.b (a3)+
        bne.s .names
.skip:  dbra d2,.names
.name:  move.b (a3)+,d2
        beq.s .players
        move.b d2,(a2)+
        bra.s .name
.players:
        cmp.w #STYLES,d0
        blo.s .next
        lea txt_two_players(pc),a3
.two:   move.b (a3)+,d2
        beq.s .next
        move.b d2,(a2)+
        bra.s .two
.next:  lea level_titles(pc),a2
        addq.w #1,d0
        move.w d0,d2
        lsl.w #5,d2
        adda.w d2,a2
        cmp.w #2*STYLES,d0
        blo.s .style
        move.w d0,list_count(a4)
        else
        ; The game's styles (STYLE_MASK); level_slots holds their numbers.
        moveq #0,d0                     ; list entry
        moveq #0,d3                     ; style
        lea txt_styles(pc),a3
.style: moveq #STYLE_MASK,d2
        btst d3,d2
        beq.s .next
        move.w d3,(a0)+
        move.b #LS_OK,(a1)+
        moveq #31,d2
.pad:   move.b #' ',(a2)+
        dbra d2,.pad
        lea -32(a2),a2
.name:  move.b (a3)+,d2
        beq.s .named
        move.b d2,(a2)+
        bra.s .name
.named: addq.w #1,d0
        lea level_titles(pc),a2
        move.w d0,d2
        lsl.w #5,d2
        adda.w d2,a2
.next:  addq.w #1,d3
        cmp.w #STYLES,d3
        blo.s .style
        move.w d0,list_count(a4)
        endif
        bsr list_show
        bsr list_fade_in
        bsr latch_buttons
        bra list_loop

; Build a new level of the selected style in custom_record and edit it.
list_new_level:
        lea custom_record(pc),a0
        movea.l a0,a1
        move.w #LEVEL_SIZE/4-1,d0
.clear: clr.l (a1)+
        dbra d0,.clear
        lea new_level(pc),a1
        moveq #new_level_end-new_level-1,d0
.header:
        move.b (a1)+,(a0)+
        dbra d0,.header
        lea custom_record(pc),a0
        move.w list_sel(a4),d0
        ifd TWO_PLAYER
        cmp.w #STYLES,d0
        blo.s .style
        subq.w #STYLES,d0               ; for two players: other objects
        lea $20(a0),a1
        lea new_level_two(pc),a2
        moveq #new_level_two_end-new_level_two-1,d1
.two:   move.b (a2)+,(a1)+
        dbra d1,.two
        else
        lea level_slots(pc),a1          ; the style of the entry
        add.w d0,d0
        move.w 0(a1,d0.w),d0
        endif
.style: move.w d0,$1a(a0)
        lea $120(a0),a1
        lea $760(a0),a2
.terrain:
        move.l #-1,(a1)+
        cmpa.l a2,a1
        blo.s .terrain
        lea $7e0(a0),a1
        lea txt_new_title(pc),a2
        moveq #31,d0
.title: move.b (a2)+,(a1)+
        dbra d0,.title
        move.w #-1,custom_slot(a4)
        st custom_edit(a4)
        st load_reopen(a4)
        moveq #-1,d0
        bra list_start

; The start of a new level's record: parameters, start position, and an
; entrance and an exit (objects 1 and 2) that fit every style.
new_level:
        dc.w 50,20,10,5                 ; release rate, lemmings, to save, minutes
        dc.w 10,10,10,10,10,10,10,10    ; skills
        dc.w 0                          ; start position
        dc.w 0,0,0                      ; style (set), special, unused
        dc.w 160,24,1,$000f             ; entrance
        dc.w 480,120,0,$000f            ; exit
new_level_end:
        ifd TWO_PLAYER
; The objects of a new level for two players: an entrance, the blue player's
; exit, the green player's exit and its marker (two_player_level).
new_level_two:
        dc.w 144,24,1,$000f             ; entrance
        dc.w 32,120,0,$000f             ; blue exit
        dc.w 256,120,0,$000f            ; green exit
        dc.w 272,96,2,$000f             ; marker
new_level_two_end:
        endif

txt_styles:
        STYLE_NAMES
        ifd TWO_PLAYER
txt_two_players:
        dc.b ' for two players',0
        endif
txt_new_title:
        dc.b 'New level                       '
        even

; D0: list entry of the selection (0-based).
list_entry:
        move.w list_page(a4),d0
        mulu #LIST_ROWS,d0
        add.w list_sel(a4),d0
        rts

; Find the levels and show the current page, or a message. A selection
; beyond the last level (fewer levels than before) moves to the last one.
list_search:
        lea txt_list_searching(pc),a0
        bsr list_message
        bsr list_find_disk
        tst.l d0
        bne.s .message
        lea txt_list_empty(pc),a0
        tst.b list_players(a4)
        beq.s .count
        lea txt_list_no_two(pc),a0
.count: tst.w list_count(a4)
        beq.s .message
        bsr list_entry
        cmp.w list_count(a4),d0
        blo.s .show
        move.w list_count(a4),d0
        subq.w #1,d0
        ext.l d0
        divu #LIST_ROWS,d0
        move.w d0,list_page(a4)
        swap d0
        move.w d0,list_sel(a4)
.show:  bsr list_show
        bra latch_buttons
.message:
        bsr list_message
        bra latch_buttons

; D0: raw key. Cursor keys move the selection and turn pages. D0 returns 1
; for Return (play), 2 for E (edit), 3 for Del (delete), otherwise 0, and 0
; also when the list has no levels.
list_key:
        bsr.s .key
        cmp.b #KEY_E,d0
        beq.s .edit
        cmp.b #KEY_DEL,d0
        beq.s .delete
        bsr menu_is_return
        seq d0
        and.w #1,d0
.count: tst.w list_count(a4)
        bne.s .play
        moveq #0,d0
.play:  tst.w d0
        rts
.edit:  moveq #2,d0
        bra.s .count
.delete:
        moveq #3,d0
        bra.s .count
.key:   move.w d0,-(sp)
        bsr.s list_move
        move.w (sp)+,d0
        rts

list_move:
        tst.w list_count(a4)
        beq.s .done
        cmp.b #KEY_UP,d0
        beq.s .up
        cmp.b #KEY_DOWN,d0
        beq.s .down
        cmp.b #KEY_LEFT,d0
        beq list_previous
        cmp.b #KEY_RIGHT,d0
        beq list_next
.done:  rts
.up:    move.w list_sel(a4),d0
        beq.s .up_page
        subq.w #1,d0
        bra list_select
.up_page:
        tst.w list_page(a4)
        beq.s .done
        move.w #LIST_ROWS-1,list_sel(a4)
        subq.w #1,list_page(a4)
        bra list_show
.down:  move.w list_sel(a4),d0
        addq.w #1,d0
        bsr list_page_rows
        cmp.w d1,d0
        blo list_select
        move.w list_page(a4),d0
        addq.w #1,d0
        bsr list_page_exists
        bne.s .done
        clr.w list_sel(a4)
        move.w d0,list_page(a4)
        bra list_show

; Mouse: moving the pointer onto a level selects it, a click on it plays it
; (D0 returns 1), a click on the page line turns the page. D0 returns -1 when
; the right button asks to leave, otherwise 0.
list_mouse:
        bsr right_edge
        bpl.s .left
        moveq #-1,d0
        rts
.left:  bsr list_pointer_row
        move.w d0,d2
        cmp.w list_hover(a4),d0
        beq.s .button                   ; the keys may have moved on
        move.w d0,list_hover(a4)
        tst.w list_count(a4)
        beq.s .button
        sub.w #LIST_FIRST,d0
        bmi.s .button
        bsr list_page_rows
        cmp.w d1,d0
        bhs.s .button
        cmp.w list_sel(a4),d0
        beq.s .button
        bsr list_select
.button:
        bsr left_edge
        bpl.s .none
        tst.w list_count(a4)
        bne.s .page
        tst.b list_retry(a4)
        beq.s .none
        bsr list_search
        bra.s .none
.page:  move.w d2,d0
        sub.w #LIST_FIRST,d0
        bmi.s .line
        bsr list_page_rows
        cmp.w d1,d0
        bhs.s .line
        move.w d0,list_sel(a4)
        moveq #1,d0
        rts
.line:  cmp.w #1,d2
        bne.s .none
        move.w (MOUSE_X).l,d0
        cmp.w #160,d0
        blo.s .back
        bsr list_next
        bra.s .none
.back:  bsr list_previous
.none:  moveq #0,d0
        rts

; D0: text row under the mouse pointer, or -1.
list_pointer_row:
        move.w (MOUSE_Y).l,d0
        subq.w #8,d0
        bmi.s .none
        lsr.w #4,d0
        cmp.w #TEXT_ROWS,d0
        blo.s .done
.none:  moveq #-1,d0
.done:  rts

; D1: number of levels on the current page.
list_page_rows:
        move.l d0,-(sp)
        move.w list_page(a4),d0
        mulu #LIST_ROWS,d0
        move.w list_count(a4),d1
        sub.w d0,d1
        cmp.w #LIST_ROWS,d1
        bls.s .done
        moveq #LIST_ROWS,d1
.done:  move.l (sp)+,d0
        rts

; D0: page. Z set when it has at least one level.
list_page_exists:
        move.l d0,-(sp)
        mulu #LIST_ROWS,d0
        cmp.w list_count(a4),d0
        blo.s .yes
        moveq #1,d0
        bra.s .done
.yes:   moveq #0,d0
.done:  movem.l (sp)+,d0              ; keeps Z
        rts

list_previous:
        tst.w list_page(a4)
        beq.s .done
        subq.w #1,list_page(a4)
        clr.w list_sel(a4)
        bra list_show
.done:  rts

list_next:
        move.w list_page(a4),d0
        addq.w #1,d0
        bsr list_page_exists
        bne.s .done
        move.w d0,list_page(a4)
        clr.w list_sel(a4)
        bra list_show
.done:  rts

; D0: row on the page. Move the highlight there.
list_select:
        move.w list_sel(a4),d1
        add.w #LIST_FIRST,d1
        moveq #PAL_LEVEL,d2
        bsr list_row_palette
        move.w d0,list_sel(a4)
        move.w d0,d1
        add.w #LIST_FIRST,d1
        moveq #PAL_SELECTED,d2
        bra list_row_palette

; ---------------------------------------------------------------------------
; Screen

; Clear the text screen to the briefing background; nothing is visible until
; the row palettes are set.
list_screen:
        movem.l d0-d7/a0-a3,-(sp)
        move.w #$50,G_TEXT_STRIDE(a5)
        move.w #$d0,G_TEXT_HEIGHT(a5)
        move.l #TEXT_SCREEN,G_TEXT_DEST(a5)
        jsr TEXT_BACKGROUND
        st G_TEXT_MODE(a5)
        movem.l (sp)+,d0-d7/a0-a3
        rts

; D1: text row, D2: palette. Show the row in that palette at once.
list_row_palette:
        movem.l d0-d2/a0-a1,-(sp)
        lea list_palette_rows(a4),a0
        add.w d1,d1
        move.w d2,0(a0,d1.w)
        lsr.w #1,d1
        lea (PALETTES).l,a0
        lsl.w #5,d2
        adda.w d2,a0
        lea (COPPER_ROWS+2).l,a1
        mulu #COPPER_GROUP,d1
        adda.w d1,a1
        moveq #15,d0
.colour:
        move.w (a0)+,(a1)
        addq.l #4,a1
        dbra d0,.colour
        movem.l (sp)+,d0-d2/a0-a1
        rts

; Set every row's palette from list_palette_rows.
list_palettes:
        movem.l d1-d2/a0,-(sp)
        lea list_palette_rows(a4),a0
        moveq #0,d1
.row:   move.w (a0)+,d2
        bsr list_row_palette
        addq.w #1,d1
        cmp.w #TEXT_ROWS,d1
        blo.s .row
        movem.l (sp)+,d1-d2/a0
        rts

; Fade the screen in from black to list_palette_rows.
list_fade_in:
        movem.l d0-d7/a0-a3,-(sp)
        lea list_palette_rows(a4),a0
        jsr FADE
        movem.l (sp)+,d0-d7/a0-a3
        rts

; Row palettes of the list: heading, page line, levels, help line.
list_default_palettes:
        move.l a0,-(sp)
        lea list_palette_rows(a4),a0
        move.w #PAL_HEAD,(a0)+
        move.w #PAL_PAGE,(a0)+
        moveq #LIST_ROWS-1,d0
.level: move.w #PAL_LEVEL,(a0)+
        dbra d0,.level
        move.w #PAL_HELP,(a0)
        movea.l (sp)+,a0
        rts

; A0: message (rows separated by $0A). Show it below the heading.
list_message:
        move.l a3,-(sp)
        suba.l a3,a3
        bsr.s list_message_more
        movea.l (sp)+,a3
        rts

; A0: message, A3: a further message from the row after it, or 0.
list_message_more:
        movem.l d0-d7/a0-a3,-(sp)
        movea.l a0,a2
        lea txt_list_head(pc),a0
        tst.b list_players(a4)
        beq.s .head
        lea txt_list_head_two(pc),a0
.head:  bsr.s list_text_begin
        moveq #4,d1                     ; first message row
.line:  move.b #2,(a1)+
        move.b d1,(a1)+
.char:  move.b (a2)+,d0
        beq.s .end
        cmp.b #$0a,d0
        beq.s .next
        move.b d0,(a1)+
        bra.s .char
.end:   move.l a3,d0
        beq.s .last
        movea.l a3,a2
        suba.l a3,a3
.next:  clr.b (a1)+
        addq.w #1,d1
        bra.s .line
.last:  clr.b (a1)+
        lea txt_list_back(pc),a0
        bsr.s list_append
        bsr.s list_text_draw
        bsr list_palettes
        movem.l (sp)+,d0-d7/a0-a3
        rts

; A0: the heading's text entries. Clear the text screen, set the list's row
; palettes and start the text entries in list_text with the heading; A1
; returns past it. D0 is changed.
list_text_begin:
        bsr list_screen
        bsr list_default_palettes
        lea list_text(pc),a1
        bra.s list_append

; A1: past the last text entry in list_text. End the entries and draw them.
list_text_draw:
        move.b #$ff,(a1)
        lea list_text(pc),a0
        jmp DRAW_TEXT

; A0: complete text entries (column, row, text, NUL), ended by $FF. Append
; them at A1 without the end marker.
list_append:
.copy:  move.b (a0)+,d0
        cmp.b #$ff,d0
        beq.s .done
        move.b d0,(a1)+
        move.b (a0)+,(a1)+
.char:  move.b (a0)+,(a1)+
        bne.s .char
        bra.s .copy
.done:  rts

; Read the titles of the current page if necessary and draw it.
list_show:
        movem.l d0-d7/a0-a3,-(sp)
        tst.b list_mode(a4)
        bne.s .styles
        bsr list_read_page
.styles:
        lea txt_list_head(pc),a0
        tst.b list_players(a4)
        beq.s .one
        lea txt_list_head_two(pc),a0
.one:   tst.b list_mode(a4)
        beq.s .head
        lea txt_new_head(pc),a0
.head:  bsr list_text_begin
        ; "< Page nn of nn >"
        move.b #11,(a1)+
        move.b #1,(a1)+
        lea txt_list_page(pc),a0
.page:  move.b (a0)+,(a1)+
        bne.s .page
        subq.l #1,a1
        move.w list_page(a4),d0
        addq.w #1,d0
        bsr list_format2
        lea txt_list_of(pc),a0
.of:    move.b (a0)+,(a1)+
        bne.s .of
        subq.l #1,a1
        move.w list_count(a4),d0
        add.w #LIST_ROWS-1,d0
        ext.l d0
        divu #LIST_ROWS,d0
        bsr list_format2
        move.b #' ',(a1)+
        move.b #'>',(a1)+
        clr.b (a1)+
        ; The levels: slot number and title.
        bsr list_page_rows
        move.w list_page(a4),d3
        mulu #LIST_ROWS,d3
        moveq #LIST_FIRST,d4
        subq.w #1,d1
.level: move.b #2,(a1)+
        move.b d4,(a1)+
        bsr list_status_entry
        tst.b list_mode(a4)
        bne.s .name
        bsr list_number
.name:  bsr list_title
        clr.b (a1)+
        addq.w #1,d3
        addq.w #1,d4
        dbra d1,.level
        lea txt_list_help(pc),a0
        tst.b list_players(a4)
        beq.s .help_one
        lea txt_list_help_two(pc),a0
.help_one:
        tst.b list_mode(a4)
        beq.s .help
        lea txt_new_help(pc),a0
.help:  bsr list_append
        bsr list_text_draw
        move.w list_sel(a4),d1
        add.w #LIST_FIRST,d1
        lea list_palette_rows(a4),a0
        add.w d1,d1
        move.w #PAL_SELECTED,0(a0,d1.w)
        bsr list_palettes
        bsr list_pointer_row
        move.w d0,list_hover(a4)
        movem.l (sp)+,d0-d7/a0-a3
        rts

; D3: list entry. D5 returns its entry in level_status and level_titles: the
; slot on a level disk, the list entry with level files (FILES).
list_status_entry:
        move.w d3,d5
        ifnd FILES
        move.l a0,-(sp)
        lea level_slots(pc),a0
        add.w d5,d5
        move.w 0(a0,d5.w),d5
        movea.l (sp)+,a0
        endif
        rts

; D5: slot (level disk) or list entry (FILES). Append the number the list shows
; for it (three digits) and a space to A1. D0 is changed.
list_number:
        move.w d5,d0
        addq.w #1,d0
        bsr list_format3
        move.b #' ',(a1)+
        rts

; D5: slot (level disk) or list entry (FILES). Append its 32-character title
; to A1, or a damage note. The
; game's text routine takes ':' as a control character; show ';' instead.
list_title:
        movem.l d0-d1/a0,-(sp)
        lea level_status(pc),a0
        cmp.b #LS_OK,0(a0,d5.w)
        bne.s .damaged
        lea level_titles(pc),a0
        move.w d5,d0
        lsl.w #5,d0
        adda.w d0,a0
        moveq #31,d1
.char:  move.b (a0)+,d0
        cmp.b #':',d0
        bne.s .put
        moveq #';',d0
.put:   move.b d0,(a1)+
        dbra d1,.char
        bra.s .done
.damaged:
        lea txt_list_damaged(pc),a0
.copy:  move.b (a0)+,(a1)+
        bne.s .copy
        subq.l #1,a1
.done:  movem.l (sp)+,d0-d1/a0
        rts

; D0: 0..99 appended to A1 as two digits.
list_format2:
        movem.l d0-d3,-(sp)
        and.l #$ffff,d0
        jsr NUMBER_DIGITS                       ; four ASCII digits in D0
        move.w d0,d1
        lsr.w #8,d1
        move.b d1,(a1)+
        move.b d0,(a1)+
        movem.l (sp)+,d0-d3
        rts

; D0: 0..999 appended to A1 as three digits.
list_format3:
        movem.l d0-d3,-(sp)
        and.l #$ffff,d0
        jsr NUMBER_DIGITS
        rol.l #8,d0
        moveq #2,d1
.digit: rol.l #8,d0
        move.b d0,(a1)+
        dbra d1,.digit
        movem.l (sp)+,d0-d3
        rts

; ---------------------------------------------------------------------------
; Level disk

; Find the custom levels. Return D0 = 0 with list_count and level_slots set,
; or with A0 pointing to a message. list_retry tells whether a click searches
; again.
list_find_disk:
        clr.b list_retry(a4)
        ifd FILES
        bra list_find_files
        else
        moveq #0,d7
.drive: move.l d7,d0
        bsr drive_present
        bne.s .next
        move.l d7,d0
        bsr list_try_drive
        tst.l d0
        beq.s .done
        cmp.l #DISK_INDEX,d0
        beq.s .index
        cmp.l #DISK_CANCELLED,d0
        beq.s .fail
.next:  addq.w #1,d7
        cmp.w #4,d7
        blo.s .drive
.fail:  st list_retry(a4)
        lea txt_list_insert(pc),a0
        moveq #-1,d0
.done:  rts
.index: st list_retry(a4)
        lea txt_e_index(pc),a0
        moveq #-1,d0
        rts

; D0: drive. Read track 0 and accept it when it is a valid level disk.
list_try_drive:
        movem.l d1-d7/a1-a3,-(sp)
        move.b d0,list_drive(a4)
        moveq #0,d1
        bsr disk_read_track
        tst.l d0
        bne.s .done
        lea install(pc),a0
        adda.l #DISK_TRACK,a0
        bsr validate_level_header
        tst.l d0
        bne.s .done
        ; Occupied slots in slot order; no title is known yet.
        lea 64(a0),a1
        lea level_slots(pc),a2
        lea level_status(pc),a3
        moveq #0,d1
        moveq #0,d2
.slot:  clr.b (a3)+
        move.b (a1),d0
        beq.s .empty
        tst.b list_players(a4)
        beq.s .take
        cmp.b #2,d0                     ; valid for two players
        bne.s .empty
.take:  move.w d1,(a2)+
        addq.w #1,d2
.empty: addq.l #2,a1
        addq.w #1,d1
        cmp.w #LEVEL_SLOTS,d1
        blo.s .slot
        move.w d2,list_count(a4)
        moveq #0,d0
.done:  movem.l (sp)+,d1-d7/a1-a3
        rts

; A0: complete track 0. Return 0 for a supported level disk with a valid
; index, otherwise DISK_WRONG or DISK_INDEX. Preserves A0.
validate_level_header:
        movem.l d1-d7/a0-a2,-(sp)
        movea.l a0,a2
        lea level_disk_header(pc),a1
        moveq #7,d1
.header:
        move.l (a0)+,d0
        cmp.l (a1)+,d0
        bne .wrong
        dbra d1,.header
        addq.l #4,a0
        moveq #5,d1
.reserved:
        tst.l (a0)+
        bne .wrong
        dbra d1,.reserved
        lea LEVEL_INDEX_END(a2),a0
        move.w #($400-LEVEL_INDEX_END)/2-1,d1
.pad:   tst.w (a0)+
        bne.s .wrong
        dbra d1,.pad
        cmpi.l #'Rese',(a0)+
        bne.s .wrong
        cmpi.l #'rved',(a0)+
        bne.s .wrong
        move.w #(TRACK_BYTES-$408)/2-1,d1
.rest:  tst.w (a0)+
        bne.s .wrong
        dbra d1,.rest
        movea.l a2,a0
        moveq #64,d0
        moveq #60,d1
        bsr crc32
        cmp.l 60(a2),d0
        bne.s .wrong
        lea 64(a2),a0
        move.l #LEVEL_SLOTS*2,d0
        moveq #-1,d1
        bsr crc32
        cmp.l 32(a2),d0
        bne.s .index
        lea 64(a2),a0
        move.w #LEVEL_SLOTS-1,d1
.entry: move.b (a0)+,d0
        move.b (a0)+,d2
        tst.b d0
        bne.s .used
        tst.b d2
        bne.s .index
        bra.s .next
.used:  cmp.b #2,d0                     ; 1 level, 2 also valid for two players
        bhi.s .index
        cmp.b #5,d2
        bhs.s .index
.next:  dbra d1,.entry
        moveq #0,d0
        bra.s .done
.wrong: moveq #DISK_WRONG,d0
        bra.s .done
.index: moveq #DISK_INDEX,d0
.done:  movem.l (sp)+,d1-d7/a0-a2
        rts
        endif

; Read the titles of the current page that are not known yet.
list_read_page:
        movem.l d0-d7/a0-a3,-(sp)
        bsr list_page_rows
        move.w list_page(a4),d3
        mulu #LIST_ROWS,d3
        subq.w #1,d1
        bmi.s .done
.level: lea level_slots(pc),a0
        move.w d3,d0
        add.w d0,d0
        move.w 0(a0,d0.w),d5
        ifd FILES
        move.w d3,d6
        else
        move.w d5,d6
        endif
        lea level_status(pc),a0
        tst.b 0(a0,d6.w)
        bne.s .next
        bsr list_read_level
.next:  addq.w #1,d3
        dbra d1,.level
.done:  movem.l (sp)+,d0-d7/a0-a3
        rts

; A0: level record. D6: its entry in level_status and level_titles. Record
; the title if the level passes the checks, otherwise mark it damaged.
list_take_level:
        movem.l d0-d1/a0-a2,-(sp)
        lea level_status(pc),a2
        adda.w d6,a2
        move.b #LS_DAMAGED,(a2)
        bsr check_level_record
        tst.l d0
        bne.s .done
        tst.b list_players(a4)
        beq.s .title
        bsr two_player_level
        bne.s .done
.title: lea $7e0(a0),a0
        lea level_titles(pc),a1
        move.w d6,d0
        lsl.w #5,d0
        adda.w d0,a1
        moveq #31,d1
.copy:  move.b (a0)+,(a1)+
        dbra d1,.copy
        move.b #LS_OK,(a2)
.done:  movem.l (sp)+,d0-d1/a0-a2
        rts

        ifd FILES
; List the .lvl files of the directory Levels and sort them by name
; (ignoring case). level_slots holds each name's offset in LIST_NAMES.
list_find_files:
        movem.l d1-d7/a1-a3,-(sp)
        clr.w list_count(a4)
        bsr file_mailbox
        bne .none
        move.l #LIST_NAMES_SIZE-1,d0
        lea levels_dir(pc),a0
        lea install(pc),a1
        adda.l #LIST_NAMES,a1
        move.l a1,d7
        clr.b LIST_NAMES_SIZE-1(a1)
        jsr resload_ListFiles(a2)
        movea.l d7,a0
        moveq #0,d2
        move.l d0,d3
        bra.s .more
.name:  movea.l a0,a1
.end:   tst.b (a1)+
        bne.s .end
        move.l a1,d1
        sub.l a0,d1                     ; length + 1
        cmp.l #6,d1
        blo.s .skip
        cmp.l #NAME_MAX+1,d1            ; longer names are not AmigaDOS ones
        bhi.s .skip
        move.b -5(a1),d0                ; the last four characters, a byte
        lsl.l #8,d0                     ; at a time: the names are packed,
        move.b -4(a1),d0                ; so they may start at an odd
        lsl.l #8,d0                     ; address (a long read there is an
        move.b -3(a1),d0                ; address error on a 68000)
        lsl.l #8,d0
        move.b -2(a1),d0
        or.l #$00202020,d0              ; ".LVL" and ".lvl"
        cmp.l #'.lvl',d0
        bne.s .skip
        bsr list_deleted                ; still listed by the write cache
        bne.s .skip
        bsr list_insert_name
.skip:  movea.l a1,a0
.more:  subq.l #1,d3
        bpl.s .name
        move.w d2,list_count(a4)
        lea level_status(pc),a3         ; no level read yet
        bra.s .status
.unknown:
        clr.b (a3)+
.status:
        dbra d2,.unknown
        tst.b list_players(a4)
        beq.s .sorted
        bsr list_keep_two
.sorted:
        moveq #0,d0
        bra.s .done
.none:  lea txt_list_no_files(pc),a0
        moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a1-a3
        rts

; Two players: read every listed file and keep the levels valid for two
; players (list_take_level), in their order.
list_keep_two:
        movem.l d0-d7/a0-a3,-(sp)
        moveq #0,d3
.read:  cmp.w list_count(a4),d3
        bhs.s .compact
        move.w d3,d6
        bsr list_read_level
        addq.w #1,d3
        bra.s .read
.compact:
        lea level_slots(pc),a0
        lea level_status(pc),a1
        lea level_titles(pc),a2
        moveq #0,d3                     ; source entry
        moveq #0,d4                     ; destination entry
.entry: cmp.w list_count(a4),d3
        bhs.s .done
        cmp.b #LS_OK,0(a1,d3.w)
        bne.s .skip
        move.w d3,d0
        add.w d0,d0
        move.w d4,d1
        add.w d1,d1
        move.w 0(a0,d0.w),0(a0,d1.w)
        move.b #LS_OK,0(a1,d4.w)
        move.w d3,d0
        lsl.w #5,d0
        move.w d4,d1
        lsl.w #5,d1
        moveq #31,d2
.title: move.b 0(a2,d0.w),0(a2,d1.w)
        addq.w #1,d0
        addq.w #1,d1
        dbra d2,.title
        addq.w #1,d4
.skip:  addq.w #1,d3
        bra.s .entry
.done:  move.w d4,list_count(a4)
        movem.l (sp)+,d0-d7/a0-a3
        rts

; A0: a name in LIST_NAMES (at D7), D2: the names kept in level_slots so far,
; in order by name (ignoring case). Insert it at its place; with LEVEL_SLOTS
; names kept, the last one drops out, or this one when it comes after them.
; D2 returns the names kept.
list_insert_name:
        movem.l d0-d1/d3/a1-a2,-(sp)
        lea level_slots(pc),a2
        moveq #0,d3                     ; its place
.find:  cmp.w d2,d3
        bhs.s .found
        move.w d3,d0
        add.w d0,d0
        movea.l d7,a1
        adda.w 0(a2,d0.w),a1
        bsr list_compare
        blo.s .found                    ; before this one
        addq.w #1,d3
        bra.s .find
.found: cmp.w #LEVEL_SLOTS,d3
        bhs.s .done
        cmp.w #LEVEL_SLOTS,d2
        bhs.s .full
        addq.w #1,d2
.full:  move.w d3,d0                    ; the names from its place up one
        add.w d0,d0
        move.w d2,d1
        subq.w #1,d1
        add.w d1,d1
.up:    cmp.w d0,d1
        bls.s .put
        move.w -2(a2,d1.w),0(a2,d1.w)
        subq.w #2,d1
        bra.s .up
.put:   move.l a0,d1
        sub.l d7,d1
        move.w d1,0(a2,d0.w)
.done:  movem.l (sp)+,d0-d1/d3/a1-a2
        rts

; A0, A1: names. Compare them ignoring case; the condition codes are those of
; comparing A0's name with A1's as unsigned values.
list_compare:
        movem.l d0-d1/a0-a1,-(sp)
.char:  move.b (a0)+,d0
        move.b (a1)+,d1
        bsr.s .upper
        exg d0,d1
        bsr.s .upper
        exg d0,d1
        cmp.b d1,d0
        bne.s .done
        tst.b d0
        bne.s .char
.done:  movem.l (sp)+,d0-d1/a0-a1
        rts
.upper: cmp.b #'a',d0
        blo.s .keep
        cmp.b #'z',d0
        bhi.s .keep
        sub.b #$20,d0
.keep:  rts

; D3: list entry, D6: the same. Load its file if it is exactly one record.
list_read_level:
        movem.l d0-d7/a0-a3,-(sp)
        lea level_slots(pc),a0
        add.w d3,d3
        move.w 0(a0,d3.w),d0
        lea install(pc),a0
        adda.l #LIST_NAMES,a0
        adda.w d0,a0
        bsr.s list_name_path
        bsr file_mailbox
        bne.s .damaged
        lea list_path(pc),a0
        jsr resload_GetFileSize(a2)
        cmp.l #LEVEL_SIZE,d0
        bne.s .damaged
        lea list_path(pc),a0
        lea install(pc),a1
        adda.l #DISK_TRACK,a1
        move.l a1,d7
        jsr resload_LoadFile(a2)
        cmp.l #LEVEL_SIZE,d0            ; a failed read keeps the previous file
        bne.s .damaged
        movea.l d7,a0
        bsr list_take_level
        bra.s .done
.damaged:
        lea level_status(pc),a0
        move.b #LS_DAMAGED,0(a0,d6.w)
.done:  movem.l (sp)+,d0-d7/a0-a3
        rts

; A0: file name. Put Levels/ and the name into list_path. A0 returns
; list_path; A1 is changed.
list_name_path:
        move.l a0,-(sp)
        lea list_path(pc),a1
        lea levels_dir(pc),a0
.dir:   move.b (a0)+,(a1)+
        bne.s .dir
        move.b #'/',-1(a1)
        movea.l (sp)+,a0
.name:  move.b (a0)+,(a1)+
        bne.s .name
        lea list_path(pc),a0
        rts

levels_dir:
        dc.b 'Levels',0
        even
        else
; D5: slot, D6: its level_status entry. Read its track; the other slot on
; the track is taken as well when it is listed and not known yet.
list_read_level:
        movem.l d0-d7/a0-a3,-(sp)
        bsr.s read_slot_track
        move.l d0,d7
        and.w #$fffe,d6
        bsr.s .slot
        addq.w #1,d6
        bsr.s .slot
        movem.l (sp)+,d0-d7/a0-a3
        rts
.slot:  lea level_status(pc),a0
        tst.b 0(a0,d6.w)
        bne.s .known
        tst.l d7
        bne.s .bad
        move.w d6,d0
        bsr.s slot_in_track
        bra.s list_take_slot
.bad:   move.b #LS_DAMAGED,0(a0,d6.w)
.known: rts

; A0: a slot of a track read without errors, D6: its level_status entry.
; Record its title when it holds a level that passes the checks, followed
; by zero padding; otherwise mark it damaged.
list_take_slot:
        bsr.s slot_padding
        beq list_take_level
        lea level_status(pc),a0
        move.b #LS_DAMAGED,0(a0,d6.w)
        rts

; A0: a slot in a track. Z set when the bytes after its level record are
; zero, as in every saved slot. D0 is changed.
slot_padding:
        move.l a0,-(sp)
        lea LEVEL_SIZE(a0),a0
        move.w #(LEVEL_SLOT_SIZE-LEVEL_SIZE)/4-1,d0
.pad:   tst.l (a0)+
        dbne d0,.pad
        movea.l (sp)+,a0
        rts

; D5: slot. Read the track that holds it from the level disk in list_drive
; into DISK_TRACK; D0 returns the result of disk_read_track. D1 is changed.
read_slot_track:
        moveq #0,d0
        move.b list_drive(a4),d0
        move.w d5,d1
        lsr.w #1,d1
        addq.w #1,d1
        bra disk_read_track

; D0: slot. A0 returns its place in the track read into DISK_TRACK.
slot_in_track:
        lea install(pc),a0
        adda.l #DISK_TRACK,a0
        btst #0,d0
        beq.s .done
        adda.w #LEVEL_SLOT_SIZE,a0
.done:  rts
        endif

; Load the selected level into custom_record and check it. Return 0, or D0
; nonzero with A0 pointing to a message.
list_load_level:
        movem.l d1-d7/a1-a3,-(sp)
        bsr list_entry
        move.w d0,d3
        ifd FILES
        move.w d3,d6
        bsr list_read_level             ; the file into DISK_TRACK
        lea install(pc),a0
        adda.l #DISK_TRACK,a0
        lea level_status(pc),a1
        cmp.b #LS_OK,0(a1,d6.w)
        bne.s .bad
        else
        lea level_slots(pc),a0
        add.w d0,d0
        move.w 0(a0,d0.w),d5
        bsr read_slot_track
        tst.l d0
        bne.s .bad
        move.w d5,d0
        bsr slot_in_track
        bsr slot_padding
        bne.s .bad
        endif
        bsr check_level_record
        tst.l d0
        bne.s .bad
        tst.b list_players(a4)
        beq.s .take
        bsr two_player_level
        bne.s .bad
.take:  lea custom_record(pc),a1
        move.w #LEVEL_SIZE/4-1,d0
.copy:  move.l (a0)+,(a1)+
        dbra d0,.copy
        moveq #0,d0
        bra.s .done
.bad:   lea txt_list_unplayable(pc),a0
        moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a1-a3
        rts

; A0: 2048-byte level record. Apply the checks of check_record in
; savedisk.py, the game's own limits: parameters, start position, graphics
; style, objects (at most four entrances; the trigger areas of the first 16
; objects inside the attribute grid), terrain, steel areas inside the grid
; and title. The style's object and piece counts and trigger areas come from
; leveldata. Return 0 or DISK_REFUSED; preserve every other register.
check_level_record:
        movem.l d1-d7/a0-a3,-(sp)
        movea.l a0,a2
        cmpi.w #99,(a2)                 ; release rate 0..99
        bhi .bad
        move.w 2(a2),d1                 ; lemmings 1..160
        beq .bad
        cmp.w #160,d1
        bhi .bad
        cmp.w 4(a2),d1                  ; to save at most the lemmings
        blo .bad
        move.w 6(a2),d0                 ; minutes 1..9
        beq .bad
        cmp.w #9,d0
        bhi .bad
        lea 8(a2),a0
        moveq #7,d2
.skill: cmpi.w #99,(a0)+
        bhi .bad
        dbra d2,.skill
        move.w $18(a2),d0               ; start position, steps of 4 up to 1280
        cmp.w #SCROLL_MAX,d0
        bhi .bad
        and.w #3,d0
        bne .bad
        moveq #0,d3
        move.w $1a(a2),d3               ; graphics style
        cmp.w #STYLES-1,d3
        bhi .bad
        ifd STYLE_MASK
        moveq #STYLE_MASK,d0            ; a style the game has
        btst d3,d0
        beq .bad
        endif
        move.w $1c(a2),d4               ; special background
        cmp.w #SPECIALS,d4
        bhi .bad
        tst.w $1e(a2)
        bne .bad
        ; Object and piece counts of the style.
        lea (LEVELDATA).l,a0
        mulu #STYLE_SIZE,d3
        adda.l d3,a0
        lea OBJECT_DESC(a0),a3
        bsr style_objects
        move.w d0,d5
        bsr style_pieces
        move.w d0,d6
        ; Objects: x = 0 is an empty slot; otherwise a known type, flags
        ; $000F, $400F, $800F or $C00F, and x and y in -4096..4095. The
        ; game's entrance table takes every slot of type 1, empty
        ; ones too, so they count towards the four entrances.
        lea $20(a2),a0
        moveq #0,d2                     ; slot
        moveq #0,d7                     ; entrances
.object:
        cmpi.w #1,4(a0)
        bne.s .used
        addq.w #1,d7
.used:  move.w (a0),d0
        beq .next_object
        add.w #4096,d0
        cmp.w #8192,d0
        bhs .bad
        move.w 2(a0),d0
        add.w #4096,d0
        cmp.w #8192,d0
        bhs .bad
        move.w 4(a0),d1
        cmp.w d1,d5
        bls .bad
        move.w 6(a0),d0
        and.w #$3fff,d0
        cmp.w #$000f,d0
        bne .bad
        cmp.w #16,d2
        bhs.s .next_object
        ; The trigger area: x >> 2 + x offset + width <= GRID_WIDTH and
        ; y >> 2 + y offset + height <= GRID_ROWS, with x > 0 and y >= 0.
        mulu #OBJECT_SIZE,d1
        lea $10(a3,d1.w),a1
        move.w (a0),d0
        bmi .bad
        lsr.w #2,d0
        add.w (a1),d0
        add.w 4(a1),d0
        cmp.w #GRID_WIDTH,d0
        bhi .bad
        move.w 2(a0),d0
        bmi .bad
        lsr.w #2,d0
        add.w 2(a1),d0
        add.w 6(a1),d0
        cmp.w #GRID_ROWS,d0
        bhi .bad
.next_object:
        addq.l #8,a0
        addq.w #1,d2
        cmp.w #32,d2
        blo .object
        cmp.w #4,d7
        bhi .bad
        ; Terrain: at most 399 known pieces before the end marker, which the
        ; game needs; none for a special background.
        lea $120(a2),a0
        moveq #0,d2
.piece: cmpi.l #-1,(a0)
        beq.s .end
        cmp.w #399,d2
        bhs .bad
        move.w 2(a0),d0
        and.w #$3f,d0
        cmp.w d6,d0
        bhs .bad
        addq.l #4,a0
        addq.w #1,d2
        bra.s .piece
.end:   tst.w d4
        beq.s .tail
        tst.w d2
        bne .bad
.tail:  lea $760(a2),a1
.rest:  cmpi.l #-1,(a0)+
        bne .bad
        cmpa.l a1,a0
        blo.s .rest
        ; Steel: x + width <= GRID_WIDTH and y + height <= GRID_ROWS-1 cells (rows y + 1
        ; to y + height of the grid).
        moveq #31,d2
.steel: move.w (a0)+,d0
        move.w (a0)+,d1
        move.w d0,d3
        or.w d1,d3
        beq.s .next_steel
        move.w d0,d3
        lsr.w #7,d3
        move.w d1,d4
        rol.w #4,d4
        and.w #15,d4
        add.w d4,d3
        cmp.w #GRID_WIDTH-1,d3
        bhi.s .bad
        and.w #127,d0
        lsr.w #8,d1
        and.w #15,d1
        add.w d1,d0
        cmp.w #GRID_ROWS-2,d0
        bhi.s .bad
.next_steel:
        dbra d2,.steel
        ; Title: printable ASCII, not only spaces.
        lea $7e0(a2),a0
        moveq #31,d2
        moveq #0,d1
.title: move.b (a0)+,d0
        cmp.b #$20,d0
        blo.s .bad
        cmp.b #$7e,d0
        bhi.s .bad
        cmp.b #$20,d0
        sne d3
        or.b d3,d1
        dbra d2,.title
        tst.b d1
        beq.s .bad
        moveq #0,d0
        bra.s .done
.bad:   moveq #DISK_REFUSED,d0
.done:  movem.l (sp)+,d1-d7/a0-a3
        rts

; A0: a level record that passes check_level_record. Return D0 = 0 (Z set)
; when it is valid for two players as the game's two-player mode reads it:
; at least one entrance, the marker (the first slot of type 2, empty or not,
; as $2D80 takes it) and exits (trigger code 1, which only the first 16 slots
; have) of both players.
; A lemming at x, y in an exit counts for the green player when
; |x - 8 - marker x| + |y - 32 - marker y| <= 32 ($6DE0..$6E0E), otherwise
; for the blue player; an exit is the green player's when the nearest point
; of its trigger area is that near. Preserves every other register.
two_player_level:
        movem.l d1-d7/a0-a3,-(sp)
        movea.l a0,a2
        lea $20(a2),a0
        moveq #31,d7
.find:  cmpi.w #2,4(a0)
        beq.s .marker
        addq.l #8,a0
        dbra d7,.find
        bra .no
.marker:
        move.w (a0),d5                  ; the point exits are measured from
        addq.w #8,d5
        move.w 2(a0),d6
        add.w #32,d6
        moveq #0,d0
        move.w $1a(a2),d0
        mulu #STYLE_SIZE,d0
        lea (LEVELDATA+OBJECT_DESC).l,a3 ; object descriptors of the style
        adda.l d0,a3
        moveq #0,d4                     ; bit 0 entrance, 1 blue exit, 2 green exit
        lea $20(a2),a0
        moveq #0,d7
.object:
        move.w (a0),d0
        beq.s .next
        move.w 4(a0),d1
        cmp.w #1,d1
        bne.s .exit
        bset #0,d4
        bra.s .next
.exit:  cmp.w #16,d7
        bhs.s .next
        mulu #OBJECT_SIZE,d1
        lea 0(a3,d1.w),a1
        cmpi.w #1,$18(a1)
        bne.s .next
        ; The trigger area in pixels: (x >> 2 + x offset) * 4, width * 4.
        lsr.w #2,d0
        add.w $10(a1),d0
        move.w $14(a1),d1
        move.w d5,d2
        bsr.s .near
        move.w d0,d3
        move.w 2(a0),d0
        lsr.w #2,d0
        add.w $12(a1),d0
        move.w $16(a1),d1
        move.w d6,d2
        bsr.s .near
        add.w d3,d0
        cmp.w #32,d0
        bgt.s .blue
        bset #2,d4
        bra.s .next
.blue:  bset #1,d4
.next:  addq.l #8,a0
        addq.w #1,d7
        cmp.w #32,d7
        blo.s .object
        cmp.b #7,d4
        bne.s .no
        moveq #0,d0
        bra.s .done
.no:    moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a0-a3
        rts
; D0: first cell, D1: cells, D2: a point. Return D0: the distance from the
; point to the nearest pixel of those cells.
.near:  lsl.w #2,d0
        lsl.w #2,d1
        add.w d0,d1
        subq.w #1,d1                    ; the last pixel
        sub.w d2,d0                     ; first - point
        bgt.s .ok                       ; the point is before the area
        sub.w d2,d1
        neg.w d1                        ; point - last
        moveq #0,d0
        tst.w d1
        ble.s .ok                       ; inside
        move.w d1,d0
.ok:    rts

; Reflected IEEE CRC-32, D0 byte count, A0 input. D1=-1 hashes all bytes;
; otherwise D1 is a four-byte field offset treated as zero without writing
; to the input. Returns D0, clobbers D1-D5/A0, preserves D6-D7/A1-A6.
crc32:
        moveq #-1,d2
        moveq #0,d3
.byte:  tst.l d0
        beq.s .done
        moveq #0,d4
        move.b (a0)+,d4
        cmp.l #-1,d1
        beq.s .mix
        move.l d3,d5
        sub.l d1,d5
        cmp.l #4,d5
        bhs.s .mix
        moveq #0,d4
.mix:   eor.b d4,d2
        moveq #7,d5
.bit:   lsr.l #1,d2
        bcc.s .next
        eori.l #$edb88320,d2
.next:  dbra d5,.bit
        addq.l #1,d3
        subq.l #1,d0
        bra.s .byte
.done:  move.l d2,d0
        not.l d0
        rts

        ifnd FILES
; The fixed first 32 bytes of a level disk's track 0.
level_disk_header:
        dc.b 'LEMSAVE',0
        dc.w 2,64
        dc.l $00020001
        dc.w 512,11,160,LEVEL_SLOT_SIZE,LEVEL_SLOTS,2048,2,LEVEL_SLOTS*2
        endif

; Text entries for the game's text routine: column, row, text, NUL; $FF ends
; a list. The game's font has no ':'.
txt_list_head:          dc.b 13,0,'Custom levels',0,$ff
txt_list_head_two:      dc.b 8,0,'Two-player custom levels',0,$ff
txt_list_back:          dc.b 5,12,'Right mouse button to go back',0,$ff
txt_list_help:          dc.b 3,12,'Click plays, E edits, Del deletes',0,$ff
txt_list_help_two:      dc.b 5,12,'Click plays, right button back',0,$ff
txt_new_head:           dc.b 11,0,'New level style',0,$ff
txt_new_help:           dc.b 2,12,'Click a style  Right button back',0,$ff
txt_list_page:          dc.b '< Page ',0
txt_list_of:            dc.b ' of ',0
txt_list_damaged:       dc.b '(damaged level)',0
txt_list_unplayable:    dc.b 'This level cannot be read or played.',0
txt_list_again:         dc.b 'Click to look for the levels again.',0
        ifd RELOCATED
txt_list_searching:     dc.b 'Reading the levels...',0
        else
txt_list_searching:     dc.b 'Looking for the level disk...',0
        endif
txt_list_no_two:        dc.b 'There are no levels for two players.',0
        ifd FILES
txt_list_no_files:
txt_list_empty:         dc.b 'There are no .lvl files in the',$0a
                        dc.b 'directory Levels.',0
        else
txt_list_empty:         dc.b 'There are no levels on the level disk.',0
txt_list_insert:        dc.b 'Insert a level disk into a drive',$0a
                        dc.b 'and click the left mouse button.',0
; The game's font has no ':', so the drive is named without it.
txt_list_disk2:         dc.b 'Insert Lemmings disk 2 into DF'
txt_list_disk2_drive:   dc.b '0',$0a
                        dc.b 'and click the left mouse button.',0
txt_list_searching_disk2:
                        dc.b 'Looking for Lemmings disk 2...',0
        endif
        even
