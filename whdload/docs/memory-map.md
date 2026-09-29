# WHDLoad memory map

## BaseMem (chip memory, `$0..$7FFFF`)

The game's own chip memory, used as on floppy. `$70000..$70FFF` holds the
disk 1 directory while the slave looks for `Code`; the game overwrites it
later.

## ExpMem

WHDLoad allocates `$80000` + 901120 bytes and passes the address in
`ws_ExpMem`. It may be chip or fast memory.

| Offset | Size | Contents |
| --- | ---: | --- |
| `+$00000` | `$5FFF0` | The game's file cache (`$4` = start, `$8` = `$7FFF0`) |
| `+$5FFF0` | `$20000` | The editor block, reserved by the editor's bootstrap at the top of the cache (layout as on floppy) |
| `+$7FFF0` | 16 | Mailbox from the slave to the editor |
| `+$80000` | 901120 | Save disk image buffer |

Mailbox:

| Offset | Size | Contents |
| --- | ---: | --- |
| `+0` | 4 | `'WHDL'` |
| `+4` | 4 | resload base |
| `+8` | 4 | Address of the save disk image buffer |
| `+12` | 1 | Image state: 0 not loaded yet, 1 valid, 2 no usable file |

The editor finds the mailbox directly above its block. The image is loaded
from `Lemmings_SaveDisk.adf` on first use; a missing file, or one that is not
exactly 901120 bytes, reads as an unformatted disk.
