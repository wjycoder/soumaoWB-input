import Foundation

enum InputKey {
 case letter(String), digit(Int), space, backspace, escape, enter, nextPage, previousPage
}
struct InputResult {
 var consumed: Bool
 var commit: String?
}
struct Composition {
 private(set) var code = ""
 private(set) var page = 0
 let pageSize = 5
 mutating func resetPage() { page = 0 }
 mutating func clear() { code = ""; page = 0 }
 func visibleCandidates(lookup: (String) -> [String]) -> [String] {
  Array(lookup(code).dropFirst(page * pageSize).prefix(pageSize))
 }
 mutating func handle(_ key: InputKey, lookup: (String) -> [String], autoCommit: Bool = false, pinyin: Bool = false) -> InputResult {
  var result = InputResult(consumed: true, commit: nil)
  let candidates = lookup(code)
  func selected(_ index: Int) -> String? { candidates.indices.contains(index) ? candidates[index] : nil }
  switch key {
  case .letter(let letter):
   guard letter.utf8.count == 1, let c = letter.utf8.first, (97...122).contains(c) || (pinyin && c == 39) else { return InputResult(consumed: false) }
   if pinyin && code.count >= 128 { return result }
   if !pinyin && code.count >= 4 { result.commit = selected(page * pageSize) ?? code; clear() }
   code += letter; page = 0
   if !pinyin && autoCommit && code.count == 4 && !code.contains("z") {
    let matches = lookup(code)
    if matches.count == 1 { result.commit = (result.commit ?? "") + matches[0]; clear() }
   }
  case .space:
   guard !code.isEmpty else { return InputResult(consumed: false) }
   result.commit = selected(page * pageSize) ?? code; clear()
  case .digit(let number):
   guard !code.isEmpty else { return InputResult(consumed: false) }
   if (1...pageSize).contains(number), let word = selected(page * pageSize + number - 1) { result.commit = word; clear() }
  case .backspace:
   guard !code.isEmpty else { return InputResult(consumed: false) }
   code.removeLast(); page = 0
  case .escape:
   guard !code.isEmpty else { return InputResult(consumed: false) }
   clear()
  case .enter:
   guard !code.isEmpty else { return InputResult(consumed: false) }
   result.commit = code; clear()
  case .nextPage:
   guard !code.isEmpty else { return InputResult(consumed: false) }
   if (page + 1) * pageSize < candidates.count { page += 1 }
  case .previousPage:
   guard !code.isEmpty else { return InputResult(consumed: false) }
   page = max(0, page - 1)
  }
  return result
 }
}
