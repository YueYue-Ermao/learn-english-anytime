import AppKit
import ContextEnglishCore

@MainActor
final class SelectionCoordinator {
    var onPauseChanged: (() -> Void)?
    var onDiagnosticChanged: ((String) -> Void)?
    var onDirectDisplayChanged: ((Bool) -> Void)?

    private let selectionReader: AccessibilitySelectionReader
    private let triggerPolicy: TriggerPolicy
    private let lookupRoutingPolicy = LookupRoutingPolicy()
    private let automaticTranslationPolicy = AutomaticTranslationPolicy()
    private let pauseManager: PauseManager
    private let dictionary: DictionaryProviding
    private let panelController: LookupPanelController
    private let settings: AppSettings
    private let favorites: FavoritesRepository
    private let localTranslationService: LocalTranslationProviding?
    private let translationService: ContextualTranslationProviding
    private let gracePeriod: TimeInterval

    private var triggerMode: TriggerMode
    private var pendingWorkItem: DispatchWorkItem?
    private var lastSelectionSignature: String?
    private var lastSelectionDate: Date?
    private var translationTask: Task<Void, Never>?
    private var activeTranslationID: UUID?

    init(
        selectionReader: AccessibilitySelectionReader,
        triggerPolicy: TriggerPolicy,
        pauseManager: PauseManager,
        dictionary: DictionaryProviding,
        panelController: LookupPanelController,
        settings: AppSettings,
        favorites: FavoritesRepository,
        localTranslationService: LocalTranslationProviding?,
        translationService: ContextualTranslationProviding,
        gracePeriod: TimeInterval = 0.3
    ) {
        self.selectionReader = selectionReader
        self.triggerPolicy = triggerPolicy
        self.pauseManager = pauseManager
        self.dictionary = dictionary
        self.panelController = panelController
        self.settings = settings
        self.favorites = favorites
        self.localTranslationService = localTranslationService
        self.translationService = translationService
        self.gracePeriod = gracePeriod
        triggerMode = settings.directDisplayEnabled ? .alwaysFull : .hintOnly

        panelController.onPauseForOneHour = { [weak self] in
            self?.pauseGlobally(for: 60 * 60)
        }
        panelController.onToggleDirectDisplay = { [weak self] in
            self?.toggleDirectDisplay() ?? false
        }
        panelController.onToggleFavorite = { [weak self] draft in
            self?.toggleFavorite(draft)
        }
        panelController.onRequestLocalTranslation = { [weak self] draft in
            self?.requestLocalTranslation(draft)
        }
        panelController.onRequestAITranslation = { [weak self] draft in
            self?.requestAITranslation(draft)
        }
        panelController.onCancelTranslation = { [weak self] in
            self?.translationTask?.cancel()
            self?.translationTask = nil
            self?.activeTranslationID = nil
        }
    }

    func selectionGestureFinished() {
        pendingWorkItem?.cancel()
        onDiagnosticChanged?("已收到鼠标松开事件，正在读取选区…")
        scheduleCapture(after: gracePeriod, attempt: 0)
    }

