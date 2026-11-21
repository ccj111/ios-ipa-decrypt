# 08 · 环境事实与版本漂移

## 8.1 fake-ip DNS 会伪装成 TLS 故障

现象：

```
HTTPS request failed (curl 35): TLS connect error: error:0A000126:SSL routines::unexpected eof while reading
```

根因：Clash / Surge 的 fake-ip 模式把 `testflight.apple.com` 解析到 `198.18.0.0/15`（RFC 2544 保留段），TLS 必然断。`testflight.apple.com` 最容易中招，`init.itunes.apple.com` 之类的商店域名通常正常。

诊断：

```
dig +short testflight.apple.com @223.5.5.5          # 拿真实 Akamai IP
curl -s -o /dev/null -w '%{http_code} tls=%{ssl_verify_result}\n' \
     --resolve testflight.apple.com:443:<IP> https://testflight.apple.com/v1/session/authenticate
# 期望 405（GET 不被允许），tls=0 表示证书校验通过
```

处置：给客户端加 `host:443:ip` 形式的 resolve 覆盖（等价 `curl --resolve`）。**走系统代理通常无效**，因为拦截发生在 DNS 层。

判断依据：报 `wrong version number` / `unexpected eof` 是 DNS/代理层；报证书错误才是 MITM。

## 8.2 UA 是最容易误判的一条

`code 102 — The credentials for this app are invalid.` 的真实原因通常不是凭据，而是 UA：

```
MacAppStore/3.0 TestFlight/<ver> (Macintosh; OS X <osver>; <build>) AppleWebKit/<...> AMS/1 (dt:1)
```

- 这串**直接从客户端自己的配置里取**（Mac Store 侧叫 `user_agent` 的字段），不要照抄本文档、也不要“写得更合理”；
- 看起来更现代的 UA（只写 `TestFlight/4.4.1 (macOS …)`）会被拒；
- UA 与版本一起漂移，所以本文不把它当常量。

## 8.3 其它必填头

`X-Apple-Device-Model` / `X-Apple-TA-Device`（`sysctl -n hw.model`）、`X-Apple-TestFlight-iOS: 0`、`X-Apple-Rosetta-Available: 0`；`X-Apple-AMD-M` 与 `X-Apple-Store-Front` 由 Store 会话补。

链路上“伪造”的只有**设备身份**（机型、udid、UA）；账号、席位、协议参数都是真的——这是为什么席位缺失时无解。

## 8.4 数据格式坑

**plist 布尔往返**：编码/解码把 `<true/>` 变成整数 `0/1`，校验方要求 `is_boolean()`，于是报 `Invalid saved Store cookie`——而认证其实已经成功。诊断技巧：把待校验的 JSON 落盘，看 `"host_only": 0` 而不是 `false`。

**Go zip 不接受目录条目**：`zip: write to directory`。用 `zip -X -D` 重打包，与 FairPlay 无关。

**输出文件不覆盖**：上游工具普遍 fail closed（`output already exists`），重跑前先删目标文件。

## 8.5 权限与身份

- `/private/var/db/fpsd/SC Info`：`drwxr-x--- _fpsd:_fpsd`，`sudo` 是唯一入口；仅首次建 model 需要。
- model `~/.unfairplay-model/*.bin`：约 4 KB，等同解密凭据，600 权限。
- 会话、`account-session.plist`、`mac-store.plist`、`tf-store-context.json`、`adi.pb`/`identity.json`：全部等同登录态。

## 8.6 版本漂移清单（每次升级先怀疑这些）

| 项 | 会怎么变 |
| --- | --- |
| `kbSync212`、`hardware20`、`dpInfo88` | 传输参数名/语义随系统版本调整 |
| UA 与 API 版本 | 见 8.2 |
| 加密面 | iOS 17+ 起不少包只加密头一页（`cryptsize 4096`），`.v4.supp` 仍带全量页密钥 |
| SINF `priv` | 440 / 448 两种长度 |
| `SUPF` / `SUPP` | ver 3 / 5、ver 1 / 4，偏移不同 |
| 缓存位置 | 容器路径可能随沙箱策略调整 |

因此本文档的每条结论都写“最后验证”。**日期是文档的编译期检查**：一条事实超过两次大版本没复核，就当它已失效。

## 8.7 卫生清单（发布前逐项过）

- 仓库里不应出现：`*.ipa`、`*.bin`、`tf-session.json`、`install.json`、`catalog.json`、`*.log`、任何真实账号值。
- 文档与图里不应出现：`accountId`、`dsid`、`sessionId`、完整 selector、`testerEmail`、真实 bundleId / 团队 ID / 应用名。
- 示例代码里的常量一律占位：`user=0 key=0`、`com.example.app`、`<40-hex>`、`<storefront>`。
- 对外分享 IPA：先 strip 账号数据；分享截图前先看状态栏与登录邮箱。

---

最后验证：2026-11-19 · macOS 15.6.1 · TestFlight 4.4.1
