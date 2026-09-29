import Testing
import Foundation
@testable import CustomTextKit

/// v1.34 §B2 item 2 — a paste over the caps used to be cut without a word. The notice the add
/// sheet shows and the text `make` stores now come out of one cut, and these hold that cut's
/// numbers.
///
/// **The rule (decided after review, 2026-09-27).** What is stored is the first 200 sentences of
/// the first 20,000 characters. The notice is ONE line, in the unit of the cap that bounded what
/// is stored, and its dropped count is taken over the whole paste: sentences when the stored text
/// has 200 and the whole paste has more, else characters when the paste is over 20,000, else
/// nothing. **v1.35:** "has 200" means the stored 200th is the paste's 200th, whole — a 200th the
/// character cut shortened makes the paste a character-cap paste even when a 201st follows.
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

    static func storedCharacters(_ text: CustomText) -> Int {
        text.sentences.reduce(0) { $0 + $1.source.count }
    }

    @Test("201 sentences: the 201st is dropped, and said so")
    func sentenceCapBites() {
        // 200 identical sentences and one that is not, so WHICH one went is observable.
        let source = Self.sentences(200, length: 5) + "おわり。"
        #expect(source.count == 1_004, "200 × 5 + 4 — the fixture, checked before it is used")
        #expect(CustomText.truncation(of: source) == .sentences(kept: 200, dropped: 1))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(text.sentences.last?.source == "ああああ。", "the LAST sentence is the one that goes")
    }

    /// The fixture where the character cap ALONE decides what is stored: one sentence spans
    /// character 20,000, so the stored text ends inside it. A `make` that split the whole paste
    /// and applied only the sentence cap would store that sentence whole (10,000 characters) —
    /// every other fixture here has the sentence cap throw away whatever the character cap did.
    @Test("a sentence spanning character 20,000 is stored cut at 20,000, and counted in characters")
    func characterCapAloneChangesTheStoredText() {
        // 150 sentences of 100 (15,000), then one sentence of 9,999 う and a 。 (10,000): 25,000.
        // The first 20,000 are the 150 sentences and 5,000 う; 151 sentences, under the sentence
        // cap, so the unit is characters and 5,000 are dropped.
        let long = String(repeating: "う", count: 9_999) + "。"
        let source = Self.sentences(150, length: 100) + long
        #expect(source.count == 25_000)
        #expect(CustomText.truncation(of: source) == .characters(kept: 20_000, dropped: 5_000))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 151)
        #expect(text.sentences.dropLast().allSatisfy { $0.source.count == 100 })
        #expect(text.sentences.last?.source == String(repeating: "う", count: 5_000),
                "the spanning sentence is stored up to character 20,000 and no further")
        #expect(Self.storedCharacters(text) == 20_000)
    }

    /// The finding's case, and ordinary Japanese: 40-character sentences hit 200 sentences at
    /// 8,000 characters, long before the character cap. The v1.34 first draft said "Only the first
    /// 20,000 characters are kept" here while 8,000 were stored.
    @Test("60,000 characters of 40-character sentences: 200 kept, 1,300 dropped, in sentences")
    func bothCapsBiteTheSentenceCapBounds() {
        let source = Self.sentences(1_500, length: 40)
        #expect(source.count == 60_000)
        #expect(CustomText.truncation(of: source) == .sentences(kept: 200, dropped: 1_300))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(Self.storedCharacters(text) == 8_000, "200 × 40 — what is stored, not 20,000")
    }

    /// The dropped count is over the WHOLE paste. The first 20,000 characters hold exactly 200
    /// sentences, so a count taken inside them finds nothing past the cap; the paste has 300.
    @Test("300 sentences of 100: 100 dropped, counted over the whole paste")
    func sentencesDroppedAreCountedOverTheWholePaste() {
        let source = Self.sentences(300, length: 100)
        #expect(source.count == 30_000)
        #expect(CustomText.truncation(of: source) == .sentences(kept: 200, dropped: 100))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(Self.storedCharacters(text) == 20_000)
    }

    /// 20,001 characters whose last character is a sentence of its own: the stored text has 200
    /// sentences and the paste has 201, so the rule counts in sentences.
    @Test("200 full sentences and a stray character past 20,000: one sentence dropped")
    func aStrayTailPastBothCapsIsASentence() {
        let source = Self.sentences(200, length: 100) + "え"
        #expect(source.count == 20_001)
        #expect(CustomText.truncation(of: source) == .sentences(kept: 200, dropped: 1))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(text.sentences.allSatisfy { $0.source.count == 100 })
    }

    /// The stored text has 200 sentences but the 200th is the one the character cap cut, and the
    /// paste has no 201st: nothing was lost to the sentence cap, so the unit is characters.
    @Test("the 200th sentence cut by the character cap: counted in characters")
    func theTwoHundredthSentenceCutByCharacters() {
        // 199 sentences of 100 (19,900), then 4,999 お and a 。 (5,000): 24,900 characters, 200
        // sentences. Stored: 199 sentences and the first 100 お.
        let source = Self.sentences(199, length: 100) + String(repeating: "お", count: 4_999) + "。"
        #expect(source.count == 24_900)
        #expect(CustomText.truncation(of: source) == .characters(kept: 20_000, dropped: 4_900))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(text.sentences.last?.source == String(repeating: "お", count: 100))
        #expect(Self.storedCharacters(text) == 20_000)
    }

    /// v1.35: the same cut 200th, and the paste goes on to a 201st. 1.34 said ".sentences(200, 1)"
    /// here — one sentence dropped — while the 200th had lost 4,900 of its 5,000 characters. The
    /// sentence cap took nothing whole that the character cap had not already taken, so the unit is
    /// characters and the dropped count is every character past 20,000.
    @Test("the 200th sentence cut by the character cap, and a 201st: still counted in characters")
    func theTwoHundredthCutAndAMoreSentences() {
        // 199 sentences of 100 (19,900), 4,999 お and a 。 (5,000), then え。 (2): 24,902
        // characters, 201 sentences. Stored: 199 sentences and the first 100 お.
        let source = Self.sentences(199, length: 100) + String(repeating: "お", count: 4_999) + "。" + "え。"
        #expect(source.count == 24_902)
        #expect(CustomText.truncation(of: source) == .characters(kept: 20_000, dropped: 4_902))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(text.sentences.last?.source == String(repeating: "お", count: 100))
        #expect(Self.storedCharacters(text) == 20_000)
    }

    /// The comparison is of text, not of whether the 200th ended in a terminator: here the 200th
    /// ends with its 。 exactly at character 20,000, and the 」 the splitter carries along with a
    /// terminator is character 20,001. Stored, the 200th is "あ…。"; in the paste it is "あ…。」".
    /// It lost a character to the character cap, so this paste is counted in characters.
    @Test("a closing bracket carried past character 20,000 makes the 200th a cut sentence")
    func aCarriedCloserPastTheCap() {
        // 200 sentences of 100 (20,000), 」 (1), え。 (2): 20,003 characters, 201 sentences.
        let source = Self.sentences(200, length: 100) + "」" + "え。"
        #expect(source.count == 20_003)
        #expect(CustomTextSplitter.sentences(in: source)[199] == String(repeating: "あ", count: 99) + "。」",
                "the fixture: the splitter carries the 」 into the 200th")
        #expect(CustomText.truncation(of: source) == .characters(kept: 20_000, dropped: 3))
        let text = CustomText.make(title: "t", source: source, now: t0)
        #expect(text.sentences.count == 200)
        #expect(text.sentences.last?.source == String(repeating: "あ", count: 99) + "。")
    }

    @Test("200,000 characters of 40-character sentences: 4,800 dropped")
    func aVeryLongPaste() {
        let source = Self.sentences(5_000, length: 40)
        #expect(source.count == 200_000)
        #expect(CustomText.truncation(of: source) == .sentences(kept: 200, dropped: 4_800))
    }

    @Test("under both caps nothing is dropped, and nothing is said")
    func underBothCaps() {
        // 9 + 11 characters, two sentences.
        #expect(CustomText.truncation(of: "日本語を勉強する。今日はいい天気ですね。") == nil)
        #expect(CustomText.truncation(of: "") == nil)
    }

    @Test("exactly at both caps is not over them")
    func exactlyAtTheCaps() {
        let source = Self.sentences(200, length: 100)
        #expect(source.count == 20_000)
        #expect(CustomText.truncation(of: source) == nil)
        #expect(CustomText.make(title: "t", source: source, now: t0).sentences.count == 200)
        // One character over, inside the 200th sentence's reach: 20,001 characters as one run.
        let oneOver = String(repeating: "あ", count: 20_001)
        #expect(CustomText.truncation(of: oneOver) == .characters(kept: 20_000, dropped: 1))
    }
}
