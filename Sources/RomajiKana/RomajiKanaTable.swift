import Foundation

/// A single romaji→kana production rule from the Mozc table.
///
/// - `romaji`:  the romaji input (already includes any `pending` prefix carried
///              over from a previous rule).
/// - `output`:  the kana produced (1–2 characters, e.g. `か`, `きゃ`, `っ`).
/// - `pending`: leftover romaji the converter keeps as already-typed input for
///              the *next* rule — this is the sokuon/gemination mechanism
///              (`kk → っ` leaves `k`, `tch → っ` leaves `ch`). Empty for most rules.
struct Production: Sendable, Hashable {
    let romaji: String
    let output: String
    let pending: String
}

/// Romaji→kana mapping data, indexed by kana output for target-aware matching.
///
/// Backed by Google Mozc's `romanji-hiragana.tsv` (BSD-3-Clause).
/// See `THIRD_PARTY_LICENSES.md`.
public struct RomajiKanaTable: Sendable {
    /// All productions whose `output` equals the key.
    let producersByOutput: [String: [Production]]
    /// Longest kana `output` length (for slicing the target). Typically 2.
    let maxOutputLength: Int
    /// The production each romaji key names — the direction a blind conversion reads the table
    /// (`RomajiReading`). First wins on a repeated key: the Mozc file lists `fu` twice, both
    /// times as ふ.
    let producerByRomaji: [String: Production]
    /// Longest romaji key, for the longest-match scan in `RomajiReading`.
    let maxRomajiLength: Int
    /// Every proper prefix of a romaji key ("t" of "ta", "ch" of "chi", "ts" of "tsu"): what a
    /// query can end in while the learner is still typing a kana. `RomajiReading.partialReadings`
    /// reads the text before such a tail.
    let incompleteKeys: Set<String>

    /// The shared default table, parsed once from the bundled Mozc resource.
    public static let shared = RomajiKanaTable.loadBundled()

    init(productions: [Production]) {
        var byOutput: [String: [Production]] = [:]
        var byRomaji: [String: Production] = [:]
        var maxLen = 1
        var maxRomaji = 1
        var incomplete = Set<String>()
        for production in productions where !production.output.isEmpty {
            byOutput[production.output, default: []].append(production)
            maxLen = max(maxLen, production.output.count)
            if byRomaji[production.romaji] == nil { byRomaji[production.romaji] = production }
            maxRomaji = max(maxRomaji, production.romaji.count)
            var prefix = production.romaji
            while prefix.count > 1 {
                prefix.removeLast()
                incomplete.insert(prefix)
            }
        }
        producersByOutput = byOutput
        maxOutputLength = maxLen
        producerByRomaji = byRomaji
        maxRomajiLength = maxRomaji
        incompleteKeys = incomplete
    }

    /// Productions that output exactly `kana`.
    func productions(forOutput kana: String) -> [Production] {
        producersByOutput[kana] ?? []
    }

    // MARK: Loading & parsing

    static func loadBundled() -> RomajiKanaTable {
        guard let url = Bundle.module.url(forResource: "romaji-hiragana", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("RomajiKana: bundled romaji-hiragana.tsv is missing")
            return RomajiKanaTable(productions: [])
        }
        return RomajiKanaTable(productions: parse(text))
    }

    /// Parses the Mozc TSV format: `romaji <TAB> kana [<TAB> pending]` per line.
    static func parse(_ text: String) -> [Production] {
        var productions: [Production] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }
            let romaji = String(columns[0])
            let output = String(columns[1])
            guard !romaji.isEmpty, !output.isEmpty else { continue }
            let pending = columns.count >= 3 ? String(columns[2]) : ""
            productions.append(Production(romaji: romaji, output: output, pending: pending))
        }
        return productions
    }
}
