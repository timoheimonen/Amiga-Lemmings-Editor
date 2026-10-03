# Lemmings Integrated Level Editor for WHDLoad

The custom level editor, installed to a hard disk and started with
[WHDLoad](https://www.whdload.de/), for Lemmings and for Holiday Lemmings
1994. The game and the editor behave as on floppy; custom levels are `.lvl`
files in the install's directory `Levels` instead of a level disk.

## Requirements

- Kickstart 2.0 or later (tested with Kickstart and Workbench 3.1), WHDLoad
  17 or later installed (tested with WHDLoad 20.0)
- Lemmings: 512K chip memory for the game and 512K of other memory for the
  game's file cache and the editor
- Holiday Lemmings 1994: 512K chip memory for the game and 384K of other
  memory for the rest of the game, the editor and the game's icons
- Tested on an emulated A1200 (68020, AGA, 2 MiB chip + 4 MiB fast) and an
  emulated A600-class machine (68000, ECS, Kickstart 3.1)

## Install

Lemmings, from its two disk images:

```sh
python3 patch.py "Disk 1.adf" "Disk 2.adf" --whdload out/Lemmings
```

| File | Contents |
| --- | --- |
| `Lemmings.slave` | The WHDLoad slave |
| `Disk.1` | Disk 1, patched with the WHDLoad version of the editor |
| `Disk.2` | Disk 2, unchanged |
| `Lemmings.info` | Workbench icon (see [Saving levels](#saving-levels)) |
| `Levels` | Directory for custom levels (`.lvl` files); keep it, even when empty |

Holiday Lemmings 1994, from its disk image:

```sh
python3 patch.py "Holiday Lemmings 1994.adf" --whdload out/HolidayLemmings1994
```

| File | Contents |
| --- | --- |
| `HolidayLemmings1994.slave` | The WHDLoad slave |
| `data` | The game's files from the disk; its program `HolidayLemmings1994` patched with the WHDLoad version of the editor |
| `HolidayLemmings1994.info` | Workbench icon (see [Saving levels](#saving-levels)) |
| `Levels` | Directory for custom levels (`.lvl` files); keep it, even when empty |

Copy the directory to the Amiga, for example into a `Games` drawer, and
double-click the icon, or from a shell:

```sh
cd Games/Lemmings
WHDLoad Lemmings.slave PRELOAD NOWRITECACHE
```

**F10** quits back to Workbench (WHDLoad's `QuitKey` option changes it). In
Holiday Lemmings 1994 the title screen's QUIT quits too; the game's suspend
key does nothing under WHDLoad.

## Custom levels

Lemmings: on the title screen, step the difficulty sign past MAYHEM to CUSTOM
with its up arrow and click 1 Player. Holiday Lemmings 1994: click the rating
sign until it shows CUSTOM, after BLIZZARD, and click PLAY. The list shows the
custom levels, the `.lvl` files in the `Levels` directory, sorted by file
name. A `.lvl` file is a level in the Amiga game's own 2048-byte format;
files that are not exactly one valid level are listed as damaged. A click or
Return plays the selected level, E edits it, and Del deletes its file after
asking (only Return confirms; a deleted level cannot be brought back); the
right mouse button or Esc returns to the title screen. New Level in CUSTOM
starts a new level in one of the game's graphics styles (Lemmings: five, for
one or for two players; Holiday Lemmings 1994: Brick and Snow).

In Lemmings, 2 Player lists the levels that are valid for two players and
plays them in the game's two-player mode, one level per match (reading every
file when the list opens). Holiday Lemmings 1994 has no two-player mode.

The editor opens at the start of the level. E test plays the level from its
start and returns to the editor; T, O and P switch between the terrain, steel
areas, objects and parameters; the right button switches the terrain brush
between adding and erasing, and with Shift held while erasing the left button
deletes the outlined piece; U undoes the last edit and Shift+U redoes it
(three steps); N changes the title and S saves the level into
its file (a new level as the first free `LevelNNN.lvl`). The status block
below the panel shows the keys of each mode.

## Saving levels

The icon's tool types are `SLAVE=` the slave, `PRELOAD`, `NOWRITECACHE` and
the disabled `(WRITEDELAY=25)`. `NOWRITECACHE` makes WHDLoad write every saved
level to the hard disk at once. WHDLoad then waits `WRITEDELAY` (default 150,
that is 3 seconds) so the file system can finish, and the display is blanked
for that time. When the screen comes back, the level is on the hard disk.

Without `NOWRITECACHE`, for example when a launcher starts the slave without
the icon's tool types, WHDLoad keeps written files in memory and writes them
to the hard disk only when it quits. Then **leave the game with the quit key**
(or QUIT) before switching off or resetting, or the levels saved in the
session are lost. A launcher can pass `NOWRITECACHE` itself, and
`S:WHDLoad.prefs` can set it for all installs.

To change the behaviour, select the icon, choose Information from the
Workbench menu and edit the tool types; a tool type in parentheses is
disabled:

| Tool types | Saving | Display during a save |
| --- | --- | --- |
| `PRELOAD` `NOWRITECACHE` (default) | At once | Blanked for a few seconds while WHDLoad writes |
| `PRELOAD` `NOWRITECACHE` `WRITEDELAY=25` | At once | Blanked for a shorter time; a reset right after a save may leave the file incomplete |
| `PRELOAD` `(NOWRITECACHE)` | To the hard disk when WHDLoad quits | No noticeable pause |

`WRITEDELAY` is in 1/50 s; WHDLoad waits that long after every write so the
file system can finish.

Deleting a level (Del in the list) follows the same tool types: with
`NOWRITECACHE` the file is deleted from the hard disk at once, after the same
wait; without it the list no longer shows the file, but WHDLoad deletes it
from the hard disk only when it quits.

If a write fails (for example a full or write-protected volume), WHDLoad ends
the game with an error requester.

## How it works

- `src/slave.s` (Lemmings) loads the game's main program from `Disk.1`,
  replaces the game's floppy loader with reads from the disk images, gives the
  game's file cache the expansion memory and adds the quit key. The editor is
  then loaded by its bootstrap exactly as from floppy.
- `src/holiday94_slave.s` (Holiday Lemmings 1994) loads the game's program,
  which carries the editor as two more hunks, from `data` and relocates it:
  the chip memory hunks into the base memory, the others into the expansion
  memory. It does the start-up's work that needs the operating system, reads
  the game's files from `data` through WHDLoad, and turns the game's ways back
  to the system (QUIT, suspend) into a quit.
- `src/disk_file.s` is the editor's file access when it is assembled with
  `WHDLOAD` defined: the editor lists, reads, writes and deletes the `.lvl`
  files through WHDLoad. Every file access switches WHDLoad to the operating
  system for a moment, which blanks the display.
- `src/whdload_api.i` holds the few WHDLoad interface values the slaves use,
  from the WHDLoad autodoc; WHDLoad's own include files are not needed.
- `build.py` assembles the slave of an install and writes the install from
  the disk images patched with the WHDLoad version of the editor.

Each slave accepts only the files of its own build and ends with WHDLoad's
"wrong version" requester otherwise.

Details: [patch points](docs/patch-points.md) and
[memory map](docs/memory-map.md).
