# Holiday Lemmings 1994

How the editor is built into Holiday Lemmings 1994, which runs on the
Lemmings engine. The editor's sources are the same for both games; what
differs is chosen at assembly time. The WHDLoad version is documented in
[whdload/docs/](../whdload/docs/).

## The game

One AmigaDOS (OFS) disk. The game is the AmigaDOS executable
`HolidayLemmings1994/HolidayLemmings1994`, four hunks that the system loads
anywhere in memory: hunk 1 chip data (the title screen, view buffers,
panel), hunk 2 code and data, hunk 3 chip code and data (copper list), and a
BSS hunk. `s/startup-sequence` changes to the directory `HolidayLemmings1994`
and starts the program there.

Addresses in this document are offsets into a hunk ("hunk 2 `$0344`"). The
game keeps its globals at A5 = hunk 2 + `$77DE`.

- Two graphics styles: Brick (style 0, `ground1`) and Snow (style 2,
  `ground3`); no special backgrounds and no two-player mode.
- Four ratings, FROST, HAIL, FLURRY and BLIZZARD, of 16 levels each, chosen
  with a click on the rating sign of the title screen.
- The game runs in user mode with the operating system present. It takes
  the hardware over (hunk 2 `$0000`) and gives it back (`$00C4`) around its
  file reader (`$2DF8`), which loads every file through dos.library.

## Assembly

`src/game_lemmings.i` and `src/game_holiday94.i` (`HOLIDAY94` defined) hold
everything the editor knows about the game: routines, data, global variable
offsets, hook sites with their continuation addresses, and game constants.
Code that differs between the games is chosen by symbols they define:

| Symbol | Lemmings | Holiday 1994 | Meaning |
| --- | --- | --- | --- |
| `FILES` | WHDLoad build | yes | Custom levels are `.lvl` files |
| `TWO_PLAYER` | yes | no | The two-player list, marker and match hooks |
| `RELOCATED` | no | yes | The editor is a hunk of the game's program |
| `STYLE_MASK` | no | `%101` | Styles the game has, when not all of 0..`STYLES`-1 |
| `FADE_STEP` | no | yes | The play view fades in inside the play loop |
| `G_TRIES` | no | `$1B(A5)` | The failed tries the access code counts, kept across the custom levels |
| `G_MUSIC` | no | `$1D(A5)` | The level tune's flag, cleared when the editor leaves or restarts a level |
| `BLIT_HEIGHT` | no | hunk 2 `$78F2` | The rows the blitter routine clips to; the object preview cuts them to the view's 160 |

