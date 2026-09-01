import Testing
import Foundation
@testable import CustomTextKit

@Suite("The learner's own texts — splitting, editing, persisting")
struct CustomTextStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("a quoted sentence stays one sentence")
    func splittingCarriesClosingQuotes() {
        let text = "「おはよう。」と彼は言った。もう一つの文。"
        let pieces = CustomTextSplitter.sentences(in: text)
        // The control is the shape a naive splitter produces: breaking at 。 without carrying
        // the 」 leaves a whole practice screen showing one character.
        #expect(pieces == ["「おはよう。」と彼は言った。", "もう一つの文。"], Comment(rawValue:
            "got \(pieces)"))
        #expect(!pieces.contains("」"), "a lone closing quote is a fragment, not a sentence")
    }

    @Test("line breaks split, and blank lines vanish")
    func splittingOnNewlines() {
        #expect(CustomTextSplitter.sentences(in: "一行目\n\n二行目\n") == ["一行目", "二行目"])
    }

    @Test("text with no terminator at all is still one sentence")
    func splittingKeepsTheTail() {
        #expect(CustomTextSplitter.sentences(in: "終止符のない文") == ["終止符のない文"])
        #expect(CustomTextSplitter.sentences(in: "").isEmpty)
    }

    @Test("a pasted text becomes typeable sentences with readings")
    func makeFromSource() {
        let text = CustomText.make(title: "", source: "日本語を勉強しています。今日はいい天気ですね。",
                                   now: t0)
        #expect(text.sentences.count == 2)
        #expect(text.title == "日本語を勉強しています。今日はいい天気ですね。".prefix(24).description,
                "an untitled text is named by its own opening, which is what a learner recognises")
        #expect(text.typeableSentences.count == 2)
        #expect(text.sentences[1].kana == "きょうはいいてんきですね")
        #expect(text.sentences[0].furiganaTokens.allSatisfy { $0.count == 2 })
    }

    @Test("a sentence the engine cannot type is kept and withheld")
    func untypeableSentencesAreKeptButNotQueued() {
        // Both halves matter. Dropping it would silently lose part of the learner's text;
        // queueing it would put a target on screen that can never be completed.
        let text = CustomText.make(title: "t", source: "ABCと言った。日本語を話す。", now: t0)
        #expect(text.sentences.count == 2, "the untypeable sentence is still THEIR text")
        #expect(text.typeableSentences.count == 1, "…and must not reach the typing queue")
    }

    @Test("a correction sticks, and a correction that is not kana is refused")
    func editingReadings() {
        var sentence = CustomSentence(source: "私は行く",
                                      tokens: JapaneseReading.tokens(for: "私は行く"))
        let index = sentence.tokens.firstIndex { $0.surface == "私" }
        let i = try! #require(index)
        #expect(sentence.tokens[i].reading == "わたくし",
                "the tokenizer's own answer, which is the one the learner may want to change")
        let accepted = sentence.setReading("わたし", at: i)
        #expect(accepted)
        #expect(sentence.tokens[i].reading == "わたし")
        // Katakana is accepted and folded, because a learner typing コレ means これ.
        let folded = sentence.setReading("ワタシ", at: i)
        #expect(folded)
        #expect(sentence.tokens[i].reading == "わたし")
        // And the refusals — each would leave the learner unable to finish their own sentence.
        for bad in ["watashi", "", "私", "。"] {
            let refused = sentence.setReading(bad, at: i)
            #expect(!refused, Comment(rawValue: "\(bad.debugDescription) was accepted as a reading"))
        }
        let outOfRange = sentence.setReading("わたし", at: 999)
        #expect(!outOfRange)
        #expect(sentence.tokens[i].reading == "わたし", "a refused edit changes nothing")
    }

    @Test("the store round-trips through disk byte for byte")
    func persistence() throws {
        var store = CustomTextStore()
        _ = store.add(CustomText.make(title: "one", source: "日本語を勉強する。", now: t0))
        _ = store.add(CustomText.make(title: "two", source: "今日はいい天気ですね。",
                                      now: t0.addingTimeInterval(1)))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-\(UUID().uuidString).json")
        try store.save(to: url)
        let (back, outcome) = CustomTextStore.loadReporting(from: url)
        #expect(outcome == .loaded)
        #expect(back == store, Comment(rawValue: "a store that does not survive its own save "
                + "is a store that is empty on next launch"))
        #expect(back.ordered.first?.title == "two", "newest first")
        try? FileManager.default.removeItem(at: url)
    }

    @Test("a missing file is not a corrupt file")
    func missingFile() {
        let (store, outcome) = CustomTextStore.loadReporting(
            from: FileManager.default.temporaryDirectory
                .appendingPathComponent("nope-\(UUID().uuidString).json"))
        #expect(store.isEmpty)
        #expect(outcome == .missing, Comment(rawValue: "'missing' and 'undecodable' must not "
                + "print the same word — one is safe to overwrite and the other is not"))
    }

    @Test("renaming, removing, and the cap")
    func crud() {
        var store = CustomTextStore()
        let text = CustomText.make(title: "a", source: "日本語。", now: t0)
        _ = store.add(text)
        let renamed = store.rename(id: text.id, to: "  renamed  ")
        #expect(renamed)
        #expect(store.text(id: text.id)?.title == "renamed")
        let blank = store.rename(id: text.id, to: "   ")
        #expect(!blank, "an empty name is not a name")
        let missing = store.rename(id: "nope", to: "x")
        #expect(!missing)

        for i in 0..<CustomText.maxTexts + 5 {
            _ = store.add(CustomText.make(title: "t\(i)", source: "文。",
                                          now: t0.addingTimeInterval(Double(i + 10))))
        }
        #expect(store.count == CustomText.maxTexts, "the cap holds")
        #expect(store.text(id: text.id) == nil, "and it drops the OLDEST, not the newest")

        let survivor = try! #require(store.ordered.first)
        let removed = store.remove(id: survivor.id)
        #expect(removed)
        let removedTwice = store.remove(id: survivor.id)
        #expect(!removedTwice)
    }

    @Test("a text with no sentences is refused")
    func emptyTextRefused() {
        var store = CustomTextStore()
        let added = store.add(CustomText.make(title: "empty", source: "   \n  ", now: t0))
        #expect(!added)
        #expect(store.isEmpty)
    }
}

