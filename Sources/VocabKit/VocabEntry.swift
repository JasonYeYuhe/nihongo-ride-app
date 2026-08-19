import Foundation
import RomajiKana

/// JLPT level. Raw value matches the level number (N5 = 5 … N1 = 1).
public enum JLPTLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case n5 = 5, n4 = 4, n3 = 3, n2 = 2, n1 = 1

    /// Display label, e.g. "N5".
    public var label: String { "N\(rawValue)" }

    /// 0 (easiest, N5) … 4 (hardest, N1). Used for difficulty ordering.
    public var difficultyRank: Int { 5 - rawValue }

    public static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool {
        lhs.difficultyRank < rhs.difficultyRank
    }
}

/// A vocabulary item the player types. The typing target is always ``kana``.
///
/// Meanings are multi-language, keyed by language code (`"en"`, `"zh"`, …), so
/// the UI can show the learner's preferred language with a sensible fallback.
public struct VocabEntry: Identifiable, Codable, Hashable, Sendable {
    /// Stable identifier.
    public let id: String
    /// Written form (kanji where standard), e.g. "学校". Equals ``kana`` for kana-only words.
    public let surface: String
    /// Reading in hiragana — the typing target, e.g. "がっこう".
    public let kana: String
    /// Part-of-speech tags, e.g. ["n"], ["v"], ["adj-i"].
    public let partsOfSpeech: [String]
    /// Derived verb-conjugation class, as a `VerbClass.rawValue` string (e.g. "ichidan",
    /// "godan_r", "suru"), or nil when the word isn't a conjugable verb OR its class is
    /// ambiguous/withheld (PLAN-V1.6 §B1). Stored as an opaque String so VocabKit stays
    /// free of any ConjugationKit dependency; GameCore maps it to `VerbClass`.
    public let vc: String?
    /// JLPT level.
    public let jlpt: JLPTLevel
    /// Meanings keyed by language code: `["en": ["school"], "zh": ["学校"]]`.
    public let meanings: [String: [String]]
    /// Optional example sentence (Japanese) and its translation.
    public let exampleJP: String?
    public let exampleEN: String?
    /// Optional example-sentence translation in Chinese.
    public let exampleZH: String?
    /// The example sentence's full reading — the typing target for sentence mode.
    ///
    /// Absent on 14 of 3,714 sentences, deliberately: a sentence whose reading could not be
    /// derived safely (digits, which Sudachi reads one digit at a time, so 10キロ becomes
    /// いちれいきろ) keeps its display text and is simply not offered as a target. A wrong
    /// target is worse than a missing one — the learner types the right thing and is marked
    /// wrong. `isTypeableSentence` is the check callers should use.
    public let exampleKana: String?
    /// Surface/reading pairs covering the example sentence, for furigana.
    ///
    /// Concatenating the surfaces reconstructs `exampleJP` exactly and the readings
    /// reconstruct `exampleKana` exactly; the generator refuses to emit anything else,
    /// because furigana that drifts puts a reading over the wrong character.
    public let exampleTokens: [[String]]?

    /// True when this entry can be used as a sentence-typing target.
    public var isTypeableSentence: Bool {
        guard let jp = exampleJP, !jp.isEmpty,
              let kana = exampleKana, !kana.isEmpty else { return false }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, surface, kana
        case partsOfSpeech = "pos"
        case vc
        case jlpt, meanings
        case exampleJP = "exJP"
        case exampleEN = "exEN"
        case exampleZH = "exZH"
        case exampleKana = "exKana"
        case exampleTokens = "exTokens"
    }

    public init(
        id: String,
        surface: String,
        kana: String,
        partsOfSpeech: [String],
        jlpt: JLPTLevel,
        meanings: [String: [String]],
        vc: String? = nil,
        exampleJP: String? = nil,
        exampleEN: String? = nil,
        exampleZH: String? = nil,
        exampleKana: String? = nil,
        exampleTokens: [[String]]? = nil
    ) {
        self.id = id
        self.surface = surface
        self.kana = kana
        self.partsOfSpeech = partsOfSpeech
        self.vc = vc
        self.jlpt = jlpt
        self.meanings = meanings
        self.exampleJP = exampleJP
        self.exampleEN = exampleEN
        self.exampleZH = exampleZH
        self.exampleKana = exampleKana
        self.exampleTokens = exampleTokens
    }

