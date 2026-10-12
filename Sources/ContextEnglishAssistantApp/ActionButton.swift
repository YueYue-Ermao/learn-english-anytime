import AppKit

enum ActionButtonStyle {
    case primary
    case secondary
    case quiet
    case danger
}

final class ActionButton: NSButton {
    private let handler: () -> Void

    init(
        title: String,
        symbolName: String? = nil,
        style: ActionButtonStyle = .secondary,
        bezelStyle: NSButton.BezelStyle? = nil,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = bezelStyle ?? .rounded
        target = self
        action = #selector(invokeHandler)
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 12.5, weight: style == .primary ? .semibold : .medium)
        controlSize = .regular
        if let symbolName {
            image = AppVisualTheme.symbol(symbolName)
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            imageHugsTitle = true
        }
        apply(style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func invokeHandler() {
        handler()
    }

    private func apply(_ style: ActionButtonStyle) {
        switch style {
        case .primary:
            isBordered = true
            bezelStyle = .rounded
            bezelColor = AppVisualTheme.accent
            contentTintColor = .white
        case .secondary:
            isBordered = true
            bezelStyle = .rounded
            contentTintColor = .labelColor
        case .quiet:
            isBordered = false
            contentTintColor = .secondaryLabelColor
        case .danger:
            isBordered = true
            bezelStyle = .rounded
            contentTintColor = .systemRed
        }
    }
}
