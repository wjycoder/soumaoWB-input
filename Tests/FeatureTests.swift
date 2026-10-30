import Foundation

@main struct FeatureTests {
 static func main() throws {
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent("soumao-feature-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: temp) }
  let store = try DictionaryStore(baseURL: root.appendingPathComponent("Resources/wubi.tsv"), userURL: temp.appendingPathComponent("user.json"))
  let pinyin = try PinyinDictionary(url: root.appendingPathComponent("Resources/pinyin.tsv"))
  var checks = 0
  func check(_ value: @autoclosure () -> Bool, _ message: String) {
   checks += 1
   guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  let prefix = store.matchingCandidates(for: "lwt")
  for (word, code) in [("输入", "lwty"), ("轮番", "lwto"), ("办公自动化", "lwtw")] {
   check(prefix.contains(InputCandidate(word: word, code: code, completion: true)), "prefix includes \(word) at \(code)")
  }
  check(prefix.first?.word == "输入", "frequent extension appears first")
  check(prefix.first?.displayText == "输入(lwty)", "completion displays source code")
  let exact = store.matchingCandidates(for: "lwty")
  check(exact.first?.displayText == "输入" && exact.allSatisfy { !$0.completion }, "exact matches omit parenthesized code")
  check(store.matchingCandidates(for: "a").first?.word == "工", "exact short code remains first")
  check(store.matchingCandidates(for: "").isEmpty && store.matchingCandidates(for: "s*").isEmpty, "empty and invalid Wubi prefixes rejected")
  check(Set(prefix.map { $0.word }).count == prefix.count, "prefix words deduplicated")
  try store.remove(code: "lwty", word: "输入")
  check(!store.matchingCandidates(for: "lwt").contains { $0.word == "输入" }, "deletion invalidates prefix cache")
  try store.restore(code: "lwty", word: "输入")
  check(store.matchingCandidates(for: "lwt").contains { $0.word == "输入" }, "restore invalidates prefix cache")
  try store.add(code: "lwta", word: "联想自造词")
  check(store.matchingCandidates(for: "lwt").contains { $0.word == "联想自造词" && $0.code == "lwta" }, "new code participates in prefix search")
  try store.move(code: "lwty", word: "畭", offset: -1)
  check(store.matchingCandidates(for: "lwt").filter { $0.code == "lwty" }.first?.word == "畭", "same-code manual ordering survives prefix search")
  for (code, word) in [("shuru", "输入"), ("zhongguo", "中国"), ("chongqing", "重庆"), ("nv", "女"), ("lvse", "绿色")] {
   check(pinyin.candidates(for: code).contains { $0.word == word && !$0.completion }, "offline full pinyin \(code) matches \(word)")
  }
  check(pinyin.candidates(for: "zhong").contains { $0.word == "中国" && $0.completion }, "pinyin prefix completion")
  check(pinyin.candidates(for: "zhong'guo") == pinyin.candidates(for: "zhongguo"), "pinyin syllable separator")
  check(pinyin.candidates(for: "").isEmpty && pinyin.candidates(for: "zzzzzzzzzz").isEmpty, "empty and missing pinyin return no candidates")
  var input = InputSession()
  func key(_ text: String, code: UInt16 = 0) -> InputResult {
   let usePinyin = input.usingPinyin
   let lookup: (String) -> [String] = { (usePinyin ? pinyin.candidates(for: $0) : store.matchingCandidates(for: $0)).map { $0.word } }
   return input.handleKey(code: code, text: text, lookup: lookup)
  }
  func ctrl() {
   _ = input.controlChanged(isDown: true, otherModifiers: false)
   _ = input.controlChanged(isDown: false, otherModifiers: false)
  }
  for c in "shu" { _ = key(String(c)) }
  ctrl()
  check(input.composition.code == "shu", "switching to pinyin keeps Wubi preedit")
  for c in "ru" { _ = key(String(c)) }
  let words = pinyin.candidates(for: "shuru")
  check(key(" ", code: 49).commit == words.first?.word && !input.usingPinyin, "pinyin commits actual candidate without code then restores Wubi")
  ctrl()
  for c in "zhongguo" { _ = key(String(c)) }
  let lookup: (String) -> [String] = { pinyin.candidates(for: $0).map { $0.word } }
  check(input.select(.digit(1), lookup: lookup).commit == "中国" && !input.usingPinyin, "mouse selection path restores Wubi")
  ctrl()
  for c in "shuru" { _ = key(String(c)) }
  _ = key("=", code: 0)
  let second = pinyin.candidates(for: "shuru")[input.composition.page * 5 + 1].word
  check(key(";").commit == second && !input.usingPinyin, "semicolon selects current pinyin page second word")
  for c in "lwt" { _ = key(String(c)) }
  let page = store.matchingCandidates(for: "lwt")
  _ = key("=")
  check(key(";").commit == page[6].word, "semicolon selects second prefix candidate on next page")
  for selection in ["'", "‘"] {
   for c in "lwt" { _ = key(String(c)) }
   _ = key("=")
   check(key(selection).commit == page[7].word, "quote selects third prefix candidate on next page")
  }
  _ = key("7"); _ = key("8")
  check(key("。").commit == "." && key(".").commit == "。", "literal Chinese period after digits is one-shot ASCII")
  _ = key("a"); _ = key("2")
  check(key(".").commit == "。", "candidate selection digit does not arm decimal override")
  print("PASS: \(checks) prefix, pinyin and combined input checks")
 }
}
