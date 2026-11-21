#!/usr/bin/env python3
"""check-links.py — 文档的相对链接必须可达；这是文档仓库唯一真正的“编译”错误。"""
import os
import re
import sys

SKIP_DIRS = {'.git', '__pycache__', 'node_modules'}


def main() -> int:
    bad = []
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if not name.endswith('.md'):
                continue
            path = os.path.join(root, name)
            text = open(path, encoding='utf-8').read()
            for link in re.findall(r'\]\(([^)\s]+)', text):
                if link.startswith(('http://', 'https://', 'mailto:', '#')):
                    continue
                target = os.path.normpath(os.path.join(root, link.split('#')[0]))
                if not os.path.exists(target):
                    bad.append(f'{path} -> {link}')
    if bad:
        print('\n'.join(bad))
        print(f'FAIL: {len(bad)} 个相对链接不可达')
        return 1
    print('ok: 相对链接全部可达')
    return 0


if __name__ == '__main__':
    sys.exit(main())