    func cancellationGestureDetected() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        translationTask?.cancel()
        translationTask = nil
        activeTranslationID = nil
        panelController.hide()
    }

    func pauseGlobally(for duration: TimeInterval) {
        _ = pauseManager.pause(.global, for: duration)
        cancellationGestureDetected()
        onPauseChanged?()
    }

    func resumeGlobally() {
        pauseManager.resume(.global)
        onPauseChanged?()
    }

    var isDirectDisplayEnabled: Bool {
        settings.directDisplayEnabled
    }

    func setDirectDisplayEnabled(_ enabled: Bool) {
        settings.directDisplayEnabled = enabled
        triggerMode = enabled ? .alwaysFull : .hintOnly
        onDirectDisplayChanged?(enabled)
        onDiagnosticChanged?(enabled ? "已开启选中即展示" : "已关闭选中即展示，恢复 A 轻提示")
    }

    @discardableResult
    func toggleDirectDisplay() -> Bool {
        let enabled = !settings.directDisplayEnabled
        setDirectDisplayEnabled(enabled)
        return enabled
    }

    func showPrototypeDemo() {
        let snapshot = SelectionSnapshot(
            text: "prioritize",
            bounds: CGRect(origin: NSEvent.mouseLocation, size: .zero),
            source: .internalComposer,
            sourceApplicationID: Bundle.main.bundleIdentifier,
            surfaceKind: .readOnly
        )
        presentFull(snapshot)
    }

    private func scheduleCapture(after delay: TimeInterval, attempt: Int) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.captureAndPresent(attempt: attempt)
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func captureAndPresent(attempt: Int) {
        pendingWorkItem = nil

        let snapshot: SelectionSnapshot
        do {
            snapshot = try selectionReader.readCurrentSelection()
        } catch SelectionReadError.selectionUnavailable where attempt < 2 {
            let nextAttempt = attempt + 1
            let delay: TimeInterval = nextAttempt == 1 ? 0.7 : 1.4
            onDiagnosticChanged?("选区树尚未就绪，正在自动重试（\(nextAttempt)/2）…")
            scheduleCapture(after: delay, attempt: nextAttempt)
            return
        } catch {
            onDiagnosticChanged?("读取失败：\(error.localizedDescription)")
            return
        }

        let isPaused = pauseManager.activePause(
            forApplicationID: snapshot.sourceApplicationID
        ) != nil
        let decision = triggerPolicy.decision(
            for: snapshot,
            mode: triggerMode,
            isPaused: isPaused
        )

        guard !isRapidDuplicate(snapshot) else {
            onDiagnosticChanged?("已忽略 1 秒内的重复选区")
            return
        }

        switch decision {
        case .none:
            onDiagnosticChanged?("已读取“\(snapshot.normalizedText)”，但当前触发策略未显示")
        case .hint:
            onDiagnosticChanged?("已读取“\(snapshot.normalizedText)”，显示轻提示")
            panelController.showHint(for: snapshot) { [weak self] in
                self?.presentFull(snapshot)
            }
        case .full:
            onDiagnosticChanged?("已读取“\(snapshot.normalizedText)”，显示查询浮窗")
            presentFull(snapshot)
        }
    }

    private func presentFull(_ snapshot: SelectionSnapshot) {
        let text = snapshot.normalizedText
        let route = lookupRoutingPolicy.route(for: text, language: snapshot.language)
        let localEntry = route == .localDictionaryFirst ? dictionary.lookup(text) : nil
        let title: String
        let pronunciation: String?
        let meaning: String
        let note: String?
        let spokenText: String
        let spokenLocale: String

        if let entry = localEntry {
            let partOfSpeech = entry.partOfSpeech.map { "\($0) · " } ?? ""
            title = entry.headword
            pronunciation = entry.phonetic
            meaning = partOfSpeech + entry.meanings.joined(separator: "；")
            note = entry.usageNote
            spokenText = entry.spokenText ?? entry.headword
            spokenLocale = "en-US"
        } else if snapshot.language == .chinese || snapshot.language == .mixed {
            title = text
            pronunciation = nil
            meaning = route == .localDictionaryFirst
                ? "本地汉英词典暂未收录；可使用“本机翻译（免费）”生成英文。"
                : "已识别为短语或句子；可直接使用 Apple 本机翻译。"
            note = "本机翻译不调用 API；“AI 地道化”只有在你主动点击后才会使用模型服务。"
            spokenText = text
            spokenLocale = "zh-CN"
        } else {
            title = text
            pronunciation = nil
            meaning = route == .localDictionaryFirst
                ? "离线词典暂未收录，可使用本机翻译。"
                : "已识别为短语或句子，可直接使用 Apple 本机翻译。"
            note = "本机翻译不调用 API；需要场景化改写时再选择“AI 地道化”。"
            spokenText = text
            spokenLocale = "en-US"
        }

        let kind = favoriteKind(for: text)
        let draft = FavoriteDraft(
            kind: kind,
            sourceText: text,
            pronunciation: pronunciation,
            meaning: meaning,
            note: note,
            spokenText: spokenText,
            sourceLanguage: snapshot.language.rawValue,
            minimalContextText: snapshot.context?.text
        )
        let contextStatus: String
        if localEntry != nil {
            contextStatus = snapshot.context == nil
                ? "本地词典结果 · 未调用模型"
                : "本地词典结果 · 可按需结合所在句"
        } else {
            contextStatus = snapshot.context == nil
                ? "本机翻译可用 · 未调用 API"
                : "已在本机取得所在句 · 未调用 API"
        }
        let translationDraft = TranslationDraft(
            selectedText: text,
            language: snapshot.language,
            context: snapshot.context,
            bounds: snapshot.bounds,
            scenario: nil
        )
        let presentation = LookupPresentation(
            title: title,
            pronunciation: pronunciation,
            meaning: meaning,
            note: note,
            spokenText: spokenText,
            spokenLocale: spokenLocale,
            favoriteDraft: draft,
            isFavorite: favorites.contains(draft),
            directDisplayEnabled: settings.directDisplayEnabled,
            contextStatus: contextStatus,
            localTranslationDraft: localTranslationActionTitle(
                for: snapshot,
                route: route,
                hasLocalEntry: localEntry != nil
            ) == nil ? nil : translationDraft,
            localTranslationActionTitle: localTranslationActionTitle(
                for: snapshot,
                route: route,
                hasLocalEntry: localEntry != nil
            ),
            aiTranslationDraft: aiTranslationActionTitle(
                for: snapshot,
                route: route,
                hasLocalEntry: localEntry != nil
            ) == nil ? nil : translationDraft,
            aiTranslationActionTitle: aiTranslationActionTitle(
                for: snapshot,
                route: route,
                hasLocalEntry: localEntry != nil
            )
        )

        panelController.showFull(presentation, near: snapshot.bounds)

        if automaticTranslationPolicy.shouldTranslate(
            text: text,
            language: snapshot.language,
            route: route,
            hasLocalEntry: localEntry != nil,
            serviceAvailable: localTranslationService != nil
        ) {
            onDiagnosticChanged?("已识别为短语或句子，正在自动使用本机翻译…")
            requestLocalTranslation(translationDraft)
        }
    }

    private func requestLocalTranslation(_ draft: TranslationDraft) {
        guard let localTranslationService else {
            panelController.showMessage(
                title: "本机翻译不可用",
                message: LocalTranslationError.unsupportedSystem.localizedDescription,
                near: draft.bounds
            )
            return
        }

        translationTask?.cancel()
        let requestID = UUID()
        activeTranslationID = requestID
        panelController.showLoading(
            title: draft.selectedText,
            statusMessage: "正在使用 Apple 本机翻译；首次使用可能需要下载语言包…",
            near: draft.bounds
        )
        onDiagnosticChanged?("正在本机翻译，未调用 API…")

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await localTranslationService.translate(draft)
                try Task.checkCancellation()
                presentLocalTranslation(result, originalDraft: draft)
                onDiagnosticChanged?(result.usedSentenceContext
                    ? "本机翻译完成，已翻译所在句"
                    : "本机翻译完成，未调用 API")
            } catch is CancellationError {
                onDiagnosticChanged?("已取消本机翻译")
            } catch {
                panelController.showMessage(
                    title: "暂时无法本机翻译",
                    message: error.localizedDescription,
                    near: draft.bounds
                )
                onDiagnosticChanged?("本机翻译失败：\(error.localizedDescription)")
            }
            if activeTranslationID == requestID {
                translationTask = nil
                activeTranslationID = nil
            }
        }
    }

    private func requestAITranslation(_ draft: TranslationDraft) {
        translationTask?.cancel()
        let requestID = UUID()
        activeTranslationID = requestID
        panelController.showLoading(
            title: draft.selectedText,
            statusMessage: "正在请求 AI 地道化；此操作可能产生 API 费用…",
            near: draft.bounds
        )
        onDiagnosticChanged?(draft.context == nil
            ? "正在按选中文字请求 AI 地道化…"
            : "正在向 AI 服务发送选中文字和最小句子上下文…")

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await translationService.translate(draft.request)
                try Task.checkCancellation()
                presentTranslation(response, originalDraft: draft)
                onDiagnosticChanged?(response.contextUsed
                    ? "AI 地道化完成，已结合所在句"
                    : "AI 地道化完成，服务未使用所在句")
            } catch is CancellationError {
                onDiagnosticChanged?("已取消 AI 地道化")
            } catch {
                panelController.showMessage(
                    title: "暂时无法使用 AI 地道化",
                    message: error.localizedDescription,
                    near: draft.bounds
                )
                onDiagnosticChanged?("AI 地道化失败：\(error.localizedDescription)")
            }
            if activeTranslationID == requestID {
                translationTask = nil
                activeTranslationID = nil
            }
        }
    }

    private func presentLocalTranslation(
        _ result: LocalTranslationResult,
        originalDraft: TranslationDraft
    ) {
        var sections: [String] = []
        if result.usedSentenceContext,
           let entry = dictionary.lookup(originalDraft.selectedText) {
            let localMeaning = entry.meanings.joined(separator: "；")
            sections.append("选中内容：\(localMeaning)")
        }
        sections.append(result.usedSentenceContext
            ? "所在句译文：\(result.targetText)"
            : "本机译文：\(result.targetText)")
        let meaning = sections.joined(separator: "\n\n")
        let note = "Apple 本机翻译 · 内容未发送到模型服务 · 无 API 费用"
        let favoriteDraft = FavoriteDraft(
            kind: favoriteKind(for: result.targetText),
            sourceText: result.targetText,
            pronunciation: nil,
            meaning: meaning,
            note: note,
            spokenText: result.targetText,
            sourceLanguage: result.targetLanguage,
            minimalContextText: originalDraft.context?.text
        )
        let presentation = LookupPresentation(
            title: originalDraft.selectedText,
            pronunciation: nil,
            meaning: meaning,
            note: note,
            spokenText: result.targetText,
            spokenLocale: speechLocale(for: result.targetLanguage),
            favoriteDraft: favoriteDraft,
            isFavorite: favorites.contains(favoriteDraft),
            directDisplayEnabled: settings.directDisplayEnabled,
            contextStatus: "本机处理完成 · 未调用 API",
            localTranslationDraft: originalDraft,
            localTranslationActionTitle: "重新本机翻译",
            aiTranslationDraft: originalDraft,
            aiTranslationActionTitle: "AI 地道化（可选）"
        )
        panelController.showFull(presentation, near: originalDraft.bounds)
    }

    private func presentTranslation(
        _ response: ContextualTranslationResponse,
        originalDraft: TranslationDraft
    ) {
        var sections: [String] = []
        let selectedLine = response.selectedMeaning.target
        sections.append("本句中：\(selectedLine)")
        if !response.selectedMeaning.explanationZh.isEmpty {
            sections.append(response.selectedMeaning.explanationZh)
        }
        if response.sentence.target != selectedLine {
            sections.append("整句：\(response.sentence.target)")
        }
        if !response.alternatives.isEmpty {
            let alternatives = response.alternatives.prefix(3).enumerated().map { index, value in
                let meaning = value.meaningZh.map { " · \($0)" } ?? ""
                return "\(index + 1). \(value.target)\(meaning)（\(value.differenceZh)）"
            }.joined(separator: "\n")
            sections.append("其他表达：\n\(alternatives)")
        }
        let meaning = sections.joined(separator: "\n\n")
        let resultText = response.sentence.target.isEmpty
            ? response.selectedMeaning.target
            : response.sentence.target
        let favoriteDraft = FavoriteDraft(
            kind: .contextualExpression,
            sourceText: resultText,
            pronunciation: nil,
            meaning: meaning,
            note: response.modelLabel.map { "AI 语境翻译 · \($0)" } ?? "AI 语境翻译",
            spokenText: resultText,
            sourceLanguage: response.targetLanguage,
            minimalContextText: originalDraft.context?.text
        )
        let presentation = LookupPresentation(
            title: response.selectedMeaning.source,
            pronunciation: response.selectedMeaning.partOfSpeech,
            meaning: meaning,
            note: favoriteDraft.note,
            spokenText: resultText,
            spokenLocale: speechLocale(for: response.targetLanguage),
            favoriteDraft: favoriteDraft,
            isFavorite: favorites.contains(favoriteDraft),
            directDisplayEnabled: settings.directDisplayEnabled,
            contextStatus: response.contextUsed ? "已结合所在句 · AI 翻译" : "仅按选中文字 · AI 翻译",
            localTranslationDraft: localTranslationService == nil ? nil : originalDraft,
            localTranslationActionTitle: localTranslationService == nil ? nil : "本机翻译（免费）",
            aiTranslationDraft: originalDraft,
            aiTranslationActionTitle: "重新 AI 地道化"
        )
        panelController.showFull(presentation, near: originalDraft.bounds)
    }

    private func localTranslationActionTitle(
        for snapshot: SelectionSnapshot,
        route: LookupRoute,
        hasLocalEntry: Bool
    ) -> String? {
        guard localTranslationService != nil else { return nil }
        if hasSurroundingContext(snapshot) { return "本机译句（免费）" }
        if route == .modelRecommended || !hasLocalEntry { return "本机翻译（免费）" }
        return nil
    }

    private func aiTranslationActionTitle(
        for snapshot: SelectionSnapshot,
        route: LookupRoute,
        hasLocalEntry: Bool
    ) -> String? {
        if hasSurroundingContext(snapshot) { return "AI 结合语境（可选）" }
        if route == .modelRecommended || !hasLocalEntry { return "AI 地道化（可选）" }
        return nil
    }

    private func hasSurroundingContext(_ snapshot: SelectionSnapshot) -> Bool {
        snapshot.context.map {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) != snapshot.normalizedText
        } ?? false
    }

    private func speechLocale(for languageIdentifier: String) -> String {
        languageIdentifier.lowercased().hasPrefix("zh") ? "zh-CN" : "en-US"
    }

    private func toggleFavorite(_ draft: FavoriteDraft) -> Bool? {
        do {
            let isFavorite = try favorites.toggle(draft)
            onDiagnosticChanged?(isFavorite ? "已收藏“\(draft.sourceText)”" : "已取消收藏“\(draft.sourceText)”")
            return isFavorite
        } catch {
            onDiagnosticChanged?("收藏失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func favoriteKind(for text: String) -> FavoriteKind {
        let sentencePunctuation = CharacterSet(charactersIn: ".!?。！？")
        let hasSentencePunctuation = text.unicodeScalars.contains {
            sentencePunctuation.contains($0)
        }
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        if hasSentencePunctuation || wordCount > 6 || text.count > 36 {
            return .sentence
        }
        if wordCount > 1 || text.contains("-") || text.count > 18 {
            return .phrase
        }
        return .word
    }

    private func isRapidDuplicate(_ snapshot: SelectionSnapshot) -> Bool {
        let signature = [
            snapshot.sourceApplicationID ?? "unknown",
            snapshot.normalizedText
        ].joined(separator: "|")

        defer {
            lastSelectionSignature = signature
            lastSelectionDate = Date()
        }

        guard signature == lastSelectionSignature,
              let lastSelectionDate else {
            return false
        }
        return Date().timeIntervalSince(lastSelectionDate) < 1.0
    }
}
