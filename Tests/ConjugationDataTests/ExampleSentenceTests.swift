import Testing
import Foundation
@testable import VocabKit

/// Guards the 2,121 shipped example sentences.
///
/// The generator's only check that a sentence is ABOUT the right word was a substring test
/// that treated "drop the last character" as a stem for every entry — so the noun 学校 was
/// reduced to 学, and 「数学を勉強します。」 would validate as an example of it. That gate lived
/// in a Python script nothing ran again after a batch landed, which is the wrong place for an
/// invariant about shipped data: this suite runs on every `swift test`.
///
/// It cannot establish that a sentence is natural, correctly translated or level-appropriate —
/// no mechanical check can, and the plan says so. It establishes the things that ARE decidable.
@Suite("Example sentences — the shipped ones")
struct ExampleSentenceTests {

    private var withExamples: [VocabEntry] {
        VocabStore.shared.entries.filter { !($0.exampleJP ?? "").isEmpty }
    }

    /// Verb classes whose written form changes inside a sentence, so the dictionary form is
    /// not present literally. Mirrors `scripts/gen_examples.py`.
    private let inflecting: Set<String> = ["godan_u", "godan_k", "godan_g", "godan_s", "godan_t",
                                           "godan_n", "godan_b", "godan_m", "godan_r",
                                           "ichidan", "zuru"]

    /// Forms besides the headword that a sentence may legitimately contain. Single-character
    /// stems are refused: 行く's stem 行 appears in 銀行 and 旅行, so matching on it would call
    /// almost any sentence an example of 行く.
    private func stems(_ e: VocabEntry) -> [String] {
        var out: [String] = []
        if e.vc == "suru" || e.vc == "kuru" || e.surface.hasSuffix("する") {
            for (form, suffix) in [(e.surface, "する"), (e.kana, "する"),
                                   (e.surface, "くる"), (e.kana, "くる")] where form.hasSuffix(suffix) {
                out.append(String(form.dropLast(suffix.count)))
            }
            // 来る is `kuru` but written in kanji, so it ends in る, not くる — the suffix strip
            // above misses it and 「友達が来ます。」 looked like it did not contain its own word.
            if e.vc == "kuru", !e.surface.hasSuffix("くる") { out.append(String(e.surface.dropLast())) }
        }
        // Also any entry that is a VERB by part of speech, even without a usable `vc`. Two
        // shipped entries need this and neither has one: する is tagged suru, so stripping する
        // leaves nothing, and できる carries no vc at all — yet 「サッカーをします。」 and
        // 「話すことができます。」 plainly use them. The Python half of this gate already accepts
        // both, because it asks Sudachi whether a token's dictionary form IS the target rather
        // than matching substrings; without this the two halves contradict each other, and the
        // stricter one is the one that is wrong.
        if inflecting.contains(e.vc ?? "")
            || e.partsOfSpeech.contains(where: { $0.lowercased().hasPrefix("v") })
            || e.partsOfSpeech.contains(where: { $0.lowercased().contains("adj-i") }) {
            out.append(String(e.surface.dropLast()))
            out.append(String(e.kana.dropLast()))
        }
        // A one-character stem is allowed here, unlike in the generator, and the difference is
        // deliberate. The generator must reject anything doubtful because it decides what to
        // SHIP; this test must not fail on data that is fine, and most kanji verbs have a
        // single-character stem (襲う → 襲った, 否む → 否めない). The over-permissive case the
        // original bug produced — noun 学校 reduced to 学 — cannot recur, because nouns are
        // offered no stem at all now.
        return out.filter { !$0.isEmpty }
    }

    /// Entries whose example writes the word a DIFFERENT way — a variant kanji, or kanji
    /// where the headword is kana. The sentences are correct Japanese and do teach the word,
    /// so they stay; they simply cannot be matched by substring.
    ///
    /// Two entries that were on this list are not exceptions and were deleted instead:
    /// 納める's example was 「大きな成功を収める。」 (収める is a different verb) and しがみつく's
    /// was 「母親に縋り付く。」 (縋り付く is a different word, すがりつく). Removing a wrong
    /// example needs no Japanese authored, so there was no reason to keep either.
    private let knownVariantSpelling: Set<String> = [
        "n1-g008",   // 跡継ぎ → 後継ぎ
        "n1-g046",   // 驕る → 奢る
        "n1-g219",   // ゆがむ → 歪む (kana headword, kanji sentence)
        "n4-g076",   // 堅い → 固い
    ]

