import AppKit
import UniformTypeIdentifiers

/// All preferences and dictionary edits stay on this Mac.
final class PreferencesController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: DictionaryStore
    private var displayedRows: [DictionaryRow] = []
    private let searchField = NSSearchField()
    private let table = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "输入 1–4 位五笔编码，查看全部同码词条。")
    private let codeField = NSTextField()
    private let wordField = NSTextField()
    private let deleteButton = NSButton(title: "删除所选词条", target: nil, action: nil)
    private let restoreButton = NSButton(title: "恢复所选词条", target: nil, action: nil)
    private let autoCommitCheckbox = NSButton(checkboxWithTitle: "四码只有一个候选时自动上屏", target: nil, action: nil)
    private let moveUpButton = NSButton(title: "上移", target: nil, action: nil)
    private let moveDownButton = NSButton(title: "下移", target: nil, action: nil)

    init(store: DictionaryStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "搜猫五笔 · 偏好设置"
        window.minSize = NSSize(width: 760, height: 600)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    func show() {
        do { try store.reloadIfChanged() } catch { present(error) }
        autoCommitCheckbox.state = UserDefaults.standard.bool(forKey: "autoCommit") ? .on : .off
        refreshRows()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        guard let root = window?.contentView else { return }
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.setAccessibilityIdentifier("preferences.tabs")
        for (name, view) in [("常规", generalView()), ("高级设置", advancedView()), ("关于", aboutView())] {
            if let stack = view.subviews.first as? NSStackView {
                for row in stack.arrangedSubviews {
                    row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                }
            }
            let item = NSTabViewItem(identifier: name)
            item.label = name
            item.view = view
            tabs.addTabViewItem(item)
        }
        root.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
    }

    private func generalView() -> NSView {
        let (view, stack) = page()
        stack.addArrangedSubview(heading("让每一次输入，都留在本机"))
        stack.addArrangedSubview(note("搜猫五笔完全离线运行。词库、造词和删除记录仅保存在本机。"))
        addSpace(16, to: stack)
        autoCommitCheckbox.target = self
        autoCommitCheckbox.action = #selector(changeAutoCommit(_:))
        autoCommitCheckbox.setAccessibilityIdentifier("settings.autoCommit")
        stack.addArrangedSubview(autoCommitCheckbox)
        stack.addArrangedSubview(note("标点跟随中英文模式。中文 / 输出顿号；数字后紧接的句点仅一次输出英文点。"))
        addSpace(14, to: stack)
        stack.addArrangedSubview(heading("输入快捷键", size: 14))
        stack.addArrangedSubview(note("空格：首选词　　1–5：选词　　;：第二候选词\n【 / 】、− / = 或 Page Up / Page Down：翻页\n退格：修改编码　　Esc：取消　　Return：上屏原始编码\nShift：有编码时上屏原始编码并切到英文；无编码时切换中英文"))
        stack.addArrangedSubview(note("每页横排 5 词；z 代替任意一位 a–y，通配及联想候选附带实际编码。\n含 z 的四码等待选词。Shift 切换时屏幕短暂显示“中文”或“ABC”。\n单击 Ctrl：本次临时全拼；有编码时保留编码，空闲时对下一次输入有效。"))
        return view
    }

    private func advancedView() -> NSView {
        let (view, stack) = page()
        stack.spacing = 8
        stack.addArrangedSubview(heading("词库管理"))
        stack.addArrangedSubview(note("按编码管理重码词，选中词条后上移或下移调整候选顺序。删除后可恢复。"))
        searchField.placeholderString = "输入五笔编码，例如：gggg"
        searchField.delegate = self
        searchField.setAccessibilityIdentifier("dictionary.search")
        searchField.setAccessibilityLabel("查询五笔编码")
        searchField.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(searchField)

        for (identifier, title, width) in [("word", "词语", CGFloat(300)), ("source", "来源", CGFloat(180)), ("status", "状态", CGFloat(130))] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = identifier == "word" ? 160 : 100
            table.addTableColumn(column)
        }
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection = false
        table.setAccessibilityIdentifier("dictionary.entries")
        table.setAccessibilityLabel("当前编码的词条")
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = table
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        stack.addArrangedSubview(scroll)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("dictionary.status")
        stack.addArrangedSubview(statusLabel)

        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.setAccessibilityIdentifier("dictionary.delete")
        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)
        restoreButton.setAccessibilityIdentifier("dictionary.restore")
        moveUpButton.target = self
        moveUpButton.action = #selector(moveWordUp)
        moveUpButton.setAccessibilityIdentifier("dictionary.moveUp")
        moveDownButton.target = self
        moveDownButton.action = #selector(moveWordDown)
        moveDownButton.setAccessibilityIdentifier("dictionary.moveDown")
        stack.addArrangedSubview(horizontal([moveUpButton, moveDownButton, deleteButton, restoreButton], spacerAtEnd: true))
        stack.addArrangedSubview(NSBox.separator())
        codeField.placeholderString = "编码（1–4 位）"
        codeField.setAccessibilityLabel("新词编码")
        codeField.setAccessibilityIdentifier("dictionary.newCode")
        codeField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        wordField.placeholderString = "输入要创建的词语"
        wordField.setAccessibilityLabel("新词词语")
        wordField.setAccessibilityIdentifier("dictionary.newWord")
        wordField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let addButton = NSButton(title: "造词", target: self, action: #selector(addWord))
        addButton.setAccessibilityIdentifier("dictionary.add")
        stack.addArrangedSubview(horizontal([codeField, wordField, addButton]))
        stack.addArrangedSubview(note("手动指定五笔编码。保存后可直接使用，无需重启输入法。"))
        let importButton = NSButton(title: "导入用户词库…", target: self, action: #selector(importChanges))
        let exportButton = NSButton(title: "导出用户词库…", target: self, action: #selector(exportChanges))
        importButton.setAccessibilityIdentifier("dictionary.import")
        exportButton.setAccessibilityIdentifier("dictionary.export")
        stack.addArrangedSubview(horizontal([importButton, exportButton], spacerAtEnd: true))
        stack.addArrangedSubview(note("JSON 包含造词、删除记录和词序。导入合并词条，同码词序采用导入值。"))
        updateButtons()
        return view
    }

    private func aboutView() -> NSView {
        let (view, stack) = page()
        stack.addArrangedSubview(heading("搜猫五笔", size: 28))
        stack.addArrangedSubview(note("独立开发的 macOS 原生五笔输入法"))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.0"
        stack.addArrangedSubview(note("版本 \(version) · 完全离线"))
        addSpace(16, to: stack)
        stack.addArrangedSubview(heading("你的词库，由你决定", size: 16))
        stack.addArrangedSubview(note("内置 \(store.baseCount.formatted()) 条编码与词语配对。\n基础数据来自本机搜狗五笔词库；应用与输入引擎为独立实现。\n搜猫五笔与搜狗公司无隶属关系。"))
        stack.addArrangedSubview(note("应用不提供账号、云候选、遥测或在线更新。\n联网能力由系统级进程限制禁用。"))
        addSpace(12, to: stack)
        stack.addArrangedSubview(heading("用户词库位置", size: 14))
        let pathLabel = note(store.userURL.path)
        pathLabel.isSelectable = true
        pathLabel.lineBreakMode = .byCharWrapping
        stack.addArrangedSubview(pathLabel)
        stack.addArrangedSubview(note("添加输入法：系统设置 → 键盘 → 文本输入 → 编辑 → ＋ → 简体中文。\n如果未立即显示，请注销后重新登录。"))
        return view
    }

    private func page() -> (NSView, NSStackView) {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])
        // A vertical stack with leading alignment needs explicit full-width rows.
        stack.distribution = .fill
        return (view, stack)
    }

    private func heading(_ value: String, size: CGFloat = 20) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: size, weight: .semibold)
        return label
    }

    private func note(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        return label
    }

    private func addSpace(_ height: CGFloat, to stack: NSStackView) {
        let space = NSView()
        space.heightAnchor.constraint(equalToConstant: height).isActive = true
        stack.addArrangedSubview(space)
    }

    private func horizontal(_ views: [NSView], spacerAtEnd: Bool = false) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        if spacerAtEnd {
            let space = NSView()
            space.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(space)
        }
        return row
    }

    @objc private func changeAutoCommit(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "autoCommit")
    }

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === searchField { refreshRows() }
    }

    private var query: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func refreshRows() {
        displayedRows = store.rows(for: query)
        table.reloadData()
        if query.isEmpty {
            statusLabel.stringValue = "输入 1–4 位五笔编码，查看全部同码词条。"
        } else if query.count > 4 || !query.utf8.allSatisfy({ $0 >= 97 && $0 <= 121 }) {
            statusLabel.stringValue = "编码应为 1–4 个英文字母 a–y。"
        } else {
            let deleted = displayedRows.filter { $0.deleted }.count
            statusLabel.stringValue = "\(query) · 共 \(displayedRows.count) 条，\(deleted) 条已删除"
            codeField.stringValue = query
        }
        updateButtons()
    }

    private var selectedRow: DictionaryRow? {
        guard displayedRows.indices.contains(table.selectedRow) else { return nil }
        return displayedRows[table.selectedRow]
    }

    private func updateButtons() {
        deleteButton.isEnabled = selectedRow.map { !$0.deleted } ?? false
        restoreButton.isEnabled = selectedRow?.deleted ?? false
        let visible = displayedRows.filter { !$0.deleted }.map { $0.word }
        let position = selectedRow.flatMap { $0.deleted ? nil : visible.firstIndex(of: $0.word) }
        moveUpButton.isEnabled = position.map { $0 > 0 } ?? false
        moveDownButton.isEnabled = position.map { $0 + 1 < visible.count } ?? false
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    func numberOfRows(in tableView: NSTableView) -> Int { displayedRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayedRows.indices.contains(row), let column = tableColumn else { return nil }
        let entry = displayedRows[row]
        let identifier = column.identifier
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = identifier
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let value: String
        switch identifier.rawValue {
        case "word": value = entry.word
        case "source": value = entry.source
        default: value = entry.deleted ? "已删除" : "可用"
        }
        cell.textField?.stringValue = value
        cell.textField?.textColor = entry.deleted ? .secondaryLabelColor : .labelColor
        cell.toolTip = value
        return cell
    }

    @objc private func moveWordUp() { moveSelected(offset: -1) }
    @objc private func moveWordDown() { moveSelected(offset: 1) }
    private func moveSelected(offset: Int) {
        guard let row = selectedRow, !row.deleted else { return }
        performChange { try store.move(code: row.code, word: row.word, offset: offset) }
        if let index = displayedRows.firstIndex(where: { $0.word == row.word }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        updateButtons()
    }

    @objc private func deleteSelected() {
        guard let row = selectedRow else { return }
        performChange { try store.remove(code: row.code, word: row.word) }
    }

    @objc private func restoreSelected() {
        guard let row = selectedRow else { return }
        performChange { try store.restore(code: row.code, word: row.word) }
    }

    @objc private func addWord() {
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let word = wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        performChange {
            try store.add(code: code, word: word)
            searchField.stringValue = code
            wordField.stringValue = ""
        }
    }

    private func performChange(_ change: () throws -> Void) {
        do {
            try store.reloadIfChanged()
            try change()
            refreshRows()
        } catch { present(error) }
    }

    @objc private func exportChanges() {
        let panel = NSSavePanel()
        panel.title = "导出用户词库"
        panel.nameFieldStringValue = "搜猫五笔用户词库.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.reloadIfChanged()
            try store.exportChanges(to: url)
        } catch { present(error) }
    }

    @objc private func importChanges() {
        let panel = NSOpenPanel()
        panel.title = "导入用户词库"
        panel.message = "选择搜猫五笔导出的 JSON 文件，将造词、删除记录与词序合并到本机；同码词序采用导入值。"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performChange { try store.importChanges(from: url) }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "词库操作未完成"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        if let window, window.isVisible { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}

private extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
