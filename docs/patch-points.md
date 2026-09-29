# Patch points

What `patch.py` changes on the disks, and which game code the editor hooks at
run time. Addresses are runtime addresses; the game's main program `Code` is
loaded at `$400`, so its file offset is the address minus `$400`.

## Disk changes

| Disk | Change |
| --- | --- |
| 1 | `Code` grows by the bootstrap (222 bytes, loaded at `$21B4C`) and gets three jump hooks. The files after it shift by the same amount. A new file `Editor2` (the packed disk code of the editor) is added after the last file, and the directory is rewritten. Everything from `$CA000` on (boot loader) is unchanged. |
| 2 | A new file `Editor` (the packed rest of the editor) is added after the last existing file (`$D9E28`). All other files are unchanged. |

The editor image is split at the `editor2_start` label because neither disk
has room for all of it. Both files are packed in the format of the game's own
unpacker (`$3934`) and unpack into one contiguous image in the editor block.

Both disks use the game's own directory format, see
[game-internals.md](game-internals.md#disk-directory).

## Hooks written by patch.py

The hooks at `$3916` and `$548` replace 8 bytes with `JMP addr.L` + `NOP`; the
hook at `$50A` replaces 6 bytes with `JMP addr.L`. `patch.py` checks the
original bytes first and refuses to patch if they differ.

| Address | Original bytes | Original code | Jumps to | Purpose |
| --- | --- | --- | --- | --- |
| `$3916` | `D3F8 0008 2B49 00F8` | `ADDA.L 8.W,A1` / `MOVE.L A1,$F8(A5)` | `reserve` | Lower the end of the file cache by 128K so the top of slow RAM is kept for the editor |
| `$50A` | `6100 3762 4A40` | `BSR $3C6E` / `TST.W D0` | `load_editor2` | While disk 1 is still in a drive, find it through the game's disk loader (`$7FB2`) and load and unpack `Editor2`; then run the game's own search for disk 2 |
| `$548` | `6100 37FE 6100 2730` | `BSR $3D48` / `BSR $2C7E` | `load_editor` | Load `Editor` from disk 2 into the reserved block and run its installer, then continue to the menu |

`reserve` returns to `$391E`, `load_editor2` to `$510` and `load_editor` to
`$550`. All do the displaced work themselves. If the game's slow-RAM
allocation is smaller than `$24000` bytes, nothing is reserved or loaded and
the game runs as normal. `load_editor` installs the editor only if `Editor2`
was loaded successfully.

## Hooks installed by the editor

The editor's `install` routine writes the same `JMP` + `NOP` pattern into the
loaded program. All of them run the displaced original code.

| Address | Hook | Purpose |
| --- | --- | --- |
| `$174E..$1759` | `keyboard` | Keyboard interrupt: queue presses of E, F, S, L and the cursor keys, and all keys while the save/load menu is open; Esc cancels a disk operation; then the original CIA acknowledge |
| `$654..$65B` | `frame` | Start of every game frame: editor toggle, brush input, painting, the save/load menu, and skipping the redraw when nothing changed |
| `$680..$687` | `actions` | Gameplay mouse and keyboard actions; skipped while the editor is open |
| `$688..$68F` | `overlay` | End of frame drawing: panel and minimap, then brush preview and status block before the frame is shown |
| `$2762..$2769` | `capture` | Level setup: reset the editor and keep a copy of the level's terrain graphics |
| `$2A4E..$2A55` | `replay_hook` | After the level's terrain is built: replay the placements of a loaded save, then the original minimap update and collision guard cleanup |
| `$3502..$3509` | `briefing_wait` | Skip the briefing click wait when a loaded save restarts the level, so it returns straight to the editor |

## Game routines called by the editor

| Address | Routine |
| --- | --- |
| `$280A` | Level style setup |
| `$2826` | Level simulation setup |
| `$3286` | Load a file by name from disk (through the file cache) |
| `$7FB2` | Disk loader: find a game disk by its first file name, load a file (bootstrap only) |
| `$3C6E` | Find disk 2 (bootstrap only, displaced by `load_editor2`) |
| `$3D48`, `$2C7E` | Start-up steps displaced by `load_editor` |
| `$3934` | Unpack a packed resource |
| `$1898` | Swap the viewport buffers |
| `$1F52` | Refresh the skill panel |
| `$4AA4` | Draw one minimap terrain column |
| `$4A78` | Refresh the minimap |
| `$4B3A` | Clear the collision guard rows at the top and bottom of the level |
| `$1862` | Convert a number to decimal digits |
| `$B4A`, `$14E2` | Gameplay mouse and keyboard actions |
| `$18DE` | Wait for a mouse click (briefing) |
| `$1AE0`, `$17268` | Level shutdown steps, called as in the game's own level exit (`$6E2..$704`) |
| `$2632` | Load the selected level (used to restart it with a loaded save) |
| `$56A` | Continue the game's normal level start (briefing and play) |

The save disk itself is read and written by the editor's own disk code
(`src/disk_io.s`, `src/disk_codec.s`) directly through the disk hardware; the
game's loader cannot write.
