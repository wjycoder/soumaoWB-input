import Foundation
import Darwin

struct InputCandidate: Equatable {
 let word: String
 let code: String
 let completion: Bool
 var displayText: String { completion ? "\(word)(\(code))" : word }
}

struct DictionaryRow {
 let code: String
 let word: String
 let source: String
 let deleted: Bool
}

struct DictionaryError: LocalizedError {
 let message: String
 var errorDescription: String? { message }
}

private struct WordPair: Codable, Hashable {
 let code: String
 let word: String
}
private struct UserDictionary: Codable, Equatable {
 var version = 1
 var added: [WordPair] = []
 var removed: [WordPair] = []
 var orders: [String: [String]]? = nil
}

/// All calls are serialized on the application's main thread. File mutations also
/// take a process-wide advisory lock, so a separately opened preferences process
/// cannot silently overwrite another process's edits.
final class DictionaryStore {
 let baseCount: Int
 let userURL: URL
 private var base: [String: [String]] = [:]
 private var prefixCodes: [String: [String]] = [:]
 private var codeRanks: [String: Int] = [:]
 private var matchCache: [String: [InputCandidate]] = [:]
 private var changes = UserDictionary()
 private var lastData: Data?
 private var addedByCode: [String: [String]] = [:]
 private var removedSet = Set<WordPair>()

