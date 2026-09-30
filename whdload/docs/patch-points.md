# WHDLoad patch points

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

## Start-up

The slave skips the boot block and the intro. `Code` is self-contained: it
sets up its own stack, supervisor mode (`TRAP #1`, vector `$84`), interrupts
and hardware. Its file cache takes its memory from the long words at `$4`
(start) and `$8` (length), which the boot block normally leaves there; the
slave writes its expansion memory there (see the [memory map](memory-map.md)).

## Floppy loader

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

## Quit key

The keyboard interrupt stores the raw key code at `$26(A5)` and continues at
`$175A` (also when the editor's keyboard hook is installed). The slave
replaces the 8-byte `BSET #6,$BFEE01` there with a call that executes it and
then quits WHDLoad when the code equals `ws_keyexit` (F10 unless changed with
the `QuitKey` option). This works on a 68000, where WHDLoad cannot watch the
keyboard itself.

## Slave settings

- `ws_Version` 17 (`resload_ListFiles` for the custom levels writes into
  ExpMem, which needs WHDLoad 16.9), the version 16 and 17 fields zero;
  flags `NoError` (a failing resload call ends WHDLoad with a requester),
  `EmulTrap` (the game's `TRAP #1` when the VBR is moved) and `ClearMem`.
- BaseMem `$80000`, ExpMem `$80000`.

## Editor

The editor on the WHDLoad disk images is assembled with `WHDLOAD` defined:

- The editor's `disk_io.s` includes `src/disk_file.s` (the mailbox with the
  resload base) instead of the floppy disk transport; the MFM codec is left
  out.
- The custom levels are the `.lvl` files of `Levels`, listed with
  `resload_ListFiles`, read with `resload_LoadFile` and written with
  `resload_SaveFile`; there are no drive searches or disk prompts.
