#!/usr/bin/env python3
# Lemmings In-Game Level Editor V2.0
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Create level disks and exchange custom levels without distributing game data."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import struct
import tempfile
from typing import Dict, List, Optional, Tuple
import zlib

SECTOR_SIZE = 512
TRACK_SIZE = 11 * SECTOR_SIZE
TRACK_COUNT = 160
DISK_SIZE = TRACK_COUNT * TRACK_SIZE
SLOTS_PER_TRACK = 2
SLOT_COUNT = (TRACK_COUNT - 1) * SLOTS_PER_TRACK
HEADER_SIZE = 64
DISK_MAGIC = b'LEMSAVE\0'
SAVE_FORMAT = 1                         # a V1.x editor's save disk
CATALOG = Path(__file__).with_name('styles.json')


def crc(data: bytes) -> int:
    return zlib.crc32(data) & 0xffffffff


def seal(data: bytearray) -> bytes:
    struct.pack_into('>I', data, 60, 0)
    struct.pack_into('>I', data, 60, crc(data))
    return bytes(data)


def check_crc(data: bytes) -> None:
    clean = bytearray(data)
    expected = struct.unpack_from('>I', clean, 60)[0]
    clean[60:64] = bytes(4)
    if crc(clean) != expected:
        raise ValueError('Checksum mismatch')


# Level disk, disk format version 2: complete custom levels in the game's own
# 2048-byte level record. Format version 1 is the save disk of the V1.x
# editor, which this version does not use.
LEVEL_FORMAT = 2
LEVEL_COMPATIBILITY = 0x00020001
LEVEL_SIZE = 2048
LEVEL_SLOT_SIZE = TRACK_SIZE // SLOTS_PER_TRACK
LEVEL_ENTRY_SIZE = 2
LEVEL_INDEX_SIZE = SLOT_COUNT * LEVEL_ENTRY_SIZE
LEVEL_INDEX_END = HEADER_SIZE + LEVEL_INDEX_SIZE
# The V1.x editor's save menu refuses a disk with the game disks' first
# directory name at $400 of track 0 as a game disk instead of offering to
# initialize it.
GUARD_OFFSET = 0x400
GUARD = b'Reserved'
STYLE_COUNT = 5
TERRAIN_END = b'\xff' * 4
OBJECT_FLAGS = (0x000f, 0x400f, 0x800f, 0xc00f)
# The game draws terrain pieces until the end marker, without a count limit,
# so a playable record keeps at least one marker: at most 399 pieces.
MAX_PIECES = 399
MAX_LEMMINGS = 160                      # lemming records up to the object instances
MAX_SCROLL = 1280                       # the view scrolls in steps of 4 up to 1280
ENTRANCE = 1                            # object type of an entrance, in every style
MARKER = 2                              # the two-player exit marker, in every style
MAX_ENTRANCES = 4                       # the game's entrance table
TRIGGER_SLOTS = 16                      # objects with a trigger area in the grid
GRID_WIDTH = 408                        # attribute grid, cells of 4 x 4 pixels
GRID_HEIGHT = 42


def style_catalog() -> List[Dict]:
    styles = json.loads(CATALOG.read_text())
    if len(styles) != STYLE_COUNT:
        raise ValueError('Incompatible style catalog')
    return styles


