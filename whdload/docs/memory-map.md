# WHDLoad memory map

## BaseMem (chip memory, `$0..$7FFFF`)

The game's own chip memory, used as on floppy. `$70000..$70FFF` holds the
disk 1 directory while the slave looks for `Code`; the game overwrites it
later.

## ExpMem

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
