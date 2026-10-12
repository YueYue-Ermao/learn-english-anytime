import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onOpenLearningCenter: ((LearningCenterSection) -> Void)?
    var onRequestPermission: (() -> Void)?
    var onOpenSetup: (() -> Void)?
    var onPause: ((TimeInterval) -> Void)?
    var onResume: (() -> Void)?
    var onShowDemo: (() -> Void)?
    var onDirectDisplayChanged: ((Bool) -> Void)?
    var onOpenWordbook: (() -> Void)?
    var onOpenServiceSettings: (() -> Void)?
    var onOpenExpressionComposer: (() -> Void)?
    var onRefreshRequested: (() -> Void)?

    private let statusItem: NSStatusItem
    private let permissionItem = NSMenuItem(title: "辅助功能权限：未开启", action: nil, keyEquivalent: "")
    private let diagnosticItem = NSMenuItem(title: "监听诊断：尚未开始", action: nil, keyEquivalent: "")
    private let resumeItem = NSMenuItem(title: "立即恢复自动浮窗", action: #selector(resume), keyEquivalent: "")
    private let directDisplayItem = NSMenuItem(
        title: "选中即展示",
        action: #selector(toggleDirectDisplay),
        keyEquivalent: ""
    )

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "character.book.closed",
            accessibilityDescription: "Context English Assistant"
        )

        let menu = NSMenu()
        menu.delegate = self

        let openLearningCenter = NSMenuItem(
            title: "打开学习中心…",
            action: #selector(openLearningCenter),
            keyEquivalent: "l"
        )
        openLearningCenter.target = self
        menu.addItem(openLearningCenter)
        menu.addItem(.separator())

        let openSetup = NSMenuItem(
            title: "打开启动与权限诊断…",
            action: #selector(openSetup),
            keyEquivalent: ""
        )
        openSetup.target = self
        menu.addItem(openSetup)
        menu.addItem(.separator())

        menu.addItem(permissionItem)
        diagnosticItem.isEnabled = false
        menu.addItem(diagnosticItem)

        let openPermission = NSMenuItem(
            title: "打开辅助功能设置…",
            action: #selector(requestPermission),
            keyEquivalent: ""
        )
        openPermission.target = self
        menu.addItem(openPermission)
        menu.addItem(.separator())

        let demo = NSMenuItem(
            title: "显示测试浮窗",
            action: #selector(showDemo),
            keyEquivalent: ""
        )
        demo.target = self
        menu.addItem(demo)
        menu.addItem(.separator())

        let expressionComposer = NSMenuItem(
            title: "这样表达…",
            action: #selector(openExpressionComposer),
            keyEquivalent: "e"
        )
        expressionComposer.target = self
        menu.addItem(expressionComposer)

        directDisplayItem.target = self
        menu.addItem(directDisplayItem)

        let wordbook = NSMenuItem(
            title: "我的单词本…",
            action: #selector(openWordbook),
            keyEquivalent: ""
        )
        wordbook.target = self
        menu.addItem(wordbook)

        let sentenceCollections = NSMenuItem(
            title: "好句收藏夹…",
            action: #selector(openSentenceCollections),
            keyEquivalent: ""
        )
        sentenceCollections.target = self
        menu.addItem(sentenceCollections)

        let grammar = NSMenuItem(
            title: "语法问答…",
            action: #selector(openGrammarQuestions),
            keyEquivalent: ""
        )
        grammar.target = self
        menu.addItem(grammar)

        let serviceSettings = NSMenuItem(
            title: "AI 服务设置…",
            action: #selector(openServiceSettings),
            keyEquivalent: ""
        )
        serviceSettings.target = self
        menu.addItem(serviceSettings)
        menu.addItem(.separator())

        menu.addItem(pauseItem(title: "暂停自动浮窗 1 小时", duration: 60 * 60))
        menu.addItem(pauseItem(title: "暂停自动浮窗 2 小时", duration: 2 * 60 * 60))
        menu.addItem(pauseItem(title: "暂停自动浮窗 4 小时", duration: 4 * 60 * 60))

        resumeItem.target = self
        menu.addItem(resumeItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        onRefreshRequested?()
    }

    func update(isTrusted: Bool, pausedUntil: Date?, directDisplayEnabled: Bool) {
        permissionItem.title = isTrusted ? "辅助功能权限：已开启" : "辅助功能权限：未开启"
        permissionItem.state = isTrusted ? .on : .off
        directDisplayItem.state = directDisplayEnabled ? .on : .off

        if let pausedUntil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            statusItem.button?.toolTip = "自动浮窗已暂停至 \(formatter.string(from: pausedUntil))"
            statusItem.button?.contentTintColor = .secondaryLabelColor
            resumeItem.isHidden = false
        } else {
            statusItem.button?.toolTip = "Context English Assistant"
            statusItem.button?.contentTintColor = nil
            resumeItem.isHidden = true
        }
    }

    func updateDiagnostic(_ message: String) {
        diagnosticItem.title = "监听诊断：\(message)"
    }

    private func pauseItem(title: String, duration: TimeInterval) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(pause(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = NSNumber(value: duration)
        return item
    }

    @objc private func requestPermission() {
        onRequestPermission?()
    }

    @objc private func openLearningCenter() {
        onOpenLearningCenter?(.words)
    }

    @objc private func openSetup() {
        onOpenSetup?()
    }

    @objc private func pause(_ sender: NSMenuItem) {
        guard let duration = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        onPause?(duration)
    }

    @objc private func resume() {
        onResume?()
    }

    @objc private func showDemo() {
        onShowDemo?()
    }

    @objc private func toggleDirectDisplay() {
        onDirectDisplayChanged?(directDisplayItem.state != .on)
    }

    @objc private func openWordbook() {
        onOpenWordbook?()
    }

    @objc private func openSentenceCollections() {
        onOpenLearningCenter?(.sentences)
    }

    @objc private func openGrammarQuestions() {
        onOpenLearningCenter?(.grammar)
    }

    @objc private func openServiceSettings() {
        onOpenServiceSettings?()
    }

    @objc private func openExpressionComposer() {
        onOpenExpressionComposer?()
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
