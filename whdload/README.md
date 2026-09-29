# Lemmings In-Game Level Editor for WHDLoad

The editor and its save/load menu, installed to a hard disk and started with
[WHDLoad](https://www.whdload.de/). The game and the editor behave as on
floppy; saves go to a save disk image file instead of a floppy.

## Requirements

- Kickstart 2.0 or later (tested with Kickstart and Workbench 3.1), WHDLoad
  installed (tested with WHDLoad 20.0)
- 512K chip memory for the game and about 1.4 MiB of other memory: 512K for
  the game's file cache and the editor, 880K for the save disk image
- Tested on an emulated A1200 (68020, AGA, 2 MiB chip + 4 MiB fast)

## Install

```sh
python3 patch.py "Disk 1.adf" "Disk 2.adf" --whdload out/Lemmings
```

Copy the `Lemmings` directory to the Amiga, for example into a `Games` drawer.
It contains:

| File | Contents |
| --- | --- |
| `Lemmings.slave` | The WHDLoad slave |
| `Disk.1`, `Disk.2` | The disk images, patched with the WHDLoad version of the editor |
| `Lemmings.info` | Workbench icon: default tool `WHDLoad`, tool types `SLAVE=Lemmings.slave`, `PRELOAD`, and the disabled `(NOWRITECACHE)` and `(WRITEDELAY=25)` |

Double-click the icon, or from a shell:

```sh
cd Games/Lemmings
WHDLoad Lemmings.slave PRELOAD
```

**F10** quits back to Workbench (WHDLoad's `QuitKey` option changes it).

## Saves

The save disk is the file `Lemmings_SaveDisk.adf` in the install directory.
The first time **S** or **L** is pressed in the editor without it, the menu
offers to create an empty one. It has exactly the format of a floppy save
disk, so it works with `savedisk.py`, can be written to a floppy for the
floppy version, and saves can be exchanged with other users. Drive selection
and disk swaps do not exist in this version.

By default WHDLoad keeps written files in memory and writes them to the hard
disk when it quits. **Leave the game with the quit key** before switching off
or resetting, or the saves of the session are lost.

To write every save at once instead, select the icon, choose Information from
the Workbench menu and remove the parentheses around the tool types:

| Tool types | Saving | Display during a save |
| --- | --- | --- |
| `PRELOAD` (default) | To the hard disk when WHDLoad quits | No noticeable pause |
| `PRELOAD` `NOWRITECACHE` | At once | Blanked for about 6 s (WHDLoad waits 3 s after each of two writes) |
| `PRELOAD` `NOWRITECACHE` `WRITEDELAY=25` | At once | Blanked for about 2 s; a reset right after a save may leave the file incomplete |

`WRITEDELAY` is in 1/50 s; WHDLoad waits that long after every write so the
file system can finish. Times are from an emulated A1200.

If a write fails (for example a full or write-protected volume), WHDLoad ends
the game with an error requester.

## How it works

- `src/slave.s` loads the game's main program from `Disk.1`, replaces the
  game's floppy loader with reads from the disk images, gives the game's file
  cache the expansion memory and adds the quit key. The editor is then loaded
  by its bootstrap exactly as from floppy.
- `src/disk_file.s` replaces the editor's floppy transport when the editor is
  assembled with `WHDLOAD` defined. The whole save disk image is kept in
  memory: it is loaded once, a changed track is written back with one call, a
  new disk with one call. Every file access switches WHDLoad to the operating
  system for a moment, which blanks the display.
- `src/whdload_api.i` holds the few WHDLoad interface values the slave uses,
  from the WHDLoad autodoc; WHDLoad's own include files are not needed.
- `build.py` assembles the slave and writes the install from disk images
  patched with the WHDLoad version of the editor.

Details: [patch points](docs/patch-points.md) and
[memory map](docs/memory-map.md).
