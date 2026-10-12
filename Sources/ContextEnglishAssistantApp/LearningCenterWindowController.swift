import AppKit
import ContextEnglishCore

enum LearningCenterSection: Int {
    case words
    case sentences
    case grammar
}

@MainActor
final class LearningCenterWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onSpeak: ((String, String) -> Void)?
    var onOpenServiceSettings: (() -> Void)?
    var onOpenExpressionComposer: (() -> Void)?
    var onOpenSetup: (() -> Void)?

    private let repository: FavoritesRepository
    private let grammarService: GrammarQuestionProviding
    private let sectionControl = NSSegmentedControl(labels: ["我的单词本", "好句收藏夹", "语法问答"], trackingMode: .selectOne, target: nil, action: nil)
    private let contentContainer = RoundedSurfaceView(
        fillColor: AppVisualTheme.surface,
        strokeColor: AppVisualTheme.border,
        radius: 16
    )
    private var sectionViews: [LearningCenterSection: NSView] = [:]
    private var currentSection = LearningCenterSection.words

    private let wordSearchField = NSSearchField()
    private let wordCountLabel = NSTextField(labelWithString: "")
    private let wordStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let wordTable = NSTableView()
    private var wordItems: [FavoriteItem] = []

    private let collectionTable = NSTableView()
    private let sentenceSearchField = NSSearchField()
    private let sentenceCountLabel = NSTextField(labelWithString: "")
    private let sentenceStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let sentenceTable = NSTableView()
    private var collectionItems: [FavoriteCollection] = []
    private var sentenceItems: [FavoriteItem] = []

    private let grammarSentenceView = NSTextView()
    private let grammarQuestionView = NSTextView()
    private let grammarScenarioField = NSTextField()
    private let grammarAnswerView = NSTextView()
    private let grammarStatusLabel = NSTextField(wrappingLabelWithString: "")
    private var grammarAskButton: ActionButton!
    private var grammarCopyButton: ActionButton!
    private var grammarTask: Task<Void, Never>?
    private var grammarResponse: GrammarQuestionResponse?

    init(repository: FavoritesRepository, grammarService: GrammarQuestionProviding) {
        self.repository = repository
        self.grammarService = grammarService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Learn English Anytime · 学习中心"
        window.minSize = NSSize(width: 820, height: 580)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        configureContent()
        show(section: .words)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present(section: LearningCenterSection = .words) {
        _ = NSApplication.shared.setActivationPolicy(.regular)
        show(section: section)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        grammarTask?.cancel()
        sender.orderOut(nil)
        return false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === wordTable { return wordItems.count }
        if tableView === collectionTable { return collectionItems.count }
        if tableView === sentenceTable { return sentenceItems.count }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier.rawValue else { return nil }
        if tableView === collectionTable, collectionItems.indices.contains(row) {
            let item = collectionItems[row]
            return tableCell(
                item.name,
                secondary: item.isSystem ? "系统" : nil,
                emphasized: true
            )
        }
        if tableView === wordTable, wordItems.indices.contains(row) {
            let item = wordItems[row]
            let value: String
            switch identifier {
            case "word_type": value = item.kind.displayName
            case "word_source": value = item.sourceText
            case "word_pronunciation": value = item.pronunciation ?? ""
            case "word_meaning": value = item.meaning
            case "word_date": value = Self.dateFormatter.string(from: item.updatedAt)
            default: value = ""
            }
            return tableCell(value, muted: identifier == "word_type" || identifier == "word_date")
        }
        if tableView === sentenceTable, sentenceItems.indices.contains(row) {
            let item = sentenceItems[row]
            let value: String
            switch identifier {
            case "sentence_source": value = item.sourceText
            case "sentence_meaning": value = item.meaning
            case "sentence_kind": value = item.kind.displayName
            case "sentence_date": value = Self.dateFormatter.string(from: item.updatedAt)
            default: value = ""
            }
            return tableCell(value, muted: identifier == "sentence_kind" || identifier == "sentence_date")
        }
        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === collectionTable {
            reloadSentences()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        if field === wordSearchField {
            reloadWords()
        } else if field === sentenceSearchField {
            reloadSentences()
        }
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = AppVisualTheme.surface.cgColor

        let eyebrow = NSTextField(labelWithString: "LEARN ENGLISH ANYTIME")
        eyebrow.font = .systemFont(ofSize: 10.5, weight: .bold)
        eyebrow.textColor = AppVisualTheme.accent

        let title = NSTextField(labelWithString: "你的英语学习中心")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString:
            "全局划词继续在后台工作；在这里整理单词、按主题收藏好句，并针对具体英文句子提问语法。"
        )
        subtitle.textColor = .secondaryLabelColor

        let expressionButton = ActionButton(
            title: "这样表达",
            symbolName: "sparkles",
            style: .primary
        ) { [weak self] in
            self?.onOpenExpressionComposer?()
        }
        let setupButton = ActionButton(title: "划词与权限", symbolName: "cursorarrow.motionlines") { [weak self] in
            self?.onOpenSetup?()
        }
        let settingsButton = ActionButton(title: "AI 设置", symbolName: "gearshape") { [weak self] in
            self?.onOpenServiceSettings?()
        }
        let topActions = NSStackView(views: [expressionButton, setupButton, settingsButton])
        topActions.orientation = .horizontal
        topActions.spacing = 8

        let titleColumn = NSStackView(views: [eyebrow, title, subtitle])
        titleColumn.orientation = .vertical
        titleColumn.alignment = .leading
        titleColumn.spacing = 4
        let header = NSStackView(views: [titleColumn, topActions])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        let headerCard = RoundedSurfaceView(
            fillColor: AppVisualTheme.raisedSurface,
            strokeColor: AppVisualTheme.border,
            radius: 16
        )
        headerCard.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 16),
            header.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -16)
        ])

        sectionControl.selectedSegment = 0
        sectionControl.segmentStyle = .rounded
        sectionControl.target = self
        sectionControl.action = #selector(sectionChanged)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        let root = NSStackView(views: [headerCard, sectionControl, contentContainer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            headerCard.widthAnchor.constraint(equalTo: root.widthAnchor),
            titleColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 430),
            topActions.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            sectionControl.widthAnchor.constraint(equalToConstant: 470),
            contentContainer.widthAnchor.constraint(equalTo: root.widthAnchor),
            contentContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 430)
        ])

        sectionViews[.words] = makeWordsView()
        sectionViews[.sentences] = makeSentencesView()
        sectionViews[.grammar] = makeGrammarView()
        for view in sectionViews.values {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 16),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -16),
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 16),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -16)
            ])
        }
    }

    private func makeWordsView() -> NSView {
        wordSearchField.placeholderString = "搜索单词、词组或释义"
        wordSearchField.delegate = self
        wordCountLabel.textColor = .secondaryLabelColor
        wordCountLabel.alignment = .right
        wordStatusLabel.textColor = .secondaryLabelColor

        addColumn(to: wordTable, identifier: "word_type", title: "类型", width: 70)
        addColumn(to: wordTable, identifier: "word_source", title: "单词 / 词组", width: 190)
        addColumn(to: wordTable, identifier: "word_pronunciation", title: "音标", width: 140)
        addColumn(to: wordTable, identifier: "word_meaning", title: "释义", width: 360)
        addColumn(to: wordTable, identifier: "word_date", title: "收藏时间", width: 105)
        configureTable(wordTable)

        let speak = ActionButton(title: "朗读", symbolName: "speaker.wave.2") { [weak self] in self?.speakSelectedWord() }
        let copy = ActionButton(title: "复制", symbolName: "doc.on.doc") { [weak self] in self?.copySelectedWord() }
        let remove = ActionButton(title: "取消收藏", symbolName: "trash", style: .danger) { [weak self] in self?.removeSelectedWord() }
        let actions = NSStackView(views: [speak, copy, remove])
        actions.orientation = .horizontal
        actions.spacing = 8

        let header = NSStackView(views: [wordSearchField, wordCountLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        let scroll = tableScrollView(wordTable)
        let root = NSStackView(views: [header, scroll, wordStatusLabel, actions])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            wordSearchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            wordCountLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 350),
            wordStatusLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            actions.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        return root
    }

    private func makeSentencesView() -> NSView {
        let collectionTitle = NSTextField(labelWithString: "收藏夹")
        collectionTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let collectionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("collection_name"))
        collectionColumn.title = "收藏夹"
        collectionColumn.width = 190
        collectionTable.addTableColumn(collectionColumn)
        collectionTable.headerView = nil
        configureTable(collectionTable)
        collectionTable.rowHeight = 36
        let collectionScroll = tableScrollView(collectionTable)

        let addCollection = ActionButton(title: "新建", symbolName: "plus", style: .primary) { [weak self] in self?.createCollection() }
        let deleteCollection = ActionButton(title: "删除", symbolName: "trash", style: .danger) { [weak self] in self?.deleteSelectedCollection() }
        let collectionActions = NSStackView(views: [addCollection, deleteCollection])
        collectionActions.orientation = .horizontal
        collectionActions.spacing = 8
        let left = NSStackView(views: [collectionTitle, collectionScroll, collectionActions])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 10

        sentenceSearchField.placeholderString = "搜索好句或中文释义"
        sentenceSearchField.delegate = self
        sentenceCountLabel.textColor = .secondaryLabelColor
        sentenceCountLabel.alignment = .right
        sentenceStatusLabel.textColor = .secondaryLabelColor
        addColumn(to: sentenceTable, identifier: "sentence_source", title: "好句", width: 360)
        addColumn(to: sentenceTable, identifier: "sentence_meaning", title: "中文释义 / 笔记", width: 300)
        addColumn(to: sentenceTable, identifier: "sentence_kind", title: "类型", width: 85)
        addColumn(to: sentenceTable, identifier: "sentence_date", title: "更新时间", width: 105)
        configureTable(sentenceTable)

        let searchHeader = NSStackView(views: [sentenceSearchField, sentenceCountLabel])
        searchHeader.orientation = .horizontal
        searchHeader.alignment = .centerY
        searchHeader.spacing = 12
        let sentenceScroll = tableScrollView(sentenceTable)
        let addSentence = ActionButton(title: "添加好句", symbolName: "plus", style: .primary) { [weak self] in self?.addSentence() }
        let speak = ActionButton(title: "朗读", symbolName: "speaker.wave.2") { [weak self] in self?.speakSelectedSentence() }
        let copy = ActionButton(title: "复制", symbolName: "doc.on.doc") { [weak self] in self?.copySelectedSentence() }
        let move = ActionButton(title: "移入收藏夹…") { [weak self] in self?.moveSelectedSentence() }
        let remove = ActionButton(title: "取消收藏", symbolName: "trash", style: .danger) { [weak self] in self?.removeSelectedSentence() }
        let sentenceActions = NSStackView(views: [addSentence, speak, copy, move, remove])
        sentenceActions.orientation = .horizontal
        sentenceActions.spacing = 8
        let right = NSStackView(views: [searchHeader, sentenceScroll, sentenceStatusLabel, sentenceActions])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 10

        let split = NSStackView(views: [left, separator(vertical: true), right])
        split.orientation = .horizontal
        split.alignment = .top
        split.spacing = 14
        NSLayoutConstraint.activate([
            left.widthAnchor.constraint(equalToConstant: 205),
            collectionScroll.widthAnchor.constraint(equalTo: left.widthAnchor),
            collectionScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 390),
            right.widthAnchor.constraint(greaterThanOrEqualToConstant: 570),
            searchHeader.widthAnchor.constraint(equalTo: right.widthAnchor),
            sentenceSearchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 310),
            sentenceCountLabel.trailingAnchor.constraint(equalTo: searchHeader.trailingAnchor),
            sentenceScroll.widthAnchor.constraint(equalTo: right.widthAnchor),
            sentenceScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 350),
            sentenceStatusLabel.widthAnchor.constraint(equalTo: right.widthAnchor)
        ])
        return split
    }

    private func makeGrammarView() -> NSView {
        let intro = NSTextField(wrappingLabelWithString:
            "粘贴完整句子，再问你真正不理解的语法点。只有点击“提问”后，句子和问题才会发送到已配置的 AI 服务。"
        )
        intro.textColor = .secondaryLabelColor

        let sentenceLabel = sectionLabel("英文句子")
        let sentenceScroll = textArea(
            grammarSentenceView,
            placeholder: "例如：I started using AI to solve real business problems and drive measurable growth.",
            editable: true
        )
        let questionLabel = sectionLabel("你的问题")
        let questionScroll = textArea(
            grammarQuestionView,
            placeholder: "例如：这句话中 using 为什么用 ing 形式？",
            editable: true
        )
        let scenarioLabel = sectionLabel("场景（可选）")
        grammarScenarioField.placeholderString = "例如：产品经理面试回答"

        let answerLabel = sectionLabel("语法老师的回答")
        let answerScroll = textArea(
            grammarAnswerView,
            placeholder: "回答会包含直接结论、语法结构、为什么这样用、其他可用形式和新例句。",
            editable: false
        )
        grammarAnswerView.backgroundColor = AppVisualTheme.raisedSurface
        grammarStatusLabel.textColor = .secondaryLabelColor
        grammarStatusLabel.stringValue = "语法问答属于可选 AI 功能，可能产生 API 费用。"

        grammarAskButton = ActionButton(title: "提问", symbolName: "arrow.up.circle.fill", style: .primary) { [weak self] in self?.askGrammarQuestion() }
        grammarAskButton.keyEquivalent = "\r"
        let loadExample = ActionButton(title: "载入示例") { [weak self] in self?.loadGrammarExample() }
        grammarCopyButton = ActionButton(title: "复制回答") { [weak self] in self?.copyGrammarAnswer() }
        grammarCopyButton.isEnabled = false
        let settings = ActionButton(title: "AI 服务设置…") { [weak self] in self?.onOpenServiceSettings?() }
        let actions = NSStackView(views: [grammarAskButton, loadExample, grammarCopyButton, settings])
        actions.orientation = .horizontal
        actions.spacing = 8

        let root = NSStackView(views: [
            intro,
            sentenceLabel,
            sentenceScroll,
            questionLabel,
            questionScroll,
            scenarioLabel,
            grammarScenarioField,
            answerLabel,
            answerScroll,
            grammarStatusLabel,
            actions
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        NSLayoutConstraint.activate([
            intro.widthAnchor.constraint(equalTo: root.widthAnchor),
            sentenceScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            sentenceScroll.heightAnchor.constraint(equalToConstant: 72),
            questionScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            questionScroll.heightAnchor.constraint(equalToConstant: 62),
            grammarScenarioField.widthAnchor.constraint(equalTo: root.widthAnchor),
            answerScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            answerScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            grammarStatusLabel.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        return root
    }

    @objc private func sectionChanged() {
        guard let section = LearningCenterSection(rawValue: sectionControl.selectedSegment) else { return }
        show(section: section)
    }

    private func show(section: LearningCenterSection) {
        currentSection = section
        sectionControl.selectedSegment = section.rawValue
        for (candidate, view) in sectionViews {
            view.isHidden = candidate != section
        }
        switch section {
        case .words: reloadWords()
        case .sentences: reloadCollections()
        case .grammar: break
        }
    }

    private func reloadWords() {
        do {
            wordItems = try repository.fetch(
                search: wordSearchField.stringValue,
                kinds: [.word, .phrase],
                collectionID: nil
            )
            wordTable.reloadData()
            wordCountLabel.stringValue = "共 \(wordItems.count) 条"
            wordStatusLabel.stringValue = wordItems.isEmpty
                ? "还没有单词收藏。可在划词浮窗中点击“☆ 收藏”。"
                : "单词本保存在本机，不会自动上传。"
        } catch {
            wordStatusLabel.stringValue = error.localizedDescription
        }
    }

    private func reloadCollections(selecting collectionID: String? = nil) {
        let previousID = collectionID ?? selectedCollection()?.id
        do {
            collectionItems = try repository.collections()
            collectionTable.reloadData()
            let row = collectionItems.firstIndex { $0.id == previousID } ?? 0
            if collectionItems.indices.contains(row) {
                collectionTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            reloadSentences()
        } catch {
            sentenceStatusLabel.stringValue = error.localizedDescription
        }
    }

    private func reloadSentences() {
        guard let collection = selectedCollection() else {
            sentenceItems = []
            sentenceTable.reloadData()
            sentenceCountLabel.stringValue = "共 0 条"
            return
        }
        do {
            sentenceItems = try repository.fetch(
                search: sentenceSearchField.stringValue,
                kinds: [.sentence, .contextualExpression],
                collectionID: collection.id
            )
            sentenceTable.reloadData()
            sentenceCountLabel.stringValue = "共 \(sentenceItems.count) 条"
            sentenceStatusLabel.stringValue = sentenceItems.isEmpty
                ? "“\(collection.name)”中还没有好句。可以手动添加，或从划词/这样表达结果中收藏。"
                : "当前收藏夹：\(collection.name)"
        } catch {
            sentenceStatusLabel.stringValue = error.localizedDescription
        }
    }

    private func selectedCollection() -> FavoriteCollection? {
        let row = collectionTable.selectedRow
        return collectionItems.indices.contains(row) ? collectionItems[row] : collectionItems.first
    }

    private func selectedWord() -> FavoriteItem? {
        let row = wordTable.selectedRow
        guard wordItems.indices.contains(row) else {
            wordStatusLabel.stringValue = "请先选择一个单词或词组。"
            return nil
        }
        return wordItems[row]
    }

    private func selectedSentence() -> FavoriteItem? {
        let row = sentenceTable.selectedRow
        guard sentenceItems.indices.contains(row) else {
            sentenceStatusLabel.stringValue = "请先选择一句好句。"
            return nil
        }
        return sentenceItems[row]
    }

    private func speakSelectedWord() {
        guard let item = selectedWord() else { return }
        onSpeak?(item.spokenText, speechLocale(for: item.sourceLanguage))
    }

    private func copySelectedWord() {
        guard let item = selectedWord() else { return }
        copyToPasteboard(item.sourceText)
        wordStatusLabel.stringValue = "已复制“\(item.sourceText)”。"
    }

    private func removeSelectedWord() {
        guard let item = selectedWord() else { return }
        do {
            try repository.delete(id: item.id)
            reloadWords()
            wordStatusLabel.stringValue = "已取消收藏“\(item.sourceText)”。"
        } catch {
            wordStatusLabel.stringValue = error.localizedDescription
        }
    }

    private func speakSelectedSentence() {
        guard let item = selectedSentence() else { return }
        onSpeak?(item.spokenText, speechLocale(for: item.sourceLanguage))
    }

    private func copySelectedSentence() {
        guard let item = selectedSentence() else { return }
        copyToPasteboard(item.sourceText)
        sentenceStatusLabel.stringValue = "已复制所选好句。"
    }

    private func removeSelectedSentence() {
        guard let item = selectedSentence() else { return }
        do {
            try repository.delete(id: item.id)
            reloadSentences()
            sentenceStatusLabel.stringValue = "已取消收藏。"
        } catch {
            sentenceStatusLabel.stringValue = error.localizedDescription
        }
    }

    private func createCollection() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "新建好句收藏夹"
        alert.informativeText = "例如：产品经理面试、工作汇报、日常口语"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "收藏夹名称"
        alert.accessoryView = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                let created = try self.repository.createCollection(name: field.stringValue)
                self.reloadCollections(selecting: created.id)
                self.sentenceStatusLabel.stringValue = "已创建“\(created.name)”。"
            } catch {
                self.sentenceStatusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func deleteSelectedCollection() {
        guard let window, let collection = selectedCollection() else { return }
        guard !collection.isSystem else {
            sentenceStatusLabel.stringValue = "默认好句收藏夹不能删除。"
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除“\(collection.name)”？"
        alert.informativeText = "其中的句子会移到“默认好句”，不会丢失。"
        alert.addButton(withTitle: "删除收藏夹")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                try self.repository.deleteCollection(id: collection.id)
                self.reloadCollections(selecting: defaultSentenceCollectionID)
                self.sentenceStatusLabel.stringValue = "收藏夹已删除，其中的句子已移到“默认好句”。"
            } catch {
                self.sentenceStatusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func addSentence() {
        guard let window, let collection = selectedCollection() else { return }
        let alert = NSAlert()
        alert.messageText = "添加到“\(collection.name)”"
        alert.informativeText = "输入好句和可选的中文释义或学习笔记。"
        alert.addButton(withTitle: "收藏")
        alert.addButton(withTitle: "取消")
        let sentenceField = NSTextField()
        sentenceField.placeholderString = "英文或中文好句"
        let meaningField = NSTextField()
        meaningField.placeholderString = "中文释义 / 笔记（可选）"
        let accessory = NSStackView(views: [sentenceField, meaningField])
        accessory.orientation = .vertical
        accessory.spacing = 8
        accessory.frame = NSRect(x: 0, y: 0, width: 420, height: 58)
        sentenceField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        meaningField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        alert.accessoryView = accessory
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let sentence = sentenceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else {
                self.sentenceStatusLabel.stringValue = "好句不能为空。"
                return
            }
            let meaning = meaningField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let language = TextLanguageDetector.detect(sentence)
            let draft = FavoriteDraft(
                kind: .sentence,
                sourceText: sentence,
                pronunciation: nil,
                meaning: meaning.isEmpty ? "手动收藏的好句" : meaning,
                note: "手动收藏",
                spokenText: sentence,
                sourceLanguage: language.rawValue,
                minimalContextText: nil
            )
            do {
                let inserted = try self.repository.save(draft, collectionID: collection.id)
                self.reloadSentences()
                self.sentenceStatusLabel.stringValue = inserted ? "好句已收藏。" : "该句已存在，已移动到当前收藏夹。"
            } catch {
                self.sentenceStatusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func moveSelectedSentence() {
        guard let window, let item = selectedSentence(), !collectionItems.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "移入收藏夹"
        alert.addButton(withTitle: "移动")
        alert.addButton(withTitle: "取消")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        popup.addItems(withTitles: collectionItems.map(\.name))
        if let index = collectionItems.firstIndex(where: { $0.id == item.collectionID }) {
            popup.selectItem(at: index)
        }
        alert.accessoryView = popup
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let self,
                  self.collectionItems.indices.contains(popup.indexOfSelectedItem) else { return }
            let target = self.collectionItems[popup.indexOfSelectedItem]
            do {
                try self.repository.moveFavorite(id: item.id, to: target.id)
                self.reloadCollections(selecting: target.id)
                self.sentenceStatusLabel.stringValue = "已移入“\(target.name)”。"
            } catch {
                self.sentenceStatusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func loadGrammarExample() {
        grammarSentenceView.string = "I started using AI to solve real business problems and drive measurable growth."
        grammarQuestionView.string = "这句话中 using 为什么用 ing 形式？"
        grammarScenarioField.stringValue = "产品经理面试回答"
        grammarStatusLabel.textColor = .secondaryLabelColor
        grammarStatusLabel.stringValue = "示例已载入，点击“提问”后才会发送。"
    }

    private func askGrammarQuestion() {
        let sentence = grammarSentenceView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = grammarQuestionView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !question.isEmpty else {
            grammarStatusLabel.textColor = .systemRed
            grammarStatusLabel.stringValue = "请同时填写完整句子和语法问题。"
            return
        }

        grammarTask?.cancel()
        grammarResponse = nil
        grammarCopyButton.isEnabled = false
        grammarAskButton.isEnabled = false
        grammarAskButton.title = "回答中…"
        grammarAnswerView.string = ""
        grammarStatusLabel.textColor = .secondaryLabelColor
        grammarStatusLabel.stringValue = "正在分析句子中的具体语法结构；此操作会请求已配置的 AI 服务…"
        let scenario = grammarScenarioField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = GrammarQuestionRequest(
            requestId: UUID().uuidString,
            sentence: sentence,
            question: question,
            scenario: scenario.isEmpty ? nil : scenario
        )
        grammarTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await grammarService.ask(request)
                try Task.checkCancellation()
                showGrammarAnswer(response)
            } catch is CancellationError {
                grammarStatusLabel.stringValue = "已取消语法提问。"
            } catch {
                grammarStatusLabel.textColor = .systemRed
                grammarStatusLabel.stringValue = error.localizedDescription
            }
            grammarAskButton.isEnabled = true
            grammarAskButton.title = "提问"
            grammarTask = nil
        }
    }

    private func showGrammarAnswer(_ response: GrammarQuestionResponse) {
        grammarResponse = response
        var sections = [
            "直接回答",
            response.answerZh,
            "",
            "句中形式",
            response.highlightedForm,
            "",
            "语法点",
            response.grammarPoint,
            "",
            "为什么这样用",
            response.explanationZh,
            "",
            "结构",
            response.structure
        ]
        if !response.alternatives.isEmpty {
            sections.append(contentsOf: ["", "其他可用形式"])
            for alternative in response.alternatives {
                sections.append("• \(alternative.form)：\(alternative.explanationZh)")
            }
        }
        sections.append(contentsOf: ["", "同类例句"])
        for (index, example) in response.examples.enumerated() {
            sections.append("\(index + 1). \(example.english)")
            sections.append("   \(example.chinese)")
            sections.append("   \(example.noteZh)")
        }
        sections.append(contentsOf: ["", "快速记忆", response.quickRuleZh])
        grammarAnswerView.string = sections.joined(separator: "\n")
        grammarCopyButton.isEnabled = true
        grammarStatusLabel.textColor = .systemGreen
        grammarStatusLabel.stringValue = response.modelLabel.map { "回答完成 · \($0)" } ?? "回答完成。"
    }

    private func copyGrammarAnswer() {
        guard grammarResponse != nil, !grammarAnswerView.string.isEmpty else { return }
        copyToPasteboard(grammarAnswerView.string)
        grammarStatusLabel.textColor = .systemGreen
        grammarStatusLabel.stringValue = "已复制语法回答。"
    }

    private func configureTable(_ table: NSTableView) {
        table.delegate = self
        table.dataSource = self
        table.headerView = table.headerView ?? NSTableHeaderView()
        table.rowHeight = 34
        table.usesAlternatingRowBackgroundColors = false
        table.style = .inset
        table.allowsMultipleSelection = false
    }

    private func addColumn(to table: NSTableView, identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = min(width, 65)
        table.addTableColumn(column)
    }

    private func tableScrollView(_ table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        return scroll
    }

    private func tableCell(
        _ value: String,
        secondary: String? = nil,
        emphasized: Bool = false,
        muted: Bool = false
    ) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.font = emphasized ? .systemFont(ofSize: 13, weight: .medium) : .systemFont(ofSize: 13)
        label.textColor = muted ? .secondaryLabelColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        if let secondary {
            let badge = NSTextField(labelWithString: secondary)
            badge.font = .systemFont(ofSize: 10)
            badge.textColor = .tertiaryLabelColor
            badge.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6)
            ])
        } else {
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func sectionLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func textArea(_ textView: NSTextView, placeholder: String, editable: Bool) -> NSScrollView {
        textView.isRichText = false
        textView.isEditable = editable
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 9, height: 8)
        textView.drawsBackground = true
        textView.backgroundColor = AppVisualTheme.raisedSurface
        textView.setAccessibilityPlaceholderValue(placeholder)
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        return scroll
    }

    private func separator(vertical: Bool = false) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        if vertical {
            box.widthAnchor.constraint(equalToConstant: 1).isActive = true
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        }
        return box
    }

    private func speechLocale(for identifier: String) -> String {
        identifier.lowercased().hasPrefix("zh") ? "zh-CN" : "en-US"
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
