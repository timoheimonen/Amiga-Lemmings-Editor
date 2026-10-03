; Lemmings In-Game Level Editor V2.3
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; File access of the versions that run with the system, included by
; disk_io.s in place of the floppy disk transport. The custom levels are the
; .lvl files of the directory Levels in the current directory, read and
; written through dos.library. Every call gives the hardware back to the
; system as the game's own file reader does, turns the system's requesters
; off, and takes the hardware over again afterwards. The calls have the
; register interface of WHDLoad's resload functions, which levels.s,
; level_save.s and level_delete.s use through file_mailbox: they change D0/D1
; only.

resload_LoadFile        equ $08
resload_SaveFile        equ $0c
resload_ListFiles       equ $14
resload_GetFileSize     equ $24
resload_DeleteFile      equ $58

_LVOOpen        equ -30
_LVOClose       equ -36
_LVORead        equ -42
_LVOWrite       equ -48
_LVODeleteFile  equ -72
_LVOLock        equ -84
_LVOUnLock      equ -90
_LVOExamine     equ -102
_LVOExNext      equ -108
_LVOCreateDir   equ -120
_LVOIoErr       equ -132
_LVOFindTask    equ -294
_LVOPutMsg      equ -366
_LVOGetMsg      equ -372
_LVOWaitPort    equ -384
pr_MsgPort      equ $5c                 ; the process's message port
fl_Task         equ 12                  ; FileLock: the file system's port
ACTION_FLUSH    equ 27
SP_PACKET       equ 20                  ; StandardPacket: the DosPacket after the Message
DP_PORT         equ 4
DP_TYPE         equ 8
MODE_OLDFILE    equ 1005
MODE_NEWFILE    equ 1006
ACCESS_READ     equ -2
ERROR_OBJECT_NOT_FOUND equ 205
ERROR_DISK_WRITE_PROTECTED equ 214
FIB_TYPE        equ 4                   ; FileInfoBlock: > 0 directory, < 0 file
FIB_NAME        equ 8
FIB_SIZE        equ 124
DOS_FIB         equ DISK_VERIFY         ; a FileInfoBlock, longword aligned
DOS_PACKET      equ DOS_FIB+260         ; a StandardPacket
DOS_READ_MAX    equ DISK_WORK_END-DISK_TRACK ; the largest file LoadFile reads

; A2 returns the base of the calls, with Z set. D0 is preserved.
file_mailbox:
        lea dos_calls(pc),a2
        cmp.b d0,d0
        rts

; The calls at the offsets of the resload functions.
dos_calls:
        bra.w dos_refuse                ; $00
        bra.w dos_refuse                ; $04
        bra.w dos_load                  ; $08 resload_LoadFile
        bra.w dos_save                  ; $0c resload_SaveFile
        bra.w dos_refuse                ; $10
        bra.w dos_list                  ; $14 resload_ListFiles
        bra.w dos_refuse                ; $18
        bra.w dos_refuse                ; $1c
        bra.w dos_refuse                ; $20
        bra.w dos_size                  ; $24 resload_GetFileSize
        rept (resload_DeleteFile-$28)/4
        bra.w dos_refuse
        endr
        bra.w dos_delete                ; $58 resload_DeleteFile

dos_refuse:
        moveq #0,d0
        moveq #-1,d1
        rts

; A0: name, A1: destination. D0 returns the length read (at most
; DOS_READ_MAX), 0 on failure with D1 the error.
dos_load:
        movem.l d2-d7/a0-a6,-(sp)
        movea.l a1,a3                   ; A0/A1 do not survive the calls
        bsr dos_system
        moveq #0,d5
        move.l a0,d1
        move.l #MODE_OLDFILE,d2
        jsr _LVOOpen(a6)
        move.l d0,d4
        beq.s .done
        move.l d4,d1
        move.l a3,d2
        move.l #DOS_READ_MAX,d3
        jsr _LVORead(a6)
        move.l d0,d5
        bpl.s .close
        moveq #0,d5
.close: jsr _LVOIoErr(a6)
        move.l d0,d7                    ; the read's error, if it failed
        move.l d4,d1
        jsr _LVOClose(a6)
        bra dos_error
