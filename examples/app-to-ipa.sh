#!/usr/bin/env bash
# app-to-ipa.sh — 本机已装的 iOS 应用（Wrapper 结构）→ 加密 IPA
#
# 结构：/Applications/<X>.app/Wrapper/<Inner>.app/{Inner, SC_Info/, Frameworks/, Info.plist}
# 特性：包内自带 SINF —— 不需要会话、不需要网络、不需要 root。
# 用法：bash app-to-ipa.sh "/Applications/<X>.app" /abs/path/out.ipa
set -eu
APP="$1"; OUT="$(cd "$(dirname "${2:-./out.ipa}")" && pwd)/$(basename "${2:-out.ipa}")"
INNER="$(ls -d "$APP"/Wrapper/*.app | head -1)"
WORK="$(mktemp -d)"; mkdir -p "$WORK/Payload"
ditto "$INNER" "$WORK/Payload/$(basename "$INNER")"
(cd "$WORK" && zip -qry -X -D "$OUT" Payload)   # -D: 不写目录条目（Go zip 不接受）
rm -rf "$WORK"; echo "$OUT"
