# Level disk

A custom level is exactly the 2048-byte level record of the Amiga game
([level record](game-internals.md#level-record)), with no header of its own:
a `.lvl` file is that record. The floppy version keeps up to 318 of them on a
level disk, never on the game disks. The editor reads and writes it with its
own disk code; `savedisk.py` works with the same format in `.adf` images. The
WHDLoad version keeps `.lvl` files in its `Levels` directory instead
([WHDLoad](#whdload)).

All values are unsigned big-endian. Reserved fields and padding are zero.
CRC-32 is the reflected IEEE variant (polynomial `$EDB88320`, initial value
and final XOR `$FFFFFFFF`, as zlib's `crc32`; `123456789` gives `$CBF43926`).

## Disk layout

A standard double-density disk: 160 tracks (cylinder sides 0..159), each with
11 sectors of 512 bytes, 901120 bytes decoded. There is no AmigaDOS file system
and the disk is not bootable.

- Track 0: a 64-byte header, 318 two-byte index entries (`$40..$2BB`),
  zeroes, the name `Reserved` at `$400..$407`, zeroes to the end of the
  track.
- Tracks 1..159: two 2816-byte slots per track: the 2048-byte level record
  and 768 zero bytes.

Slot `i` (0..317) starts at byte `5632 * (1 + i/2) + 2816 * (i%2)`.
`savedisk.py` and the game's list number slots from 1. A slot is empty only
if all 2816 bytes are zero; any other content must be a valid level
([checks](#level-record-checks)) followed by zero padding. There is no
checksum per level: on a floppy the MFM sector checksums detect read errors,
and the record checks reject structural damage.

The name `Reserved` at `$400` is the first directory name of the game disks.
V1.x editors refuse such a disk as a game disk, so they never write to a
level disk.

## Header (track 0)

| Offset | Bytes | Value |
| --- | --- | --- |
| `$00` | 8 | `LEMSAVE` followed by NUL |
| `$08` | 2 | Format version: 2 |
| `$0A` | 2 | Header size: 64 |
| `$0C` | 4 | Compatibility ID: `$00020001` |
| `$10` | 2 | Sector size: 512 |
| `$12` | 2 | Sectors per track: 11 |
| `$14` | 2 | Track count: 160 |
| `$16` | 2 | Slot size: 2816 |
| `$18` | 2 | Slot count: 318 |
| `$1A` | 2 | Level record size: 2048 |
| `$1C` | 2 | Index entry size: 2 |
| `$1E` | 2 | Index length: 636 |
| `$20` | 4 | CRC-32 of the index |
| `$24` | 24 | Reserved |
| `$3C` | 4 | CRC-32 of the header, with this field zero |

A level disk requires the exact first 32 bytes, zero reserved fields, a valid
header CRC, zero padding and the name `Reserved`. Anything else is not a level
disk, and the game never writes to it.

## Index

Entry `i` is at `$40 + i*2`:

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 1 | State: 0 empty, 1 level, 2 level for two players |
| 1 | 1 | Graphics style 0..4 of the level; 0 when empty |

The list finds the occupied slots, and the 2 Player list the levels for two
players, from track 0 alone and reads the titles from the data tracks. State
2 follows from the record by the [two-player rule](#levels-for-two-players);
`savedisk.py` treats a state that disagrees with the record as index damage.
Under WHDLoad the 2 Player list reads every `.lvl` file when it opens. Any other entry value and an index CRC mismatch are
index damage, which never allows writing a slot.

## Writing

A write replaces one slot:

1. Read track 0 and check that it is a level disk; read the target track
   afresh. A slot the index calls empty must really be empty, and the new
   record must pass the checks.
2. Write the whole data track, read it back and compare. The other slot on
   the track stays byte-identical.
3. Read track 0 again and compare it with the first read.
4. Write track 0 with the updated index entry and both CRCs, read it back and
   compare.

The index never lists a level before its data track has been verified.
Cancelling with Esc is deferred from the first write through both
verifications. A physical track write is not atomic: if writing the data
track fails, both slots on that track may be damaged. If only the index
write fails, the level is saved but the index is stale; `savedisk.py
rebuild-index` rebuilds it from a scan of every slot. Damaged slots block the
rebuild and are never discarded silently.

Deletion (`savedisk.py delete`) zeroes the whole slot and updates the index
in the same order.

## Name and music

A level's name is its title in the record (`$7E0`, 32 characters,
space-padded). The music is not part of the record: the game chooses it as
for its own levels, by the level's number, which for a custom level is its
place in the list, counted from 0 (a new level 0).

## WHDLoad

The WHDLoad version stores custom levels as files: every file in the
directory `Levels` whose name ends in `.lvl` (upper or lower case) and that
holds exactly 2048 bytes is a custom level, subject to the same checks. The
list shows them sorted by file name, at most 318; files that are not exactly
one valid level are listed as damaged. A new level is saved as the first free
`LevelNNN.lvl`.

## Levels for two players

A level is for two players when it has an entrance, the marker (the first
object of type 2) and an exit of each player. In the game's two-player mode
a lemming at x, y in an exit counts for the green player when
|x - 8 - marker x| + |y - 32 - marker y| <= 32, otherwise for the blue
player; an exit is the green player's when the nearest pixel of its trigger
area ((x / 4 + trigger x) * 4, width * 4 pixels, the same in y) is that near.
Only the first 16 slots have trigger areas. The rule accepts all 20
two-player levels of the game. `savedisk.py list` marks these levels `2P`.

## Level record checks

`savedisk.py` and the game accept a record only within the game's own limits:

- release rate 0..99, lemmings 1..160, lemmings to save at most the number of
  lemmings, time 1..9 minutes, every skill count 0..99;
- start position 0..1280, a multiple of 4;
- graphics style 0..4, special background 0..4, the unused word `$1E` zero;
- objects: a slot with x = 0 is empty and otherwise ignored; an occupied slot
  has a type below the style's object count and flags `$000F`, `$400F`,
  `$800F` or `$C00F`; at most four entrances (type 1); for the first 16 slots
  x > 0, y >= 0 and the type's trigger area inside the attribute grid:
  x / 4 + trigger x + width <= 408, y / 4 + trigger y + height <= 42 (cells
  of 4 x 4 pixels, integer division);
- terrain: at most 399 pieces before the first `$FFFFFFFF`, every later entry
  `$FFFFFFFF`, piece number (bits 0..5 of the low word) below the style's
  piece count; a special background level has no pieces;
- steel: each nonzero area inside the grid: cell x + width <= 408, cell y +
  height <= 41;
- title: 32 printable ASCII characters, not all spaces.

The style limits (object types / terrain pieces: 12/50 for style 0, 12/64,
11/60, 12/62 and 12/37 for style 4, and the trigger areas) are in
`styles.json`, taken from the game's `leveldata`. A level without an entrance
or an exit passes: the game releases lemmings at (16, 16) when there is no
entrance, and a level without an exit cannot be won. PC `.LVL` files are
accepted under the same checks.

## Reference

An empty level disk has SHA-256
`821796b0ed7f593a428e89aa0cff239fbf621be0bd0e52b2b84de10c946b0fac`, index CRC
`$5CFF7486` and header CRC `$3604F834`.

## V1.x save disks

The V1.x editor keeps saves of edited original levels on a save disk, disk
format version 1: its track 0 starts with the same eight bytes `LEMSAVE` and
NUL, followed by format version 1 and the compatibility ID `$00010001`. Save
disks are user data. This version never initializes, converts or writes one:
the game refuses it like any other disk that is not a level disk ("This is
not a level disk."), and `savedisk.py` names it as a save disk of the V1.x
editor and refuses every command on it. Use the V1.x editor and its
`savedisk.py` (branch `v1-maint`) for save disks.
