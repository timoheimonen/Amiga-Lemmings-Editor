; Lemmings In-Game Level Editor V2.3.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The game interface of Holiday Lemmings 1994: the addresses of the game's
; routines, data and hook sites that the editor uses, for the game version
; patch.py identifies by SHA-256.
;
; The game is an AmigaDOS executable whose hunks the system loads anywhere.
; The editor becomes two more hunks of it: its code and storage, and its chip
; memory. Addresses are given relative to the hunk they lie in: H1 is the
; game's chip data hunk, H2 its code hunk, H3 its chip code and data hunk, H5
; the editor's chip hunk. patch.py assembles the editor with several values of
; these bases and turns every address that follows them into a relocation.

RELOCATED       equ 1                   ; the editor is a hunk of the program
FILES           equ 1                   ; custom levels are .lvl files

; ---------------------------------------------------------------------------
; Global variables, relative to A5 (H2+$77DE)

G_RAW_KEY       equ $06                 ; byte: last raw key code
G_LEVEL_ENDING  equ $09                 ; byte: the level ends (Esc, time out)
G_SHUTDOWN      equ $0b                 ; byte: set while a level shuts down
G_ALL_OUT       equ $0d                 ; byte: every lemming is out
G_PLAYING       equ $0f                 ; byte: cleared while a level shuts down
G_TWO_PLAYERS   equ $10                 ; byte: two-player mode, never set
G_TEXT_MODE     equ $12                 ; byte: the text screen is shown
G_RESULT_SHOWN  equ $13                 ; byte: cleared on a successful result
G_PAUSE         equ $19                 ; byte: the game is paused
G_TRIES         equ $1b                 ; byte: failed tries, part of the access code
G_PANEL         equ $1c                 ; byte: the loaded skill panel
G_MUSIC         equ $1d                 ; byte: the level's tune plays (suspend restarts it)
G_FRAMES        equ $24                 ; word: frames since the last step
G_LEVEL         equ $28                 ; word: level number
G_BANK          equ $52                 ; word: record number in the bank cache
G_FADE          equ $60                 ; word: steps left of the play view's fade-in
G_TEXT_STRIDE   equ $64                 ; word: text screen bytes per row
G_TEXT_HEIGHT   equ $66                 ; word: text screen rows
G_RATING        equ $7e                 ; word: rating
G_DOS           equ $8e                 ; long: dos.library
G_VIEW_BACK     equ $c2                 ; long: viewport buffer being drawn
G_VIEW_FRONT    equ $c6                 ; long: viewport buffer being shown
G_STARTUP       equ $d2                 ; long: frames since the level started
G_TEXT_DEST     equ $d6                 ; long: text screen bitmap
G_STYLE         equ $ee                 ; long: style data of the level
G_WINDOW_PTR    equ $f2                 ; long: address of the process's pr_WindowPtr

; ---------------------------------------------------------------------------
; Data

MOUSE           equ H2+$775e            ; +4 view scroll, +6 x, +8 y
VIEW_SCROLL     equ MOUSE+4
MOUSE_X         equ MOUSE+6
MOUSE_Y         equ MOUSE+8
LEVEL_RECORD    equ H2+$9b38            ; the level being played, 2048 bytes
OBJECTS         equ LEVEL_RECORD+$20
TERRAIN         equ H1+$13a00           ; 1632 x 168 pixels, four planes
TERRAIN_PLANE   equ $85e0
GROUND_BASE     equ 0                   ; style piece offsets are relative to Ground
OBJECT_BASE     equ H1+$357e0           ; object frame offsets are relative to Objects
VIEW_PLANE      equ $2100               ; viewport plane: 44 bytes x 192 rows
BLIT_HEIGHT     equ H2+$78f2            ; word: rows of BLIT's surface (192), where it clips;
                                        ; the second buffer's plane 3 from row 176 is the panel
