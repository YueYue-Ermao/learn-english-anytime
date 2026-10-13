# Learn English Anytime

> 中文名：随时学英语

<p align="center">
  <img src="assets/social-preview.png" alt="Learn English Anytime：选中英文即可查看翻译和发音，也可获得自然的英文表达建议" width="100%">
</p>

<p align="center">
  <strong>不离开当前页面，随时查词、听发音、学会地道表达。</strong><br>
  Translate, pronounce, and express naturally—without leaving what you’re doing.
</p>

<p align="center">
  <a href="https://github.com/YueYue-Ermao/learn-english-anytime/releases/latest"><strong>⬇️ 下载最新版</strong></a>
  ·
  <a href="docs/USAGE.md">使用说明</a>
  ·
  <a href="https://github.com/YueYue-Ermao/learn-english-anytime/issues/new/choose">反馈问题</a>
</p>

为希望持续学习英语的职场人和学生打造。当你使用电脑时遇到不懂的英文单词或句子，无需复制内容或跳转到其他网页，选中文字即可查看翻译并收听发音；当你知道中文意思、却不确定怎样用自然地道的英语表达时，也可以立即获得结合场景的英文建议。让英语学习自然地发生在工作和学习过程中。

Built for professionals and students who want to keep improving their English while they work and study. Select any unfamiliar English word or sentence to see its meaning and hear its pronunciation—without copying it or leaving the page or app you are using. When you know what you want to say in Chinese but need a natural English expression, get immediate, context-aware suggestions in the same place.

这是一款 macOS / Apple Silicon 应用。v0.7.1 在精美划词浮窗中增加了离线相关近义词；未命中词典的短语和短句继续自动使用 Apple 设备端翻译，单词本、好句收藏夹和语法问答保持可用。

> 当前为公开测试版：支持 macOS 14+ 和 Apple Silicon（M1/M2/M3/M4）。安装包使用临时签名，尚未完成 Apple Developer ID 公证。

## 三个核心体验

| 随时理解 | 自然表达 | 持续积累 |
|---|---|---|
| 在网页、Office 和常见应用中选中英文，直接查看释义与发音 | 输入中文意思和使用场景，获得更符合真实语境的英文表达 | 把单词、词组和好句收藏到本地学习中心，随时搜索和复习 |

基础查词、收藏和支持系统版本上的 Apple 本机翻译无需项目 AI 服务。地道化表达和语法问答是用户主动触发的可选能力。

## 快速开始

