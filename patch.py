#!/usr/bin/env python3
# Lemmings In-Game Level Editor V2.3.1
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Patch Amiga Lemmings or Holiday Lemmings 1994 disk images with the in-game
level editor.

Usage: python3 patch.py DISK1.adf [DISK2.adf] [-o OUTPUT_DIR]
       python3 patch.py DISK1.adf DISK2.adf --whdload INSTALL_DIR
       python3 patch.py HOLIDAY.adf [-o OUTPUT_DIR]
       python3 patch.py HOLIDAY.adf --whdload INSTALL_DIR

The input images may be given in any order; they are identified by their
SHA-256 hashes, which also tell the game, and only the supported ones are
accepted. The inputs are never modified.

Lemmings: only disk 1 is patched; disk 2 is used unchanged. The floppy
version is written to the output directory (default: the current directory)
as Lemmings_Disk1-editor-patch.adf; disk 2 is optional there and only
checked. With --whdload, the WHDLoad install is written instead, which needs
both disks: Lemmings.slave, Disk.1 (patched with the WHDLoad version of the
editor), Disk.2 (unchanged), the Workbench icon Lemmings.info and the empty
directory Levels for the custom levels.

Holiday Lemmings 1994: the editor is added to the game's program on its
disk, which also gets the directory Levels for the custom levels; the
floppy version is written as HolidayLemmings1994-editor-patch.adf. With
--whdload, the WHDLoad install is written instead: HolidayLemmings1994.slave,
the Workbench icon HolidayLemmings1994.info, the directory data with the
game's files (its program patched with the WHDLoad version of the editor)
and the empty directory Levels.

Requires only Python 3. The editors, the slaves and the icons are embedded
below; they are generated from the sources in src/ and whdload/ by build.py.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import os
import re
import struct
import sys
import tempfile
from pathlib import Path

# The supported Lemmings disk images, identified by their SHA-256 hashes.
DISK_SIZE = 901120
INPUT_SHA256 = {
    1: 'a4fdba69017f1a760bba3bb06c55f7e434226c498c9d22c1f627212b08d24f91',
    2: '1526000b96d196efecab9c63aa72c0ce6257649a4993141b00ead8738fd97a65',
}
OUTPUT_NAME = 'Lemmings_Disk1-editor-patch.adf'
LEVELS = 'Levels'

# Holiday Lemmings 1994: one AmigaDOS (OFS) disk. The game is the program
# HolidayLemmings1994 in the directory of the same name; the editor is added
# to it as two more hunks, its code and its chip memory.
HOLIDAY94_SHA256 = 'bdce698427db9e186332b3989162441d354b4d9fe8de8bb5f4c3e7eac729f74f'
HOLIDAY94_DIRECTORY = 'HolidayLemmings1994'
HOLIDAY94_PROGRAM = 'HolidayLemmings1994/HolidayLemmings1994'
HOLIDAY94_PROGRAM_SHA256 = '044397cdc86f78c511940c54d977cf1b57aace5c823fb41da6008644fca549db'
HOLIDAY94_OUTPUT_NAME = 'HolidayLemmings1994-editor-patch.adf'
# The WHDLoad install takes the game's files into data/, except the icons,
# the start script and a log file that the game does not read.
HOLIDAY94_DATA = 'data'
HOLIDAY94_SKIPPED = {'holiday lemmings 1994', 'log', 'levels'}
# Hook sites in the program's code hunk (hunk 2): offset, the original
# instructions (as in the file, relocated longwords unrelocated), the
# editor's label and the instruction that replaces them, padded with NOPs.
HOLIDAY94_HOOKS = [
    (0x0344, '6100fcba49f900007908', 'holiday_start', 'jmp'),
    (0x13b2, '1b40000613fc000000bfec01', 'keyboard', 'jmp'),
    (0x0482, '6100107e426d0024', 'frame', 'jmp'),
    (0x04ae, '610003e661000cae', 'actions', 'jmp'),
    (0x04b6, '61001776610056d0', 'overlay', 'jmp'),
    (0x22d0, '61000098610000b0', 'capture', 'jmp'),
    (0x2254, '41f900009b383028001a', 'custom_inject', 'jmp'),
    (0x3068, '6100f63461002bd2', 'custom_brief', 'jsr'),
    (0x30b4, '6100e49441fa3626', 'briefing_wait', 'jmp'),
    (0x053a, '422d001d43f900006bc9', 'custom_ended', 'jmp'),
    (0x0590, '422d0013302d0028', 'custom_won', 'jmp'),
    (0x06d8, '41f9000066e061000f7e', 'custom_quit', 'jmp'),
    (0x27a2, '303c0280323c00d0', 'title_sign', 'jmp'),
    (0x301e, '4a2d001c67000006', 'title_play', 'jmp'),
    (0x2ff2, '0c4000bc6f00fad6', 'title_new', 'jmp'),
    (0x3174, '302d007e5240', 'title_rating', 'jmp'),
]

# The game's own disk directory: 16-byte records at $400..$13FF (the first one
# is reserved), each a 12-byte name and a big-endian 32-bit length. File data
# starts at $1600 and is stored back to back in directory order.
DIRECTORY = 0x400
FIRST_RECORD = 0x410
DIRECTORY_END = 0x1400
PAYLOAD = 0x1600
# Disk 1 keeps its raw boot loader and the packed boot intro at
# $CA000..$CF9FF; files must end before it. The game never reads tracks
# 151..159 ($CFA00 to the end of the disk), which hold the packed editor. A
# placeholder directory entry covers the boot loader, so the game's loader,
# which adds up the lengths of the preceding entries, finds Editor there by
# name like any other file.
DISK1_PAYLOAD_LIMIT = 0xCA000
DISK1_TAIL = 0xCFA00
TAIL_PLACEHOLDER = 'BootLoader'

# The main program file "Code" loads at $400. The bootstrap is appended to it
# and must end before BOOTSTRAP_LIMIT, where the editor's chip-memory status
# bitmap starts.
CODE_BASE = 0x400
BOOTSTRAP_BASE = 0x21B4C

