; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The game interface of Lemmings: the addresses of the game's routines, data
; and hook sites that the editor uses, for the game version patch.py
; identifies by SHA-256. The game's main program is loaded at $400.

; ---------------------------------------------------------------------------
; Global variables, relative to A5

G_RAW_KEY       equ $26                 ; byte: last raw key code
G_LEVEL_ENDING  equ $29                 ; byte: the level ends (Esc, time out)
G_SHUTDOWN      equ $2b                 ; byte: set while a level shuts down
G_ALL_OUT       equ $2d                 ; byte: every lemming is out
G_PLAYING       equ $2f                 ; byte: cleared while a level shuts down
G_TWO_PLAYERS   equ $30                 ; byte: two-player mode
G_TEXT_MODE     equ $32                 ; byte: the text screen is shown
G_RESULT_SHOWN  equ $33                 ; byte: cleared on a successful result
G_TITLE_FLAG    equ $38                 ; byte: cleared after a two-player match
G_PAUSE         equ $39                 ; byte: the game is paused
G_PANEL         equ $3c                 ; byte: the loaded skill panel
G_FRAMES        equ $3e                 ; word: frames since the last step
G_LEVEL         equ $42                 ; word: level number
G_BANK          equ $76                 ; word: record number in the bank cache
G_TEXT_STRIDE   equ $8c                 ; word: text screen bytes per row
G_TEXT_HEIGHT   equ $8e                 ; word: text screen rows
G_RATING        equ $aa                 ; word: rating on the title screen
G_VIEW_BACK     equ $cc                 ; long: viewport buffer being drawn
G_VIEW_FRONT    equ $d0                 ; long: viewport buffer being shown
G_STARTUP       equ $dc                 ; long: frames since the level started
G_TEXT_DEST     equ $e0                 ; long: text screen bitmap
G_CACHE_END     equ $f8                 ; long: end of the file cache
G_STYLE         equ $fc                 ; long: style data of the level
G_WINS_BLUE     equ $104                ; words: two-player match counters
G_WINS_GREEN    equ $106
G_SAVED_BLUE    equ $110
G_SAVED_GREEN   equ $112

; ---------------------------------------------------------------------------
; Data

MOUSE           equ $9da4               ; +4 view scroll, +6 x, +8 y
VIEW_SCROLL     equ MOUSE+4
MOUSE_X         equ MOUSE+6
MOUSE_Y         equ MOUSE+8
LEVEL_RECORD    equ $c5a6               ; the level being played, 2048 bytes
OBJECTS         equ LEVEL_RECORD+$20
TERRAIN         equ $37080              ; 1632 x 168 pixels, four planes
TERRAIN_PLANE   equ $85e0
GROUND_BASE     equ $75578              ; style piece offsets are relative to it
OBJECT_BASE     equ 0                   ; object frame pointers are addresses
VIEW_PLANE      equ $2100               ; viewport plane: 44 bytes x 192 rows
GAME_ROWS       equ $a3c0               ; the game's A4: row y at y * 204
LEVELDATA       equ $1f7a2              ; leveldata: $590 bytes per style
STYLE_SIZE      equ $590
STYLES          equ 5                   ; graphics styles 0..4
SPECIALS        equ 4                   ; special backgrounds 1..4
GRID_ROWS       equ 42                  ; rows of the attribute grid
RATINGS         equ 4                   ; Fun, Tricky, Taxing, Mayhem
SKILL_SPRITE    equ $144f2              ; skill selection sprite
KEY_ASCII       equ $a526               ; raw key to ASCII, without shift
KEY_ASCII_SHIFT equ $a586               ; and with shift
TEXT_SCREEN     equ $23680              ; text screen bitmap
COPPER_DIWSTOP  equ $84ee               ; copper value word of DIWSTOP
COPPER_END      equ $8668               ; end of the copper list, 12 bytes
VIEW_PALETTE    equ $850e               ; copper value word of COLOR00
COPPER_ROWS     equ $8754               ; 13 groups of 16 colour moves and a wait
PALETTES        equ $8dd0               ; the text palettes, 32 bytes each
FADE_BLACK      equ $8cd6               ; palette numbers: every row black
FADE_RESULT     equ $8c54               ; palette numbers of the result screen
BRIEF_LEVEL     equ $917c               ; briefing: "Level 00", 8 characters
BRIEF_TITLE     equ $9187               ; the title, 32 characters
BRIEF_RATING    equ $9204               ; the rating name, 8 characters

; ---------------------------------------------------------------------------
; Routines

