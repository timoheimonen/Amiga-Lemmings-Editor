; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Title screen: a fifth rating, CUSTOM, after MAYHEM. The up arrow on the
; rating sign selects it and the down arrow returns to MAYHEM. The game's own
; rating ($AA(A5)) stays at MAYHEM meanwhile; only the sign and the buttons
; change. In CUSTOM, "1 Player" opens the custom level list, "2 Player" the
; list of the levels for two players, and "New Level" starts a new custom
; level in the editor (levels.s).
;
; The CUSTOM sign is built on the title screen from the FUN sign: the lettering
; and the difficulty slope are replaced by the board colour and the editor's
; own lettering, pink with a dark outline like the game's signs.
TITLE_BITMAP    equ $23680            ; 640x208 title screen bitmap, 4 planes
TITLE_PLANE     equ $4100
TITLE_ROW       equ 80
SIGN_SOURCE     equ $4690a            ; FUN, the first rating sign (file Icons)
SIGN_BYTES      equ 12                ; 96 pixels
SIGN_ROWS       equ 30
SIGN_Y          equ 140
SIGN_X_BYTE     equ 64                ; x = 512
LETTER_ROWS     equ 27                ; rows of the sign replaced by lettering
LETTER_TOP      equ 6                 ; first row of the lettering masks
LETTER_HEIGHT   equ 14

; Hook the rating sign, both rating arrows and the button dispatch, and the
; places where a custom level is started and ended (levels.s).
title_install:
        lea custom_inject(pc),a0
        lea (HOOK_INJECT).l,a1
        bsr .jump
        move.w #$4e71,2(a1)             ; ten bytes replaced
        lea custom_won(pc),a0
        lea (HOOK_WON).l,a1
        bsr .jump
        lea custom_quit(pc),a0
        lea (HOOK_QUIT).l,a1
        bsr .jump
        move.w #$4e71,2(a1)
        lea custom_ended(pc),a0
        lea (HOOK_ENDED).l,a1
        bsr .jump
        lea custom_match(pc),a0
        lea (HOOK_MATCH).l,a1
        bsr .jump
        lea custom_match_end(pc),a0
        lea (HOOK_MATCH_END).l,a1
        bsr .jump
        lea briefing_wait(pc),a0
        lea (HOOK_BRIEF_WAIT).l,a1
        bsr .jump
        lea custom_brief(pc),a0
        lea (HOOK_BRIEFING).l,a1
        move.w #$4eb9,(a1)+             ; jsr, returning to $34B0
        move.l a0,(a1)+
        move.w #$4e71,(a1)
        lea title_sign(pc),a0
        lea ($2cca).l,a1
        bsr .jump
        lea title_up(pc),a0
        lea ($35ca).l,a1
        bsr .jump
        lea title_down(pc),a0
        lea ($35fc).l,a1
        bsr .jump
        lea title_click(pc),a0
        lea ($33c0).l,a1
; A0: target, A1: game address. Write a jump and a NOP (8 bytes); A1 returns
; pointing to the NOP.
.jump:  move.w #$4ef9,(a1)+
        move.l a0,(a1)+
        move.w #$4e71,(a1)
        rts

; Replaces $2CCA..$2CD1, the start of the rating sign drawing. The game's
; routine uses D0-D5/A0/A1; so does this one.
title_sign:
        move.w #$280,d0
        move.w #$d0,d1
        jsr $7014
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        movea.l (sp)+,a4
        bne.s .custom
        jmp $2cd6
.custom:
        movem.l d6-d7/a2-a3,-(sp)
        lea (SIGN_SOURCE).l,a0
        lea (TITLE_BITMAP+SIGN_Y*TITLE_ROW+SIGN_X_BYTE).l,a1
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
        lea (TITLE_BITMAP+SIGN_Y*TITLE_ROW+SIGN_X_BYTE+2).l,a1
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

; Replaces $35CA..$35D1 in the up arrow: at MAYHEM, select CUSTOM.
title_up:
        cmp.w #3,d0
        beq.s .last
        jmp $35d2
.last:  move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        bne.s .done
        st custom_tier(a4)
        jsr $2cca
.done:  movea.l (sp)+,a4
        jmp $33ae

; Replaces $35FC..$3603 in the down arrow: from CUSTOM, back to MAYHEM.
title_down:
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        beq.s .rating
        clr.b custom_tier(a4)
        movea.l (sp)+,a4
        jsr $2cca
        jmp $33ae
.rating:
        movea.l (sp)+,a4
        move.w G_RATING(a5),d0
        bne.s .lower
        jmp $33ae
.lower: jmp $3604

; Replaces $33C0..$33C7, where a click on the title screen is dispatched.
; Continue at $33C8 with A3 and D0 as the game sets them.
title_click:
        lea (MOUSE).l,a3
        move.w 6(a3),d0
        move.l a4,-(sp)
        lea state(pc),a4
        tst.b custom_tier(a4)
        movea.l (sp)+,a4
        bne.s .custom
.game:  jmp $33c8
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
.none:  jmp $33ae                     ; between the buttons

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
