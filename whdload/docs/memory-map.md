# WHDLoad memory map

## Lemmings

### BaseMem (chip memory, `$0..$7FFFF`)

The game's own chip memory, used as on floppy. `$70000..$70FFF` holds the
disk 1 directory while the slave looks for `Code`; the game overwrites it
later.

### ExpMem

WHDLoad allocates `$80000` bytes and passes the address in `ws_ExpMem`. It
may be chip or fast memory.

| Offset | Size | Contents |
| --- | ---: | --- |
| `+$00000` | `$5FFF8` | The game's file cache (`$4` = start, `$8` = `$7FFF8`) |
| `+$5FFF8` | `$20000` | The editor block, reserved by the editor's bootstrap at the top of the cache (layout as on floppy; the `.lvl` file names at `$1A100..$1FEFF` of the block) |
| `+$7FFF8` | 8 | Mailbox from the slave to the editor |

Mailbox:

| Offset | Size | Contents |
| --- | ---: | --- |
| `+0` | 4 | `'WHDL'` |
| `+4` | 4 | resload base |

The editor finds the mailbox directly above its block.

## Holiday Lemmings 1994

The game is an AmigaDOS program of six hunks: its four and the editor's two.
`resload_Relocate` places them like `dos.LoadSeg` (segment list, hunk lengths
rounded up to 8 bytes): the chip memory hunks in BaseMem, the others in
ExpMem.

### BaseMem (chip memory, `$0..$7FFFF`)

| Address | Contents |
| --- | --- |
| `$1000` | The empty copper list WHDLoad leaves there; it stands for the system's copper lists the game saves |
| `$2000..` | The chip memory hunks: the game's chip data (hunk 1, 363112 bytes), its chip code and data (hunk 3, 37380 bytes) and the editor's status block (hunk 5, 3880 bytes), each after its segment header |
| `..$7F000` | The game's stack (user mode) |
| `..$80000` | The supervisor stack, as WHDLoad set it |

### ExpMem

WHDLoad allocates `$60000` bytes and passes the address in `ws_ExpMem`. It
may be chip or fast memory.

| Offset | Size | Contents |
| --- | ---: | --- |
| `+$00000` | | The executable as loaded from `data`, then relocated over itself: the game's start hunk (hunk 0), its code hunk (hunk 2) and the editor's hunk (hunk 4, `$20000` bytes with the editor's storage), each after its segment header |
| end of hunk 4 | 8 | Mailbox from the slave to the editor: `'WHDL'` and the resload base, as in Lemmings |
| +8 | `$17200` | The game's Icons buffer (the game allocated it with `AllocMem`) |

The editor finds the mailbox directly above its hunk.
