; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; WHDLoad slave for Holiday Lemmings 1994 with the in-game level editor.
;
; The game is an AmigaDOS program. The slave loads its executable, patched
; with the editor's two hunks, from data/ and relocates it: the chip memory
; hunks into BaseMem, the others into the expansion memory. It does the work
; of the game's start-up that needs the operating system (the Icons file and
; its memory), replaces the game's file reader with WHDLoad's, and turns the
; game's two ways back to the system into a quit: the title screen's quit and
; the suspend key. The editor reaches WHDLoad through the mailbox the slave
; leaves directly above the editor's hunk.
;
; Offsets are relative to the start of the game's code hunk (hunk 2) of the
; supported executable.

        include "whdload_api.i"

BASEMEM         equ $80000
EXPMEM_SIZE     equ $60000              ; the program's other hunks and Icons
CHIP_HUNKS      equ $2000               ; the chip memory hunks, above the
USER_STACK      equ $7f000              ; empty copper list at $1000
EDITOR_RESERVE  equ $20000              ; the editor's hunk (hunk 4)
MAILBOX_SIZE    equ 8                   ; 'WHDL' and the resload base
ICONS_SIZE      equ $17200              ; the game's Icons buffer
HUNKS           equ 6

; The game's code hunk
GLOBALS         equ $77de               ; the game's A5
TAKE_OVER       equ $0000               ; the game takes over the hardware
RESTORE_SYSTEM  equ $00c4               ; and gives it back to the system
SUSPEND         equ $0160               ; suspend key: a console window
QUIT            equ $0256               ; title screen quit: back to the system
START_CONTINUE  equ $033a               ; the start-up after its system calls
KEY_ACK         equ $13be               ; keyboard interrupt: CIA handshake
LOAD_FILE       equ $2df8               ; A0: name, A1: destination
PLAY_STOP       equ $175e
UNPACK          equ $3498               ; A0: packed, A1: output, D0: size
HOOK_START      equ $0344               ; the editor's start-up hook
; Global variables (A5)
G_RAW_KEY       equ $06
G_SAVED_SP      equ $86
G_SYSTEM_COP1   equ $92                 ; the system's copper lists
G_SYSTEM_COP2   equ $96
G_WINDOW_PTR    equ $f2                 ; points to the process's pr_WindowPtr
G_ICONS         equ $fe

        ifnd EXE_SIZE
        fail "EXE_SIZE (length of the patched executable) must be defined"
        endif

;============================================================================

base:
        moveq #-1,d0                    ; ws_Security
        rts
        dc.b "WHDLOADS"                 ; ws_ID
        dc.w 17                         ; ws_Version
        dc.w WHDLF_NoError|WHDLF_ClearMem
        dc.l BASEMEM                    ; ws_BaseMemSize
        dc.l 0                          ; ws_ExecInstall
        dc.w start-base                 ; ws_GameLoader
        dc.w 0                          ; ws_CurrentDir
        dc.w 0                          ; ws_DontCache
        dc.b 0                          ; ws_keydebug
keyexit:
        dc.b $59                        ; ws_keyexit: F10
expmem:
        dc.l EXPMEM_SIZE                ; ws_ExpMem, replaced by its address
        dc.w name-base                  ; ws_name
        dc.w copy-base                  ; ws_copy
        dc.w info-base                  ; ws_info
        dc.w 0                          ; ws_kickname: no kickstart image
        dc.l 0                          ; ws_kicksize
        dc.w 0                          ; ws_kickcrc
        dc.w 0                          ; ws_config

name:   dc.b "Holiday Lemmings 1994",0
copy:   dc.b "1994 DMA Design / Psygnosis",0
info:   dc.b "In-Game Level Editor V2.3",10
        dc.b "by Timo Heimonen",0
executable:
        dc.b "data/HolidayLemmings1994",0
icons:  dc.b "Icons",0
        even

resload:
        dc.l 0
hunk2:  dc.l 0
window: dc.l 0                          ; stands in for pr_WindowPtr
path:   dc.b "data/"
path_name:
        ds.b 64
        even

;============================================================================
; Entry from WHDLoad, in supervisor mode. A0: resload base.

start:
        lea resload(pc),a1
        move.l a0,(a1)
        movea.l a0,a2

        ; The executable must be the one of this build: the game's program
        ; with the WHDLoad version of the editor.
        lea executable(pc),a0
        movea.l expmem(pc),a1
        jsr resload_LoadFile(a2)
        cmp.l #EXE_SIZE,d0
        bne wrong_version
        movea.l expmem(pc),a0
        clr.l -(sp)                     ; TAG_DONE
        move.l #-1,-(sp)
        move.l #WHDLTAG_LOADSEG,-(sp)
        pea 8
        move.l #WHDLTAG_ALIGN,-(sp)
        pea CHIP_HUNKS
        move.l #WHDLTAG_CHIPPTR,-(sp)
        movea.l sp,a1
        jsr resload_Relocate(a2)
        lea 7*4(sp),sp

        ; The segment list starts at the second long word of the executable's
        ; place; each segment is a link (BPTR) followed by the hunk.
        movea.l expmem(pc),a0
        addq.l #4,a0
        lea hunks(pc),a1
        moveq #HUNKS-1,d0
