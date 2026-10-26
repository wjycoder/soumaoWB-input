import AppKit
import InputMethodKit

@objc(SoumaoInputController)
final class SoumaoInputController: IMKInputController {
 private var input = InputSession()
 private let panel = CandidatePanel()
 private var lastClient: IMKTextInput?
 private var lastError: String?
 private var store: DictionaryStore? { AppContext.store }

 override func recognizedEvents(_ sender: Any!) -> Int {
  Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue |
      NSEvent.EventTypeMask.leftMouseDown.rawValue | NSEvent.EventTypeMask.rightMouseDown.rawValue)
 }
 override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
  guard let event, let client = sender as? IMKTextInput, let store else { return false }
  lastClient = client
  if event.type == .leftMouseDown || event.type == .rightMouseDown {
   commitComposition(sender); input.resetContext(); return false
  }
  let capsResult = input.setCapsLock(event.modifierFlags.contains(.capsLock))
  if let raw = capsResult.commit { insert(raw, into: client); render(client) }
  let shortcut = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
  if event.type == .flagsChanged {
   if event.keyCode == 56 || event.keyCode == 60 {
    let previous = input.english
    let result = input.shiftChanged(isDown: event.modifierFlags.contains(.shift), otherModifiers: shortcut)
    if let raw = result.commit { insert(raw, into: client); render(client) }
    if previous != input.english { ModeIndicator.shared.show(title: input.modeTitle, owner: self) }
   } else if event.keyCode == 59 || event.keyCode == 62 {
    let other = !event.modifierFlags.intersection([.command, .option, .shift]).isEmpty
    if input.controlChanged(isDown: event.modifierFlags.contains(.control), otherModifiers: other) { render(client) }
   } else { input.cancelModifiers() }
   return false
  }
  guard event.type == .keyDown else { return false }
  input.cancelModifiers()
  if shortcut { commitComposition(sender); input.resetContext(); return false }
  if input.isEnglish { return false }
  do { try store.reloadIfChanged(); lastError = nil }
  catch {
   if lastError != error.localizedDescription {
    lastError = error.localizedDescription
    AppContext.showError(error)
   }
   return false
  }
  let lookup = currentLookup()
  let result = input.handleKey(code: event.keyCode, text: event.characters ?? "", lookup: lookup,
                              autoCommit: UserDefaults.standard.bool(forKey: "autoCommit"))
  if let committed = result.commit { insert(committed, into: client) }
  if result.consumed || result.commit != nil { render(client) }
  return result.consumed
 }
 private func matches(for code: String) -> [InputCandidate] {
  input.usingPinyin ? (AppContext.pinyin?.candidates(for: code) ?? []) : (store?.matchingCandidates(for: code) ?? [])
 }
 private func currentLookup() -> (String) -> [String] {
  // Capture mode before mutating InputSession to avoid overlapping Swift access.
  if input.usingPinyin { return { AppContext.pinyin?.candidates(for: $0).map { $0.word } ?? [] } }
  return { [weak self] in self?.store?.matchingCandidates(for: $0).map { $0.word } ?? [] }
 }
 private func insert(_ text: String, into client: IMKTextInput) {
  client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
 }
 private func render(_ client: IMKTextInput) {
  let code = input.composition.code
  client.setMarkedText(code, selectionRange: NSRange(location: code.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  guard !code.isEmpty, store != nil else { panel.hide(); return }
  var rect = NSRect.zero
  _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
  if rect == .zero { rect = NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 1, height: 20)) }
  let candidates = Array(matches(for: code).dropFirst(input.composition.page * input.composition.pageSize).prefix(input.composition.pageSize))
  panel.show(candidates: candidates, anchor: rect) { [weak self] number in
   guard let self, let client = self.lastClient else { return }
   let lookup = self.currentLookup()
   let result = self.input.select(.digit(number), lookup: lookup)
   if let text = result.commit { self.insert(text, into: client) }
   self.render(client)
  }
 }
 override func commitComposition(_ sender: Any!) {
  guard !input.composition.code.isEmpty, let client = (sender as? IMKTextInput) ?? lastClient else { panel.hide(); return }
  let lookup = currentLookup()
  let result = input.select(.space, lookup: lookup)
  if let text = result.commit { insert(text, into: client) }
  panel.hide()
 }
 override func activateServer(_ sender: Any!) {
  super.activateServer(sender)
  lastClient = sender as? IMKTextInput
  // Qt clients read TISCopyInputMethodKeyboardLayoutOverride when translating
  // keys. Our input mode has no Unicode layout data of its own; supply the
  // standard ABC layout for both Wubi codes and English pass-through.
  lastClient?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
  input.resetContext()
  input.composition.clear(); panel.hide()
  _ = input.setCapsLock(NSEvent.modifierFlags.contains(.capsLock))
 }
 override func deactivateServer(_ sender: Any!) {
  commitComposition(sender)
  panel.hide(); lastClient = nil; input.resetContext()
  ModeIndicator.shared.hide(owner: self)
  super.deactivateServer(sender)
 }
 override func menu() -> NSMenu! {
  let menu = NSMenu(title: "搜猫五笔")
  let preferences = NSMenuItem(title: "偏好设置…", action: #selector(showPreferences(_:)), keyEquivalent: "")
  preferences.target = self; menu.addItem(preferences)
  let mode = NSMenuItem(title: input.english ? "切换到中文" : "切换到英文", action: #selector(toggleMode(_:)), keyEquivalent: "")
  mode.target = self; mode.isEnabled = !input.capsLock; menu.addItem(mode)
  return menu
 }
 override func showPreferences(_ sender: Any!) { AppContext.showPreferences() }
 @objc private func toggleMode(_ sender: Any?) {
  guard !input.capsLock else { return }
  let result = input.toggleMode()
  if let client = lastClient {
   if let raw = result.commit { insert(raw, into: client) }
   render(client)
  }
 }
}
