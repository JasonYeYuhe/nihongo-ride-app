/// Blind romaji → hiragana, the direction the typing engine never needs.
///
/// `KanaInputMatcher` is target-aware: it knows the word and asks whether a key is on a path to
/// it. A search box has no target — "mizu" has to become みず before there is anything to compare
/// with — so this reads the same Mozc table the other way round, by longest match, the way an IME
/// converts as you type. It exists for word search (`VocabKit.WordSearchIndex`, v1.35 §B6) and
/// answers nothing rather than a partial reading, because a half-converted query ("みz") matches
/// nothing a learner meant.
///
/// **ん is where blind reading and the ride part ways.** The table has four keys for ん — `n'`,
/// `nn`, `xn` and `n` — and the ride accepts every one of them anywhere a ん is, because it knows
/// the word: for 単位 (たんい) it takes `tan'i`, `tanni`, `taxni` and `tani` alike. Blind, three of
/// those are ambiguous before a vowel or `y`: `tanni` could be たんい or たんに, `tani` たんい or
/// たに. So a query does not have one reading but a few (`readings`), and search matches any of
/// them: a learner who spells ん the way the ride let them spell it finds the word.
public enum RomajiReading {

    /// How many ambiguous `n`s one query branches on — the first four it meets, in reading order.
    /// Each doubles the readings, so four is at most sixteen, and it bounds the work: without it a
    /// query of twenty `na`s followed by a letter that reads as nothing would try 2²⁰ paths before
    /// answering none. Past the fourth, an ambiguous `n` takes the IME's reading only. No corpus
    /// word needs more: `WordSearchTests.everyNSpellingFindsTheWord` spells every entry whose
    /// hint has an `n'` each way the ride accepts, and all are found.
    public static let maxAmbiguousN = 4

    /// The IME's reading of `romaji` — the first of `readings`: `nn` before a vowel is ん and
    /// then the n-row, `n` before a vowel is the n-row. Nil when it is not romaji all the way
    /// through.
    public static func hiragana(fromRomaji romaji: String, table: RomajiKanaTable = .shared) -> String? {
        readings(fromRomaji: romaji, table: table).first
    }

    /// Every hiragana `romaji` can spell under the ride's ん keys, the IME's reading first, no
    /// repeats; empty when it is not romaji all the way through.
    ///
    /// * Input is lowercased first; only `a`–`z`, `-` (the long-vowel mark ー, the table's own
    ///   rule) and `'` (after n: `kin'youbi`) are romaji. Anything else — a space, a digit, a
    ///   comma the Mozc table would happily turn into 、 — is not, and the answer is empty.
    /// * **`nn` before a vowel or `y`** reads first as ん and then the n-row ("konnichiha" →
    ///   こんにちは, "onna" → おんな — what a learner who types them usually means; a plain longest
    ///   match would read the table's `nn` first and give こんいちは), and also as the table's
    ///   `nn` → ん with the vowel bare ("tanni" → たんい, as the ride takes it). After the first
    ///   reading's ん the next `n` is the n-row only: こんんいちは is nobody's word.
    /// * **`n` before a vowel or `y`** reads first as the n-row ("tani" → たに) and also as ん with
    ///   the vowel bare ("tani" → たんい, "kinyoubi" → きんようび).
    /// * `n'` and `xn` are ん wherever they are, and `nn` before anything else is ん ("kannji" →
    ///   かんじ); a lone final `n` is ん ("hon" → ほん). Those are the table's own keys.
    /// * Sokuon comes from the table's pending rules (`kk` → っ, leaving `k`), exactly as the
    ///   engine types it.
    /// * Each reading must be kana (hiragana, ー, and the small ヵ/ヶ the table keeps in
    ///   katakana); a path on which a key produced anything else — `zh` → ←, `www` → w — is
    ///   dropped.
    ///
    /// Every step consumes input: a table key is taken only when it leaves pending fewer letters
    /// than it read (the longest pending in the table is two letters, `tch` → っ leaving `ch`),
    /// and the ん branches consume one or two letters. So every path ends.
    public static func readings(fromRomaji romaji: String, table: RomajiKanaTable = .shared) -> [String] {
        let lowered = romaji.lowercased()
        guard !lowered.isEmpty,
              lowered.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || $0 == "-" || $0 == "'" })
        else { return [] }
        var results: [String] = []
        var seen = Set<String>()
        walk(Array(lowered), output: "", nRowOnly: false, branchesLeft: maxAmbiguousN,
             table: table, results: &results, seen: &seen)
        return results
    }

    private static let vowelsAndY: Set<Character> = ["a", "i", "u", "e", "o", "y"]

    private static func walk(_ remaining: [Character], output: String, nRowOnly: Bool, branchesLeft: Int,
                             table: RomajiKanaTable, results: inout [String], seen: inout Set<String>) {
        guard !remaining.isEmpty else {
            if isKana(output), seen.insert(output).inserted { results.append(output) }
            return
        }
        // Every ambiguous n spends one of the budget whichever way it is read, so a path meets at
        // most `maxAmbiguousN` forks and there are at most 2^maxAmbiguousN paths. (Spending it
        // only on the ん side, the first version, bounded forks TAKEN per path, not paths: forty
        // n's still gave C(40, ≤4) ≈ 100,000 of them — `branchesAreBounded` measured 1.5 s.)
        let canBranch = branchesLeft > 0
        let left = max(branchesLeft - 1, 0)
        if remaining[0] == "n", !nRowOnly {
            if remaining.count >= 3, remaining[1] == "n", vowelsAndY.contains(remaining[2]) {
                // ん, then the second n starts the n-row: konnichiha → こんにちは.
                walk(Array(remaining.dropFirst()), output: output + "ん", nRowOnly: true,
                     branchesLeft: left, table: table, results: &results, seen: &seen)
                // The table's nn → ん, the vowel bare: tanni → たんい.
                if canBranch {
                    walk(Array(remaining.dropFirst(2)), output: output + "ん", nRowOnly: false,
                         branchesLeft: left, table: table, results: &results, seen: &seen)
                }
                return
            }
            if remaining.count >= 2, vowelsAndY.contains(remaining[1]) {
                // The n-row first, then ん with the vowel bare: tani → たに, たんい.
                longestMatch(remaining, output: output, branchesLeft: left,
                             table: table, results: &results, seen: &seen)
                if canBranch {
                    walk(Array(remaining.dropFirst()), output: output + "ん", nRowOnly: false,
                         branchesLeft: left, table: table, results: &results, seen: &seen)
                }
                return
            }
        }
        longestMatch(remaining, output: output, branchesLeft: branchesLeft,
                     table: table, results: &results, seen: &seen)
    }

    /// The table read by longest match at the head of `remaining`.
    private static func longestMatch(_ remaining: [Character], output: String, branchesLeft: Int,
                                     table: RomajiKanaTable, results: inout [String], seen: inout Set<String>) {
        var length = min(table.maxRomajiLength, remaining.count)
        while length > 0 {
            if let production = table.producerByRomaji[String(remaining[0..<length])] {
                // A key that leaves as much pending as it read would not move: refuse it.
                guard production.pending.count < length else { return }
                walk(Array(production.pending) + remaining[length...], output: output + production.output,
                     nRowOnly: false, branchesLeft: branchesLeft, table: table, results: &results, seen: &seen)
                return
            }
            length -= 1
        }
    }

    private static func isKana(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            (0x3041...0x3096).contains(scalar.value) || scalar.value == 0x30FC
                || scalar.value == 0x30F5 || scalar.value == 0x30F6
        }
    }
}
