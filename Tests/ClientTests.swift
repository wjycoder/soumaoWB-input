import AppKit
import InputMethodKit

// Exercise the real IMK controller boundary, including activation of each client.
final class AppContext {
 static var store: DictionaryStore?
 static var pinyin: PinyinDictionary?
 static func showError(_ error: Error) { fatalError(error.localizedDescription) }
 static func showPreferences() {}
}
final class RecordingClient: NSObject, IMKTextInput {
 var keyboard: String?
 var inserted = ""
 var marked = ""
 func insertText(_ string: Any!, replacementRange: NSRange) { inserted += string as! String; marked = "" }
 func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) { marked = string as! String }
 func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
 func markedRange() -> NSRange { NSRange(location: 0, length: marked.utf16.count) }
 func attributedSubstring(from range: NSRange) -> NSAttributedString! { nil }
 func length() -> Int { 0 }
 func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
 func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! { lineRect.pointee = NSRect(x: 100, y: 100, width: 1, height: 20); return [:] }
 func validAttributesForMarkedText() -> [Any]! { [] }
 func overrideKeyboard(withKeyboardNamed name: String!) { keyboard = name }
 func selectMode(_ modeIdentifier: String!) {}
 func supportsUnicode() -> Bool { true }
 func bundleIdentifier() -> String! { "com.vandyke.SecureCRT" }
 func windowLevel() -> CGWindowLevel { 0 }
 func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
 func uniqueClientIdentifierString() -> String! { "soumao-test-client" }
 func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { "" }
 func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}
@main struct ClientTests {
 static func main() throws {
  _ = NSApplication.shared
  let client = RecordingClient()
  let controller = SoumaoInputController(server: nil, delegate: nil, client: nil)!
  controller.activateServer(client)
  guard client.keyboard == "com.apple.keylayout.ABC" else {
   print("FAIL: activated input method must supply a Unicode keyboard layout for Qt clients")
   exit(1)
  }
  var checks = 1
  func check(_ value: Bool, _ message: String) {
   guard value else { print("FAIL: \(message)"); exit(1) }
   checks += 1
  }
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent("soumao-client-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temp) }
  AppContext.store = try DictionaryStore(baseURL: URL(fileURLWithPath: "Resources/wubi.tsv"), userURL: temp.appendingPathComponent("user.json"))
  func key(_ code: UInt16, _ text: String, type: NSEvent.EventType = .keyDown, flags: NSEvent.ModifierFlags = []) -> Bool {
   let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
   return controller.handle(event, client: client)
  }
  for (code, letter) in [(UInt16(37), "l"), (13, "w"), (17, "t"), (16, "y")] {
   check(key(code, letter), "Chinese code is consumed")
  }
  check(client.marked == "lwty", "preedit reaches client")
  check(key(49, " "), "space selects candidate")
  check(client.inserted == "输入" && client.marked.isEmpty, "Chinese commit reaches client and clears preedit")
  _ = key(56, "", type: .flagsChanged, flags: .shift)
  _ = key(56, "", type: .flagsChanged)
  for (code, letter) in [(UInt16(0), "a"), (11, "b"), (8, "c"), (7, "x"), (16, "y"), (6, "z"), (18, "1"), (19, "2"), (20, "3")] {
   check(!key(code, letter), "English and digits are passed through to host")
  }
  check(!key(8, "c", flags: .control), "terminal Control-C is passed through")
  check(!key(36, "\r"), "idle Return is passed through")
  check(!key(51, "\u{8}"), "idle Backspace is passed through")
  client.keyboard = nil
  controller.activateServer(client)
  check(client.keyboard == "com.apple.keylayout.ABC", "layout override is reapplied on activation")
  let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
  check(!controller.handle(mouse, client: client), "mouse is passed through without key-only access")
  controller.deactivateServer(client)
  print("PASS: \(checks) IMK client boundary checks")
 }
}
