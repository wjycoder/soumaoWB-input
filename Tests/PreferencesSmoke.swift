import AppKit

/// Exercises the actual preferences controls without starting an IMK server.
/// Build with DictionaryStore.swift and Preferences.swift, then run from the repo.
@main struct PreferencesSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let build = root.appendingPathComponent("build")
        let userDirectory = build.appendingPathComponent("ui-test-user")
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let userURL = userDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let baseURL = root.appendingPathComponent("Resources/wubi.tsv")
        let store = try DictionaryStore(baseURL: baseURL, userURL: userURL)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let controller = PreferencesController(store: store)
        controller.show()
        let window = controller.window!
        defer { window.orderOut(nil) }
        // Exercise the smallest supported window, where truncation is most likely.
        window.setContentSize(NSSize(width: 760, height: 578))
        let content = window.contentView!
        var checks = 0

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
            print("PASS: \(message)")
        }

        func descendant(_ identifier: String, in view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == identifier { return view }
            for child in view.subviews {
                if let match = descendant(identifier, in: child) { return match }
            }
            return nil
        }

        func control<T: NSView>(_ identifier: String, as type: T.Type) -> T {
            guard let found = descendant(identifier, in: content) as? T else {
                fatalError("Missing control \(identifier)")
            }
            return found
        }

        func settle() {
            content.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
            content.layoutSubtreeIfNeeded()
        }

        func screenshot(_ name: String) throws {
            settle()
            guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                fatalError("Cannot create AppKit bitmap")
            }
            content.cacheDisplay(in: content.bounds, to: bitmap)
            // NSView capture has transparency where the NSWindow normally paints
            // its background. Composite it before exporting an inspectable PNG.
            let flattened = NSImage(size: content.bounds.size)
            flattened.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: content.bounds).fill()
            let captured = NSImage(size: content.bounds.size)
            captured.addRepresentation(bitmap)
            captured.draw(in: content.bounds, from: .zero, operation: .sourceOver, fraction: 1)
            flattened.unlockFocus()
            guard let tiff = flattened.tiffRepresentation,
                  let result = NSBitmapImageRep(data: tiff),
                  let png = result.representation(using: .png, properties: [:]) else {
                fatalError("Cannot encode AppKit bitmap")
            }
            let url = build.appendingPathComponent(name)
            try png.write(to: url)
            print("SCREENSHOT: \(url.path)")
        }

        func click(_ button: NSButton) {
            check(button.isEnabled, "button enabled: \(button.title)")
            check(app.sendAction(button.action!, to: button.target, from: button),
                  "native target/action delivered: \(button.title)")
            settle()
        }

        let tabs = control("preferences.tabs", as: NSTabView.self)
        check(tabs.tabViewItems.map { $0.label } == ["常规", "关于"], "general and about preferences tabs")
        tabs.selectTabViewItem(at: 0)
        check(descendant("dictionary.search", in: tabs.selectedTabViewItem!.view!) != nil, "dictionary management is on general page")
        try screenshot("preferences-general.png")
        settle()
        let search = control("dictionary.search", as: NSSearchField.self)
        let table = control("dictionary.entries", as: NSTableView.self)
        search.stringValue = "khlg"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        settle()
        let original = store.candidates(for: "khlg")
        check(original.contains("中国") && original.contains("跑车"), "full dictionary contains 中国 and 跑车 at khlg")
        check(table.numberOfRows == store.rows(for: "khlg").count, "search populates real candidate table")
        let chinaRow = store.rows(for: "khlg").firstIndex { $0.word == "中国" }!
        let chinaCell = table.view(atColumn: 0, row: chinaRow, makeIfNecessary: true) as? NSTableCellView
        check(chinaCell?.textField?.stringValue == "中国", "table renders 中国")
        try screenshot("preferences-dictionary.png")

        // Compare every other source code before/after a real delete-button action.
        let source = try String(contentsOf: baseURL, encoding: .utf8)
        let allCodes = Set(source.split(separator: "\n").dropFirst().map { String($0.split(separator: "\t")[0]) })
        var before: [String: [String]] = [:]
        for code in allCodes { before[code] = store.candidates(for: code) }
        table.selectRowIndexes(IndexSet(integer: chinaRow), byExtendingSelection: false)
        settle()
        click(control("dictionary.delete", as: NSButton.self))
        check(!store.candidates(for: "khlg").contains("中国"), "delete control removes 中国 at khlg")
        check(store.candidates(for: "khlg") == original.filter { $0 != "中国" }, "same-code neighbors remain intact")
        check(allCodes.filter { $0 != "khlg" }.allSatisfy { store.candidates(for: $0) == before[$0] },
              "all other source codes unchanged by deletion")
        check(store.rows(for: "khlg").contains { $0.word == "中国" && $0.deleted }, "deleted row stays visible for restore")
        table.selectRowIndexes(IndexSet(integer: chinaRow), byExtendingSelection: false)
        settle()
        click(control("dictionary.restore", as: NSButton.self))
        check(store.candidates(for: "khlg") == original, "restore control restores original candidates and order")

        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        settle()
        let movedWord = store.rows(for: "khlg")[1].word
        click(control("dictionary.moveUp", as: NSButton.self))
        check(store.candidates(for: "khlg").first == movedWord, "up button changes first candidate")
        check(table.selectedRow == 0, "selection follows moved word")
        check(!control("dictionary.moveUp", as: NSButton.self).isEnabled, "up disabled at first row")
        try screenshot("preferences-reordered.png")
        click(control("dictionary.moveDown", as: NSButton.self))
        check(store.candidates(for: "khlg") == original, "down button restores candidate order")

        control("dictionary.newCode", as: NSTextField.self).stringValue = "aaaa"
        control("dictionary.newWord", as: NSTextField.self).stringValue = "搜猫离线测试"
        click(control("dictionary.add", as: NSButton.self))
        check(search.stringValue == "aaaa", "add control switches search to new code")
        check(store.candidates(for: "aaaa").first == "搜猫离线测试", "add control creates first candidate")
        check(control("dictionary.newWord", as: NSTextField.self).stringValue.isEmpty, "successful add clears word field")
        let restarted = try DictionaryStore(baseURL: baseURL, userURL: userURL)
        check(restarted.candidates(for: "aaaa").first == "搜猫离线测试", "new word survives store restart")
        check(restarted.candidates(for: "khlg") == original, "restored dictionary survives store restart")
        try screenshot("preferences-custom-word.png")

        tabs.selectTabViewItem(at: 1)
        try screenshot("preferences-about.png")
        for item in tabs.tabViewItems {
            tabs.selectTabViewItem(item)
            settle()
            let page = item.view!
            let stack = page.subviews.first as! NSStackView
            check(stack.frame.minY >= 0 && stack.frame.maxY <= page.bounds.height + 1,
                  "\(item.label) content fits smallest supported window")
        }
        let candidate = CandidatePanel()
        var chosen = 0
        candidate.show(candidates: [InputCandidate(word: "工", code: "a", completion: false)] + Array(store.matchingCandidates(for: "lwt").prefix(4)), anchor: NSRect(x: 100, y: 100, width: 1, height: 20)) { chosen = $0 }
        settle()
        let candidateWindow = app.windows.first { $0.accessibilityIdentifier() == "soumao.candidates" }!
        let candidates = candidateWindow.contentView as! NSStackView
        check(candidates.orientation == .horizontal, "candidates arranged horizontally")
        check(candidates.arrangedSubviews.count == 5 && candidates.arrangedSubviews.allSatisfy { $0 is NSButton }, "only five candidate buttons, no title/code/paging labels")
        check(!candidateWindow.canBecomeKey, "candidate window does not steal input focus")
        let buttons = candidates.arrangedSubviews as! [NSButton]
        check(zip(buttons, buttons.dropFirst()).allSatisfy { $0.frame.maxX <= $1.frame.minX && abs($0.frame.midY - $1.frame.midY) < 1 }, "candidate buttons fit one row without overlap")
        check(buttons[0].title == "1 工", "exact candidate has no code suffix")
        check(buttons[1].title == "2 输入(lwty)", "completion candidate shows full code suffix")
        click(buttons[2])
        check(chosen == 3, "candidate click delivers correct selection")
        if let bitmap = candidates.bitmapImageRepForCachingDisplay(in: candidates.bounds) {
            candidates.cacheDisplay(in: candidates.bounds, to: bitmap)
            let flattened = NSImage(size: candidates.bounds.size)
            flattened.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: candidates.bounds).fill()
            let captured = NSImage(size: candidates.bounds.size)
            captured.addRepresentation(bitmap)
            captured.draw(in: candidates.bounds)
            flattened.unlockFocus()
            let output = NSBitmapImageRep(data: flattened.tiffRepresentation!)!
            try output.representation(using: .png, properties: [:])?.write(to: build.appendingPathComponent("candidates-horizontal.png"))
        }
        let screen = NSScreen.main!.visibleFrame
        candidate.show(candidates: Array(repeating: InputCandidate(word: String(repeating: "长词", count: 32), code: "aaaa", completion: true), count: 5), anchor: NSRect(x: screen.maxX - 1, y: screen.minY, width: 1, height: 20)) { _ in }
        settle()
        check(screen.contains(candidateWindow.frame), "long candidates stay inside screen edges")
        candidate.show(candidates: [], anchor: .zero) { _ in }
        check(!candidateWindow.isVisible, "no-match candidate window hidden")
        let toast = ModeIndicator.shared
        let owner = NSObject()
        let otherOwner = NSObject()
        toast.show(title: "中文", owner: owner)
        settle()
        let toastWindow = app.windows.first { $0.accessibilityIdentifier() == "soumao.modeToast" }!
        check(toastWindow.isVisible && !toastWindow.canBecomeKey && toastWindow.ignoresMouseEvents, "mode toast is visible and never steals input")
        let toastLabel = toastWindow.contentView!.subviews.first as! NSTextField
        check(toastLabel.stringValue == "中文", "toast displays Chinese state")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.45))
        toast.show(title: "ABC", owner: otherOwner)
        toast.hide(owner: owner)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.45))
        check(toastWindow.isVisible && toastLabel.stringValue == "ABC", "new toast survives previous timer and owner cleanup")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        check(!toastWindow.isVisible, "toast automatically dismisses")
        print("PASS: \(checks) real AppKit preferences and candidate checks; local user data: \(userURL.path)")
        print("Rendering: native NSWindow with NSView.cacheDisplay bitmap, not a system screenshot or IMK integration test.")
    }
}
