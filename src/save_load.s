; Lemmings In-Game Level Editor V1.1
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Format-1 save creation, validated loading and bounded terrain replay. Routines
; use the enclosing editor's position-independent storage and A5 game globals.

install_load_hooks:
        lea replay_hook(pc),a0
        move.l a0,$2a50
        move.w #$4ef9,$2a4e
        move.w #$4e71,$2a54
        lea briefing_wait(pc),a0
        move.l a0,$3504
        move.w #$4ef9,$3502
        move.w #$4e71,$3508
        rts

; Build a complete format-1 slot in save_record from the live placement log.
; A0 points to exactly 16 readable name bytes, printable ASCII and NUL-padded.
; The name must not overlap save_record. Return D0=0 or -1; preserve all other
; registers. Refusal clears the output. No terrain, log or load request changes.
create_record:
        movem.l d1-d7/a0-a4,-(sp)
        lea state(pc),a4
        lea save_record(pc),a2
        bsr .clear
        tst.b active(a4)
        beq .bad
        tst.b load_pending(a4)
        bne .bad
        move.l paint_count(a4),d6
        cmp.l #MAX_PLACEMENTS,d6
        bhi .bad
        move.l #$4c454d45,(a2)
        move.l #$44495400,4(a2)
        move.l #$00010040,8(a2)
        move.l #$00010001,12(a2)
        move.w level_id(a4),16(a2)
        move.w d6,18(a2)
        move.l base_crc(a4),20(a2)
        lea 24(a2),a1
        moveq #15,d1
.name:  move.b (a0)+,(a1)+
        dbra d1,.name
        lea placements(pc),a0
        lea 64(a2),a1
        move.w d6,d1
        beq.s .checksum
        subq.w #1,d1
.copy:  move.l (a0)+,(a1)+
        dbra d1,.copy
.checksum:
        movea.l a2,a0
        move.l d6,d0
        lsl.l #2,d0
        add.l #64,d0
        moveq #60,d1
        bsr crc32
        move.l d0,60(a2)
        movea.l a2,a0
        bsr validate_record
        tst.l d0
        beq.s .done
.bad:   bsr.s .clear
        moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a0-a4
        rts
.clear: movea.l a2,a1
        move.w #511,d1
.zero:  clr.l (a1)+
        dbra d1,.zero
        rts

; A0 points to one complete, word-aligned 2048-byte slot. Accept only while
; editing a live single-player level. Return D0=0 on acceptance or -1 on
; refusal; preserve all other registers. Refusal changes no editor state.
; The caller must obtain confirmation and restore game disk access first.
queue_load:
        movem.l d1-d7/a0-a4,-(sp)
        lea state(pc),a4
        tst.b active(a4)
        beq.s .bad
        tst.b load_pending(a4)
        bne.s .bad
        bsr validate_record
        tst.l d0
        bne.s .done
        lea load_record(pc),a1
        move.w #511,d1
.copy:  move.l (a0)+,(a1)+
        dbra d1,.copy
        clr.b load_error(a4)
        st load_pending(a4)
        bra.s .done
.bad:   moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a0-a4
        rts

; Validate against the captured original record and current graphics metadata.
; A0 addresses a full slot; A4 addresses state. Preserve all except D0/CCR.
validate_record:
        movem.l d1-d7/a0-a2,-(sp)
        moveq #0,d7
        bra.s validate_record_body

; Validate the wire format of any level's slot during disk scanning. Current
; level records also undergo the base/capacity/piece checks used for replay.
; Other levels' base compatibility is checked when that level is loaded.
validate_any_record:
        movem.l d1-d7/a0-a2,-(sp)
        moveq #-1,d7
validate_record_body:
        movea.l a0,a2
        tst.b valid(a4)
        beq .bad
        tst.b $30(a5)
        bne .bad
        cmpi.l #$4c454d45,(a2)       ; LEME
        bne .bad
        cmpi.l #$44495400,4(a2)      ; DIT NUL
        bne .bad
        cmpi.l #$00010040,8(a2)      ; version and header length
        bne .bad
        cmpi.l #$00010001,12(a2)
        bne .bad
        move.w 16(a2),d0
        cmp.w #120,d0
        bhs .bad
        cmp.w level_id(a4),d0
        beq.s .current
        tst.b d7
        bne.s .count
.current:
        moveq #0,d7
        cmp.w level_id(a4),d0
        bne .bad
        cmp.w $42(a5),d0
        bne .bad
        move.l 20(a2),d0
        cmp.l base_crc(a4),d0
        bne .bad
.count:
        moveq #0,d6
        move.w 18(a2),d6
        cmp.w #MAX_PLACEMENTS,d6
        bhi .bad
        tst.b d7
        bne.s .name_start
        move.w original_count(a4),d0
        cmp.w #MAX_PLACEMENTS,d0
        bhi .bad
        add.w d6,d0
        cmp.w #MAX_PLACEMENTS,d0
        bhi .bad
