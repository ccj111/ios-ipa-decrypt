#!/usr/bin/env python3
"""cryptid.py — 唯一有效的加密状态判据：LC_ENCRYPTION_INFO(_64).cryptid

用法:
    python3 cryptid.py Payload/App.app/App
    python3 cryptid.py Payload/App.app            # 递归扫该 bundle 下所有 Mach-O

判据: 全部 0 才是明文；无该 load command 视为未加密；fat 包逐切片读。
注意: 0x2C 是 LC_ENCRYPTION_INFO_64，0x21 是 LC_ENCRYPTION_INFO —— 别记反。
"""
import os
import struct
import sys

MAGICS = {b"\xcf\xfa\xed\xfe": 64, b"\xce\xfa\xed\xfe": 32,
          b"\xfe\xed\xfa\xcf": 64, b"\xfe\xed\xfa\xce": 32}


def thin(blob: bytes):
    magic = blob[:4]
    if magic not in MAGICS:
        return None
    endian = "<" if magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe") else ">"
    off, ncmds = (32 if MAGICS[magic] == 64 else 28), struct.unpack(endian + "I", blob[16:20])[0]
    for _ in range(ncmds):
        cmd, size = struct.unpack(endian + "II", blob[off:off + 8])
        if cmd in (0x21, 0x2C):
            return struct.unpack(endian + "III", blob[off + 8:off + 20])[2]
        off += size or 8
    return 0                                   # 没有加密段 == 未加密


def report(path: str):
    with open(path, "rb") as fh:
        head = fh.read(8)
        fh.seek(0)
        if head[:4] == b"\xca\xfe\xba\xbe":     # fat
            n = struct.unpack(">I", head[4:8])[0]
            for i in range(n):
                fh.seek(8 + i * 20)
                _cpu, _sub, off, size = struct.unpack(">4I", fh.read(16))
                fh.seek(off)
                print(f"{path} [slice {i}] cryptid={thin(fh.read(size))}")
        else:
            print(f"{path} cryptid={thin(fh.read())}")


targets = [sys.argv[1]] if not os.path.isdir(sys.argv[1]) else [
    os.path.join(d, f) for d, _, fs in os.walk(sys.argv[1]) for f in fs
    if os.path.isfile(os.path.join(d, f))]
for t in targets:
    try:
        if open(t, "rb").read(4) in MAGICS:
            report(t)
    except OSError:
        pass
