; Lemmings In-Game Level Editor V2.3.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Title screen: a fifth rating, CUSTOM, after MAYHEM. The up arrow on the
; rating sign selects it and the down arrow returns to MAYHEM. The game's own
; rating (G_RATING) stays at MAYHEM meanwhile; only the sign and the buttons
; change. In CUSTOM, "1 Player" opens the custom level list, "2 Player" the
; list of the levels for two players, and "New Level" starts a new custom
; level in the editor (levels.s).
;
; The CUSTOM sign is built on the title screen from the FUN sign: the lettering
; and the difficulty slope are replaced by the board colour and the editor's
; own lettering, pink with a dark outline like the game's signs.
TITLE_ROW       equ 80                ; the title screen (TEXT_SCREEN)
SIGN_BYTES      equ 12                ; 96 pixels
SIGN_ROWS       equ 30
SIGN_Y          equ 140
SIGN_X_BYTE     equ 64                ; x = 512
LETTER_ROWS     equ 27                ; rows of the sign replaced by lettering
LETTER_TOP      equ 6                 ; first row of the lettering masks
LETTER_HEIGHT   equ 14

; Replaces MOVE.W #$280,D0 / MOVE.W #$D0,D1 at the start of the rating sign
; drawing (HOOK_SIGN), which uses D0-D5/A0/A1; so does this one.
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
        movem.l d6-d7/a2-a3,-(sp)
        lea (SIGNS).l,a0                ; FUN
        lea (TEXT_SCREEN+SIGN_Y*TITLE_ROW+SIGN_X_BYTE).l,a1
        moveq #3,d7
.plane: movea.l a1,a2
        moveq #SIGN_ROWS-1,d6
.copy:  move.l (a0)+,(a2)+
        move.l (a0)+,(a2)+
        move.l (a0)+,(a2)+
        lea TITLE_ROW-SIGN_BYTES(a2),a2
        dbra d6,.copy
        lea TITLE_PLANE(a1),a1
        dbra d7,.plane
        ; Bytes 2..9 (x 16..79) of the first rows: plane 0 clear, board
        ; colour 2 (plane 1) outside the letters, colour 12 (planes 2 and 3)
        ; in them, colour 0 on the outline.
        lea (TEXT_SCREEN+SIGN_Y*TITLE_ROW+SIGN_X_BYTE+2).l,a1
        lea TITLE_PLANE(a1),a2
        lea TITLE_PLANE(a2),a3
        moveq #0,d6
.row:   moveq #0,d0
        moveq #0,d1
        moveq #0,d2
        moveq #0,d3
        move.w d6,d4
        subq.w #LETTER_TOP,d4
        bcs.s .put
        cmp.w #LETTER_HEIGHT,d4
        bhs.s .put
        lsl.w #3,d4
        lea custom_fill(pc),a0
        move.l 0(a0,d4.w),d0
        move.l 4(a0,d4.w),d1
        lea custom_outline(pc),a0
        move.l 0(a0,d4.w),d2
        move.l 4(a0,d4.w),d3
.put:   or.l d0,d2
        or.l d1,d3
        not.l d2
        not.l d3
        clr.l (a1)
        clr.l 4(a1)
        move.l d2,(a2)
        move.l d3,4(a2)
        move.l d0,(a3)
        move.l d1,4(a3)
        move.l d0,TITLE_PLANE(a3)
        move.l d1,TITLE_PLANE+4(a3)
        lea TITLE_ROW(a1),a1
        lea TITLE_ROW(a2),a2
        lea TITLE_ROW(a3),a3
        addq.w #1,d6
        cmp.w #LETTER_ROWS,d6
        blo.s .row
        movem.l (sp)+,d6-d7/a2-a3
        rts

; Replaces HOOK_UP in the up arrow: at MAYHEM (RATINGS-1), select CUSTOM.
title_up:
        cmp.w #RATINGS-1,d0
        beq.s .last
        jmp UP_NEXT
