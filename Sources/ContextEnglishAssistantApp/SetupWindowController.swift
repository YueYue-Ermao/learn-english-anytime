import AppKit

@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    var onRequestPermission: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onShowDemo: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let permissionStatusLabel = NSTextField(labelWithString: "")
    private let permissionDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let diagnosticLabel = NSTextField(wrappingLabelWithString: "监听诊断：尚未开始")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 490),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Context English Assistant"
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

    func present(isTrusted: Bool) {
        updatePermissionStatus(isTrusted: isTrusted)
        _ = NSApplication.shared.setActivationPolicy(.regular)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func updatePermissionStatus(isTrusted: Bool) {
        if isTrusted {
            permissionStatusLabel.stringValue = "✓ 辅助功能权限已开启"
            permissionStatusLabel.textColor = .systemGreen
            permissionDetailLabel.stringValue = "现在可以点击“显示测试浮窗”。随后到任意应用中拖动选中中文或英文，验证跨应用读取。"
        } else {
            permissionStatusLabel.stringValue = "● 辅助功能权限尚未开启"
            permissionStatusLabel.textColor = .systemOrange
            permissionDetailLabel.stringValue = "点击下方按钮，在系统设置中开启权限；返回本窗口后点击“重新检测权限”。"
        }
    }

    func dismissToMenuBar() {
        window?.orderOut(nil)
    }

    func updateDiagnostic(_ message: String) {
        diagnosticLabel.stringValue = "监听诊断：\(message)"
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onDismiss?()
        return false
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "英语选区助手已启动")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)

        let introLabel = NSTextField(wrappingLabelWithString:
            "应用主窗口用于单词本、好句收藏夹和语法问答；菜单栏组件会继续在后台运行，拖动选中中文或英文时显示释义、发音、收藏、本机翻译和可选 AI 地道化入口。"
        )
        introLabel.font = .systemFont(ofSize: 14)
        introLabel.textColor = .secondaryLabelColor

        permissionStatusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        permissionDetailLabel.font = .systemFont(ofSize: 13)
        permissionDetailLabel.textColor = .secondaryLabelColor

        diagnosticLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        diagnosticLabel.textColor = .secondaryLabelColor

        let pathTitleLabel = NSTextField(labelWithString: "当前运行的应用副本")
        pathTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let pathLabel = NSTextField(wrappingLabelWithString: Bundle.main.bundlePath)
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.isSelectable = true

        let copyWarning = NSTextField(wrappingLabelWithString:
            "请只保留一个副本，并先把它移到“应用程序”文件夹再授权。macOS 的辅助功能权限与具体应用副本有关。"
        )
        copyWarning.font = .systemFont(ofSize: 12, weight: .medium)
        copyWarning.textColor = .systemOrange

        let permissionButton = ActionButton(title: "打开辅助功能设置…") { [weak self] in
            self?.onRequestPermission?()
        }
        permissionButton.bezelStyle = .rounded

        let refreshButton = ActionButton(title: "重新检测权限") { [weak self] in
            self?.onRefresh?()
        }

        let demoButton = ActionButton(title: "显示测试浮窗") { [weak self] in
            self?.onShowDemo?()
        }

        let continueButton = ActionButton(title: "完成") { [weak self] in
            self?.onDismiss?()
        }
        continueButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [permissionButton, refreshButton, demoButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY

        let rootStack = NSStackView(views: [
            titleLabel,
            introLabel,
            separator(),
            permissionStatusLabel,
            permissionDetailLabel,
            diagnosticLabel,
            buttonRow,
            separator(),
            pathTitleLabel,
            pathLabel,
            copyWarning,
            flexibleSpacer(),
            continueButton
        ])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            introLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            permissionDetailLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            diagnosticLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            pathLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            copyWarning.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            continueButton.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor)
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func flexibleSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }
}