.name_start:
        lea 24(a2),a0
        moveq #15,d1
        moveq #0,d2                ; non-space character seen
        moveq #0,d3                ; NUL terminator seen
.name:  moveq #0,d0
        move.b (a0)+,d0
        beq.s .nul
        tst.b d3
        bne .bad
        cmp.b #32,d0
        blo .bad
        cmp.b #126,d0
        bhi .bad
        cmp.b #32,d0
        beq.s .name_next
        moveq #1,d2
        bra.s .name_next
.nul:   moveq #1,d3
.name_next:
        dbra d1,.name
        tst.b d2
        beq .bad
        moveq #19,d1
.reserved:
        tst.b (a0)+
        bne .bad
        dbra d1,.reserved
        lea 64(a2),a0
        move.w d6,d1
        beq.s .padding
        subq.w #1,d1
.entry: move.w (a0)+,d0
        bmi .bad                   ; H bit 15 reserved
        move.w (a0)+,d0
        btst #6,d0
        bne .bad
        tst.b d7
        bne.s .entry_next
        and.w #63,d0
        cmp.w piece_count(a4),d0
        bhs .bad
.entry_next:
        dbra d1,.entry
.padding:
        moveq #0,d7
        move.w d6,d7
        lsl.w #2,d7
        add.w #64,d7
        move.w #2048,d1
        sub.w d7,d1
        subq.w #1,d1
.zero:  tst.b (a0)+
        bne.s .bad
        dbra d1,.zero
        movea.l a2,a0
        move.l d7,d0
        moveq #60,d1
        bsr crc32
        cmp.l 60(a2),d0
        bne.s .bad
        moveq #0,d0
        bra.s .done
.bad:   moveq #-1,d0
.done:  movem.l (sp)+,d1-d7/a0-a2
        rts

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

; Called by capture after loading metadata and hashing the fresh base. A
; changed base refuses replay, leaving a clean original level and an error.
check_loaded_base:
        clr.b load_reopen(a4)
        tst.b load_pending(a4)
        beq.s .done
        lea load_record(pc),a0
        bsr validate_record
        tst.l d0
        beq.s .done
        clr.b load_pending(a4)
        st load_error(a4)
        st load_reopen(a4)
.done:  rts

; Entered from the frame hook with its register frame still on the stack.
; Use the game's loader, simulation initialization and normal start path.
; Invalidating the bank cache reloads the untouched base, including oddtable.
restart_saved_level:
        bsr hide_status
        st $2b(a5)
        move.w #$0010,$9a(a6)
        move.w #$8020,$9a(a6)
        clr.b $2f(a5)
        jsr $1ae0
        moveq #-1,d0
        jsr $17268
        move.w #-1,$76(a5)
        jsr $2632
        movem.l (sp)+,d0-d7/a0-a6
        jmp $56a

; The second terrain builder has completed both normal and special terrain.
; Replay before its minimap and collision guard cleanup, bounded by the count.
replay_hook:
        movem.l d0-d7/a0-a6,-(sp)
        lea state(pc),a4
        tst.b load_pending(a4)
        beq .done
        clr.b load_pending(a4)
        st load_reopen(a4)
        lea load_record+64(pc),a0
        lea placements(pc),a1
        moveq #0,d7
        move.w load_record+18(pc),d7
        move.l d7,paint_count(a4)
        sub.w d7,remaining(a4)
        tst.w d7
        beq.s .done
        subq.w #1,d7
.entry: move.l (a0),(a1)+
        move.w (a0)+,d6
        move.w (a0)+,d5
        move.w d5,d0
        and.w #63,d0
        move.w d0,piece_id(a4)
        btst #13,d6
        sne negative(a4)
        btst #14,d6
        sne flipped(a4)
        movem.l d5-d7/a0-a1,-(sp)
        bsr descriptor
        move.w d6,d0
        lsl.w #3,d0
        asr.w #3,d0                ; signed 13-bit x
        move.w d5,d1
        asr.w #7,d1                ; signed 9-bit y
        move.w width(a4),d2
        lsr.w #1,d2
        add.w d2,d0                ; compositor takes the centered anchor
        move.w height(a4),d2
        lsr.w #1,d2
        add.w d2,d1
        moveq #0,d2
        bsr composite
        movem.l (sp)+,d5-d7/a0-a1
        dbra d7,.entry
        clr.w piece_id(a4)
        clr.b negative(a4)
        clr.b flipped(a4)
.done:  movem.l (sp)+,d0-d7/a0-a6
        jsr $4a78
        jsr $4b3a
        jmp $2a56

; A loaded level returns directly to the paused editor. Ordinary level starts
; retain the game's briefing click wait and its original following LEA.
briefing_wait:
        lea state(pc),a0
        tst.b load_reopen(a0)
        bne.s .done
        jsr $18de
.done:  lea ($8cd6).l,a0
        jmp $350a
