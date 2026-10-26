import Foundation

@main struct WildcardTests {
 static func main() throws {
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent("soumao-wildcard-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temp) }
  var checks = 0
  func check(_ value: @autoclosure () -> Bool, _ message: String) {
   checks += 1
   guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  let store = try DictionaryStore(baseURL: root.appendingPathComponent("Resources/wubi.tsv"), userURL: temp.appendingPathComponent("user.json"))
  let lookup: (String) -> [String] = { store.matchingCandidates(for: $0).map { $0.word } }
  var input = InputSession()
  func key(_ text: String, code: UInt16 = 0, autoCommit: Bool = false) -> InputResult {
   input.handleKey(code: code, text: text, lookup: lookup, autoCommit: autoCommit)
  }
  _ = key("s")
  let z = key("z")
  check(z.consumed && z.commit == nil && input.composition.code == "sz", "z extends preedit without committing s or literal z")
  let sz = store.matchingCandidates(for: "sz")
  for (word, code) in [("械", "sa"), ("林", "ss"), ("枯", "sd")] {
   check(sz.contains(InputCandidate(word: word, code: code, completion: true)), "sz includes \(word) with actual code \(code)")
  }
  check(sz.allSatisfy { $0.displayText == "\($0.word)(\($0.code))" }, "wildcard candidates show actual codes")
  check(key(" ", code: 49).commit == sz.first?.word, "space commits word without code suffix")
  for pattern in ["z", "zs", "sz", "sza", "lzt", "lwzz", "zz", "zzzz"] {
   let matches = store.matchingCandidates(for: pattern)
   let regex = "^" + pattern.replacingOccurrences(of: "z", with: "[a-y]")
   check(!matches.isEmpty && matches.allSatisfy { $0.code.range(of: regex, options: .regularExpression) != nil }, "\(pattern) consumes exactly one letter per z")
   check(zip(matches, matches.dropFirst()).allSatisfy { $0.code.count <= $1.code.count }, "\(pattern) puts shorter matches first")
   check(Set(matches.map { $0.word }).count == matches.count, "\(pattern) deduplicates words")
   check(matches == store.matchingCandidates(for: pattern), "\(pattern) has stable cached order")
  }
  for invalid in ["", "zzzzz", "s*", "s1", "z'", "汉"] {
   check(store.matchingCandidates(for: invalid).isEmpty, "invalid pattern \(invalid) rejected")
  }
  check(store.matchingCandidates(for: "SZ") == sz, "lookup normalizes uppercase")
  check(store.matchingCandidates(for: "ss").first?.displayText == "林", "ordinary exact match keeps existing display")
  check(store.candidates(for: "sz").isEmpty, "dictionary management remains exact-code only")
  do {
   try store.add(code: "sz", word: "非法词")
   check(false, "wildcard is never stored as a real code")
  } catch { check(true, "dictionary writes reject wildcard") }

  // Tiny fixture verifies complete coverage, ranking, deduplication and overlays.
  let fixture = temp.appendingPathComponent("base.tsv")
  try "code\tword\trank\tsource\ns\t木\t0\ttest\nsa\t械\t2\ttest\nss\t林\t1\ttest\nsd\t枯\t3\ttest\nss\t双木\t2\ttest\nsaa\t械\t0\ttest\nsab\t长词\t0\ttest\naa\t其他\t0\ttest\n".write(to: fixture, atomically: true, encoding: .utf8)
  let small = try DictionaryStore(baseURL: fixture, userURL: temp.appendingPathComponent("small.json"))
  check(small.matchingCandidates(for: "sz").map { $0.word } == ["林", "双木", "械", "枯", "长词"], "all same-length matches before longer completions, deduplicated by shortest code")
  check(small.matchingCandidates(for: "zz").map { $0.word } == ["其他", "林", "双木", "械", "枯", "长词"], "multiple wildcards cover all matching codes")
  check(small.matchingCandidates(for: "szz").map { $0.word } == ["械", "长词"], "z cannot match zero characters")
  check(small.matchingCandidates(for: "zzzz").isEmpty, "missing wildcard match returns empty")
  try small.add(code: "sy", word: "自造词")
  check(small.matchingCandidates(for: "sz").first?.word == "自造词", "new custom code participates and invalidates cache")
  try small.move(code: "ss", word: "双木", offset: -1)
  check(small.matchingCandidates(for: "sz").filter { $0.code == "ss" }.map { $0.word } == ["双木", "林"], "custom same-code order respected")
  try small.remove(code: "sy", word: "自造词")
  check(!small.matchingCandidates(for: "sz").contains { $0.word == "自造词" }, "deletion invalidates cache")
  try small.restore(code: "sy", word: "自造词")
  check(small.matchingCandidates(for: "sz").contains { $0.word == "自造词" }, "restore invalidates cache")
  try small.remove(code: "sa", word: "械")
  check(small.matchingCandidates(for: "sz").contains { $0.word == "械" && $0.code == "saa" }, "deletion applies only to original code")
  let backup = temp.appendingPathComponent("backup.json")
  try small.exportChanges(to: backup)
  let imported = try DictionaryStore(baseURL: fixture, userURL: temp.appendingPathComponent("imported.json"))
  _ = imported.matchingCandidates(for: "sz")
  try imported.importChanges(from: backup)
  check(imported.matchingCandidates(for: "sz") == small.matchingCandidates(for: "sz"), "import updates cached wildcard results")
  let sibling = try DictionaryStore(baseURL: fixture, userURL: small.userURL)
  try sibling.add(code: "sx", word: "另一进程词")
  try small.reloadIfChanged()
  check(small.matchingCandidates(for: "sz").contains { $0.word == "另一进程词" }, "external dictionary changes invalidate cache")

  _ = key("s"); _ = key("z"); _ = key("=")
  check(input.composition.page == 1 && key(";").commit == sz[6].word, "semicolon selects second wildcard candidate on next page")
  _ = key("s"); _ = key("z")
  check(key("3").commit == sz[2].word, "number selects wildcard candidate")
  _ = key("s"); _ = key("z")
  check(input.select(.digit(2), lookup: lookup).commit == sz[1].word, "mouse selection uses same wildcard ordering")
  _ = key("s"); _ = key("z"); _ = key("="); _ = key("", code: 51)
  check(input.composition.code == "s" && input.composition.page == 0, "backspace removes wildcard and resets page")
  _ = key("", code: 53)
  check(input.composition.code.isEmpty, "escape clears wildcard composition")
  _ = key("z")
  check(input.composition.code == "z", "idle z starts composition")
  check(key("", code: 36).commit == "z", "Return explicitly submits raw wildcard")
  _ = key("s"); _ = key("z")
  check(key("!").commit == sz[0].word + "！", "punctuation submits wildcard word")
  _ = key("s"); _ = key("z")
  _ = input.shiftChanged(isDown: true, otherModifiers: false)
  check(input.shiftChanged(isDown: false, otherModifiers: false).commit == "sz", "Shift explicitly commits raw wildcard and switches to English")
  check(!key("z").consumed, "English z passes through")
  _ = input.toggleMode()
  _ = input.setCapsLock(true)
  check(!key("z").consumed, "Caps Lock z passes through")
  _ = input.setCapsLock(false)
  var composition = Composition()
  let unique: (String) -> [String] = { $0 == "abc" || $0 == "abcz" || $0 == "abcd" ? ["唯一"] : [] }
  for c in "abc" { _ = composition.handle(.letter(String(c)), lookup: unique, autoCommit: true) }
  check(composition.handle(.letter("z"), lookup: unique, autoCommit: true).commit == nil && composition.code == "abcz", "fourth-key z never auto-commits even a unique candidate")
  check(composition.handle(.letter("a"), lookup: unique).commit == "唯一" && composition.code == "a", "fifth code retains normal rollover behavior")
  composition.clear()
  for c in "abc" { _ = composition.handle(.letter(String(c)), lookup: unique, autoCommit: true) }
  check(composition.handle(.letter("d"), lookup: unique, autoCommit: true).commit == "唯一", "ordinary four-code auto-commit unchanged")
  _ = input.controlChanged(isDown: true, otherModifiers: false)
  _ = input.controlChanged(isDown: false, otherModifiers: false)
  let pinyin = try PinyinDictionary(url: root.appendingPathComponent("Resources/pinyin.tsv"))
  let pinyinLookup: (String) -> [String] = { pinyin.candidates(for: $0).map { $0.word } }
  for c in "zhongguo" { _ = input.handleKey(code: 0, text: String(c), lookup: pinyinLookup) }
  check(input.composition.code == "zhongguo" && input.usingPinyin, "temporary pinyin retains literal z and long codes")
  check(input.handleKey(code: 49, text: " ", lookup: pinyinLookup).commit == "中国" && !input.usingPinyin, "pinyin commits and restores Wubi")
  print("PASS: \(checks) wildcard lookup and input checks")
 }
}