# BEGIN GENERATED BY build.py - do not edit by hand
VERSION = '2.3.1'
VARIANTS = {
    'floppy': {
        'reserve': 0x21B4C,
        'load_editor': 0x21B68,
        'install_editor': 0x21BD8,
        'limit': 0x21D00,
    },
    'whdload': {
        'reserve': 0x21B4C,
        'load_editor': 0x21B68,
        'install_editor': 0x21BD8,
        'limit': 0x21D00,
    },
}
HOLIDAY94_VARIANTS = {
    'floppy': {
        'holiday_start': 0x1A78,
        'keyboard': 0x132,
        'frame': 0x256,
        'actions': 0x922,
        'overlay': 0x93E,
        'capture': 0x54,
        'custom_inject': 0x1EB8,
        'custom_brief': 0x1EF8,
        'briefing_wait': 0x2064,
        'custom_ended': 0x2030,
        'custom_won': 0x1FA8,
        'custom_quit': 0x2002,
        'title_sign': 0x1A8E,
        'title_play': 0x1B58,
        'title_new': 0x1B7A,
        'title_rating': 0x1B18,
        'reserve': 0x20000,
        'chip': 0xF28,
    },
    'whdload': {
        'holiday_start': 0x17B2,
        'keyboard': 0x132,
        'frame': 0x256,
        'actions': 0x922,
        'overlay': 0x93E,
        'capture': 0x54,
        'custom_inject': 0x1BF2,
        'custom_brief': 0x1C32,
        'briefing_wait': 0x1D9E,
        'custom_ended': 0x1D6A,
        'custom_won': 0x1CE2,
        'custom_quit': 0x1D3C,
        'title_sign': 0x17C8,
        'title_play': 0x1892,
        'title_new': 0x18B4,
        'title_rating': 0x1852,
        'reserve': 0x20000,
        'chip': 0xF28,
    },
}
HOLIDAY94_SLAVE_SIZE_AT = 0x13A
HOLIDAY94_SLAVE_SIZE = 0x12345678
SHA256 = {
    'floppy bootstrap': '26f34ad27061f38e6521bf5ca5ea6594b9bc1488d4f3f546e6ec4a830e5908ae',
    'floppy Editor': 'c2b0e1128f99ed446a03a8159ccc77886d3c5307d9341642928f7f72f356d270',
    'whdload bootstrap': '26f34ad27061f38e6521bf5ca5ea6594b9bc1488d4f3f546e6ec4a830e5908ae',
    'whdload Editor': '5ea4b50c42ab0711cd49516467911ec46c1cfb0ec503a41135966fd5d658f8e1',
    'Lemmings.slave': '984e54c4422b67cf598e9ed3f8dbb990671e0d2c6ce767102c7937082c7d45af',
    'Lemmings.info': 'ec0bd941d1fa6f40203ca0338e977005847612f44dcc7d356749247c845afbab',
    'holiday94 floppy editor': 'cf7d5afde5249068756771c0a868bdcad0c6f895ca7032239496cc64ddabe3ae',
    'holiday94 floppy relocations': '078af1fbdcb65316c9062503389166ca143975e316e63bb7dfe89bb66963836e',
    'holiday94 whdload editor': 'eda073544d75cd7ecceaf904d11495c537bd8f8b1e89b61630a593e67ea8c7cc',
    'holiday94 whdload relocations': 'f1931b9967fd09c9b6df4461d886b9f06e89e73f482d6495d37afd0e6b2a099e',
    'HolidayLemmings1994.slave': '8769b40f778a6487757692a6da9a60a675645eb989fa6d9caaf9dfc9f377d7b5',
    'HolidayLemmings1994.info': 'e38f051eb4466400fd7ca86f629a48c0fdfdf9870dcea39cdd4983aa04c4951b',
}
BLOBS = {
    'floppy bootstrap': (
        '0/gACAy4AAJAAAAIZQaT/AACAAArSQD4Tvg5Hkjn//hB+gCLShBmVgy4AAJAAAAIZUxB'
        '+swiQ/kABYgAcP9yBSQ8bWFpbk64f7JKgGYwQfoAViJtAPjT/AAAsAByAE64f7JKgGYY'
        'Im0A+CBJ0fwAALAAIAFOuDk0QfoAM1DQTN8f/064PG5KQE74BRBOuD1IQfoAG0oQZwYg'
        'bQD4TpBOuCx+TvgFUEVkaXRvcgAA'
    ),
    'floppy Editor': (
        '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'
    ),
    'whdload bootstrap': (
        '0/gACAy4AAJAAAAIZQaT/AACAAArSQD4Tvg5Hkjn//hB+gCLShBmVgy4AAJAAAAIZUxB'
        '+swiQ/kABYgAcP9yBSQ8bWFpbk64f7JKgGYwQfoAViJtAPjT/AAAsAByAE64f7JKgGYY'
        'Im0A+CBJ0fwAALAAIAFOuDk0QfoAM1DQTN8f/064PG5KQE74BRBOuD1IQfoAG0oQZwYg'
        'bQD4TpBOuCx+TvgFUEVkaXRvcgAA'
    ),
    'whdload Editor': (
        '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'
    ),
    'Lemmings.slave': (
        'AAAD8wAAAAAAAAABAAAAAAAAAAAAAACfAAAD6QAAAJ9w/051V0hETE9BRFMAERAGAAgA'
        'AAAAAAAAigAAAAAAWQAIAAAANAA9AFkAAAAAAAAAAAAATGVtbWluZ3MAMTk5MSBETUEg'
        'RGVzaWduIC8gUHN5Z25vc2lzAEluLUdhbWUgTGV2ZWwgRWRpdG9yIFYyLjMuMQpieSBU'
        'aW1vIEhlaW1vbmVuAAAAAABD+v/6IogkSCA8AAAEACI8AAAQAHQBQfkABwAATqoAKEP5'
        'AAcAECY8AAAWAHgAegB8AAyR/////2c6DJFDb2RlZg5KKQAEZiIoAyopAAxgGgyRRWRp'
        'dGYSDGlvcgAEZgpKKQAGZgQsKQAM1qkADEPpABBgvrq8AAIX+mYAAKa8vAAAPLBmAACc'
        'IgUgBHQBQfkAAAQATqoAKEH6AJQgGGcKIkAgGLCRZnpg8kH6AK4z/E75AACA1iPIAACA'
        '2EH6AO4z/E75AACBZCPIAACBZjP8TnUAAIQcM/xOdQAAhDhB+gDuM/xOuQAAF1ojyAAA'
        'F1wz/E5xAAAXYCA6/pwhwAAEIfwAB//4AAggQNH8AAf/+CD8V0hETCCKTqoAIE75AAAE'
        'AEh4AAkvOv7UWJdOdQAAgNZKQGsAAACBZFD5AAAAAIQcCLkABwAAhDgI+QAHAAAXWgj5'
        'AAYAAAAASOfg4HABtLxtYWluZxpwArS8R3JvdWcQcAAQLQACVUCwfAABZwJwAiQAVAAb'
        'QAACIDwAAAQAIjwAABAAIG0ABCR6/mBOqgAoQm0AFEzfBwdOdUjn4GAvCCIHdAAULQAC'
        'VUIkev4+TqoAKCBf0cdM3wYHTnUI+QAGAL/uAS8AEDr9u7AtACZnBCAfTnVIeP//Lzr+'
        'EFiXTnUAAAPy'
    ),
    'Lemmings.info': (
        '4xAAAQAAAAAAAAAAABoAEwAEAAMAAQAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAA'
        'AAABAAAAAYAAAACAAAAAAAAAAAAAAAAAACgAAAAAAAAaABIAAgAAAAEDAAAAAAAANYAA'
        'AH/AAAD/4AABwHAAAZEwAACAIAAAAAAAAAAAAAH/8AAD//gAAf/wAAD/4AAA/+AAAP/g'
        'AAB7wAAAe8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP4AAAG7AAAB/wAAAf8AAAD+AAAH/'
        '8AAD//gAB//8AAb/7AAA/+AAAP/gAAB7wAAAe8AAAPvgAAH78AAAAAAIV0hETG9hZAAA'
        'AAAUAAAAFVNMQVZFPUxlbW1pbmdzLnNsYXZlAAAAAAhQUkVMT0FEAAAAAA1OT1dSSVRF'
        'Q0FDSEUAAAAAEChXUklURURFTEFZPTI1KQA='
    ),
    'holiday94 floppy editor': (
        'SOf//kn6TiogTDA8J3pCWFHI//xB+v/q0fwAALAAKUgACGEADmBB+g64Q/kAAA8AMDwA'
        'EzLYUcj//CA8AAAAADPAAAAPHkhAM8AAAA8aTN9//051TrkAACNqSOf//kn6TdBhAAwk'
        'QiwBUEIsAVRCLAFWQiwBUUIsAX9CLAGAQiwBgUIsAYJCLAGIQmwAXkJsAFxCLAFhQmwA'
        'JEKsABBCLAF1QiwBdkIsAYVhAEB+OXz//wB+OXz//wCAQiwBc0IsAXRCLAF5QmwApEos'
        'AW9nUkosAXBX7AFWQiwBcGEABG5B+g4mMDkAAJtSsHwAAmIy0DwAMRFAAAYibAAIcgBO'
        'uQAALfggbAAIIkggAU65AAA0mCBtAO5hAAfAOUAAJlbsAVRM33//TrkAACOGTvkAACLY'
        'G0AABkn6TPhhAACoSiwBV2cOsDwARWYAAIxQ7AFYYCJKLAFdZgZKLAFmZwZhABRiYBBK'
        'LAFvZ2ywPABFZhBQ7AF5sDwARWZcEDwAxWBWSgBrUmEARLRmTLA8ABJmCAosAAEAXGA+'
        'sDwATmYGUiwAXWAysDwAT2YGUywAXWAmsDwAI2YOSiwBUGcaCiwAAQBfYBKwPAA1ZgxK'
        'LAFQZwYKLAABAYAT/AAAAL/sAU75AAATvrA8AGBnGLA8AGFnErA8AOBnBrA8AOFmCkIs'
        'AWROdVDsAWROdQg5AAYAv+ABV+wBUgguAAIAFlfsAVNOdQg5AAYAv+ABV8CwLAFSZyIZ'
        'QAFSYBIILgACABZXwLAsAVNnDhlAAVNnBHD/TnVwAU51cABOdUjn//5J+kvUSiwBVmci'
        'QiwBVkosAVRnGFDsAVBQ7QAZYZBCuQAAjJRhAAnAUOwBXBlsAVwBVUIsAVxKLAFdZhxw'
        'ABAsAWFnLEIsAWFKLAFQZyJTAGEAK4RgAAJOYQASgEosAXpnAAJCQiwBemEARohgAAJw'
        'ECwBgmcIQiwBgmEAPSJKLAGAZxZCLAGASiwBcmYMRiwBf0IsAVFQ7AFVSiwBgWcQQiwB'
        'gQwsAAIBcmYEYQA3eEosAX1nDEIsAX1GLAF8UOwBVT85AN/wHDP8QAAA3/CafAAwLABc'
        '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'
        'AQEOAAQAAAQAAAAEAAAEBAgCBAgQCAQCAAAfAB8AAAgEAgECBAgOEQECBAAEDhEXFRcQ'
        'Dw4RER8REREeEREeEREeDxAQEBAQDx4RERERER4fEBAeEBAfHxAQHhAQEA8QEBcREQ4R'
        'EREfERERDgQEBAQEDgEBAQEREQ4REhQYFBIREBAQEBAQHxEbFRURERERGRUTERERDhER'
        'ERERDh4RER4QEBAOERERFRINHhERHhQSEQ8QEA4BAR4fBAQEBAQEERERERERDhERERER'
        'CgQREREVFRsREREKBAoRERERCgQEBAQfAQIECBAfDggICAgIDhAICAQCAgEOAgICAgIO'
        'BAoRAAAAAAAAAAAAAB8IBAAAAAAAAAAOAQ8RDxAQHhERER4AAA4QEBAOAQEPERERDwAA'
        'DhEfEA8GCAgeCAgIAA8REQ8BDhAQHhEREREEAAwEBAQOAgAGAgISDBAQEhQYFBIMBAQE'
        'BAQOAAAaFRUVEQAAHhEREREAAA4REREOAB4RER4QEAAPEREPAQEAABYYEBAQAAAPEA4B'
        'HggIHggICAYAABEREREPAAAREREKBAAAEREVFQoAABEKBAoRABEREQ8BDgAAHwIECB8D'
        'BAQIBAQDBAQEBAQEBBgEBAIEBBgAAAkWAAAARfoABrAATnVgAABaYAAAVmAAAFhgAACY'
        'YAAASmAAARhgAABCYAAAPmAAADpgAAFuYAAAMmAAAC5gAAAqYAAAJmAAACJgAAAeYAAA'
        'GmAAABZgAAASYAAADmAAAApgAAAGYAABdHAAcv9OdUjnP/4mSWEAAiZ6ACIIJDwAAAPt'
        'Tq7/4igAZyQiBCQLJjwAAEIATq7/1ioAagJ6AE6u/3wuACIETq7/3GAAAU5gAAFESOc/'
        '/iwAJEgmSWEAAd5haGYqTq7/fLC8AAAAzWZKQfoWkiIITq7/iCIAZzxOrv+mYUZmCE6u'
        '/3wuAGAiIgQkCyYGTq7/0CoATq7/fC4AIgROrv/cuoZnFiIKTq7/uGEAAQB6AGAAAOJ6'
        'AGAAANZhAADwegFgAADMIgokPAAAA+5Orv/iKABOdUjnP/4sACZJegBhAAFWIgh0/k6u'
        '/6woAGdKYQABOCIETq7/mkqAZzYgQkqoAARvLmEAASIiBE6u/5RKgGcgIEJKqAAEaupQ'
        'iCJIShlm/JPIvIllCpyJFthm/FKFYNIiBE6u/6ZgVEjnP/56AGEAAPQiCHT+Tq7/rCgA'
        'ZyJhAADWIgROrv+aSoBnDiBCev9KqAAEagQqKAB8IgROrv+mYBpI5z/+YQAAvCIITq7/'
        'uCoATq7/fC4AYSBgBk6u/3wuAHIASoVmAiIHLwFhAADAIh8gBUzff/xOdUjn+PJB+hVM'
        'Igh0/k6u/6woAGdiLHgABJPJTq7+2iZAR+sAXEP66/bT/AABbwQkSXAQQppRyP/8RekA'
        'FCNKAAojSwAOJIklSwAEJXwAAAAbAAggBOWIIEAgaAAMTq7+kiBLTq7+gCBLTq7+jCxv'
        'ACQiBE6u/6ZM308fTnVB+uue0fwAAW4AJAhOdUjn//xOuQAAAMRM1z//Sfo5siBtAPIp'
        'UAFMILz/////LG0AjkzfP/9OdUjn//xJ+jmSIG0A8iCsAUxOuQAAAABM3z//TfkA3/AA'
        'TnUZQAFeYQAyLEIsAWBCLAFiQiwBY1DsAV9hAO00SOdzAEptAGBnCE65AAAV9mDyTN8A'
        'zkH5AAAASkPsAKZF+gL2cAQy0DCaWIhRyP/4TnVI54DAQfkAAABKQ+wApnAEMJlYiFHI'
        '//pCLAFdUOwBXGEA7N5M3wMBTnVg1Ejn//BhREpAawxhAAC6SiwBXWcwYO5hAOzqagxw'
        'RWEAAKZKLAFdZxxhAOzCahYMLAADAV1nDgwsAAUBXWcGcERhAACETN8P/051Lwhw/z85'
        'AN/wHDP8QAAA3/CacgASLAFjsiwBYmcUQewBinAAEDAQAFIBwjwADxlBAWMAV4AAAlfA'
        'ADPfAN/wmiBfTnWwPABgZzCwPABhZypKAGsmSOdAgEHsAYpyABIsAWIRgBAAUgHCPAAP'
        'siwBY2cEGUEBYkzfAQJOdRIsAV2yPAADZwAYcrI8AARnABqIsjwAAWcIsjwABWcKTnVh'
        'HGcA/xJOdbA8AEVnAP7eYQxm6mEA/tZQ7AF6TnWwPABEZwSwPABDTnVyASlIABgZQQFd'
        'YAABPEjn//BwAmEA/l5B+gG9cgVh4kzfD/9OdUSAU4CwvAAAAAplAnAA0EBB+gF6MDAA'
        'AEHwAABOdUjnwIAgbQDGVYhyAzA8Bt9CmFHI//xB6AWAUcn/8EzfAQNOdUjn//A+AnAA'
        'EBhnGLA8AApmBlJBNAdg7rR8AChk6GEKUkJg4kzfD/9OdUjn/uBhAPfmJEgibQDGVYnC'
        '/AFg08FUQtLCfAAgSiZJegcQGHQADQNnAhQADQRnBEYAhAAWgkfrACxRzf/mQ+khAFJG'
        'vHwABGXSTN8Hf051SOewAHAgdgB0J2GkUcr//EzfAA1OdUjn+MByAHgCYeBB+gDCSiwB'
        'XmcQQfoAvQwsAAEBXmcEQfoAt3QBdgFhAP9GQfkAAKMYQ+wBmnAfEthRyP/8QhFB7AGa'
        'dAdhAP8oTN8DH051SOf4wCBsABhD+gJ6DCwABAFdZgRD+gJ/DCwABQFdZgRD+gKeYRpM'
        '3wMfTnVI5/jAQfoAn0P6An5hBkzfAx9OdWEA/rphAP9qcgd0AnYBeABhAP7OchN0AHYE'
        'IElgAP7CARIP/wNrD/8PxACAAJsApgDFAN4A+AEVATYBeAHKU0FWRQBUSVRMRQBMRUFW'
        'RQBUaGlzIGxldmVsIGhhcyB1bnNhdmVkIGNoYW5nZXMuCkxlYXZpbmcgdGhlIGVkaXRv'
        'ciBkaXNjYXJkcyB0aGVtLgBXb3JraW5nIHdpdGggdGhlIGRpc2suLi4AVGhlIG9wZXJh'
        'dGlvbiB3YXMgcmVmdXNlZC4AQ2FuY2VsbGVkLgBUaGVyZSBpcyBubyBkaXNrIGluIHRo'
        'ZSBkcml2ZS4AVGhlIGRpc2sgY2Fubm90IGJlIHJlYWQuAFRoaXMgaXMgbm90IGEgbGV2'
        'ZWwgZGlzay4AVGhlIGRpc2sgaXMgd3JpdGUtcHJvdGVjdGVkLgBUaGUgZGlzayBoYXMg'
        'Y2hhbmdlZC4gVHJ5IGFnYWluLgBXcml0aW5nIGZhaWxlZC4gVGhpcyBsZXZlbCBhbmQg'
        'dGhlCm9uZSBuZXh0IHRvIGl0IG1heSBiZSBkYW1hZ2VkLgBUaGUgaW5kZXggb2YgdGhl'
        'IGxldmVsIGRpc2sgaXMKZGFtYWdlZC4gUmVwYWlyIGl0IHdpdGggc2F2ZWRpc2sucHkK'
        'cmVidWlsZC1pbmRleC4AU2F2ZWQsIGJ1dCB0aGUgaW5kZXggd2FzIG5vdAp1cGRhdGVk'
        'LiBSZXBhaXIgaXQgd2l0aCBzYXZlZGlzay5weQpyZWJ1aWxkLWluZGV4LgBSZXR1cm46'
        'IGNvbnRpbnVlAFJldHVybjogY29udGludWUgICBFc2M6IGNhbmNlbABFc2M6IGNhbmNl'
        'bABSZXR1cm46IGxlYXZlIHdpdGhvdXQgc2F2aW5nICAgRXNjOiBiYWNrAABhAOWGTrkA'
        'AAAASfkAAHkITvkAAANOMDwCgDI8ANBOuQAAYAIvDEn6M5BKLAFlKF9mBk75AAAnrkH5'
        'AAAAAEP5AAIq2jA8AgByezQ8AIB2RXgEegBOuQAAYDpI5wMwQfkAADFUQ/oAvkX6AVQq'
        'PAAAQQB+DXwKEBkSGkYBJkgWgNfFFoDXxRaB18UWgFKIUc7/5kHoAEVRz//cTN8MwE51'
        'LwxJ+jMUSiwBZWYYDG0AAwB+Zh5Q7AFlKF9hAP9aTvkAADGOQiwBZShfcABO+QAAMXoo'
        'XzAtAH5SQE75AAAxei8MSfoy1EosAWUoX2YAAWpKLQAcZwZO+QAAMCZO+QAAMCoMQAC8'
        'bhYvDEn6MqxKLAFlKF9mAAUOTvkAACrOTvkAAC/6AAAAAAAAAAAAAAAD+HBwf4f/A+Bw'
        'cAf8cHD/x/8P+HjwDxxwceGAcB48ffAeAHBx4ABwHBx3cBwAcHD+AHAcHHJwHABwcH+A'
        'cBwccHAcAHBwB8BwHBxwcBwAcHABwHAcHHBwHgBwcAHAcBwccHAPHHjww8BwHjxwcAf8'
        'P+H/gHAP+HBwA/gfwP8AcAPgcHAAAAAAAAAAAAAAAAf8+Pj/z/+H8Pj4DAaIiYBoAJwc'
        'jYgYAoiLACgAsAaHCDDiiIoeb4+hwoIIIb6Iih/AiCNiiIgjAIiLAcCIIiKNiCIAiImA'
        'YIgiIo+IIgCIiPggiCIiiIgjAIiIDiCIIiKIiCG+jYnmIIgjYoiIMOKHCzwgiCHCiIgY'
        'AsAaAGCIMAaIiAwGYDMAwIgcHIiIB/w/4f+A+Afw+PhYj0n6MVxCLAFuYQAA0kn6MVBN'
        '+QDf8ABCLAFtQmwAbEIsAWJCLAFjUOwBZlDsAWhB+hDCYQAHmGEAB2BhAATqTrkAABXe'
        'YQD4ZkpAawywPABFZ1BhAAUkYARhAAW+SkBrQmfcsHwAA2cqSiwBbWYAA+Y8ALx8AAJm'
        'BkosAW5mwGEAC+xKgGZ8vHwAAmcAAJ5gAADYSiwBbWamSiwBbmagYAAVVGFSYXRCLAFr'
        'QiwBbzt8AAMAfjtsAHQAKBtsAYkAG0osAWxnCkIsAWxOuQAAJ1JJ+QAAeQhO+QAAA6hC'
        'bABoQmwAahltABIBaTltACgAdBltABsBiUH5AABm4E75AAAWXkf6D8phAAbOYQDkKlDs'
        'AWpCbABsYAD/JkIsAWZCLAFoG2wBaQASTnVhAAPsQfpDJtBAMDAAAEH64fTR/AABoQDQ'
        'wEP6eXpwahLYV8j//EIRYQADxDlAAHJQ7AFvUOwBVmEAA7RgCEIsAW9hAAOqUOwBa1Ds'
        'AWxhACGaQiwBckJsAHo5fAAPAHxCLAF3QiwBcEIsAXthACsoUkA5QABwU0BqAnAASMCA'
        '/AARSEA7QAAoQm0AfmEA/z5hAP9eQi0AEEotABxnBk65AAAwwkn5AAB5CE65AAAh9k65'
        'AAAXkk75AAADvi8MSfovdEosAWtnIkjngMBB+nCmQ/kAAJs4MDwB/yLYUcj//Dt8//8A'
        'UkzfAwEoX0H5AACbODAoABpO+QAAIl5OuQAAJp4vDEn6Ly5KLAFrZwAAlkjn8MBD+QAA'
        'atZB+gFsMCwAcGYGQfoBbmA4sHwAZGUEQfoBXRLYZvxTicC8AAD//065AAAUzHQD4ZhK'
        'QmcKsDwAMGYEU0Jg8BLA4ZhRyv/6YAYS2Gb8U4mz/AAAat5kBhL8ACBg8kP5AABrXkH6'
        'ARpwBxLYUcj//EP5AABq4XAfDBkAOmYGE3wAO///Ucj/8kzfAw8oX075AABcQEItABMv'
        'DEn6LoBKLAFrKF9mCjAtAChO+QAABZhOuQAABupOuQAAMo5B+QAAZl5OuQAAFl5OuQAA'
        'FUphAP3kLwxJ+i5GSiwBbyhfZwD86k65AAAh9k75AAADvmEA/cQvDEn6LiZKLAFvZhBK'
        'LAFrKF9mAPzETvkAAAbiKF9OuQAAIfZO+QAAA74vDEn6LfxKLAF7ZxZCLAF7QiwBbyhf'
        'Qi0AHWEA/XxgAPyOKF9CLQAdQ/kAAGvJTvkAAAVELwhB+i3ISigBbyBfZgZOuQAAFUpB'
        '+QAAZuBO+QAAMLxMZXZlbCAATHZsIABOZXcAQ3VzdG9tICBYj0n6LZBN+QDf8ABCLAFu'
        'YQD9AFDsAW1CLAFiQiwBY0IsAWpQ7AFmQiwBaEH6QF5D+kLWRfpEEnAAdgBH+gDkdAUH'
        'AmcoMMMS/AABdB8U/AAgUcr/+kXq/+AUG2cEFMJg+FJARfpD4jQA60rUwlJDtnwAA2XK'
        'OUAAbGEABAxhAANOYQDg6GAA++xB+m5IIkgwPAH/QplRyP/8Q/oAVnAvENlRyP/8Qfpu'
        'LDAsAGpD+j/c0EAwMQAAMUAAGkPoASBF6AdgIvz/////s8pl9kPoB+BF+gBZcB8S2lHI'
        '//w5fP//AHJQ7AFvUOwBVnD/YAD8tgAyABQACgAFAAoACgAKAAoACgAKAAoACgAAAAAA'
        'AAAAAKAAGAABAA8B4AB4AAAAD0JyaWNrAFNub3cATmV3IGxldmVsICAgICAgICAgICAg'
        'ICAgICAgICAgICAAMCwAaMD8AArQbABqTnVB+gvKYQACoGEABIpKgGY6QfoL9UosAW5n'
        'BEH6C8ZKbABsZyZhzLBsAGxlFjAsAGxTQEjAgPwACjlAAGhIQDlAAGphAALoYADfyGEA'
        'AlpgAN/AYSqwPAASZxywPABGZxphAPPgV8DAfAABSmwAbGYCcABKQE51cAJg8HADYOw/'
        'AGEEMB9OdUpsAGxnHLA8AExnGLA8AE1nMrA8AE9nAAEYsDwATmcAASROdTAsAGpnBlNA'
        'YAABLkpsAGhn7Dl8AAkAalNsAGhgAAJkMCwAalJAYQAAsLBBZQABCjAsAGhSQGEAALxm'
        'wkJsAGo5QABoYAACPGEA30pqBHD/TnVhbjQAsGwAbmceOUAAbkpsAGxnFFVAaxBhbLBB'
        'ZAqwbABqZwRhAADAYQDfAmo+SmwAbGYMSiwBamcyYQD+yGAsMAJVQGsOYT6wQWQIOUAA'
        'anABTnW0fAABZhIwOQAAd2SwfACgZQRhZmACYU5wAE51MDkAAHdmUUBrCOhIsHwADWUC'
        'cP9OdS8AMCwAaMD8AAoyLABskkCyfAAKYwJyCiAfTnUvAMD8AAqwbABsZQRwAWACcABM'
        '3wABTnVKbABoZwxTbABoQmwAamAAAWZOdTAsAGhSQGHMZgw5QABoQmwAamAAAU5OdTIs'
        'AGpUQXQEYTQ5QABqMgBUQXQDYChI5//wO3wAUABkO3wA0ABmK3wAAAAAANZOuQAAGMpQ'
        '7QASTN8P/051SOfgwEHsALDSQTGCEADiSUH5AABn2utK0MJD+QAAAnrC/ABE0sFwDzKY'
        'WIlRyP/6TN8DB051SOdggEHsALByADQYYbxSQbJ8AA1l9EzfAQZOdUjn//BB7ACwTrkA'
        'ABZeTN8P/051LwhB7ACwMPwAATD8AAZwCTD8AARRyP/6MLwABSBfTnUvC5fLYQQmX051'
        'SOf/8CRIQfoH4kosAW5nBEH6B+lhOHIEEvwAAhLBEBpnCrA8AApnDBLAYPIgC2cKJEuX'
        'y0IZUkFg3kIZQfoH2WEmYRZhAP9gTN8P/051YQD++GGCQ/pnpmAOErwA/0H6Z5xO+QAA'
        'EnYQGLA8AP9nChLAEtgS2Gb8YO5OdUjn//BKLAFtZgRhAAFiQfoHXkosAW5nBEH6B2VK'
        'LAFtZwRB+gffYaoS/AALEvwAAUH6CAgS2Gb8U4kwLABoUkBhAADmQfoH/BLYZvxTiTAs'
        'AGzQfAAJSMCA/AAKYQAAyhL8ACAS/AA+QhlhAP3qNiwAaMb8AAp4AlNBEvwAAhLEYVhK'
        'LAFtZgJhVGFeQhlSQ1JEUcn/5kH6ByRKLAFuZwRB+gc/SiwBbWcEQfoHamEA/zxhAP8q'
        'MiwAalRBQewAsNJBMbwAAxAAYQD+YGEA/XI5QABuTN8P/051OgNOdTAFUkBhYhL8ACBO'
        'dUjnwIBB+j2QDDAAAVAAZh5B+j7EMAXrSNDAch8QGLA8ADpmAnA7EsBRyf/yYApB+gct'
        'Ethm/FOJTN8BA051SOfwAMC8AAD//065AAAUzDIA4EkSwRLATN8AD051SOfwAMC8AAD/'
        '/065AAAUzOGYcgLhmBLAUcn/+kzfAA9OdUIsAWpgfkjn//BhAPziNiwAaMb8AApTQWsi'
        'Qfo6gDAD0EA6MAAAPANB+jzuSjBgAGYEYQAB8FJDUcn/4EzfD/9OdUjnwOBF+jzQ1MYU'
        'vAACYQACtkqAZiZKLAFuZwZhAASOZhpB6AfgQ/o97jAG60jSwHIfEthRyf/8FLwAAUzf'
        'BwNOdUjnf3BCbABsYQDqvGYAAJIgPAAAXf9B+gIOQ/rY1NP8AAGhAC4JQild/06qABQg'
        'R3QAJgBgSiJIShlm/CIJkoiyvAAAAAZlNrK8AAAAbGIuECn/++GIECn//OGIECn//eGI'
        'ECn//oC8ACAgILC8Lmx2bGYKYQAM0mYEYQAAoCBJU4NqsjlCAGxH+jwKYAJCG1HK//xK'
        'LAFuZwJhEHAAYAZB+gZNcP9M3w7+TnVI5//wdgC2bABsZAo8A2EAAORSQ2DwQfo5VEP6'
        'O8xF+j0IdgB4ALZsAGxkOgwxAAEwAGYuMAPQQDIE0kExsAAAEAATvAABQAAwA+tIMgTr'
        'SXQfFbIAABAAUkBSQVHK//RSRFJDYMA5RABsTN8P/051SOfQYEX6OPZ2ALZCZBIwA9BA'
        'IkfS8gAAYTplBFJDYOq2fAE+ZCi0fAE+ZAJSQjAD0EAyAlNB0kGyQGMKNbIQ/hAAVUFg'
        '8iIIkoc1gQAATN8GC051SOfAwBAYEhlhFMFBYRDBQbABZgRKAGbsTN8DA051sDwAYWUK'
        'sDwAemIEkDwAIE51SOf/8EH6OHLWQzAwMABB+tdA0fwAAaEA0MBhSmEA6QhmNEH6ZihO'
        'qgAksLwAAAgAZiRB+mYYQ/rXGNP8AAFYAC4JTqoACLC8AAAIAGYIIEdhAP3MYApB+jqc'
        'EbwAAmAATN8P/051LwhD+mXiQfoAGBLYZvwTfAAv//8gXxLYZvxB+mXKTnVMZXZlbHMA'
        'AEjnf3BhAPimNgA8A2EA/2RB+taw0fwAAVgAQ/o6SgwxAAFgAGYkYS5KgGYeSiwBbmcG'
        'YQACCGYSQ/pl+DA8Af8i2FHI//xwAGAGQfoD8XD/TN8O/k51SOd/8CRIDFIAY2IAAdIy'
        'KgACZwAByrJ8AKBiAAHCsmoABGUAAbowKgAGZwABsrB8AAliAAGqQeoACHQHDFgAY2IA'
        'AZxRyv/2MCoAGLB8BQBiAAGMwHwAA2YAAYR2ADYqABq2fAACYgABdnAFBwBnAAFuOCoA'
        'HEpEYgABZEpqAB5mAAFcQfkAAXp6xvwFkNHDR+gAcGEA3tA6AGEA3qg8AEHqACB0AH4A'
        'DGgAAQAEZgJSRzAQZ3TQfBAAsHwgAGQAAR4wKAAC0HwQALB8IABkAAEOMigABLpBYwAB'
        'BDAoAAbAfD//sHwAD2YAAPS0fAAQZDjC/AAiQ/MQEDAQawAA4ORI0FHQaQAEsHwBmGIA'
        'ANAwKAACawAAyORI0GkAAtBpAAawfAAsYgAAtlCIUkK0fAAgZQD/dL58AARiAACiQeoB'
        'IHQADJD/////Zxq0fAGPZAAAjDAoAALAfAA/sEZkfliIUkJg3kpEZwRKQmZwQ+oHYAyY'
        '/////2Zkscll9HQfMBgyGDYAhkFnJjYA7ks4AelcyHwAD9ZEtnwBl2JAwHwAf+BJwnwA'
        'D9BBsHwAKmIuUcr/zkHqB+B0H3IAEBiwPAAgZRqwPAB+YhSwPAAgVsOCA1HK/+hKAWcE'
        'cABgAnD/TN8P/k51SOd/8CRIQeoAIH4fDGgAAgAEZwpQiFHP//RgAACaOhBQRTwoAALc'
        'fAAgcAAwKgAawPwFkEf5AAF66tfAeABB6gAgfgAwEGdaMigABLJ8AAFmBgjEAABgSr58'
        'ABBkRML8ACJD8xAADGkAAQAYZjTkSNBpABAyKQAUNAVhQjYAMCgAAuRI0GkAEjIpABY0'
        'BmEu0EOwfAAgbgYIxAACYAQIxAABUIhSR758ACBlmLg8AAdmBHAAYAJw/0zfD/5OdeVI'
        '5UnSQFNBkEJuDJJCREFwAEpBbwIwAU51dP92AEqAZzJ4ABgYsrz/////Zw4qA5qBurwA'
        'AAAEZAJ4ALkCegfiimQGCoLtuIMgUc3/9FKDU4BgyiACRoBOdQ0AQ3VzdG9tIGxldmVs'
        'cwD/CABUd28tcGxheWVyIGN1c3RvbSBsZXZlbHMA/wUMUmlnaHQgbW91c2UgYnV0dG9u'
        'IHRvIGdvIGJhY2sA/wMMQ2xpY2sgcGxheXMsIEUgZWRpdHMsIERlbCBkZWxldGVzAP8F'
        'DENsaWNrIHBsYXlzLCByaWdodCBidXR0b24gYmFjawD/CwBOZXcgbGV2ZWwgc3R5bGUA'
        '/wIMQ2xpY2sgYSBzdHlsZSAgUmlnaHQgYnV0dG9uIGJhY2sA/zwgUGFnZSAAIG9mIAAo'
        'ZGFtYWdlZCBsZXZlbCkAVGhpcyBsZXZlbCBjYW5ub3QgYmUgcmVhZCBvciBwbGF5ZWQu'
        'AENsaWNrIHRvIGxvb2sgZm9yIHRoZSBsZXZlbHMgYWdhaW4uAFJlYWRpbmcgdGhlIGxl'
        'dmVscy4uLgBUaGVyZSBhcmUgbm8gbGV2ZWxzIGZvciB0d28gcGxheWVycy4AVGhlcmUg'
        'YXJlIG5vIC5sdmwgZmlsZXMgaW4gdGhlCmRpcmVjdG9yeSBMZXZlbHMuAEjn//BhAOaE'
        'QfppFkP6aTJwH3IAdABSQhYYEsO2PAAgZwIyAlHI//BCERlBAXFD+mkQQjEQABl8AAMB'
        'XWEAAIpM3w//TnWwPABFZwDmtkH6aPBhAOe2Z1pyABIsAXGwPABBZhBKQWdeU0FCMBAA'
        'GUEBcWBUsnwAIGRMsDwAQGJGQ/kAAHp4SiwBZGcGQ/kAAHr4EDEAALA8ACBlKrA8AH5i'
        'JBGAEABSAUIwEAAZQQFxYBZyABIsAXFTQWsKDBgAIGZkUcn/+E51SOf4gGEA54xhAOg8'
        'cgd0BHYBeABB+gJSYQDnnHIJeAJhAOgOQfpoUnAAECwBcRG8AF8AAHQEYQDnfkIwAABy'
        'E3QAdgR4AEH6AjZKLAFeZwRB+gJFYQDnYEzfAR9OdUosAV5mAAC8YQAA/EqAZwhB+gJX'
        'YAAAqGEA6EphAAEiSoBmckH6MYxD+mfQcB+zCFbI//xnDGEAAJphABA4QiwBhWEAEZBB'
        '+imKQ/pfzjA8Af8i2FHI//xB+megQ/kAAKMYcAci2FHI//xB+mDOQ/kAAJxYMDwBjyLY'
        'Ucj//AAsAAEBeGEA1XBCrAAQYQAZrkH6AcJgKEH6AhKwvP////VnHEH6AnWwvP////Rn'
        'EEH6AjOwvP////JnBGEA5lpgAOYwYQ5D+mc0YR5hABhMYADk4kjnwIAwfAfgcCByAGEA'
        'DepM3wEDTnVI58DAQfpnLHIfEBhmBFOIcCASwFHJ//RM3wMDTnVI52DgQfpfDkP6KMIw'
        'PAH/IthRyP/8Q/ootGEAGTpmEEP6MIphvEH6KKRhAPkMYAJw/0zfBwZOdU51SOd/8GEA'
        '4TpmNEpsAHJqBGE8ZixhMCA8AAAIAEP6KHROqgAMSoBnCEJsAHJwAGAQcPqyvAAAANZn'
        'BnDyYAJw/0zfD/5OdUH6ZrRgAPg0IDwAAF3/Qfr4SkP6zxDT/AABoQAmSUIpXf9OqgAU'
        'LAB6AUP6ZopB+gBOEthm/FOJIAVhAPVSEvwALhL8AGwS/AB2EvwAbEIRIEsoBmAOQ/pm'
        'XmEA90hnEkoYZvxThGruYZZOqgAkSoBnClJFunwD52OwcPVOdUxldmVsAFRpdGxlIGZv'
        'ciB0aGlzIGxldmVsOgBSZXR1cm46IHNhdmUgICBFc2M6IGJhY2sAUmV0dXJuOiBhY2Nl'
        'cHQgICBFc2M6IGJhY2sAVGhlIGxldmVsIHdhcyBzYXZlZC4AVGhlIGxldmVsIGNhbm5v'
        'dCBiZSBzYXZlZDogaXQgaXMKb3V0c2lkZSB0aGUgbGltaXRzIG9mIHRoZSBnYW1lLgBU'
        'aGVyZSBpcyBubyBmcmVlIG5hbWUgZnJvbQpMZXZlbDAwMS5sdmwgdG8gTGV2ZWw5OTku'
        'bHZsLgBUaGUgbGV2ZWwgY291bGQgbm90IGJlIHdyaXR0ZW4uClRoZSBkaXNrIG1heSBi'
        'ZSBmdWxsLgBUaGUgbGV2ZWwgZGlzayBob2xkcyBhbm90aGVyIGxldmVsCmluIHRoaXMg'
        'cGxhY2UuIEluc2VydCB0aGUgZGlzayB0aGUKbGV2ZWwgY2FtZSBmcm9tLgBhbkqAZgDr'
        'CGEAAIphAM80TrkAABXeYQDioEpAaw6wPABFZxxhAONOZyJg5GEAz0JrDgg5AAYAv+AB'
        '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'
        'IbAwADAEYPIhgQAAUqwAEFNsAFBM3wMdTnVKLAFQZ0RyAbA8ABRnQHICsDwAGGc4cgOw'
        'PAAZZzByAbA8ACFnLnICsDwANmcmsDwAJGcmsDwAFmcocv+wPABMZzByAbA8AE1nKHIA'
        'TnUZQQFzTnUZQQFhTnVQ7AF9cgFOdXIBSiwBZGcCcgIZQQGCTnXTLAF0cgFOdRAsAXNn'
        'MEIsAXOwLAFyZgJwABlAAXI5fP//AIBCLAF1SiwBdmcIQiwBdmEAAY5Q7AFVUOwBeE51'
        'QiwBdUosAXZnCEIsAXZhAAFyPzkA3/AcM/xAAADf8JpCbABcQiwAX0IsAXRCLAF5QiwB'
        'c0IsAWFCLAF9QiwBgEIsAYFCLAGCAFeAAAJXwAAz3wDf8JpOdQwsAAIBcmcA8N4MLAAD'
        'AXJmBGEEYDBOdUoFZygSLAF30gVqBtI8AA1g+LI8AA1lBpI8AA1g9BlBAXcALAABAXhQ'
        '7AFVTnVKAGcAAJBI5/DASIByABIsAXdB+gCCwvwABtDBcgASKAABSiwBZGcEwvwACsHB'
        'Q/pHtnIAEhDSwTQoAARmBDQ6R6jQUbBoAAJsBDAoAAKwQm8CMAJI58CAkchwGnIB0iwB'
        'd2EA9jJM3wEDMoBD+kd4MCkAArBpAARkBDNAAARhZAwsAAwBd2YIM+kAGAAAd2JM3wMP'
        'TnUAAQAAAGMCAQABAKAEAQAAAAAGAQABAAkIAQAAAGMKAQAAAGMMAQAAAGMOAQAAAGMQ'
        'AQAAAGMSAQAAAGMUAQAAAGMWAQAAAGMYEAAABQBhAPauSOf//kH6RvhD+QAAmzgwPABH'
        'IthRyP/8QfpOREP5AACimHAnIthRyP/8Hy0AGS8tANI/OQAAd2JJ+QAAeQhOuQAAI4Yz'
        '3wAAd2IrXwDSG18AGUK5AACMlE65AAAhAE65AAAgeEzff/9Q7AFVACwAAQF4TnVKLAFQ'
        'ZxRD+kaCYQAAwGYEQqwAEFDsAXBgBEIsAXBhAMOCUO0ACz18ABAAmj18gCAAmkItAA9O'
        'uQAAF15w/065AAClNEItAB07fP//AFJOuQAAIfZM33//TvkAAAO+YRhnBGAAzQphAMM6'
        'QiwBUFDsAXtO+QAAEipI5/zAQfpGDEqsABBnGkP6D7owPAH/IthRyP/8Q/oPrGEyZgpB'
        '+g+kYR6wrAAcTN8DP051SOf8gGEKKUAAHEzfAT9OdUH6RcwgPAAACABy/2AA4qJI54Dg'
        'RekHYEPpASCzymQoDJH/////ZwRYiWDwICwAEEH6BiBgAiLYU4BrBLPKZfazymQEcABg'
        'AnD/TN8HAU51RfoBbgwsAAMBcmYERfoB6GEAARRwABAsAXLQQEX6AUrU8gAAYQABABAs'
        'AXKwPAADZ3QwLABwcgJ0AGEAAMAwOQAAm1JSQHIDYQAAskH6RTByAHQoMCgAAmEAAKJU'
        'iFJBsnwAA2XuECwBcmcKVQBrHGEA8yhgeDAsACZyAXQUYXwwOQAAm1RyA2FyYGJB+kxQ'
        'ch9wAEqYZwJSQFHJ//hyAHQUYVhgSEH6/YZD+kTSdgAyA8J8AAM0A+RKxPwAFHAAEBAw'
        'MQAAYTRI52AA1HwAC2E+cCC2LAF3ZgJwPmEAw9JM3wAGXIhSQ7Z8AA1lwkX6AFZhMmEA'
        'wexgAMIISOdoENR8AAxhCmEAw0xM3wgWTnUvAUf5AAAAAML8AoDXwTgC50wiH051SOfo'
        'EHIAEhqyPAD/Zwx0ABQaYdZhAMMMYOpM3wgXTnUFMkVkaXRvciBWMi4zLjEgYnkgVGlt'
        'byBIZWltb25lbgD/AX0CHQJXAI0AAFggQ29vcmQAAQBZIENvb3JkAAIATGV2ZWwAAwBH'
        'cm91bmQAAChMZW1taW5ncwABKFRvIFNhdmUAAihNaW51dGVzAAQAUm9vbQAEFEU6VGVz'
        'dCBUOlN0ZWVsIE86T2JqZWN0cyBQOlBhcmFtcyBOOlRpdGxlIFM6U2F2ZSBVOlVuZG8A'
        '/wAAUmVsZWFzZQABAExlbW1pbmdzAAIAVG8gU2F2ZQADAE1pbnV0ZXMAABRDbGltYmVy'
        'cwABFEZsb2F0ZXJzAAIUQm9tYmVycwADFEJsb2NrZXJzAAAoQnVpbGRlcnMAAShCYXNo'
        'ZXJzAAIoTWluZXJzAAMoRGlnZ2VycwAAPFN0YXJ0IFgAATxTaGlmdDogU3RlcHMgeDEw'
        'AAI8VXAvRG93bjogRmllbGQAAzxMZWZ0L1JpZ2h0OiBWYWx1ZQAEAFJvb20ABBRFOlRl'
        'c3QgUDpUZXJyYWluIE46VGl0bGUgUzpTYXZlIFU6VW5kbwD/ABRQaWVjZQABFFBpZWNl'
        'IFR5cGVzAAIUQnJ1c2gAAxRTcGVjaWFsAAMoRmxpcAAAPExNQjogUGxhY2UAAjxMZWZ0'
        'L1JpZ2h0OiBQaWVjZQADPEY6IEZsaXAgIEI6IEJlaGluZAAFAEc6IFNuYXAA/wE8Uk1C'
        'OiBBZGQvRXJhc2UgICAgICAA/wE8Uk1COiBBZGQgIFNoaWZ0OiBEZWwA/wAUU3RlZWwg'
        'QXJlYXMAADxMTUIgRHJhZzogQWRkAAE8Uk1COiBSZW1vdmUAAzxUOiBUZXJyYWluAP8A'
        'FE9iamVjdAACFE9iamVjdCBTbG90AAMUT2JqZWN0cwADKERyYXcAADxMTUI6IFBsYWNl'
        'L01vdmUAATxSTUI6IERlbGV0ZQACPExlZnQvUmlnaHQ6IE9iamVjdAADPEY6IERyYXcg'
        'IE86IFRlcnJhaW4ABQBHOiBTbmFwAP8A'
    ),
    'holiday94 floppy relocations': (
        'AAAAAQAAAAgAAAnuAAAasgAAGrgAABrYAAAkAgAAO/YAAD0UAABCPgAAAAIAAACmAAAA'
        'VgAAAOYAAAEAAAABDgAAASgAAAEuAAAB4AAABFAAAARkAAAEkgAABJgAAAS4AAAExAAA'
        'BNwAAAT0AAAFCAAABQ4AAAUUAAAFHAAABSQAAAU0AAAFPgAABUgAAAVSAAAFXAAABdYA'
        'AAXeAAAF6AAABfAAAAX6AAAGBAAABgwAAAYWAAAGHgAABiQAAAYyAAAGpgAABq4AAAa0'
        'AAAJLgAACTQAAAk6AAAJQAAACUYAAAmIAAAJpAAACcQAAAnOAAAM1gAADmQAABR0AAAU'
        'qgAAFOIAABdsAAAafgAAGoQAABqKAAAamAAAGqwAABrOAAAbOAAAG0YAABtUAAAbcAAA'
        'G3YAABuSAAAbmAAAHRIAAB2eAAAdpAAAHaoAAB3KAAAd0AAAHpwAAB6iAAAeqAAAHq4A'
        'AB60AAAezgAAHuoAAB70AAAe+gAAHxIAAB8+AAAfZgAAH3QAAB+GAAAfpAAAH8AAAB/G'
        'AAAfzAAAH9IAAB/YAAAf3gAAH/gAAB/+AAAgHgAAICYAACAsAAAgWgAAIGAAACB0AAAg'
        'egAAIIAAACNQAAAjZgAAJAoAACQqAAAkdAAAJQwAACZYAAAmdgAAKhoAACuwAAAusgAA'
        'Lr4AAC+0AAAvxgAAMtgAADVuAAA3AAAANxoAADcmAAA4rAAAOPIAADlYAAA5pgAAObAA'
        'ADm8AAA5yAAAO2oAADzkAAA8+AAAPSoAAD0yAAA9OAAAPT4AAD1QAAA9XAAAPoAAAEEE'
        'AABBjAAAQdYAAEHcAABCpAAAQrgAAEQmAABEUAAARYgAAEXkAABIFgAASHwAAEiQAABI'
        'pgAASKwAAEiyAABIuAAASMwAAEjSAABJHgAASSYAAEk2AABJQAAASVoAAEoyAABKdAAA'
        'AAMAAAANAAACegAADE4AAAxmAAAMeAAADIIAAAyMAAAMlgAADKAAAAyqAAAU7gAAFQ4A'
        'ACQ0AABIxgAAAAUAAAAPAAAALAAAADwAAABCAAAASgAADFQAAAzCAAAM3AAADTAAAA1M'
        'AAANcAAADaAAAA3aAAAOAAAADhoAAEsG'
    ),
    'holiday94 whdload editor': (
        'SOf//kn6SwwgTDA8J3pCWFHI//xB+v/q0fwAALAAKUgACGEADmBB+g64Q/kAAA8AMDwA'
        'EzLYUcj//CA8AAAAADPAAAAPHkhAM8AAAA8aTN9//051TrkAACNqSOf//kn6SrJhAAwk'
        'QiwBUEIsAVRCLAFWQiwBUUIsAX9CLAGAQiwBgUIsAYJCLAGIQmwAXkJsAFxCLAFhQmwA'
        'JEKsABBCLAF1QiwBdkIsAYVhAD1gOXz//wB+OXz//wCAQiwBc0IsAXRCLAF5QmwApEos'
        'AW9nUkosAXBX7AFWQiwBcGEABG5B+g4mMDkAAJtSsHwAAmIy0DwAMRFAAAYibAAIcgBO'
        'uQAALfggbAAIIkggAU65AAA0mCBtAO5hAAfAOUAAJlbsAVRM33//TrkAACOGTvkAACLY'
        'G0AABkn6SdphAACoSiwBV2cOsDwARWYAAIxQ7AFYYCJKLAFdZgZKLAFmZwZhABGcYBBK'
        'LAFvZ2ywPABFZhBQ7AF5sDwARWZcEDwAxWBWSgBrUmEAQZZmTLA8ABJmCAosAAEAXGA+'
        'sDwATmYGUiwAXWAysDwAT2YGUywAXWAmsDwAI2YOSiwBUGcaCiwAAQBfYBKwPAA1ZgxK'
        'LAFQZwYKLAABAYAT/AAAAL/sAU75AAATvrA8AGBnGLA8AGFnErA8AOBnBrA8AOFmCkIs'
        'AWROdVDsAWROdQg5AAYAv+ABV+wBUgguAAIAFlfsAVNOdQg5AAYAv+ABV8CwLAFSZyIZ'
        'QAFSYBIILgACABZXwLAsAVNnDhlAAVNnBHD/TnVwAU51cABOdUjn//5J+ki2SiwBVmci'
        'QiwBVkosAVRnGFDsAVBQ7QAZYZBCuQAAjJRhAAnAUOwBXBlsAVwBVUIsAVxKLAFdZhxw'
        'ABAsAWFnLEIsAWFKLAFQZyJTAGEAKL5gAAJOYQAPukosAXpnAAJCQiwBemEAQ2pgAAJw'
        'ECwBgmcIQiwBgmEAOgRKLAGAZxZCLAGASiwBcmYMRiwBf0IsAVFQ7AFVSiwBgWcQQiwB'
        'gQwsAAIBcmYEYQA0WkosAX1nDEIsAX1GLAF8UOwBVT85AN/wHDP8QAAA3/CafAAwLABc'
        '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'
        'AQEOAAQAAAQAAAAEAAAEBAgCBAgQCAQCAAAfAB8AAAgEAgECBAgOEQECBAAEDhEXFRcQ'
        'Dw4RER8REREeEREeEREeDxAQEBAQDx4RERERER4fEBAeEBAfHxAQHhAQEA8QEBcREQ4R'
        'EREfERERDgQEBAQEDgEBAQEREQ4REhQYFBIREBAQEBAQHxEbFRURERERGRUTERERDhER'
        'ERERDh4RER4QEBAOERERFRINHhERHhQSEQ8QEA4BAR4fBAQEBAQEERERERERDhERERER'
        'CgQREREVFRsREREKBAoRERERCgQEBAQfAQIECBAfDggICAgIDhAICAQCAgEOAgICAgIO'
        'BAoRAAAAAAAAAAAAAB8IBAAAAAAAAAAOAQ8RDxAQHhERER4AAA4QEBAOAQEPERERDwAA'
        'DhEfEA8GCAgeCAgIAA8REQ8BDhAQHhEREREEAAwEBAQOAgAGAgISDBAQEhQYFBIMBAQE'
        'BAQOAAAaFRUVEQAAHhEREREAAA4REREOAB4RER4QEAAPEREPAQEAABYYEBAQAAAPEA4B'
        'HggIHggICAYAABEREREPAAAREREKBAAAEREVFQoAABEKBAoRABEREQ8BDgAAHwIECB8D'
        'BAQIBAQDBAQEBAQEBBgEBAIEBBgAAAkWAAAAR/ruKNf8AAIAAAyTV0hETGYIJGsABLAA'
        'TnVw/051GUABXmEAMdRCLAFgQiwBYkIsAWNQ7AFfYQDv+kjncwBKbQBgZwhOuQAAFfZg'
        '8kzfAM5B+QAAAEpD7ACmRfoC9nAEMtAwmliIUcj/+E51SOeAwEH5AAAASkPsAKZwBDCZ'
        'WIhRyP/6QiwBXVDsAVxhAO+kTN8DAU51YNRI5//wYURKQGsMYQAAukosAV1nMGDuYQDv'
        'sGoMcEVhAACmSiwBXWccYQDviGoWDCwAAwFdZw4MLAAFAV1nBnBEYQAAhEzfD/9OdS8I'
        'cP8/OQDf8Bwz/EAAAN/wmnIAEiwBY7IsAWJnFEHsAYpwABAwEABSAcI8AA8ZQQFjAFeA'
        'AAJXwAAz3wDf8JogX051sDwAYGcwsDwAYWcqSgBrJkjnQIBB7AGKcgASLAFiEYAQAFIB'
        'wjwAD7IsAWNnBBlBAWJM3wECTnUSLAFdsjwAA2cAGHKyPAAEZwAafLI8AAFnCLI8AAVn'
        'Ck51YRxnAP8STnWwPABFZwD+3mEMZuphAP7WUOwBek51sDwARGcEsDwAQ051cgEpSAAY'
        'GUEBXWAAATxI5//wcAJhAP5eQfoBvXIFYeJM3w//TnVEgFOAsLwAAAAKZQJwANBAQfoB'
        'ejAwAABB8AAATnVI58CAIG0AxlWIcgMwPAbfQphRyP/8QegFgFHJ//BM3wEDTnVI5//w'
        'PgJwABAYZxiwPAAKZgZSQTQHYO60fAAoZOhhClJCYOJM3w//TnVI5/7gYQD6rCRIIm0A'
        'xlWJwvwBYNPBVELSwnwAIEomSXoHEBh0AA0DZwIUAA0EZwRGAIQAFoJH6wAsUc3/5kPp'
        'IQBSRrx8AARl0kzfB39OdUjnsABwIHYAdCdhpFHK//xM3wANTnVI5/jAcgB4AmHgQfoA'
        'wkosAV5nEEH6AL0MLAABAV5nBEH6ALd0AXYBYQD/RkH5AACjGEPsAZpwHxLYUcj//EIR'
        'QewBmnQHYQD/KEzfAx9OdUjn+MAgbAAYQ/oCegwsAAQBXWYEQ/oCfwwsAAUBXWYEQ/oC'
        'nmEaTN8DH051SOf4wEH6AJ9D+gJ+YQZM3wMfTnVhAP66YQD/anIHdAJ2AXgAYQD+znIT'
        'dAB2BCBJYAD+wgESD/8Daw//D8QAgACbAKYAxQDeAPgBFQE2AXgBylNBVkUAVElUTEUA'
        'TEVBVkUAVGhpcyBsZXZlbCBoYXMgdW5zYXZlZCBjaGFuZ2VzLgpMZWF2aW5nIHRoZSBl'
        'ZGl0b3IgZGlzY2FyZHMgdGhlbS4AV29ya2luZyB3aXRoIHRoZSBkaXNrLi4uAFRoZSBv'
        'cGVyYXRpb24gd2FzIHJlZnVzZWQuAENhbmNlbGxlZC4AVGhlcmUgaXMgbm8gZGlzayBp'
        'biB0aGUgZHJpdmUuAFRoZSBkaXNrIGNhbm5vdCBiZSByZWFkLgBUaGlzIGlzIG5vdCBh'
        'IGxldmVsIGRpc2suAFRoZSBkaXNrIGlzIHdyaXRlLXByb3RlY3RlZC4AVGhlIGRpc2sg'
        'aGFzIGNoYW5nZWQuIFRyeSBhZ2Fpbi4AV3JpdGluZyBmYWlsZWQuIFRoaXMgbGV2ZWwg'
        'YW5kIHRoZQpvbmUgbmV4dCB0byBpdCBtYXkgYmUgZGFtYWdlZC4AVGhlIGluZGV4IG9m'
        'IHRoZSBsZXZlbCBkaXNrIGlzCmRhbWFnZWQuIFJlcGFpciBpdCB3aXRoIHNhdmVkaXNr'
        'LnB5CnJlYnVpbGQtaW5kZXguAFNhdmVkLCBidXQgdGhlIGluZGV4IHdhcyBub3QKdXBk'
        'YXRlZC4gUmVwYWlyIGl0IHdpdGggc2F2ZWRpc2sucHkKcmVidWlsZC1pbmRleC4AUmV0'
        'dXJuOiBjb250aW51ZQBSZXR1cm46IGNvbnRpbnVlICAgRXNjOiBjYW5jZWwARXNjOiBj'
        'YW5jZWwAUmV0dXJuOiBsZWF2ZSB3aXRob3V0IHNhdmluZyAgIEVzYzogYmFjawAAYQDo'
        'TE65AAAAAEn5AAB5CE75AAADTjA8AoAyPADQTrkAAGACLwxJ+jM4SiwBZShfZgZO+QAA'
        'J65B+QAAAABD+QACKtowPAIAcns0PACAdkV4BHoATrkAAGA6SOcDMEH5AAAxVEP6AL5F'
        '+gFUKjwAAEEAfg18ChAZEhpGASZIFoDXxRaA18UWgdfFFoBSiFHO/+ZB6ABFUc//3Ezf'
        'DMBOdS8MSfoyvEosAWVmGAxtAAMAfmYeUOwBZShfYQD/Wk75AAAxjkIsAWUoX3AATvkA'
        'ADF6KF8wLQB+UkBO+QAAMXovDEn6MnxKLAFlKF9mAAFqSi0AHGcGTvkAADAmTvkAADAq'
        'DEAAvG4WLwxJ+jJUSiwBZShfZgAFDk75AAAqzk75AAAv+gAAAAAAAAAAAAAAA/hwcH+H'
        '/wPgcHAH/HBw/8f/D/h48A8ccHHhgHAePH3wHgBwceAAcBwcd3AcAHBw/gBwHBxycBwA'
        'cHB/gHAcHHBwHABwcAfAcBwccHAcAHBwAcBwHBxwcB4AcHABwHAcHHBwDxx48MPAcB48'
        'cHAH/D/h/4BwD/hwcAP4H8D/AHAD4HBwAAAAAAAAAAAAAAAH/Pj4/8//h/D4+AwGiImA'
        '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'
        'TnXlSOVJ0kBTQZBCbgySQkRBcABKQW8CMAFOdXT/dgBKgGcyeAAYGLK8/////2cOKgOa'
        'gbq8AAAABGQCeAC5AnoH4opkBgqC7biDIFHN//RSg1OAYMogAkaATnUNAEN1c3RvbSBs'
        'ZXZlbHMA/wgAVHdvLXBsYXllciBjdXN0b20gbGV2ZWxzAP8FDFJpZ2h0IG1vdXNlIGJ1'
        'dHRvbiB0byBnbyBiYWNrAP8DDENsaWNrIHBsYXlzLCBFIGVkaXRzLCBEZWwgZGVsZXRl'
        'cwD/BQxDbGljayBwbGF5cywgcmlnaHQgYnV0dG9uIGJhY2sA/wsATmV3IGxldmVsIHN0'
        'eWxlAP8CDENsaWNrIGEgc3R5bGUgIFJpZ2h0IGJ1dHRvbiBiYWNrAP88IFBhZ2UgACBv'
        'ZiAAKGRhbWFnZWQgbGV2ZWwpAFRoaXMgbGV2ZWwgY2Fubm90IGJlIHJlYWQgb3IgcGxh'
        'eWVkLgBDbGljayB0byBsb29rIGZvciB0aGUgbGV2ZWxzIGFnYWluLgBSZWFkaW5nIHRo'
        'ZSBsZXZlbHMuLi4AVGhlcmUgYXJlIG5vIGxldmVscyBmb3IgdHdvIHBsYXllcnMuAFRo'
        'ZXJlIGFyZSBubyAubHZsIGZpbGVzIGluIHRoZQpkaXJlY3RvcnkgTGV2ZWxzLgBI5//w'
        'YQDmhEH6aL5D+mjacB9yAHQAUkIWGBLDtjwAIGcCMgJRyP/wQhEZQQFxQ/pouEIxEAAZ'
        'fAADAV1hAACKTN8P/051sDwARWcA5rZB+miYYQDntmdacgASLAFxsDwAQWYQSkFnXlNB'
        'QjAQABlBAXFgVLJ8ACBkTLA8AEBiRkP5AAB6eEosAWRnBkP5AAB6+BAxAACwPAAgZSqw'
        'PAB+YiQRgBAAUgFCMBAAGUEBcWAWcgASLAFxU0FrCgwYACBmZFHJ//hOdUjn+IBhAOeM'
        'YQDoPHIHdAR2AXgAQfoCNGEA55xyCXgCYQDoDkH6Z/pwABAsAXERvABfAAB0BGEA535C'
        'MAAAchN0AHYEeABB+gIYSiwBXmcEQfoCJ2EA52BM3wEfTnVKLAFeZgAAsGEAAPBKgGcI'
        'QfoCOWAAAJxhAOhKYQABFkqAZnJB+jE0Q/pneHAfswhWyP/8ZwxhAACOYQAP4EIsAYVh'
        'ABE4QfopMkP6X3YwPAH/IthRyP/8QfpnSEP5AACjGHAHIthRyP/8QfpgdkP5AACcWDA8'
        'AY8i2FHI//wALAABAXhhANg2QqwAEGEAGVZB+gGkYBxB+gH0sLz////1ZxBB+gIhsLz/'
        '///0ZwRhAOZmYADmPGEOQ/pm6GEeYQAYAGAA5O5I58CAMHwH4HAgcgBhAA2eTN8BA051'
        'SOfAwEH6ZuByHxAYZgRTiHAgEsBRyf/0TN8DA051SOdg4EH6XsJD+ih2MDwB/yLYUcj/'
        '/EP6KGhhABjuZhBD+jA+YbxB+ihYYQD5GGACcP9M3wcGTnVOdUjnf/BhAOQMZiJKbABy'
        'agRhKmYaYR4gPAAACABD+igoTqoADEJsAHJwAGACcP9M3w/+TnVB+mZ6YAD4UiA8AABd'
        '/0H6+GhD+tH00/wAAaEAJklCKV3/TqoAFCwAegFD+mZQQfoAThLYZvxTiSAFYQD1cBL8'
        'AC4S/ABsEvwAdhL8AGxCESBLKAZgDkP6ZiRhAPdmZxJKGGb8U4Rq7mGWTqoAJEqAZwpS'
        'Rbp8A+djsHD1TnVMZXZlbABUaXRsZSBmb3IgdGhpcyBsZXZlbDoAUmV0dXJuOiBzYXZl'
        'ICAgRXNjOiBiYWNrAFJldHVybjogYWNjZXB0ICAgRXNjOiBiYWNrAFRoZSBsZXZlbCB3'
        'YXMgc2F2ZWQuAFRoZSBsZXZlbCBjYW5ub3QgYmUgc2F2ZWQ6IGl0IGlzCm91dHNpZGUg'
        'dGhlIGxpbWl0cyBvZiB0aGUgZ2FtZS4AVGhlcmUgaXMgbm8gZnJlZSBuYW1lIGZyb20K'
        'TGV2ZWwwMDEubHZsIHRvIExldmVsOTk5Lmx2bC4AVGhlIGxldmVsIGRpc2sgaG9sZHMg'
        'YW5vdGhlciBsZXZlbAppbiB0aGlzIHBsYWNlLiBJbnNlcnQgdGhlIGRpc2sgdGhlCmxl'
        'dmVsIGNhbWUgZnJvbS4AYW5KgGYA61xhAACKYQDSTk65AAAV3mEA4vRKQGsOsDwARWcc'
        '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'
        '5UgmLAAQ5UtB+gncWUO2QG0IIbAwADAEYPIhgQAAUqwAEFNsAFBM3wMdTnVKLAFQZ0Ry'
        'AbA8ABRnQHICsDwAGGc4cgOwPAAZZzByAbA8ACFnLnICsDwANmcmsDwAJGcmsDwAFmco'
        'cv+wPABMZzByAbA8AE1nKHIATnUZQQFzTnUZQQFhTnVQ7AF9cgFOdXIBSiwBZGcCcgIZ'
        'QQGCTnXTLAF0cgFOdRAsAXNnMEIsAXOwLAFyZgJwABlAAXI5fP//AIBCLAF1SiwBdmcI'
        'QiwBdmEAAY5Q7AFVUOwBeE51QiwBdUosAXZnCEIsAXZhAAFyPzkA3/AcM/xAAADf8JpC'
        'bABcQiwAX0IsAXRCLAF5QiwBc0IsAWFCLAF9QiwBgEIsAYFCLAGCAFeAAAJXwAAz3wDf'
        '8JpOdQwsAAIBcmcA8N4MLAADAXJmBGEEYDBOdUoFZygSLAF30gVqBtI8AA1g+LI8AA1l'
        'BpI8AA1g9BlBAXcALAABAXhQ7AFVTnVKAGcAAJBI5/DASIByABIsAXdB+gCCwvwABtDB'
        'cgASKAABSiwBZGcEwvwACsHBQ/pHtnIAEhDSwTQoAARmBDQ6R6jQUbBoAAJsBDAoAAKw'
        'Qm8CMAJI58CAkchwGnIB0iwBd2EA9jJM3wEDMoBD+kd4MCkAArBpAARkBDNAAARhZAws'
        'AAwBd2YIM+kAGAAAd2JM3wMPTnUAAQAAAGMCAQABAKAEAQAAAAAGAQABAAkIAQAAAGMK'
        'AQAAAGMMAQAAAGMOAQAAAGMQAQAAAGMSAQAAAGMUAQAAAGMWAQAAAGMYEAAABQBhAPau'
        'SOf//kH6RvhD+QAAmzgwPABHIthRyP/8QfpOREP5AACimHAnIthRyP/8Hy0AGS8tANI/'
        'OQAAd2JJ+QAAeQhOuQAAI4Yz3wAAd2IrXwDSG18AGUK5AACMlE65AAAhAE65AAAgeEzf'
        'f/9Q7AFVACwAAQF4TnVKLAFQZxRD+kaCYQAAwGYEQqwAEFDsAXBgBEIsAXBhAMagUO0A'
        'Cz18ABAAmj18gCAAmkItAA9OuQAAF15w/065AAClNEItAB07fP//AFJOuQAAIfZM33//'
        'TvkAAAO+YRhnBGAAzWJhAMZYQiwBUFDsAXtO+QAAEipI5/zAQfpGDEqsABBnGkP6D7ow'
        'PAH/IthRyP/8Q/oPrGEyZgpB+g+kYR6wrAAcTN8DP051SOf8gGEKKUAAHEzfAT9OdUH6'
        'RcwgPAAACABy/2AA4vpI54DgRekHYEPpASCzymQoDJH/////ZwRYiWDwICwAEEH6BiBg'
        'AiLYU4BrBLPKZfazymQEcABgAnD/TN8HAU51RfoBbgwsAAMBcmYERfoB6GEAARRwABAs'
        'AXLQQEX6AUrU8gAAYQABABAsAXKwPAADZ3QwLABwcgJ0AGEAAMAwOQAAm1JSQHIDYQAA'
        'skH6RTByAHQoMCgAAmEAAKJUiFJBsnwAA2XuECwBcmcKVQBrHGEA8yhgeDAsACZyAXQU'
        'YXwwOQAAm1RyA2FyYGJB+kxQch9wAEqYZwJSQFHJ//hyAHQUYVhgSEH6/YZD+kTSdgAy'
        'A8J8AAM0A+RKxPwAFHAAEBAwMQAAYTRI52AA1HwAC2E+cCC2LAF3ZgJwPmEAxvBM3wAG'
        'XIhSQ7Z8AA1lwkX6AFZhMmEAxQpgAMUmSOdoENR8AAxhCmEAxmpM3wgWTnUvAUf5AAAA'
        'AML8AoDXwTgC50wiH051SOfoEHIAEhqyPAD/Zwx0ABQaYdZhAMYqYOpM3wgXTnUFMkVk'
        'aXRvciBWMi4zLjEgYnkgVGltbyBIZWltb25lbgD/AX0CHQJXAI0AAFggQ29vcmQAAQBZ'
        'IENvb3JkAAIATGV2ZWwAAwBHcm91bmQAAChMZW1taW5ncwABKFRvIFNhdmUAAihNaW51'
        'dGVzAAQAUm9vbQAEFEU6VGVzdCBUOlN0ZWVsIE86T2JqZWN0cyBQOlBhcmFtcyBOOlRp'
        'dGxlIFM6U2F2ZSBVOlVuZG8A/wAAUmVsZWFzZQABAExlbW1pbmdzAAIAVG8gU2F2ZQAD'
        'AE1pbnV0ZXMAABRDbGltYmVycwABFEZsb2F0ZXJzAAIUQm9tYmVycwADFEJsb2NrZXJz'
        'AAAoQnVpbGRlcnMAAShCYXNoZXJzAAIoTWluZXJzAAMoRGlnZ2VycwAAPFN0YXJ0IFgA'
        'ATxTaGlmdDogU3RlcHMgeDEwAAI8VXAvRG93bjogRmllbGQAAzxMZWZ0L1JpZ2h0OiBW'
        'YWx1ZQAEAFJvb20ABBRFOlRlc3QgUDpUZXJyYWluIE46VGl0bGUgUzpTYXZlIFU6VW5k'
        'bwD/ABRQaWVjZQABFFBpZWNlIFR5cGVzAAIUQnJ1c2gAAxRTcGVjaWFsAAMoRmxpcAAA'
        'PExNQjogUGxhY2UAAjxMZWZ0L1JpZ2h0OiBQaWVjZQADPEY6IEZsaXAgIEI6IEJlaGlu'
        'ZAAFAEc6IFNuYXAA/wE8Uk1COiBBZGQvRXJhc2UgICAgICAA/wE8Uk1COiBBZGQgIFNo'
        'aWZ0OiBEZWwA/wAUU3RlZWwgQXJlYXMAADxMTUIgRHJhZzogQWRkAAE8Uk1COiBSZW1v'
        'dmUAAzxUOiBUZXJyYWluAP8AFE9iamVjdAACFE9iamVjdCBTbG90AAMUT2JqZWN0cwAD'
        'KERyYXcAADxMTUI6IFBsYWNlL01vdmUAATxSTUI6IERlbGV0ZQACPExlZnQvUmlnaHQ6'
        'IE9iamVjdAADPEY6IERyYXcgIE86IFRlcnJhaW4ABQBHOiBTbmFwAP8A'
    ),
    'holiday94 whdload relocations': (
        'AAAAAQAAAAgAAAnuAAAX7AAAF/IAABgSAAAhPAAAONgAADn2AAA/IAAAAAIAAACkAAAA'
        'VgAAAOYAAAEAAAABDgAAASgAAAEuAAAB4AAABFAAAARkAAAEkgAABJgAAAS4AAAExAAA'
        'BNwAAAT0AAAFCAAABQ4AAAUUAAAFHAAABSQAAAU0AAAFPgAABUgAAAVSAAAFXAAABdYA'
        'AAXeAAAF6AAABfAAAAX6AAAGBAAABgwAAAYWAAAGHgAABiQAAAYyAAAGpgAABq4AAAa0'
        'AAAJLgAACTQAAAk6AAAJQAAACUYAAAmIAAAJpAAACcQAAAnOAAAM1gAADmQAABIcAAAU'
        'pgAAF7gAABe+AAAXxAAAF9IAABfmAAAYCAAAGHIAABiAAAAYjgAAGKoAABiwAAAYzAAA'
        'GNIAABpMAAAa2AAAGt4AABrkAAAbBAAAGwoAABvWAAAb3AAAG+IAABvoAAAb7gAAHAgA'
        'ABwkAAAcLgAAHDQAABxMAAAceAAAHKAAAByuAAAcwAAAHN4AABz6AAAdAAAAHQYAAB0M'
        'AAAdEgAAHRgAAB0yAAAdOAAAHVgAAB1gAAAdZgAAHZQAAB2aAAAdrgAAHbQAAB26AAAg'
        'igAAIKAAACFEAAAhZAAAIa4AACJGAAAjkgAAI7AAACdUAAAo6gAAK+wAACv4AAAs7gAA'
        'LQAAAC++AAAyUAAAM+IAADP8AAA0CAAANY4AADXUAAA2OgAANogAADaSAAA2ngAANqoA'
        'ADhMAAA5xgAAOdoAADoMAAA6FAAAOhoAADogAAA6MgAAOj4AADtiAAA95gAAPm4AAD64'
        'AAA+vgAAP4YAAD+aAABBCAAAQTIAAEJqAABCxgAARPgAAEVeAABFcgAARYgAAEWOAABF'
        'lAAARZoAAEWuAABFtAAARgAAAEYIAABGGAAARiIAAEY8AABHFAAAR1YAAAADAAAADQAA'
        'AnoAAAxOAAAMZgAADHgAAAyCAAAMjAAADJYAAAygAAAMqgAAEigAABJIAAAhbgAARagA'
        'AAAFAAAADwAAACwAAAA8AAAAQgAAAEoAAAxUAAAMwgAADNwAAA0wAAANTAAADXAAAA2g'
        'AAAN2gAADgAAAA4aAABH6A=='
    ),
    'HolidayLemmings1994.slave': (
        'AAAD8wAAAAAAAAABAAAAAAAAAAAAAADAAAAD6QAAAMBw/051V0hETE9BRFMAERACAAgA'
        'AAAAAAABBAAAAAAAWQAGAAAANABKAGYAAAAAAAAAAAAASG9saWRheSBMZW1taW5ncyAx'
        'OTk0ADE5OTQgRE1BIERlc2lnbiAvIFBzeWdub3NpcwBJbi1HYW1lIExldmVsIEVkaXRv'
        'ciBWMi4zLjEKYnkgVGltbyBIZWltb25lbgBkYXRhL0hvbGlkYXlMZW1taW5nczE5OTQA'
        'SWNvbnMAAAAAAAAAAAAAAAAAZGF0YS8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEP6/6wiiCRIQfr/hSJ6'
        '/w5OqgAIsLwSNFZ4ZgABHCB6/vxCpy88/////y88iBAAA0h4AAgvPIgQAAJIeCAALzyI'
        'EAAAIk9OqgBQT+8AHCB6/sxYiEP6AO5wBUfoAAQiyyIQ5YkgQVHI//Kw/AAAZgAAyCZ6'
        'ANhB+v86IItB+gDeMBhrDCIYsrMAAGYAAKxg8Dd8TnUBYEH6AT43fE75AlYnSAJYQfoA'
        '6jd8Tvkt+CdILfpB+gEuN3xOuRO+J0gTwDd8TnETxCJ6AIzT/AACAAAi/FdIREwiykvr'
        'd94rSQD+Qfr+xmEAAN5OqgAIIG0A/iJITqs0mCt8AAAQAACSK3wAABAAAJZB+v6uK0gA'
        '8kH6AGwhyABoQfoAbiHIAGxOqgAgQfkAB/AATmArSACGR+sDOkb8AABO00h4AAkvOv5w'
        'WJdOdQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFgSOf//gJWLm0Ahi34SOcA8BO+CPkA'
        'BgNKTnFOcf//M/wACADf8JxOczP8AHAA3/CcTnNI57/+Jnr+HE6rAMROk06rF15OqwDE'
        'TO8DAAAcYRZOqgAIIgAvASZ6/fpOkyIfTN9//U51Rfr9+RTYZvxB+v3sJHr93E51SHj/'
        '/y86/dJYl051CPkABgC/7gEvABA6/S2wLQAGZ+AgH051TnEAAAPy'
    ),
    'HolidayLemmings1994.info': (
        '4xAAAQAAAAAAAAAAABoAEwAEAAMAAQAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAA'
        'AAABAAAAAYAAAACAAAAAAAAAAAAAAAAAACgAAAAAAAAaABIAAgAAAAEDAAAAAAAANYAA'
        'AH/AAAD/4AABwHAAAZEwAACAIAAAAAAAAAAAAAH/8AAD//gAAf/wAAD/4AAA/+AAAP/g'
        'AAB7wAAAe8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP4AAAG7AAAB/wAAAf8AAAD+AAAH/'
        '8AAD//gAB//8AAb/7AAA/+AAAP/gAAB7wAAAe8AAAPvgAAH78AAAAAAIV0hETG9hZAAA'
        'AAAUAAAAIFNMQVZFPUhvbGlkYXlMZW1taW5nczE5OTQuc2xhdmUAAAAACFBSRUxPQUQA'
        'AAAADU5PV1JJVEVDQUNIRQAAAAAQKFdSSVRFREVMQVk9MjUpAA=='
    ),
}
# END GENERATED BY build.py


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def embedded(name: str) -> bytes:
    data = base64.b64decode(BLOBS[name])
    if not data or sha256(data) != SHA256[name]:
        raise ValueError(f'Embedded {name} is missing or damaged; run build.py')
    return data


