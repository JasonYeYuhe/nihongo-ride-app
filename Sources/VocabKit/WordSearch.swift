import Foundation
import RomajiKana

/// Search over the corpus for the Word Lists screen (v1.35 §B6): "the N4 verbs I know I am weak
/// on" can be added before riding, instead of only by meeting them in a ride.
///
/// **What a query matches.** Substring over each entry's written form, its reading and every
/// gloss in every language the entry carries (en and zh today). Both sides are folded the same
/// way (`fold`): NFKC (full-width Latin and half-width katakana become what a learner means),
/// katakana → hiragana through `KanaScript` — the one rule the typing engine uses, not a second
/// copy — lowercased, and a dash typed after kana read as the long-vowel mark ー. A Latin query
/// that is romaji all the way through (`RomajiReading`) is ALSO matched as the hiragana it spells
/// against the written form and the reading, so "mizu" finds 水/みず while "water" still finds
/// it by its gloss.
///
/// **Ranking.** Three tiers, best first: exact (a whole field equals the query — the written
/// form, the reading, or one gloss item), prefix (a field starts with it; for a gloss, any word
/// in it does, so "eat" is a prefix of "to eat"), substring (anywhere). An entry takes the best
/// tier any of its fields reaches. Within a tier, N5 first, then corpus order.
///
/// **What it never returns.** A duplicate — the index keeps the first entry for an id, as
/// `VocabStore.entry(id:)` does. And a retired word: this corpus retires a word by DELETING the
/// entry (`scripts/check_vocab_diff.py` allows a deletion only with a manifest naming its
/// replacement — `docs/measurements/n3-retirement-manifest.json`, `v121-section-c-manifest.json`),
/// so every entry this index holds is a word the app can ride. The shipped-corpus test pins the
/// three retired ids by name.
///
/// **Cost.** Built once from the entries (`VocabStore.search` builds it on first use, not at
/// launch); a query is a scan of pre-folded UTF-8 bytes. Byte comparison of valid UTF-8 is
/// code-point comparison — a match can only begin on a scalar boundary — which is the rule the
/// corpus residue tests settled on after grapheme comparison proved storage-dependent.
public struct WordSearchIndex: Sendable {

    public enum Tier: Int, Comparable, Sendable {
        case exact = 0, prefix, substring
        public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    struct Row: Sendable {
        let entry: VocabEntry
        let order: Int
        let surface: [UInt8]
        let kana: [UInt8]
        let glosses: [[UInt8]]
    }

    let rows: [Row]

    public init(entries: [VocabEntry]) {
        var seen = Set<String>()
        var rows: [Row] = []
        rows.reserveCapacity(entries.count)
        for (order, entry) in entries.enumerated() where seen.insert(entry.id).inserted {
            // Every language the entry carries, in a fixed order so the index does not depend on
            // dictionary iteration: en, zh, then any other language by code.
            let languages = entry.meanings.keys.sorted { a, b in
                let rank = { (code: String) -> Int in code == "en" ? 0 : code == "zh" ? 1 : 2 }
                return rank(a) != rank(b) ? rank(a) < rank(b) : a < b
            }
            let glosses = languages.flatMap { entry.meanings[$0] ?? [] }
                .map { Array(Self.fold($0).utf8) }
                .filter { !$0.isEmpty }
            rows.append(Row(entry: entry, order: order,
                            surface: Array(Self.fold(entry.surface).utf8),
                            kana: Array(Self.fold(entry.kana).utf8),
                            glosses: glosses))
        }
        self.rows = rows
    }

    /// At most `limit` entries matching `query`, best first. Empty or whitespace → none.
    public func search(_ query: String, limit: Int) -> [VocabEntry] {
        matches(query, limit: limit).map(\.entry)
    }

