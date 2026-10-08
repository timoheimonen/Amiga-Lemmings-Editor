; Lemmings In-Game Level Editor V2.3.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Holiday Lemmings 1994: the editor's start-up and the title screen.
;
; patch.py writes the jumps of all hooks into the game's code hunk. The first
; one, at the game's hardware take-over, installs the editor while the system
; still runs.
;
; Title screen: a fifth rating, CUSTOM, after BLIZZARD. A click on the rating
; sign goes through FROST, HAIL, FLURRY, BLIZZARD, CUSTOM and back to FROST.
; The game's own rating (G_RATING) stays at BLIZZARD meanwhile; only the sign
; and the buttons change. In CUSTOM, PLAY opens the custom level list and NEW
; LEVEL starts a new custom level in the editor (levels.s).
;
; The CUSTOM sign is FROST's with the editor's own lettering, white with a
; dark outline like the game's signs.

SIGN_X_BYTE     equ 64                  ; the sign at x 512, y 123 of the
SIGN_Y          equ 123                 ; 640 x 208 title screen
TITLE_ROW       equ 80
LETTER_ROW      equ 34                  ; the lettering: 14 rows from row 34,
LETTER_BYTE     equ 4                   ; 11 bytes from byte 4 of the sign
LETTER_ROWS     equ 14
LETTER_BYTES    equ 11

; Replaces BSR TAKE_OVER / LEA GAME_ROWS,A4 in the game's start-up: install
; the editor, then take over the hardware as the game does.
holiday_start:
        bsr install
        jsr TAKE_OVER
        lea (GAME_ROWS).l,a4
        jmp START_DONE

; Replaces MOVE.W #$280,D0 / MOVE.W #$D0,D1 at the start of the rating sign
; drawing, which uses D0-D5/A0/A1; so does this one.
title_sign:
        move.w #$280,d0
        move.w #$d0,d1
        jsr SETUP_BLIT
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        movea.l (sp)+,a4
        bne.s .custom
        jmp SIGN_DONE
.custom:
        lea (TEXT_SCREEN).l,a0
        lea (SIGNS).l,a1                ; FROST
        move.w #SIGN_X_BYTE*8,d0
        moveq #SIGN_Y,d1
        move.w #128,d2
        moveq #69,d3
        moveq #4,d4
        moveq #0,d5
        jsr BLIT
        ; The lettering: fill colour 15, outline colour 0, elsewhere the
        ; board colour 4 (plane 2).
        movem.l d6-d7/a2-a3,-(sp)
        lea (TEXT_SCREEN+(SIGN_Y+LETTER_ROW)*TITLE_ROW+SIGN_X_BYTE+LETTER_BYTE).l,a0
        lea custom_fill(pc),a1
        lea custom_outline(pc),a2
        move.l #TITLE_PLANE,d5
        moveq #LETTER_ROWS-1,d7
.row:   moveq #LETTER_BYTES-1,d6
.byte:  move.b (a1)+,d0
        move.b (a2)+,d1
        not.b d1
        movea.l a0,a3
        move.b d0,(a3)
        adda.l d5,a3
        move.b d0,(a3)
        adda.l d5,a3
        move.b d1,(a3)
        adda.l d5,a3
        move.b d0,(a3)
        addq.l #1,a0
        dbra d6,.byte
        lea TITLE_ROW-LETTER_BYTES(a0),a0
        dbra d7,.row
        movem.l (sp)+,d6-d7/a2-a3
        rts

; Replaces MOVE.W G_RATING(A5),D0 / ADDQ.W #1,D0 where a click on the sign
; selects the next rating: after BLIZZARD comes CUSTOM, after CUSTOM FROST.
title_rating:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        bne.s .first
        cmpi.w #RATINGS-1,G_RATING(a5)
        bne.s .game
        st custom_tier(a4)
        movea.l (sp)+,a4
        bsr title_sign
        jmp RATING_SHOWN