def directory_entries(disk: bytes) -> list[tuple[str, int, int]]:
    """Return (name, offset, size) for every file in the disk directory."""
    if disk[DIRECTORY:DIRECTORY + 12] != b'Reserved\0\0\0\0':
        raise ValueError('Unexpected disk directory')
    entries = []
    offset = PAYLOAD
    for record in range(FIRST_RECORD, DIRECTORY_END, 16):
        raw = disk[record:record + 16]
        if raw == b'\xff' * 16:
            return entries
        name = raw[:12].split(b'\0', 1)[0].decode('ascii')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
            raise ValueError(f'Invalid file name in directory at {record:#x}')
        size = int.from_bytes(raw[12:], 'big')
        if size <= 0 or offset + size > len(disk):
            raise ValueError(f'{name}: file outside the disk')
        entries.append((name, offset, size))
        offset += size
    raise ValueError('Disk directory has no end marker')


def repack(disk: bytes, replacements: dict[str, bytes], tail: tuple[str, bytes]) -> bytes:
    """Rewrite the directory and file area of disk 1 with replaced files and
    put the tail file behind the boot loader, at DISK1_TAIL."""
    entries = directory_entries(disk)
    names = [name for name, _, _ in entries]
    if replacements.keys() - set(names) or {tail[0], TAIL_PLACEHOLDER} & set(names):
        raise ValueError('Invalid replacement or duplicate file')
    if not 0 < len(tail[1]) <= len(disk) - DISK1_TAIL:
        raise ValueError(f'{tail[0]} does not fit behind the boot loader')
    files = [(name, replacements.get(name, disk[offset:offset + size]))
             for name, offset, size in entries]
    end = PAYLOAD + sum(len(data) for _, data in files)
    if end > DISK1_PAYLOAD_LIMIT:
        raise ValueError(f'Files would end at {end:#x}, beyond {DISK1_PAYLOAD_LIMIT:#x}')
    records = ([(name, len(data)) for name, data in files]
               + [(TAIL_PLACEHOLDER, DISK1_TAIL - end), (tail[0], len(tail[1]))])
    if FIRST_RECORD + 16 * (len(records) + 1) > DIRECTORY_END:
        raise ValueError('Disk directory is full')
    result = bytearray(disk)
    result[FIRST_RECORD:DIRECTORY_END] = b'\xff' * (DIRECTORY_END - FIRST_RECORD)
    for index, (name, size) in enumerate(records):
        encoded = name.encode('ascii')
        if len(encoded) > 11 or not size:
            raise ValueError('Invalid file record')
        start = FIRST_RECORD + index * 16
        result[start:start + 16] = encoded + b'\0' + b'\xff' * (11 - len(encoded)) + struct.pack('>I', size)
    offset = PAYLOAD
    for _, data in files:
        result[offset:offset + len(data)] = data
        offset += len(data)
    tail_end = DISK1_TAIL + len(tail[1])
    result[DISK1_TAIL:tail_end] = tail[1]
    if (result[DISK1_PAYLOAD_LIMIT:DISK1_TAIL] != disk[DISK1_PAYLOAD_LIMIT:DISK1_TAIL]
            or result[tail_end:] != disk[tail_end:] or result[:FIRST_RECORD] != disk[:FIRST_RECORD]):
        raise ValueError('Protected disk area would change')
    return bytes(result)


