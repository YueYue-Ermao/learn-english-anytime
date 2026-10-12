import AppKit

@MainActor
final class WordbookWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onSpeak: ((String, String) -> Void)?

    private let repository: FavoritesRepository
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let tableView = NSTableView()
    private var items: [FavoriteItem] = []

    init(repository: FavoritesRepository) {
        self.repository = repository
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "我的单词表"
        window.minSize = NSSize(width: 620, height: 360)
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
        reload()
        _ = NSApplication.shared.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let item = items[row]
        let value: String
        switch identifier.rawValue {
        case "kind":
            value = item.kind.displayName
        case "source":
            value = item.sourceText
        case "meaning":
            value = item.meaning
        case "date":
            value = Self.dateFormatter.string(from: item.updatedAt)
        default:
            value = ""
        }

        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        if identifier.rawValue == "kind" || identifier.rawValue == "date" {
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 12)
        }
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        searchField.placeholderString = "搜索单词、词组、句子或释义"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2

        addColumn(identifier: "kind", title: "类型", width: 70)
        addColumn(identifier: "source", title: "内容", width: 190)
        addColumn(identifier: "meaning", title: "释义", width: 350)
        addColumn(identifier: "date", title: "收藏时间", width: 110)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 30
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder

        let speakButton = ActionButton(title: "▶ 朗读") { [weak self] in
            self?.speakSelected()
        }
        let copyButton = ActionButton(title: "复制") { [weak self] in
            self?.copySelected()
        }
        let removeButton = ActionButton(title: "取消收藏") { [weak self] in
            self?.removeSelected()
        }
        let closeButton = ActionButton(title: "关闭") { [weak self] in
            self?.window?.performClose(nil)
        }
        let controls = NSStackView(views: [speakButton, copyButton, removeButton, closeButton])
        controls.orientation = .horizontal
        controls.spacing = 8

        let header = NSStackView(views: [searchField, countLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let root = NSStackView(views: [header, scrollView, statusLabel, controls])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            countLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
    }

    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = min(width, 60)
        tableView.addTableColumn(column)
    }

    private func reload() {
        do {
            items = try repository.fetch(search: searchField.stringValue)
            tableView.reloadData()
            countLabel.stringValue = "共 \(items.count) 条"
            statusLabel.stringValue = items.isEmpty
                ? (searchField.stringValue.isEmpty ? "还没有收藏内容。可在查询浮窗中点击“☆ 收藏”。" : "没有匹配结果。")
                : "收藏保存在本机，不会自动上传。"
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func selectedItem() -> FavoriteItem? {
        let row = tableView.selectedRow
        guard items.indices.contains(row) else {
            statusLabel.stringValue = "请先选择一条收藏。"
            return nil
        }
        return items[row]
    }

    private func speakSelected() {
        guard let item = selectedItem() else { return }
        let locale = item.sourceLanguage == "zh-Hans" ? "zh-CN" : "en-US"
        onSpeak?(item.spokenText, locale)
    }

    private func copySelected() {
        guard let item = selectedItem() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.sourceText, forType: .string)
        statusLabel.stringValue = "已复制“\(item.sourceText)”。"
    }

    private func removeSelected() {
        guard let item = selectedItem() else { return }
        do {
            try repository.delete(id: item.id)
            reload()
            statusLabel.stringValue = "已取消收藏“\(item.sourceText)”。"
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