 init(baseURL: URL, userURL: URL) throws {
  self.userURL = userURL
  let text = try String(contentsOf: baseURL, encoding: .utf8)
  var indexed: [String: [(String, Int, Int)]] = [:]
  var count = 0
  for (index, line) in text.split(separator: "\n").enumerated() {
   if index == 0 && line.hasPrefix("code\tword\t") { continue }
   let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
   guard fields.count == 4, let rank = Int(fields[2]) else {
    throw DictionaryError(message: "基础词库第 \(index + 1) 行格式无效。")
   }
   let pair = try Self.pair(code: String(fields[0]), word: String(fields[1]))
   indexed[pair.code, default: []].append((pair.word, rank, index))
   count += 1
  }
  guard count > 0 else { throw DictionaryError(message: "基础词库为空。") }
  baseCount = count
  for (code, values) in indexed {
   base[code] = values.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1 }.map { $0.0 }
  }
  for (code, values) in indexed {
   codeRanks[code] = values.map { $0.1 }.min()
   if code.count > 1 {
    for length in 1..<code.count { prefixCodes[String(code.prefix(length)), default: []].append(code) }
   }
  }
  try reloadIfChanged()
 }

 private static func pair(code: String, word: String) throws -> WordPair {
  let code = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
  guard (1...4).contains(code.utf8.count), code.utf8.allSatisfy({ (97...121).contains($0) }) else {
   throw DictionaryError(message: "编码须为 1–4 个 a–y 字母。")
  }
  guard !word.isEmpty, word.count <= 64,
        !word.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
   throw DictionaryError(message: "词语须为 1–64 个字符，不能含换行或控制字符。")
  }
  return WordPair(code: code, word: word)
 }

 private static func decode(_ data: Data) throws -> UserDictionary {
  guard data.count <= 16 * 1024 * 1024 else { throw DictionaryError(message: "用户词库超过 16 MB 上限。") }
  let value: UserDictionary
  do { value = try JSONDecoder().decode(UserDictionary.self, from: data) }
  catch { throw DictionaryError(message: "用户词库格式损坏，原文件已保留。请恢复有效备份。\n\(error.localizedDescription)") }
  guard value.version == 1 else { throw DictionaryError(message: "不支持此用户词库版本。") }
  for p in value.added + value.removed {
   guard try pair(code: p.code, word: p.word) == p else { throw DictionaryError(message: "用户词库含非规范词条。") }
  }
  guard Set(value.added).count == value.added.count, Set(value.removed).count == value.removed.count else {
   throw DictionaryError(message: "用户词库含重复记录。")
  }
  for (code, words) in value.orders ?? [:] {
   guard !words.isEmpty, Set(words).count == words.count else {
    throw DictionaryError(message: "用户词库排序包含空列表或重复词条。")
   }
   for word in words {
    guard try pair(code: code, word: word) == WordPair(code: code, word: word) else {
     throw DictionaryError(message: "用户词库排序含非规范词条。")
    }
   }
  }
  return value
 }

 private func readUserData() throws -> Data? {
  // A missing file is an empty overlay; permission and malformed-file errors are
  // never treated as empty state, since that would erase existing user edits.
  do { return try Data(contentsOf: userURL) }
  catch let error as NSError {
   if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
   // Foundation reports ENOTDIR when a new target's parent is an ordinary file.
   if !FileManager.default.fileExists(atPath: userURL.path),
      (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(ENOTDIR) { return nil }
   throw error
  }
 }

 func reloadIfChanged() throws {
  let data = try readUserData()
  guard data != lastData else { return }
  let value = try data.map(Self.decode) ?? UserDictionary()
  publish(value, data: data)
 }

 private func publish(_ value: UserDictionary, data: Data?) {
  matchCache.removeAll()
  changes = value
  lastData = data
  addedByCode = [:]
  for p in value.added { addedByCode[p.code, default: []].append(p.word) }
  removedSet = Set(value.removed)
 }

 private func orderedWords(for code: String, in value: UserDictionary, added: [String]? = nil) -> [String] {
  let available = (added ?? value.added.filter { $0.code == code }.map { $0.word }) + (base[code] ?? [])
  let known = Set(available)
  var seen = Set<String>()
  return ((value.orders?[code] ?? []).filter { known.contains($0) } + available).filter { seen.insert($0).inserted }
 }

 func candidates(for code: String) -> [String] {
  let normalized = code.lowercased()
  return orderedWords(for: normalized, in: changes, added: addedByCode[normalized] ?? []).filter {
   !removedSet.contains(WordPair(code: normalized, word: $0))
  }
 }

 /// Same-length matches first, then longer codes. Each z matches one a–y letter.
 /// Wildcard candidates carry their actual code for display and dictionary edits.
 func matchingCandidates(for code: String) -> [InputCandidate] {
  let code = code.lowercased()
  guard !code.isEmpty, code.utf8.count <= 4, code.utf8.allSatisfy({ (97...122).contains($0) }) else { return [] }
  if let cached = matchCache[code] { return cached }
  let matchingCodes: Set<String>
  if code.contains("z") {
   let pattern = Array(code.utf8)
   let literalPrefix = String(code.prefix { $0 != "z" })
   // Scan only existing codes, never expand 25^N wildcard combinations.
   let baseCodes = literalPrefix.isEmpty ? Array(base.keys) : (prefixCodes[literalPrefix] ?? [])
   matchingCodes = Set((baseCodes + addedByCode.keys).filter { fullCode in
    fullCode.utf8.count >= pattern.count && zip(pattern, fullCode.utf8).allSatisfy { $0 == 122 || $0 == $1 }
   })
  } else {
   matchingCodes = Set([code] + (prefixCodes[code] ?? []) + addedByCode.keys.filter { $0.hasPrefix(code) })
  }
  let codes = matchingCodes.sorted {
   if $0.count != $1.count { return $0.count < $1.count }
   let left = codeRanks[$0] ?? 0, right = codeRanks[$1] ?? 0
   return left == right ? $0 < $1 : left < right
  }
  var seen = Set<String>()
  let matches = codes.flatMap { fullCode in
   candidates(for: fullCode).compactMap { word -> InputCandidate? in
    guard seen.insert(word).inserted else { return nil }
    return InputCandidate(word: word, code: fullCode, completion: fullCode != code)
   }
  }
  if matchCache.count >= 64 { matchCache.removeAll() }
  matchCache[code] = matches
  return matches
 }

 func rows(for code: String) -> [DictionaryRow] {
  let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  let custom = Set(addedByCode[normalized] ?? [])
  return orderedWords(for: normalized, in: changes, added: addedByCode[normalized] ?? []).map {
   DictionaryRow(code: normalized, word: $0, source: custom.contains($0) ? "自造词" : "搜狗基础词库",
                 deleted: removedSet.contains(WordPair(code: normalized, word: $0)))
  }
 }

 /// Move one position among visible candidates, preserving deleted entries' slots.
 func move(code: String, word: String, offset: Int) throws {
  let pair = try Self.pair(code: code, word: word)
  guard offset == -1 || offset == 1 else { throw DictionaryError(message: "每次只能上移或下移一位。") }
  try mutate { value in
   var words = orderedWords(for: pair.code, in: value)
   let removed = Set(value.removed)
   let visibleIndices = words.indices.filter { !removed.contains(WordPair(code: pair.code, word: words[$0])) }
   guard let position = visibleIndices.firstIndex(where: { words[$0] == pair.word }) else {
    throw DictionaryError(message: "没有找到可排序的词条，请刷新后重试。")
   }
   let destination = position + offset
   guard visibleIndices.indices.contains(destination) else { return }
   words.swapAt(visibleIndices[position], visibleIndices[destination])
   if value.orders == nil { value.orders = [:] }
   value.orders?[pair.code] = words
  }
 }

 private func mutate(_ operation: (inout UserDictionary) throws -> Void) throws {
  let directory = userURL.deletingLastPathComponent()
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let lockFD = open(userURL.path + ".lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
  guard lockFD >= 0 else { throw DictionaryError(message: "无法锁定用户词库：\(String(cString: strerror(errno)))") }
  defer { flock(lockFD, LOCK_UN); close(lockFD) }
  guard flock(lockFD, LOCK_EX) == 0 else { throw DictionaryError(message: "无法取得词库写入锁。") }
  let previous = try readUserData()
  var next = try previous.map(Self.decode) ?? UserDictionary()
  try operation(&next)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(next)
  try data.write(to: userURL, options: .atomic)
  publish(next, data: data)
 }

 func add(code: String, word: String) throws {
  let pair = try Self.pair(code: code, word: word)
  try mutate { value in
   value.removed.removeAll { $0 == pair }
   value.added.removeAll { $0 == pair }
   value.added.insert(pair, at: 0)
   if value.orders?[pair.code] != nil {
    value.orders?[pair.code]?.removeAll { $0 == pair.word }
    value.orders?[pair.code]?.insert(pair.word, at: 0)
   }
  }
 }
 func remove(code: String, word: String) throws {
  let pair = try Self.pair(code: code, word: word)
  try mutate { value in
   guard base[pair.code]?.contains(pair.word) == true || value.added.contains(pair) else {
    throw DictionaryError(message: "没有找到此编码下的词条。")
   }
   if !value.removed.contains(pair) { value.removed.append(pair) }
  }
 }
 func restore(code: String, word: String) throws {
  let pair = try Self.pair(code: code, word: word)
  try mutate { $0.removed.removeAll { $0 == pair } }
 }
 func exportChanges(to url: URL) throws {
  try reloadIfChanged()
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(changes).write(to: url, options: .atomic)
 }
 /// Merge the imported overlay. Imported removals win over existing visibility;
 /// existing custom words remain in place and are never silently replaced.
 func importChanges(from url: URL) throws {
  let imported = try Self.decode(Data(contentsOf: url))
  try mutate { value in
   var added = Set(value.added)
   for p in imported.added where added.insert(p).inserted { value.added.append(p) }
   var removed = Set(value.removed)
   for p in imported.removed where removed.insert(p).inserted { value.removed.append(p) }
   if let orders = imported.orders {
    if value.orders == nil { value.orders = [:] }
    value.orders?.merge(orders) { _, imported in imported }
   }
  }
 }
}
