# Amiga Lemmings level file format (`.lvl`)

A Lemmings level file holds one level of Amiga Lemmings: exactly 2048
bytes, with no header, no version field and no checksum. Its content is the
level record that the game itself copies to `$C5A6` and plays. This
document specifies the format completely as the Amiga game reads it: every
field and bit, the coordinate system, the objects of each graphics style,
what the game does with each value and which values are safe, one-player
and two-player play, music, special backgrounds and the title's
characters. The last sections cover Holiday Lemmings 1994, whose level
files have the same layout. "The editor" below is the in-game level editor
patch for these two games, which reads and writes this format.

## Sources

- Static analysis of the game's main program `Code` from disk 1,
  SHA-256 `65786a0977e42d0aedeb3e0894fd9e53eb6984b0b0a3c07ef18d3a64e94d8ea3`,
  loaded at `$400`. All addresses in this document are runtime addresses;
  subtract `$400` for the offset in the file. A5 is `$9E10` throughout the
  game, so `$44(A5)` is `$9E54`.
- The game's data file `leveldata` (disk 2) for the graphics styles and the
  music table, and the 140 level records of the original game (120
  one-player and 20 two-player levels), decoded from disk 2 as the game
  selects them. "The originals" below means these records.
- Run-time tests in an emulator (A500, 68000, OCS, cycle-exact) with the
  patched game playing custom levels: the object flags, the special
  backgrounds and a level with 160 lemmings. These are emulator results.

Anything that was inferred or not run is marked as such.

## Overview

All multibyte values are big-endian. Offsets are hexadecimal.

| Offset | Size | Content |
| --- | ---: | --- |
| `$000` | 32 | Header: parameters, skills, start position, graphics |
| `$020` | 256 | 32 object slots of 8 bytes |
| `$120` | 1600 | 400 terrain slots of 4 bytes, ended by `$FFFFFFFF` |
| `$760` | 128 | 32 steel areas of 4 bytes |
| `$7E0` | 32 | Title, ASCII, padded with spaces |

The game reads the record in these routines (every absolute reference to
`$C5A6..$CDA5` in `Code`):

| Address | Routine | Reads |
| --- | --- | --- |
| `$27C2..$2808` | Copy the record from its level file | all |
| `$26B4..$26E4` | `oddtable` override of the original levels | header, title |
| `$26E6..$2762` | Load the graphics files | style, special background |
| `$2788..$27C0`, `$060E..$062A` | Special background palette | special background |
| `$280A` | Select the style's data | style |
| `$2832..$2988` | Set up the level | header |
| `$2A60` | Object instances | objects |
| `$2D02`, `$2D80` | Entrances, two-player marker | object types |
| `$298A..$2A10` | Build the terrain and objects for the briefing's overview | terrain, objects |
| `$2A12..$2A5E` | Build the playing terrain | terrain, steel, objects |
| `$24FE` | Steel areas | steel |
| `$2476` | Object trigger areas | objects |
| `$235C` | Object animation | objects |
| `$23D8`, `$2414` | Draw the objects every frame | objects |
| `$2BA2..$2C7C` | Briefing texts | header, title |
| `$20DE` | End of a one-player level | number of lemmings |
| `$3780` | Music | special background |

The word at `$01E` is not read anywhere.

## Coordinates

The game builds the level in a terrain bitmap of 1632 x 168 pixels at
`$37080` (four planes of `$85E0` bytes, 204 bytes per row; set up by
`$7014` from `$2A16..$2A1E`). The playable level is 1600 pixels wide and 160
pixels high; the bitmap has 16 extra columns on each side and 4 extra rows
at the top and the bottom, in which the game clears the solid plane
(`$4B3A`). The fourth plane is the solid terrain that lemmings stand on.
The view is a 352 x 192 buffer (`$34DE..$34E6`) of which 320 x 160 is
shown; every frame the game copies the terrain into it from buffer row 4
and column *scroll* (`$4904`), so the screen shows buffer columns *scroll*
+ 16 .. *scroll* + 335 and buffer rows 4..163.

```
buffer x    0      16                                   1615     1631
            | pad  |<------------ level, 1600 px ------------->| pad |
buffer y    0..3     guard rows
            4..163   level, 160 px (the visible rows)
            164..167 guard rows
```

Below, *X* and *Y* are level coordinates: 0..1599 from the left edge of the
level and 0..159 from the top of the visible rows. The stored values
relate to them as follows:

| Field | Stored value | Evidence |
| --- | --- | --- |
| Terrain x, y | x = *X* + 16, y = *Y* + 4 (buffer coordinates) | `$2AA0` draws at the stored x and y into the bitmap |
| Object x, y | x = *X* + 16, y = *Y* | `$2414` draws at x − scroll and y into the view buffer, whose row 0 is buffer row 4 |
| Steel column, row | column = (*X* + 16) / 4, row = *Y* / 4 | `$24FE` marks attribute grid rows row + 1 .. (4 x 4 pixel cells of the bitmap) |
| Object trigger cells | column = x / 4 + offset, row = y / 4 + offset | `$2476` |
| Start position | *X* of the view's left edge | `$296E` |

