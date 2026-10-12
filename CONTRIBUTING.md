# 参与贡献

感谢你改进 Learn English Anytime（随时学英语）。提交代码前，请先创建 issue 描述问题或功能目标，避免重复实现。

## 本地开发

环境要求：

- Apple Silicon Mac
- macOS 14 或更高版本
- Xcode 16 或与当前 macOS 匹配的更新版本
- Python 3（仅用于可选 AI 服务和词典构建脚本）

运行基础检查：

```bash
swift build
swift test
python3 services/contextual-translation/server.py --self-test
```

完整的词典集成检查需要先按 [离线词典构建说明](docs/DICTIONARY.md) 生成 `Resources/App/ecdict.sqlite3`，然后运行：

```bash
./scripts/check.sh
```

## Pull Request 要求

- 每个 PR 聚焦一个明确问题。
- UI 或触发行为变化需要说明在 Safari、Chrome、Office 或 Electron 应用中的验证范围。
- 不得提交 API Key、访问令牌、用户收藏数据库或带有个人内容的日志。
- 新增联网行为时必须在 UI 和隐私文档中说明发送的数据、触发时机和服务端用途。
- 影响数据库结构时必须提供向后兼容迁移，并验证旧数据不会丢失。

## 代码与提交

- Swift 代码保持现有 AppKit 与 Swift Package 结构。
- 用户可见文案优先使用清晰、非技术化的中文。
- 提交信息使用简短的祈使句，例如 `Add sentence collection export`。

提交即表示你同意以仓库的 MIT License 发布你的贡献。
