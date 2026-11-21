# ios-ipa-decrypt —— 方案笔记

在 Apple Silicon Mac 上把 IPA 拿到手并在主机侧解开，**不需要越狱设备**。

这个仓库是**文档，不是工具**。它写清机制、判据、实测数字和失败签名，配少量 ≤20 行的示例让每条结论可核对。端到端脚本刻意不放：真正不可替代的知识大约 5 KB，剩下 95% 是重试、回退、清理和参数解析，写进仓库只会把判据埋掉。

## 撑起全部内容的两条事实

1. **token ≠ credential**。TestFlight 会话只给“下载权”；“解密权”是账号级的 FairPlay credential，绑在每个 `SC_Info/*.sinf` 的 `user` + `key` 上——这对字段叫 **selector**。同 selector → 一份 enrollment model 通吃所有渠道的包，永久有效。不同 selector → 会话再新也解不了。
2. **会话不用换，去读**。TestFlight 客户端把 `POST /v1/session/authenticate` 的响应写进了自己的 CFNetwork 缓存，一条只读 SQL 就能取回 `sessionId` 与 `accountId`。不需要 GSA 登录、不需要 root、不用装根证书、不碰系统代理。

## 实测证据（同一 selector，三个包）

| 样本 | 取源 | 加密 | 解密后 | cryptid |
| --- | --- | --- | --- | --- |
| A | TestFlight 服务端 | 260,225,568 B | 173,156,713 B | `[0]` |
| B | TestFlight 本机 Wrapper | 44,845,042 B | 45,057,814 B | `[0]` |
| C | TestFlight 本机 Wrapper | 56,113,054 B | 56,147,264 B | `[0]` |

三个包命中同一 selector，即同一份 model——这就是重点：**解密这一步不知道、也不关心包是从哪个渠道来的。** 原始记录里的账号、selector、应用标识在发布前已全部脱敏。

## 从哪读起

| 文件 | 回答什么 |
| --- | --- |
| [docs/01-sources.md](docs/01-sources.md) | 三个取源各能拿到什么，各自代价是什么 |
| [docs/02-session.md](docs/02-session.md) | 会话在磁盘哪里；`dsid` / `AMD-M` / storefront 为什么老出错 |
| [docs/03-install.md](docs/03-install.md) | install 元数据里到底有什么；为什么不能自己拼 `?token=` |
| [docs/04-sinf.md](docs/04-sinf.md) | 为什么这个包没有 `.sinf`；selector 是什么 |
| [docs/05-decrypt.md](docs/05-decrypt.md) | 为什么 `sudo` 只要一次；为什么 `setup --app` 与 `decrypt --ipa` 必须是同一个应用 |
| [docs/06-verify.md](docs/06-verify.md) | 哪三个数字才真正证明二进制已是明文 |
| [docs/07-troubleshooting.md](docs/07-troubleshooting.md) | 报错字面 vs 真实根因 |
| [docs/08-environment.md](docs/08-environment.md) | fake-ip DNS、UA、plist 布尔、zip 布局、版本漂移 |
| [docs/flow.svg](docs/flow.svg) | 一张图看完整决策树 |
| [SKILL.md](SKILL.md) | 给 agent 的形态：决策表、停手条件、失败签名 |

## 明确不在范围内

- **没有 beta 席位就没有包**。TestFlight 是“席位”：账号必须已获得该 beta 的访问权。App Store 更接近“通行证”：`acquire` 过一次即可反复下载。
- **没有 Apple Silicon enrollment 就没有主机侧解密**。Intel Mac、或从未登录 Mac App Store 的机器没有 `fpsd` enrollment，建不出 model；剩下的路是用越狱设备取 16 字节 credential。
- **selector 不匹配就解不了**。不同 selector 就是不同 credential，症状是 `SINF authentication failed`，没有可调参数。
- **解密后 ≠ 能装**。清 `cryptid` 会破坏 CodeDirectory 哈希，安装前必须重签。

## 依赖

Apple Silicon Mac、Python 3.8+（仅标准库）、`curl zip unzip ditto plutil shasum`、处于登录态的 TestFlight 客户端（App Store 路线则需要 Mac App Store 账号）。编译上游解密工具需要 C++20 工具链与 Homebrew 包，本仓库不覆盖该构建，只在 [docs/05-decrypt.md](docs/05-decrypt.md) 里给出轮廓。

## 上游

- [unfairplay](https://github.com/DrWhax/unfairplay) —— 主机侧 FairPlay 解密与 enrollment model 恢复（MIT）。
- [apple-auth](https://github.com/apple-auth/apple-auth) —— provisioning / anisette / GrandSlam / Store 与 TestFlight 客户端（MIT）。本文档对应 `v0.1.3`；Mac 会话需要的本地补丁在 [docs/03-install.md](docs/03-install.md) 与 [docs/08-environment.md](docs/08-environment.md) 里描述。
- [ipatool](https://github.com/majd/ipatool) —— App Store 获取与下载。

本仓库不分发任何上游二进制。

## 状态

`docs/` 里每条事实自带一行「最后验证」，写明所用 macOS、客户端与上游版本。文档会静默腐化，日期让腐化可见。当前覆盖的版本见 [docs/07-troubleshooting.md](docs/07-troubleshooting.md)。

## 许可

MIT —— 见 [LICENSE](LICENSE)。
