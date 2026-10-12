# macOS 正式分发准备

当前公开测试包可以下载和使用，但仍是临时签名版本。若希望陌生用户安装时获得更顺畅、更可信的体验，需要使用 Apple Developer ID 签名并完成 Apple 公证。

## 需要项目维护者提供

- 有效的 Apple Developer Program 会员资格。
- 安装在发布 Mac 钥匙串中的 `Developer ID Application` 证书及私钥。
- Apple Developer Team ID。
- 用于 `notarytool` 的 App Store Connect API Key，或已经保存到钥匙串的公证凭据。

这些账号资料、私钥和 API Key 不应提交到 GitHub，也不应写入应用源码。

## 推荐发布流程

1. 在干净的 Apple Silicon Mac 上生成 Release 构建。
2. 使用 Developer ID 对 `.app` 内所有可执行文件和应用本体签名，启用 Hardened Runtime 和可信时间戳。
3. 运行 `codesign --verify --deep --strict --verbose=2` 验证签名。
4. 用 `ditto` 创建提交公证用的 ZIP。
5. 通过 `xcrun notarytool submit ... --wait` 提交 Apple 公证。
6. 对 `.app` 执行 `xcrun stapler staple`，再次验证，再生成最终下载 ZIP。
7. 在一台从未安装过本应用的 Mac 上下载、解压并启动，验证 Gatekeeper、辅助功能授权和划词。
8. 上传新的 GitHub Release，并在发布说明中明确标注“Developer ID signed and notarized”。

## 本地核验命令

```bash
security find-identity -v -p codesigning
codesign --verify --deep --strict --verbose=2 "/path/to/Learn English Anytime.app"
spctl --assess --type execute --verbose=4 "/path/to/Learn English Anytime.app"
xcrun stapler validate "/path/to/Learn English Anytime.app"
```

## 发布门槛

- 不把 Apple 凭据或模型 API Key 打进安装包。
- 不覆盖现有稳定 Release；新版本使用新的语义化版本号。
- 真实验证 Safari、Chrome、Word 和至少一个 Electron 应用。
- 确认升级后仍能正确识别辅助功能权限；如签名身份或 Bundle ID 发生变化，应在发布说明中解释可能需要重新授权。