.done:  bra dos_result

; D0: length, A0: name, A1: data. Write the file, replacing an old one; the
; directory of a name in Levels is created when it is missing. D0 returns
; nonzero on success, otherwise 0 with D1 the error.
dos_save:
        movem.l d2-d7/a0-a6,-(sp)
        move.l d0,d6
        movea.l a0,a2                   ; A0/A1 do not survive the calls
        movea.l a1,a3
        bsr dos_system
        bsr.s .open
        bne.s .write
        jsr _LVOIoErr(a6)
        cmp.l #ERROR_OBJECT_NOT_FOUND,d0
        bne.s .error
        lea levels_dir(pc),a0           ; the directory Levels is missing
        move.l a0,d1
        jsr _LVOCreateDir(a6)
        move.l d0,d1
        beq.s .error
        jsr _LVOUnLock(a6)
        bsr.s .open
        bne.s .write
        jsr _LVOIoErr(a6)
        move.l d0,d7
        bra.s .flush                    ; the new directory is written out
.write: move.l d4,d1
        move.l a3,d2
        move.l d6,d3
        jsr _LVOWrite(a6)
        move.l d0,d5
        jsr _LVOIoErr(a6)
        move.l d0,d7                    ; the write's error, if it failed
        move.l d4,d1
        jsr _LVOClose(a6)
        cmp.l d6,d5
        beq.s .saved
        move.l a2,d1                    ; a failed write leaves no file
        jsr _LVODeleteFile(a6)
.flush: bsr dos_flush
        moveq #0,d5
        bra dos_error
.error: moveq #0,d5
        bra dos_result
.saved: bsr dos_flush
        moveq #1,d5
        bra dos_result
.open:  move.l a2,d1
        move.l #MODE_NEWFILE,d2
        jsr _LVOOpen(a6)
        move.l d0,d4
        rts

; D0: length of the buffer, A0: directory, A1: buffer. Put the names of the
; directory's files into the buffer, each ended by NUL, as many as fit. D0
; returns their number.
dos_list:
        movem.l d2-d7/a0-a6,-(sp)
        move.l d0,d6                    ; room left
        movea.l a1,a3
        moveq #0,d5                     ; names
        bsr dos_system
        move.l a0,d1
        moveq #ACCESS_READ,d2
        jsr _LVOLock(a6)
        move.l d0,d4
        beq.s .done
        bsr dos_fib
        move.l d4,d1
        jsr _LVOExamine(a6)
        tst.l d0
        beq.s .unlock
        movea.l d2,a0
        tst.l FIB_TYPE(a0)
        ble.s .unlock                   ; not a directory
.next:  bsr dos_fib
        move.l d4,d1
        jsr _LVOExNext(a6)
        tst.l d0
        beq.s .unlock
        movea.l d2,a0
        tst.l FIB_TYPE(a0)
        bpl.s .next                     ; a directory
        lea FIB_NAME(a0),a0
        movea.l a0,a1
.length:
        tst.b (a1)+
        bne.s .length
        suba.l a0,a1                    ; with its NUL
        cmp.l a1,d6
        blo.s .unlock                   ; the buffer is full
        sub.l a1,d6
.copy:  move.b (a0)+,(a3)+
        bne.s .copy
        addq.l #1,d5
        bra.s .next
.unlock:
        move.l d4,d1
        jsr _LVOUnLock(a6)
.done:  bra dos_result

; A0: name. D0 returns the length of the file, 0 when there is none and -1
; for a directory, whose name is taken too.
dos_size:
        movem.l d2-d7/a0-a6,-(sp)
        moveq #0,d5
        bsr dos_system
        move.l a0,d1
        moveq #ACCESS_READ,d2
        jsr _LVOLock(a6)
        move.l d0,d4
        beq.s .done
        bsr dos_fib
        move.l d4,d1
        jsr _LVOExamine(a6)
        tst.l d0
        beq.s .unlock
        movea.l d2,a0
        moveq #-1,d5
        tst.l FIB_TYPE(a0)
        bpl.s .unlock                   ; a directory
        move.l FIB_SIZE(a0),d5