def check_record(record: bytes, styles: List[Dict]) -> None:
    """Reject level records the Amiga game cannot play safely.

    The limits are the game's own: its lemming records, entrance table,
    attribute grid (408 x 42 cells of 4 x 4 pixels, written without clipping
    by steel areas and the trigger boxes of the first 16 objects), scrolling
    range, terrain end marker, one-digit time and two-digit counters.
    """
    if len(record) != LEVEL_SIZE:
        raise ValueError('Expected a 2048-byte level record')
    rate, lemmings, required, minutes, *skills = struct.unpack_from('>12H', record)
    start_x, style, special, unused = struct.unpack_from('>4H', record, 0x18)
    if not (rate <= 99 and 1 <= lemmings <= MAX_LEMMINGS and required <= lemmings
            and 1 <= minutes <= 9 and max(skills) <= 99):
        raise ValueError('Level parameter out of range')
    if start_x > MAX_SCROLL or start_x % 4:
        raise ValueError('Start position must be a multiple of 4 up to 1280')
    if style >= STYLE_COUNT or special > 4 or unused:
        raise ValueError('Invalid graphics style or special background')
    entrances = 0
    for slot in range(32):
        x, y, kind, flags = struct.unpack_from('>hhHH', record, 0x20 + slot * 8)
        if not x:
            continue
        if kind >= styles[style]['object_count'] or flags not in OBJECT_FLAGS:
            raise ValueError(f'Object {slot + 1}: invalid type or flags')
        entrances += kind == ENTRANCE
        if slot < TRIGGER_SLOTS:
            tx, ty, tw, th = styles[style]['triggers'][kind]
            if (x < 0 or y < 0 or (x >> 2) + tx + tw > GRID_WIDTH
                    or (y >> 2) + ty + th > GRID_HEIGHT):
                raise ValueError(f'Object {slot + 1}: trigger area outside the level')
    if entrances > MAX_ENTRANCES:
        raise ValueError(f'More than {MAX_ENTRANCES} entrances')
    terrain = [record[offset:offset + 4] for offset in range(0x120, 0x760, 4)]
    if TERRAIN_END not in terrain[:MAX_PIECES + 1]:
        raise ValueError(f'More than {MAX_PIECES} terrain pieces')
    count = terrain.index(TERRAIN_END)
    if any(entry != TERRAIN_END for entry in terrain[count:]):
        raise ValueError('Terrain entries after the end marker')
    if special and count:
        raise ValueError('A special background level has no terrain pieces')
    for number, entry in enumerate(terrain[:count]):
        if entry[3] & 0x3f >= styles[style]['piece_count']:
            raise ValueError(f'Terrain piece {number + 1}: invalid piece')
    for number in range(32):
        high, low = struct.unpack_from('>HH', record, 0x760 + number * 4)
        if (high or low) and ((high >> 7) + ((low >> 12) & 15) + 1 > GRID_WIDTH
                              or (high & 127) + ((low >> 8) & 15) + 1 > GRID_HEIGHT - 1):
            raise ValueError(f'Steel area {number + 1}: outside the level')
    title = record[0x7e0:]
    if any(not 32 <= c <= 126 for c in title) or not title.strip():
        raise ValueError('Title must be 32 printable ASCII characters, not all spaces')


def two_player(record: bytes, styles: List[Dict]) -> bool:
    """Whether a checked record is valid for the game's two-player mode.

    It needs an entrance, the marker (the first object of type 2) and exits of
    both players. A lemming at x, y in an exit counts for the green player
    when |x - 8 - marker x| + |y - 32 - marker y| <= 32, otherwise for the
    blue player; an exit is the green player's when the nearest point of its
    trigger area is that near. Only the first 16 slots have trigger areas.
    """
    style = struct.unpack_from('>H', record, 0x1a)[0]
    objects = [struct.unpack_from('>hhHH', record, 0x20 + slot * 8) for slot in range(32)]
    marker = next(((x, y) for x, y, kind, _ in objects if x and kind == MARKER), None)
    if marker is None or not any(x and kind == ENTRANCE for x, _, kind, _ in objects):
        return False
    point = (marker[0] + 8, marker[1] + 32)
    owners = set()
    for x, y, kind, _ in objects[:TRIGGER_SLOTS]:
        if not x or kind not in styles[style]['exits']:
            continue
        tx, ty, tw, th = styles[style]['triggers'][kind]
        near = 0
        for start, size, centre in ((((x >> 2) + tx) * 4, tw * 4, point[0]),
                                    (((y >> 2) + ty) * 4, th * 4, point[1])):
            near += max(start - centre, centre - (start + size - 1), 0)
        owners.add('green' if near <= 32 else 'blue')
    return owners == {'blue', 'green'}


