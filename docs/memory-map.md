# Memory map

Memory used by the editor on an A500 with 512K chip and 512K slow RAM.

## Editor block (slow RAM)

The top 128K (`$20000` bytes) of the game's slow-RAM file cache. The address
is taken from the game's own allocation at start-up and stored at `$F8(A5)`;
it is not fixed.

| Offset | Size | Contents |
| --- | --- | --- |
| `+$0000` | < `$B000` | Editor image (position independent) followed by its zero-initialized state: the edited level record, placements, font, list of custom levels, undo history |
| `+$B000` | | Staging area: the packed `Editor` is loaded here during start-up and unpacked to `+$0000` |
| `+$B000` | up to 42200 bytes | Afterwards: the unpacked `GroundN` terrain graphics of the level being edited |
| `+$15800..+$199FF` | 3 x 5632 bytes | Floppy: decoded disk tracks (the track read or to be written, the read-back of a write, the level disk's track 0) |
| `+$1A100..+$1FEFF` | | WHDLoad: the file names of the `Levels` directory |

`build.py` checks this layout from the assembler's symbols. The raw MFM
track buffer for level disk reads and writes is chip memory the game is not
using at that moment: in a level the non-displayed viewport buffer, borrowed
while the level is paused; on the title screen and in the list the game's
own raw track buffer at `$58800`, which is idle there (in a level it holds
the attribute grid).

Slow RAM is not reachable by the blitter, so the editor draws terrain pieces
with the CPU.

## Chip RAM workspace

Between the end of the game program and the game's display memory.

| Range | Contents |
| --- | --- |
| `$21B4C..$21BF9` | Bootstrap (only used during start-up) |
| `$21D00..$22BFF` | Status block bitmap: 640x48, one hires plane, 80 bytes per row |
| `$22C00..$22C27` | Copper list continuation for the status block |
| `$23680..` | Game display memory (unchanged) |

## Game memory the editor uses

| Surface | Address | Layout |
| --- | --- | --- |
| Level record | `$C5A6` | 2048 bytes, see [game internals](game-internals.md#level-record); steel areas and title are also read from `$CD06` |
| Level terrain | `$37080` | 1632x168 pixels, 4 planes, 204 bytes per row, planes `$85E0` apart. Plane 4 is the collision plane. |
| Viewport back buffer | pointer at `$CC(A5)` | 4 planes, 44 bytes per row, planes `$2100` apart; visible x 16..335, y 0..159 |
| Attribute grid | `$58800` | 408x42 cells of 4x4 pixels (steel, triggers), rebuilt by the game's `$24FE` and `$2476` |
| Object instances | `$C166` | 32 of `$22` bytes, set up from the record by the game's `$2826` |
| Style data | `$FC(A5)` | Object descriptors at +`$70`, terrain piece descriptors at +`$290` |

Level coordinates include 16 pixels of padding on the left and 4 rows at the
top: level x = cursor x + scroll x + 16, level y = cursor y + 4.

## Display

The status block is shown by redirecting the end of the game's copper list
(`$8668`) to the continuation at `$22C00`, and by moving the display window
stop (`$84EE`) from `$F4C1` to `$24C1`, which adds 48 lines below the skill
panel. Both are restored when the editor closes or a level loads. This needs a
PAL display.

The editor's menu (title entry, disk prompts, messages) is drawn with the
editor's font into the displayed viewport buffer over the paused level.
While it is open it replaces the level view's colours 0..4, whose values are
the copper moves at `$850E + 4n`, and restores them when it closes.

The custom level list uses the game's own text screen, the one of the level
briefing: 13 rows of 40 characters in the game's font at `$23680`, each row
with its own palette from the copper list at `$8754`.
