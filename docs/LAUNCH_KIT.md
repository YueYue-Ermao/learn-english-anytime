# Learn English Anytime 推广素材包

这份文档用于 GitHub、Product Hunt、小红书、即刻、V2EX、LinkedIn 和 X 等渠道。发布前应使用真实产品截图或录屏，不要把概念主视觉描述为真实 UI 截图。

## 核心定位

### 中文一句话

不离开当前页面，随时查词、听发音、学会地道表达。

### English tagline

Learn English without leaving your workflow.

### 中文短介绍

Learn English Anytime（随时学英语）是一款面向职场人和学生的 macOS 英语学习工具。在网页、Office 和常见应用里选中英文，就能直接查看释义和发音；当你知道中文意思、却不知道怎样自然地用英语表达时，也可以结合场景获得建议。单词、词组和好句都能收藏到本地学习中心。

### English short description

Learn English Anytime is a native macOS assistant for professionals and students. Select unfamiliar English in the app you are already using to see its meaning and hear its pronunciation. When you know what you want to say in Chinese, get context-aware English suggestions and save useful words and sentences for later.

## 核心差异

- 不需要把内容复制到词典网站再查询。
- 普通单词优先使用离线词典，不让每次查词都变成模型调用。
- 支持结合能可靠取得的所在句解释当前词义。
- 本机翻译与 AI 地道化是两个明确入口，用户能够理解费用和隐私边界。
- 单词、词组和句子可以持续沉淀到本地学习中心。

## 30 秒演示脚本

| 时间 | 画面 | 字幕/旁白 |
|---|---|---|
| 0–4 秒 | 在网页中选中一个英文词，原本准备复制 | 看不懂英文时，你还在复制、打开词典、粘贴吗？ |
| 4–10 秒 | 选中后出现释义和发音入口 | 现在，选中即可查看释义并听发音。 |
| 10–17 秒 | 选中句子并展示本机翻译 | 句子也能直接翻译，不用离开当前页面。 |
| 17–24 秒 | 输入中文意图和“产品经理面试”场景 | 想用英文表达时，还可以结合具体场景获得更自然的说法。 |
| 24–28 秒 | 收藏单词与好句，打开学习中心 | 有用的内容会进入你的单词本和好句收藏夹。 |
| 28–30 秒 | 项目主视觉与下载链接 | Learn English Anytime。让英语学习发生在工作和学习中。 |

## Product Hunt 素材

### Name

Learn English Anytime

### Tagline（60 字符以内）

Learn English without leaving your workflow

### Short description

A native macOS assistant that translates selected text, speaks unfamiliar words, suggests natural English for real situations, and saves what you learn—all without interrupting your workflow.

### Maker comment 草稿

I built Learn English Anytime after noticing how often English learning breaks the flow of real work. Looking up one word usually means copying it, switching to a dictionary, pasting it, and then receiving a definition that may not fit the sentence. Expressing a Chinese idea naturally in a product interview or workplace conversation is even harder.

This macOS app brings those steps into the place where you are already working. Basic word lookup is offline-first, sentence translation can use Apple’s on-device translation on supported macOS versions, and AI is reserved for optional context-aware expression and grammar help. I would especially value feedback on installation, cross-app selection, and the learning-center workflow.

## 中文社区发布草稿

### 标题

我做了一个不用复制粘贴、选中英文就能查询的 Mac 应用

### 正文

工作中阅读英文网页、文档或者 AI 回复时，我经常只是不懂其中一个词或一句话，但传统流程要先复制，再打开词典，再粘贴查询。词典给出的中文有时也和当前工作场景不匹配。

所以我做了 Learn English Anytime（随时学英语）：

- 在网页、Office 和常见应用中选中英文，直接查看释义和发音；
- 句子可以使用 Apple 本机翻译；
- 想把中文自然地表达成英文时，可以补充“产品经理面试”等场景；
- 有用的单词和句子可以收藏到本地学习中心。

目前是 macOS Apple Silicon 公开测试版，基础查词和收藏不需要 AI 服务。欢迎体验，也很希望知道它在哪些应用或真实场景中还不够好用。

项目与下载：<https://github.com/YueYue-Ermao/learn-english-anytime>

## 发布前检查

- 使用真实 Mac 完成一次全新安装验证。
- 确认 Safari、Chrome、Word 和至少一个 Electron 应用的划词体验。
- 准备一段真实录屏，不使用概念图冒充产品截图。
- README、Release 和发布帖使用相同名称与下载地址。
- 明确当前安装包是否已经 Developer ID 签名和 Apple 公证。
- 如果 AI 服务尚未公开部署，推广内容必须说明它是可选功能。
- 发布当天及时回答安装、权限和隐私问题。
- 把高频问题更新到 `docs/USAGE.md`，把真实需求转为 GitHub Issue。
