# Changelog

## V2.1.1

- Saving no longer writes over a level of another level disk: when the level
  disk in the drive holds a different level in the edited level's place, the
  editor says so and writes nothing.
- Levels with a special background (possible from a `.lvl` file) no longer
  take terrain pieces from the brush; such pieces could be neither saved,
  undone nor deleted.
- The level checks follow the game: empty object slots of type 1 count
  towards the four entrances (more crashed the game), the two-player marker
  is the first slot of type 2 even when it is empty, and object positions
  must be within -4096..4095 (an object far to the right hung the editor).
  `savedisk.py` applies the same checks.
- WHDLoad: the custom level list no longer crashes a 68000 (A600, A500+)
  when `Levels` holds more than one level. File names of up to 107
  characters are kept when a level is saved (longer ones were cut to 31
  characters); with more than 318 levels the first 318 by name are listed;
  a new level never overwrites an existing file.
- A title of spaces only is not accepted.
- An object dropped over the panel goes back to its place instead of
  vanishing below the view.
- A steel area dragged over more than 16 cells is cut at the cell where the
  drag began, as its outline shows.
- Floppy: Esc while the drives are searched cancels the save; disk 2 is
  checked before the menu closes whenever its drive held another disk; a
  track that does not read is read again, up to three times; a new level
  passes over a slot left by an interrupted save; the level disk also works
  with 32-bit addressing (accelerator cards).
- Opening the menu ends a drag and drops keys pressed together with S or
  N; Shift is followed also during disk access.
- Undo: changing a parameter and changing it back no longer loses the
  oldest step.
- Leaving the custom level list keeps the title screen's level, for example
  a MAYHEM level entered with its code.
- Floppy: the briefing and the status block show the level's number as the
  list does (its place on the level disk); the music follows that number.
- Negative coordinates are shown with a minus sign, and the preview shows at
  once when the editor reopens after a test play.

## V2.1

- Undo and redo in the editor: `U` undoes the last edit, Shift+`U` redoes
  it, three steps. Every kind of edit can be undone: terrain pieces, steel
  areas, objects (including the two-player marker), the parameters and the
  title. The history survives test plays and saving; it is cleared when
  another level is opened.
- Deleting whole terrain pieces: in the erasing mode, Shift held hides the
  brush and outlines the piece under the cursor; the left button deletes it
  and frees its place among the 399 pieces. Erasing pieces (tunnels) can be
  deleted too, which gives the terrain back.
- The key help of the terrain mode follows the brush: `RMB: Add/Erase`
  while adding, `RMB: Add  Shift: Del` while erasing.
- WHDLoad: the install's icon sets `NOWRITECACHE`, so a saved level is
  written to the hard disk at once instead of when WHDLoad quits; the display
  is blanked for about three seconds while WHDLoad writes. Switching off or
  resetting without the quit key no longer loses the levels saved in the
  session.
- After a save, snap also finds the pieces placed before the save.

## V2.0

Version 2 is a separate line: custom levels instead of editing the original
ones. V1.x continues on the `v1-maint` branch.

- CUSTOM on the title screen, after MAYHEM. 1 Player lists the custom
  levels and plays them through the game's own level start, briefing and
  result screens; New Level starts a new level in one of the five graphics
  styles.
- Two players: 2 Player in CUSTOM lists the levels made for two players
  (an entrance, exits and the marker object beside the green player's exit)
  and plays them in the game's own two-player mode, one level per match. In
  the editor `M` puts the marker at an exit and the status block shows
  whether the level is for two players; New Level has templates for two
  players.
- The editor opens a custom level paused at its start and edits everything
  a level holds: terrain pieces (add, erase, flip, behind), steel areas,
  objects (entrances, exits, traps, decorations, with their drawing modes),
  the parameters (release rate, lemmings, to save, time, skills, start
  position) and the title, within the game's own limits.
- `E` test plays the current edits from the start and returns to the editor.
- `G` snap joins new and moved pieces and objects to the nearest one of the
  same kind, by their visible edges.
- Esc leaves the editor for the list and asks first when the level has
  unsaved changes.
- Levels are saved on a level disk (318 levels) on floppy and as `.lvl`
  files in the directory `Levels` under WHDLoad. A `.lvl` file is the
  game's 2048-byte level record and can be shared freely.
- `savedisk.py` creates level disks, lists and checks them, and imports,
  exports and deletes levels (`.lvl`); `styles.json` holds the limits of the
  five styles.
- Only disk 1 is patched: the whole editor is one file on tracks 151..159,
  behind the boot loader. Disk 2 stays unchanged. With one drive the list
  asks for disk 2 before a level starts and before it returns to the title
  screen, because the game reads its files from whichever disk is in the
  drive.
- Removed: the in-level editor for the original levels, its save/load menu
  and save disk support (they remain in V1.x). A V1.x save disk is
  recognised and never written to.

The entries below are the V1.x line.

## V1.2.1

- The WHDLoad slave accepts only the disk images written with it by
  `patch.py --whdload`. Disk images of the floppy version or of another
  version end with WHDLoad's "wrong version" requester instead of starting a
  game whose save menu would try to use the floppy drive.

## V1.2

- WHDLoad install: `patch.py --whdload DIR` writes a slave, the patched disk
  images and a Workbench icon. Runs from hard disk on Kickstart 2.0 or later
  (tested on an A1200 with Kickstart and Workbench 3.1); F10 quits.
- Under WHDLoad, saves go to the save disk image file `Lemmings_SaveDisk.adf`
  in the install directory, in the same format as a floppy save disk.
- The floppy version is unchanged apart from the version number; V1.1 save
  disks and saves work in both versions.

## V1.1

- Save and load: up to 32 named saves per level on a separate save disk,
  318 per disk. `S` and `L` in the editor open the menu for the current level.
- Loading a save restarts the level with the saved terrain.
- The menu pages through saves, works with keys and mouse, asks before
  replacing, deleting or loading, and can rebuild the save index.
- Works with one or two drives: asks for the save disk and for disk 2 again,
  refuses the game disks, and can initialize a new save disk.
- `savedisk.py`: create, list, check, export and import save disk images on a
  PC or Mac.
- The editor is loaded in two parts (`Editor` on disk 2, `Editor2` on disk 1).

## V1.0

- Initial release.
