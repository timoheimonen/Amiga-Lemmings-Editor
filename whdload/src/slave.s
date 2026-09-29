; Lemmings In-Game Level Editor V1.2.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; WHDLoad slave for Lemmings with the in-game level editor.
;
; The game is started from the patched disk images, installed as Disk.1 and
; Disk.2. The slave loads the main program "Code" from disk 1 to $400, replaces
; the game's floppy loader with reads from the disk images, gives the game's
; file cache the expansion memory, and adds a quit key. The editor is loaded by
; its bootstrap through the replaced loader, exactly as from floppy.
;
; Game addresses are runtime addresses of the supported "Code" ($400 base).

        include "whdload_api.i"

BASEMEM         equ $80000
GAME_MEM        equ $80000              ; the game's file cache and the editor
SAVE_DISK_SIZE  equ 901120              ; the editor's save disk image buffer
EXPMEM_SIZE     equ GAME_MEM+SAVE_DISK_SIZE
DIRECTORY       equ $70000              ; disk 1 directory, only during start-up
CODE_BASE       equ $400
; The top 16 bytes of the game's part of the expansion memory hold the
; mailbox for the editor: 'WHDL', the resload base, the address of the save
; disk image buffer (directly behind the mailbox) and the image state.
MAILBOX_SIZE    equ 16

        ifnd CODE_SIZE
        fail "CODE_SIZE (length of the patched Code file) must be defined"
        endif
        ifnd EDITOR2_SIZE
        fail "EDITOR2_SIZE (length of the WHDLoad build's Editor2 file) must be defined"
        endif

;============================================================================

base:
        moveq #-1,d0                    ; ws_Security
        rts
        dc.b "WHDLOADS"                 ; ws_ID
        dc.w 10                         ; ws_Version
        dc.w WHDLF_NoError|WHDLF_EmulTrap|WHDLF_ClearMem
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

name:   dc.b "Lemmings",0
copy:   dc.b "1991 DMA Design / Psygnosis",0
info:   dc.b "In-Game Level Editor V1.2.1",10
        dc.b "by Timo Heimonen",0
        even

resload:
        dc.l 0

;============================================================================
; Entry from WHDLoad. A0: resload base.

start:
        lea resload(pc),a1
        move.l a0,(a1)
        movea.l a0,a2

        ; Read the disk 1 directory. The install must be the disk images
        ; patched with this version's WHDLoad editor: "Code" with its
        ; bootstrap and "Editor2" must have exactly the lengths of that build.
        ; Floppy editor builds and other versions differ at least in Editor2.
        move.l #$400,d0
        move.l #$1000,d1
        moveq #1,d2
        lea (DIRECTORY).l,a0
        jsr resload_DiskLoad(a2)
        lea (DIRECTORY+$10).l,a1
        move.l #$1600,d3                ; first file's disk offset
        moveq #0,d4                     ; offset of Code
        moveq #0,d5                     ; length of Code
        moveq #0,d6                     ; length of Editor2
.find:  cmpi.l #-1,(a1)
        beq.s .end
        cmpi.l #'Code',(a1)
        bne.s .editor2
        tst.b 4(a1)
        bne.s .next
        move.l d3,d4
        move.l 12(a1),d5
        bra.s .next
.editor2:
        cmpi.l #'Edit',(a1)
        bne.s .next
        cmpi.l #'or2'<<8,4(a1)
        bne.s .next
        move.l 12(a1),d6
.next:  add.l 12(a1),d3
        lea 16(a1),a1
        bra.s .find
.end:   cmp.l #CODE_SIZE,d5
        bne wrong_version
        cmp.l #EDITOR2_SIZE,d6
        bne wrong_version
        move.l d5,d1
        move.l d4,d0
        moveq #1,d2
        lea (CODE_BASE).l,a0
        jsr resload_DiskLoad(a2)

        ; Check the patch sites before changing them.
        lea checks(pc),a0
.check: move.l (a0)+,d0
        beq.s .patch
        movea.l d0,a1
        move.l (a0)+,d0
        cmp.l (a1),d0
        bne wrong_version
        bra.s .check

