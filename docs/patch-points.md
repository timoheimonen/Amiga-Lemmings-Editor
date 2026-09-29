# Patch points

What `patch.py` changes on the disks, and which game code the editor hooks at
run time. Addresses are runtime addresses; the game's main program `Code` is
loaded at `$400`, so its file offset is the address minus `$400`.

## Disk changes

| Disk | Change |
| --- | --- |
| 1 | `Code` grows by the bootstrap (78 bytes, loaded at `$21B4C`) and gets two jump hooks. The files after it shift by the same amount and the directory is rewritten. Everything from `$CA000` on (boot loader) is unchanged. |
| 2 | A new file `Editor` is added after the last existing file (`$D9E28`). All other files are unchanged. |

Both disks use the game's own directory format, see
[game-internals.md](game-internals.md#disk-directory).

## Hooks written by patch.py

Each hook replaces exactly 8 bytes with `JMP addr.L` + `NOP`. `patch.py`
checks the original bytes first and refuses to patch if they differ.

| Address | Original bytes | Original code | Jumps to | Purpose |
| --- | --- | --- | --- | --- |
| `$3916` | `D3F8 0008 2B49 00F8` | `ADDA.L 8.W,A1` / `MOVE.L A1,$F8(A5)` | `reserve` | Lower the end of the file cache by 128K so the top of slow RAM is kept for the editor |
| `$548` | `6100 37FE 6100 2730` | `BSR $3D48` / `BSR $2C7E` | `load_editor` | Load `Editor` from disk 2 into the reserved block and run its installer, then continue to the menu |

`reserve` returns to `$391E`, `load_editor` to `$550`. Both do the displaced
work themselves. If the game's slow-RAM allocation is smaller than
`$24000` bytes, nothing is reserved or loaded and the game runs as normal.

## Hooks installed by the editor

The editor's `install` routine writes the same `JMP` + `NOP` pattern into the
loaded program. All of them run the displaced original code.

| Address | Hook | Purpose |
| --- | --- | --- |
| `$174E..$1759` | `keyboard` | Keyboard interrupt: queue presses of E, F and the cursor keys, then the original CIA acknowledge |
| `$654..$65B` | `frame` | Start of every game frame: editor toggle, brush input, painting, and skipping the redraw when nothing changed |
| `$680..$687` | `actions` | Gameplay mouse and keyboard actions; skipped while the editor is open |
| `$688..$68F` | `overlay` | End of frame drawing: panel and minimap, then brush preview and status block before the frame is shown |
| `$2762..$2769` | `capture` | Level setup: reset the editor and keep a copy of the level's terrain graphics |

## Game routines called by the editor

| Address | Routine |
| --- | --- |
| `$280A` | Level style setup |
| `$2826` | Level simulation setup |
| `$3286` | Load a file by name from disk |
| `$3934` | Unpack a packed resource |
| `$1898` | Swap the viewport buffers |
| `$1F52` | Refresh the skill panel |
| `$4AA4` | Draw one minimap terrain column |
| `$4A78` | Refresh the minimap |
| `$4B3A` | Clear the collision guard rows at the top and bottom of the level |
| `$1862` | Convert a number to decimal digits |
| `$B4A`, `$14E2` | Gameplay mouse and keyboard actions |
