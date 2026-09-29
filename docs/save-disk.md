# Save disk

Saves are stored on a separate save disk, never on the game disks. The editor
reads and writes it with its own disk code; `savedisk.py` works with the same
format in `.adf` images.

## Disk layout

A standard double-density disk: 160 tracks (cylinder sides 0..159), each with
11 sectors of 512 bytes, 901120 bytes decoded. There is no AmigaDOS file system
and the disk is not bootable.

- Track 0: a 64-byte header, then a 954-byte slot index (318 entries of 3
  bytes), then zeroes.
- Tracks 1..159: two 2048-byte slots per track, in sectors 0..3 and 4..7.
  Sectors 8..10 are reserved and zero.

Slot `i` (0..317) starts at byte `5632 * (1 + i/2) + 2048 * (i%2)`. A slot is
empty only if all 2048 bytes are zero; any other content must be a valid save.
`savedisk.py` and the menu number slots from 1.

All values are unsigned big-endian. Reserved fields and padding are zero.

## Header (track 0)

| Offset | Bytes | Value |
| --- | --- | --- |
| `$00` | 8 | `LEMSAVE` followed by NUL |
| `$08` | 2 | Format version: 1 |
| `$0A` | 2 | Header size: 64 |
| `$0C` | 4 | Editor compatibility ID: `$00010001` |
| `$10` | 2 | Sector size: 512 |
| `$12` | 2 | Sectors per track: 11 |
| `$14` | 2 | Track count: 160 |
| `$16` | 2 | Slot size: 2048 |
| `$18` | 2 | Slot count: 318 |
| `$1A` | 2 | Maximum saves per level: 32 |
| `$1C` | 2 | Index entry size: 3 |
| `$1E` | 2 | Index length: 954 |
| `$20` | 4 | CRC-32 of the index |
| `$24` | 24 | Reserved |
| `$3C` | 4 | CRC-32 of the header, computed with this field zero |

The index starts at `$40`. Entry `i` holds the slot's level (0..119, or `$FF`
if empty) and its edit count as a 16-bit value (zero if empty). Entries are
odd-aligned, so the 68000 code accesses them byte by byte.

An empty disk has the SHA-256
`34f0c52d9aab5ba4fc77793fc5ee4147a240605fa8ce5f3eb1895a112f8902f6`.

## Save record

| Offset | Bytes | Value |
| --- | --- | --- |
| `$00` | 8 | `LEMEDIT` followed by NUL |
| `$08` | 2 | Format version: 1 |
| `$0A` | 2 | Header size: 64 |
| `$0C` | 4 | Editor compatibility ID: `$00010001` |
| `$10` | 2 | Level: 0..119 (Fun 0..29, Tricky 30..59, Taxing 60..89, Mayhem 90..119) |
| `$12` | 2 | Edit count: 0..400 |
| `$14` | 4 | CRC-32 of the level's original 2048-byte record |
| `$18` | 16 | Name: 1..16 printable ASCII characters, NUL-padded, not all spaces |
| `$28` | 20 | Reserved |
| `$3C` | 4 | CRC-32 of the first `64 + count*4` bytes, computed with this field zero |
| `$40` | count * 4 | Placements |

Each placement is two words, H and L:

- H: x in bits 0..12 (signed), erase in bit 13, flip in bit 14, bit 15 zero.
- L: y in bits 7..15 (signed), piece in bits 0..5, bit 6 zero.

These are the level format's own placement fields. The piece must exist in
the level's graphics set, and the original pieces plus the edits must not
exceed 400. A save contains only the edits; no original level data is copied.

The level CRC covers the level record at `$C5A6..$CDA5` as loaded, before
level setup changes it. A save loads only in the level whose number and CRC
match. `bases.json` lists these CRCs, the original piece counts and the piece
counts of the graphics sets, so `savedisk.py` can check saves without game
files.

CRC-32 is the IEEE variant (Python `zlib.crc32`). It detects damage and
incompatible saves; it is not an authentication mechanism.

## Slot allocation

A new save uses the lowest slot from the first of these that applies:

1. the free partner slot of a slot that already holds a save of the level;
2. a slot on a track whose both slots are free;
3. any free slot.

This keeps a level's saves on as few tracks as possible, so the menu reads
fewer tracks when it lists them.

## Writing

A track is written as a whole. To save or delete, the editor:

1. reads the target track, checks both of its slots against the index, and
   reads it again just before writing to make sure it has not changed;
2. replaces the slot's four sectors, writes the track and reads it back to
   verify it;
3. then updates, writes and verifies track 0.

A track write is not atomic. An interrupted write is detected by the CRCs but
cannot be undone, and it can damage the other slot on the same track. If the
index and the slots disagree (for example after a write was interrupted), the
menu offers **Rebuild index** (`R`): it reads every slot and rewrites only
track 0. Damaged slots are reported, never silently discarded.

## Initialization in the game

A disk that is not a save disk, or cannot be read (unformatted), can be
initialized from the menu after a confirmation. Every data track is written
with two empty slots and verified first; track 0 with the header and an empty
index is written last. An interrupted initialization therefore never leaves a
valid header in front of unformatted tracks. A disk whose directory starts
with `Reserved` (a Lemmings game disk) is always refused.

## Drives

- Search order: the drive where a save disk was last found, then every other
  connected drive except the one holding disk 2. DF1..DF3 are detected with
  the standard 32-bit drive identification, so missing drives cause no seek
  timeouts.
- If no save disk is found, the menu asks for one: in another connected drive,
  or in the disk 2 drive on a single-drive machine.
- If the save disk was in the disk 2 drive, the menu asks for disk 2 again
  before it closes or a loaded level restarts, and waits until track 0 of that
  drive holds the disk 2 directory.
