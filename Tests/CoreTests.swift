import Foundation

@main struct CoreTests {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("soumao-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let base = URL(fileURLWithPath: CommandLine.arguments[1])
  let user = root.appendingPathComponent("user.json")
  let store = try DictionaryStore(baseURL: base, userURL: user)
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ message: String) {
   checks += 1
   if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
  }
  func rejects(_ message: String, _ body: () throws -> Void) {
   checks += 1
   do { try body(); fputs("FAIL: \(message)\n", stderr); exit(1) } catch { }
  }
  check(store.baseCount == 112014, "all source pairs loaded")
  check(store.candidates(for: "a").first == "工", "short code priority")
  check(store.candidates(for: "q").first == "我", "irregular short code")
  check(store.candidates(for: "khlg").prefix(3).elementsEqual(["中国", "跑车", "跳车"]), "same-code ranking")
  check(store.candidates(for: "ltif").contains("输入法"), "phrase code")
  try store.remove(code: "a", word: "工")
  check(!store.candidates(for: "a").contains("工"), "delete exact pair")
  check(store.candidates(for: "aaaa").contains("工"), "other code preserved")
  check(store.rows(for: "a").contains { $0.word == "工" && $0.deleted }, "deleted row remains restorable")
  try store.add(code: "aaaa", word: "搜猫测试")
  check(store.candidates(for: "aaaa").first == "搜猫测试", "new phrase priority")
  try store.add(code: "aaaa", word: "搜猫测试")
  check(store.candidates(for: "aaaa").filter { $0 == "搜猫测试" }.count == 1, "addition idempotent")
  let reloaded = try DictionaryStore(baseURL: base, userURL: user)
  check(reloaded.candidates(for: "aaaa").first == "搜猫测试", "new phrase survives restart")
  check(!reloaded.candidates(for: "a").contains("工"), "deletion survives restart")
  try store.restore(code: "a", word: "工")
  check(store.candidates(for: "a").first == "工", "restore base word")
  try store.remove(code: "aaaa", word: "搜猫测试")
  check(!store.candidates(for: "aaaa").contains("搜猫测试"), "remove custom word")
  try store.restore(code: "aaaa", word: "搜猫测试")
  check(store.candidates(for: "aaaa").contains("搜猫测试"), "restore custom word")
  rejects("illegal code") { try store.add(code: "zzzzz", word: "测试") }
  rejects("empty word") { try store.add(code: "abcd", word: " ") }
  rejects("newline word") { try store.add(code: "abcd", word: "坏\n词") }
  let backup = root.appendingPathComponent("backup.json")
  try store.exportChanges(to: backup)
  let other = try DictionaryStore(baseURL: base, userURL: root.appendingPathComponent("other.json"))
  try other.importChanges(from: backup)
  check(other.candidates(for: "aaaa").contains("搜猫测试"), "backup roundtrip")
  let bad = root.appendingPathComponent("bad.json")
  try Data("{broken".utf8).write(to: bad)
  rejects("invalid import") { try other.importChanges(from: bad) }
  check(other.candidates(for: "aaaa").contains("搜猫测试"), "bad import preserves state")
  rejects("corrupt persisted file") { _ = try DictionaryStore(baseURL: base, userURL: bad) }
  let before = try Data(contentsOf: bad)
  check(before == Data("{broken".utf8), "corrupt data not overwritten")
  let blocked = root.appendingPathComponent("blocked")
  try Data("file".utf8).write(to: blocked)
  let failureStore = try DictionaryStore(baseURL: base, userURL: blocked.appendingPathComponent("user.json"))
  rejects("save failure") { try failureStore.add(code: "abcd", word: "失败词") }
  check(!failureStore.candidates(for: "abcd").contains("失败词"), "failed save not published")
  // Optional ordering metadata must work when importing into a fresh store.
  let orderedBackup = root.appendingPathComponent("ordered.json")
  try Data(#"{"version":1,"added":[],"removed":[],"orders":{"khlg":["跳车","中国","跑车"]}}"#.utf8).write(to: orderedBackup)
  try other.importChanges(from: orderedBackup)
  check(other.candidates(for: "khlg").prefix(3).elementsEqual(["跳车", "中国", "跑车"]), "import applies explicit candidate order")
  let ranking = other.candidates(for: "khlg")
  try other.move(code: "khlg", word: "中国", offset: -1)
  check(other.candidates(for: "khlg").prefix(3).elementsEqual(["中国", "跳车", "跑车"]), "move up swaps adjacent candidates")
  let sibling = try DictionaryStore(baseURL: base, userURL: other.userURL)
  try other.move(code: "khlg", word: "中国", offset: 1)
  try sibling.move(code: "khlg", word: "跑车", offset: -1)
  try other.reloadIfChanged()
  check(other.candidates(for: "khlg").prefix(3).elementsEqual(["跳车", "跑车", "中国"]), "stale instance edits latest order under lock")
  try other.remove(code: "khlg", word: "跑车")
  try other.move(code: "khlg", word: "中国", offset: -1)
  check(other.candidates(for: "khlg").prefix(2).elementsEqual(["中国", "跳车"]), "move skips deleted rows")
  try other.restore(code: "khlg", word: "跑车")
  check(other.candidates(for: "khlg").prefix(3).elementsEqual(["中国", "跑车", "跳车"]), "restore retains saved order")
  try other.move(code: "khlg", word: "中国", offset: -1)
  check(other.candidates(for: "khlg").first == "中国", "first candidate cannot move above boundary")
  rejects("reject moving absent word") { try other.move(code: "khlg", word: "不存在词", offset: 1) }
  rejects("reject invalid move offset") { try other.move(code: "khlg", word: "中国", offset: 9) }
  try other.add(code: "khlg", word: "自造优先")
  check(other.candidates(for: "khlg").first == "自造优先", "new word retains priority with custom order")
  try other.exportChanges(to: orderedBackup)
  let roundtrip = try DictionaryStore(baseURL: base, userURL: root.appendingPathComponent("roundtrip.json"))
  try roundtrip.importChanges(from: orderedBackup)
  check(roundtrip.candidates(for: "khlg") == other.candidates(for: "khlg"), "ordering backup roundtrip")
  check(roundtrip.rows(for: "khlg").filter { !$0.deleted }.map { $0.word } == roundtrip.candidates(for: "khlg"), "management rows follow candidate order")
  check(Set(ranking).isSubset(of: Set(roundtrip.candidates(for: "khlg"))), "sorting never loses base words")
  try Data(#"{"version":1,"added":[],"removed":[],"orders":{"khlg":["中国","中国"]}}"#.utf8).write(to: bad)
  rejects("duplicate order import rejected") { try other.importChanges(from: bad) }
  try Data(#"{"version":1,"added":[],"removed":[],"orders":{"ZZZ":["中国"]}}"#.utf8).write(to: bad)
  rejects("invalid order code import rejected") { try other.importChanges(from: bad) }
  var state = Composition()
  let lookup: (String) -> [String] = { ["a":["工", "戈", "或", "式", "功", "节"], "ab":["节"], "abcd":["唯一"]][$0] ?? [] }
  check(state.handle(.letter("a"), lookup: lookup).consumed, "letter consumed")
  check(state.code == "a", "composition reflects key")
  _ = state.handle(.nextPage, lookup: lookup)
  check(state.page == 1, "page next")
  check(state.handle(.space, lookup: lookup).commit == "节", "space chooses current page")
  check(state.code.isEmpty, "selection clears composition")
  _ = state.handle(.letter("a"), lookup: lookup)
  check(state.handle(.digit(2), lookup: lookup).commit == "戈", "number selection")
  _ = state.handle(.letter("a"), lookup: lookup)
  _ = state.handle(.letter("b"), lookup: lookup)
  _ = state.handle(.backspace, lookup: lookup)
  check(state.code == "a", "backspace")
  check(state.handle(.escape, lookup: lookup).commit == nil && state.code.isEmpty, "escape cancels")
  check(!state.handle(.space, lookup: lookup).consumed, "empty space passes through")
  _ = state.handle(.letter("x"), lookup: lookup)
  check(state.handle(.space, lookup: lookup).commit == "x", "unmatched code never lost")
  for c in "abcd" { _ = state.handle(.letter(String(c)), lookup: lookup) }
  check(state.handle(.letter("a"), lookup: lookup).commit == "唯一" && state.code == "a", "fifth key commits then starts next")
  _ = state.handle(.escape, lookup: lookup)
  for c in "abc" { _ = state.handle(.letter(String(c)), lookup: lookup, autoCommit: true) }
  check(state.handle(.letter("d"), lookup: lookup, autoCommit: true).commit == "唯一", "optional unique four-code auto commit")
  print("PASS: \(checks) core behavior checks; \(store.baseCount) dictionary pairs")
 }
}
