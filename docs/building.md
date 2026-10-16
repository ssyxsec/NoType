# 从源码构建

需要 macOS 14+、Xcode Command Line Tools、Swift 5.9+、Python 3 和 Git。若本机未安装编译工具，先按 Apple 提示安装 Command Line Tools。

```sh
git clone https://github.com/ssyxsec/NoType.git
cd NoType
swift test
./scripts/build.sh
```

输出位于 `dist/NoType.app`。脚本会从图标源代码生成 icns，构建 release 并使用本机固定开发证书签名。首次构建在 `~/Library/Application Support/NoType/Signing/` 创建私有签名钥匙串；不添加系统信任根、不修改 TCC。

关闭正在运行的 NoType 后执行：

```sh
./scripts/install.sh
```

这会安装到 `/Applications/NoType.app` 并启动。自行构建使用自己的签名身份，替换其他签名的版本后可能需重新授予辅助功能权限。Whisper 与 Codex CLI 均为独立外部依赖，构建脚本不安装它们。

## 目录

- `Sources/NoType/`：录音、语音引擎适配、自动输入、快捷键和 SwiftUI / AppKit 界面。
- `Sources/NoTypeCore/`：Codex app-server 桥接、云端语音协议、历史与统计模型。
- `Tests/NoTypeCoreTests/`：协议、超时、取消、隔离、持久化、统计等测试。
- `Resources/`：Info.plist、应用图标及约 5 秒合成英文示例。
- `scripts/`：构建、安装、图标生成、Whisper 安装和本地签名。

## 发布

```sh
ditto -c -k --sequesterRsrc --keepParent dist/NoType.app dist/NoType-macOS-arm64.zip
shasum -a 256 dist/NoType-macOS-arm64.zip
```

GitHub Release 附安装包和 SHA256；不要把构建缓存、应用支持目录、凭证或签名私钥提交到 Git。当前 Release 为 Apple Silicon 测试构建，未使用 Developer ID 签名或 Apple 公证。正式面向广泛用户分发前，应完成相应签名、公证和发布验证。
