---
name: ios-ipa-decrypt
description: Explain and drive non-jailbroken iOS IPA acquisition and FairPlay decryption on an Apple Silicon Mac — TestFlight (session read from the client's own URL cache), App Store (ipatool / apple-auth), or the local Wrapper of an already-installed build, converging on one selector-based decryption and a three-signal verification. Use when asked how an IPA is decrypted on macOS, why a build is iPhone-only or refuses to install, why a binary still reports cryptid=1, why SINF authentication fails, or how two packages relate via their selector. This skill ships reasoning and decision rules, not a ready-to-run pipeline.
---

# 非越狱 IPA 获取与解密（决策层）

这份 skill 只给**判据与决策**，不给可直接执行的整链脚本。实现细节见 `docs/`，可核对的小例子见 `examples/`（只读参考，不要当工具跑）。

## 0. 三条硬判据（记这三条，其余都是细节）

1. `selector = sha256(be32(sinf.schi.user) ‖ be32(sinf.schi.key))`
   解密权绑 selector，不绑 Apple ID、不绑渠道。同 selector → 同一份 model 通吃。
2. TF 会话只需**读**：TestFlight 客户端把会话写在自己的 CFNetwork 缓存里；不需要 GSA、不需要 root、不需要 MITM。
3. `cryptid` 是唯一有效的加密状态判据。版本号、渠道、包大小都只是线索。

## 1. 先判可行，再谈步骤

| 条件 | 结论 | 动作 |
| --- | --- | --- |
| 目标 build 是 iPhone-only（`UIDeviceFamily [1]`），但账号已加入该 beta | 可下 | 走服务端：会话 → catalog → install → CDN |
| 同一 build 已装到本机 Mac | 可拿 | 直接读 `/Applications/<X>.app/Wrapper/<Inner>.app`，包内自带 SINF |
| 目标 build 装不上且账号没有该 beta 席位 | **停手** | 席位不可绕，明确告知；不要尝试登录别的账号或猜 bundle |
| App Store 公开版，账号能 `acquire` | 可下 | ipatool / apple-auth-appstore，包内自带 SINF |
| Intel Mac，或本机从未登录 Mac App Store | **停手** | 无 `fpsd` enrollment，建不出 model；只剩越狱设备取 credential |
| 包的 selector 与本机 model 不匹配 | **停手/换源** | `SINF authentication failed`，无参数可调；换一个 selector 匹配的已装应用当验证对象，或改用设备路线 |

判断顺序：**席位 → 平台 → 本机是否已有该 build → selector**。顺序颠倒会浪费最多时间在“会话为什么 401”上，而问题其实在第一步。

## 2. 七个动作（每步只做一件事）

| # | 动作 | 输入 | 输出 | 判据 |
| --- | --- | --- | --- | --- |
| ① | 从 `Cache.db` 读会话 | 本机 TF 客户端缓存 | `sessionId` / `accountId` / `dsid` | 见 `docs/02-session.md` |
| ② | catalog | 会话 | `appId` 列表 | 401 即会话过期，不是权限问题 |
| ③ | install 元数据 | 会话 + bundle | `url` / `sinf` / `packageSize` / `expirationDate` | `url` 自带 `accessKey`，**不要**补 `?token=` |
| ④ | 下载并判形态 | `url` | 加密 `.ipa` 或非 zip | 头 4 字节 `PK\x03\x04` 才是 zip；否则是 transport 包装态 |
| ⑤ | SINF 就位 | install 元数据里的 `sinf` | 回插后的包 | TF 服务端包内**没有** `.sinf` |
| ⑥ | 解密 | 加密包 + model | 明文包 | 只认 selector 匹配 |
| ⑦ | 校验 | 明文包 | 三个信号 | 见 `docs/06-verify.md` |

第 ④ 步是唯一需要“换路”的地方：直链不是 zip 时，改读本机 Wrapper 比研究 transport 解包快得多。

## 3. 失败签名：报错字面 ≠ 根因

| 字面 | 真实根因 | 判据 |
| --- | --- | --- |
| `/v1/catalog` 401 | 会话过期（几天寿命） | 重启一次客户端刷新缓存即恢复 |
| `credentials for this app are invalid` (102) | **UA 与客户端不一致**，不是密码错 | 对照 `docs/08-environment.md` 的 UA 表 |
| `Incomplete saved TestFlight session` | `X-Apple-AMD-M` 为空 | 会话 JSON 的 headers 缺字段 |
| `TestFlight returned incomplete install metadata` | `dpInfo` 为 `null`（Mac 会话常态） | 只需 `url`；放宽校验或用直链下载 |
| CDN 403 | URL 上多拼了 `?token=` | 用 install 给的 `url` 原样 |
| `unzip: start of central directory not found` | `pre-thinned` transport 包装态 | 改走本机 Wrapper |
| `IPA 里没有可用 SINF` | TF 包只有 `.supp/.supf` | 从 install 元数据回插 |
| `SINF authentication failed` | selector 不匹配 | 换验证对象；**没有可调参数** |
| `zip: write to directory` | 包里有目录条目，Go zip 不接受 | 去掉目录条目后重打包，与 FairPlay 无关 |
| `permission denied` on `fpsd/SC Info` | 建 model 没 root | 仅首次需要 root |

完整表（含环境类）见 `docs/07-troubleshooting.md`。

## 4. 停手条件（遇到就直说，别硬试）

- 账号没有该 beta 的访问权。
- 机器无 Apple Silicon enrollment。
- 目标包 selector 与本机所有 model 都不匹配，且没有可用的越狱设备。
- 目标 build 是 transport 包装态，且本机也未安装同一 build。

这四条都属于**前提缺失**，继续尝试只会产生误导性报错。

## 5. 卫生（做与不做都要说清楚）

- 会话 JSON、`account-session.plist`、`mac-store.plist`、`install.json`（含 `DSPersonID` / `testerEmail`）、model `*.bin`：全部等同登录态，600 权限、不入库、不外传。
- 对外分享 IPA 时先去掉账号数据（`--strip-account-data` 一类选项），不要连 `iTunesMetadata` 一起发。
- 不要用别人的账号、不要伪造席位——这两件事都不能靠参数解决。

## 6. 文档索引

- 取源矩阵：`docs/01-sources.md`
- 会话：`docs/02-session.md` ｜ 元数据：`docs/03-install.md` ｜ SINF 与 selector：`docs/04-sinf.md`
- 解密：`docs/05-decrypt.md` ｜ 校验：`docs/06-verify.md`
- 排障：`docs/07-troubleshooting.md` ｜ 环境与漂移：`docs/08-environment.md`
- 图：`docs/flow.svg` ｜ 示例：`examples/`（`session.sql`、`selector.py`、`cryptid.py`、`sinf-inject.py`、`app-to-ipa.sh`）