    /// A canonical, always-typeable romaji hint, derived from ``kana`` by the engine.
    public var romaji: String { KanaRomanizer.romaji(for: kana) }

    /// Heuristic 0…1 difficulty from length, sokuon/youon, ん, and JLPT level.
    public var difficulty: Double { Self.difficulty(kana: kana, jlpt: jlpt) }

    /// Meanings for `languageCode`, falling back to `fallback` then to any available language.
    public func meanings(for languageCode: String, fallback: String = "en") -> [String] {
        meanings[languageCode] ?? meanings[fallback] ?? meanings.values.first ?? []
    }

    /// A short joined gloss for `languageCode`, e.g. "to eat".
    public func gloss(for languageCode: String, fallback: String = "en") -> String {
        meanings(for: languageCode, fallback: fallback).joined(separator: ", ")
    }

    /// The token of the example sentence whose READING covers `index` in `exampleKana`.
    ///
    /// Sentence and dictation runs type a whole sentence, so a mistake's `kanaIndex` is a
    /// position in that sentence rather than in a word — which is why the app can count a
    /// learner's mistakes in those modes and still not name what they got wrong. The tokens
    /// already carry the answer: their readings concatenate to `exampleKana` exactly (the
    /// generator refuses to emit anything else), so a cumulative walk turns a position back
    /// into a word.
    ///
    /// Punctuation tokens contribute nothing to the reading and are skipped, which keeps the
    /// walk aligned with `exampleKana` — that string has no punctuation, because a romaji
    /// keyboard cannot produce 。
    ///
    /// Returns nil when the entry has no tokens, or when `index` is past the end — a caller
    /// holding a stale index should get nothing rather than the last word by accident.
    public func exampleToken(atReadingIndex index: Int) -> (surface: String, reading: String)? {
        exampleTokenInContext(atReadingIndex: index)?.token
    }

    /// The same walk, plus the surface of the token that FOLLOWS the one it lands on.
    ///
    /// The successor is what tells a free word from a bound stem. Sudachi's `SplitMode.C`
    /// emits 読みます as 読み + ます and 食べた as 食べ + た, so the first half is written and
    /// read exactly like the noun 読み "reading" and resolves to it with full confidence —
    /// a chip offering to save the wrong word. Nothing about the token in isolation says
    /// which it is; the next token does. (v1.24, found by the pre-submission review.)
    ///
    /// One walk, not two: the alignment rule — punctuation contributes no reading, because
    /// `exKana` has none — is subtle enough that a second copy would drift, and this project
    /// has paid for that three times.
    public func exampleTokenInContext(atReadingIndex index: Int)
        -> (token: (surface: String, reading: String), next: String?)? {
        guard index >= 0, let tokens = exampleTokens else { return nil }
        let content = tokens.filter { token in
            token.count >= 2 && !token[1].filter { !Self.punctuation.contains($0) }.isEmpty
        }
        var consumed = 0
        for (position, token) in content.enumerated() {
            let reading = token[1].filter { !Self.punctuation.contains($0) }
            let next = consumed + reading.count
            if index < next {
                let successor = position + 1 < content.count ? content[position + 1][0] : nil
                return ((surface: token[0], reading: token[1]), successor)
            }
            consumed = next
        }
        return nil
    }

    /// The characters `exKana` drops, so the token walk stays aligned with it.
    private static let punctuation: Set<Character> = ["。", "、", "！", "？", "「", "」", "・"]

    /// The example-sentence translation for `languageCode` (Chinese when "zh", else English).
    public func exampleTranslation(for languageCode: String) -> String? {
        languageCode == "zh" ? (exampleZH ?? exampleEN) : (exampleEN ?? exampleZH)
    }

    static func difficulty(kana: String, jlpt: JLPTLevel) -> Double {
        let length = kana.count
        let sokuon = kana.filter { $0 == "っ" }.count
        let small = kana.filter { "ゃゅょぁぃぅぇぉ".contains($0) }.count
        let hatsuon = kana.filter { $0 == "ん" }.count
        let raw = Double(length) * 0.6
            + Double(sokuon + small) * 1.2
            + Double(hatsuon) * 0.5
            + Double(jlpt.difficultyRank) * 2.0
        return min(1.0, raw / 14.0)
    }
}
