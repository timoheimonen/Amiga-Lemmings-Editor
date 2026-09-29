# Changelog

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
