# Memory map

Memory used by the editor on an A500 with 512K chip and 512K slow RAM.

## Editor block (slow RAM)

The top 128K (`$20000` bytes) of the game's slow-RAM file cache. The address
is taken from the game's own allocation at start-up and stored at `$F8(A5)`;
it is not fixed.

| Offset | Size | Contents |
| --- | --- | --- |
| `+$0000` | < `$7000` | Editor image (both parts, position independent) followed by its zero-initialized state, font and placement list |
| `+$7000` | | Staging area: a packed editor file is loaded here during start-up and unpacked to `+$0000` |
| `+$8000` | up to 42200 bytes | Unpacked `GroundN` terrain graphics of the current level |
| `+$12800..+$1703A` | | Disk buffers: decoded track, verify track, save-disk track 0, menu rows and index rebuild |

`build.py` checks this layout from the assembler's symbols. The raw MFM track
buffer for save-disk reads and writes is the non-displayed viewport buffer in
chip RAM, borrowed while the level is paused.

Slow RAM is not reachable by the blitter, so the editor draws pieces with the
CPU.

## Chip RAM workspace

Between the end of the game program and the game's display memory.

| Range | Contents |
| --- | --- |
| `$21B4C..$21C29` | Bootstrap (only used during start-up) |
| `$21D00..$22BFF` | Status block bitmap: 640x48, one hires plane, 80 bytes per row |
| `$22C00..$22C23` | Copper list continuation for the status block |
| `$23680..` | Game display memory (unchanged) |

## Game surfaces the editor draws into

| Surface | Address | Layout |
| --- | --- | --- |
| Level terrain | `$37080` | 1632x168 pixels, 4 planes, 204 bytes per row, planes `$85E0` apart. Plane 4 is the collision plane. |
| Viewport back buffer | pointer at `$CC(A5)` | 4 planes, 44 bytes per row, planes `$2100` apart; visible x 16..335, y 0..159 |

Level coordinates include 16 pixels of padding on the left and 4 rows at the
top: level x = cursor x + scroll x + 16, level y = cursor y + 4.

## Display

The status block is shown by redirecting the end of the game's copper list
(`$8668`) to the continuation at `$22C00`, and by moving the display window
stop (`$84EE`) from `$F4C1` to `$24C1`, which adds 48 lines below the skill
panel. Both are restored when the editor closes or a level loads. This needs a
PAL display.

The save/load menu is drawn with the editor's font into the displayed viewport
buffer over the paused level. While it is open it replaces the level view's
colours 0..4, whose values are the copper moves at `$850E + 4n`, and restores
them when it closes.
