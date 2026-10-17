#if canImport(AppKit)
import AppKit

/// The launcher's content: search field, up to eight result rows, a status line and key hints,
/// on a translucent rounded background that follows light/dark mode.
final class LauncherView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let rowHeight: CGFloat = 52
    static let rowSpacing: CGFloat = 2
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("ResultCell")

    private let viewModel: MainViewModel
    private let icons = IconCache()

    private let background = NSVisualEffectView()
    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private var tableHeight: NSLayoutConstraint!

    var onCancel: (() -> Void)?
    var onContentHeightChanged: (() -> Void)?

    init(viewModel: MainViewModel) {
        self.viewModel = viewModel
        super.init(frame: NSRect(x: 0, y: 0, width: LauncherWindowController.panelWidth, height: 120))
        buildViews()
        bindViewModel()
        applyStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Public

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        layoutSubtreeIfNeeded()
        return fittingSize.height
    }

    // MARK: - Building

    private func buildViews() {
        wantsLayer = true

        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        searchField.font = .systemFont(ofSize: 24)
        searchField.placeholderString = "앱 이름을 입력하세요"
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.lineBreakMode = .byTruncatingTail
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Result"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: Self.rowSpacing)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.refusesFirstResponder = true
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.style = .plain

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.isHidden = true
        tableHeight = scrollView.heightAnchor.constraint(equalToConstant: 0)
        tableHeight.isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .right
        hintLabel.stringValue = viewModel.hintText

        let footer = NSStackView(views: [statusLabel, hintLabel])
        footer.orientation = .horizontal
        footer.distribution = .fill
        footer.spacing = 12

        // Rows are 10 px wider than the text content on each side so the highlight frames the text, as on Windows.
        let stack = NSStackView(views: [searchField, scrollView, separator, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 10, bottom: 14, right: 10)
        stack.setCustomSpacing(12, after: searchField)
        stack.setCustomSpacing(12, after: scrollView)
        stack.setCustomSpacing(8, after: separator)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: LauncherWindowController.panelWidth),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        background.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private func bindViewModel() {
        viewModel.onResultsChanged = { [weak self] in self?.applyResults() }
        viewModel.onSelectionChanged = { [weak self] in self?.applySelection() }
        viewModel.onStatusChanged = { [weak self] in self?.applyStatus() }
        viewModel.onQueryReset = { [weak self] in self?.searchField.stringValue = "" }
    }

    // MARK: - View model -> view

    private func applyResults() {
        let count = viewModel.results.count
        tableView.reloadData()
        scrollView.isHidden = count == 0
        tableHeight.constant = count == 0 ? 0 : CGFloat(count) * (Self.rowHeight + Self.rowSpacing)
        applySelection()
        onContentHeightChanged?()
    }

    private func applySelection() {
        if let selected = viewModel.selectedIndex, selected < tableView.numberOfRows {
            tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
            tableView.scrollRowToVisible(selected)
        } else {
            tableView.deselectAll(nil)
        }
    }

    private func applyStatus() {
        statusLabel.stringValue = viewModel.statusText
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        viewModel.query = searchField.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            viewModel.moveSelection(+1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            viewModel.moveSelection(-1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            viewModel.launchSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.results.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < viewModel.results.count else {
            return nil
        }

        let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? ResultCellView
            ?? ResultCellView(identifier: Self.cellIdentifier)
        let result = viewModel.results[row]
        cell.configure(
            icon: icons.icon(forPath: result.entry.launchPath),
            name: result.name,
            detail: result.detail,
            kind: result.kind,
            shortcut: result.shortcutHint
        )
        return cell
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        if row >= 0 {
            viewModel.launchAt(row)
        }
    }
}
#endif
