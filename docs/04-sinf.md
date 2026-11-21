# 04 · SINF 与 selector：解密唯一认的东西

## 4.1 为什么 TF 包里没有 `.sinf`

较新的 TestFlight 包，`SC_Info/` 里只有：

```
SC_Info/<exe>.supp  <exe>.v4.supp  <exe>.v5.supf  <exe>.supx  Manifest.plist
```

`Manifest.plist` 的 `SinfPaths` 指向 `SC_Info/<exe>.sinf`，但**那个文件不在包里**：SINF 由服务端在 install 时下发。App Store 包则相反，`.sinf` 随包附带。

所以：

- TF 服务端包 → 从 install 元数据的 `sinf` 字段取出，回插到 `Payload/<exe>.app/SC_Info/<exe>.sinf`；
- TF 本机 Wrapper 包、App Store 包 → 包内自带，跳过这一步。

## 4.2 SINF 的结构与 selector

`sinf` 是嵌套的 big-endian atom：

```
sinf
└── schi
    ├── user   (u32)     ← selector 的一半
    ├── key    (u32)     ← selector 的另一半
    ├── righ   (rights 键值对：veID / plat / aver / tran / sing / song / tool / medi / mode / hi32)
    ├── iviv   (16 B IV)
    └── priv   (440 或 448 B)
```

**selector 定义（唯一的判据）**：

```
selector = sha256( be32(user) ‖ be32(key) )
```

注意：

- 与 Apple ID 无关、与渠道无关、与 bundleId 无关；
- `priv` 的长度有两种形态（440 / 448），解析要按长度分支；
- 密钥文件还有版本差异：`SUPF` 有 ver 3 / 5（v5 省掉 20 字节 SHA-1），`SUPP` 有 ver 1 / 4。**不要假设固定偏移**——旧脚本在空文件上还会直接 `IndexError`。

可核对的最小实现：[`examples/selector.py`](../examples/selector.py)（12 行）。

## 4.3 回插 SINF

TF 服务端包到手后，把 1056 B 的 SINF 写成 zip 成员：

```
Payload/<App>.app/SC_Info/<App>.sinf
```

要点：

- zip 成员名必须与 `appFileName` 对齐（`SC_Info` 里的名字由主可执行名决定，写错就是 `IPA member not found`）；
- 用 `zip -X -D`：`-X` 去掉额外字段、`-D` 不写目录条目（Go 的 zip 读不了以 `/` 结尾的成员名）；
- 注入只改容器，不改 payload。

示例：[`examples/sinf-inject.py`](../examples/sinf-inject.py)。

## 4.4 一个容易误判的现象

注入 SINF 后，同一个包的**容器 sha256 会变**（成员时间戳、目录条目顺序），但 `Payload/` 内文件逐字节相同。所以验证要用：

```
unzip -p out.ipa Payload/<exe> | shasum -a 256
```

而不是比较整个 ipa 的 sha。反过来，`unfairplay decrypt` 的输出是确定的：同输入、同 model、同 sha256。

## 4.5 selector 什么时候会不同

- 同一账号的 TF 与 App Store 包**可能**共用同一 selector，也可能各自不同；
- 同一账号也可能不止两把 credential——Apple 侧没有这个承诺；
- 判断方法只有比对：解出两个包的 selector 看是否相等。相等 → 一份 model 通吃；不等 → 各自需要匹配的 credential/model。

---

最后验证：2026-11-19 · macOS 15.6.1 · TestFlight 4.4.1
