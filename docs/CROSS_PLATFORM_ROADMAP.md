# Apple / Android 跨平台路线图

## 目标

让用户在 Mac、iPhone/iPad 和 Android 上使用一致的查词、设备端翻译、朗读、收藏、场景表达和语法学习能力，同时遵循各平台允许的系统入口，不通过高权限方案伪造完全一致的交互。

## 平台能力差异

| 能力 | macOS | iOS / iPadOS | Android |
|---|---|---|---|
| 跨应用选中文字 | Accessibility 读取选区，可在鼠标松开后触发 | Action/Share Extension；只有宿主应用明确提供内容时可取得选区 | `ACTION_PROCESS_TEXT` 可出现在系统文本选择菜单 |
| 结果呈现 | 非激活浮窗，靠近选区 | 扩展页或应用内卡片 | 小型 Activity / Compose 卡片；必要时返回处理结果 |
| 设备端翻译 | Apple Translation（macOS 15+） | Apple Translation（iOS 18+） | Google ML Kit on-device Translation（Android API 23+） |
| 发音 | `AVSpeechSynthesizer` | `AVSpeechSynthesizer` | Android `TextToSpeech` |
| 本地收藏 | SQLite | App Group + SQLite | Room / SQLite |
| 后台自动监听 | 可在授权后实现 | 系统不允许任意后台全局选区监听 | 不作为默认方案；优先使用系统文本操作入口 |

Apple 明确说明，iOS Action Extension 只有在宿主应用提供内容时才能收到选区，因此 iPhone/iPad 不能完全复制 Mac 的“松开鼠标自动浮窗”。Android 首版使用系统 `ACTION_PROCESS_TEXT`，不默认申请 Accessibility 或全局悬浮窗权限。

## 共享边界

不会为了“代码看起来统一”立即重写已经可用的 macOS 客户端。三端共享以下稳定契约：

- `DetectedLanguage`、查询类型、收藏类型和翻译结果的数据结构；
- ECDICT 数据生成流程与 SQLite 表结构；
- 自动翻译策略的行为测试用例；
- 收藏导出/导入 JSON 格式；
- 可选 AI 服务的 `/v1/translations/contextual` 与 `/v1/grammar/questions` 接口；
- 产品文案、隐私边界和费用标识。

界面和系统入口保持原生实现：macOS/iOS 使用 Swift，Android 使用 Kotlin + Jetpack Compose。这样可以获得可靠的系统集成，也不会让现有 Mac 版本为尚未开发的移动端承担重写风险。

## 迭代顺序

### v0.7 — macOS 体验基线（当前）

- 统一浮窗与学习中心视觉。
- 短语/短句自动使用 Apple 设备端翻译。
- 固化翻译路由、收藏结构和隐私说明。

### v0.8 — 可移植核心

- 定义跨平台 JSON 数据契约和收藏导出/导入。
- 把路由测试样例整理成平台无关测试夹具。
- 为本机翻译、词典、朗读和收藏定义统一能力接口。
- 补充真实 Safari、Chrome、Word、Codex 回归清单。

### v0.9 — iPhone / iPad MVP

- SwiftUI 主应用：查词、输入翻译、单词本和好句收藏夹。
- Action/Share Extension：从支持的宿主应用接收选中文字。
- Apple Translation 与系统语音。
- App Group 共享主应用和扩展的收藏数据库。

### v1.0 — Android MVP

- Kotlin + Jetpack Compose 主应用。
- `ACTION_PROCESS_TEXT`：用户选中文字后从系统菜单选择“随时学英语”。
- ML Kit 中英设备端翻译；首次按需下载语言模型。
- Room 收藏库与 Android TextToSpeech。
- 接入同一套可选 AI 服务，保持基础翻译不依赖模型 API。

## 不采用的捷径

- 不把网页套壳当作完整移动端，因为它无法可靠接入系统选词、设备端翻译和本地收藏。
- 不默认使用 Android Accessibility Service 读取所有屏幕内容；它权限过高，也会增加隐私和商店审核风险。
- 不在三个客户端中放入供应商 API Key。
- 不承诺 iOS 上不存在的“任意应用后台自动监听”。

## 完成标准

- 三端基础查词、普通翻译、朗读和收藏无需项目 AI 服务。
- 各平台都清楚展示语言包下载、设备端处理和可选 AI 的边界。
- 同一收藏导出文件可以被其他平台导入。
- 自动化测试覆盖路由、语言判断、收藏迁移和 API 响应解析。
- 每个平台有独立版本、安装包和发布说明，不用一次大提交覆盖全部客户端。

## 官方能力依据

- Apple Translation：<https://developer.apple.com/documentation/translation/translationsession>
- Apple Action Extension：<https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Action.html>
- Android `ACTION_PROCESS_TEXT`：<https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT>
- ML Kit Android 设备端翻译：<https://developers.google.com/ml-kit/language/translation/android>
