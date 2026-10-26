import Foundation

/// Input policy shared by IMK events and regression tests; no host-app state.
struct InputSession {
 var composition = Composition()
 private(set) var english = false
 private(set) var capsLock = false
 private var shiftPending = false
 private var controlPending = false
 private var afterDigit = false
 private(set) var usingPinyin = false
 private var openingDoubleQuote = true
 private var openingSingleQuote = true
 var isEnglish: Bool { english || capsLock }
 var modeTitle: String { isEnglish ? "ABC" : "中文" }

 mutating func cancelModifiers() { shiftPending = false; controlPending = false }
 mutating func resetContext() { cancelModifiers(); afterDigit = false; usingPinyin = false }
 mutating func controlChanged(isDown: Bool, otherModifiers: Bool) -> Bool {
  shiftPending = false
  if isDown {
   controlPending = !otherModifiers && !isEnglish
   return false
  }
  let activate = controlPending && !otherModifiers && !isEnglish
  controlPending = false
  if activate { usingPinyin = true; composition.resetPage(); afterDigit = false }
  return activate
 }
 mutating func select(_ key: InputKey, lookup: (String) -> [String]) -> InputResult {
  let result = composition.handle(key, lookup: lookup, pinyin: usingPinyin)
  if composition.code.isEmpty { resetContext() }
  return result
 }
 mutating func shiftChanged(isDown: Bool, otherModifiers: Bool) -> InputResult {
  controlPending = false
  if isDown {
   shiftPending = !otherModifiers && !capsLock
   return InputResult(consumed: false)
  }
  let toggle = shiftPending && !otherModifiers && !capsLock
  shiftPending = false
  return toggle ? toggleMode() : InputResult(consumed: false)
 }
 mutating func toggleMode() -> InputResult {
  // Shift always submits literal preedit, never a Chinese candidate.
  let raw = composition.code.isEmpty ? nil : composition.code
  composition.clear()
  resetContext()
  english.toggle()
  openingDoubleQuote = true; openingSingleQuote = true
  return InputResult(consumed: raw != nil, commit: raw)
 }
 mutating func setCapsLock(_ enabled: Bool) -> InputResult {
  defer { capsLock = enabled }
  guard enabled != capsLock else { return InputResult(consumed: false) }
  resetContext()
  let raw = composition.code.isEmpty ? nil : composition.code
  composition.clear()
  return InputResult(consumed: raw != nil, commit: raw)
 }
 mutating func handleKey(code: UInt16, text: String, lookup: (String) -> [String], autoCommit: Bool = false) -> InputResult {
  cancelModifiers()
  let decimal = afterDigit
  afterDigit = false
  let hadComposition = !composition.code.isEmpty
  defer { if hadComposition && composition.code.isEmpty { usingPinyin = false } }
  guard !isEnglish else { return InputResult(consumed: false) }
  let key: InputKey?
  switch code {
  case 51: key = .backspace
  case 53:
   let armed = usingPinyin && composition.code.isEmpty
   usingPinyin = false
   if armed { return InputResult(consumed: true) }
   key = .escape
  case 36, 76: key = .enter
  case 49: key = .space
  case 116: key = .previousPage
  case 121: key = .nextPage
  default:
   if !composition.code.isEmpty && text == ";" { key = .digit(2) }
   else if !composition.code.isEmpty && ["[", "【", "-"].contains(text) { key = .previousPage }
   else if !composition.code.isEmpty && ["]", "】", "="].contains(text) { key = .nextPage }
   else if text.utf8.count == 1, let c = text.utf8.first, ((97...122).contains(c) || (usingPinyin && c == 39)) { key = .letter(text) }
   else if text.count == 1, let number = Int(text), (0...9).contains(number) { key = .digit(number) }
   else { key = nil }
  }
  if let key {
   let result = composition.handle(key, lookup: lookup, autoCommit: autoCommit, pinyin: usingPinyin)
   if !result.consumed && text.utf8.count == 1, let byte = text.utf8.first, (48...57).contains(byte) { afterDigit = true }
   return result
  }
  let pending = composition.handle(.space, lookup: lookup).commit
  let punctuation = ["/":"、", ",":"，", ".":"。", "?":"？", "!":"！", ":":"：", ";":"；", "(":"（", ")":"）", "[":"【", "]":"】", "\\":"、", "<":"《", ">":"》", "$":"￥", "^":"……", "_":"——"]
  var output = punctuation[text]
  if decimal && (text == "." || text == "。") { output = "." }
  if text == "\"" {
   output = openingDoubleQuote ? "“" : "”"; openingDoubleQuote.toggle()
  } else if text == "'" {
   output = openingSingleQuote ? "‘" : "’"; openingSingleQuote.toggle()
  }
  if let output { return InputResult(consumed: true, commit: (pending ?? "") + output) }
  return InputResult(consumed: false, commit: pending)
 }
}
