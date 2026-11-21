# 01 · 取源矩阵：三条路，一条尾巴

先决定“包从哪来”，再谈解密。渠道只影响**加密包怎么到手**和**SINF 从哪来**；到手之后完全一致：

```
加密包 →（缺 SINF 时回插）→ selector 比对 → 解密 → 校验
```

## 1.1 矩阵

| | TestFlight · 服务端 | TestFlight · 本机 Wrapper | App Store |
| --- | --- | --- | --- |
| 前提 | 本机 TestFlight 客户端已登录 | 该 build 已装到本机 Mac | 账号能 `acquire` 该 app |
| 覆盖范围 | 该 beta 的全部 build，**含 iPhone-only** | 只有 Mac 支持的 build | 公开版 |
| 需要会话 | 是，但从缓存直取（无 root / 无证书 / 无代理） | 否 | 是（commerce 会话） |
| 网络 | 需要（CDN） | 不需要 | 需要 |
| 到手形态 | 加密 `.ipa`（`pre-thinned` 时不是 zip） | 加密 `.app`，自己 `ditto` + `zip` | 加密 `.ipa` |
| SINF 来源 | **install 元数据下发，需回插** | 包内自带 | 包内自带 |
| 包完整度 | 按 `variantId` 瘦身（单架构） | 瘦身包的原样 | 通常 universal，更完整 |

## 1.2 决策顺序（顺序错了会白查一天）

```
① 账号有没有这个 beta 的席位 / 有没有这个 app 的获取权
② 目标平台能不能装到本机（UIDeviceFamily 是否含 Mac）
③ 本机是否已经有同一 build（有 → 直接读 Wrapper，省掉整个下载）
④ 包的 selector 与本机 model 是否一致
```

- ①② 不成立 → 换账号或换渠道，**不要**去调网络参数。
- ③ 成立 → 本机 Wrapper 是**退路优先**：它自带完整 `SC_Info`，绕开 transport 包装态。
- ④ 不成立 → 见 [05-decrypt.md](05-decrypt.md) 的 selector 一节。

## 1.3 各路的取包形状

**TestFlight 服务端**（详见 [02](02-session.md) / [03](03-install.md) / [04](04-sinf.md)）：

```
Cache.db → sessionId/accountId/dsid → /v1/catalog → /v1/install → url → curl → 加密 ipa
```

**本机 Wrapper**：TestFlight 装到 Mac 上的应用是“外层 app 包内层 app”的结构：

```
/Applications/<X>.app/Wrapper/<Inner>.app/{Inner, SC_Info/, Frameworks/, Info.plist}
```

内层即完整加密 bundle，`ditto` 进 `Payload/` 后 `zip -X -D` 即可（示例：[`examples/app-to-ipa.sh`](../examples/app-to-ipa.sh)）。不需要会话、不需要网络、不需要 root。

**App Store**：`ipatool auth login` → `search`/`lookup` → `acquire`（免费 app 直接获取，付费需先购买）→ `download`。或 `apple-auth-appstore` 的 `catalog` / `metadata` / `acquire-free` / `download` 子命令。拿不到 TF beta build、拿不到已下架 app、拿不到别人账号的付费内容。

## 1.4 实测样本（已脱敏）

| 样本 | 渠道 | 加密 | 解密后 | cryptid |
| --- | --- | --- | --- | --- |
| A | TF 服务端 | 260,225,568 B | 173,156,713 B | `[0]` |
| B | TF 本机 | 44,845,042 B | 45,057,814 B | `[0]` |
| C | TF 本机 | 56,113,054 B | 56,147,264 B | `[0]` |

三个包 selector 相同。注意 A 的量级：加密包比明文大 87 MB，因为 FairPlay 段在解密前不可压缩。

## 1.5 常见误判

| 误判 | 事实 |
| --- | --- |
| “App Store 包是解密好的” | 不是，`cryptid` 照样为 1 |
| “TF 包更全” | 相反：TF 按设备变体瘦身，App Store 通常更完整 |
| “能装到 Mac 才能下” | 客户端装不上不影响服务端下载，两者是不同策略 |
| “同一个 Apple ID 就一定能解” | credential 绑 selector，不绑账号 |

---

最后验证：2026-11-19 · macOS 15.6.1 (arm64) · TestFlight 4.4.1 · apple-auth v0.1.3
