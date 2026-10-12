import AppKit

final class ActionButton: NSButton {
    private let handler: () -> Void

    init(title: String, bezelStyle: NSButton.BezelStyle = .rounded, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = bezelStyle
        target = self
        action = #selector(invokeHandler)
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func invokeHandler() {
        handler()
    }
}
