import AppKit

@MainActor
final class ServiceSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: AppSettings
    private let endpointField = NSTextField()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(settings: AppSettings) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI 服务设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        endpointField.stringValue = settings.contextualTranslationEndpoint?.absoluteString ?? ""
        statusLabel.stringValue = settings.contextualTranslationEndpoint == nil
            ? "尚未配置 AI 服务；本机翻译、单词本和好句收藏仍可使用。开发服务地址为 http://127.0.0.1:8765/v1/translations/contextual"
            : "只有主动点击“AI 地道化”“生成表达”或“语法提问”时，才会发送对应内容。"
        _ = NSApplication.shared.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        let title = NSTextField(labelWithString: "可选 AI 语言服务地址")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let detail = NSTextField(wrappingLabelWithString:
            "普通查词和句子翻译均可在本机免费完成。此服务用于场景化改写和语法问答；语法接口会自动使用同一主机的 /v1/grammar/questions。留空不会影响本机翻译和收藏。"
        )
        detail.textColor = .secondaryLabelColor

        endpointField.placeholderString = "https://example.com/v1/translations/contextual"
        endpointField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        statusLabel.textColor = .secondaryLabelColor

        let useLocal = ActionButton(title: "使用本机开发服务") { [weak self] in
            self?.endpointField.stringValue = "http://127.0.0.1:8765/v1/translations/contextual"
        }
        let clear = ActionButton(title: "清除") { [weak self] in
            self?.endpointField.stringValue = ""
        }
        let save = ActionButton(title: "保存") { [weak self] in
            self?.save()
        }
        save.keyEquivalent = "\r"

        let controls = NSStackView(views: [useLocal, clear, save])
        controls.orientation = .horizontal
        controls.spacing = 8

        let root = NSStackView(views: [title, detail, endpointField, statusLabel, controls])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            detail.widthAnchor.constraint(equalTo: root.widthAnchor),
            endpointField.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
    }

    private func save() {
        let value = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            settings.contextualTranslationEndpoint = nil
            statusLabel.stringValue = "已清除服务地址。离线查词和收藏不受影响。"
            return
        }
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            statusLabel.stringValue = "请输入完整的 http 或 https 地址。"
            statusLabel.textColor = .systemRed
            return
        }
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        if scheme == "http", !["127.0.0.1", "localhost", "::1"].contains(host ?? "") {
            statusLabel.stringValue = "远程服务必须使用 HTTPS；HTTP 只允许本机开发地址。"
            statusLabel.textColor = .systemRed
            return
        }
        settings.contextualTranslationEndpoint = url
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "已保存。只有主动使用 AI 地道化、这样表达或语法问答时才会请求此服务。"
    }
}
