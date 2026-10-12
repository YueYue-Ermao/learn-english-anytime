import AppKit
import ContextEnglishCore

struct LookupPresentation {
    let title: String
    let pronunciation: String?
    let meaning: String
    let note: String?
    let spokenText: String
    let spokenLocale: String
    let favoriteDraft: FavoriteDraft
    let isFavorite: Bool
    let directDisplayEnabled: Bool
    let contextStatus: String?
    let localTranslationDraft: TranslationDraft?
    let localTranslationActionTitle: String?
    let aiTranslationDraft: TranslationDraft?
    let aiTranslationActionTitle: String?
}

@MainActor
final class LookupPanelController {
    var onSpeak: ((String, String) -> Void)?
    var onPauseForOneHour: (() -> Void)?
    var onToggleFavorite: ((FavoriteDraft) -> Bool?)?
    var onToggleDirectDisplay: (() -> Bool)?
    var onRequestLocalTranslation: ((TranslationDraft) -> Void)?
    var onRequestAITranslation: ((TranslationDraft) -> Void)?
    var onCancelTranslation: (() -> Void)?

    private let panel: NSPanel
    private let rootView = NSView()
    private weak var displayedContent: NSView?
    private weak var translationHostView: NSView?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = rootView
    }

    func installTranslationHost(_ view: NSView) {
        translationHostView?.removeFromSuperview()
        translationHostView = view
        rootView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            view.topAnchor.constraint(equalTo: rootView.topAnchor),
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func showHint(for snapshot: SelectionSnapshot, onActivate: @escaping () -> Void) {
        let button = ActionButton(title: "A", bezelStyle: .circular, handler: onActivate)
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = "查看翻译、释义和发音"

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])

        let size = NSSize(width: 36, height: 36)
        installDisplayedContent(effect, size: size)
        positionPanel(size: size, near: snapshot.bounds)
        panel.orderFrontRegardless()
    }

    func showFull(_ presentation: LookupPresentation, near bounds: CGRect?) {
        let title = makeLabel(
            presentation.title,
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 2

        let pronunciation = makeLabel(
            presentation.pronunciation ?? "",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        pronunciation.isHidden = presentation.pronunciation == nil

        let meaning = makeLabel(
            presentation.meaning,
            font: .systemFont(ofSize: 14),
            color: .labelColor
        )
        meaning.maximumNumberOfLines = 10

        let note = makeLabel(
            presentation.note ?? "",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        note.maximumNumberOfLines = 3
        note.isHidden = presentation.note == nil

        let contextStatus = makeLabel(
            presentation.contextStatus ?? "",
            font: .systemFont(ofSize: 11, weight: .medium),
            color: presentation.contextStatus == nil ? .secondaryLabelColor : .systemBlue
        )
        contextStatus.isHidden = presentation.contextStatus == nil

        let speak = ActionButton(title: "▶ 发音") { [weak self] in
            self?.onSpeak?(presentation.spokenText, presentation.spokenLocale)
        }
        let copy = ActionButton(title: "复制") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(presentation.spokenText, forType: .string)
        }
        weak var favoriteButtonReference: ActionButton?
        let favoriteButton = ActionButton(
            title: presentation.isFavorite ? "★ 已收藏" : "☆ 收藏"
        ) { [weak self] in
            guard let self,
                  let isFavorite = self.onToggleFavorite?(presentation.favoriteDraft) else { return }
            favoriteButtonReference?.title = isFavorite ? "★ 已收藏" : "☆ 收藏"
        }
        favoriteButtonReference = favoriteButton

        weak var directDisplayButtonReference: ActionButton?
        let directDisplayButton = ActionButton(
            title: presentation.directDisplayEnabled ? "选中即展示：开" : "选中即展示：关"
        ) { [weak self] in
            guard let self, let enabled = self.onToggleDirectDisplay?() else { return }
            directDisplayButtonReference?.title = enabled ? "选中即展示：开" : "选中即展示：关"
        }
        directDisplayButtonReference = directDisplayButton
        let pause = ActionButton(title: "暂停 1 小时") { [weak self] in
            self?.onPauseForOneHour?()
        }
        let close = ActionButton(title: "关闭") { [weak self] in
            self?.hide()
        }

        let primaryControls = NSStackView(views: [speak, copy, favoriteButton])
        primaryControls.orientation = .horizontal
        primaryControls.alignment = .centerY
        primaryControls.spacing = 8

        var translationControlViews: [NSView] = []
        if let translationDraft = presentation.localTranslationDraft,
           let translationActionTitle = presentation.localTranslationActionTitle {
            let translate = ActionButton(title: translationActionTitle) { [weak self] in
                self?.onRequestLocalTranslation?(translationDraft)
            }
            translate.bezelColor = .controlAccentColor
            translationControlViews.append(translate)
        }
        if let translationDraft = presentation.aiTranslationDraft,
           let translationActionTitle = presentation.aiTranslationActionTitle {
            let translate = ActionButton(title: translationActionTitle) { [weak self] in
                self?.onRequestAITranslation?(translationDraft)
            }
            translate.toolTip = "使用已配置的 AI 服务，可能产生 API 费用"
            translationControlViews.append(translate)
        }
        let translationControls = NSStackView(views: translationControlViews)
        translationControls.orientation = .horizontal
        translationControls.alignment = .centerY
        translationControls.spacing = 8

        let secondaryControls = NSStackView(views: [directDisplayButton, pause, close])
        secondaryControls.orientation = .horizontal
        secondaryControls.alignment = .centerY
        secondaryControls.spacing = 8

        var contentViews: [NSView] = [
            title,
            pronunciation,
            contextStatus,
            meaning,
            note,
            primaryControls
        ]
        if !translationControlViews.isEmpty {
            contentViews.append(translationControls)
        }
        contentViews.append(secondaryControls)
        let content = NSStackView(views: contentViews)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 388),
            meaning.widthAnchor.constraint(lessThanOrEqualToConstant: 388),
            note.widthAnchor.constraint(lessThanOrEqualToConstant: 388),
            contextStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 388)
        ])

        let fittingSize = content.fittingSize
        let size = NSSize(
            width: max(320, min(420, fittingSize.width)),
            height: max(170, min(500, fittingSize.height))
        )
        installDisplayedContent(effect, size: size)
        positionPanel(size: size, near: bounds)
        panel.orderFrontRegardless()
    }

    func showLoading(title: String, statusMessage: String, near bounds: CGRect?) {
        let titleLabel = makeLabel(
            title,
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .labelColor
        )
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)
        let status = makeLabel(
            statusMessage,
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor
        )
        let row = NSStackView(views: [progress, status])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let cancel = ActionButton(title: "取消") { [weak self] in
            self?.onCancelTranslation?()
            self?.hide()
        }
        let content = NSStackView(views: [titleLabel, row, cancel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 328)
        ])

        let size = NSSize(width: 340, height: 132)
        installDisplayedContent(effect, size: size)
        positionPanel(size: size, near: bounds)
        panel.orderFrontRegardless()
    }

    func showMessage(title: String, message: String, near bounds: CGRect?) {
        let titleLabel = makeLabel(
            title,
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .labelColor
        )
        let messageLabel = makeLabel(
            message,
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor
        )
        messageLabel.maximumNumberOfLines = 5
        let close = ActionButton(title: "关闭") { [weak self] in self?.hide() }
        let content = NSStackView(views: [titleLabel, messageLabel, close])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 328),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 328)
        ])
        let fittingSize = content.fittingSize
        let size = NSSize(
            width: max(320, min(380, fittingSize.width)),
            height: max(140, min(280, fittingSize.height))
        )
        installDisplayedContent(effect, size: size)
        positionPanel(size: size, near: bounds)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func makeLabel(_ value: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = font
        label.textColor = color
        label.isSelectable = true
        label.drawsBackground = false
        return label
    }

    private func installDisplayedContent(_ view: NSView, size: NSSize) {
        displayedContent?.removeFromSuperview()
        displayedContent = view
        if let translationHostView {
            rootView.addSubview(view, positioned: .below, relativeTo: translationHostView)
        } else {
            rootView.addSubview(view)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            view.topAnchor.constraint(equalTo: rootView.topAnchor),
            view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
        panel.setContentSize(size)
    }

    private func positionPanel(size: NSSize, near bounds: CGRect?) {
        let anchor = bounds ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let preferredOrigin = NSPoint(
            x: anchor.maxX + 8,
            y: anchor.minY - size.height - 8
        )

        let screen = NSScreen.screens.first { $0.visibleFrame.contains(anchor.center) }
            ?? NSScreen.screens.first { $0.visibleFrame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            panel.setFrameOrigin(preferredOrigin)
            return
        }

        let clampedX = min(
            max(preferredOrigin.x, visibleFrame.minX + 8),
            visibleFrame.maxX - size.width - 8
        )
        let clampedY = min(
            max(preferredOrigin.y, visibleFrame.minY + 8),
            visibleFrame.maxY - size.height - 8
        )
        panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
