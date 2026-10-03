#!/usr/bin/env python3
# Lemmings In-Game Level Editor V2.3
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Build the WHDLoad install of Lemmings or Holiday Lemmings 1994 with the
in-game level editor.

Usage: python3 whdload/build.py DISK1 DISK2 -o OUTPUT_DIR [--vasm PATH]
       python3 whdload/build.py HOLIDAY_DISK -o OUTPUT_DIR [--vasm PATH]

Lemmings: DISK1 is the disk 1 image patched for WHDLoad, whose editor keeps
the custom levels as files in the directory Levels; DISK2 is the unchanged
disk 2 image. The output directory receives Lemmings.slave, the two images
as Disk.1 and Disk.2, and the icon Lemmings.info that starts it from
Workbench.

Holiday Lemmings 1994: HOLIDAY_DISK is the disk image patched for WHDLoad.
The output directory receives HolidayLemmings1994.slave, the icon
HolidayLemmings1994.info and the directory data with the game's files,
among them its executable with the editor.

Both installs get the directory Levels for the custom levels. Requires the
vasm 68000 assembler with Motorola syntax (vasmm68k_mot).
"""
from __future__ import annotations

import argparse
import os
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DISK_SIZE = 901120
LEVELS = 'Levels'                   # custom levels (.lvl files)
DIRECTORY, FIRST_RECORD, DIRECTORY_END = 0x400, 0x410, 0x1400

# The icon's picture: '.' background (colour 0), 'k' black (1), 'w' white (2),
# 'b' blue (3) in the standard Workbench palette.
ICON_PICTURE = '''\
..........kk.k.kk.........
.........kkkkkkkkk........
........kkkkkkkkkkk.......
.......kkkwwwwwwwkkk......
.......kkwwkwwwkwwkk......
........kwwwwwwwwwk.......
.........wwwwwwwww........
..........wwwwwww.........
.......bbbbbbbbbbbbb......
......bbbbbbbbbbbbbbb.....
.....wwbbbbbbbbbbbbbww....
.....ww.bbbbbbbbbbb.ww....
........bbbbbbbbbbb.......
........bbbbbbbbbbb.......
.........bbbb.bbbb........
.........bbbb.bbbb........
........wwwww.wwwww.......
.......wwwwww.wwwwww......'''
# NOWRITECACHE makes WHDLoad write a saved level to the hard disk at once.
# Tool types in parentheses are disabled until the parentheses are removed in
# the icon's Information window (see README.md).
ICON_TOOLTYPES = ['PRELOAD', 'NOWRITECACHE', '(WRITEDELAY=25)']

# Holiday Lemmings 1994: an AmigaDOS (OFS) disk whose game is the directory
# HolidayLemmings1994. Its files go to data/, except the icons, the start
# script and a log file that the game does not read.
HOLIDAY_DIRECTORY = 'HolidayLemmings1994'
HOLIDAY_EXECUTABLE = 'HolidayLemmings1994'
HOLIDAY_SKIPPED = {'holiday lemmings 1994', 'log', 'levels'}
DATA = 'data'
OFS_ROOT, OFS_BLOCK = 880, 512


def file_size(disk1: bytes, name: bytes) -> int:
    """Length of a file in the disk 1 directory."""
    for record in range(FIRST_RECORD, DIRECTORY_END, 16):
        raw = disk1[record:record + 16]
        if raw == b'\xff' * 16:
            break
        if raw[:len(name) + 1] == name + b'\0':
            return int.from_bytes(raw[12:], 'big')
    raise ValueError(f'disk 1 has no {name.decode()} file')


def check(disk: bytes, first_file: bytes, path: Path, patched: bool) -> None:
    if (len(disk) != DISK_SIZE or disk[DIRECTORY:DIRECTORY + 8] != b'Reserved'
            or disk[FIRST_RECORD:FIRST_RECORD + len(first_file)] != first_file):
        raise ValueError(f'{path}: not a Lemmings disk image')
    if (disk[FIRST_RECORD:DIRECTORY_END].find(b'Editor\0') >= 0) != patched:
        raise ValueError(f'{path}: ' + ('not patched with the editor' if patched
                                        else 'patched; use the unchanged disk 2'))


def assemble_slave(vasm: str, source: str, defines: dict[str, int]) -> bytes:
    with tempfile.TemporaryDirectory() as work:
        output = Path(work) / 'slave'
        subprocess.run([vasm, '-m68000', '-Fhunkexe', '-nosym', '-quiet',
                        '-I', str(ROOT / 'src'),
                        *(f'-D{key}={value}' for key, value in defines.items()),
                        '-o', str(output), str(ROOT / 'src' / source)], check=True)
        return output.read_bytes()


def slave(vasm: str, code_size: int, editor_size: int) -> bytes:
    """Assemble the Lemmings slave for the patched Code and Editor files of
    these lengths; it refuses disk images whose files differ."""
    return assemble_slave(vasm, 'slave.s', {'CODE_SIZE': code_size, 'EDITOR_SIZE': editor_size})


def holiday_slave(vasm: str, executable_size: int) -> bytes:
    """Assemble the Holiday Lemmings 1994 slave for the patched executable of
    this length; it refuses other executables."""
    return assemble_slave(vasm, 'holiday94_slave.s', {'EXE_SIZE': executable_size})


def ofs_files(disk: bytes, directory: str) -> dict[str, bytes]:
    """The files of a directory of an OFS disk image, by name."""
    def block(number: int) -> bytes:
        if not 2 <= number < len(disk) // OFS_BLOCK:
            raise ValueError('not an AmigaDOS disk image')
        return disk[number * OFS_BLOCK:(number + 1) * OFS_BLOCK]

    def long(data: bytes, offset: int) -> int:
        return int.from_bytes(data[offset:offset + 4], 'big')

    blocks = len(disk) // OFS_BLOCK

    def entries(number: int) -> dict[str, int]:
        found, header, seen = {}, block(number), set()
        for slot in range(72):
            entry = long(header, 24 + 4 * slot)
            while entry:
                if entry in seen:                        # a damaged hash chain
                    raise ValueError('not an AmigaDOS disk image')
                seen.add(entry)
                data = block(entry)
                found[data[433:433 + data[432]].decode('latin-1')] = entry
                entry = long(data, 496)
        return found

    if disk[:4] != b'DOS\0':
        raise ValueError('not an AmigaDOS (OFS) disk image')
    folder = {name.lower(): number for name, number in entries(OFS_ROOT).items()}.get(directory.lower())
    if folder is None:
        raise ValueError(f'the disk has no directory {directory}')
    files = {}
    for name, number in entries(folder).items():
        header = block(number)
        if long(header, 508) != 0xfffffffd:              # ST_FILE
            continue
        if name in ('', '.', '..') or any(c in name for c in '/:\\\0'):
            raise ValueError(f'{directory} holds a file name that is not a plain name')
        size, data, following = long(header, 324), bytearray(), long(header, 16)
        for _ in range(blocks):                          # OFS data blocks
            if not following or len(data) >= size:
                break
            chunk = block(following)
            data += chunk[24:24 + long(chunk, 12)]
            following = long(chunk, 16)
        if len(data) != size:
            raise ValueError(f'{directory}/{name} is damaged')
        files[name] = bytes(data)
    return files


def icon(slave_name: str) -> bytes:
    """A Workbench project icon whose default tool is WHDLoad."""
    rows = ICON_PICTURE.splitlines()
    width, height = len(rows[0]), len(rows)
    words = (width + 15) // 16
    planes = []
    for plane in (1, 2):
        data = bytearray()
        for row in rows:
            bits = 0
            for x in range(words * 16):
                colour = '.kwb'.index(row[x]) if x < width else 0
                bits = bits << 1 | (colour & plane != 0)
            data += bits.to_bytes(words * 2, 'big')
        planes.append(bytes(data))

    def string(text: str) -> bytes:
        data = text.encode('ascii') + b'\0'
        return struct.pack('>I', len(data)) + data

    no_position = 0x80000000
    disk_object = struct.pack(
        '>HH' 'IhhhhHHH' 'IIIIIHI' 'BB' 'IIIIIII',
        0xE310, 1,                                  # magic, version
        0, 0, 0, width, height + 1, 4, 3, 1,        # gadget: size, image, boolean
        1, 0, 0, 0, 0, 0, 0,                        # gadget render image only
        4, 0,                                       # WBPROJECT
        1, 1, no_position, no_position, 0, 0, 10240)
    image = struct.pack('>hhhhhIBBI', 0, 0, width, height, 2, 1, 3, 0, 0)
    tooltypes = [f'SLAVE={slave_name}'] + ICON_TOOLTYPES
    return (disk_object + image + b''.join(planes) + string('WHDLoad')
            + struct.pack('>I', (len(tooltypes) + 1) * 4) + b''.join(string(t) for t in tooltypes))


def install(vasm: str, disk1: bytes, disk2: bytes) -> dict[str, bytes]:
    """The files of the Lemmings install, by name."""
    code, editor = file_size(disk1, b'Code'), file_size(disk1, b'Editor')
    return {'Lemmings.slave': slave(vasm, code, editor), 'Disk.1': disk1,
            'Disk.2': disk2, 'Lemmings.info': icon('Lemmings.slave')}


def holiday_install(vasm: str, disk: bytes) -> dict[str, bytes]:
    """The files of the Holiday Lemmings 1994 install, by path."""
    files = ofs_files(disk, HOLIDAY_DIRECTORY)
    if HOLIDAY_EXECUTABLE not in files:
        raise ValueError('the disk has no Holiday Lemmings 1994 executable')
    executable = files[HOLIDAY_EXECUTABLE]
    if executable[:4] != b'\0\0\x03\xf3' or int.from_bytes(executable[8:12], 'big') != 6:
        raise ValueError('the executable is not patched with the editor')
    if b'WHDL' not in executable:
        # Only the WHDLoad build of the editor looks for the slave's mailbox;
        # the floppy build's file access needs the operating system.
        raise ValueError('the executable is the floppy version; patch the disk with --whdload')
    result = {'HolidayLemmings1994.slave': holiday_slave(vasm, len(executable)),
              'HolidayLemmings1994.info': icon('HolidayLemmings1994.slave')}
    for name, data in files.items():
        if not name.lower().endswith('.info') and name.lower() not in HOLIDAY_SKIPPED:
            result[f'{DATA}/{name}'] = data
    return result


def write(path: Path, data: bytes) -> None:
    """Write a new file and move it into place."""
    with tempfile.NamedTemporaryFile(dir=path.parent, suffix='.tmp', delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(data)
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('disks', type=Path, nargs='+',
                        help='Lemmings: disk 1 patched for WHDLoad and the unchanged disk 2; '
                             'Holiday Lemmings 1994: its disk patched for WHDLoad')
    parser.add_argument('-o', '--output', type=Path, required=True,
                        help='directory for the install')
    parser.add_argument('--vasm', default='vasmm68k_mot',
                        help='path or name of the vasm 68000 assembler')
    args = parser.parse_args()
    vasm = shutil.which(args.vasm)
    if not vasm:
        parser.exit(1, f'error: assembler not found: {args.vasm}\n')
    try:
        disks = [path.read_bytes() for path in args.disks]
        if len(disks) == 2:
            check(disks[0], b'main\0', args.disks[0], True)
            check(disks[1], b'Ground1\0', args.disks[1], False)
            files = install(vasm, *disks)
        elif len(disks) == 1:
            files = holiday_install(vasm, disks[0])
        else:
            raise ValueError('give the two Lemmings disks or the Holiday Lemmings 1994 disk')
        args.output.mkdir(parents=True, exist_ok=True)
        for name, data in files.items():
            (args.output / name).parent.mkdir(exist_ok=True)
            write(args.output / name, data)
        (args.output / LEVELS).mkdir(exist_ok=True)
    except subprocess.CalledProcessError as error:
        parser.exit(1, f'error: assembly failed: {error}\n')
    except (OSError, ValueError) as error:
        parser.exit(1, f'error: {error}\n')
    shown = sorted({name.split('/')[0] + ('/' if '/' in name else '') for name in files})
    print(f'{args.output}: {", ".join(shown)}, {LEVELS}/')


if __name__ == '__main__':
    main()