.unlock:
        move.l d4,d1
        jsr _LVOUnLock(a6)
.done:  bra dos_result

; A0: name. Delete the file. D0 returns nonzero on success, otherwise 0
; with D1 the error.
dos_delete:
        movem.l d2-d7/a0-a6,-(sp)
        bsr dos_system
        move.l a0,d1
        jsr _LVODeleteFile(a6)
        move.l d0,d5
        jsr _LVOIoErr(a6)
        move.l d0,d7                    ; its error, if it failed
        bsr dos_flush
        bra.s dos_error

; Common end of the calls: D5 is the result. D1 returns the system's error
; when it is 0. Give the hardware back to the game.
dos_result:
        jsr _LVOIoErr(a6)
        move.l d0,d7

; D5: the result, D7: the error when D5 is 0.
dos_error:
        moveq #0,d1
        tst.l d5
        bne.s dos_return
        move.l d7,d1

; D5: the result, D1: the error when D5 is 0.
dos_return:
        move.l d1,-(sp)
        bsr dos_game
        move.l (sp)+,d1
        move.l d5,d0
        movem.l (sp)+,d2-d7/a0-a6
        rts

; Have the file system of the directory Levels write out its buffers, and
; wait until it has (ACTION_FLUSH): no disk transfer may be under way when
; the game takes the hardware over. A6: dos.library. Preserves every
; register.
dos_flush:
        movem.l d0-d4/a0-a3/a6,-(sp)
        lea levels_dir(pc),a0
        move.l a0,d1
        moveq #ACCESS_READ,d2
        jsr _LVOLock(a6)
        move.l d0,d4
        beq.s .done
        movea.l 4.w,a6
        suba.l a1,a1
        jsr _LVOFindTask(a6)
        movea.l d0,a3
        lea pr_MsgPort(a3),a3           ; the reply port
        lea install(pc),a1
        adda.l #DOS_PACKET,a1
        movea.l a1,a2
        moveq #(SP_PACKET+48)/4-1,d0
.clear: clr.l (a2)+
        dbra d0,.clear
        lea SP_PACKET(a1),a2
        move.l a2,10(a1)                ; ln_Name: the packet
        move.l a3,14(a1)                ; mn_ReplyPort
        move.l a1,(a2)                  ; dp_Link: the message
        move.l a3,DP_PORT(a2)
        move.l #ACTION_FLUSH,DP_TYPE(a2)
        move.l d4,d0
        lsl.l #2,d0
        movea.l d0,a0
        movea.l fl_Task(a0),a0
        jsr _LVOPutMsg(a6)
        movea.l a3,a0
        jsr _LVOWaitPort(a6)
        movea.l a3,a0
        jsr _LVOGetMsg(a6)
        movea.l 9*4(sp),a6              ; dos.library
        move.l d4,d1
        jsr _LVOUnLock(a6)
.done:  movem.l (sp)+,d0-d4/a0-a3/a6
        rts

; D2 returns the FileInfoBlock.
dos_fib:
        lea install(pc),a0
        adda.l #DOS_FIB,a0
        move.l a0,d2
        rts

; Give the hardware to the system and turn its requesters off. A6 returns
; dos.library; every other register is preserved.
dos_system:
        movem.l d0-d7/a0-a5,-(sp)
        jsr RESTORE_SYSTEM
        movem.l (sp),d0-d7/a0-a5
        lea state(pc),a4
        movea.l G_WINDOW_PTR(a5),a0
        move.l (a0),dos_window(a4)
        move.l #-1,(a0)
        movea.l G_DOS(a5),a6
        movem.l (sp)+,d0-d7/a0-a5
        rts

; Turn the requesters back on and give the hardware to the game. A6 returns
; the custom chip base; every other register is preserved.
dos_game:
        movem.l d0-d7/a0-a5,-(sp)
        lea state(pc),a4
        movea.l G_WINDOW_PTR(a5),a0
        move.l dos_window(a4),(a0)
        jsr TAKE_OVER
        movem.l (sp)+,d0-d7/a0-a5
        lea $dff000,a6
        rts
