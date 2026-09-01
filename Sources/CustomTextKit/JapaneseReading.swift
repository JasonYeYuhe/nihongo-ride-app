import Foundation

/// Readings for arbitrary Japanese text, on the device, with no dictionary shipped and no
/// network.
///
/// **This exists because `PLAN-STAGE1` §N was wrong and its correction unblocked a feature.**
/// It said *"there is no tokenizer on the device at all"*, and the flagship "bring your own
/// Japanese" was costed at 80–120 hours partly on that. `CFStringTokenizer` has been in
/// Foundation the whole time, on both platforms, and returns a Latin transcription per token
/// that `StringTransform.latinToHiragana` turns back into kana.
///
/// HOW GOOD IT IS, MEASURED — `scripts/measure_tokenizer_readings.swift`,
/// `docs/measurements/tokenizer-reading-accuracy.json`. Against **6,724 corpus sentences whose
/// `exKana` went through a three-lens human review**: **96.9% of whole sentences exactly right,
/// 99.1% of kana positions.** The residue is homograph ambiguity rather than breakage — 私 as
/// わたくし against わたし, 木綿 as もめん against きわた, 汚れる as よごれる against けがれる —
/// and the corpus is *itself* inconsistent on 私, which says exactly what kind of disagreement
/// it is.
///
/// ⚠️ **THE POPULATION THAT NUMBER DESCRIBES, AND THE ONE IT DOES NOT.** Those are short,
/// curated sentences built around JLPT vocabulary and reviewed for teaching. News, lyrics,
/// forum posts and above all **proper names** are a different population, and 96.9% says
/// nothing about them. Names are the predictable weak spot and nothing in that measurement
/// tests them. This is why every reading this produces is **editable by the learner** — the
/// standard for pasted text is different from the standard for the shipped corpus. A wrong
/// reading in the corpus is a taught error; a wrong reading in text the learner pasted is
/// visible to them and theirs to correct.
public enum JapaneseReading {

    /// The app's kana set, copied from `scripts/gen_sentence_kana.py`, which is the authority
    /// on what this project treats as kana — including ー and the small kana. **Getting this
    /// set wrong is not a rounding error:** the first version of the measurement above filtered
    /// to U+3041–U+3096, silently deleted every ー, and reported 88.6% instead of 96.9%.
    static let kana = Set("ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとど"
                        + "なにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんー")

    /// Sentence punctuation. The typing target carries none — `Passage.kana` has said "pure
    /// kana, no punctuation" since v1.2, because romaji cannot produce 。
    public static let punctuation = Set("、。！？「」『』・…‥　 ，,.!?…\n\t｡｢｣､")

    public static func toHiragana(_ s: String) -> String {
        String(s.map { c in
            let v = c.unicodeScalars.first!.value
            return (v >= 0x30A1 && v <= 0x30F6) ? Character(UnicodeScalar(v - 0x60)!) : c
        })
    }

    static func isKanaOnly(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { kana.contains($0) || punctuation.contains($0) }
    }

    /// One token of Japanese text and the reading this produced for it.
    public struct Token: Codable, Hashable, Sendable {
        /// The text as written, exactly as it appeared. Concatenating every `surface` in order
        /// reconstructs the input — the same invariant `exTokens` carries, and for the same
        /// reason: furigana that drifts by one token puts the reading over the wrong character.
        public let surface: String
        /// The reading in hiragana. Editable — see the type's own note on why.
        public var reading: String

        public init(surface: String, reading: String) {
            self.surface = surface
            self.reading = reading
        }

        /// Kana and punctuation get no ruby, and read as themselves.
        public var needsReading: Bool {
            surface != reading && surface.contains { ch in
                (0x4E00...0x9FFF).contains(ch.unicodeScalars.first!.value)   // CJK ideographs
            }
        }
    }

    /// Tokenise Japanese text and give each token a hiragana reading.
    ///
    /// **A token already written in kana reads as ITSELF, and that rule is worth 8.3 points.**
    /// Taking the transcription for such a token normalises ー and the small kana away — スープ
    /// comes back as すうぷ where this corpus writes すーぷ. `gen_sentence_kana.py` found and
    /// documented exactly this about Sudachi; it is true of `CFStringTokenizer` for the same
    /// reason, and applying the repo's existing rule took the measured accuracy from 88.6% to
    /// 96.9%.
    public static func tokens(for text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let cf = text as CFString
        let tokenizer = CFStringTokenizerCreate(nil, cf, CFRangeMake(0, CFStringGetLength(cf)),
                                                kCFStringTokenizerUnitWordBoundary,
                                                Locale(identifier: "ja") as CFLocale)
        var out: [Token] = []
        let ns = text as NSString
        var covered = 0
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // The tokenizer skips whitespace and some punctuation, which would break the
            // "surfaces reconstruct the input" invariant. Anything it stepped over is emitted
            // as its own token, reading itself.
            if r.location > covered {
                let gap = ns.substring(with: NSRange(location: covered, length: r.location - covered))
                out.append(Token(surface: gap, reading: gap))
            }
            let surface = ns.substring(with: NSRange(location: r.location, length: r.length))
            covered = r.location + r.length
            let hiragana = toHiragana(surface)
            if isKanaOnly(hiragana) {
                out.append(Token(surface: surface, reading: hiragana))
                continue
            }
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String ?? ""
            let reading = (latin as NSString).applyingTransform(.latinToHiragana, reverse: false)
            // An empty reading is not a reading. Falling back to the surface keeps the text
            // typeable-or-visibly-wrong rather than silently short, which is the failure this
            // repo calls "a wrong number that looks like a small one".
            out.append(Token(surface: surface,
                             reading: (reading?.isEmpty == false) ? reading! : hiragana))
        }
        if covered < ns.length {
            let tail = ns.substring(from: covered)
            out.append(Token(surface: tail, reading: tail))
        }
        return out
    }

    /// The typing target for a token list: every reading, punctuation removed.
    public static func typingTarget(_ tokens: [Token]) -> String {
        String(tokens.map(\.reading).joined().filter { !punctuation.contains($0) })
    }

    /// Whether a typing target is kana the engine can accept. **Necessary and NOT sufficient
    /// — see `canRead(_:)`, which is the check that matters.**
    public static func isTypeable(_ target: String) -> Bool {
        !target.isEmpty && target.allSatisfy { kana.contains($0) }
    }

    /// Whether this SOURCE text can be given an honest reading at all.
    ///
    /// **Checking the target is not enough, and the reason was found by a test rather than by
    /// reasoning.** `ABCを見る。` comes out as **あぶくをみる** — the transcription leaves `ABC`
    /// alone and `latinToHiragana` then reads it as ordinary romaji. The result is valid kana,
    /// is perfectly typeable, and is not a reading of anything. A check on the target passes it.
    ///
    /// `gen_sentence_kana.py` refuses exactly this input for exactly this reason — *"Latin
    /// letters and digits read aloud as kana — and both come out untypeable while remaining
    /// kana-only, so they sail straight past the round-trip check"* — and records that Sudachi
    /// turns 10 into いちれい. The same rule is applied here, to the same class of input,
    /// because the pipeline changed and the failure did not.
    public static func canRead(_ source: String) -> Bool {
        !source.isEmpty && !source.contains { $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }
    }
}