.hunk:  lea 4(a0),a3
        move.l a3,(a1)+
        move.l (a0),d1
        lsl.l #2,d1
        movea.l d1,a0
        dbra d0,.hunk
        cmpa.w #0,a0
        bne wrong_version
        movea.l hunks+2*4(pc),a3        ; the game's code hunk
        lea hunk2(pc),a0
        move.l a3,(a0)

        ; Check the patch sites before changing them.
        lea checks(pc),a0
.check: move.w (a0)+,d0
        bmi.s .patch
        move.l (a0)+,d1
        cmp.l (a3,d0.w),d1
        bne wrong_version
        bra.s .check

.patch: move.w #$4e75,SUSPEND(a3)       ; RTS
        lea quit(pc),a0
        move.w #$4ef9,QUIT(a3)
        move.l a0,QUIT+2(a3)
        lea load_file(pc),a0
        move.w #$4ef9,LOAD_FILE(a3)
        move.l a0,LOAD_FILE+2(a3)
        lea keyboard(pc),a0
        move.w #$4eb9,KEY_ACK(a3)
        move.l a0,KEY_ACK+2(a3)
        move.w #$4e71,KEY_ACK+6(a3)

        ; The mailbox for the editor directly above its hunk, and Icons above
        ; the mailbox.
        movea.l hunks+4*4(pc),a1
        adda.l #EDITOR_RESERVE,a1
        move.l #'WHDL',(a1)+
        move.l a2,(a1)+
        lea GLOBALS(a3),a5
        move.l a1,G_ICONS(a5)
        lea icons(pc),a0
        bsr load_path
        jsr resload_LoadFile(a2)
        movea.l G_ICONS(a5),a0
        movea.l a0,a1
        jsr UNPACK(a3)

        ; What the start-up took from the system: its copper lists stand for
        ; the empty one WHDLoad left at $1000.
        move.l #$1000,G_SYSTEM_COP1(a5)
        move.l #$1000,G_SYSTEM_COP2(a5)
        lea window(pc),a0
        move.l a0,G_WINDOW_PTR(a5)
        ; The interrupt vectors the game saves and restores as the system's.
        lea system_ports(pc),a0
        move.l a0,($68).w
        lea system_vertb(pc),a0
        move.l a0,($6c).w

        jsr resload_FlushCache(a2)
        lea USER_STACK,a0
        move.l a0,usp
        move.l a0,G_SAVED_SP(a5)
        lea START_CONTINUE(a3),a3
        move.w #0,sr                    ; user mode, as the game ran
        jmp (a3)

wrong_version:
        pea TDREASON_WRONGVER
        move.l resload(pc),-(sp)
        addq.l #resload_Abort,(sp)
        rts

hunks:  ds.l HUNKS

; Offset and first long word of every patched site.
checks:
        dc.w SUSPEND
        dc.l $48e7fffe                  ; MOVEM.L D0-D7/A0-A6,-(SP)
        dc.w QUIT
        dc.l $2e6d0086                  ; MOVEA.L $86(A5),SP
        dc.w LOAD_FILE
        dc.l $48e700f0                  ; MOVEM.L A0-A3,-(SP)
        dc.w KEY_ACK
        dc.l $08f90006                  ; BSET #6,$BFEE01.L
        dc.w HOOK_START+6
        dc.l $4e714e71                  ; NOPs after the editor's start-up jump
        dc.w -1

; The interrupts the game hands back to the system: acknowledge them.
system_ports:
        move.w #$0008,($dff09c).l
        rte
system_vertb:
        move.w #$0070,($dff09c).l
        rte

;============================================================================
; Replacement for the game's file reader. A0: name, A1: destination. D1
; returns the length; A0-A5 and D2-D7 are preserved, as by the original. The
; hardware is handed over as by the original around its reads; the file comes
; from data/ through WHDLoad.

load_file:
        movem.l d0/d2-d7/a0-a6,-(sp)
        movea.l hunk2(pc),a3
        jsr RESTORE_SYSTEM(a3)
        jsr TAKE_OVER(a3)
        jsr PLAY_STOP(a3)
        jsr RESTORE_SYSTEM(a3)
        movem.l 7*4(sp),a0-a1
        bsr.s load_path
        jsr resload_LoadFile(a2)
        move.l d0,d1
        move.l d1,-(sp)
        movea.l hunk2(pc),a3
        jsr TAKE_OVER(a3)
        move.l (sp)+,d1
        movem.l (sp)+,d0/d2-d7/a0-a6
        rts

; A0: a name of the game's files. A0 returns its path in data/, A2 the
; resload base.
load_path:
        lea path_name(pc),a2
.copy:  move.b (a0)+,(a2)+
        bne.s .copy
        lea path(pc),a0
        movea.l resload(pc),a2
        rts

; Title screen quit: back to the system.
quit:   pea TDREASON_OK
        move.l resload(pc),-(sp)
        addq.l #resload_Abort,(sp)
        rts

; Called from the keyboard interrupt after the key code has been stored at
; G_RAW_KEY(A5). Runs the replaced instruction, then quits on the quit key.
keyboard:
        bset #6,($bfee01).l
        move.l d0,-(sp)
        move.b keyexit(pc),d0
        cmp.b G_RAW_KEY(a5),d0
        beq.s quit
        move.l (sp)+,d0
        rts