def jump(address: int) -> bytes:
    """JMP address.L followed by NOP: replaces exactly 8 bytes."""
    return b'\x4e\xf9' + struct.pack('>I', address) + b'\x4e\x71'


def hook(code: bytearray, address: int, original: str, replacement: bytes) -> None:
    """Replace original instructions after checking they are the expected ones."""
    expected = bytes.fromhex(original)
    start = address - CODE_BASE
    if len(expected) != len(replacement) or code[start:start + len(expected)] != expected:
        raise ValueError(f'Unexpected game code at {address:#x}')
    code[start:start + len(expected)] = replacement


def patch(disk1: bytes, variant: str = 'floppy') -> bytes:
    """Patch disk 1 with the floppy or the WHDLoad ('whdload') editor."""
    symbols = VARIANTS[variant]
    bootstrap = embedded(f'{variant} bootstrap')
    editor = embedded(f'{variant} Editor')
    if BOOTSTRAP_BASE + len(bootstrap) > symbols['limit']:
        raise ValueError('Embedded bootstrap is too large; run build.py')
    name, offset, size = next(e for e in directory_entries(disk1) if e[0] == 'Code')
    code = bytearray(disk1[offset:offset + size])
    if CODE_BASE + len(code) != BOOTSTRAP_BASE:
        raise ValueError('Unexpected size of the game program')
    # Reserve the editor's memory when the game sets up its file cache. Load
    # and unpack Editor from disk 1 in place of the game's first search for
    # disk 2 (BSR $3C6E / TST.W D0, 6 bytes; the bootstrap runs them
    # afterwards and returns to $510). Install the editor after the level
    # metadata, before the title screen starts.
    hook(code, 0x3916, 'd3f800082b4900f8', jump(symbols['reserve']))
    hook(code, 0x50A, '610037624a40', jump(symbols['load_editor'])[:6])
    hook(code, 0x548, '610037fe61002730', jump(symbols['install_editor']))
    code.extend(bootstrap)
    return repack(disk1, {'Code': bytes(code)}, ('Editor', editor))


