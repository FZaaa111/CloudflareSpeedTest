# CloudflareSpeedTest iOS App

在 iPhone 上测试 Cloudflare IP 的延迟与下载速度，并把结果自动写入你在 Cloudflare 托管的域名 DNS 记录。

测速核心直接复用本仓库的 Go 代码（`task/`、`utils/`），通过 [gomobile](https://pkg.go.dev/golang.org/x/mobile/cmd/gomobile) 编译为 `Cfst.xcframework`（入口见 [`../mobile/mobile.go`](../mobile/mobile.go)），界面使用 SwiftUI。

## 功能

- **测速**：TCPing / HTTPing 延迟测速 + 下载测速，参数与命令行版本一致；IP 段可选内置 IPv4（`ip.txt`）、IPv6（`ipv6.txt`）或自定义。
- **保存凭证与域名**：支持 API Token 或 Global API Key + 邮箱，凭证保存在 iOS 钥匙串；域名列表保存在本机。
- **映射到域名**：按域名列表的顺序，第 1 个域名使用第 1 快的 IP，第 2 个域名使用第 2 快的 IP，以此类推（A 记录分配 IPv4，AAAA 记录分配 IPv6）。记录不存在时自动创建，存在则更新；记录为「仅 DNS」（不开启代理）、TTL 60 秒。可开启「测速完成后自动映射」。
- **检测映射**：对每个域名检测三项：
  1. Cloudflare API 中的记录值是否为分配的 IP 且未开启代理；
  2. Cloudflare（1.1.1.1）与 Google 公共 DNS（DoH）是否已解析到该 IP；
  3. 该 IP 的 443 端口能否连通，以及连接延迟。

## 构建

环境要求：macOS + Xcode 15 或更高、Go 1.22 或更高、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
cd ios
./build-go.sh          # 安装 gomobile 并生成 Frameworks/Cfst.xcframework
xcodegen               # 根据 project.yml 生成 CFST.xcodeproj
open CFST.xcodeproj
```

在 Xcode 中选择 `CFST` target → **Signing & Capabilities**，选择你的 Team（免费 Apple ID 也可以），必要时把 Bundle Identifier 改成唯一值，然后连接 iPhone 运行即可。

> `build-go.sh` 会临时往 `go.mod` 添加 `golang.org/x/mobile` 依赖，构建结束后自动还原，不影响命令行版本。

## 导出 .ipa / 分享给朋友

```bash
cd ios
./build-ipa.sh         # 生成 dist/CFST.ipa（未签名）
```

`.ipa` 是 iOS 安装包。这里生成的是**未签名**的包，不能直接装，要用下面任一工具在安装时用**安装者自己的 Apple ID** 签名：

| 工具 | 平台 | 有效期 | 说明 |
|---|---|---|---|
| [Sideloadly](https://sideloadly.io) | Mac / Windows | 7 天（免费 Apple ID） | 最简单：数据线连接 iPhone，把 `.ipa` 拖进窗口，填 Apple ID，点 Start |
| [AltStore](https://altstore.io) | Mac / Windows + iPhone | 7 天，自动续签 | 电脑上运行 AltServer，同一 Wi-Fi 下后台续签 |
| [SideStore](https://sidestore.io) | iPhone | 7 天，手机上自己续签 | 首次需电脑配置，之后不用电脑 |
| [TrollStore](https://github.com/opa334/TrollStore) | iPhone | 永久 | 仅支持部分 iOS 版本 |

安装后都需要在 iPhone 上：打开 **设置 → 隐私与安全性 → 开发者模式**；首次打开前在 **设置 → 通用 → VPN 与设备管理** 中信任对应的 Apple ID。

有付费开发者账号时，更推荐 Xcode **Product → Archive → Distribute App → TestFlight**，朋友通过 TestFlight 安装和更新。

> 每个人应使用自己的 Cloudflare Token。本项目为 GPL-3.0 协议，公开分发安装包时请同时提供源码（附上仓库链接即可）。

## Cloudflare 凭证

推荐使用 **API Token**：Cloudflare 控制台 → 我的个人资料 → API 令牌（用户令牌），或 账户主页 → 管理账户 → 账户 API 令牌（账户令牌），两种都支持。创建令牌时可用「编辑区域 DNS」模板，权限需要：

- 区域 → Zone → 读取
- 区域 → DNS → 编辑

也可以使用 **Global API Key + 账号邮箱**（权限更大，不推荐）。

## 说明

- 映射的域名需要已经托管在该 Cloudflare 账号下。若该域名已有开启代理（橙色云朵）的同类型记录，App 会把它改为「仅 DNS」，否则解析结果是 Cloudflare 代理 IP 而不是优选 IP。
- 刚映射后公共 DNS 可能仍有缓存，DNS 解析检测失败时请等待 TTL 过期后再点「检测映射」。
- iOS 会在 App 进入后台后暂停网络任务，测速期间请保持 App 在前台（测速时会自动保持屏幕常亮）。
- 延迟测速线程数不宜过高，iPhone 上建议 100~300。
