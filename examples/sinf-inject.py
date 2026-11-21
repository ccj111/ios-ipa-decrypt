#!/usr/bin/env python3
"""sinf-inject.py — TF 服务端包没有 SC_Info/*.sinf，从 install 元数据回插

用法:
    python3 sinf-inject.py install.json app.ipa app-sinf.ipa

要点:
  * SINF 在 install.json 的 sinf 字段（plist 字符串），约 1056 B
  * 成员名必须是 Payload/<App>.app/SC_Info/<App>.sinf，<App> 与 appFileName 对齐
  * 只改容器，不改 payload；zipfile 默认不写目录条目（等价 zip -D）
"""
import json
import plistlib
import shutil
import sys
import zipfile

meta, src, dst = sys.argv[1:4]
raw = json.load(open(meta))
sinf = plistlib.loads(raw["sinf"].encode())["sinfs"][0]["sinf"]
app = raw.get("appFileName") or "App"
member = f"Payload/{app}.app/SC_Info/{app}.sinf"

shutil.copyfile(src, dst)
with zipfile.ZipFile(dst, "a", zipfile.ZIP_DEFLATED) as z:
    z.writestr(member, sinf)
print(f"{len(sinf)} B → {member}")
