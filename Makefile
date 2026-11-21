SHELL := /bin/sh

.PHONY: all check check-secrets check-examples check-links

all: check

check: check-secrets check-examples check-links

# 发布前必跑：任何真实账号 / selector / 应用标识都不该出现在仓库里
check-secrets:
	@bash tools/check-secrets.sh

# 示例必须能被解析——它们是不可执行的规格，但不能是坏的
check-examples:
	@python3 -m py_compile examples/*.py && echo 'ok: python 示例可编译'
	@bash -n examples/app-to-ipa.sh && echo 'ok: bash 示例可解析'
	@rm -rf examples/__pycache__

# 文档仓库的“编译”就是链接可达性
check-links:
	@python3 tools/check-links.py