.last:  move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        bne.s .done
        st custom_tier(a4)
        jsr HOOK_SIGN
.done:  movea.l (sp)+,a4
        jmp TITLE_IDLE

; Replaces HOOK_DOWN in the down arrow: from CUSTOM, back to MAYHEM.
title_down:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        beq.s .rating
        clr.b custom_tier(a4)
        movea.l (sp)+,a4
        jsr HOOK_SIGN
        jmp TITLE_IDLE
.rating:
        movea.l (sp)+,a4
        move.w G_RATING(a5),d0
        bne.s .lower
        jmp TITLE_IDLE
.lower: jmp DOWN_NEXT

; Replaces HOOK_CLICK, where a click on the title screen is dispatched.
; Continue at CLICK_DONE with A3 and D0 as the game sets them.
title_click:
        lea (MOUSE).l,a3
        move.w 6(a3),d0
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        movea.l (sp)+,a4
        bne.s .custom
.game:  jmp CLICK_DONE
.custom:
        move.w 8(a3),d1
        subq.w #8,d1
        cmp.w #$87,d1
        blt.s .game
        cmp.w #$ac,d1
        bgt.s .game
        move.w d0,d1
        subq.w #8,d1
        cmp.w #8,d1
        blt.s .game
        cmp.w #$bc,d1
        bgt.s .game
        cmp.w #$3c,d1
        ble level_list                ; 1 Player: the custom levels
        cmp.w #$88,d1
        bge level_new                 ; New Level: a new custom level
        cmp.w #$48,d1
        blt.s .none
        cmp.w #$7b,d1
        ble level_list_two            ; 2 Player: the two-player levels
.none:  jmp TITLE_IDLE                ; between the buttons

; The editor's CUSTOM lettering for x 16..79 of sign rows 6..19.
custom_fill:
        dc.l %00000000000000000000000000000000,%00000000000000000000000000000000
        dc.l %00001111110001110011100011111100,%01111111100011111100011000011000
        dc.l %00011111111001110011100111111110,%01111111100111111110011100111000
        dc.l %00011100011001110011100111000110,%00011110000111001110011111111000
        dc.l %00011100000001110011100111000000,%00011110000111001110011111111000
        dc.l %00011100000001110011100111110000,%00011110000111001110011011011000
        dc.l %00011100000001110011100011111100,%00011110000111001110011011011000
        dc.l %00011100000001110011100000111110,%00011110000111001110011000011000
        dc.l %00011100000001110011100000001110,%00011110000111001110011000011000
        dc.l %00011100000001110011100000001110,%00011110000111001110011000011000
        dc.l %00011100011001110011100110001110,%00011110000111001110011000011000
        dc.l %00011111111001111111100111111110,%00011110000111111110011000011000
        dc.l %00001111110000111111000011111100,%00011110000011111100011000011000
        dc.l %00000000000000000000000000000000,%00000000000000000000000000000000
custom_outline:
        dc.l %00011111111011111111110111111110,%11111111110111111110111100111100
        dc.l %00110000001110001100011100000011,%10000000011100000011100111100100
        dc.l %00100000000110001100011000000001,%10000000011000000001100011000100
        dc.l %00100011100110001100011000111001,%11100001111000110001100000000100
        dc.l %00100010111110001100011000111111,%00100001001000110001100000000100
        dc.l %00100010000010001100011000001110,%00100001001000110001100100100100
        dc.l %00100010000010001100011100000011,%00100001001000110001100100100100
        dc.l %00100010000010001100010111000001,%00100001001000110001100111100100
        dc.l %00100010000010001100010001110001,%00100001001000110001100100100100
        dc.l %00100010111110001100011111010001,%00100001001000110001100100100100
        dc.l %00100011100110001100011001110001,%00100001001000110001100100100100
        dc.l %00100000000110000000011000000001,%00100001001000000001100100100100
        dc.l %00110000001111000000111100000011,%00100001001100000011100100100100
        dc.l %00011111111001111111100111111110,%00111111000111111110111100111100