DRAW_TEXT       equ $15e4               ; A0: text entries
NUMBER_DIGITS   equ $1862               ; D0: number, returns four ASCII digits
SWAP_BUFFERS    equ $1898
WAIT_CLICK      equ $18de
WAIT_FRAME      equ $196a
FADE            equ $19e4               ; A0: palette numbers of the rows
PLAY_STOP       equ $1ae0               ; end of play: display and interrupts
TITLE_PREPARE   equ $1b10
TEXT_BACKGROUND equ $1cd4               ; clears the text screen
PANEL_REFRESH   equ $1f52
OBJECT_GRID     equ $2476               ; trigger areas into the grid (game A4)
STEEL_GRID      equ $24fe               ; clears the grid, steel areas (game A4)
LOAD_LEVEL      equ $2632               ; level G_LEVEL into LEVEL_RECORD
SELECT_STYLE    equ $280a
INIT_SIMULATION equ $2826
BRIEF_TEXTS     equ $2ba2
LOAD_ICONS      equ $2c7e
LOAD_FILE       equ $3286               ; A0: name, A1: destination, D1 = 0
PANEL_ONE       equ $3510
PANEL_TWO       equ $3522
PRESS_BUTTON    equ $36e4               ; "Press mouse button to continue"
UNPACK          equ $3934               ; A0: packed, A1: output, D0: size
MINIMAP_REFRESH equ $4a78
MINIMAP_COLUMN  equ $4aa4
CLEAR_GUARDS    equ $4b3a               ; clears the terrain's collision guard rows
BRIEF_PREVIEW   equ $4b58
BLIT            equ $704c
SOUND_CONTROL   equ $17268              ; D0 = -1 stops the music
RESULT_COMMENT  equ $82a

; ---------------------------------------------------------------------------
; Main flow and hooks. A hook replaces whole instructions with a jump and
; continues at the address after them.

TITLE_LOOP      equ $554                ; back to the title screen
ENTER_LEVEL     equ $56a                ; level graphics, briefing and play
FRAME_WAIT      equ $646                ; play loop: wait for the next frame
HOOK_FRAME      equ $654                ; BSR SWAP_BUFFERS / CLR.W G_FRAMES(A5)
FRAME_STEP      equ $65c
HOOK_ACTIONS    equ $680                ; BSR $B4A / BSR $14E2: mouse, keys
PLAY_MOUSE      equ $b4a
PLAY_KEYS       equ $14e2
HOOK_OVERLAY    equ $688                ; BSR PANEL_REFRESH / BSR MINIMAP_COLUMN
OVERLAY_DONE    equ $690
HOOK_KEYBOARD   equ $174e               ; MOVE.B D0,G_RAW_KEY(A5) / CIA handshake
KEYBOARD_DONE   equ $175a
ESC_ACTION      equ $1598               ; the game's Esc key action
HOOK_CAPTURE    equ $2762               ; BSR SELECT_STYLE / BSR INIT_SIMULATION
CAPTURE_DONE    equ $276a
HOOK_INJECT     equ $26e6               ; LEA LEVEL_RECORD,A0 / MOVE.W $1A(A0),D0
INJECT_DONE     equ $26f0
HOOK_BRIEFING   equ $34aa               ; BSR BRIEF_TEXTS / BSR BRIEF_PREVIEW
HOOK_BRIEF_WAIT equ $3502               ; BSR WAIT_CLICK / LEA FADE_BLACK,A0
BRIEF_WAIT_DONE equ $350a
HOOK_ENDED      equ $706                ; after the level: TST.B G_TWO_PLAYERS(A5)
ENDED_ONE       equ $70e
ENDED_TWO       equ $89e
HOOK_WON        equ $760                ; enough saved: CLR.B G_RESULT_SHOWN(A5)
WON_DONE        equ $768
HOOK_QUIT       equ $818                ; too few, right button: back to the menu
QUIT_DONE       equ $822
HOOK_MATCH      equ $918                ; two players: BSR $9CA / ADDQ.W #1,G_LEVEL(A5)
MATCH_WINS      equ $9ca
MATCH_NEXT      equ $920
MATCH_WINNER    equ $96a
HOOK_MATCH_END  equ $9be                ; end of the match: back to the title screen
MATCH_END_DONE  equ $9c6

TWO_PLAYER      equ 1                   ; the game has a two-player mode

; The instructions the hook at HOOK_ENDED replaced, then back to the game.
RESUME_ENDED    macro
        tst.b G_TWO_PLAYERS(a5)
        bne.s .two\@
        jmp ENDED_ONE
.two\@: jmp ENDED_TWO
        endm

; The names of the graphics styles in the list of a new level.
STYLE_NAMES     macro
        dc.b 'Dirt',0,'Fire',0,'Marble',0,'Pillar',0,'Crystal',0
        endm

; Keep the interrupts away while the editor changes what they share with it.
; The game runs in supervisor mode.
INTS_OFF        macro
        move.w sr,-(sp)
        ori.w #$0700,sr
        endm
INTS_ON         macro
        move.w (sp)+,sr
        endm
