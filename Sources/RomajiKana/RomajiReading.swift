/// Blind romaji → hiragana, the direction the typing engine never needs.
///
/// `KanaInputMatcher` is target-aware: it knows the word and asks whether a key is on a path to
/// it. A search box has no target — "mizu" has to become みず before there is anything to compare
/// with — so this reads the same Mozc table the other way round, by longest match, the way an IME
/// converts as you type. It exists for word search (`VocabKit.WordSearchIndex`, v1.35 §B6) and
/// answers nil rather than a partial reading, because a half-converted query ("みz") matches
/// nothing a learner meant.
public enum RomajiReading {

    /// The hiragana `romaji` spells, or nil when it is not romaji all the way through.
    ///
    /// * Input is lowercased first; only `a`–`z`, `-` (the long-vowel mark ー, the table's own
    ///   rule) and `'` (after n: `kin'youbi`) are romaji. Anything else — a space, a digit, a
    ///   comma the Mozc table would happily turn into 、 — is not, and the answer is nil.
    /// * **`nn` before a vowel or `y` is ん plus the n-row**, not the table's `nn` → ん: "konnichiha"
    ///   is こんにちは and "onna" is おんな, which is what a learner who types them means. A plain
    ///   longest match reads the table's `nn` first and gives こんいちは (the test pins both). Elsewhere `nn` is ん as the table says ("kannji" → かんじ), and a lone final
    ///   `n` is ん ("hon" → ほん).
    /// * Sokuon comes from the table's pending rules (`kk` → っ, leaving `k`), exactly as the
    ///   engine types it.
    /// * The result must be kana (hiragana, ー, and the small ヵ/ヶ the table keeps in katakana);
    ///   a key that produced a symbol makes the whole answer nil.
    public static func hiragana(fromRomaji romaji: String, table: RomajiKanaTable = .shared) -> String? {
        let lowered = romaji.lowercased()
        guard !lowered.isEmpty,
              lowered.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || $0 == "-" || $0 == "'" })
        else { return nil }
        var remaining = Array(lowered)
        var output = ""
        // Every production consumes more than it leaves pending (the longest pending in the table
        // is one letter, for a two-letter key), so each step shortens `remaining`; the bound only
        // makes a table that broke that rule fail closed instead of spinning.
        var steps = 0
        while !remaining.isEmpty {
            steps += 1
            if steps > 4 * lowered.count + 4 { return nil }
            if remaining.count >= 3, remaining[0] == "n", remaining[1] == "n",
               "aiueoy".contains(remaining[2]) {
                output += "ん"
                remaining.removeFirst()
                continue
            }
            var matched: Production?
            var length = min(table.maxRomajiLength, remaining.count)
            while length > 0 {
                if let production = table.producerByRomaji[String(remaining[0..<length])] {
                    matched = production
                    break
                }
                length -= 1
            }
            guard let production = matched, production.pending.count < length else { return nil }
            output += production.output
            remaining = Array(production.pending) + remaining[length...]
        }
        guard output.unicodeScalars.allSatisfy({ scalar in
            (0x3041...0x3096).contains(scalar.value) || scalar.value == 0x30FC
                || scalar.value == 0x30F5 || scalar.value == 0x30F6
        }) else { return nil }
        return output
    }
}