Macros cover what differs in code: `RESUME_ENDED` (the instructions the hook
after a level replaced), `INTS_OFF`/`INTS_ON` (the editor's critical
sections: Lemmings runs in supervisor mode and masks the interrupts in SR,
Holiday Lemmings 1994 runs in user mode and uses INTENA's master bit) and
`STYLE_NAMES`.

Holiday-only sources: `src/holiday94.s` (start-up, the CUSTOM sign and the
title hooks) and `src/dos_file.s` (file access). Lemmings-only sources:
`src/bootstrap.s`, `src/title.s`, the track transport of `src/disk_io.s` and
`src/disk_codec.s`.

## The patched program

`patch.py` adds two hunks to the program:

| Hunk | Contents | Memory |
| --- | --- | --- |
| 0..3 | The game; its code hunk with the hook jumps | as before |
| 4 | The editor's code and data, then its storage, the Ground graphics of the edited level, the file buffers and the list of names (128K) | any |
| 5 | The status block's bitmap and copper list (3880 bytes) | chip |

**Relocations.** `src/game_holiday94.i` gives every game address as a hunk
base (`H1`, `H2`, `H3`, `H5`) plus an offset. `build.py` assembles the
editor with the bases at `$01000000`.. and once more with each base, and the
editor's origin (`EDITOR_ORG`), moved by `$10000000`: every longword that
follows a base is a relocation to its hunk, and any other difference stops
the build. The editor's own code is position independent; the two copper
words that hold the status block's address cannot be relocated and are set
when the editor is installed.

**Hooks.** `patch.py` writes 16 jumps into the game's code hunk, each after
checking the original bytes of the instructions it replaces, and removes
the relocations inside them. The editor's hook routines carry out the
replaced instructions and continue at the address after them:

| Site (hunk 2) | Replaced instructions | Editor |
| --- | --- | --- |
| `$0344` | `BSR TAKE_OVER` / `LEA GAME_ROWS,A4` | `holiday_start`: installs the editor, then the two |
| `$13B2` | raw key store / CIA handshake | `keyboard` |
| `$0482` | `BSR SWAP_BUFFERS` / `CLR.W G_FRAMES(A5)` | `frame` |
| `$04AE` | `BSR PLAY_MOUSE` / `BSR PLAY_KEYS` | `actions` |
| `$04B6` | `BSR PANEL_REFRESH` / `BSR MINIMAP_COLUMN` | `overlay` |
| `$22D0` | `BSR SELECT_STYLE` / `BSR INIT_SIMULATION` | `capture` |
| `$2254` | `LEA LEVEL_RECORD,A0` / `MOVE.W $1A(A0),D0` | `custom_inject` |
| `$3068` | `BSR BRIEF_TEXTS` / `BSR BRIEF_PREVIEW` (as JSR) | `custom_brief` |
| `$30B4` | `BSR WAIT_CLICK` / `LEA FADE_BLACK,A0` | `briefing_wait` |
| `$053A` | `CLR.B $1D(A5)` / `LEA ENDED_TEXTS,A1` | `custom_ended` |
| `$0590` | `CLR.B G_RESULT_SHOWN(A5)` / `MOVE.W G_LEVEL(A5),D0` | `custom_won` |
| `$06D8` | `LEA FADE_BLACK,A0` / `BSR FADE` | `custom_quit` |
| `$27A2` | `MOVE.W #$280,D0` / `MOVE.W #$D0,D1` (rating sign) | `title_sign` |
| `$301E` | `TST.B G_PANEL(A5)` / `BEQ.W` (PLAY) | `title_play` |
| `$2FF2` | `CMPI.W #$BC,D0` / `BLE.W` (NEW LEVEL) | `title_new` |
| `$3174` | `MOVE.W G_RATING(A5),D0` / `ADDQ.W #1,D0` (sign clicked) | `title_rating` |

**Disk.** The program grows from 143544 to 165296 bytes and replaces the
original on the disk; the directory `HolidayLemmings1994/Levels` is added.
Every changed block gets its checksum and the bitmap follows every
allocation; `patch.py` checks the whole file system before writing the
image. The patched disk has 744 free blocks, room for about 124 levels of
six blocks each.

## File access

Custom levels are `.lvl` files in the directory `Levels` of the current
directory: the game's own when it is started from its disk or from
Workbench. `src/dos_file.s` gives the custom level list, saving and
deleting the register interface of WHDLoad's `resload_LoadFile`,
`SaveFile`, `ListFiles`, `GetFileSize` and `DeleteFile`, so they are the same
code as in the WHDLoad version. Each call:

1. gives the hardware back to the system with the game's own routine, as
   the game's file reader does, and turns the system's requesters off (the
   process's `pr_WindowPtr` = -1);
2. makes its dos.library calls;
3. after a write or a deletion, has the file system write out its buffers
   and waits for it (`ACTION_FLUSH`), so that no disk transfer is under way
   when the game takes over;
4. turns the requesters back on and lets the game take the hardware over
   again.

A failed save reports a write-protected disk or, for any other error, that
the level could not be written; a failed write leaves no partial file. A
read that does not return the whole level record marks the level as
damaged, and a deletion the system refuses is reported.

Limits: saving over an existing level replaces the file, so a write that
fails leaves neither version on the disk (the level stays in the editor and
can be saved again); requesters that a file system raises itself (not
through dos.library) are not suppressed and would open behind the game's
display; an error that only closing the file would report is not seen.

## Display

The play view has two buffers of four planes, 44 bytes x 192 rows each,
shown 160 rows high. In Holiday Lemmings 1994 the skill panel's first
bitplane (hunk 1 `$10800`) follows the second buffer's fourth plane from its
row 176. The editor therefore clears only the view's 160 rows when it draws
a menu, and draws the object preview with the blitter routine's surface cut
to those rows (`BLIT_HEIGHT`). The play view fades in inside the play loop
(`FADE_STEP`); the editor lets the fade end before a menu keeps the level's
colours.

## Memory

At the title screen of an emulated A500 with 512K chip and 512K slow memory
(Kickstart 1.3), with the editor installed: 150152 bytes of other memory and
34944 bytes of chip memory free. The editor needs the 128K of hunk 4 in one
piece of any memory.
