import AppKit
import ContextEnglishCore

@MainActor
final class ExpressionWindowController: NSWindowController, NSWindowDelegate {
    var onSpeak: ((String, String) -> Void)?
    var onOpenServiceSettings: (() -> Void)?

    private let translationService: ContextualTranslationProviding
    private let favorites: FavoritesRepository
    private let inputTextView = NSTextView()
    private let scenarioField = NSTextField()
    private let resultTextView = NSTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let generateButton: ActionButton
    private let speakButton: ActionButton
    private let copyButton: ActionButton
    private let favoriteButton: ActionButton
    private var generationTask: Task<Void, Never>?
    private var currentResponse: ContextualTranslationResponse?
    private var currentFavoriteDraft: FavoriteDraft?

    init(
        translationService: ContextualTranslationProviding,
        favorites: FavoritesRepository
    ) {
        self.translationService = translationService
        self.favorites = favorites

        weak var weakController: ExpressionWindowController?
        generateButton = ActionButton(
            title: "生成地道表达",
            symbolName: "sparkles",
            style: .primary
        ) {
            weakController?.generate()
        }
        speakButton = ActionButton(title: "朗读首选", symbolName: "speaker.wave.2") {
            weakController?.speakPrimary()
        }
        copyButton = ActionButton(title: "复制首选", symbolName: "doc.on.doc") {
            weakController?.copyPrimary()
        }
        favoriteButton = ActionButton(title: "收藏首选", symbolName: "star") {
            weakController?.toggleFavorite()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "这样表达"
        window.minSize = NSSize(width: 620, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        weakController = self
        window.delegate = self
        configureContent()
        updateActionButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present(prefill: String? = nil, scenario: String? = nil) {
        if let prefill, !prefill.isEmpty {
            inputTextView.string = prefill
        }
        if let scenario, !scenario.isEmpty {
            scenarioField.stringValue = scenario
        }
        _ = NSApplication.shared.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(inputTextView)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        generationTask?.cancel()
        sender.orderOut(nil)
        return false
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = AppVisualTheme.surface.cgColor

        let eyebrow = NSTextField(labelWithString: "CONTEXT-AWARE ENGLISH")
        eyebrow.font = .systemFont(ofSize: 10.5, weight: .bold)
        eyebrow.textColor = AppVisualTheme.accent

        let title = NSTextField(labelWithString: "把你真正想表达的意思说清楚")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let intro = NSTextField(wrappingLabelWithString:
            "支持中文、英文和中英混合输入。场景越具体，表达越贴近真实工作和生活用法。"
        )
        intro.textColor = .secondaryLabelColor

        let inputLabel = NSTextField(labelWithString: "你想表达什么")
        inputLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let inputScroll = makeTextArea(
            inputTextView,
            placeholder: "例如：我会先确认需求优先级，再和研发评估实现成本。",
            editable: true
        )

        let scenarioLabel = NSTextField(labelWithString: "场景（可选）")
        scenarioLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        scenarioField.placeholderString = "例如：互联网公司，产品经理面试，口语，自信但不要夸张"

        let resultLabel = NSTextField(labelWithString: "首选表达与 3 个备选")
        resultLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let resultScroll = makeTextArea(
            resultTextView,
            placeholder: "结果会显示在这里，并且可以选择、复制、朗读和收藏。",
            editable: false
        )

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "内容只会在点击“生成地道表达”后发送到已配置的模型服务。"

        let settingsButton = ActionButton(title: "AI 服务设置…") { [weak self] in
            self?.onOpenServiceSettings?()
        }
        let closeButton = ActionButton(title: "关闭") { [weak self] in
            self?.window?.performClose(nil)
        }
        let actionRow = NSStackView(views: [
            generateButton,
            speakButton,
            copyButton,
            favoriteButton,
            settingsButton,
            closeButton
        ])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        actionRow.alignment = .centerY

        let root = NSStackView(views: [
            eyebrow,
            title,
            intro,
            inputLabel,
            inputScroll,
            scenarioLabel,
            scenarioField,
            resultLabel,
            resultScroll,
            statusLabel,
            actionRow
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            intro.widthAnchor.constraint(equalTo: root.widthAnchor),
            inputScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 105),
            scenarioField.widthAnchor.constraint(equalTo: root.widthAnchor),
            resultScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            resultScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            actionRow.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor)
        ])
    }

    private func makeTextArea(
        _ textView: NSTextView,
        placeholder: String,
        editable: Bool
    ) -> NSScrollView {
        textView.isRichText = false
        textView.isEditable = editable
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = true
        textView.backgroundColor = AppVisualTheme.raisedSurface
        textView.setAccessibilityPlaceholderValue(placeholder)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        return scroll
    }

    private func generate() {
        let input = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "请先输入想表达的内容。"
            return
        }

        generationTask?.cancel()
        currentResponse = nil
        currentFavoriteDraft = nil
        updateActionButtons()
        generateButton.isEnabled = false
        generateButton.title = "生成中…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在结合场景生成 1 个首选表达和 3 个常见备选…"

        let scenario = scenarioField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TranslationDraft(
            selectedText: input,
            language: TextLanguageDetector.detect(input),
            context: nil,
            bounds: nil,
            scenario: scenario.isEmpty ? nil : scenario
        )

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await translationService.translate(draft.request)
                try Task.checkCancellation()
                show(response, sourceInput: input, scenario: scenario)
            } catch is CancellationError {
                statusLabel.stringValue = "已取消生成。"
            } catch {
                statusLabel.textColor = .systemRed
                statusLabel.stringValue = error.localizedDescription
            }
            generateButton.isEnabled = true
            generateButton.title = "生成地道表达"
            generationTask = nil
        }
    }

    private func show(
        _ response: ContextualTranslationResponse,
        sourceInput: String,
        scenario: String
    ) {
        currentResponse = response
        var sections = [
            "首选",
            response.sentence.target,
            "",
            "中文释义",
            response.sourceLanguage == "zh-Hans" ? sourceInput : response.selectedMeaning.explanationZh
        ]
        if !response.alternatives.isEmpty {
            sections.append(contentsOf: ["", "其他常见表达"])
            for (index, alternative) in response.alternatives.prefix(3).enumerated() {
                sections.append("\(index + 1). \(alternative.target)")
                if let meaning = alternative.meaningZh, !meaning.isEmpty {
                    sections.append("   中文：\(meaning)")
                }
                sections.append("   差异：\(alternative.differenceZh)")
            }
        }
        resultTextView.string = sections.joined(separator: "\n")

        let favoriteDraft = FavoriteDraft(
            kind: .contextualExpression,
            sourceText: response.sentence.target,
            pronunciation: nil,
            meaning: response.sourceLanguage == "zh-Hans" ? sourceInput : response.selectedMeaning.explanationZh,
            note: scenario.isEmpty ? "AI 场景表达" : "AI 场景表达 · \(scenario)",
            spokenText: response.sentence.target,
            sourceLanguage: response.targetLanguage,
            minimalContextText: sourceInput
        )
        currentFavoriteDraft = favoriteDraft
        let isFavorite = favorites.contains(favoriteDraft)
        favoriteButton.title = isFavorite ? "已收藏" : "收藏首选"
        favoriteButton.image = AppVisualTheme.symbol(isFavorite ? "star.fill" : "star")
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "生成完成。结果可选择、复制、朗读或收藏。"
        updateActionButtons()
    }

    private func updateActionButtons() {
        let hasResult = currentResponse != nil
        speakButton.isEnabled = hasResult
        copyButton.isEnabled = hasResult
        favoriteButton.isEnabled = hasResult
    }

    private func speakPrimary() {
        guard let response = currentResponse else { return }
        let locale = response.targetLanguage == "zh-Hans" ? "zh-CN" : "en-US"
        onSpeak?(response.sentence.target, locale)
    }

    private func copyPrimary() {
        guard let response = currentResponse else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response.sentence.target, forType: .string)
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "已复制首选表达。"
    }

    private func toggleFavorite() {
        guard let draft = currentFavoriteDraft else { return }
        do {
            let isFavorite = try favorites.toggle(draft)
            favoriteButton.title = isFavorite ? "已收藏" : "收藏首选"
            favoriteButton.image = AppVisualTheme.symbol(isFavorite ? "star.fill" : "star")
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = isFavorite ? "已收藏首选表达。" : "已取消收藏。"
        } catch {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = error.localizedDescription
        }
    }
}
