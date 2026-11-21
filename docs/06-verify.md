# 06 · 校验：三个数字，不看退出码

## 6.1 判据只有三个

| # | 判据 | 期望 |
| --- | --- | --- |
| ① | 逐 Mach-O 的 `LC_ENCRYPTION_INFO(_64).cryptid` | 全部 `0` |
| ② | 加密二进制清单 | 空（`encrypted []`） |
| ③ | 逐页明文校验（工具报告的 `PlaintextVerified` 一类字段） | `true`，且 `EncryptedImages` / `DecryptedPages` 数量对得上 |

退出码为 0 不等于解开了：一个没找到任何 Mach-O 的“成功”也会是 0。**计数是防线**：先确认扫到了几个二进制，再确认几个是 0。

## 6.2 自己动手看 cryptid

两个 load command 的编号只差一个字面：`LC_ENCRYPTION_INFO = 0x21`（32 位头），`LC_ENCRYPTION_INFO_64 = 0x2C`（64 位头，实际包里绝大多数命中这个）：

```
mach_header_64.cryptid  ← LC_ENCRYPTION_INFO_64 (0x2C) 的第三个 u32
fat binary             → 每个切片各读一次
无该 load command      → 未加密（cryptid 视为 0）
```

最小实现：[`examples/cryptid.py`](../examples/cryptid.py)。

## 6.3 渠道怎么判

`codesign -dvvv` 的 Authority 是免费的渠道指示器：

| Authority | 渠道 |
| --- | --- |
| `TestFlight Beta Distribution` | TestFlight beta build |
| `Apple Distribution: <Developer>` | App Store 正式版 |
| 自签 / ad-hoc | 已被改过 |

另外 `embedded.mobileprovision` 的 `beta-reports-active` 也是线索，但 TF 包**通常没有** `embedded.mobileprovision`（描述文件单独下发），所以“缺 profile”不能当作异常。

## 6.4 解密后的两个必然结果

1. `signature_verified: false` —— 清 `cryptid` 破坏了 CodeDirectory 哈希。这不是失败，是预期。
2. SINF 仍在 `SC_Info/` 里（除非显式 strip），SINF 的 selector 依然可读——可以用来交叉核对“这个包本来该用哪把 credential”。

## 6.5 一个版本陷阱：只加密头一页

iOS 17+ 起不少包只加密第一页（`cryptsize 4096`），而 `.v4.supp` 仍带全量页密钥表。也就是说：

- `cryptid` 为 1 但实际加密面很小 → 解密很快；
- 反过来，不能用“包大小变化量”推断加密面；
- 判定永远以 `cryptid` 与明文校验为准，不要凭系统版本号推断。

## 6.6 报告该有什么字段

一份可公开贴出的校验报告只需要这些（都不含账号信息）：

```
bundle_id, version, build, platforms
macho_total, encrypted_total, cryptid 表
verdict: DECRYPTED | FAIRPLAY_ENCRYPTED
codesign authority 首项
ipa 大小（可选）
```

不要包含：`accountId`、`dsid`、`sessionId`、完整 selector、`testerEmail`。

---

最后验证：2026-11-19 · macOS 15.6.1 · 三个样本均 `cryptid=[0]` / `encrypted []`