GAME_ROWS       equ H2+$7908            ; the game's A4: row y at y * 204
LEVELDATA       equ H2+$17a7a           ; leveldata: $590 bytes per style
STYLE_SIZE      equ $590
STYLES          equ 3                   ; graphics styles 0 and 2 (Ground1, Ground3)
STYLE_MASK      equ %101
SPECIALS        equ 0                   ; no special backgrounds
GRID_ROWS       equ 44                  ; rows of the attribute grid
SKILL_SPRITE    equ H3+$8c94            ; skill selection sprite
KEY_ASCII       equ H2+$7a78            ; raw key to ASCII, without shift
KEY_ASCII_SHIFT equ H2+$7af8            ; and with shift
TEXT_SCREEN     equ H1                  ; text screen bitmap
TITLE_PLANE     equ $4100               ; the title screen: 640 x 208, four planes
SIGNS           equ H1+$22ada           ; the rating signs, 128 x 69, $1140 bytes each
COPPER_DIWSTOP  equ H3+$2a              ; copper value word of DIWSTOP
COPPER_END      equ H3+$1a4             ; end of the copper list, 12 bytes
VIEW_PALETTE    equ H3+$4a              ; copper value word of COLOR00
COPPER_ROWS     equ H3+$278             ; 13 groups of 16 colour moves and a wait
PALETTES        equ H2+$67da            ; the text palettes, 32 bytes each
FADE_BLACK      equ H2+$66e0            ; palette numbers: every row black
FADE_RESULT     equ H2+$665e            ; palette numbers of the result screen
BRIEF_LEVEL     equ H2+$6ad6            ; briefing: "Level 00", 8 characters
BRIEF_TITLE     equ H2+$6ae1            ; the title, 32 characters
BRIEF_RATING    equ H2+$6b5e            ; the rating name, 8 characters

; ---------------------------------------------------------------------------
; Routines

TAKE_OVER       equ H2+$0000            ; the game takes over the hardware
RESTORE_SYSTEM  equ H2+$00c4            ; and gives it back to the system
DRAW_TEXT       equ H2+$1276            ; A0: text entries
NUMBER_DIGITS   equ H2+$14cc            ; D0: number, returns four ASCII digits
SWAP_BUFFERS    equ H2+$1502
WAIT_CLICK      equ H2+$154a
WAIT_FRAME      equ H2+$15de
FADE            equ H2+$165e            ; A0: palette numbers of the rows
FADE_STEP       equ H2+$15f6            ; one step of the play view's fade
PLAY_STOP       equ H2+$175e            ; end of play: display and interrupts
TITLE_PREPARE   equ H2+$1792
TEXT_BACKGROUND equ H2+$18ca            ; clears the text screen
PANEL_REFRESH   equ H2+$1c2e
OBJECT_GRID     equ H2+$2078            ; trigger areas into the grid (game A4)
STEEL_GRID      equ H2+$2100            ; clears the grid, steel areas (game A4)
LOAD_LEVEL      equ H2+$21f6            ; level G_LEVEL into LEVEL_RECORD
SELECT_STYLE    equ H2+$236a
INIT_SIMULATION equ H2+$2386
BRIEF_TEXTS     equ H2+$269e
LOAD_ICONS      equ H2+$2752
LOAD_FILE       equ H2+$2df8            ; A0: name, A1: destination, D1 = 0
SETUP_BLIT      equ H2+$6002            ; D0/D1: width and height of the surface
PANEL_ONE       equ H2+$30c2
PRESS_BUTTON    equ H2+$328e            ; "Press mouse button to continue"
UNPACK          equ H2+$3498            ; A0: packed, A1: output, D0: size
MINIMAP_REFRESH equ H2+$5b68
MINIMAP_COLUMN  equ H2+$5b8c
CLEAR_GUARDS    equ H2+$5c1a            ; clears the terrain's collision guard rows
BRIEF_PREVIEW   equ H2+$5c40
BLIT            equ H2+$603a
SOUND_CONTROL   equ H2+$a534            ; D0 = -1 stops the music
RESULT_COMMENT  equ H2+$06ea

; ---------------------------------------------------------------------------
; Main flow and hooks. A hook replaces whole instructions with a jump and
; continues at the address after them; patch.py writes the jumps.