.patch: lea find_disk(pc),a0            ; drive search, operation 5
        move.w #$4ef9,($80d6).l
        move.l a0,($80d8).l
        lea read_disk(pc),a0            ; read D7 bytes from disk offset D0
        move.w #$4ef9,($8164).l
        move.l a0,($8166).l
        move.w #$4e75,($841c).l         ; drive motor on: nothing to do
        move.w #$4e75,($8438).l         ; drive motor off
        lea keyboard(pc),a0             ; after each key, check the quit key
        move.w #$4eb9,($175a).l
        move.l a0,($175c).l
        move.w #$4e71,($1760).l

        ; The game takes its file cache from the address at $4 and the size
        ; at $8 ($38FE); the editor reserves the top of it.
        move.l expmem(pc),d0
        move.l d0,($4).w
        move.l #GAME_MEM-MAILBOX_SIZE,($8).w
        movea.l d0,a0
        adda.l #GAME_MEM-MAILBOX_SIZE,a0
        move.l #'WHDL',(a0)+
        move.l a2,(a0)+
        lea 8(a0),a1
        move.l a1,(a0)+
        clr.l (a0)

        jsr resload_FlushCache(a2)
        jmp (CODE_BASE).l

wrong_version:
        pea TDREASON_WRONGVER
        move.l resload(pc),-(sp)
        addq.l #resload_Abort,(sp)
        rts

; Address and first long word of every patched site.
checks:
        dc.l $80d6,$4a406b00            ; TST.W D0 / BMI.W
        dc.l $8164,$50f90000            ; ST $83C2.L
        dc.l $841c,$08b90007            ; BCLR #7,$BFD100.L
        dc.l $8438,$08f90007            ; BSET #7,$BFD100.L
        dc.l $175a,$08f90006            ; BSET #6,$BFEE01.L
        dc.l 0

;============================================================================
; Replacement for the loader's drive search ($80D6). The game identifies a
; disk by the first long word of its first file name in D2: 'main' is disk 1,
; 'Grou' (Ground1) disk 2. The disk is selected by setting the loader's drive
; (A5+2) to 3 for disk 1 or 4 for disk 2, and its directory is read to the
; loader's directory buffer (A5+4). Any other D2 keeps the current disk.

find_disk:
        movem.l d0-d2/a0-a2,-(sp)
        moveq #1,d0
        cmp.l #'main',d2
        beq.s .set
        moveq #2,d0
        cmp.l #'Grou',d2
        beq.s .set
        moveq #0,d0
        move.b 2(a5),d0
        subq.w #2,d0
        cmp.w #1,d0
        beq.s .set
        moveq #2,d0
.set:   move.l d0,d2
        addq.b #2,d0
        move.b d0,2(a5)
        move.l #$400,d0
        move.l #$1000,d1
        movea.l 4(a5),a0
        movea.l resload(pc),a2
        jsr resload_DiskLoad(a2)
        clr.w $14(a5)
        movem.l (sp)+,d0-d2/a0-a2
        rts

; Replacement for the loader's read ($8164): D7 bytes from disk offset D0 of
; the current disk to A0. Like the original, A0 advances past the data and all
; other registers are preserved.

read_disk:
        movem.l d0-d2/a1-a2,-(sp)
        move.l a0,-(sp)
        move.l d7,d1
        moveq #0,d2
        move.b 2(a5),d2
        subq.w #2,d2
        movea.l resload(pc),a2
        jsr resload_DiskLoad(a2)
        movea.l (sp)+,a0
        adda.l d7,a0
        movem.l (sp)+,d0-d2/a1-a2
        rts

; Called from the keyboard interrupt ($175A) after the key code has been
; stored at $26(A5). Runs the replaced instruction, then quits on the quit key.

keyboard:
        bset #6,($bfee01).l
        move.l d0,-(sp)
        move.b keyexit(pc),d0
        cmp.b $26(a5),d0
        beq.s .quit
        move.l (sp)+,d0
        rts
.quit:  pea TDREASON_OK
        move.l resload(pc),-(sp)
        addq.l #resload_Abort,(sp)
        rts
