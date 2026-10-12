# 技术架构

## 1. 产品边界

Context English Assistant 是原生 macOS 应用，目标是在不要求复制粘贴的情况下，为跨应用选区提供查词、发音、翻译、收藏和语法学习。基础能力本地优先；只有地道化表达和开放式语法解释需要可选模型服务。

当前发布目标：

- macOS 14+
- Apple Silicon arm64
- 原生 Swift、AppKit 与 Swift Package Manager
- 本地 SQLite 数据
- macOS 15+ 可选 Apple Translation
- 可选 Python AI 网关

## 2. 总体结构

```text
Safari / Chrome / Office / Electron / 其他应用
                    │
       全局鼠标与键盘事件 + Accessibility
                    │
            SelectionCoordinator
          ┌─────────┴──────────┐
          │                    │
   TriggerPolicy         TextContext
          │                    │
          └─────────┬──────────┘
                    │
             LookupPanelController
        ┌───────────┼──────────────┐
        │           │              │
 SQLiteDictionary  Apple       可选 AI 服务
  ECDICT/汉英索引  Translation  contextual/grammar
        │           │              │
        └───────────┴──────┬───────┘
                           │
                 FavoritesRepository
                     user.sqlite3
```

学习中心和菜单栏组件共享同一套设置、收藏库、语音服务和 AI 服务配置。

## 3. 全局选区与低干扰触发

`GlobalEventMonitor` 监听鼠标松开、滚动、右键和键盘事件。鼠标松开后等待 300ms，再由 `AccessibilitySelectionReader` 查询前台应用的选区。任何新的用户输入都会取消待触发任务。

选区读取按能力逐级回退：

1. 焦点 Accessibility 元素的 `AXSelectedText`。
2. `AXSelectedTextRange` 与 `AXBoundsForRange` 获取选区坐标。
3. Web 内容的 Text Marker Range。
4. 鼠标位置元素及父级回溯。
5. Chromium/Electron 应用可访问性树激活和短暂重试。

`TriggerPolicy` 过滤空白、过长内容和不适合自动提示的交互。默认“轻提示”只显示一个非激活 `NSPanel`；用户可切换为选中即展示，也可全局暂停 1/2/4 小时。暂停截止时间写入 `UserDefaults`，应用重启后仍有效。

## 4. 查询与翻译路由

路由原则不是“所有内容都调用模型”，而是按任务选最便宜且足够可靠的引擎：

| 输入/意图 | 默认引擎 | 是否联网 |
|---|---|---|
| 英文单词、词形 | ECDICT SQLite + 词形索引 | 否 |
| 常见中文词语 | 本地汉英反向索引 | 否 |
| 一般中英文句子 | Apple Translation（macOS 15+） | 首次下载语言包 |
| 场景化地道表达 | 用户配置的 AI 服务 | 是，主动触发 |
| 开放式语法解释 | 用户配置的 AI 服务 | 是，主动触发 |

`LookupRoutingPolicy` 根据语言、长度、是否为句子和本地命中状态选择入口。模型能力在 UI 中以独立按钮呈现，避免基础查询意外产生费用。

## 5. 所在句与上下文

`TextContext` 负责规范化选区并识别最小必要上下文。能访问周围文本时，应用提取包含选区的句子；不能访问时只保留选中文字并显示降级提示。客户端不采集完整文档、URL、窗口标题或应用历史。

上下文翻译请求只包含：

- 用户选中的文本；
- 能够可靠提取到的最小所在句；
- 用户主动输入的场景；
- 源语言和目标语言。

## 6. 本地数据

### 6.1 词典

`SQLiteDictionary` 读取只读的 `Resources/App/ecdict.sqlite3`：

- ECDICT 主词条；
- `exchange` 构建的词形映射；
- 从中文释义生成的汉英反向索引；
- 常见职场词汇校准。

数据库约 108 MiB，超过 GitHub 100 MiB 单文件限制，因此不提交到源码仓库。Release 安装包内包含完整数据库；开发者也可按 [词典构建说明](DICTIONARY.md) 重建。

### 6.2 用户收藏

`FavoritesRepository` 使用本机 SQLite：

```text
~/Library/Application Support/Context English Assistant/user.sqlite3
```

数据库 v2 区分单词/词组与句子，并支持多个句子收藏夹。迁移逻辑会把旧版句子移动到“默认好句”，不删除已有数据。

## 7. UI 组成

- `LearningCenterWindowController`：单词本、好句收藏夹、语法问答主窗口。
- `LookupPanelController`：全局划词轻提示和完整结果卡片。
- `ExpressionWindowController`：输入中文意图与场景，生成一个首选表达和三个备选。
- `SetupWindowController`：辅助功能权限诊断与测试浮窗。
- `ServiceSettingsWindowController`：配置用户自行部署的 AI 服务地址。
- `StatusBarController`：后台状态、暂停、显示策略和入口。

应用是普通 Dock 应用；关闭主窗口不会退出，菜单栏组件继续监听。

## 8. 可选 AI 服务

`services/contextual-translation/server.py` 暴露：

- `POST /v1/translations/contextual`
- `POST /v1/grammar/questions`
- `GET /healthz`

它把供应商 API Key 留在服务端，使用 OpenAI Responses API Structured Outputs，并设置 `store: false`。开发服务不提供生产级身份验证，不能直接公开暴露。

生产部署至少需要：

- HTTPS；
- 应用用户身份与短期令牌；
- 按用户和 IP 限流；
- 日/周/月成本上限；
- 超时、重试和熔断；
- 不记录正文的可观测性；
- 密钥管理与轮换。

## 9. 隐私与安全

基础查词、收藏和本机翻译不发送内容到项目服务端。AI 请求必须由用户明确点击；客户端不包含 API Key。权限遵循最小化原则，目前只要求辅助功能，不监控剪贴板，不截图，不做 OCR，也不后台上传文档。

## 10. 构建与测试

基础检查：

```bash
swift build
swift test
python3 services/contextual-translation/server.py --self-test
```

生成完整词典后可运行：

```bash
./scripts/check.sh
./scripts/build-app.sh
```

检查覆盖触发策略、上下文拆分、路由、学习中心布局、词典、收藏数据库创建和 v1→v2 迁移、服务端结构化输出以及 Release 构建。

## 11. 已知边界

- 不同应用暴露 Accessibility 文本的方式不同，需要逐应用回归。
- 目标应用不提供周围文本时，无法可靠结合完整句意。
- Apple Translation 需要 macOS 15+；macOS 14 仍可使用词典和可选 AI 服务。
- 多显示器上下排列的坐标转换仍需要更多真机验证。
- 当前 Release 为临时签名的公开测试包，正式分发应使用 Apple Developer ID 签名和公证。