HOOK_START      equ H2+$0344            ; BSR TAKE_OVER / LEA GAME_ROWS,A4
START_DONE      equ H2+$034e
TITLE_LOOP      equ H2+$03a8            ; back to the title screen
ENTER_LEVEL     equ H2+$03be            ; level graphics, briefing and play
FRAME_WAIT      equ H2+$0474            ; play loop: wait for the next frame
HOOK_FRAME      equ H2+$0482            ; BSR SWAP_BUFFERS / CLR.W G_FRAMES(A5)
FRAME_STEP      equ H2+$048a
HOOK_ACTIONS    equ H2+$04ae            ; BSR PLAY_MOUSE / BSR PLAY_KEYS
PLAY_MOUSE      equ H2+$0896
PLAY_KEYS       equ H2+$1162
HOOK_OVERLAY    equ H2+$04b6            ; BSR PANEL_REFRESH / BSR MINIMAP_COLUMN
OVERLAY_DONE    equ H2+$04be
HOOK_KEYBOARD   equ H2+$13b2            ; MOVE.B D0,G_RAW_KEY(A5) / CIA handshake
KEYBOARD_DONE   equ H2+$13be
ESC_ACTION      equ H2+$122a            ; the game's Esc key action
HOOK_CAPTURE    equ H2+$22d0            ; BSR SELECT_STYLE / BSR INIT_SIMULATION
CAPTURE_DONE    equ H2+$22d8
HOOK_INJECT     equ H2+$2254            ; LEA LEVEL_RECORD,A0 / MOVE.W $1A(A0),D0
INJECT_DONE     equ H2+$225e
HOOK_BRIEFING   equ H2+$3068            ; BSR BRIEF_TEXTS / BSR BRIEF_PREVIEW
HOOK_BRIEF_WAIT equ H2+$30b4            ; BSR WAIT_CLICK / LEA FADE_BLACK,A0
BRIEF_WAIT_DONE equ H2+$30bc
HOOK_ENDED      equ H2+$053a            ; after the level: CLR.B G_MUSIC(A5) / LEA texts,A1
ENDED_DONE      equ H2+$0544
ENDED_TEXTS     equ H2+$6bc9
HOOK_WON        equ H2+$0590            ; enough saved: CLR.B G_RESULT_SHOWN(A5)
WON_DONE        equ H2+$0598
HOOK_QUIT       equ H2+$06d8            ; too few, right button: back to the menu
QUIT_DONE       equ H2+$06e2

; Title screen
HOOK_SIGN       equ H2+$27a2            ; the rating sign: its surface
SIGN_DONE       equ H2+$27ae
HOOK_PLAY       equ H2+$301e            ; PLAY: TST.B G_PANEL(A5) / BEQ.W
PLAY_PANEL      equ H2+$3026
PLAY_LOAD       equ H2+$302a
HOOK_NEW        equ H2+$2ff2            ; NEW LEVEL: CMPI.W #$BC,D0 / BLE.W
NEW_GAME        equ H2+$2ace            ; the game's own access code entry
NEW_MISSED      equ H2+$2ffa
HOOK_RATING     equ H2+$3174            ; the rating sign clicked: MOVE.W G_RATING / ADDQ
RATING_NEXT     equ H2+$317a
RATING_SHOWN    equ H2+$318e
RATINGS         equ 4                   ; Frost, Hail, Flurry, Blizzard

; The instructions the hook at HOOK_ENDED replaced, then back to the game.
RESUME_ENDED    macro
        clr.b G_MUSIC(a5)
        lea (ENDED_TEXTS).l,a1
        jmp ENDED_DONE
        endm

; The names of the graphics styles in the list of a new level.
STYLE_NAMES     macro
        dc.b 'Brick',0,'Snow',0
        endm

; Keep the interrupts away while the editor changes what they share with it.
; The game runs in user mode, so the master enable bit of INTENA does it;
; INTS_ON restores it as it was. The condition codes change.
INTS_OFF        macro
        move.w $dff01c,-(sp)
        move.w #$4000,$dff09a
        endm
INTS_ON         macro
        or.w #$8000,(sp)
        and.w #$c000,(sp)
        move.w (sp)+,$dff09a
        endm
