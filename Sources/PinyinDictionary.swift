import Foundation

final class PinyinDictionary {
 private var words: [String: [(word: String, rank: Int)]] = [:]
 private let codes: [String]
 private var cache: [String: [InputCandidate]] = [:]
 init(url: URL) throws {
  for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n").dropFirst() {
   let fields = line.split(separator: "\t")
   guard fields.count == 3, let rank = Int(fields[2]) else { throw DictionaryError(message: "拼音词库格式无效，请重新安装。") }
   words[String(fields[0]), default: []].append((String(fields[1]), rank))
  }
  guard !words.isEmpty else { throw DictionaryError(message: "拼音词库为空，请重新安装。") }
  codes = words.keys.sorted()
 }
 func candidates(for input: String) -> [InputCandidate] {
  let input = input.lowercased().replacingOccurrences(of: "'", with: "")
  guard !input.isEmpty else { return [] }
  if let value = cache[input] { return value }
  var low = 0, high = codes.count
  while low < high {
   let mid = (low + high) / 2
   if codes[mid] < input { low = mid + 1 } else { high = mid }
  }
  var entries: [(word: String, code: String, rank: Int)] = []
  for index in low..<codes.count {
   let code = codes[index]
   guard code.hasPrefix(input) else { break }
   for entry in words[code] ?? [] { entries.append((entry.word, code, entry.rank)) }
  }
  entries.sort {
   if ($0.code == input) != ($1.code == input) { return $0.code == input }
   if $0.rank != $1.rank { return $0.rank < $1.rank }
   return $0.word == $1.word ? $0.code < $1.code : $0.word < $1.word
  }
  var seen = Set<String>()
  let result = entries.compactMap { entry -> InputCandidate? in
   guard seen.insert(entry.word).inserted else { return nil }
   return InputCandidate(word: entry.word, code: entry.code, completion: entry.code != input)
  }
  if cache.count >= 64 { cache.removeAll() }
  cache[input] = result
  return result
 }
}
