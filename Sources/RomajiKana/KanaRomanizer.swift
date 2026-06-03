/// Generates a Hepburn-style romaji hint for a kana string (the "罗马字提示").
///
/// The output is chosen to be both readable *and* a valid input for
/// ``KanaInputMatcher`` (see the `hintIsTypable` property test): sokuon `っ`
/// becomes a doubled consonant (`がっこう → "gakkou"`, `まっちゃ → "matcha"`),
/// and `ん` gets an apostrophe before a vowel or `y` to stay unambiguous
/// (`れんあい → "ren'ai"`, `きんようび → "kin'youbi"`).
///
/// Note: rare `ぢ`/`づ` use the typeable `di`/`du` rather than Hepburn `ji`/`zu`
/// so the hint always round-trips through the matcher.
public enum KanaRomanizer {
    public static func romaji(for kana: String) -> String {
        // Normalize katakana → hiragana so loanword readings romanize too.
        let characters = Array(KanaScript.katakanaToHiragana(kana))
        var result = ""
        var index = 0
        while index < characters.count {
            let (romaji, consumed) = segment(characters, at: index)
            result += romaji
            index += consumed
        }
        return result
    }

    /// Romanizes the kana segment starting at `index`, returning the romaji and
    /// the number of kana characters consumed (1, or 2 for a youon cluster).
    private static func segment(_ characters: [Character], at index: Int) -> (String, Int) {
        let kana = characters[index]

        // Youon cluster: base kana + small ゃ/ゅ/ょ.
        if index + 1 < characters.count,
           let cluster = youon[String(kana) + String(characters[index + 1])] {
            return (cluster, 2)
        }

        // Foreign-sound digraph (katakana loanwords): base kana + small vowel.
        if index + 1 < characters.count,
           let cluster = foreign[String(kana) + String(characters[index + 1])] {
            return (cluster, 2)
        }

        switch kana {
        case "っ":   // sokuon — geminate the following consonant
            let next = peek(characters, at: index + 1)
            if next.hasPrefix("ch") { return ("t", 1) }                 // っち → "tchi"
            if let first = next.first, !"aiueo".contains(first) { return (String(first), 1) }
            return ("xtsu", 1)                                          // っ with no consonant after (rare)

        case "ん":   // hatsuon — apostrophe before a vowel or y to disambiguate
            let next = peek(characters, at: index + 1)
            if let first = next.first, "aiueoy".contains(first) { return ("n'", 1) }
            return ("n", 1)

        case "ー":   // prolonged-sound mark (katakana) — typed with the '-' key
            return ("-", 1)

        default:
            return (base[String(kana)] ?? String(kana), 1)
        }
    }

    /// The romaji of the next segment, used only to pick a gemination consonant
    /// or decide on `ん`'s apostrophe.
    private static func peek(_ characters: [Character], at index: Int) -> String {
        guard index < characters.count else { return "" }
        return segment(characters, at: index).0
    }

    // MARK: Maps

    private static let base: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "だ": "da", "ぢ": "di", "づ": "du", "で": "de", "ど": "do",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "ゐ": "wi", "ゑ": "we", "を": "wo", "ゔ": "vu",
        // small kana standing alone — typeable x-forms
        "ぁ": "xa", "ぃ": "xi", "ぅ": "xu", "ぇ": "xe", "ぉ": "xo",
        "ゃ": "xya", "ゅ": "xyu", "ょ": "xyo", "ゎ": "xwa",
    ]

    /// Foreign-sound digraphs in katakana loanwords, with engine-typeable romaji.
    private static let foreign: [String: String] = [
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
        "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo", "ゔゅ": "vyu",
        "てぃ": "thi", "でぃ": "dhi", "とぅ": "twu", "どぅ": "dwu", "てゅ": "thu", "でゅ": "dhu",
        "うぃ": "wi", "うぇ": "we", "うぉ": "who",
        "しぇ": "she", "じぇ": "je", "ちぇ": "che", "ぢぇ": "dye",
        "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso",
        "きぇ": "kye", "にぇ": "nye", "ひぇ": "hye", "みぇ": "mye", "りぇ": "rye",
        "びぇ": "bye", "ぴぇ": "pye", "いぇ": "ye",
        "くぁ": "qa", "くぃ": "qi", "くぇ": "qe", "くぉ": "qo", "ぐぁ": "gwa",
    ]

    private static let youon: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "ぢゃ": "dya", "ぢゅ": "dyu", "ぢょ": "dyo",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
    ]
}