Object y and terrain y have different origins: an object and a terrain
piece with the same stored y are 4 pixels apart on screen.

The attribute grid at `$58800` has 408 x 42 cells of 4 x 4 pixels (`$42F0`
bytes, cleared by `$2464`), one byte per cell: `slot << 4 | trigger code`
for objects, 9 for steel. The game rebuilds it at every level start: steel
first, then the objects' trigger areas over it (`$2A56..$2A5A`).

## Header (`$000..$01F`)

Every field is a word and is read as a whole word. "Game" gives what the
game does with the value and the values it handles; "Originals" the values
the original levels use.

| Offset | Field | Game | Originals |
| --- | --- | --- | --- |
| `$000` | Release rate | 0..99. The rate the level starts with and the lowest the player can set (`$5E(A5)`, `$56(A5)`; the minus button stops at it, `$DAE`, and the plus button at 99, `$DE6`). Release interval `(99 − rate) / 2 + 4` frames, computed with a 16-bit subtraction and a logical shift (`$284A..$285E`): above 99 the interval becomes huge. The briefing shows it in a two-digit field | 1..99 |
| `$002` | Number of lemmings | 1..160. One-player play releases this many (`$44(A5)`, `$2838`); the lemming table holds 160 records (`$A5E6`, `$2C` bytes each, followed by the object instances at `$C166`). 0 divides by zero in the briefing (`$2C02`) and the result (`$2082`). A one-player level ends when this many have been released and none is out (`$20DE`). The briefing shows it in a three-digit field. Two-player play ignores it | 1..100 |
| `$004` | Lemmings to save | A count, not a percentage, at most the number of lemmings. The briefing computes the percentage `to save * 100 / lemmings` (`$2BFA..$2C06`, `$4A(A5)`) and shows it in a three-digit field | |
| `$006` | Time limit in minutes | 1..9 (`$64(A5)`; the seconds start at 0). The briefing shows the digit `'0'` + minutes, with "Minute" for 1 and "Minutes" otherwise (`$2C26..$2C48`); 10 would print `:`, which the text routine draws as nothing, and the panel has one digit | |
| `$008` | Skills, 8 words | Climbers, floaters, bombers, blockers, builders, bashers, miners, diggers; 0..99 each, as the panel shows two digits. `$293C` copies them to the player's counters at `$9DA4 + $1A..$28` (in the game's internal order bombers, diggers, climbers, builders, blockers, bashers, floaters, miners), for both players | |
| `$018` | Start position | 0..1280, a multiple of 4: the view's left edge (`$296E`, both players). The view scrolls in steps of 4 (16 fast) and stops only when it reaches exactly 0 or 1280 (`$0D30`, `$0CF2`) | 0..1168, all multiples of 8 |
| `$01A` | Graphics style | 0 dirt, 1 fire, 2 marble, 3 pillar, 4 crystal. Selects the files `Ground1..5` and `Objects1..5` (the digit is style + `'1'`, a byte add, `$26EC..$26FA`), the palette and the object and piece descriptors in `leveldata` (style * `$590`, `$280A`) | 0..4 |
| `$01C` | Special background | 0 none, or 1..4 for the image file `special0..3` (see [special backgrounds](#special-backgrounds)) | 1..4 in one level each |
| `$01E` | Unused | Not read; write 0 | 0 |

### Special backgrounds

A special background replaces the terrain pieces with an image: Fun 22
(`$01C` = 4), Tricky 14 (2), Taxing 15 (1) and Mayhem 22 (3) use them.
With `$01C` = *n* (1..4), the game:

- loads the file `special` followed by the digit *n* + `$2F` (a byte add;
  `special0..3`) instead of `Ground`, to `$75578` (`$272E..$2760`). The
  files are IFF ILBM images, 960 pixels wide with three planes and ByteRun1
  compression;
- does not draw the terrain list (`$2A2E`, and `$29A6` for the briefing's
  overview), so the list must be empty: `$FFFFFFFF` in the first terrain
  slot. A terrain piece in the record is not drawn (tested at run time);
- decodes 160 rows of the image into planes 0..2 of the terrain bitmap at
  buffer columns 320..1279, rows 4..163, that is level *X* 304..1263, and
  makes every pixel with a non-zero colour solid: plane 3 = plane 0 | plane
  1 | plane 2 over the whole bitmap (`$3A40..$3AA0`);
- takes the image's `CMAP` colours 1..7 as the level's colours 9..15
  (12-bit, `$2788..$27C0`) and makes colour 0 black (`$060E..$062A`);
- still loads `Objects` of the record's style and builds the objects and
  steel areas as usual;
- plays the background's own tune (see [music](#music)).

Tested at run time for all four backgrounds, each with another style
(1..4) than the originals' style 0: the tune, the image's position and
solidity, the piece not drawn, the style's `Objects` file, the colours, and
lemmings standing on the image.

## Objects (`$020..$11F`)

32 slots of 8 bytes:

| Slot offset | Field |
| --- | --- |
| +0 | x, signed word: left edge, *X* + 16 |
| +2 | y, signed word: top edge, *Y* |
| +4 | Object type of the style (see [object types](#object-types)) |
| +6 | Drawing flags (see [drawing flags](#drawing-flags)) |

**Empty slots.** A slot with x = 0 is empty: the object instances
(`$2A60`), animation (`$235C`), drawing (`$23D8`, `$298A`) and trigger areas
(`$2476`) all skip it. The type word of every slot is still read, empty or
not: the entrance table (`$2D02`) takes every slot of type 1, and the
two-player marker (`$2D80`) is the first slot of type 2. Write empty slots
as eight zero bytes. (Two slots of the originals have x = 0 and other
nonzero bytes.)

**Slot numbers matter.** Only slots 0..15 get trigger areas (`$2476`), and
a trigger cell stores its slot number, which the trap code uses to find the
object's animation (`$6ED4`). An object with a trigger code (see the
tables) must therefore be in slots 0..15; entrances and decorations can be
in any slot. A tool must not compact or reorder the slots.

**Drawing order.** Slot 0 is drawn first and slot 31 last, every frame,
after the terrain and before the lemmings (`$23D8`, `$3D64`).

**Instances.** At the level start `$2A60` copies each occupied slot's
`$22`-byte descriptor (style * `$590` + `$70` + type * `$22` in
`leveldata`) to the instance at `$C166` + slot * `$22`; the size, frames,
animation and trigger area come from it, not from the record.

### Entrances

At most four slots of type 1, empty slots included: `$2D02` fills a table
of four entries at `$B0(A5)` with no bound, and a fifth overwrites the
game's variables. Each entrance gives the lemmings' starting point (x + 24,
y + 14), in slot order. With fewer than four, the table repeats them
(`$2D36..$2D7E`), and the lemmings come from the four entries in turn
(`$25E2..$260A`):

| Entrances | Table |
| --- | --- |
| 0 | (16, 16) four times |
| 1 | E0 E0 E0 E0 |
| 2 | E0 E1 E0 E1 |
| 3 | E0 E1 E2 E1 |
| 4 | E0 E1 E2 E3 |

An entrance opens once at the level start: its animation runs only while
`$35(A5)` is set (`$237E..$238C`).

### Object types

The object types of each style, from the descriptors in `leveldata`. The
size is the frame in pixels; the trigger area is x offset, y offset, width
x height in attribute cells, relative to (x / 4, y / 4); "Used" counts the
objects of the type in the originals.

Animation, from the descriptor's flags (`$235C`): *still* has one frame;
*loop* repeats; *when triggered* stands still until a lemming triggers it,
then runs once; *opens once* is the entrance.

Trigger codes, as the game handles them:

| Code | Effect | Evidence |
| --- | --- | --- |
| 0 | None; no trigger area | |
| 1 | Exit: the lemming leaves and counts as saved; a bomber here makes no hole | `$6E7A` → `$6F96`, `$4810` |
| 2 | A lemming walking right turns left | `$6EA0` |
| 3 | A lemming walking left turns right | `$6EBA` |
| 4 | Trap: unless its animation is already running, it starts the animation, plays the descriptor's sound and removes the lemming | `$6ED4..$6F0C` |
| 5 | Water: the lemming drowns; a bomber here makes no hole | `$6F0E`, `$4808` |
| 6 | Fire: the lemming burns | `$6F52` |
| 7 | One-way wall: bashers and miners dig through it only towards the left; facing right, they stop and cannot be assigned there | `$60A4`, `$67E2`, `$113C`, `$11D6` |
| 8 | One-way wall: the same towards the right | `$60B4`, `$67F8`, `$11E2` |
| 9 | Steel (the steel areas' code): stops bashers, miners and diggers; a miner or digger on it or a basher facing it cannot be assigned; a bomber makes no hole | `$6094`, `$67D4`, `$6C12`, `$1124`, `$11EA`, `$1326`, `$4800` |
| 10, 11..15 | None; no routine reads them | |

The original objects use codes 0, 1, 4..8 and 11. "A bomber makes no
hole": the explosion's hole in the terrain (`$47EA`) is skipped when the
exploding lemming stands in a cell with code 1, 5 or 9.

Style 0, dirt (12 types, 50 terrain pieces):

| Type | Size | Frames | Animation | Code | Trigger area | Used |
| ---: | --- | ---: | --- | --- | --- | ---: |
| 0 | 48 x 17 | 1 | still | 1 exit | 6, 4, 1 x 2 | 36 |
| 1 | 48 x 25 | 10 | opens once | 0 entrance | | 37 |
| 2 | 16 x 16 | 14 | loop | 0 | | 6 |
| 3 | 32 x 32 | 7 | loop | 7 one-way left | 0, 0, 8 x 8 | 23 |
| 4 | 32 x 32 | 7 | loop | 8 one-way right | 0, 0, 8 x 8 | 16 |
| 5 | 64 x 16 | 8 | loop | 5 water | 0, 2, 16 x 2 | 214 |
| 6 | 16 x 21 | 15 | when triggered | 4 trap | 2, 5, 1 x 2 | 6 |
| 7 | 48 x 8 | 6 | loop | 0 | | 36 |
| 8 | 16 x 38 | 17 | when triggered | 4 trap | 1, 10, 1 x 1 | 1 |
| 9 | 16 x 16 | 14 | loop | 0 | | 6 |
| 10 | 32 x 42 | 12 | when triggered | 4 trap | 3, 10, 1 x 1 | 2 |
| 11 | 16 x 10 | 6 | loop | 11 | 2, 0, 1 x 1 | 0 |

Style 1, fire (12 types, 64 pieces):

| Type | Size | Frames | Animation | Code | Trigger area | Used |
| ---: | --- | ---: | --- | --- | --- | ---: |
| 0 | 48 x 28 | 1 | still | 1 exit | 5, 7, 1 x 2 | 45 |
| 1 | 48 x 25 | 10 | opens once | 0 entrance | | 42 |
| 2 | 16 x 16 | 14 | loop | 0 | | 4 |
| 3 | 32 x 21 | 8 | loop | 7 one-way left | 0, 0, 8 x 6 | 16 |
| 4 | 32 x 21 | 8 | loop | 8 one-way right | 0, 0, 8 x 6 | 0 |
| 5 | 64 x 20 | 8 | loop | 5 water | 0, 3, 16 x 2 | 275 |
| 6 | 48 x 24 | 6 | loop | 0 | | 45 |
| 7 | 32 x 17 | 8 | loop | 6 fire | 1, 3, 6 x 2 | 38 |
| 8 | 80 x 20 | 10 | loop | 6 fire | 0, 5, 15 x 1 | 11 |
| 9 | 16 x 16 | 14 | loop | 0 | | 4 |
| 10 | 80 x 20 | 10 | loop | 6 fire | 5, 5, 14 x 1 | 9 |
| 11 | 16 x 10 | 6 | loop | 11 | 2, 0, 1 x 1 | 0 |

Style 2, marble (11 types, 60 pieces):

| Type | Size | Frames | Animation | Code | Trigger area | Used |
| ---: | --- | ---: | --- | --- | --- | ---: |
| 0 | 48 x 16 | 1 | still | 1 exit | 6, 4, 1 x 2 | 33 |
| 1 | 48 x 25 | 10 | opens once | 0 entrance | | 39 |
| 2 | 16 x 16 | 14 | loop | 0 | | 1 |
| 3 | 32 x 32 | 7 | loop | 7 one-way left | 0, 0, 8 x 8 | 24 |
| 4 | 32 x 32 | 7 | loop | 8 one-way right | 0, 0, 8 x 8 | 2 |
| 5 | 64 x 25 | 8 | loop | 5 water | 0, 2, 16 x 4 | 160 |
| 6 | 48 x 8 | 6 | loop | 0 | | 33 |
| 7 | 16 x 16 | 14 | loop | 0 | | 1 |
| 8 | 32 x 34 | 15 | when triggered | 4 trap | 3, 8, 2 x 1 | 11 |
| 9 | 32 x 19 | 16 | loop | 6 fire | 1, 4, 6 x 3 | 19 |
| 10 | 16 x 10 | 6 | loop | 11 | 2, 0, 1 x 1 | 0 |

Style 3, pillar (12 types, 62 pieces):

| Type | Size | Frames | Animation | Code | Trigger area | Used |
| ---: | --- | ---: | --- | --- | --- | ---: |
| 0 | 48 x 17 | 1 | still | 1 exit | 6, 4, 1 x 2 | 35 |
| 1 | 48 x 25 | 10 | opens once | 0 entrance | | 35 |
| 2 | 16 x 16 | 14 | loop | 0 | | 5 |
| 3 | 32 x 32 | 7 | loop | 7 one-way left | 0, 0, 8 x 8 | 0 |
| 4 | 32 x 32 | 7 | loop | 8 one-way right | 0, 0, 8 x 8 | 6 |
| 5 | 64 x 16 | 8 | loop | 5 water | 0, 2, 16 x 2 | 322 |
| 6 | 48 x 8 | 6 | loop | 0 | | 35 |
| 7 | 16 x 16 | 14 | loop | 0 | | 5 |
| 8 | 16 x 41 | 37 | when triggered | 4 trap | 1, 9, 1 x 1 | 6 |
| 9 | 16 x 26 | 7 | when triggered | 4 trap | 1, 5, 1 x 1 | 1 |
| 10 | 16 x 26 | 7 | when triggered | 4 trap | 2, 5, 1 x 1 | 1 |
| 11 | 16 x 10 | 6 | loop | 11 | 2, 0, 1 x 1 | 0 |

Style 4, crystal (12 types, 37 pieces):

| Type | Size | Frames | Animation | Code | Trigger area | Used |
| ---: | --- | ---: | --- | --- | --- | ---: |
| 0 | 48 x 15 | 1 | still | 1 exit | 5, 4, 1 x 2 | 17 |
| 1 | 48 x 25 | 10 | opens once | 0 entrance | | 16 |
| 2 | 16 x 16 | 14 | loop | 0 | | 4 |
| 3 | 16 x 16 | 14 | loop | 0 | | 4 |
| 4 | 32 x 32 | 7 | loop | 7 one-way left | 0, 0, 8 x 8 | 0 |
| 5 | 32 x 32 | 7 | loop | 8 one-way right | 0, 0, 8 x 8 | 0 |
| 6 | 64 x 16 | 8 | loop | 5 water | 0, 2, 16 x 2 | 84 |
| 7 | 32 x 19 | 25 | when triggered | 4 trap | 3, 3, 1 x 1 | 0 |
| 8 | 48 x 8 | 6 | loop | 0 | | 17 |
| 9 | 16 x 71 | 8 | when triggered | 4 trap | 1, 10, 2 x 2 | 1 |
| 10 | 32 x 15 | 16 | when triggered | 4 trap | 3, 3, 2 x 1 | 2 |
| 11 | 16 x 10 | 6 | loop | 11 | 2, 0, 1 x 1 | 0 |

The exit is one still frame; its animated top is a separate decoration,
which the originals place 8 pixels above every exit: type 7 in style 0,
type 6 in styles 2 and 3, type 8 in style 4. In style 1 every exit has a
type 6 object (48 x 24) as well. Type 2 has no trigger area in any style;
two-player levels use it as the marker.

### Drawing flags

`$2414` passes the flags word unchanged, as D5, to the game's drawing
routine `$704C`, which also draws the terrain pieces. Its bits:

| Bit | Meaning | Evidence |
| --- | --- | --- |
| 0 | Set: draw at the exact x (the blitter shifts the object). Clear: x is rounded down to a multiple of 16 and bits 7, 14 and 15 are ignored | `$7062` → `$73AE` |
| 1 | Set: draw through the object's mask. Clear: copy the whole rectangle, transparent pixels as colour 0, over every 16-pixel word the object touches, and ignore bits 7, 14 and 15 | `$7082` → `$72BC`, `$73AE` → `$74B2` |
| 2 | Clip at the left and right edges of the view (in 16-pixel steps, only outside the visible part). Clear: no horizontal clipping | `$75A0` |
| 3 | Clip at the top and bottom edges. Clear: no vertical clipping | `$75EE` |
| 5 | With bits 8..11: set the selected planes under the mask, draw the others normally. Takes precedence over bit 6 | `$7114` → `$7254` |
| 6 | With bits 8..11: clear the selected planes under the mask, draw the others normally | `$711C` → `$7246` |
| 7 | Upside down | `$70BE`, `$71FC` |
| 8..11 | The planes 0..3 that bits 5 and 6 change | `$725E..$7264` |
| 14 | Draw only where the view already has solid terrain (its fourth plane). Takes precedence over bit 15 | `$70A8` → `$7198` |
| 15 | Draw behind: the object's colours are added only where the view has no solid terrain; the mask and bits 5 and 6 are not used | `$70FA` → `$714C` |
| 4, 12, 13 | Not read | |

The view's fourth plane at that moment holds the terrain and the objects of
lower slots already drawn in the frame. Objects are drawn into the view
only (and, at the level start, into the bitmap for the briefing's
overview, which is then rebuilt without them): no flag changes the solid
terrain or the trigger areas, which `$2476` builds from x, y and type
alone.

The originals use four values: `$000F` (660 objects), `$400F` (only over
terrain, 102), `$800F` (behind terrain, 1024) and `$C00F` (5), which draws
exactly as `$400F`. Tested at run time, with one exit over an empty
background and one over solid terrain:

| Flags | Result |
| --- | --- |
| `$000F` | Normal |
| `$008F` | Upside down |
| `$400F` | Only over solid terrain |
| `$800F` | Only where there is no solid terrain |
| `$C00F` | As `$400F` |
| `$408F`, `$C08F` | Only over solid terrain, but the image is upside down and the mask is not: the routine builds its mask from the mask as it is (`$7198..$71EE`) and flips only the image (`$71FC`). Drawn correctly only for a vertically symmetric mask |
| `$808F` | Upside down, behind terrain |
| `$004F`, `$301F`, `$0003` | As `$000F` (bit 6 without plane bits; bits 4, 12, 13; no clipping inside the view) |
| `$0F4F` | A hole in the shape of the mask in the view's picture; nothing drawn |
| `$0F2F` | The mask's shape in colour 15 |
| `$000D` | The rectangle copied without the mask |
| `$000E` | Drawn at x rounded down to a multiple of 16 |

The trigger cells of an exit with `$008F` were where they are without the
flag. Not run: bits 5 and 6 with only some of bits 8..11, and objects
without clipping at the view's edges (the routine then writes outside the
view buffer).

Safe values are `$000F`, `$400F`, `$800F`, `$008F` and `$808F`; bits 2 and
3 must stay set. The editor accepts only the originals' four values.

### Position limits

The game writes the trigger area into the attribute grid without clipping
(`$2476`), after shifting x and y right by 2 with `lsr`, so for objects in
slots 0..15:

    x > 0, y >= 0
    x / 4 + trigger x + trigger width  <= 408
    y / 4 + trigger y + trigger height <= 42

(integer division; types without a trigger area need only x > 0 and y >=
0). Drawing clips at the view buffer's edges (with bits 2 and 3), so slots
16..31 can be anywhere; an object whose top is at y 160 or more is below
the visible rows. The editor keeps x and y of every occupied slot within
−4096..4095. The originals have x 16..1552, always a multiple of 8, and y
0..144.

The briefing's overview draws the objects into the terrain bitmap 4 rows
down, clipped to 168 rows from there (`$29CE..$2A00`): an object reaching
below *Y* 164 writes into the first rows of the next plane, which the
playing terrain build then replaces (inferred from the code, harmless).

## Terrain (`$120..$75F`)

400 slots of two words, H and L, drawn in list order by `$2AA0`; a later
piece goes over the earlier ones, or under them with the behind bit:

```
H  bit 15     14     13     12 ............................ 0
       behind flip   erase  x, 13 bits, unsigned

L  bit 15 .................. 7    6        5 ............ 0
       y, 9 bits, signed          ignored  piece number
```

`$2AA0..$2AF4` decodes a slot and calls `$704C` with flags `$000F`, plus bit
7 for flip, bit 6 and bits 8..11 for erase and bit 15 for behind:

| Field | Decoding | Game | Originals |
| --- | --- | --- | --- |
| x | `H & $1FFF`, unsigned | *X* + 16. Clipped at 0..1631 (`$759A`), so x of `$1000` or more is never drawn, and no piece can start left of buffer x 0. The right edge is clipped in 16-pixel steps; the lost strip lies in the invisible pad | 0..1612, and 22 entries of `$1FD5..$1FFF` in four records |
| erase | H bit 13 | Clears all four planes through the piece's mask: removes terrain | |
| flip | H bit 14 | Draws the piece upside down | |
| behind | H bit 15 | Adds the piece's planes only where the bitmap has no solid terrain yet; takes precedence over erase | every combination of the three bits |
| y | `signed16(L) >> 7`, arithmetic | *Y* + 4; −256..255; clipped at rows 0..167 | −66..164 |
| piece | `L & $3F` | Below the style's piece count: 50, 64, 60, 62, 37 for styles 0..4; the descriptor is style * `$590` + `$290` + piece * 12 in `leveldata` (width, height, image, mask) | |
| bit 6 | | Ignored (`andi.w #$3F`, `$2ACA`); write 0 | set in 68 pieces of Taxing 2 |

A piece's fourth plane is its solidity, so normal and behind pieces add
solid terrain wherever they draw.

**End of the list.** The game draws pieces until the first `$FFFFFFFF`
(`$2A38..$2A48`) and has no count limit: a list of 400 pieces without the
marker would continue into the steel areas. A level therefore has at most
399 pieces, followed by `$FFFFFFFF` in every remaining slot up to `$75F`.
The originals have at most 398. A special background level has no pieces.

## Steel areas (`$760..$7DF`)

32 slots of two words, H and L (`$24FE`):

```
H  bit 15 ................. 7    6 ............... 0
       column, 9 bits             row, 7 bits

L  bit 15 ...... 12   11 ...... 8   7 ............. 0
       width − 1          height − 1      unused
```

- The area covers columns *column* .. *column* + width − 1 and attribute
  grid rows *row* + 1 .. *row* + height, cells of 4 x 4 pixels: in level
  coordinates *X* = 4 * column − 16, *Y* = 4 * row, 4..64 pixels wide and
  high. The game writes code 9 into these cells; see code 9 in the
  [trigger codes](#object-types). Steel areas are not drawn.
- A slot of zero (both words) is unused. An area of one cell at column 0,
  row 0 would encode as zero; it would lie outside the level anyway.
- The low byte of L is not read and is 0 in every original; write 0.
- The game writes the cells without clipping: column + width <= 408 and
  row + height <= 41. The originals have column 4..385 and row 0..38.
- An object's trigger area written over steel replaces the steel in those
  cells.

## Title (`$7E0..$7FF`)

32 bytes, padded with spaces, with no terminator. The game shows the title
only in the briefing: `$2C6A` copies it into the briefing text at `$9187`,
and the text routine `$15E4` prints it in its 16 x 16 font (`$14EA4`,
`$60` bytes per character from `$20` on):

| Bytes | Shown as |
| --- | --- |
| `$20..$7E` except `:` | The character |
| `:` (`$3A`) | Nothing, and the next character takes its place (`$1622..$1630`); the game uses it to drop leading zeros |
| `$01..$1F`, `$A0..$FF` | A blank character |
| `$7F..$9F` | Garbage: the glyph is read from the data after the font |
| `$00` | Ends the line (`$16F0`); the bytes after it are read as the next text entry (column, row, text), which misplaces the rest of the briefing |

Use `$20..$7E` and avoid `:`. The editor accepts `$20..$7E` and shows a
custom level's `:` as `;` in the briefing.

## Music

The record holds no music. `$3780` chooses the tune from the table in
`leveldata` (runtime `$2188E`, 21 entries of `$1C` bytes: a 12-byte module
name and 16 instrument numbers):

- a level with a special background (`$01C` = 1..4): entry 16 + `$01C`,
  the tunes `awesome`, `menace`, `beastII` and `beastI` (tested at run
  time); values above 4 would read past the table;
- any other level: entry (level number mod 17), the level number being the
  game's level index (`$42(A5)`: 0..119 for the one-player levels, 0..19
  for the two-player levels), of `cancan`, `lemming1`, `tim2`, `lemming2`,
  `tim8`, `tim3`, `tim5`, `doggie`, `tim6`, `lemming3`, `tim7`, `tim9`,
  `tim1`, `tim10`, `tim4`, `tenlemmings`, `mountain`.

The editor numbers a custom level by its place in the level list,
counted from 0.

## Two-player levels

There is no two-player flag: the original game plays its 20 two-player
levels from ordinary records, with these rules in two-player mode
(`$30(A5)` set):

- Each player gets 40 lemmings plus the ones they saved in the previous
  level, at most 80 (`$290A..$2936`); the record's number of lemmings is
  not used, also not for the end of the level (`$2072` returns before the
  test at `$20DE`).
- Releases alternate between the players, one from entrance table entry 0,
  the other from entry 1 (`$2590..$25C8`): the first two entrances, or the
  only one for both. A third and fourth entrance are not used.
- The marker is the first slot of type 2, empty or not (`$2D80..$2DAA`).
  Without one, the marker position of the previous level stays.
- A lemming at x, y leaving through an exit counts for the green player
  when `|x − 8 − marker x| + |y − 32 − marker y| <= 32`, otherwise for the
  blue player (`$6DE0..$6E0E`).
- The level's win goes to whoever rescued more lemmings, to both on a draw
  (`$89E..$91E`).

A level is valid for two players when it has at least one entrance, the
marker, and exits of both players among slots 0..15 (only these have
trigger areas). The editor calls an exit the green player's when the
nearest pixel of its trigger area is within that distance of (marker x +
8, marker y + 32). This rule accepts all 20
two-player originals and none of the 120 one-player originals. In the
originals the marker is 16 pixels right of the green exit and 20 or 24
pixels above it. In the dirt style type 2 is a green flag.

## Not in the file

- Music (see [music](#music)), level number, rating and access code: they
  come from the level's place in the game or in a level list.
- The game the level belongs to (see [Holiday Lemmings 1994](#holiday-lemmings-1994)).
- Two-player mode: decided by the content.
- Author, date, palette and lemming graphics: the palette comes from the
  style (or a special background's image).

## Files

- A level file's name ends in `.lvl` (in any case), and the file holds
  exactly 2048 bytes: the record, nothing before or after it.
- The editor's WHDLoad version reads the `.lvl` files in the directory
  `Levels` of its data directory, sorted by name, at most 318, with names
  of at most 107 characters. Holiday Lemmings 1994 with the editor uses
  `Levels` in the game's directory and saves new levels as
  `LevelNNN.lvl`.
- The editor's floppy version keeps the same records on a level disk, 318
  slots of 2816 bytes (the record and 768 zero bytes), and its tools
  convert between `.lvl` files and the disk.
- A tool that rewrites a level should keep the object slots and the order
  of the terrain pieces.

## Holiday Lemmings 1994

Holiday Lemmings 1994 (like Xmas Lemmings and Holiday Lemmings 1993, on the
same engine) uses the same 2048-byte record with the same fields, bit
layouts and decoding: the header, object, terrain and steel readers were
traced in those games' code, and the editor reads and writes the record
there with the same code. The
drawing flags, trigger codes and title characters were traced only in
Lemmings. The differences:

- Styles 0 (Brick, `ground1`) and 2 (Snow, `ground3`) only, each with 10
  object types; 60 pieces in style 0 and 37 in style 2 (from the game's
  own `leveldata`). A level file does not say which game it is for: a
  Holiday level loaded into Lemmings would be drawn with dirt or marble
  pieces of the wrong shape. Keep the levels of each game apart.
- No special backgrounds: `$01C` must be 0.
- The attribute grid has 44 rows: y / 4 + trigger y + trigger height <= 44
  for objects in slots 0..15 and row + height <= 43 for steel areas.
- No two-player mode.

Style 0, Brick:

| Type | Size | Frames | Animation | Code | Trigger area |
| ---: | --- | ---: | --- | --- | --- |
| 0 | 48 x 35 | 1 | still | 1 exit | 4, 9, 2 x 1 |
| 1 | 48 x 25 | 10 | opens once | 0 entrance | |
| 2 | 16 x 16 | 14 | loop | 0 | |
| 3 | 16 x 32 | 7 | loop | 7 one-way left | 0, 0, 8 x 8 |
| 4 | 16 x 32 | 7 | loop | 8 one-way right | 0, 0, 8 x 8 |
| 5 | 64 x 24 | 9 | loop | 5 water | 0, 4, 16 x 2 |
| 6 | 16 x 35 | 18 | when triggered | 4 trap | 1, 9, 1 x 1 |
| 7 | 48 x 32 | 20 | when triggered | 4 trap | 2, 8, 1 x 1 |
| 8 | 16 x 16 | 14 | loop | 0 | |
| 9 | 32 x 13 | 4 | loop | 0 | |

Style 2, Snow:

| Type | Size | Frames | Animation | Code | Trigger area |
| ---: | --- | ---: | --- | --- | --- |
| 0 | 48 x 29 | 1 | still | 1 exit | 6, 8, 1 x 1 |
| 1 | 48 x 22 | 10 | opens once | 0 entrance | |
| 2 | 48 x 36 | 1 | still | 0 | |
| 3 | 48 x 14 | 6 | loop | 0 | |
| 4 | 32 x 48 | 16 | loop | 0 | |
| 5 | 64 x 25 | 6 | loop | 0 | |
| 6 | 32 x 17 | 4 | loop | 0 | |
| 7 | 32 x 48 | 1 | still | 0 | |
| 8 | 32 x 15 | 1 | still | 0 | |
| 9 | 32 x 20 | 14 | loop | 0 | |

## Checklist for writing a level

A file that follows these rules plays in Amiga Lemmings, and the editor
accepts it:

1. 2048 bytes, big-endian words.
2. Header: release rate 0..99, lemmings 1..160, to save at most the
   lemmings, minutes 1..9, skills 0..99, start position 0..1280 in steps of
   4, style 0..4, special background 0..4, the word at `$01E` zero.
3. Objects: empty slots of eight zero bytes; occupied slots with x not 0, a
   type below the style's count, flags `$000F`, `$400F`, `$800F` or
   `$C00F`, x and y within −4096..4095; objects with a trigger code in
   slots 0..15, and every object there with x > 0, y >= 0 and its trigger
   area inside the grid; at most four slots of type 1.
4. Terrain: at most 399 pieces, then `$FFFFFFFF` in every slot up to
   `$75F`; piece numbers below the style's count; x below 1632; no pieces
   with a special background. Bit 6 of L should be 0.
5. Steel: each area inside the grid, the low byte zero, unused slots zero.
6. Title: 32 printable ASCII characters (`$20..$7E`), padded with spaces,
   not all spaces; avoid `:`.

For Holiday Lemmings 1994, the styles, counts and grid of its section
apply.

## Example

A flipped piece 3 at *X* 100, *Y* 50; an exit at *X* 200, *Y* 100; a steel
area of 16 x 8 pixels at *X* 200, *Y* 80:

| Item | Stored | Bytes |
| --- | --- | --- |
| Terrain | x 116, flip, y 54, piece 3 | `40 74 1B 03` |
| Object | x 216, y 100, type 0, flags `$000F` | `00 D8 00 64 00 00 00 0F` |
| Steel | column 54, row 20, width 4, height 2 | `1B 14 31 00` |

## Appendix: the original levels on disk

The original levels are not stored as `.lvl` files. On disk 2, `leveldata`
holds a table of words at offset `$1BD0` of its unpacked data (runtime
`$21372`), one for each level: 0..119 for the one-player levels (Fun 1..30,
Tricky, Taxing, Mayhem) and 160..179 for the two-player levels (the game
adds 160 in two-player mode, `$27D2`). `LoadSelectedLevelResources`
(`$2632`) takes m = entry − 1, then:

- the record is number (m >> 1) & 3, at offset record * `$800`, of the file
  `Level%03d` with the number m >> 3 (25 files, each unpacking to 8192
  bytes, four records; `$27C2..$2808`);
- when bit 0 of m is set, the `$38`-byte entry at (m >> 1) * `$38` of the
  file `oddtable` replaces bytes `$000..$017` and the title `$7E0..$7FF`
  (`$26B4..$26E4`).

The files are packed with the game's backward bitstream packer
(`$3934..$3A02`). In Xmas and Holiday Lemmings the entries are record
numbers counted from 1 (file m >> 2, record m & 3), without an `oddtable`.
The original levels are the publisher's copyrighted data; this document
describes only where they are.
