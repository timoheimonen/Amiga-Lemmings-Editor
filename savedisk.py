#!/usr/bin/env python3
# Lemmings In-Game Level Editor V1.2.1
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Create and exchange editor save disks without distributing game data."""
from __future__ import annotations

import argparse
from collections import Counter
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
SLOT_SIZE = 2048
SLOTS_PER_TRACK = 2
SLOT_COUNT = (TRACK_COUNT - 1) * SLOTS_PER_TRACK
HEADER_SIZE = 64
INDEX_ENTRY_SIZE = 3
INDEX_SIZE = SLOT_COUNT * INDEX_ENTRY_SIZE
INDEX_END = HEADER_SIZE + INDEX_SIZE
FORMAT_VERSION = 1
COMPATIBILITY = 0x00010001
LEVEL_COUNT = 120
PER_LEVEL = 32
MAX_EDITS = 400
DISK_MAGIC = b'LEMSAVE\0'
SAVE_MAGIC = b'LEMEDIT\0'
CATALOG = Path(__file__).with_name('bases.json')


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


def base_catalog() -> List[Dict]:
    catalog = json.loads(CATALOG.read_text())
    if catalog['compatibility'] != COMPATIBILITY or len(catalog['levels']) != LEVEL_COUNT:
        raise ValueError('Incompatible base-level catalog')
    return catalog['levels']


@dataclass(frozen=True)
class Save:
    level: int
    base_crc: int
    name: str
    placements: bytes

    @property
    def count(self) -> int:
        return len(self.placements) // 4

    def validate(self, bases: List[Dict]) -> None:
        if not 0 <= self.level < LEVEL_COUNT:
            raise ValueError('Invalid single-player level')
        base = bases[self.level]
        if self.base_crc != int(base['crc32'], 16):
            raise ValueError('Base-level checksum mismatch')
        if not 1 <= len(self.name) <= 16 or any(not 32 <= ord(c) <= 126 for c in self.name):
            raise ValueError('Name must contain 1..16 printable ASCII characters')
        if not self.name.strip():
            raise ValueError('Name must not be blank')
        if len(self.placements) % 4 or self.count + base['original_count'] > MAX_EDITS:
            raise ValueError('Placement capacity exceeded or invalid record length')
        for high, low in struct.iter_unpack('>HH', self.placements):
            if high & 0x8000 or low & 0x40 or (low & 0x3f) >= base['piece_count']:
                raise ValueError('Invalid placement flags or piece ID')

    def encode(self, bases: List[Dict], *, padded: bool = False) -> bytes:
        self.validate(bases)
        data = bytearray(SLOT_SIZE if padded else HEADER_SIZE + len(self.placements))
        struct.pack_into('>8sHHIHHI', data, 0, SAVE_MAGIC, FORMAT_VERSION,
                         HEADER_SIZE, COMPATIBILITY, self.level, self.count, self.base_crc)
        data[24:40] = self.name.encode('ascii').ljust(16, b'\0')
        data[64:64 + len(self.placements)] = self.placements
        # Slot and export use the same checksum over the used prefix only.
        used = seal(data[:64 + len(self.placements)])
        data[:len(used)] = used
        return bytes(data)

    @classmethod
    def decode(cls, data: bytes, bases: List[Dict], *, padded: bool = False) -> Save:
        if len(data) < HEADER_SIZE:
            raise ValueError('Truncated save')
        magic, version, header, compat, level, count, base = struct.unpack_from('>8sHHIHHI', data)
        if (magic, version, header, compat) != (SAVE_MAGIC, FORMAT_VERSION, HEADER_SIZE, COMPATIBILITY):
            raise ValueError('Unsupported save format or editor compatibility')
        used = HEADER_SIZE + count * 4
        if count > MAX_EDITS or len(data) != (SLOT_SIZE if padded else used) or used > len(data):
            raise ValueError('Invalid save length or placement count')
        if any(data[40:60]) or any(data[used:]):
            raise ValueError('Nonzero reserved save bytes')
        check_crc(data[:used])
        raw_name = data[24:40]
        name = raw_name.split(b'\0', 1)[0]
        if raw_name != name.ljust(16, b'\0'):
            raise ValueError('Invalid name padding')
        try:
            result = cls(level, base, name.decode('ascii'), data[64:used])
        except UnicodeDecodeError as error:
            raise ValueError('Invalid save name') from error
        result.validate(bases)
        return result


def new_disk() -> bytes:
    data = bytearray(DISK_SIZE)
    struct.pack_into('>8sHHIHHHHHH', data, 0, DISK_MAGIC, FORMAT_VERSION,
                     HEADER_SIZE, COMPATIBILITY, SECTOR_SIZE, 11, TRACK_COUNT,
                     SLOT_SIZE, SLOT_COUNT, PER_LEVEL)
    struct.pack_into('>HH', data, 28, INDEX_ENTRY_SIZE, INDEX_SIZE)
    data[HEADER_SIZE:INDEX_END] = b'\xff\0\0' * SLOT_COUNT
    seal_index(data)
    return bytes(data)


def seal_index(data: bytearray) -> None:
    struct.pack_into('>I', data, 32, crc(data[HEADER_SIZE:INDEX_END]))
    data[:HEADER_SIZE] = seal(data[:HEADER_SIZE])


def read_header(data: bytes, *, check_index: bool = True) -> List[Tuple[int, int]]:
    """Require supported identity even during index recovery."""
    if len(data) != DISK_SIZE:
        raise ValueError('Expected a standard 901120-byte ADF')
    if data[:32] != new_disk()[:32] or any(data[36:60]) or any(data[INDEX_END:TRACK_SIZE]):
        raise ValueError('Not a supported save disk (header mismatch)')
    check_crc(data[:HEADER_SIZE])
    entries = list(struct.iter_unpack('>BH', data[HEADER_SIZE:INDEX_END]))
    if check_index:
        if crc(data[HEADER_SIZE:INDEX_END]) != struct.unpack_from('>I', data, 32)[0]:
            raise ValueError('Index checksum mismatch; use rebuild-index')
        for level, count in entries:
            if not (level == 255 and count == 0 or level < LEVEL_COUNT and count <= MAX_EDITS):
                raise ValueError('Invalid slot index entry; use rebuild-index')
        if any(n > PER_LEVEL for n in Counter(level for level, _ in entries if level != 255).values()):
            raise ValueError('Index has more than 32 saves for one level; use rebuild-index')
    return entries


def scan_slots(data: bytes, bases: List[Dict]) -> List[Optional[Save]]:
    """Validate every physical slot, independently of the allocation index."""
    for track in range(1, TRACK_COUNT):
        start = track * TRACK_SIZE + SLOTS_PER_TRACK * SLOT_SIZE
        if any(data[start:(track + 1) * TRACK_SIZE]):
            raise ValueError(f'Nonzero reserved sectors on track {track}')
    saves = []
    for index in range(SLOT_COUNT):
        offset = slot_offset(index)
        raw = data[offset:offset + SLOT_SIZE]
        try:
            saves.append(Save.decode(raw, bases, padded=True) if any(raw) else None)
        except ValueError as error:
            raise ValueError(f'Slot {index + 1}: {error}') from error
    if any(n > PER_LEVEL for n in Counter(s.level for s in saves if s is not None).values()):
        raise ValueError('More than 32 saves for one level')
    return saves


def index_entry(save: Optional[Save]) -> Tuple[int, int]:
    return (255, 0) if save is None else (save.level, save.count)


def set_index_entry(data: bytearray, slot: int, save: Optional[Save]) -> None:
    struct.pack_into('>BH', data, HEADER_SIZE + slot * INDEX_ENTRY_SIZE, *index_entry(save))


def read_disk(data: bytes, bases: List[Dict]) -> List[Optional[Save]]:
    entries = read_header(data)
    saves = scan_slots(data, bases)
    for slot, (entry, save) in enumerate(zip(entries, saves)):
        if entry != index_entry(save):
            raise ValueError(f'Slot {slot + 1}: index mismatch; use rebuild-index')
    return saves


def rebuild_index(data: bytes, bases: List[Dict]) -> bytes:
    """Repair only the index after a complete, successful physical-slot scan."""
    read_header(data, check_index=False)
    saves = scan_slots(data, bases)
    result = bytearray(data)
    for slot, save in enumerate(saves):
        set_index_entry(result, slot, save)
    seal_index(result)
    return bytes(result)


def slot_offset(index: int) -> int:
    if not 0 <= index < SLOT_COUNT:
        raise ValueError(f'Slot must be in 1..{SLOT_COUNT}')
    return (1 + index // SLOTS_PER_TRACK) * TRACK_SIZE + (index % SLOTS_PER_TRACK) * SLOT_SIZE


def choose_slot(saves: List[Optional[Save]], level: int) -> int:
    """Pick a free slot so that a level's saves share as few tracks as possible.

    The two slots of a track are 2t and 2t+1. Prefer the free partner of a slot
    that already holds this level, then a slot on a completely free track, then
    any free slot. The menu reads one track per pair, so pairing halves the
    number of tracks it has to read for a level.
    """
    free = [i for i, entry in enumerate(saves) if entry is None]
    if not free:
        raise ValueError('Save disk full')
    for i in free:
        partner = saves[i ^ 1]
        if partner is not None and partner.level == level:
            return i
    for i in free:
        if saves[i ^ 1] is None:
            return i
    return free[0]


def import_save(data: bytes, save: Save, bases: List[Dict], *, slot: Optional[int] = None,
                replace: bool = False) -> Tuple[bytes, int]:
    saves = read_disk(data, bases)
    encoded = save.encode(bases, padded=True)
    if slot is None:
        slot = choose_slot(saves, save.level)
    offset = slot_offset(slot)
    if saves[slot] is not None and not replace:
        raise ValueError('Slot occupied; use --replace to overwrite')
    if saves[slot] is not None and saves[slot].level != save.level:
        raise ValueError('Cannot overwrite a different level')
    count = sum(s is not None and s.level == save.level for i, s in enumerate(saves) if i != slot)
    if count >= PER_LEVEL:
        raise ValueError('This level already has 32 saves')
    result = bytearray(data)
    result[offset:offset + SLOT_SIZE] = encoded
    set_index_entry(result, slot, save)
    seal_index(result)
    return bytes(result), slot


def delete_save(data: bytes, slot: int, bases: List[Dict], *, force: bool = False) -> bytes:
    """Clear one slot using the same validation as batch deletion."""
    return delete_saves(data, [slot], bases, force=force)


def delete_saves(data: bytes, slots: List[int], bases: List[Dict], *, force: bool = False) -> bytes:
    """Clear selected slots together, then validate the complete prospective disk."""
    if not slots:
        raise ValueError('Select at least one slot')
    targets = [(slot, slot_offset(slot)) for slot in dict.fromkeys(slots)]
    if len(data) != DISK_SIZE:
        raise ValueError('Expected a standard 901120-byte ADF')
    if not force:
        read_disk(data, bases)
    else:
        read_header(data)
    result = bytearray(data)
    for slot, offset in targets:
        if not any(data[offset:offset + SLOT_SIZE]):
            raise ValueError('Slot is empty')
        result[offset:offset + SLOT_SIZE] = bytes(SLOT_SIZE)
        set_index_entry(result, slot, None)
    # Validate once after clearing every target so damaged slots cannot block
    # each other's recovery. All bytes outside the selected slots still validate.
    seal_index(result)
    read_disk(bytes(result), bases)
    return bytes(result)


def write_new(path: Path, data: bytes) -> None:
    # Exclusive creation cannot overwrite an original disk or an existing export.
    with path.open('xb') as output:
        output.write(data)


def replace_disk(path: Path, before: bytes, after: bytes) -> None:
    # Only a validated save disk reaches this function. Preserve file permissions
    # and replace atomically so a failed host write leaves the previous disk intact.
    if path.is_symlink() or not path.is_file():
        raise ValueError('Disk must be a regular file, not a symbolic link')
    mode = path.stat().st_mode & 0o777
    if not mode & 0o222:
        raise ValueError('Save disk is write-protected')
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
    create = sub.add_parser('create', help='Create a new empty save ADF; never overwrite')
    create.add_argument('disk', type=Path)
    listing = sub.add_parser('list', help='Validate and list saves')
    listing.add_argument('disk', type=Path)
    listing.add_argument('--level', type=int, choices=range(LEVEL_COUNT), metavar='0..119')
    export = sub.add_parser('export', help='Export a physical slot to a new .lemsave file')
    export.add_argument('disk', type=Path)
    export.add_argument('slot', type=int)
    export.add_argument('output', type=Path)
    importing = sub.add_parser('import', help='Import a compatible .lemsave file')
    importing.add_argument('disk', type=Path)
    importing.add_argument('save', type=Path)
    importing.add_argument('--slot', type=int, help='Physical slot 1..318; default: paired allocation')
    importing.add_argument('--replace', action='store_true')
    delete = sub.add_parser('delete', help='Delete saves and free their slots together')
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
            write_new(args.disk, new_disk())
            print(f'Created {SLOT_COUNT} empty slots')
            return
        bases = base_catalog()
        data = args.disk.read_bytes()
        if args.command == 'rebuild-index':
            replace_disk(args.disk, data, rebuild_index(data, bases))
            print('Rebuilt slot index')
            return
        if args.command == 'delete':
            if not args.yes:
                raise ValueError('Deletion requires --yes')
            after = delete_saves(data, [slot - 1 for slot in args.slots], bases, force=args.force)
            replace_disk(args.disk, data, after)
            return
        saves = read_disk(data, bases)
        if args.command == 'list':
            for i, save in enumerate(saves):
                if save is not None and (args.level is None or save.level == args.level):
                    print(f'{i + 1:3}  level {save.level:3}  {save.name:16}  {save.count:3} edits')
            print(f'{saves.count(None)}/{SLOT_COUNT} free slots')
        elif args.command == 'export':
            slot_offset(args.slot - 1)
            save = saves[args.slot - 1]
            if save is None:
                raise ValueError('Slot is empty')
            write_new(args.output, save.encode(bases))
        elif args.command == 'import':
            if args.replace and args.slot is None:
                raise ValueError('--replace requires --slot')
            save = Save.decode(args.save.read_bytes(), bases)
            after, slot = import_save(data, save, bases,
                                      slot=None if args.slot is None else args.slot - 1,
                                      replace=args.replace)
            replace_disk(args.disk, data, after)
            print(f'Imported into slot {slot + 1}')
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f'Error: {error}\n')


if __name__ == '__main__':
    main()