    @Test("every example sentence actually uses its own word")
    func usesTheWord() {
        var offenders: [String] = []
        for e in withExamples {
            guard let jp = e.exampleJP else { continue }
            let candidates = [e.surface, e.kana] + stems(e)
            if !candidates.contains(where: { !$0.isEmpty && jp.contains($0) }),
               !knownVariantSpelling.contains(e.id) {
                offenders.append("\(e.id) \(e.surface): \(jp)")
            }
        }
        #expect(offenders.isEmpty,
                Comment(rawValue: "\(offenders.count) example(s) don't contain their word:\n"
                                  + offenders.prefix(12).joined(separator: "\n")))
    }

    /// Sentences already shared by two entries when this test was written.
    ///
    /// A ratchet, not an exemption. Resolving one means giving the other entry a NEW sentence,
    /// which is authoring Japanese — the thing this project requires review for — so it
    /// belongs to a reviewed content batch, not to a quick edit. Recording the debt keeps it
    /// visible and stops it growing; each line removed here is one pair genuinely fixed.
    private let knownSharedExamples: Set<String> = [
        "プールで泳ぎます。", "チャンスを掴む。", "永遠の愛を誓う。", "私は学生です。",
        "水を飲みます。", "ラッシュアワーを避ける。", "データを保存する。",
        "トイレはどこですか。", "本を読みます。",
    ]

    @Test("no NEW entry pair starts sharing an example sentence")
    func noNewDuplicates() {
        // A learner who meets the same sentence under two different words learns neither of
        // them from it. The generator already refuses duplicates within a batch; these nine
        // escaped before that, and nothing was watching afterwards.
        var byJP: [String: [String]] = [:]
        for e in withExamples {
            guard let jp = e.exampleJP else { continue }
            byJP[jp, default: []].append(e.id)
        }
        let dupes = byJP.filter { $0.value.count > 1 }
        let unexpected = dupes.filter { !knownSharedExamples.contains($0.key) }
        #expect(unexpected.isEmpty,
                Comment(rawValue: "\(unexpected.count) NEW shared sentence(s):\n"
                    + unexpected.prefix(12).map { "\($0.key) → \($0.value.joined(separator: ", "))" }
                           .joined(separator: "\n")))
        // …and the debt must not silently outlive its entries either: a name in the list that
        // is no longer shared should be deleted from it, so the ratchet keeps tightening.
        let stale = knownSharedExamples.subtracting(dupes.keys)
        #expect(stale.isEmpty,
                Comment(rawValue: "no longer shared — remove from knownSharedExamples: "
                                  + stale.sorted().joined(separator: ", ")))
    }

    @Test("examples are one sentence, punctuated, and free of latin text")
    func shape() {
        var bad: [String] = []
        for e in withExamples {
            guard let jp = e.exampleJP else { continue }
            // 5, not the generator's 6: 「席が空く。」 and 「腕が痛い。」 are five characters and
            // are perfectly good sentences. The generator's lower bound is about what to
            // ACCEPT from a model; it is not a statement about what good data looks like, and
            // eighteen shipped entries say so.
            if !(5...42).contains(jp.count) { bad.append("\(e.id): length \(jp.count)") }
            // 。 ! ? ！ ？ — the fullwidth question mark U+FF1F was missing here while the
            // Python gate's JP_END has always had it, so 「…どうなったの？」 passed generation and
            // failed this suite. Two spellings of the same rule drift; this one was wrong.
            if !"。!?！？".contains(jp.last ?? " ") { bad.append("\(e.id): no final punctuation") }
            if jp.dropLast().contains(where: { "。!?".contains($0) }) { bad.append("\(e.id): multiple sentences") }
            if jp.contains(where: { $0.isASCII && $0.isLetter }) { bad.append("\(e.id): latin letters") }
        }
        #expect(bad.isEmpty, Comment(rawValue: "\(bad.count) malformed:\n"
                                                + bad.prefix(12).joined(separator: "\n")))
    }

    @Test("every example has both translations")
    func translated() {
        var missing: [String] = []
        for e in withExamples {
            if (e.exampleTranslation(for: "en") ?? "").count < 4 { missing.append("\(e.id): en") }
            if (e.exampleTranslation(for: "zh") ?? "").count < 2 { missing.append("\(e.id): zh") }
        }
        #expect(missing.isEmpty, Comment(rawValue: "\(missing.count) missing:\n"
                                                    + missing.prefix(12).joined(separator: "\n")))
    }
}
