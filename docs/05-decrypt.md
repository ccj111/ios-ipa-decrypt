# 05 · 解密：一次 root，之后只看 selector

## 5.1 credential 与 token 是两套东西

| | token（TF 会话） | credential（FairPlay） |
| --- | --- | --- |
| 给什么 | 下载权 | 解密权 |
| 绑定对象 | 账号 + 设备身份 + 时间 | SINF 的 `user`+`key`（selector） |
| 寿命 | 几天 | 与 enrollment 绑定，长期 |
| 换渠道是否失效 | 是 | 否 |

所以“会话过期”与“解不开”是两件无关的事：会话过期只会让 `/v1/catalog` 返 401，不会影响已到手的包能不能解。

## 5.2 model 的作用域是 enrollment，不是应用

enrollment model 来自这台 Mac 的 `fpsd`：

```
/private/var/db/fpsd/SC Info     drwxr-x--- _fpsd:_fpsd
```

- 就算在 `admin` 组也读不到；`sudo` 是唯一入口 → **第一次恢复 model 必须 root**；
- 恢复后 model 落在 `~/.unfairplay-model/*.bin`（约 4 KB），**之后解密不需要 root**；
- model 匹配的是 enrollment 里的 selector，所以任意一个 selector 匹配的**已装** iOS 应用都能用来恢复；恢复完，同 selector 的所有包都能解。

## 5.3 两个必须知道的行为

**① `setup --app` 与目标包必须是同一个应用。**
恢复 model 时，工具会拿该 app 的 `SC_Info/<exe>.sinf` 去匹配目标包成员，对不上就是：

```
IPA member not found: .../SC_Info/<exe>.sinf
```

正确姿势：**只用 `--app` 建 model，另跑 `decrypt` 解目标包**，不要指望一条命令同时干两件事。

**② 包里有目录条目时要先重打包。**
Go 的 `zip.Writer.Create()` 遇到以 `/` 结尾的成员名直接报 `zip: write to directory`，而很多下载器会保留目录条目。去掉目录条目与 FairPlay 无关（SINF 签的是 Mach-O 代码签名，不是 zip 布局），可安全重打包：

```
ditto -x -k in.ipa /tmp/x && (cd /tmp/x && zip -qry -X -D out.ipa Payload META-INF)
```

## 5.4 调用形状

上游 CLI 的语义（版本相关，命令名以 `--help` 为准）：

```
unfairplay setup   --app "/Applications/<X>.app" --model-dir "$MODEL_DIR"   # 首次，需 root
unfairplay decrypt --input enc.ipa --output dec.ipa --model "$MODEL_DIR"    # 每次，不需 root
```

`unfairplay` 的输出结构、日志字段与 `cryptid` 清零点见 [06-verify.md](06-verify.md)；构建方式（C++/Go 两条路）属于上游文档，此处不复制。

## 5.5 解密之后

- **输出是确定的**：同输入、同 model → 同 sha256。跨机器比较时注意容器层可能因时间戳不同而不同，比较 `Payload/` 内文件。
- **清 `cryptid` 必然破坏代码签名**（CodeDirectory 里记的是加密前哈希），安装前必须重签：

  ```
  codesign -f -s - --entitlements ent.plist Payload/<X>.app
  ```

  重签会连带把 SINF 的许可绑定关系搞乱，所以重签后的包用于**静态分析/本地调试**，不要指望它还原“原始商店签名”。
- **对外分享前**去掉账号数据（`iTunesMetadata` 里的 Apple ID、`SC_Info` 许可、`testerEmail`）。工具侧一般有 `--strip-account-data` 一类开关。
- **没有 enrollment 就没有主机侧解密**：Intel Mac、或从未登录 Mac App Store 的机器走不通；剩下的路是用越狱设备取 16 字节 credential（`credential.bin`），再在主机侧解。

## 5.6 失败签名的含义

| 症状 | 含义 | 可调余地 |
| --- | --- | --- |
| `SINF authentication failed` | 该 SINF 与 model 的 selector 不匹配 | **无**；换验证对象或换 credential |
| `IPA member not found` | `setup --app` 与被解包不是同一应用 | 有：分开执行 |
| `zip: write to directory` | 目录条目 | 有：重打包 |
| `permission denied` on `fpsd` | 建 model 没 root | 有：首次 `sudo` |

---

最后验证：2026-11-19 · macOS 15.6.1 (arm64) · unfairplay 主线 · model 4 KB 形态