@dataclass(frozen=True)
class Level:
    """A custom level: the 2048-byte record exactly as the Amiga game plays it."""
    record: bytes

    @property
    def title(self) -> str:
        return self.record[0x7e0:].decode('ascii').rstrip()

    @property
    def style(self) -> int:
        return struct.unpack_from('>H', self.record, 0x1a)[0]

    def validate(self, styles: List[Dict]) -> None:
        check_record(self.record, styles)

    def encode(self, styles: List[Dict]) -> bytes:
        """Return the complete disk slot: the record and zero padding."""
        self.validate(styles)
        return self.record + bytes(LEVEL_SLOT_SIZE - LEVEL_SIZE)

    @classmethod
    def decode(cls, data: bytes, styles: List[Dict]) -> Level:
        if len(data) != LEVEL_SLOT_SIZE:
            raise ValueError('Invalid level slot length')
        if any(data[LEVEL_SIZE:]):
            raise ValueError('Nonzero padding after the level record')
        result = cls(bytes(data[:LEVEL_SIZE]))
        result.validate(styles)
        return result


def check_level_disk(data: bytes) -> None:
    """Refuse anything but a level disk before reading it as one; a V1.x save
    disk is named, so it is never taken for a damaged level disk."""
    if len(data) != DISK_SIZE:
        raise ValueError('Expected a standard 901120-byte ADF')
    version = struct.unpack_from('>H', data, 8)[0]
    if data[:8] == DISK_MAGIC and version == SAVE_FORMAT:
        raise ValueError('This is a save disk of the V1.x editor, not a level disk; '
                         'use the savedisk.py of the V1.x editor for it')
    if data[:8] != DISK_MAGIC or version != LEVEL_FORMAT:
        raise ValueError('Not a level disk (header mismatch)')


def new_level_disk() -> bytes:
    data = bytearray(DISK_SIZE)
    struct.pack_into('>8sHHIHHHHHHHH', data, 0, DISK_MAGIC, LEVEL_FORMAT, HEADER_SIZE,
                     LEVEL_COMPATIBILITY, SECTOR_SIZE, 11, TRACK_COUNT, LEVEL_SLOT_SIZE,
                     SLOT_COUNT, LEVEL_SIZE, LEVEL_ENTRY_SIZE, LEVEL_INDEX_SIZE)
    data[GUARD_OFFSET:GUARD_OFFSET + len(GUARD)] = GUARD
    seal_level_index(data)
    return bytes(data)


def seal_level_index(data: bytearray) -> None:
    struct.pack_into('>I', data, 32, crc(data[HEADER_SIZE:LEVEL_INDEX_END]))
    data[:HEADER_SIZE] = seal(data[:HEADER_SIZE])


def read_level_header(data: bytes, *, check_index: bool = True) -> List[Tuple[int, int]]:
    """Require supported identity even during index recovery."""
    if len(data) != DISK_SIZE:
        raise ValueError('Expected a standard 901120-byte ADF')
    guard_end = GUARD_OFFSET + len(GUARD)
    if (data[:32] != new_level_disk()[:32] or any(data[36:60])
            or any(data[LEVEL_INDEX_END:GUARD_OFFSET]) or data[GUARD_OFFSET:guard_end] != GUARD
            or any(data[guard_end:TRACK_SIZE])):
        raise ValueError('Not a supported level disk (header mismatch)')
    check_crc(data[:HEADER_SIZE])
    entries = list(struct.iter_unpack('>BB', data[HEADER_SIZE:LEVEL_INDEX_END]))
    if check_index:
        if crc(data[HEADER_SIZE:LEVEL_INDEX_END]) != struct.unpack_from('>I', data, 32)[0]:
            raise ValueError('Index checksum mismatch; use rebuild-index')
        for state, style in entries:
            if not ((state, style) == (0, 0) or state in (1, 2) and style < STYLE_COUNT):
                raise ValueError('Invalid slot index entry; use rebuild-index')
    return entries


