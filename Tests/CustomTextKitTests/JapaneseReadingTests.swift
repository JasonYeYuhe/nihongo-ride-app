import Testing
import Foundation
@testable import CustomTextKit

/// Readings for text the app has never seen, and the two invariants a furigana renderer needs.
///
/// The corpus-scale number lives elsewhere and is not repeated here:
/// `scripts/measure_tokenizer_readings.swift` measures this pipeline against 6,724 sentences
/// whose readings a human reviewed, and reports 96.9% exact / 99.1% per-kana. What this suite
/// holds is the *structure* that number depends on — reconstruction, the kana-token rule, and
/// typeability — because a pipeline that scores 96.9% and drops a character is still unusable.
@Suite("Readings for the learner's own text")
struct JapaneseReadingTests {

    @Test("every surface concatenates back to exactly the input")
    func surfacesReconstructTheInput() {
        // Furigana that drifts by one token puts the reading over the wrong character, which
        // is worse than showing none — `FuriganaText`'s own doc comment says so about the
        // corpus, and the corpus has a test behind it. This is that test for pasted text,
        // including the shapes the tokenizer is most likely to step over.
        for text in ["日本語を勉強しています。",
                     "私は  毎日 学校へ行きます。",
                     "「おはよう」と彼は言った。",
                     "ABC 123 混ざった文。",
                     "改行\nを含む\n文章",
                     "   ",
                     "😀 絵文字も。"] {
            let joined = JapaneseReading.tokens(for: text).map(\.surface).joined()
            #expect(joined == text, Comment(rawValue:
                "reconstruction failed for \(text.debugDescription): got \(joined.debugDescription)"))
        }
    }

    @Test("a kana token reads as itself — the rule worth 8.3 points")
    func kanaTokensReadAsThemselves() {
        // スープ must come back すーぷ, not すうぷ. The corpus writes すーぷ, and the
        // transcription route normalises ー away. THE CONTROL IS THE POINT: the naive path is
        // computed right here and required to differ, so "すーぷ" cannot be right by accident.
        let tokens = JapaneseReading.tokens(for: "スープ")
        #expect(tokens.map(\.reading).joined() == "すーぷ")

        let naive = ("suupu" as NSString).applyingTransform(.latinToHiragana, reverse: false)
        #expect(naive == "すうぷ", "the control itself must reproduce the failure mode")
        #expect(tokens.map(\.reading).joined() != naive,
                "if the rule and the naive path agree here, this test is not testing the rule")

        // And the small kana, which the same normalisation eats.
        #expect(JapaneseReading.tokens(for: "ちょっと").map(\.reading).joined() == "ちょっと")
    }

    @Test("katakana is read as hiragana, because that is what gets typed")
    func katakanaBecomesHiragana() {
        #expect(JapaneseReading.tokens(for: "コーヒー").map(\.reading).joined() == "こーひー")
    }

    @Test("it reads ordinary sentences the way the corpus does")
    func knownReadings() {
        // Sentences whose readings this repo has already reviewed. Not a substitute for the
        // corpus-scale measurement — six cases prove nothing about a rate — but a floor: if
        // these break, the pipeline has changed underneath.
        let cases = [
            ("東京駅で新幹線に乗った。", "とうきょうえきでしんかんせんにのった"),
            ("今日はいい天気ですね。", "きょうはいいてんきですね"),
            ("彼は本を読んでいる。", "かれはほんをよんでいる"),
        ]
        for (jp, expected) in cases {
            let got = JapaneseReading.typingTarget(JapaneseReading.tokens(for: jp))
            #expect(got == expected, Comment(rawValue: "\(jp): want \(expected), got \(got)"))
        }
    }

    @Test("the typing target drops punctuation and nothing else")
    func typingTargetStripsPunctuationOnly() {
        let tokens = JapaneseReading.tokens(for: "「そうですか。」と、彼は言った。")
        let target = JapaneseReading.typingTarget(tokens)
        #expect(!target.contains("。") && !target.contains("「") && !target.contains("、"))
        #expect(target == "そうですかとかれはいった")
    }

    @Test("text that cannot be typed on a romaji engine is reported, not silently shortened")
    func typeability() {
        // The failure this guards is recorded in gen_sentence_kana.py: Sudachi reads 10 as
        // いちれい, producing a target that LOOKS like kana and teaches the wrong thing. Here
        // Latin and digits survive transcription as themselves, so the target is visibly
        // untypeable — and must be reported as such rather than quietly stripped, because a
        // silently shortened target is one the learner can never complete.
        #expect(JapaneseReading.isTypeable("たべます"))
        #expect(!JapaneseReading.isTypeable(""))

        // THE CASE THAT MADE `canRead` EXIST, and it was found here rather than reasoned to.
        // `ABC` survives transcription untouched and `latinToHiragana` then reads it as
        // ordinary romaji, so the target is あぶくをみる: valid kana, perfectly typeable, and
        // not a reading of the sentence. A check on the target alone passes it.
        let mixed = JapaneseReading.typingTarget(JapaneseReading.tokens(for: "ABCを見る。"))
        #expect(JapaneseReading.isTypeable(mixed), Comment(rawValue:
            "the whole point is that the TARGET looks fine — got \(mixed.debugDescription)"))
        #expect(!JapaneseReading.canRead("ABCを見る。"),
                "…and the source check is what has to refuse it")
        #expect(!JapaneseReading.canRead("荷物は10キロあります。"),
                "digits too — gen_sentence_kana.py records Sudachi reading 10 as いちれい")
        #expect(JapaneseReading.canRead("日本語を勉強する。"),
                "and it must not refuse ordinary Japanese, or it refuses everything")
    }

    @Test("a reading is never empty, even for text the tokenizer has nothing to say about")
    func neverEmpty() {
        for text in ["𠮷野家へ行く。", "㍿の看板。", "😀"] {
            for token in JapaneseReading.tokens(for: text) {
                #expect(!token.reading.isEmpty, Comment(rawValue:
                    "empty reading for \(token.surface.debugDescription) — a token with no "
                    + "reading silently shortens the typing target"))
            }
        }
    }

    @Test("only kanji gets ruby")
    func rubyOnlyOnKanji() {
        #expect(JapaneseReading.Token(surface: "です", reading: "です").needsReading == false)
        #expect(JapaneseReading.Token(surface: "。", reading: "。").needsReading == false)
        #expect(JapaneseReading.Token(surface: "食べる", reading: "たべる").needsReading)
    }
}
