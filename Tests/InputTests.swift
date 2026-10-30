import Foundation

@main struct InputTests {
 static func main() {
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ message: String) {
   checks += 1
   guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  let lookup: (String) -> [String] = { $0 == "a" ? ["工", "戈", "或", "式", "功", "节"] : [] }
  var input = InputSession()
  func key(_ text: String, code: UInt16 = 0) -> InputResult {
   input.handleKey(code: code, text: text, lookup: lookup)
  }
  func shift() -> InputResult {
   _ = input.shiftChanged(isDown: true, otherModifiers: false)
   return input.shiftChanged(isDown: false, otherModifiers: false)
  }
  check(input.modeTitle == "中文", "initial Chinese status")
  check(key("`").commit == "·", "Chinese backtick outputs middle dot")
  _ = key("a")
  check(key("`").commit == "工·", "backtick commits candidate before middle dot")
  for selection in [";", "；", "'", "‘"] {
   _ = key("a")
   let result = key(selection)
   check(result.consumed && result.commit == ([";", "；"].contains(selection) ? "戈" : "或"), "candidate shortcut \(selection)")
   check(input.composition.code.isEmpty, "selection clears composition")
   _ = key("a"); _ = key("=")
   let missing = key(selection)
   check(missing.consumed && missing.commit == nil && input.composition.code == "a" && input.composition.page == 1, "missing candidate preserves composition for \(selection)")
   _ = key("", code: 53)
   _ = key("x")
   let unmatched = key(selection)
   check(unmatched.consumed && unmatched.commit == nil && input.composition.code == "x", "no matches preserve code for \(selection)")
   _ = key("", code: 53)
  }
  check(key("'").commit == "‘" && key("'").commit == "’", "idle single quotes remain paired punctuation")
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  for c in "xi'an" { _ = key(String(c)) }
  check(input.composition.code == "xi'an" && input.usingPinyin, "pinyin ASCII apostrophe remains syllable separator")
  _ = key("", code: 53)
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  _ = key("a")
  check(key("‘").commit == "或" && !input.usingPinyin, "Chinese quote selects third pinyin candidate and restores Wubi")
  _ = input.setCapsLock(true)
  for text in ["`", ";", "；", "'", "‘"] {
   check(!key(text).consumed, "Caps Lock passes through \(text)")
  }
  _ = input.setCapsLock(false)
  _ = key("a")
  _ = key("=")
  check(shift().commit == "a", "Shift commits raw code even after paging")
  check(input.composition.code.isEmpty && input.modeTitle == "ABC", "Shift clears composition and enters English")
  check(!key(",").consumed, "English punctuation passes through")
  for text in ["`", ";", "；", "'", "‘"] {
   check(!key(text).consumed, "English passes through \(text)")
  }
  check(!key("a").consumed, "English letters pass through")
  check(shift().commit == nil && input.modeTitle == "中文", "idle Shift switches back without inserting text")
  check(key(",").commit == "，", "Chinese punctuation follows mode")
  check(key("[").commit == "【" && key("]").commit == "】", "idle brackets are Chinese punctuation")
  for next in ["]", "】", "="] {
   _ = key("a")
   _ = key(next)
   check(input.composition.page == 1, "next page using \(next)")
   _ = key(next)
   check(input.composition.page == 1, "last page stays bounded")
   check(key(" ", code: 49).commit == "节", "page selection commits current candidate")
  }
  for previous in ["[", "【", "-"] {
   _ = key("a"); _ = key("="); _ = key(previous)
   check(input.composition.page == 0, "previous page using \(previous)")
   _ = key(previous)
   check(input.composition.page == 0, "first page stays bounded")
   _ = key("", code: 53)
  }
  _ = input.shiftChanged(isDown: true, otherModifiers: false)
  _ = key("A")
  check(input.shiftChanged(isDown: false, otherModifiers: false).commit == nil && !input.english, "Shift-letter does not toggle mode")
  _ = input.shiftChanged(isDown: true, otherModifiers: true)
  _ = input.shiftChanged(isDown: false, otherModifiers: false)
  check(!input.english, "modified Shift does not toggle")
  _ = key("a")
  check(key("!").commit == "工！", "punctuation commits candidate then Chinese punctuation")
  _ = key("x")
  check(shift().commit == "x", "Shift preserves unmatched code")
  _ = shift()
  _ = key("a")
  check(input.setCapsLock(true).commit == "a", "Caps Lock preserves pending raw code")
  check(input.modeTitle == "ABC" && !key(".").consumed, "Caps Lock uses English punctuation and status")
  _ = input.setCapsLock(false)
  check(input.modeTitle == "中文", "Caps Lock off restores mode")
  check(key("/").commit == "、", "Chinese slash becomes enumeration comma")
  _ = key("3")
  check(key(".").commit == ".", "period immediately after digit stays ASCII")
  check(key(".").commit == "。", "decimal exception used only once")
  _ = key("2"); _ = key(",")
  check(key(".").commit == "。", "other punctuation clears decimal context")
  _ = key("a")
  check(key(";").commit == "戈", "semicolon selects second candidate")
  check(key(";").commit == "；", "idle semicolon remains Chinese punctuation")
  _ = key("a"); _ = key("=")
  check(key(";").commit == nil && input.composition.page == 1, "missing second candidate does not commit or clear")
  _ = key("", code: 53)
  _ = key("4"); input.resetContext()
  check(key(".").commit == "。", "focus reset clears decimal context")
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  check(input.controlChanged(isDown: false, otherModifiers: false) && input.usingPinyin, "idle Ctrl arms one pinyin composition")
  for c in "zhongguo" { _ = key(String(c)) }
  check(input.composition.code == "zhongguo", "pinyin accepts z and more than four letters")
  check(key("", code: 36).commit == "zhongguo" && !input.usingPinyin, "raw commit ends temporary pinyin")
  _ = key("a")
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  check(input.usingPinyin && input.composition.code == "a", "Ctrl preserves existing preedit")
  check(key(";").commit == "戈" && !input.usingPinyin, "candidate selection restores Wubi")
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  input.cancelModifiers()
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  check(!input.usingPinyin, "Ctrl shortcut does not arm pinyin")
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  _ = key("", code: 53)
  check(!input.usingPinyin, "Esc cancels armed pinyin even before typing")
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  _ = key("x"); _ = key("", code: 51)
  check(!input.usingPinyin, "deleting final pinyin letter restores Wubi")
  _ = shift()
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  check(!input.usingPinyin && !key("/").consumed, "English ignores Ctrl pinyin and slash mapping")
  _ = shift()
  print("PASS: \(checks) input event policy checks")
 }
}
