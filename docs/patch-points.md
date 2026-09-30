# Patch points

What `patch.py` changes on the disks, and which game code the editor hooks at
run time. Addresses are runtime addresses; the game's main program `Code` is
loaded at `$400`, so its file offset is the address minus `$400`.

## Disk changes

| Disk | Change |
| --- | --- |
| 1 | `Code` grows by the bootstrap (174 bytes, loaded at `$21B4C`) and gets three jump hooks. The files after it shift by the same amount, and the directory is rewritten. Two entries follow the files: `BootLoader`, a placeholder from the end of the files to `$CFA00`, and `Editor` (the packed editor) at `$CFA00`. The boot block and everything from `$CA000` to `$CF9FF` (boot loader and packed boot intro) are unchanged. |
| 2 | Unchanged. |

Tracks 151..159 of disk 1 (`$CFA00` to the end of the disk) are read neither
by the boot chain nor by the game. The game's disk loader computes a file's
offset from the lengths of the entries before it, so the placeholder, whose
bytes are the unchanged boot loader, puts `Editor` at `$CFA00`, and the loader
reads it by name like any other file. `Editor` is packed in the format of the
game's own unpacker (`$3934`).

Both disks use the game's own directory format, see
[game-internals.md](game-internals.md#disk-directory).

## Hooks written by patch.py

The hooks at `$3916` and `$548` replace 8 bytes with `JMP addr.L` + `NOP`; the
hook at `$50A` replaces 6 bytes with `JMP addr.L`. `patch.py` checks the
original bytes first and refuses to patch if they differ.

| Address | Original bytes | Original code | Jumps to | Purpose |
| --- | --- | --- | --- | --- |
| `$3916` | `D3F8 0008 2B49 00F8` | `ADDA.L 8.W,A1` / `MOVE.L A1,$F8(A5)` | `reserve` | Lower the end of the file cache by 128K so the top of slow RAM is kept for the editor |
| `$50A` | `6100 3762 4A40` | `BSR $3C6E` / `TST.W D0` | `load_editor` | While disk 1 is still in a drive, find it through the game's disk loader (`$7FB2`), load `Editor` into the reserved block and unpack it; then run the game's own search for disk 2 |
| `$548` | `6100 37FE 6100 2730` | `BSR $3D48` / `BSR $2C7E` | `install_editor` | Run the editor's installer after the level metadata, then continue to the title screen |

`reserve` returns to `$391E`, `load_editor` to `$510` and `install_editor` to
`$550`. All do the displaced work themselves. If the game's slow-RAM
allocation is smaller than `$24000` bytes, nothing is reserved or loaded and
the game runs as normal. `install_editor` installs the editor only if
`Editor` was loaded and unpacked successfully.

## Hooks installed by the editor

The editor's installer writes the same `JMP` + `NOP` pattern into the loaded
program (at `$34AA` a `JSR`). Every hook runs the displaced original code
itself, or skips it where noted.

Level and editor:

| Address | Hook | Purpose |
| --- | --- | --- |
| `$174E..$1759` | `keyboard` | Keyboard interrupt: queue the editor's key presses; while a custom level is edited, Esc goes to the editor, not to the game's Esc action; then the original CIA acknowledge |
| `$654..$65B` | `frame` | Start of every game frame: editor input, modes, painting, the menu, and skipping the redraw when nothing changed |
| `$680..$687` | `actions` | Gameplay mouse and keyboard actions; skipped while the editor is open |
| `$688..$68F` | `overlay` | End of frame drawing: panel and minimap, then the preview, outlines and status block, then the display swap |
| `$2762..$2769` | `capture` | Level setup: reset the editor; for a level being edited, load the style's `Ground` graphics for the brush and open the editor at the first frame |

Title screen and custom levels:

| Address | Hook | Purpose |
| --- | --- | --- |
| `$2CCA..$2CD1` | `title_sign` | Draw the CUSTOM rating sign |
| `$35CA..$35D1` | `title_up` | The up arrow at MAYHEM selects CUSTOM |
| `$35FC..$3603` | `title_down` | The down arrow in CUSTOM returns to MAYHEM |
| `$33C0..$33C7` | `title_click` | In CUSTOM, 1 Player opens the custom level list, 2 Player the list of the levels for two players and New Level the style choice for a new level |
| `$26E6..$26EF` | `custom_inject` | Level loading: copy the custom level's record to `$C5A6`, so the style, graphics and everything after it come from the custom level |
| `$34AA..$34B1` | `custom_brief` | Briefing: the list number in "Level", the rating `Custom`, and `;` for `:` in the title |
| `$3502..$3509` | `briefing_wait` | Skip the briefing's click wait for a level being edited or test played |
| `$706..$70D` | `custom_ended` | After a level has been torn down: when the editor was left with Esc, return to the list without a result screen |
| `$760..$767` | `custom_won` | Enough rescued: no next level or access code; back to the list, or after a test play back to the editor |
| `$818..$821` | `custom_quit` | Right button after a failed level: back to the list, or after a test play back to the editor |
| `$918..$91F` | `custom_match` | Two players, after the level's win has been counted: a custom level is a match of one level, so show the winner (`$96A`) instead of the next level and its access code |
| `$9BE..$9C5` | `custom_match_end` | End of a two-player match: back to the list instead of the title screen |

The game's rating stays at MAYHEM while CUSTOM is shown, so nothing else in
the game sees a new rating. The original levels play exactly as before;
the hooks act only on custom levels.

## Game routines called by the editor

| Address | Routine |
| --- | --- |
| `$7FB2` | Disk loader: find a game disk by its first file name, load a file (bootstrap only) |
| `$3C6E`, `$3D48`, `$2C7E` | Start-up steps displaced by the bootstrap; `$2C7E` also reloads `Icons` after a level, as the game does |
| `$3934` | Unpack a packed resource |
| `$3286` | Load a file by name (the style's `Ground` graphics) |
| `$2632` | Load the selected level (with `custom_inject`: the custom level) |
| `$280A`, `$2826` | Level style setup, level simulation setup |
| `$24FE`, `$2476` | Rebuild the attribute grid: steel areas, then the trigger areas of the first 16 objects |
| `$56A`, `$554` | Continue the game's level start (briefing and play); back to the title screen |
| `$1B10`, `$3510`, `$3522` | Steps of the game's own 1 Player and 2 Player starts (`$3460..$3488`, `$342C..$3450`): `$3510` loads the one-player panel, `$3522` the two-player one |
| `$1AE0`, `$17268` | Level shutdown steps, as in the game's own level exit (`$6E2..$704`); `$17268` stops the music |
| `$1598` | The game's Esc action (end the level) |
| `$B4A`, `$14E2` | Gameplay mouse and keyboard actions |
| `$1898` | Swap the viewport buffers |
| `$1F52` | Refresh the skill panel |
| `$4AA4`, `$4A78` | Draw one minimap terrain column; refresh the minimap |
| `$4B3A` | Clear the collision guard rows at the top and bottom of the level |
| `$7014`, `$704C` | Set the blitter destination; draw an object frame |
| `$2CCA` | Draw the rating sign |
| `$2BA2`, `$4B58` | Briefing texts and level preview |
| `$82A`, `$36E4`, `$18DE` | Result comment, "Press mouse button to continue", wait for a click |
| `$19E4`, `$1CD4`, `$15E4`, `$196A` | Text screen: fade rows to palettes, background texture, text in the game's font, wait for the vertical blank |
| `$1862` | Convert a number to decimal digits |

The level disk itself is read and written by the editor's own disk code
(`src/disk_io.s`, `src/disk_codec.s`) directly through the disk hardware;
the game's loader cannot write.
