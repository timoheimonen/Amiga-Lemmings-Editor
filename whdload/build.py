#!/usr/bin/env python3
# Lemmings In-Game Level Editor V2.0
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Build the WHDLoad install of Lemmings with the in-game level editor.

Usage: python3 whdload/build.py DISK1 DISK2 -o OUTPUT_DIR [--vasm PATH]

DISK1 is the disk 1 image patched for WHDLoad, whose editor keeps the custom
levels as files in the directory Levels; DISK2 is the unchanged disk 2 image.
The output directory receives the
install: Lemmings.slave, the two images as Disk.1 and Disk.2, and the icon
Lemmings.info that starts it from Workbench. Requires the vasm 68000
assembler with Motorola syntax (vasmm68k_mot).
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
# Tool types in parentheses are disabled; removing the parentheses in the
# icon's Information window makes WHDLoad write saved levels at once
# (see README.md).
ICON_TOOLTYPES = ['SLAVE=Lemmings.slave', 'PRELOAD', '(NOWRITECACHE)', '(WRITEDELAY=25)']


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


def slave(vasm: str, code_size: int, editor_size: int) -> bytes:
    """Assemble the slave for the patched Code and Editor files of these
    lengths; it refuses disk images whose files differ."""
    with tempfile.TemporaryDirectory() as work:
        output = Path(work) / 'Lemmings.slave'
        subprocess.run([vasm, '-m68000', '-Fhunkexe', '-nosym', '-quiet',
                        '-I', str(ROOT / 'src'), f'-DCODE_SIZE={code_size}',
                        f'-DEDITOR_SIZE={editor_size}',
                        '-o', str(output), str(ROOT / 'src' / 'slave.s')], check=True)
        return output.read_bytes()


def icon() -> bytes:
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
    tooltypes = struct.pack('>I', (len(ICON_TOOLTYPES) + 1) * 4)
    return (disk_object + image + b''.join(planes) + string('WHDLoad')
            + tooltypes + b''.join(string(t) for t in ICON_TOOLTYPES))


def install(vasm: str, disk1: bytes, disk2: bytes) -> dict[str, bytes]:
    """The files of the install, by name."""
    code, editor = file_size(disk1, b'Code'), file_size(disk1, b'Editor')
    return {'Lemmings.slave': slave(vasm, code, editor), 'Disk.1': disk1,
            'Disk.2': disk2, 'Lemmings.info': icon()}


def write(path: Path, data: bytes) -> None:
    """Write a new file and move it into place."""
    with tempfile.NamedTemporaryFile(dir=path.parent, suffix='.tmp', delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(data)
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('disk1', type=Path, help='disk 1 image patched for WHDLoad')
    parser.add_argument('disk2', type=Path, help='unchanged disk 2 image')
    parser.add_argument('-o', '--output', type=Path, required=True,
                        help='directory for the install')
    parser.add_argument('--vasm', default='vasmm68k_mot',
                        help='path or name of the vasm 68000 assembler')
    args = parser.parse_args()
    vasm = shutil.which(args.vasm)
    if not vasm:
        parser.exit(1, f'error: assembler not found: {args.vasm}\n')
    try:
        disk1, disk2 = args.disk1.read_bytes(), args.disk2.read_bytes()
        check(disk1, b'main\0', args.disk1, True)
        check(disk2, b'Ground1\0', args.disk2, False)
        files = install(vasm, disk1, disk2)
        args.output.mkdir(parents=True, exist_ok=True)
        for name, data in files.items():
            write(args.output / name, data)
        (args.output / LEVELS).mkdir(exist_ok=True)
    except subprocess.CalledProcessError as error:
        parser.exit(1, f'error: assembly failed: {error}\n')
    except (OSError, ValueError) as error:
        parser.exit(1, f'error: {error}\n')
    print(f'{args.output}: {", ".join(files)}, {LEVELS}/')


if __name__ == '__main__':
    main()
