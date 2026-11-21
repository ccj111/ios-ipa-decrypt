# 02 · 会话：它本来就在磁盘上

## 2.1 结论

TestFlight 客户端每次启动都会 `POST https://testflight.apple.com/v1/session/authenticate`，并把**响应体**写进自己的 CFNetwork URL 缓存。因此会话不需要“换”，只需要“读”：

- 不需要 GSA / SRP 登录；
- 不需要 root；
- 不需要安装根证书、不碰系统代理。

只要客户端处于登录态（能列出 beta），磁盘上就已经有一份可用会话。

## 2.2 缓存位置与表结构

```
~/Library/Containers/com.apple.TestFlight/Data/Library/Caches/com.apple.TestFlight/Cache.db
```

CFNetwork 的标准三张表：`cfurl_cache_response`（`request_key` / `time_stamp`）、`cfurl_cache_receiver_data`（`receiver_data`）、`cfurl_cache_blob_data`。容器不在默认路径时（不同系统版本、沙箱迁移）用环境变量或参数指定。

一条只读查询即可（完整版见 [`examples/session.sql`](../examples/session.sql)）：

```sql
SELECT CAST(d.receiver_data AS TEXT)
FROM cfurl_cache_response r
JOIN cfurl_cache_receiver_data d ON d.entry_ID = r.entry_ID
WHERE r.request_key LIKE '%/v1/session/authenticate%'
ORDER BY r.time_stamp DESC LIMIT 1;
```

`receiver_data` 有两种形态：**内联 JSON**，或 **`fsCachedData/<name>` 的文件名**。后者需要按名回读——这是第一个坑。

## 2.3 三个坑

| 坑 | 现象 | 判据与处理 |
| --- | --- | --- |
| **`dsid` 不在这个响应里** | 拿到 session 也签不出请求 | 会话头的签名要数值 `dsid`；它在 `MZInit.woa/wa/initiateSession` 一类响应的 `DSPersonID` 里，常以文件名形式落在 `fsCachedData/` |
| **`X-Apple-AMD-M` 必须非空** | `Incomplete saved TestFlight session` | 任意 anisette provider 都能给一个 `X-Apple-I-MD-M`，它就是 Store 侧的 AMD-M |
| **storefront 要用客户端自己的** | 401 / code 102 | 别用 App Store 账号的 storefront；客户端缓存里 `metricsBase.storeFrontHeader` 才是真值（形如 `143441-19`，注意有的写法带 `,13` 后缀，照抄缓存） |

配套的两个身份量：

- `udid`：40 位十六进制，只用做 `hardware20` 的会话校验。生成一次即固定复用，换 udid 不影响已下载的包。
- `X-Apple-Device-Model` / `X-Apple-TA-Device`：`sysctl -n hw.model`。UA 必须与客户端一致，见 [08-environment.md](08-environment.md)。

## 2.4 生命周期

- 会话寿命几天；过期后 `/v1/catalog` 返 401。
- 刷新方式：**打开一次客户端**（最好再进一次 beta 详情页，让 `MZInit` 也发生），缓存随之更新，重跑提取即可。
- 缓存文件不需要 root；`sqlite3 -readonly` 打开不会改动客户端状态。

## 2.5 会话 JSON 长什么样

给 apple-auth 之类工具用时需要一个合成对象，字段语义固定：

| 字段 | 来源 |
| --- | --- |
| `accountId` / `sessionId` | `/v1/session/authenticate` 响应 |
| `dsid` | `MZInit` 的 `DSPersonID` |
| `udid` / `deviceVendorId` | 自生成，保持稳定 |
| `headers["X-Apple-AMD-M"]` | anisette provider |
| `headers["X-Apple-Store-Front"]` | 缓存里的 `storeFrontHeader` |

这个文件等同登录态：**不要入库、不要贴 issue、不要外传**。

## 2.6 失败签名

| 症状 | 含义 |
| --- | --- |
| `缓存里没有 /v1/session/authenticate 响应` | 客户端没登录过，或缓存被清 |
| `缓存里没有 DSPersonID` | `MZInit` 还没发生 → 打开一次 beta 详情页 |
| 拿到了会话但 401 | 会话过期，或 storefront/UA 不对 |

---

最后验证：2026-11-19 · macOS 15.6.1 · TestFlight 4.4.1
