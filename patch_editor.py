#!/usr/bin/env python3
"""Patch selected no-argument void method bodies, preserving DEX layout."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
import zlib

TARGETS = {
    "Lmiuix/textaction/Query;",
    "Lmiuix/textaction/Translate;",
    "Lmiuix/textaction/AskHyperXiaoai;",
    "Lmiuix/textaction/AiRecognition;",
    "Lmiuix/textaction/Phrases;",
}

def patch_dex(raw):
    data = bytearray(raw)
    assert data[:4] == b"dex\n", "Unsupported dex format"
    def u32(at): return struct.unpack_from('<I', data, at)[0]
    def u16(at): return struct.unpack_from('<H', data, at)[0]
    def uleb(at):
        value = shift = 0
        while True:
            byte = data[at]; at += 1
            value |= (byte & 127) << shift
            if byte < 128: return value, at
            shift += 7
            assert shift < 35
    strings = []
    for i in range(u32(56)):
        off = u32(u32(60) + i * 4)
        _, off = uleb(off)
        strings.append(bytes(data[off:data.index(0, off)]).decode('utf-8', 'replace'))
    types = [strings[u32(u32(68) + i * 4)] for i in range(u32(64))]
    changed = []
    for i in range(u32(96)):
        class_off = u32(100) + 32 * i
        descriptor = types[u32(class_off)]
        if descriptor not in TARGETS: continue
        pos = u32(class_off + 24)
        counts = []
        for _ in range(4):
            v, pos = uleb(pos); counts.append(v)
        for _ in range(counts[0] + counts[1]):
            _, pos = uleb(pos); _, pos = uleb(pos)
        for count in counts[2:]:
            method_index = 0
            for _ in range(count):
                delta, pos = uleb(pos); method_index += delta
                _, pos = uleb(pos)
                code, pos = uleb(pos)
                method_off = u32(92) + method_index * 8
                if strings[u32(method_off + 4)] != 'onInvalidated': continue
                proto = u32(76) + u16(method_off + 2) * 12
                assert types[u32(proto + 4)] == 'V' and u32(proto + 8) == 0
                assert code, 'Missing code item'
                size = u32(code + 12) * 2
                assert size >= 2
                before = bytes(data[code+16:code+16+size])
                # return-void plus nops. Existing try/catch ranges still point at valid insns.
                data[code+16:code+16+size] = b'\x0e\x00' + bytes(size-2)
                changed.append({'class': descriptor, 'method': 'onInvalidated()V',
                                'code_offset': code, 'instruction_bytes': size,
                                'tries_size': u16(code + 6),
                                'original_body_sha256': hashlib.sha256(before).hexdigest()})
    if changed:
        data[12:32] = hashlib.sha1(data[32:]).digest()
        struct.pack_into('<I', data, 8, zlib.adler32(data[12:]) & 0xffffffff)
    return bytes(data), changed

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    changes = []
    with zipfile.ZipFile(args.source) as src, zipfile.ZipFile(args.output, 'w') as dst:
        for entry in src.infolist():
            raw = src.read(entry)
            if entry.filename.endswith('.dex'):
                raw, found = patch_dex(raw)
                changes.extend(dict(dex=entry.filename, **x) for x in found)
            dst.writestr(entry, raw)
    assert {x['class'] for x in changes} == TARGETS and len(changes) == len(TARGETS), changes
    # Verify all APK entries other than the targeted DEX are byte-for-byte identical.
    with zipfile.ZipFile(args.source) as src, zipfile.ZipFile(args.output) as dst:
        touched = {x['dex'] for x in changes}
        assert src.namelist() == dst.namelist()
        for name in src.namelist():
            if name not in touched: assert src.read(name) == dst.read(name), name
    report = {'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(), 'changes': changes}
    args.output.with_suffix('.patch.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__': main()