# -- Amiga executables (hunks) ------------------------------------------------

HUNK_KINDS = {0x3E9: 'CODE', 0x3EA: 'DATA', 0x3EB: 'BSS'}


def parse_hunks(data: bytes) -> list[dict]:
    """The hunks of an executable: kind, memory flags, allocation, payload
    and relocations (offset, target hunk). Records other than code, data,
    BSS, relocations, symbols and debug data are refused."""
    pos = 0

    def word() -> int:
        nonlocal pos
        if pos + 4 > len(data):
            raise ValueError(f'Truncated program at {pos:#x}')
        value = struct.unpack_from('>I', data, pos)[0]
        pos += 4
        return value

    def skip(count: int) -> None:
        nonlocal pos
        pos += count * 4
        if pos > len(data):
            raise ValueError('Truncated program')

    if word() != 0x3F3:
        raise ValueError('Not an Amiga executable')
    while (count := word()):
        skip(count)
    count, first, last = word(), word(), word()
    if first != 0 or last != count - 1:
        raise ValueError('Unexpected hunk table')
    allocations = []
    for _ in range(count):
        value = word()
        if value >> 30 == 3:
            raise ValueError('Unexpected memory flags')
        allocations.append((4 * (value & 0x3FFFFFFF), value >> 30))
    hunks = []
    for allocation, flags in allocations:
        tag = word()
        while tag & 0x3FFFFFFF == 0x3E8:                   # HUNK_NAME
            skip(word())
            tag = word()
        kind = HUNK_KINDS.get(tag & 0x3FFFFFFF)
        if kind is None:
            raise ValueError(f'Unexpected hunk {tag:#x} at {pos - 4:#x}')
        size = word() * 4
        if size > allocation:
            raise ValueError('Hunk larger than its allocation')
        payload = b''
        if kind != 'BSS':
            payload = data[pos:pos + size]
            skip(size // 4)
        relocations = []
        while (tag := word()) != 0x3F2:                     # HUNK_END
            if tag == 0x3EC:                                # HUNK_RELOC32
                while (number := word()):
                    target = word()
                    if target >= count:
                        raise ValueError('Relocation to an unknown hunk')
                    for _ in range(number):
                        at = word()
                        if at & 1 or at + 4 > size or kind == 'BSS':
                            raise ValueError('Invalid relocation')
                        relocations.append((at, target))
            elif tag == 0x3F0:                              # HUNK_SYMBOL
                while (number := word()):
                    skip(number)
                    word()
            elif tag == 0x3F1:                              # HUNK_DEBUG
                skip(word())
            else:
                raise ValueError(f'Unexpected record {tag:#x} at {pos - 4:#x}')
        hunks.append(dict(kind=kind, memory_flags=flags, allocation=allocation,
                          payload=payload, relocations=relocations))
    if pos != len(data):
        raise ValueError('Trailing bytes after the hunks')
    return hunks


def write_hunks(hunks: list[dict]) -> bytes:
    """An executable of hunks as parse_hunks() returns them."""
    out = bytearray()

    def word(value: int) -> None:
        out.extend(struct.pack('>I', value & 0xFFFFFFFF))

    for value in (0x3F3, 0, len(hunks), 0, len(hunks) - 1):
        word(value)
    for hunk in hunks:
        if hunk['allocation'] % 4 or len(hunk['payload']) % 4 or len(hunk['payload']) > hunk['allocation']:
            raise ValueError('Hunk sizes must be longword multiples within the allocation')
        word(hunk['allocation'] // 4 | hunk['memory_flags'] << 30)
    for hunk in hunks:
        word({kind: tag for tag, kind in HUNK_KINDS.items()}[hunk['kind']])
        if hunk['kind'] == 'BSS':
            word(hunk['allocation'] // 4)
        else:
            word(len(hunk['payload']) // 4)
            out.extend(hunk['payload'])
        groups: dict[int, list[int]] = {}
        for offset, target in sorted(hunk['relocations']):
            if offset & 1 or offset + 4 > len(hunk['payload']) or not 0 <= target < len(hunks):
                raise ValueError('Invalid relocation')
            groups.setdefault(target, []).append(offset)
        if groups:
            word(0x3EC)
            for target, offsets in sorted(groups.items()):
                word(len(offsets))
                word(target)
                for offset in offsets:
                    word(offset)
            word(0)
        word(0x3F2)
    return bytes(out)


# -- AmigaDOS (OFS) disks -----------------------------------------------------

OFS_BLOCK = 512
OFS_BLOCKS = 1760
OFS_ROOT = 880
OFS_HASH_SIZE = 72
OFS_DATA_BYTES = 488
T_HEADER, T_DATA, T_LIST = 2, 8, 16
ST_ROOT, ST_USERDIR, ST_FILE = 1, 2, -3


def ofs_upper(name: str) -> bytes:
    """A name as the file system compares it: only a..z are folded."""
    return bytes(c - 32 if 97 <= c <= 122 else c for c in name.encode('latin-1'))


def ofs_hash(name: str) -> int:
    value = len(name)
    for char in ofs_upper(name):
        value = (value * 13 + char) & 0x7FF
    return value % OFS_HASH_SIZE


class OFS:
    """Read and change files of an AmigaDOS OFS floppy image: what patching
    the game's disk needs. Every changed block gets its checksum, the bitmap
    follows every allocation, and check() validates the file system."""

    def __init__(self, image: bytes):
        if len(image) != OFS_BLOCKS * OFS_BLOCK or image[:4] != b'DOS\0':
            raise ValueError('Not an OFS floppy image')
        self.image = bytearray(image)
        root = self.block(OFS_ROOT)
        if self.long(root, 0) != T_HEADER or self.slong(root, 508) != ST_ROOT:
            raise ValueError('Invalid root block')
        self.bitmap_block = self.long(root, 316)

    def block(self, number: int) -> memoryview:
        if not 2 <= number < OFS_BLOCKS:
            raise ValueError(f'Block {number} out of range')
        return memoryview(self.image)[number * OFS_BLOCK:(number + 1) * OFS_BLOCK]

    @staticmethod
    def long(block, offset: int) -> int:
        return struct.unpack_from('>I', block, offset)[0]

    @staticmethod
    def slong(block, offset: int) -> int:
        return struct.unpack_from('>i', block, offset)[0]

    @staticmethod
    def put(block, offset: int, value: int) -> None:
        struct.pack_into('>I', block, offset, value & 0xFFFFFFFF)

    def seal(self, number: int) -> None:
        """Set the checksum (offset 20) so that the block's longs sum to 0."""
        block = self.block(number)
        self.put(block, 20, 0)
        self.put(block, 20, -sum(struct.unpack('>128I', block)))

    def _bit(self, number: int) -> tuple[int, int]:
        index = number - 2
        return 4 + (index // 32) * 4, 1 << (index % 32)

    def is_free(self, number: int) -> bool:
        offset, bit = self._bit(number)
        return bool(self.long(self.block(self.bitmap_block), offset) & bit)

    def _set_free(self, number: int, free: bool) -> None:
        bitmap = self.block(self.bitmap_block)
        offset, bit = self._bit(number)
        value = self.long(bitmap, offset)
        self.put(bitmap, offset, value | bit if free else value & ~bit)
        self.put(bitmap, 0, 0)
        self.put(bitmap, 0, -sum(struct.unpack('>128I', bitmap)))

    def allocate(self) -> int:
        """A free block, the nearest to the root first, as AmigaDOS does."""
        for distance in range(1, OFS_BLOCKS):
            for number in (OFS_ROOT + distance, OFS_ROOT - distance):
                if 2 <= number < OFS_BLOCKS and self.is_free(number):
                    self._set_free(number, False)
                    self.image[number * OFS_BLOCK:(number + 1) * OFS_BLOCK] = bytes(OFS_BLOCK)
                    return number
        raise ValueError('The disk is full')

    def name(self, number: int) -> str:
        block = self.block(number)
        return bytes(block[433:433 + block[432]]).decode('latin-1')

    def entries(self, directory: int) -> dict[str, int]:
        result, seen = {}, set()
        block = self.block(directory)
        for slot in range(OFS_HASH_SIZE):
            number = self.long(block, 24 + slot * 4)
            while number:
                if number in seen:
                    raise ValueError('Damaged directory')
                seen.add(number)
                result[self.name(number)] = number
                number = self.long(self.block(number), 496)
        return result

    def kind(self, number: int) -> int:
        return self.slong(self.block(number), 508)

    def lookup(self, path: str) -> int:
        number = OFS_ROOT
        for part in filter(None, path.split('/')):
            found = {ofs_upper(k): v for k, v in self.entries(number).items()}.get(ofs_upper(part))
            if found is None:
                raise FileNotFoundError(path)
            number = found
        return number

    def _parent_and_name(self, path: str) -> tuple[int, str]:
        parent, _, name = path.rpartition('/')
        if not name or len(name.encode('latin-1')) > 30:
            raise ValueError(f'Invalid name: {path}')
        return self.lookup(parent), name

    def _link(self, directory: int, number: int, name: str) -> None:
        slot = 24 + ofs_hash(name) * 4
        block = self.block(directory)
        self.put(self.block(number), 496, self.long(block, slot))     # hash chain
        self.put(block, slot, number)
        self.seal(directory)

    def _unlink(self, directory: int, number: int, name: str) -> None:
        slot = 24 + ofs_hash(name) * 4
        block = self.block(directory)
        following = self.long(self.block(number), 496)
        if self.long(block, slot) == number:
            self.put(block, slot, following)
            self.seal(directory)
            return
        current = self.long(block, slot)
        while current:
            chained = self.block(current)
            if self.long(chained, 496) == number:
                self.put(chained, 496, following)
                self.seal(current)
                return
            current = self.long(chained, 496)
        raise ValueError(f'{name} is not in its directory')

    def _header(self, number: int, name: str, parent: int, kind: int, date: bytes) -> None:
        block = self.block(number)
        self.put(block, 0, T_HEADER)
        self.put(block, 4, number)
        encoded = name.encode('latin-1')
        block[432] = len(encoded)
        block[433:433 + len(encoded)] = encoded
        block[420:432] = date
        self.put(block, 500, parent)
        self.put(block, 508, kind)

    def date(self, number: int) -> bytes:
        return bytes(self.block(number)[420:432])

    def read(self, path: str) -> bytes:
        number = self.lookup(path)
        header = self.block(number)
        if self.slong(header, 508) != ST_FILE:
            raise ValueError(f'{path} is not a file')
        size = self.long(header, 324)
        data = bytearray()
        following = self.long(header, 16)
        for _ in range(OFS_BLOCKS):
            if not following or len(data) >= size:
                break
            block = self.block(following)
            if self.long(block, 0) != T_DATA or self.long(block, 4) != number:
                raise ValueError(f'{path}: broken data chain')
            data += block[24:24 + self.long(block, 12)]
            following = self.long(block, 16)
        if len(data) != size:
            raise ValueError(f'{path}: {len(data)} of {size} bytes')
        return bytes(data)

    def _blocks_of(self, number: int) -> list[int]:
        """The header, its extension blocks and every data block of a file."""
        blocks, current = [], number
        while current:
            if len(blocks) > OFS_BLOCKS:
                raise ValueError('Damaged file')
            block = self.block(current)
            blocks.append(current)
            for index in range(self.long(block, 8)):
                blocks.append(self.long(block, 308 - index * 4))
            current = self.long(block, 504)
        return blocks

    def delete(self, path: str) -> None:
        parent, _ = self._parent_and_name(path)
        number = self.lookup(path)
        if self.kind(number) != ST_FILE:
            raise ValueError(f'{path} is not a file')
        self._unlink(parent, number, self.name(number))
        for block in self._blocks_of(number):
            self._set_free(block, True)

    def write(self, path: str, data: bytes) -> None:
        """Add the file, replacing one of the same name and keeping its date."""
        parent, name = self._parent_and_name(path)
        try:
            old = self.lookup(path)
        except FileNotFoundError:
            old = None
        date = self.date(parent)
        if old is not None:
            date, name = self.date(old), self.name(old)
            self.delete(path)
        header = self.allocate()
        self._header(header, name, parent, ST_FILE, date)
        self.put(self.block(header), 324, len(data))
        chunks = [data[i:i + OFS_DATA_BYTES] for i in range(0, len(data), OFS_DATA_BYTES)]
        data_blocks = [self.allocate() for _ in chunks]
        for index, (number, chunk) in enumerate(zip(data_blocks, chunks)):
            block = self.block(number)
            self.put(block, 0, T_DATA)
            self.put(block, 4, header)
            self.put(block, 8, index + 1)
            self.put(block, 12, len(chunk))
            self.put(block, 16, data_blocks[index + 1] if index + 1 < len(data_blocks) else 0)
            block[24:24 + len(chunk)] = chunk
            self.seal(number)
        # The data block table of the header, then of extension blocks.
        owner = header
        for start in range(0, max(len(data_blocks), 1), OFS_HASH_SIZE):
            part = data_blocks[start:start + OFS_HASH_SIZE]
            block = self.block(owner)
            self.put(block, 8, len(part))
            for index, number in enumerate(part):
                self.put(block, 308 - index * 4, number)
            if start == 0:
                self.put(block, 16, data_blocks[0] if data_blocks else 0)
            if start + OFS_HASH_SIZE < len(data_blocks):
                extension = self.allocate()
                ext = self.block(extension)
                self.put(ext, 0, T_LIST)
                self.put(ext, 4, extension)
                self.put(ext, 500, header)
                self.put(ext, 508, ST_FILE)
                self.put(block, 504, extension)
                self.seal(owner)
                owner = extension
            else:
                self.seal(owner)
        self._link(parent, header, name)

    def mkdir(self, path: str) -> None:
        parent, name = self._parent_and_name(path)
        try:
            self.lookup(path)
            raise ValueError(f'{path} exists')
        except FileNotFoundError:
            pass
        number = self.allocate()
        self._header(number, name, parent, ST_USERDIR, self.date(parent))
        self.seal(number)
        self._link(parent, number, name)

    def check(self) -> None:
        """Checksums of every reachable block, and the bitmap against them."""
        used = {OFS_ROOT, self.bitmap_block}

        def sealed(number: int) -> None:
            if sum(struct.unpack('>128I', self.block(number))) & 0xFFFFFFFF:
                raise ValueError(f'Block {number}: bad checksum')

        def walk(directory: int, path: str) -> None:
            sealed(directory)
            for name, number in self.entries(directory).items():
                if self.kind(number) == ST_USERDIR:
                    used.add(number)
                    walk(number, f'{path}{name}/')
                elif self.kind(number) == ST_FILE:
                    for block in self._blocks_of(number):
                        sealed(block)
                        used.add(block)
                    self.read(f'{path}{name}')
                else:
                    raise ValueError(f'{name}: unknown block type')

        walk(OFS_ROOT, '')
        if sum(struct.unpack('>128I', self.block(self.bitmap_block))) & 0xFFFFFFFF:
            raise ValueError('Bitmap: bad checksum')
        for number in range(2, OFS_BLOCKS):
            if (number in used) == self.is_free(number):
                raise ValueError(f'Block {number}: bitmap does not match its use')


# -- Holiday Lemmings 1994 ----------------------------------------------------

def holiday_relocations(table: bytes) -> list[tuple[int, int]]:
    """The editor's relocations (offset, target hunk) from their table."""
    values = struct.unpack(f'>{len(table) // 4}I', table)
    relocations, pos = [], 0
    while pos < len(values):
        target, count = values[pos], values[pos + 1]
        relocations += [(offset, target) for offset in values[pos + 2:pos + 2 + count]]
        pos += 2 + count
    return relocations


def patch_holiday(image: bytes, variant: str = 'floppy') -> OFS:
    """The Holiday Lemmings 1994 disk with the floppy or the WHDLoad
    ('whdload') editor added to the game's program."""
    symbols = HOLIDAY94_VARIANTS[variant]
    editor = embedded(f'holiday94 {variant} editor')
    disk = OFS(image)
    program = disk.read(HOLIDAY94_PROGRAM)
    if sha256(program) != HOLIDAY94_PROGRAM_SHA256:
        raise ValueError('Unexpected game program')
    hunks = parse_hunks(program)
    if len(hunks) != 4:
        raise ValueError('Unexpected game program')
    code = hunks[2]
    payload = bytearray(code['payload'])
    relocations = list(code['relocations'])
    # Each hook replaces whole instructions with a jump into the editor
    # (hunk 4); a relocation inside the replaced bytes goes, the jump's own
    # address gets one.
    for site, original, label, instruction in HOLIDAY94_HOOKS:
        expected = bytes.fromhex(original)
        if payload[site:site + len(expected)] != expected or len(expected) < 6:
            raise ValueError(f'Unexpected game code at {site:#x}')
        opcode = {'jmp': b'\x4e\xf9', 'jsr': b'\x4e\xb9'}[instruction]
        replacement = opcode + struct.pack('>I', symbols[label]) + b'\x4e\x71' * ((len(expected) - 6) // 2)
        payload[site:site + len(expected)] = replacement
        relocations = [r for r in relocations if not site <= r[0] < site + len(expected)]
        relocations.append((site + 2, 4))
    code = dict(code, payload=bytes(payload), relocations=relocations)
    editor_hunk = dict(kind='CODE', memory_flags=0, allocation=symbols['reserve'],
                       payload=editor + bytes(-len(editor) % 4),
                       relocations=holiday_relocations(embedded(f'holiday94 {variant} relocations')))
    chip_hunk = dict(kind='BSS', memory_flags=1, allocation=(symbols['chip'] + 3) & ~3,
                     payload=b'', relocations=[])
    patched = write_hunks([hunks[0], hunks[1], code, hunks[3], editor_hunk, chip_hunk])
    if parse_hunks(patched)[2]['payload'] != code['payload']:
        raise ValueError('Program round trip failed')
    disk.write(HOLIDAY94_PROGRAM, patched)
    disk.mkdir(f'{HOLIDAY94_DIRECTORY}/{LEVELS}')
    disk.check()
    return disk


def holiday_install(image: bytes) -> dict[str, bytes]:
    """The files of the Holiday Lemmings 1994 WHDLoad install, by path."""
    disk = patch_holiday(image, 'whdload')
    program = disk.read(HOLIDAY94_PROGRAM)
    slave = bytearray(embedded('HolidayLemmings1994.slave'))
    at = HOLIDAY94_SLAVE_SIZE_AT
    if slave[at:at + 4] != struct.pack('>I', HOLIDAY94_SLAVE_SIZE):
        raise ValueError('Embedded HolidayLemmings1994.slave is damaged; run build.py')
    slave[at:at + 4] = struct.pack('>I', len(program))      # it accepts only this program
    files = {'HolidayLemmings1994.slave': bytes(slave),
             'HolidayLemmings1994.info': embedded('HolidayLemmings1994.info')}
    directory = disk.lookup(HOLIDAY94_DIRECTORY)
    for name, number in disk.entries(directory).items():
        if (disk.kind(number) == ST_FILE and not name.lower().endswith('.info')
                and name.lower() not in HOLIDAY94_SKIPPED):
            if name in ('.', '..') or any(c in name for c in '/:\\\0'):
                raise ValueError(f'Unexpected file name {name!r} on the disk')
            files[f'{HOLIDAY94_DATA}/{name}'] = disk.read(f'{HOLIDAY94_DIRECTORY}/{name}')
    return files


def identify(paths: list[Path]) -> tuple[str, dict[int, bytes]]:
    """Read the inputs and match them by hash: 'lemmings' with disk 1 and
    disk 2, or 'holiday94' with its disk as number 1."""
    by_hash = {digest: ('lemmings', number) for number, digest in INPUT_SHA256.items()}
    by_hash[HOLIDAY94_SHA256] = ('holiday94', 1)
    games: set[str] = set()
    disks: dict[int, bytes] = {}
    for path in paths:
        data = path.read_bytes()
        game, number = by_hash.get(sha256(data), (None, None)) if len(data) == DISK_SIZE else (None, None)
        if game is None:
            raise ValueError(f'{path}: not a supported Lemmings or Holiday Lemmings 1994 disk '
                             'image (SHA-256 does not match)')
        if number in disks and game in games:
            raise ValueError(f'{path}: this disk was given twice')
        games.add(game)
        disks[number] = data
    if len(games) != 1:
        raise ValueError('the images must be the disks of one game')
    return games.pop(), disks


def write(path: Path, data: bytes, inputs: list[Path]) -> None:
    path.parent.mkdir(exist_ok=True)
    if path.is_symlink():
        raise ValueError(f'{path}: refusing to write through a symbolic link')
    if path.exists() and any(path.samefile(source) for source in inputs):
        raise ValueError(f'{path}: output would overwrite an input image')
    # Write a new file and move it into place, so an existing file (or a hard
    # link to an input) is replaced rather than modified.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, suffix='.tmp', delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(data)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=f'Lemmings in-game level editor V{VERSION} disk patcher.')
    parser.add_argument('disks', nargs='+', type=Path, metavar='DISK.adf',
                        help='the original Lemmings disk 1 image, and disk 2 (needed for '
                             '--whdload), in any order; or the Holiday Lemmings 1994 disk image')
    parser.add_argument('-o', '--output', type=Path, default=Path('.'),
                        help='directory for the patched images (default: current directory)')
    parser.add_argument('--whdload', type=Path, metavar='INSTALL_DIR',
                        help='write the WHDLoad install to this directory instead')
    args = parser.parse_args()
    if len(args.disks) > 2:
        parser.error('at most two disk images')
    try:
        game, disks = identify(args.disks)
        if 1 not in disks:
            raise ValueError('disk 1 is required')
        if game == 'holiday94':
            if args.whdload:
                output = args.whdload
                files = holiday_install(disks[1])
            else:
                output = args.output
                files = {HOLIDAY94_OUTPUT_NAME: bytes(patch_holiday(disks[1]).image)}
        elif args.whdload:
            if 2 not in disks:
                raise ValueError('the WHDLoad install needs disk 2 as well')
            output = args.whdload
            files = {'Lemmings.slave': embedded('Lemmings.slave'),
                     'Disk.1': patch(disks[1], 'whdload'), 'Disk.2': disks[2],
                     'Lemmings.info': embedded('Lemmings.info')}
        else:
            output = args.output
            files = {OUTPUT_NAME: patch(disks[1])}
        output.mkdir(parents=True, exist_ok=True)
        for name, data in files.items():
            path = output / name
            write(path, data, args.disks)
            if not name.startswith(f'{HOLIDAY94_DATA}/'):
                print(f'{path}  SHA-256 {sha256(data)}')
        if game == 'holiday94' and args.whdload:
            print(f'{output / HOLIDAY94_DATA}/  {len(files) - 2} files of the game, its program patched')
        if args.whdload:
            (output / LEVELS).mkdir(exist_ok=True)
            print(f'{output / LEVELS}/')
        elif game == 'lemmings':
            print('Use disk 2 unchanged.')
    except (OSError, ValueError) as error:
        parser.exit(1, f'error: {error}\n')


if __name__ == '__main__':
    main()
