import AppKit
import ContextEnglishCore

struct LookupPresentation {
    let title: String
    let pronunciation: String?
    let meaning: String
    let synonyms: [String]
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
        let button = ActionButton(
            title: "",
            symbolName: "character.book.closed.fill",
            style: .primary,
            bezelStyle: .circular,
            handler: onActivate
        )
        button.toolTip = "查看翻译、释义和发音"

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 20
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderColor = AppVisualTheme.border.cgColor
        effect.layer?.borderWidth = 1
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 34)
        ])

        let size = NSSize(width: 42, height: 42)
        installDisplayedContent(effect, size: size)
        positionPanel(size: size, near: snapshot.bounds)
        panel.orderFrontRegardless()
    }

    func showFull(_ presentation: LookupPresentation, near bounds: CGRect?) {
        let brandLabel = makeLabel(
            "Aa",
            font: .systemFont(ofSize: 15, weight: .bold),
            color: AppVisualTheme.accent
        )
        brandLabel.alignment = .center
        brandLabel.isSelectable = false
        let brand = RoundedSurfaceView(
            fillColor: AppVisualTheme.accentSoft,
            strokeColor: AppVisualTheme.accent.withAlphaComponent(0.20),
            radius: 11
        )
        brand.addSubview(brandLabel)
        brandLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brand.widthAnchor.constraint(equalToConstant: 42),
            brand.heightAnchor.constraint(equalToConstant: 42),
            brandLabel.centerXAnchor.constraint(equalTo: brand.centerXAnchor),
            brandLabel.centerYAnchor.constraint(equalTo: brand.centerYAnchor)
        ])

        let title = makeLabel(
            presentation.title,
            font: .systemFont(ofSize: 20, weight: .bold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 2

        let pronunciation = makeLabel(
            presentation.pronunciation ?? "",
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            color: .secondaryLabelColor
        )
        pronunciation.isHidden = presentation.pronunciation == nil

        let titleColumn = NSStackView(views: [title, pronunciation])
        titleColumn.orientation = .vertical
        titleColumn.alignment = .leading
        titleColumn.spacing = 3

        let close = ActionButton(
            title: "",
            symbolName: "xmark",
            style: .quiet
        ) { [weak self] in
            self?.hide()
        }
        close.toolTip = "关闭"

        let headerSpacer = flexibleSpacer()
        let header = NSStackView(views: [brand, titleColumn, headerSpacer, close])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let meaning = makeLabel(
            presentation.meaning,
            font: .systemFont(ofSize: 14.5, weight: .regular),
            color: .labelColor
        )
        meaning.maximumNumberOfLines = 10
        meaning.lineBreakMode = .byWordWrapping

        let meaningCard = RoundedSurfaceView()
        meaningCard.addSubview(meaning)
        meaning.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            meaning.leadingAnchor.constraint(equalTo: meaningCard.leadingAnchor, constant: 13),
            meaning.trailingAnchor.constraint(equalTo: meaningCard.trailingAnchor, constant: -13),
            meaning.topAnchor.constraint(equalTo: meaningCard.topAnchor, constant: 11),
            meaning.bottomAnchor.constraint(equalTo: meaningCard.bottomAnchor, constant: -11)
        ])

        let synonymHeading = makeLabel(
            "相关近义词 · 请按语境选用",
            font: .systemFont(ofSize: 11.5, weight: .semibold),
            color: .secondaryLabelColor
        )
        let synonymList = makeLabel(
            presentation.synonyms.joined(separator: "  ·  "),
            font: .systemFont(ofSize: 13.5, weight: .medium),
            color: AppVisualTheme.accent
        )
        synonymList.maximumNumberOfLines = 3
        synonymList.lineBreakMode = .byWordWrapping
        let synonymColumn = NSStackView(views: [synonymHeading, synonymList])
        synonymColumn.orientation = .vertical
        synonymColumn.alignment = .leading
        synonymColumn.spacing = 5
        synonymColumn.isHidden = presentation.synonyms.isEmpty
        let synonymCard = RoundedSurfaceView(
            fillColor: AppVisualTheme.accentSoft.withAlphaComponent(0.72),
            strokeColor: AppVisualTheme.accent.withAlphaComponent(0.12),
            radius: 11
        )
        synonymCard.isHidden = presentation.synonyms.isEmpty
        synonymCard.addSubview(synonymColumn)
        synonymColumn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            synonymColumn.leadingAnchor.constraint(equalTo: synonymCard.leadingAnchor, constant: 13),
            synonymColumn.trailingAnchor.constraint(equalTo: synonymCard.trailingAnchor, constant: -13),
            synonymColumn.topAnchor.constraint(equalTo: synonymCard.topAnchor, constant: 9),
            synonymColumn.bottomAnchor.constraint(equalTo: synonymCard.bottomAnchor, constant: -9)
        ])

        let note = makeLabel(
            presentation.note ?? "",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        note.maximumNumberOfLines = 3
        note.isHidden = presentation.note == nil

        let contextStatus = makeLabel(
            presentation.contextStatus ?? "",
            font: .systemFont(ofSize: 11.5, weight: .semibold),
            color: AppVisualTheme.accent
        )
        contextStatus.isHidden = presentation.contextStatus == nil

        let statusPill = RoundedSurfaceView(
            fillColor: AppVisualTheme.accentSoft,
            strokeColor: .clear,
            radius: 9
        )
        statusPill.isHidden = presentation.contextStatus == nil
        statusPill.addSubview(contextStatus)
        contextStatus.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contextStatus.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 9),
            contextStatus.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -9),
            contextStatus.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 4),
            contextStatus.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -4)
        ])

        let speak = ActionButton(title: "发音", symbolName: "speaker.wave.2.fill") { [weak self] in
            self?.onSpeak?(presentation.spokenText, presentation.spokenLocale)
        }
        let copy = ActionButton(title: "复制", symbolName: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(presentation.spokenText, forType: .string)
        }
        weak var favoriteButtonReference: ActionButton?
        let favoriteButton = ActionButton(
            title: presentation.isFavorite ? "已收藏" : "收藏",
            symbolName: presentation.isFavorite ? "star.fill" : "star"
        ) { [weak self] in
            guard let self,
                  let isFavorite = self.onToggleFavorite?(presentation.favoriteDraft) else { return }
            favoriteButtonReference?.title = isFavorite ? "已收藏" : "收藏"
            favoriteButtonReference?.image = AppVisualTheme.symbol(isFavorite ? "star.fill" : "star")
        }
        favoriteButtonReference = favoriteButton

        weak var directDisplayButtonReference: ActionButton?
        let directDisplayButton = ActionButton(
            title: presentation.directDisplayEnabled ? "自动展示：开" : "自动展示：关",
            symbolName: presentation.directDisplayEnabled ? "eye.fill" : "eye.slash",
            style: .quiet
        ) { [weak self] in
            guard let self, let enabled = self.onToggleDirectDisplay?() else { return }
            directDisplayButtonReference?.title = enabled ? "自动展示：开" : "自动展示：关"
            directDisplayButtonReference?.image = AppVisualTheme.symbol(enabled ? "eye.fill" : "eye.slash")
        }
        directDisplayButtonReference = directDisplayButton
        let pause = ActionButton(
            title: "暂停 1 小时",
            symbolName: "moon.zzz",
            style: .quiet
        ) { [weak self] in
            self?.onPauseForOneHour?()
        }

        let primaryControls = NSStackView(views: [speak, copy, favoriteButton])
        primaryControls.orientation = .horizontal
        primaryControls.alignment = .centerY
        primaryControls.spacing = 8

        var translationControlViews: [NSView] = []
        if let translationDraft = presentation.localTranslationDraft,
           let translationActionTitle = presentation.localTranslationActionTitle {
            let translate = ActionButton(
                title: translationActionTitle,
                symbolName: "arrow.left.arrow.right",
                style: .primary
            ) { [weak self] in
                self?.onRequestLocalTranslation?(translationDraft)
            }
            translationControlViews.append(translate)
        }
        if let translationDraft = presentation.aiTranslationDraft,
           let translationActionTitle = presentation.aiTranslationActionTitle {
            let translate = ActionButton(
                title: translationActionTitle,
                symbolName: "sparkles"
            ) { [weak self] in
                self?.onRequestAITranslation?(translationDraft)
            }
            translate.toolTip = "使用已配置的 AI 服务，可能产生 API 费用"
            translationControlViews.append(translate)
        }
        let translationControls = NSStackView(views: translationControlViews)
        translationControls.orientation = .horizontal
        translationControls.alignment = .centerY
        translationControls.spacing = 8

        let secondaryControls = NSStackView(views: [directDisplayButton, pause])
        secondaryControls.orientation = .horizontal
        secondaryControls.alignment = .centerY
        secondaryControls.spacing = 8

        var contentViews: [NSView] = [
            header,
            statusPill,
            meaningCard,
            synonymCard,
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
        content.spacing = 11
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 13, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderColor = AppVisualTheme.border.cgColor
        effect.layer?.borderWidth = 1
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 448),
            header.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            titleColumn.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            meaningCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            synonymCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            note.widthAnchor.constraint(lessThanOrEqualToConstant: 416)
        ])

        let fittingSize = content.fittingSize
        let size = NSSize(
            width: 448,
            height: max(196, min(540, fittingSize.height))
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

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
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