.first: clr.b custom_tier(a4)
        movea.l (sp)+,a4
        moveq #0,d0
        jmp RATING_NEXT
.game:  movea.l (sp)+,a4
        move.w G_RATING(a5),d0
        addq.w #1,d0
        jmp RATING_NEXT

; Replaces TST.B G_PANEL(A5) / BEQ.W in PLAY: in CUSTOM, the custom levels.
title_play:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        movea.l (sp)+,a4
        bne level_list
        tst.b G_PANEL(a5)
        beq.s .load
        jmp PLAY_PANEL
.load:  jmp PLAY_LOAD

; Replaces CMPI.W #$BC,D0 / BLE.W in NEW LEVEL: in CUSTOM, a new custom level.
title_new:
        cmpi.w #$bc,d0
        bgt.s .missed
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        movea.l (sp)+,a4
        bne level_new
        jmp NEW_GAME
.missed:
        jmp NEW_MISSED

; The editor's CUSTOM lettering, 88 x 14 pixels.
custom_fill:
        dc.b $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        dc.b $03,$f8,$70,$70,$7f,$87,$ff,$03,$e0,$70,$70
        dc.b $07,$fc,$70,$70,$ff,$c7,$ff,$0f,$f8,$78,$f0
        dc.b $0f,$1c,$70,$71,$e1,$80,$70,$1e,$3c,$7d,$f0
        dc.b $1e,$00,$70,$71,$e0,$00,$70,$1c,$1c,$77,$70
        dc.b $1c,$00,$70,$70,$fe,$00,$70,$1c,$1c,$72,$70
        dc.b $1c,$00,$70,$70,$7f,$80,$70,$1c,$1c,$70,$70
        dc.b $1c,$00,$70,$70,$07,$c0,$70,$1c,$1c,$70,$70
        dc.b $1c,$00,$70,$70,$01,$c0,$70,$1c,$1c,$70,$70
        dc.b $1e,$00,$70,$70,$01,$c0,$70,$1c,$1c,$70,$70
        dc.b $0f,$1c,$78,$f0,$c3,$c0,$70,$1e,$3c,$70,$70
        dc.b $07,$fc,$3f,$e1,$ff,$80,$70,$0f,$f8,$70,$70
        dc.b $03,$f8,$1f,$c0,$ff,$00,$70,$03,$e0,$70,$70
        dc.b $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
custom_outline:
        dc.b $07,$fc,$f8,$f8,$ff,$cf,$ff,$87,$f0,$f8,$f8
        dc.b $0c,$06,$88,$89,$80,$68,$00,$9c,$1c,$8d,$88
        dc.b $18,$02,$88,$8b,$00,$28,$00,$b0,$06,$87,$08
        dc.b $30,$e2,$88,$8a,$1e,$6f,$8f,$a1,$c2,$82,$08
        dc.b $21,$be,$88,$8a,$1f,$c0,$88,$23,$62,$88,$88
        dc.b $23,$00,$88,$8b,$01,$c0,$88,$22,$22,$8d,$88
        dc.b $22,$00,$88,$89,$80,$60,$88,$22,$22,$8f,$88
        dc.b $22,$00,$88,$88,$f8,$20,$88,$22,$22,$88,$88
        dc.b $23,$00,$88,$88,$0e,$20,$88,$22,$22,$88,$88
        dc.b $21,$be,$8d,$89,$e6,$20,$88,$23,$62,$88,$88
        dc.b $30,$e2,$87,$0b,$3c,$20,$88,$21,$c2,$88,$88
        dc.b $18,$02,$c0,$1a,$00,$60,$88,$30,$06,$88,$88
        dc.b $0c,$06,$60,$33,$00,$c0,$88,$1c,$1c,$88,$88
        dc.b $07,$fc,$3f,$e1,$ff,$80,$f8,$07,$f0,$f8,$f8
        even
