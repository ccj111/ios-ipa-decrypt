# 07 · 排障：报错字面 ≠ 根因

这类链路最贵的成本不是技术，是**报错指向错误的方向**。下表按“字面 → 真实根因”排，每条都实测过。

## 7.1 会话与认证

| 字面 | 真实根因 | 判据 | 处置 |
| --- | --- | --- | --- |
| `/v1/catalog` 返 401 | 会话过期（几天寿命） | 客户端里还能列出 beta | 重启客户端刷新缓存，重取会话 |
| `credentials for this app are invalid`（code 102） | **User-Agent 与客户端不一致** | 换回客户端自己的 UA 立刻成功 | 取客户端的 `user_agent` 原值 |
| `Incomplete saved TestFlight session` | `headers.X-Apple-AMD-M` 为空 | 看会话 JSON 的 headers | 补 anisette 的 `X-Apple-I-MD-M` |
| `Invalid saved Store cookie` | plist 布尔往返成了 `0/1` 整数 | 落盘待校验 JSON，看 `"host_only": 0` | 回读时强制转 bool |
| `Store operation failed`（无细节） | CLI 吞了异常 | 非 2xx 响应体被丢弃 | 把响应体落盘再读 |

## 7.2 下载

| 字面 | 真实根因 | 判据 | 处置 |
| --- | --- | --- | --- |
| `TestFlight returned incomplete install metadata` | `dpInfo` 为 `null`（Mac 会话常态） | 元数据里 `url` 非空 | 放宽校验，或直接 `curl` 直链 |
| CDN 返 403 | URL 上多拼了 `?token=` | 对比 install 给的原始 `url` | 只用原样 URL |
| `unzip: start of central directory not found` / `file` 报 `data` | `pre-thinned` 的 LZFSE transport 包装态 | 头 4 字节不是 `PK\x03\x04` | 改读本机 Wrapper；或 `--unwrap-transport`（要 `dpInfo`，常没有） |
| 下载到一半停在固定大小 | 直链过期 / 限速 | `packageSize` 对不上 | 重取 install 元数据 |

## 7.3 SINF 与解密

| 字面 | 真实根因 | 判据 | 处置 |
| --- | --- | --- | --- |
| `IPA 里没有可用 SINF` | TF 包只有 `.supp/.supf` | 列 `SC_Info/` 有无 `.sinf` | 从 install 元数据回插 |
| `IPA member not found: …/SC_Info/<exe>.sinf` | `setup --app` 与 `--ipa` 不是同一应用 | 比对 `appFileName` 与 `--app` 的 exe | 拆成两步：`setup` 建 model，`decrypt` 解包 |
| `SINF authentication failed` | 该 SINF 的 selector 与 model 不匹配 | 比两个包的 selector | **无参数可调**；换验证对象或走设备路线 |
| `zip: write to directory` | 包内有目录条目，Go zip 不接受 | `unzip -l` 看 `/` 结尾成员 | `zip -X -D` 去掉目录条目后重打包 |
| `error: unsupported cryptid` / 解密后 cryptid 仍为 1 | 解密没真正落到该 Mach-O | 逐二进制看 cryptid | 确认该二进制在包内路径被覆盖（framework 也要看） |
| `permission denied` on `/private/var/db/fpsd` | 建 model 没 root | `id -u` | 仅首次 `sudo`；之后 model 可读即可 |

## 7.4 环境类（细节见 [08](08-environment.md)）

| 字面 | 真实根因 |
| --- | --- |
| `curl 35: unexpected eof while reading` / `wrong version number` | Clash/Surge 的 fake-ip 把域名解析进 `198.18.0.0/15` |
| `unzip` 报 central directory not found 但文件大小正常 | transport 包装态，不是坏文件 |
| 脚本报 `X: 未绑定的变量` | `set -u` 下 `local a=$b` 多赋值/中文字符紧邻变量 |
| 工具报 `output already exists` | 上游普遍 fail closed，不覆盖已有输出 |

## 7.5 产出一个可公开的诊断包

贴 issue 时只需要这些（都不含账号信息）：

```
macOS 版本 / 芯片 / 是否 arm64
客户端与上游工具版本
失败在哪一步（①②③④⑤⑥⑦）
错误字面（原样）+ 该步的输入类型（不是输入内容）
cryptid 表 + macho_total/encrypted_total
selector 前 8 位（可选）
```

**不要贴**：`accountId`、`sessionId`、`dsid`、完整 selector、`testerEmail`、`install.json` 原文、会话 JSON、model `*.bin`。

## 7.6 当前版本覆盖

| 项 | 版本 |
| --- | --- |
| macOS | 15.6.1（arm64） |
| TestFlight 客户端 | 4.4.1 |
| apple-auth | v0.1.3 + 本地四处改动（[03](03-install.md) §3.6） |
| unfairplay | 主线（model 4 KB 形态） |
| 样本 | 三个：TF 服务端 / TF 本机 ×2 |

超出这些版本的报错，先怀疑版本漂移（[08](08-environment.md) §8.6），再怀疑结论。

---

最后验证：2026-11-19
