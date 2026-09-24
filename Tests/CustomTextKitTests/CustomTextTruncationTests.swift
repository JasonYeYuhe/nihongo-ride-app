import Testing
import Foundation
@testable import CustomTextKit

/// v1.34 §B2 item 2 — a paste over the caps used to be cut without a word. The notice the add
/// sheet shows and the text `make` stores now come out of one cut, and these hold that cut's
/// numbers.
///
/// Every expected value is counted by hand from the way the fixture was built, never read back
/// from `truncation(of:)`. Where `make` is asked too, its answer is compared with the same hand
/// count and not with the notice: two functions agreeing with each other is not evidence that
/// either is right.
@Suite("v1.34 B2: truncation is counted, and counted the way make cuts")
struct CustomTextTruncationTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// `count` sentences of `length` characters each: `length - 1` あ and a 。.
    static func sentences(_ count: Int, length: Int) -> String {
        String(repeating: String(repeating: "あ", count: length - 1) + "。", count: count)
    }

    @Test("201 sentences: the 201st is dropped, and said so")
    func sentenceCapBites() {
        // 200 identical sentences and one that is not, so WHICH one went is observable.
        let source = Self.sentences(200, length: 5) + "おわり。"
        #expect(source.count == 1_004, "200 × 5 + 4 — the fixture, checked before it is used")
        let truncation = CustomText.truncation(of: source)
        #expect(truncation == CustomText.Truncation(keptCharacters: 1_004, droppedCharacters: 0,
                                                    keptSentences: 200, droppedSentences: 1))
        #expect(truncation.isTruncated)
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(text.sentences.last?.source == "ああああ。", "the LAST sentence is the one that goes")
    }

    @Test("20,001 characters: the last one is dropped, and said so")
    func characterCapBites() {
        // 200 sentences of 100 characters fill the cap exactly; the え after them is character
        // 20,001 and never reaches the splitter, so it is counted as a character and not as a
        // sentence.
        let source = Self.sentences(200, length: 100) + "え"
        #expect(source.count == 20_001)
        let truncation = CustomText.truncation(of: source)
        #expect(truncation == CustomText.Truncation(keptCharacters: 20_000, droppedCharacters: 1,
                                                    keptSentences: 200, droppedSentences: 0))
        #expect(truncation.isTruncated)
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(text.sentences.allSatisfy { $0.source.count == 100 })
    }

    @Test("both caps: characters go first, then the sentences that survived them are capped")
    func bothCapsBite() {
        // 201 ten-character sentences (2,010) then 17,991 い — 20,001 in all. The character
        // cap keeps 20,000: the 201 sentences plus a 17,990-character tail, 202 sentences, of
        // which 200 stay. So one character dropped and two sentences dropped — not three, which
        // is what counting the tail twice would say.
        let source = Self.sentences(201, length: 10) + String(repeating: "い", count: 17_991)
        #expect(source.count == 20_001)
        let truncation = CustomText.truncation(of: source)
        #expect(truncation == CustomText.Truncation(keptCharacters: 20_000, droppedCharacters: 1,
                                                    keptSentences: 200, droppedSentences: 2))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
    }

    @Test("under both caps nothing is dropped, and nothing is said")
    func underBothCaps() {
        // 9 + 11 characters, two sentences.
        let source = "日本語を勉強する。今日はいい天気ですね。"
        let truncation = CustomText.truncation(of: source)
        #expect(truncation == CustomText.Truncation(keptCharacters: 20, droppedCharacters: 0,
                                                    keptSentences: 2, droppedSentences: 0))
        #expect(!truncation.isTruncated)
        #expect(!CustomText.truncation(of: "").isTruncated)
    }

    @Test("exactly at both caps is not over them")
    func exactlyAtTheCaps() {
        let source = Self.sentences(200, length: 100)
        #expect(source.count == 20_000)
        let truncation = CustomText.truncation(of: source)
        #expect(truncation == CustomText.Truncation(keptCharacters: 20_000, droppedCharacters: 0,
                                                    keptSentences: 200, droppedSentences: 0))
        #expect(!truncation.isTruncated)
        #expect(CustomText.make(title: "t", source: source, now: t0).sentences.count == 200)
    }
}
