# 03 · install 元数据：直链、SINF、以及两个陷阱

## 3.1 两个请求

```
POST /v1/catalog   → 该账号可见的 beta 列表
POST /v1/install   → 单个 build 的下载元数据
```

**catalog 里没有 `bundleId`**：只有 `appId` / `name` / `developerName` / `appCategories` / `etag`。bundleId 要等 `install` 才出现。所以“catalog 里按 bundleId 过滤”这种写法一定会失配——按名字或 `appId` 定位，再用 install 校验。

## 3.2 install 里有什么

| 字段 | 用途 |
| --- | --- |
| `framework.bundleId` / `shortVersion` / `bundleVersion` | 目标身份 |
| `appFileName` | 包内主可执行名（回插 SINF 时要用） |
| `url` / `packages.full.url` | CDN 直链，**自带 `accessKey`** |
| `packageSize` | 下载长度校验 |
| `sinf` / `packages.full.sinf` | SINF（plist 字符串，1056 B 那种），见 [04-sinf.md](04-sinf.md) |
| `iTunesMetadata.variantId` | 瘦身目标（形如 `1:iPhone12,1:17.4`） |
| `expirationDate` | 会话/许可的到期提示 |
| `testerEmail` / `testerType` / `cohortId` | 账号痕迹，**分享前要去掉** |
| `dpInfo` | Mac 会话常为 `null`，见 3.4 |
| `token`（JWT） | 只与会话相关，不要拼进下载 URL |
| `profiles/<TeamID>.<bundleId>` | 描述文件 |

## 3.3 下载规则

```
curl -L --fail -o app.ipa "$(jq -r .url install.json)"
```

- **只**用元数据给的 `url`。自己拼 `?token=` / `&dsid=` 会让 CDN 返 403。
- 校验头 4 字节：`PK\x03\x04` 才是 zip。
- `file` 报 `data`、`unzip` 报 `start of central directory not found` → 这是 `pre-thinned` 的 **LZFSE transport 包装态**，不是坏包。

## 3.4 两个陷阱

**① `dpInfo` 为 `null`。**
Mac 会话换来的 install 元数据里它常常是 null，而上游 apple-auth 原本要求 `url` 与 `dpInfo` 同时非空，于是报 `TestFlight returned incomplete install metadata`。`dpInfo` 只在 `--tf-download` 的 transport 解包时需要（那个路径同时要 `hardware20` 与 `dpInfo88`），**CDN 直链根本不需要它**。两种处置：

- 放宽校验：只要求 `url` 非空（改 `src/testflight/protocol.cpp` 的 `require(...)`）；
- 或干脆不用 `--tf-download`，自己 `curl` 直链。

**② 非 2xx 响应体被丢弃。**
上游在非 2xx 时只抛一句笼统错误，真正的 `{"code":102,"message":"The credentials for this app are invalid."}` 看不到。把响应体落盘再读；那条 102 的真实含义是 **UA 不匹配**，不是凭据错（见 [08-environment.md](08-environment.md)）。

## 3.5 需要的请求头（Mac 客户端路径）

| 头 | 值 |
| --- | --- |
| `User-Agent` | 与客户端完全一致的那串，**不能自己编** |
| `X-Apple-Device-Model` | `sysctl -n hw.model` |
| `X-Apple-TA-Device` | 同上 |
| `X-Apple-TestFlight-iOS` | `0`（走 Mac 认证路径） |
| `X-Apple-Rosetta-Available` | `0` |
| `X-Apple-AMD-M` / `X-Apple-Store-Front` | 由 Store 会话补 |

签名头形如 `X-Session-Id` + `X-Session-Digest(session, id, dsid)`；参数名（`kbSync212`、`hardware20`、`dpInfo88`）会随系统版本漂移，**不要硬编码死**。

## 3.6 上游构建与本地补丁

`apple-auth` 需要 `APPLE_AUTH_WITH_TESTFLIGHT=ON` 才会编出 `apple-auth-testflight`（默认 OFF，只出 `apple-auth-store`——这是最容易被误判成“功能不存在”的一处）。实测在 `v0.1.3` 上需要四处本地改动：

| # | 位置 | 症状 | 改什么 |
| --- | --- | --- | --- |
| 1 | `src/client/store.cpp` (`StoreSession::from_plist`) | `Invalid saved Store cookie`（认证其实已成功） | plist 布尔往返变成 `0/1` 整数，回读时强制转 bool；`expires` 浮点转整数 |
| 2 | `src/client/transport.cpp` | `curl 35: unexpected eof` | 支持 `host:443:ip` 的 `CURLOPT_RESOLVE` 覆盖（fake-ip 场景） |
| 3 | `src/testflight/protocol.cpp` | 401 但看不到原因 | 非 2xx 时把响应体落盘 |
| 4 | `examples/*.cpp` | 只有 `Store operation failed` | CLI 捕获并打印 `code` / `what()` |

外加 3.4 的 `dpInfo` 放宽。这些改动只影响诊断能力与 Mac 会话适配，不改变协议本身。

---

最后验证：2026-11-19 · macOS 15.6.1 · apple-auth v0.1.3 · TestFlight 4.4.1
