# Game internals

The parts of the game that the editor and `patch.py` rely on. All values are
for the supported disk images only.

## Disk directory

The disks do not use AmigaDOS. Files are read through the game's own directory:

- Directory at disk offset `$400..$13FF`, 16-byte records. The first record
  (`Reserved`) is skipped.
- Record: 12-byte name (NUL-terminated, padded with `$FF`), then the file
  length as a big-endian 32-bit value. A record of sixteen `$FF` bytes ends the
  list.
- File data starts at `$1600`. Files follow each other with no gaps, in
  directory order; a file's offset is the sum of the lengths before it.
- Disk 1 keeps its raw boot loader and the packed boot intro at
  `$CA000..$CF9FF`, so its files must end before that. Tracks 151..159
  (`$CFA00` to the end) are never read; the patch stores `Editor` there
  behind a placeholder entry ([patch points](patch-points.md#disk-changes)).
- The game's file loader (`$3286`) takes a file from its cache, or reads it
  by the disk 2 directory it read at start-up from the drive it found disk 2
  in, without checking which disk is there. With one drive the editor's list
  therefore asks for disk 2 before a level starts and before it returns to
  the title screen.
- The game's disk loader (`$7FB2`) identifies a disk by the first four
  characters of its first file name: `main` on disk 1, `Grou` (`Ground1`) on
  disk 2. After a level disk swap the editor recognizes disk 2 by its first
  file name `Ground1`. A level disk carries the name `Reserved` at `$400`,
  so the V1.x editors refuse it as a game disk.

## Game variables

`A5` points to the game's globals at `$9E10`. The game keeps `A4` at its row
offset table `$A3C0` everywhere; the editor sets it back before calling the
game.

| Address | Meaning |
| --- | --- |
| `$26(A5)` | Last raw key code |
| `$29(A5)`, `$2D(A5)` | Level-end state; the game's Esc action `$1598` sets `$29(A5)` |
| `$30(A5)` | Two-player mode |
| `$3C(A5)` | Negative while the two-player panel is loaded |
| `$7E(A5)`, `$80(A5)` | Position of the two-player marker (the first object of type 2) |
| `$104(A5)`, `$106(A5)` | Two players: lemmings saved in the last level (green, blue), added to the next level's 40 |
| `$110(A5)`, `$112(A5)` | Two players: won levels (blue, green) |
| `$39(A5)` | Pause flag. Freezes lemmings, releases, object animations and the clock, while mouse and display keep running |
| `$3E(A5)` | Frame timing counter of the main loop |
| `$42(A5)` | Selected level number; for a custom level its list number mod 17, which chooses the tune |
| `$5C(A5)` | Release counter; the editor opens before the first lemming is released |
| `$76(A5)` | Cached level bank; set to -1 so the next level is copied again |
| `$AA(A5)` | Rating (0..3); CUSTOM is not one of them; it exists only in the editor |
| `$CC(A5)` | Viewport back buffer |
| `$DC(A5)` | Level start counter (entrances open at 35) |
| `$F8(A5)` | End of the file cache (after the patch: start of the editor block) |
| `$FC(A5)` | Current style data |
| `$9DA4` | Mouse position on the title screen and the text screens |
| `$9DA8` | Horizontal scroll |
| `$9DAA`, `$9DAC` | Cursor x, y |
| `$144F2` | Skill-selection sprite (hidden while editing) |

## Level record

The current level is copied to `$C5A6` (2048 bytes); a `.lvl` file is exactly
this record. All words are big-endian.

| Offset | Size | Field |
| --- | --- | --- |
| `$000` | 2 | Release rate, 0..99 |
| `$002` | 2 | Number of lemmings, 1..160 |
| `$004` | 2 | Lemmings to save (a count), at most the number of lemmings |
| `$006` | 2 | Time limit in minutes, 1..9 |
| `$008` | 16 | Skills, 8 words, 0..99: climbers, floaters, bombers, blockers, builders, bashers, miners, diggers |
| `$018` | 2 | Start scroll x, 0..1280, a multiple of 4 |
| `$01A` | 2 | Graphics style 0..4 (`Ground1..5`, `Objects1..5`: dirt, fire, marble, pillar, crystal) |
| `$01C` | 2 | Special background 0 (none) or 1..4 |
| `$01E` | 2 | Unused, 0 |
| `$020` | 256 | 32 objects of 8 bytes: x, y, object type of the style, drawing flags (`$000F` normal, `$400F` only on terrain, `$800F` behind terrain, `$C00F` both); x = 0 is an empty slot |
| `$120` | 1600 | 400 terrain pieces of 4 bytes, ended by `$FFFFFFFF` (so at most 399): high word x (unsigned 13 bits) and flags (bit 13 erase, 14 flip vertically, 15 behind existing terrain), low word y (signed 9 bits, bits 7..15) and piece (bits 0..5) |
| `$760` | 128 | 32 steel areas of 4 bytes: H = cell x << 7 \| (cell y - 1), L = (width - 1) << 12 \| (height - 1) << 8, in cells of 4x4 pixels; a zero record is skipped |
| `$7E0` | 32 | Title, ASCII, space-padded (the game's copy at `$CD86`) |

The layout is the same as the PC version's `.LVL` files. The game draws
terrain pieces until the end marker and writes trigger and steel areas into
the attribute grid without clipping, so the editor and `savedisk.py` accept a
record only within the limits above, with trigger and steel areas inside the
grid and at most four entrances ([level disk](level-disk.md#level-record-checks)). A
terrain x of `$1000` or more is not drawn on the Amiga.

The music is not part of the record: a special background level gets its
special tune, any other level tune `$42(A5)` mod 17 of the game's rotation.

## Terrain pieces

Terrain piece descriptors are at style +`$290`, 12 bytes each: width, height
(words), image pointer, mask pointer (longs). The pointers refer to the
`Ground` graphics as loaded at `$75578`; the editor loads its own copy of the
style's `Ground` file into its block and rebases them, because the game
overwrites that memory with sound data before play.

A piece has four image planes stored one after another (`width/8 * height`
bytes each) and a one-plane mask. Every piece width is a multiple of 8, and
every piece's image lies inside its mask. Many pieces have transparent
columns or rows; snap uses the opaque bounds of the mask.

The editor's erase mode (right button), `F` flip and `B` behind set bits 13,
14 and 15 of a placement. As in the game, behind draws the piece only where
the terrain's fourth (solid) plane is clear, so existing terrain stays in
front; the added parts are solid like any other terrain.

## Objects

Object descriptors are at style +`$70`, `$22` bytes each, up to the first
empty one (12 types, 11 in style 2). A descriptor with a trigger code (`$18`:
exits, traps, water, one-way walls) gets trigger cells only in the first 16
object slots (`$2476`); the editor places such objects there and other
objects from slot 16 on. `$2D02` collects the entrances (type 1) of all 32
slots into four entries with no bound, so a level has at most four. The game
draws an object frame with `$704C`, using the record's flags.

## Attribute grid

`$58800`, 408x42 cells of 4x4 pixels. `$24FE` clears it and writes the steel
areas (code 9) from `$CD06`, `$2476` writes the trigger areas of the first 16
objects. The editor rebuilds it with these two routines after every change of
the steel areas or objects, as the level start does.

## Input

| Source | Meaning |
| --- | --- |
| `$BFE001` bit 6 | Left mouse button (0 = pressed) |
| `$DFF016` bit 10 (byte `$16`, bit 2) | Right mouse button (0 = pressed) |
| Raw keys `$12`, `$14`, `$18`, `$19`, `$36`, `$21` | E, T, O, P, N, S |
| Raw keys `$23`, `$35`, `$24` | F, B, G (no gameplay action in the original game) |
| Raw keys `$4C`..`$4F` | Cursor up, down, right, left |
| Raw keys `$44`, `$43`, `$45`, `$41` | Return, Enter, Esc, Backspace |
| Raw keys `$60`/`$61`, `$E0`/`$E1` | Left/right Shift down, up |
| `$A526`, `$A586` | The game's raw-key-to-ASCII tables, unshifted and shifted (title entry) |

The game's gameplay key handler (`$14E2`) acts only on the translated codes
of its own keys, so the editor's letter keys do nothing in the game. Esc
(translated `$11`) would end the level; while a custom level is edited the
keyboard hook passes it to the game as a key release (`$C5`) and handles it
itself.