如果只想使用应用，请打开 [Releases](https://github.com/YueYue-Ermao/learn-english-anytime/releases/latest)，下载最新的 `Context-English-Assistant-*-arm64.zip`。解压后将应用放入“应用程序”，右键选择“打开”，再按引导开启辅助功能权限。

- [完整使用说明](docs/USAGE.md)
- [技术架构](docs/TECHNICAL_ARCHITECTURE.md)
- [离线词典构建](docs/DICTIONARY.md)
- [隐私说明](docs/PRIVACY.md)
- [正式签名与公证准备](docs/DISTRIBUTION.md)
- [Apple / Android 跨平台路线图](docs/CROSS_PLATFORM_ROADMAP.md)
- [v0.7.1 发布说明](docs/releases/v0.7.1.md)

从源码构建时请注意：包含近义词数据的完整离线词典约 131 MiB，超过 GitHub 单文件限制，因此不提交到源码仓库；Release 安装包已经内置，开发者也可以按照词典文档重建。

## 已实现

- 普通 macOS 应用：启动显示学习中心，并出现在 Dock 与 `Command + Tab` 中。
- 菜单栏组件继续在后台提供全局划词、暂停和快捷入口。
- 双击启动时显示学习中心；权限诊断可从主窗口或菜单栏打开，并显示当前实际运行副本的路径。
- Accessibility 权限检测和系统设置入口。
- 通过 `AXUIElement` 读取焦点元素的选中文字。
- 尝试通过 `AXSelectedTextRange` 和 `AXBoundsForRange` 获取选区坐标。
- 鼠标松开后 300ms 宽限期。
- 新的鼠标、右键、滚动或键盘事件取消待触发浮窗。
- 智能、完整、轻提示、仅手动和禁用五种核心策略模型。
- 全局暂停 1/2/4 小时，并将绝对截止时间保存在 `UserDefaults`。
- 非激活 `NSPanel` 轻提示和完整查询卡片。
- `AVSpeechSynthesizer` 英文朗读。
- ECDICT 离线 SQLite 词典：770,611 个英文词条及 14 万余条汉英反向映射，无需联网查询。
- Princeton WordNet 3.1 离线近义词：覆盖 11 万余个英文词条，结果按常见程度排序，不调用模型 API。
- 基于 ECDICT `exchange` 字段的 56,718 个词形映射，并支持大小写、标点和连字符规范化。
- 简单中英文词汇优先查询本地词典。
- macOS 15 及以上通过 Apple Translation 在设备上翻译中英文短语、句子和所在句；首次使用需联网下载系统语言包，下载后翻译在设备端完成。
- 未命中词典的短语和短句会自动使用 Apple 本机翻译；单个未知词和长段落仍保留手动入口。
- 本机翻译结果明确标注“未调用 API、无 API 费用”。
- GPT 等模型服务改为可选的“AI 地道化”；只有用户主动点击后才请求服务。
- 查询结果内存缓存、词典来源标记和未收录回退提示。
- “选中即展示”持久化开关：可从浮窗或菜单栏开启/关闭。
- 本地收藏 SQLite 数据库，位于 `~/Library/Application Support/Context English Assistant/user.sqlite3`。
- 学习中心“我的单词本”，只展示单词和词组，支持搜索、朗读、复制和取消收藏。
- 学习中心“好句收藏夹”，支持多个主题收藏夹、新建/删除收藏夹、搜索、手动添加、移动句子、朗读、复制和取消收藏。
- 收藏数据库 v2 会把已有句子和场景表达迁移到“默认好句”，不丢失旧数据。
- 学习中心“语法问答”，支持输入完整句子、具体语法问题和可选场景，并以结构化区域展示回答、规则、替代形式和例句。
- 中文、英文和中英混合输入识别。
- 尽可能从 Accessibility 文本范围或 Web Text Marker 提取选中项所在句；失败时明确降级为仅选中文字。
- 划词浮窗分别提供“本机翻译（免费）”与“AI 地道化（可选）”入口，并支持加载、取消和错误状态。
- “这样表达”窗口支持内容、自然语言场景、首选表达、3 个备选、中文释义、朗读、复制和收藏。
- 可选 AI 服务设置窗口；同一服务支持地道化表达和语法问答，API 密钥不进入桌面应用。
- 可独立运行的语言学习服务，提供上下文翻译与 `/v1/grammar/questions`，支持本地模拟和 OpenAI Responses API Structured Outputs。
- PauseManager 与 TriggerPolicy 核心检查；安装完整 Xcode 后同时运行框架化单元测试。

## 当前原型边界

- 离线中英双向查词、本机句子翻译、收藏、单词表和触发开关无需服务端即可使用。
- Apple 本机句子翻译需要 macOS 15 或更高版本；首次使用某语言组合时，系统可能请求联网下载翻译资源，但不会产生模型 API 费用。
- “AI 地道化”“这样表达”和“语法问答”仍需配置模型服务，但完全可选；应用包内不包含 API 密钥，也不会直接调用供应商密钥。
- 当前提供可运行的本机开发服务和服务端实现，但生产上线仍需要模型 API 账号、费用授权与部署环境。
- 浏览器或应用未暴露完整可访问文本时，只能翻译选中文字；UI 会明确标注，不会假装已经结合所在句。
- 不包含截图、OCR、剪贴板监控或自动上传。
- Safari、Chrome 和 Office 对 Accessibility 的暴露方式不同，必须真机逐项验证。
- 多显示器上下排列的坐标转换还需要真实设备校准。

## v0.7.1 使用入口

- 应用主窗口 → `我的单词本`、`好句收藏夹`、`语法问答`。
- 主窗口 → `好句收藏夹` → `+ 新建`：建立产品经理面试、工作汇报、日常口语等主题收藏夹。
- 主窗口 → `语法问答`：输入句子和具体问题；只有点击“提问”后才请求 AI 服务。
- 菜单栏 → `选中即展示`：开启后所有有效选区直接展示完整浮窗；关闭后只显示 `A` 轻提示。
- 浮窗 → `☆ 收藏`：单词进入单词本，句子或场景表达进入“默认好句”，之后可在学习中心移动到其他收藏夹。
- 查询英文单词时，释义卡片下方会显示最多 8 个“相关近义词”；近义词并非在所有语境中都可直接替换。
- 选中未命中词典的短语或短句：自动使用 Apple 设备端翻译，不请求模型服务；需要时仍可点击 `重新本机翻译`。
- 浮窗 → `AI 地道化（可选）`：只有此时才请求已配置的 AI 服务，并可能产生 API 费用。
- 菜单栏 → `这样表达…`：输入内容和场景，获得首选表达与 3 个备选。
- 主窗口或菜单栏 → `AI 服务设置…`：可选填写部署后的 `/v1/translations/contextual` 地址；语法问答自动使用同一主机的 `/v1/grammar/questions`。

## 本机模型服务联调

无 API 密钥时可以启动模拟服务，验证完整交互：

```bash
CONTEXT_TRANSLATION_MOCK=1 python3 services/contextual-translation/server.py
```

随后在应用的“AI 服务设置”中点击“使用本机开发服务”并保存。模拟结果仅用于联调，不代表正式翻译或语法回答质量；不配置也不影响本机翻译和收藏。

使用真实模型时，API Key 只放在服务端环境变量：

```bash
OPENAI_API_KEY="your-server-side-key" \
OPENAI_MODEL="gpt-6-astra" \
python3 services/contextual-translation/server.py
```

生产部署前还需增加 HTTPS、鉴权、限流、成本上限和脱敏监控。

## 本机构建要求

推荐安装与当前 macOS 匹配的完整 Xcode，然后运行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./scripts/check.sh
./scripts/build-app.sh
```

构建后的应用和可传输 ZIP 位于：

```text
dist/Context English Assistant.app
dist/Context-English-Assistant-v0.7.1-arm64.zip
```

## 首次安装与授权

1. 退出并删除旧的应用副本，避免同时存在 `Context English Assistant.app` 和 Finder 自动命名的 `Context English Assistant 2.app`。
2. 解压 ZIP，只把其中唯一的应用移动到“应用程序”文件夹。
3. 从“应用程序”文件夹双击启动。v0.7.1 会直接显示“英语学习中心”主窗口。
4. 点击“打开辅助功能设置”，在以下位置开启当前这个应用：

```text
系统设置 → 隐私与安全性 → 辅助功能
```

5. 从学习中心点击“划词与权限…”，在诊断窗口点击“重新检测权限”，状态应变为绿色；再点击“显示测试浮窗”。
6. 关闭学习中心不会退出应用，菜单栏划词仍会运行；点击 Dock 图标或菜单栏“打开学习中心…”即可恢复窗口。

如果系统设置里已有旧版本条目，请先用减号移除旧条目，再用加号选择 `/Applications/Context English Assistant.app`。不要在授权后移动或重命名应用。是否需要 Input Monitoring 将根据全局事件监听在目标 macOS 版本上的实际表现决定，首版遵循最少权限原则。

## “双击没反应”的排查

- v0.1.0 没有主窗口，只在菜单栏运行，容易被误认为没有启动；v0.1.1 起已修复这一交互问题。
- 如果双击时打开的是已运行的进程，v0.1.1 起也会重新显示诊断窗口。
- v0.1.2 会在权限由关闭变为开启时自动重建全局监听器，并在窗口和菜单中展示最近一次监听/选区读取结果。
- v0.1.2 增加网页 `AXTextMarkerRange`、鼠标位置元素和父级元素回溯，以提高 Safari、Chrome 等网页选区的读取成功率。
- v0.1.3 会在 Chrome、Codex 等 Chromium/Electron 应用激活时开启它们的辅助功能树，并在树尚未就绪时自动重试读取两次。
- v0.2.0 内置完整 ECDICT SQLite 词库和词形索引；普通查词不再依赖原型硬编码数据。
- v0.3.0 增加直接展示开关、收藏/单词表、中英文检测、所在句提取、双向翻译入口、“这样表达”窗口和可配置模型服务。
- v0.4.0 增加本地汉英反向索引与词典/模型混合路由；普通中英文词汇不调用模型，句子和场景化表达按需调用。
- v0.5.0 增加 Apple 本机中英句子翻译；本机翻译与 AI 地道化拆分为两个明确入口，普通句子不再要求配置 API。
- v0.6.0 增加普通 Mac 主窗口、单词本、多好句收藏夹和结构化语法问答；菜单栏划词继续保留。
- v0.7.0 统一浮窗与学习中心视觉，并让短语和短句自动走 Apple 本机翻译。
- v0.7.1 为英文查词增加离线相关近义词，并兼容不含近义词表的旧数据库。
- 确认只保留一个应用副本，并以诊断窗口展示的实际路径为准授权。
- 如果看不到窗口，可先从“活动监视器”退出所有 `Context English Assistant` 进程，再从“应用程序”文件夹重开。
- 本开发包使用临时签名，macOS 首次拦截时请右键应用选择“打开”；正式发布需使用 Apple Developer ID 签名并完成公证。

## 当前机器的已知工具链问题

在创建原型时，机器只有 Xcode Command Line Tools，没有完整 Xcode。项目可使用 `--disable-sandbox` 完成 Swift 构建和自包含核心检查，但 Command Line Tools 不包含 XCTest/Swift Testing 运行模块，因此框架化单元测试会被检查脚本跳过。安装完整、匹配当前 macOS 的 Xcode 并切换 `xcode-select` 后，检查脚本会额外执行正式测试。

当前机器的 Swift 编译器与默认 macOS 26.2 SDK 存在补丁版本差异，构建脚本会在仅安装 Command Line Tools 时自动使用兼容的 macOS 15.4 SDK；应用最低运行版本仍为 macOS 14。

## 离线词典数据

- 数据来源：[ECDICT](https://github.com/skywind3000/ECDICT)，仓库标注为 MIT License。
- 近义词来源：[Princeton WordNet 3.1](https://wordnet.princeton.edu/)，按其许可随应用分发派生的词间关系。
- 应用包内附 `ThirdPartyLicenses/ECDICT-LICENSE.txt` 和数据版本通知。
- 没有打包 `lemma.en.txt`：该文件头的授权表述与仓库根许可证存在差异。词形索引只从 `ecdict.csv` 的 `exchange` 字段生成。
- 正式商业发布前仍应对聚合词典数据来源进行法律审查；如需更强的权威性，可替换为商业授权词典，查询接口无需改动。

重新生成离线数据库（会同时构建汉英反向索引）：

```bash
python3 scripts/build-dictionary.py /path/to/ecdict.csv Resources/App/ecdict.sqlite3 \
  --wordnet-dict /path/to/wordnet/dict
```

为已有数据库补建或刷新汉英反向索引：

```bash
python3 scripts/add-chinese-index.py Resources/App/ecdict.sqlite3
```

## 项目结构

```text
Sources/ContextEnglishAssistantApp/   macOS 应用、全局划词与学习中心
Sources/ContextEnglishCore/           触发、上下文和路由核心逻辑
Tests/                                Swift 单元测试
services/contextual-translation/      可选 AI 地道化与语法服务
scripts/                              构建、检查与词典生成脚本
docs/                                 使用、架构、隐私与发布文档
```

## 参与贡献与许可

欢迎提交 issue 和 pull request。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。项目代码采用 [MIT License](LICENSE)；ECDICT 数据遵循其上游许可与本仓库的第三方通知。
