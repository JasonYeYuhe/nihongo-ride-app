/// Blind romaji → hiragana, the direction the typing engine never needs.
///
/// `KanaInputMatcher` is target-aware: it knows the word and asks whether a key is on a path to
/// it. A search box has no target — "mizu" has to become みず before there is anything to compare
/// with — so this reads the same Mozc table the other way round, by longest match, the way an IME
/// converts as you type. It exists for word search (`VocabKit.WordSearchIndex`, v1.35 §B6).
/// `readings` answers nothing rather than a half-conversion, because "みz" matches nothing a
/// learner meant; `partialReadings` answers what an IME would show while the learner is still
/// typing — the reading before the unfinished tail, み for "miz" — which search matches as the
/// start of a word.
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
        collect(romaji, partial: false, table: table)
    }

    /// The readings of a query that stops partway through a kana — what the IME shows while the
    /// learner is still typing: "tabem" → たべ, "miz" → み, "gakk" → がっ, "kiny" → きん and き. Each is
    /// the reading of the query's longest complete prefix, on a path whose remaining letters are a
    /// proper prefix of a table key ("m" of "ma", "ch" of "chi"), so more typing could complete
    /// them. A lone final `n` is such a tail as well as ん ("tabemon" → たべも, the start of
    /// たべもの, besides `readings`' たべもん), because "n" is also the start of "na". Empty when the query is not romaji up to that tail, when
    /// the tail could not become a key ("mizq"), or when nothing before the tail reads ("sh").
    /// Never a reading `readings` already gives. The ん alternatives are read as in `readings`,
    /// the IME's first.
    ///
    /// Why search needs it (v1.35 §B6 review): without it every keystroke that ended mid-kana read
    /// as nothing, so "tabemono" typed a letter at a time found words at た, none at "tab", some at
    /// "tabe", none at "tabem" — the result list flashed empty and VoiceOver announced it: measured
    /// on the tree before this, 32 announcements over the 61 keystrokes of eight learner words, 64
    /// over 136 for twenty (`V135B6WordSearchTests.typingAWordAnnouncesAtMostTwice` has the list).
    public static func partialReadings(fromRomaji romaji: String, table: RomajiKanaTable = .shared) -> [String] {
        let complete = Set(collect(romaji, partial: false, table: table))
        return collect(romaji, partial: true, table: table).filter { !complete.contains($0) }
    }

    private static func collect(_ romaji: String, partial: Bool, table: RomajiKanaTable) -> [String] {
        let lowered = romaji.lowercased()
        guard !lowered.isEmpty,
              lowered.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || $0 == "-" || $0 == "'" })
        else { return [] }
        var results: [String] = []
        var seen = Set<String>()
        var walker = Walker(table: table, partial: partial)
        walker.walk(Array(lowered), output: "", nRowOnly: false, branchesLeft: maxAmbiguousN)
        for reading in walker.results where seen.insert(reading).inserted { results.append(reading) }
        return results
    }

    private static let vowelsAndY: Set<Character> = ["a", "i", "u", "e", "o", "y"]

    /// One walk over the query. `partial` false records the paths that read to the end (`readings`);
    /// true records, instead, the output of the paths that stop at a tail more typing could
    /// complete (`partialReadings`). The branching is the same in both.
    private struct Walker {
        let table: RomajiKanaTable
        let partial: Bool
        var results: [String] = []

        mutating func record(_ output: String) {
            if !output.isEmpty, isKana(output) { results.append(output) }
        }

        mutating func walk(_ remaining: [Character], output: String, nRowOnly: Bool, branchesLeft: Int) {
            guard !remaining.isEmpty else {
                if !partial { record(output) }
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
                    walk(Array(remaining.dropFirst()), output: output + "ん", nRowOnly: true, branchesLeft: left)
                    // The table's nn → ん, the vowel bare: tanni → たんい.
                    if canBranch {
                        walk(Array(remaining.dropFirst(2)), output: output + "ん", nRowOnly: false, branchesLeft: left)
                    }
                    return
                }
                if remaining.count >= 2, vowelsAndY.contains(remaining[1]) {
                    // The n-row first, then ん with the vowel bare: tani → たに, たんい.
                    longestMatch(remaining, output: output, branchesLeft: left)
                    if canBranch {
                        walk(Array(remaining.dropFirst()), output: output + "ん", nRowOnly: false, branchesLeft: left)
                    }
                    return
                }
            }
            longestMatch(remaining, output: output, branchesLeft: branchesLeft)
        }

        /// The table read by longest match at the head of `remaining`.
        mutating func longestMatch(_ remaining: [Character], output: String, branchesLeft: Int) {
            // Everything left is the start of a key: the learner is mid-kana. Checked before a
            // shorter key is taken, because one can be: "ny" is on its way to にゃ/にょ, and a lone
            // final "n" to the n-row ("tabemon" → たべも, for たべもの), though "n" alone is also ん
            // (which the path below still reads, for `readings`).
            if partial, table.incompleteKeys.contains(String(remaining)) { record(output) }
            var length = min(table.maxRomajiLength, remaining.count)
            while length > 0 {
                if let production = table.producerByRomaji[String(remaining[0..<length])] {
                    // A key that leaves as much pending as it read would not move: refuse it.
                    guard production.pending.count < length else { return }
                    walk(Array(production.pending) + remaining[length...], output: output + production.output,
                         nRowOnly: false, branchesLeft: branchesLeft)
                    return
                }
                length -= 1
            }
        }
    }

    private static func isKana(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            (0x3041...0x3096).contains(scalar.value) || scalar.value == 0x30FC
                || scalar.value == 0x30F5 || scalar.value == 0x30F6
        }
    }
}