def level_slot_offset(index: int) -> int:
    if not 0 <= index < SLOT_COUNT:
        raise ValueError(f'Slot must be in 1..{SLOT_COUNT}')
    return (1 + index // SLOTS_PER_TRACK) * TRACK_SIZE + (index % SLOTS_PER_TRACK) * LEVEL_SLOT_SIZE


def scan_levels(data: bytes, styles: List[Dict]) -> List[Optional[Level]]:
    """Validate every physical slot, independently of the index."""
    levels = []
    for index in range(SLOT_COUNT):
        offset = level_slot_offset(index)
        raw = data[offset:offset + LEVEL_SLOT_SIZE]
        try:
            levels.append(Level.decode(raw, styles) if any(raw) else None)
        except ValueError as error:
            raise ValueError(f'Slot {index + 1}: {error}') from error
    return levels


def level_entry(level: Optional[Level], styles: List[Dict]) -> Tuple[int, int]:
    """Index entry: state 0 empty, 1 a level, 2 a level valid for two players;
    the graphics style."""
    if level is None:
        return (0, 0)
    return (2 if two_player(level.record, styles) else 1, level.style)


def set_level_entry(data: bytearray, slot: int, level: Optional[Level],
                    styles: List[Dict]) -> None:
    struct.pack_into('>BB', data, HEADER_SIZE + slot * LEVEL_ENTRY_SIZE,
                     *level_entry(level, styles))


def read_level_disk(data: bytes, styles: List[Dict]) -> List[Optional[Level]]:
    entries = read_level_header(data)
    levels = scan_levels(data, styles)
    for slot, (entry, level) in enumerate(zip(entries, levels)):
        if entry != level_entry(level, styles):
            raise ValueError(f'Slot {slot + 1}: index mismatch; use rebuild-index')
    return levels


def rebuild_level_index(data: bytes, styles: List[Dict]) -> bytes:
    read_level_header(data, check_index=False)
    levels = scan_levels(data, styles)
    result = bytearray(data)
    for slot, level in enumerate(levels):
        set_level_entry(result, slot, level, styles)
    seal_level_index(result)
    return bytes(result)


def import_level(data: bytes, level: Level, styles: List[Dict], *, slot: Optional[int] = None,
                 replace: bool = False) -> Tuple[bytes, int]:
    """Store a level in the given slot or the lowest free one."""
    levels = read_level_disk(data, styles)
    encoded = level.encode(styles)
    if slot is None:
        if None not in levels:
            raise ValueError('Level disk full')
        slot = levels.index(None)
    offset = level_slot_offset(slot)
    if levels[slot] is not None and not replace:
        raise ValueError('Slot occupied; use --replace to overwrite')
    result = bytearray(data)
    result[offset:offset + LEVEL_SLOT_SIZE] = encoded
    set_level_entry(result, slot, level, styles)
    seal_level_index(result)
    return bytes(result), slot


def delete_levels(data: bytes, slots: List[int], styles: List[Dict], *, force: bool = False) -> bytes:
    """Clear selected slots together, then validate the complete prospective disk."""
    if not slots:
        raise ValueError('Select at least one slot')
    targets = [(slot, level_slot_offset(slot)) for slot in dict.fromkeys(slots)]
    if not force:
        read_level_disk(data, styles)
    else:
        read_level_header(data)
    result = bytearray(data)
    for slot, offset in targets:
        if not any(data[offset:offset + LEVEL_SLOT_SIZE]):
            raise ValueError('Slot is empty')
        result[offset:offset + LEVEL_SLOT_SIZE] = bytes(LEVEL_SLOT_SIZE)
        set_level_entry(result, slot, None, styles)
    seal_level_index(result)
    read_level_disk(bytes(result), styles)
    return bytes(result)


def write_new(path: Path, data: bytes) -> None:
    # Exclusive creation cannot overwrite an original disk or an existing export.
    with path.open('xb') as output:
        output.write(data)


def replace_disk(path: Path, before: bytes, after: bytes) -> None:
    # Only a validated level disk reaches this function. Preserve file
    # permissions and replace atomically so a failed host write leaves the
    # previous disk intact.
    if path.is_symlink() or not path.is_file():
        raise ValueError('Disk must be a regular file, not a symbolic link')
    mode = path.stat().st_mode & 0o777
    if not mode & 0o222:
        raise ValueError('Level disk is write-protected')
    temp = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.savedisk-', delete=False) as output:
            temp = Path(output.name)
            output.write(after)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temp, mode)
        if path.read_bytes() != before:
            raise ValueError('Disk changed while editing; retry with the latest image')
        os.replace(temp, path)
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    create = sub.add_parser('create', help='Create a new empty level disk ADF; never overwrite')
    create.add_argument('disk', type=Path)
    listing = sub.add_parser('list', help='Validate and list the levels')
    listing.add_argument('disk', type=Path)
    export = sub.add_parser('export', help='Export a slot to a new .lvl file')
    export.add_argument('disk', type=Path)
    export.add_argument('slot', type=int)
    export.add_argument('output', type=Path)
    importing = sub.add_parser('import', help='Import a .lvl level record')
    importing.add_argument('disk', type=Path)
    importing.add_argument('level', type=Path, metavar='file')
    importing.add_argument('--slot', type=int, help='Slot 1..318; default: the lowest free one')
    importing.add_argument('--replace', action='store_true')
    delete = sub.add_parser('delete', help='Delete levels and free their slots together')
    delete.add_argument('disk', type=Path)
    delete.add_argument('slots', type=int, nargs='+', metavar='SLOT')
    delete.add_argument('--yes', action='store_true', help='Confirm deletion')
    delete.add_argument('--force', action='store_true',
                        help='Allow clearing damaged slots; still requires --yes')
    rebuild = sub.add_parser('rebuild-index', help='Validate all slots and repair the index')
    rebuild.add_argument('disk', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'create':
            write_new(args.disk, new_level_disk())
            print(f'Created {SLOT_COUNT} empty level slots')
            return
        data = args.disk.read_bytes()
        check_level_disk(data)
        level_command(args, data)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f'Error: {error}\n')


