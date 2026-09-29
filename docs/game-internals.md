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
- Disk 1 keeps its raw boot loader at `$CA000`, so its files must end before
  that. Disk 2 has free space from `$D9E28` to the end of the disk.
- The game's disk loader (`$7FB2`) identifies a disk by the first four
  characters of its first file name: `main` on disk 1, `Grou` (`Ground1`) on
  disk 2. After a save-disk swap the editor recognizes disk 2 by its first
  file name `Ground1`, and it refuses any disk whose directory starts with
  `Reserved` (a game disk) as a save disk.

## Game variables

`A5` points to the game's globals at `$9E10`.

| Address | Meaning |
| --- | --- |
| `$26(A5)` | Last raw key code |
| `$27(A5)`, `$28(A5)` | Translated key state (cleared when the editor closes, so editor keys do not reach the game) |
| `$29(A5)`, `$2D(A5)` | Level-end state; the editor cannot be opened while set |
| `$30(A5)` | Two-player mode |
| `$39(A5)` | Pause flag. Freezes lemmings, releases, object animations and the clock, while mouse and display keep running |
| `$3E(A5)` | Frame timing counter of the main loop |
| `$42(A5)` | Selected level number |
| `$CC(A5)` | Viewport back buffer |
| `$F8(A5)` | End of the file cache (after the patch: start of the editor block) |
| `$FC(A5)` | Current style data |
| `$9DA8` | Horizontal scroll |
| `$9DAA`, `$9DAC` | Cursor x, y |
| `$144F2` | Skill-selection sprite (hidden while editing) |

## Level record

The current level is copied to `$C5A6` (2048 bytes). Fields used by the
editor:

| Address | Field |
| --- | --- |
| `$C5A8` | Number of lemmings |
| `$C5AA` | Lemmings to save |
| `$C5AC` | Time limit in minutes |
| `$C5C0` | Style (0-4, selects `Ground1..5`) |
| `$C5C2` | Special background (0 = none) |
| `$CD86` | Level title, 32 characters |

## Terrain pieces

Style data starts at `$FC(A5)`. Terrain piece descriptors are at style +`$290`,
12 bytes each: width, height (words), image pointer, mask pointer (longs).
The pointers refer to the `Ground` graphics as loaded at `$75578`; the editor
rebases them to its own copy, because the game overwrites that memory with
sound data before play.

A piece has four image planes stored one after another (`width/8 * height`
bytes each) and a one-plane mask. Every piece width is a multiple of 8.

In the level's own piece list, bit 13 of a placement erases through the mask,
bit 14 flips the piece vertically and bit 15 draws it behind existing terrain.
The editor's erase mode and `F` flip match bits 13 and 14.

## Input

| Source | Meaning |
| --- | --- |
| `$BFE001` bit 6 | Left mouse button (0 = pressed) |
| `$DFF016` bit 10 (byte `$16`, bit 2) | Right mouse button (0 = pressed) |
| Raw key `$12` | E |
| Raw key `$23` | F (no gameplay action in the original game) |
| Raw keys `$4E`, `$4F` | Cursor right, left |
| Raw keys `$21`, `$28` | S, L (save and load menus) |
| Raw keys `$4C`, `$4D`, `$44`, `$43`, `$45`, `$46`, `$41` | Cursor up, down, Return, Enter, Esc, Del, Backspace (menu) |
| Raw keys `$60`/`$61`, `$E0`/`$E1` | Left/right Shift down, up |
| `$A526`, `$A586` | The game's raw-key-to-ASCII tables, unshifted and shifted (save names) |
