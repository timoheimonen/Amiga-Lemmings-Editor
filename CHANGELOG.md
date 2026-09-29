# Changelog

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
