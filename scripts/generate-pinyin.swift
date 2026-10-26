import Foundation

// Offline, deterministic index generated using macOS transliteration data.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: CommandLine.arguments[2])
var ranks: [String: Int] = [:]
for line in try String(contentsOf: source, encoding: .utf8).split(separator: "\n").dropFirst() {
 let fields = line.split(separator: "\t")
 guard fields.count == 4, let rank = Int(fields[2]) else { continue }
 let word = String(fields[1])
 ranks[word] = min(ranks[word] ?? Int.max, rank)
}
var lines = ["pinyin\tword\trank"]
for word in ranks.keys.sorted() {
 guard let latin = word.applyingTransform(.toLatin, reverse: false) else { continue }
 let umlaut = latin.decomposedStringWithCanonicalMapping.replacingOccurrences(of: "u\u{0308}", with: "v", options: .literal)
 guard let plain = umlaut.applyingTransform(.stripDiacritics, reverse: false) else { continue }
 let code = plain.lowercased().filter { !$0.isWhitespace }
 guard !code.isEmpty, code.count <= 128, code.utf8.allSatisfy({ (97...122).contains($0) }) else { continue }
 lines.append("\(code)\t\(word)\t\(ranks[word]!)")
}
try (lines.joined(separator: "\n") + "\n").write(to: target, atomically: true, encoding: .utf8)
print("Generated \(lines.count - 1) offline pinyin entries")
