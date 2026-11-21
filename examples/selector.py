#!/usr/bin/env python3
"""selector.py — 解密权绑定的那个数：sha256(be32(user) ‖ be32(key))

用法:
    python3 selector.py <user> <key>          # 从 SINF 的 schi/user、schi/key 取值

判据：selector 相同 → 同一份 enrollment model 通吃所有渠道；不同 → 换 credential，没有参数可调。
它不是 Apple ID 的哈希，也与渠道、bundleId 无关。
"""
import hashlib
import struct
import sys

user, key = (int(a) for a in sys.argv[1:3])
print(hashlib.sha256(struct.pack(">I", user) + struct.pack(">I", key)).hexdigest())
