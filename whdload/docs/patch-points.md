# WHDLoad patch points

## Lemmings

What the slave changes in the game's main program `Code` after loading it to
`$400`. Addresses are runtime addresses.

The slave accepts only the disk images of its own build: in the disk 1
directory, `Code` (the game program with the editor's bootstrap) and `Editor`
(the packed WHDLoad editor) must have exactly the lengths of that build,
and the first long word of every patch site is checked before it is changed.
Anything else, including the floppy version's disk images, ends with
WHDLoad's "wrong version" requester. The slave and its `Disk.1` therefore
always come from the same `patch.py --whdload` run; `Disk.2` is the unchanged
disk 2. The editor's own patch points are the same as on floppy (see the main
documentation).

### Start-up

The slave skips the boot block and the intro. `Code` is self-contained: it
sets up its own stack, supervisor mode (`TRAP #1`, vector `$84`), interrupts
and hardware. Its file cache takes its memory from the long words at `$4`
(start) and `$8` (length), which the boot block normally leaves there; the
slave writes its expansion memory there (see the [memory map](memory-map.md)).

### Floppy loader

All floppy hardware access of the game is in its loader at `$7FB2..$8497`. The
loader finds a disk by the first four characters of its first file name
(`'main'` for disk 1, `'Grou'` for disk 2) and keeps the drive in `$2(A5)`
(A5 = `$9E10`). Every read goes through `$8164`.

| Address | Original | Replacement |
| --- | --- | --- |
| `$80D6` | Search DF0..DF2 for the disk named in D2 and read its directory | `JMP` to the slave: select disk 1 or 2 by D2 (`$2(A5)` = 3 or 4) and read the directory to `$4(A5)` with `resload_DiskLoad` |
| `$8164` | Read D7 bytes from disk offset D0 to A0 (MFM, retried) | `JMP` to the slave: the same read with `resload_DiskLoad` from the selected disk image; A0 ends past the data |
| `$841C` | Drive motor on | `RTS` |
| `$8438` | Drive motor off | `RTS` |

The game's "insert disk 2" prompts therefore never appear.

### Quit key

The keyboard interrupt stores the raw key code at `$26(A5)` and continues at
`$175A` (also when the editor's keyboard hook is installed). The slave
replaces the 8-byte `BSET #6,$BFEE01` there with a call that executes it and
then quits WHDLoad when the code equals `ws_keyexit` (F10 unless changed with
the `QuitKey` option). This works on a 68000, where WHDLoad cannot watch the
keyboard itself.

### Slave settings

- `ws_Version` 17 (`resload_ListFiles` for the custom levels writes into
  ExpMem, which needs WHDLoad 16.9), the version 16 and 17 fields zero;
  flags `NoError` (a failing resload call ends WHDLoad with a requester),
  `EmulTrap` (the game's `TRAP #1` when the VBR is moved) and `ClearMem`.
- BaseMem `$80000`, ExpMem `$80000`.

### Editor

The editor on the WHDLoad disk images is assembled with `WHDLOAD` defined:

- The editor's `disk_io.s` includes `src/disk_file.s` (the mailbox with the
  resload base) instead of the floppy disk transport; the MFM codec is left
  out.
- The custom levels are the `.lvl` files of `Levels`, listed with
  `resload_ListFiles`, read with `resload_LoadFile`, written with
  `resload_SaveFile` and deleted with `resload_DeleteFile`; there are no
  drive searches or disk prompts.

## Holiday Lemmings 1994

The slave loads `data/HolidayLemmings1994`, the game's program with the
editor's hunks and hooks as patched for WHDLoad, and refuses any other length
of it, and so the floppy version's program. It relocates the program
(`resload_Relocate` with `WHDLTAG_CHIPPTR`, `WHDLTAG_ALIGN` 8 and
`WHDLTAG_LOADSEG`) and finds the hunks through the segment list. Offsets below
are in the game's code hunk (hunk 2); the first long word of every site is
checked before it is changed, and the two NOPs that follow the editor's
start-up jump at `$0344` (at `$034A`) must be there.

### Start-up

The game's start-up (`$0288..$0339`) opens graphics.library for the system's
copper lists, opens dos.library, allocates and reads its `Icons` buffer and
finds the process's requester window pointer. The slave does instead:

- the Icons buffer above the editor's mailbox, read from `data/Icons` and
  unpacked in place with the game's unpacker (`$3498`);
- the system's copper lists (`$92/$96(A5)`) set to WHDLoad's empty one at
  `$1000`; the requester window pointer (`$F2(A5)`) to a long word of the
  slave;
- the interrupt vectors `$68` and `$6C`, which the game saves as the system's
  when it takes the hardware over, set to handlers that acknowledge the
  interrupt;
- the stack at `$7F000`, then user mode as the game ran, and on at `$033A`,
  where the start-up continues with the editor's start-up hook and the
  game's hardware take-over.

### Patches

| Offset | Original | Replacement |
| --- | --- | --- |
| `$0160` | Suspend: give the hardware back, open a console window and wait for Return | `RTS` |
| `$0256` | QUIT on the title screen: back to the system | `JMP` to the slave: `resload_Abort` with `TDREASON_OK` |
| `$13BE` | Keyboard interrupt: `BSET #6,$BFEE01` (handshake) | `JSR` to the slave: the same, then quit when the key code at `$6(A5)` is `ws_keyexit` |
| `$2DF8` | File reader: A0 name, A1 destination, D1 returns the length (dos.library) | `JMP` to the slave: the same hand-over of the hardware around the read as the original (`$00C4`, `$0000`, `$175E`, `$00C4`, then `$0000`), the file read from `data/` with `resload_LoadFile` |

### Slave settings

- `ws_Version` 17, flags `NoError` and `ClearMem`, BaseMem `$80000`, ExpMem
  `$60000`, no `ws_CurrentDir`: the game's files are in `data`, the custom
  levels in `Levels`.

### Editor

The editor is assembled with `HOLIDAY94` and `WHDLOAD` defined: its file
access is `src/disk_file.s`, as in the Lemmings install, instead of the
floppy version's dos.library calls.