    /// The same search with each result's tier — what the ranking tests read.
    public func matches(_ query: String, limit: Int) -> [(entry: VocabEntry, tier: Tier)] {
        guard limit > 0 else { return [] }
        let words = query.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return [] }
        let folded = Self.fold(words.joined(separator: " "))
        guard !folded.isEmpty else { return [] }
        let text = Array(folded.utf8)
        let reading = RomajiReading.hiragana(fromRomaji: folded).map { Array($0.utf8) }

        var found: [(row: Int, tier: Tier)] = []
        for index in rows.indices {
            let row = rows[index]
            var best = Self.tier(of: row.surface, query: text, wordStarts: false)
            best = Self.better(best, Self.tier(of: row.kana, query: text, wordStarts: false))
            if best != .exact {
                for gloss in row.glosses {
                    best = Self.better(best, Self.tier(of: gloss, query: text, wordStarts: true))
                    if best == .exact { break }
                }
            }
            if let reading, best != .exact {
                best = Self.better(best, Self.tier(of: row.kana, query: reading, wordStarts: false))
                best = Self.better(best, Self.tier(of: row.surface, query: reading, wordStarts: false))
            }
            if let best { found.append((index, best)) }
        }
        found.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            let ra = rows[a.row], rb = rows[b.row]
            if ra.entry.jlpt != rb.entry.jlpt { return ra.entry.jlpt < rb.entry.jlpt }
            return ra.order < rb.order
        }
        return found.prefix(limit).map { (rows[$0.row].entry, $0.tier) }
    }

    // MARK: Folding

    /// The one normalisation both the corpus and a query go through.
    public static func fold(_ text: String) -> String {
        let normalised = KanaScript.katakanaToHiragana(text.precomposedStringWithCompatibilityMapping)
            .lowercased()
        var scalars = String.UnicodeScalarView()
        var previousIsKana = false
        for scalar in normalised.unicodeScalars {
            // A dash typed after kana is the long-vowel mark: こ-ひ- is こーひー. After anything
            // else it is a dash ("T-shirt", "well-known") and stays one.
            if previousIsKana, dashes.contains(scalar.value) {
                scalars.append("ー")
                continue
            }
            scalars.append(scalar)
            previousIsKana = (0x3041...0x3096).contains(scalar.value) || scalar.value == 0x30FC
        }
        return String(scalars)
    }

    /// Hyphen-minus, the Unicode hyphens and dashes, and the minus sign. NFKC has already turned
    /// the full-width hyphen-minus into "-" and the half-width ｰ into ー.
    private static let dashes: Set<UInt32> = [0x2D, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212]

    // MARK: Matching

    private static func better(_ a: Tier?, _ b: Tier?) -> Tier? {
        guard let a else { return b }
        guard let b else { return a }
        return min(a, b)
    }

    /// How `query` sits in `field`: equal, at the start (or, with `wordStarts`, at the start of
    /// any word), anywhere, or not at all.
    static func tier(of field: [UInt8], query: [UInt8], wordStarts: Bool) -> Tier? {
        let n = field.count, m = query.count
        guard m > 0, n >= m else { return nil }
        if n == m { return field == query ? .exact : nil }
        return field.withUnsafeBufferPointer { f in
            query.withUnsafeBufferPointer { q in
                if memcmp(f.baseAddress!, q.baseAddress!, m) == 0 { return .prefix }
                var found: Tier?
                let first = q[0]
                var i = 1
                while i <= n - m {
                    if f[i] == first, memcmp(f.baseAddress! + i, q.baseAddress!, m) == 0 {
                        if !wordStarts { return .substring }
                        if isWordBoundary(f[i - 1]) { return .prefix }
                        found = .substring
                    }
                    i += 1
                }
                return found
            }
        }
    }

    /// An ASCII byte that is not a letter or a digit: a space, a bracket, a slash, a comma. The
    /// continuation bytes of a multi-byte scalar are ≥ 0x80 and never count.
    private static func isWordBoundary(_ byte: UInt8) -> Bool {
        guard byte < 0x80 else { return false }
        let isDigit = (0x30...0x39).contains(byte)
        let isLetter = (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
        return !isDigit && !isLetter
    }
}
