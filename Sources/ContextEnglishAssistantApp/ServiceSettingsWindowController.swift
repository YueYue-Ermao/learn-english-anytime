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
        window.title = "AI 服务（可选）"
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
            ? "当前使用推荐的无 API 模式：无模型费用，选中文字不会发送给模型服务。"
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
        let title = NSTextField(labelWithString: "先直接使用，需要时再配置 AI")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let detail = NSTextField(wrappingLabelWithString:
            "推荐保持留空：离线查词、近义词、发音、收藏和支持系统版本上的 Apple 本机翻译均可使用，无模型费用。限制是不能使用场景化改写、开放式语法问答和更地道的表达建议；需要这些能力时，再填写你自己的服务地址。"
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
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = "已切换到无 API 模式。离线查词、本机翻译、发音和收藏仍可使用。"
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