@Suite("The caret and the engine count the same characters")
struct CustomTextAlignmentTests {
    /// `PracticeView` advances its caret once per character of `displayKana` that it considers
    /// a typing target, while `GameSession` consumes `kana`. Two predicates, one string — the
    /// count-and-run shape this project has shipped two dozen times. It cannot happen here
    /// only if every character is either punctuation or kana, with nothing in between, and
    /// that is asserted rather than argued.
    @Test("a typeable sentence has no character that is neither punctuation nor kana")
    func noThirdCategory() {
        let sources = [
            "「おはよう。」と彼は言った。",
            "東京駅で、新幹線に乗った！",
            "コーヒーを一杯……ください。",
            "彼女はチームのメンバーだ。",
            "そうですか?　わかりました。",
        ]
        var checked = 0
        for source in sources {
            let text = CustomText.make(title: "t", source: source, now: Date(timeIntervalSince1970: 0))
            for sentence in text.typeableSentences {
                checked += 1
                #expect(sentence.hasNoUncountedCharacters, Comment(rawValue:
                    "\(sentence.displayKana.debugDescription) contains a character that is "
                    + "neither punctuation nor kana, so the caret and the engine would disagree"))
                let counted = sentence.displayKana.filter { !JapaneseReading.punctuation.contains($0) }
                #expect(String(counted) == sentence.kana, Comment(rawValue:
                    "display minus punctuation is \(String(counted).debugDescription) but the "
                    + "engine consumes \(sentence.kana.debugDescription)"))
            }
        }
        // A scan that inspected nothing must not report clean — the shape ResolvesCallSiteTests
        // uses, applied to a five-line loop because the failure is identical.
        #expect(checked >= 5, Comment(rawValue: "only \(checked) sentences were checked"))
    }
}