def level_command(args: argparse.Namespace, data: bytes) -> None:
    styles = style_catalog()
    if args.command == 'rebuild-index':
        replace_disk(args.disk, data, rebuild_level_index(data, styles))
        print('Rebuilt slot index')
        return
    if args.command == 'delete':
        if not args.yes:
            raise ValueError('Deletion requires --yes')
        after = delete_levels(data, [slot - 1 for slot in args.slots], styles, force=args.force)
        replace_disk(args.disk, data, after)
        return
    levels = read_level_disk(data, styles)
    if args.command == 'list':
        for i, level in enumerate(levels):
            if level is not None:
                players = '2P' if two_player(level.record, styles) else '  '
                print(f'{i + 1:3}  style {level.style}  {players}  {level.title}')
        print(f'{levels.count(None)}/{SLOT_COUNT} free slots')
    elif args.command == 'export':
        level_slot_offset(args.slot - 1)
        level = levels[args.slot - 1]
        if level is None:
            raise ValueError('Slot is empty')
        write_new(args.output, level.record)
    elif args.command == 'import':
        if args.replace and args.slot is None:
            raise ValueError('--replace requires --slot')
        level = Level(args.level.read_bytes())
        after, slot = import_level(data, level, styles,
                                   slot=None if args.slot is None else args.slot - 1,
                                   replace=args.replace)
        replace_disk(args.disk, data, after)
        print(f'Imported into slot {slot + 1}')


if __name__ == '__main__':
    main()
