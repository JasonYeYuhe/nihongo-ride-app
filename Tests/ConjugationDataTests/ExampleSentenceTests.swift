import Testing
import Foundation
import RomajiKana
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
        // The data uses BOTH "adj-i" and "i-adjective" for the same class, and this check
        // only knew the first spelling — so 「今日の海は波が荒くて危険だ。」 was reported as not
        // containing 荒い, because no stem was ever offered for it. Match on "adj" so either
        // tag works.
        if inflecting.contains(e.vc ?? "")
            || e.partsOfSpeech.contains(where: { $0.lowercased().hasPrefix("v") })
            || e.partsOfSpeech.contains(where: { $0.lowercased().contains("adj") }) {
            out.append(String(e.surface.dropLast()))
            out.append(String(e.kana.dropLast()))
        }
        // A -ずる verb conjugates on a じ stem: 存ずる → 存じております, 命ずる → 命じた,
        // 論ずる → 論じている. Dropping one character leaves 存ず, which appears in none of
        // them. Drop the whole ずる instead. The Python matcher already handles this class
        // through Sudachi's normalized_form; this half did not, and the stricter half was
        // the wrong one — the same drift that put a fullwidth ？ out of reach in v1.18.
        if e.vc == "zuru" {
            if e.surface.hasSuffix("ずる") { out.append(String(e.surface.dropLast(2))) }
            if e.kana.hasSuffix("ずる") { out.append(String(e.kana.dropLast(2))) }
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

    /// Whether the sentence contains the headword in SOME writable form. One function, so the
    /// ratchet and its staleness companion cannot disagree about what "uses the word" means —
    /// which is the only way a companion is worth having.
    private func sentenceUsesTheWord(_ e: VocabEntry) -> Bool {
        guard let jp = e.exampleJP else { return false }
        let candidates = [e.surface, e.kana] + stems(e)
        return candidates.contains { !$0.isEmpty && jp.contains($0) }
    }

    @Test("every example sentence actually uses its own word")
    func usesTheWord() {
        var offenders: [String] = []
        for e in withExamples {
            guard e.exampleJP != nil else { continue }
            if !sentenceUsesTheWord(e), !knownVariantSpelling.contains(e.id) {
                offenders.append("\(e.id) \(e.surface): \(e.exampleJP ?? "")")
            }
        }
        #expect(offenders.isEmpty,
                Comment(rawValue: "\(offenders.count) example(s) don't contain their word:\n"
                                  + offenders.prefix(12).joined(separator: "\n")))
    }

    /// The reading half of `usesTheWord`, which only ever compared the WRITTEN form.
    ///
    /// `usesTheWord` asks whether the sentence contains the headword — `jp.contains(surface)`,
    /// a substring test that never looks at a reading. So a sentence can contain its headword
    /// and transcribe it as a different word entirely, and pass. Twenty-one shipped sentences
    /// do, and `exKana` is not decoration: it is the LITERAL TYPING TARGET the learner is graded
    /// against, and the furigana printed over the sentence.
    ///
    /// The card 何/なに ships 「何を食べますか。」 with `exKana` なんをたべますか — and なんを is
    /// not a possible reading of anything. 額/ひたい, glossed "forehead", types がく. 御/お
    /// types ごちゃ for 御茶. In eighteen of the twenty-one the reading the sentence uses is
    /// literally another entry's `kana`, so the corpus contradicts itself in a way it can be
    /// asked about.
    ///
    /// Derived, never a list of forms: for every entry whose `exTokens` contain a token written
    /// exactly like the headword, the entry's own `kana` must be among those tokens' readings.
    /// Katakana is folded with `KanaScript` — the same folding the typing matcher and the
    /// stumbled-word index use, not a fourth copy of the rule.
    /// How the sentence reads this entry's headword, wherever the headword appears — as one
    /// token or as a run of adjacent ones.
    ///
    /// **The single-token version of this was a blind spot that hid 26 further offenders, ten
    /// of them N5.** Sudachi splits 四つ into 四 + つ and 二十日 into 二十 + 日, so an exact
    /// `token == surface` match skipped 240 entries entirely and the gate reported them clean.
    /// Behind it: 四つ typed よんつ, 八つ typed ようつ, 二日 typed ふたか, 一昨日 typed いっさくひ
    /// — counters and dates, the most beginner-facing content the app has, graded against
    /// readings that are not words. Found by the v1.25 pre-submission review, in the gate this
    /// release exists to add.
    ///
    /// The lesson is the one this project keeps paying for: the gate was validated by what it
    /// CAUGHT (21) and never asked what it structurally could not see.
    static func headwordReadings(of entry: VocabEntry) -> [String]? {
        guard let tokens = entry.exampleTokens else { return nil }
        let content = tokens.filter { $0.count >= 2 }
        var found: [String] = []
        for start in content.indices {
            var surface = ""
            for end in start..<content.count {
                surface += content[end][0]
                if surface == entry.surface {
                    found.append(KanaScript.katakanaToHiragana(
                        content[start...end].map { $0[1] }.joined()))
                    break
                }
                if surface.count > entry.surface.count { break }
            }
        }
        return found.isEmpty ? nil : found
    }

    /// The headword's reading where the tokenizer does not split ON the headword's boundary.
    ///
    /// `headwordReadings` needs a run of tokens whose surfaces concatenate to EXACTLY the
    /// headword. Sudachi does not always oblige: 支払い方式 comes back as 支払い方 + 式, so no
    /// span equals 方式 and the entry was skipped — 106 entries, and two of them shipped a
    /// reading that is not a word (支払い方式 keyed しはらいかたしき, 建築学科 keyed けんちくがくか).
    ///
    /// This is the SAME lesson twice: the single-token gate was validated by its catches and
    /// missed 240 entries; the span gate was validated by its 26 catches and missed 106 more.
    /// The question is always what the scan cannot see.
    ///
    /// Here the headword's own reading cannot be isolated — the covering tokens carry more than
    /// the headword — so the test is weaker on purpose: the card's reading must appear SOMEWHERE
    /// in the covering reading. That is satisfied by legitimate rendaku and jukujikun only when
    /// the compound leaves the reading intact, so the three shipped cases where it does not
    /// (座り心地 ごこち, 働き盛り ざかり, 今日 きょう) are named rather than papered over.
    static func coveringReading(of entry: VocabEntry) -> (surface: String, reading: String)? {
        guard headwordReadings(of: entry) == nil,
              let jp = entry.exampleJP, jp.contains(entry.surface),
              let tokens = entry.exampleTokens else { return nil }
        let content = tokens.filter { $0.count >= 2 }
        for start in content.indices {
            var surface = ""
            for end in start..<content.count {
                surface += content[end][0]
                if surface.contains(entry.surface) {
                    return (surface, KanaScript.katakanaToHiragana(
                        content[start...end].map { $0[1] }.joined()))
                }
            }
        }
        return nil
    }

    /// Rendaku and jukujikun that legitimately change the headword's reading inside a compound.
    /// Named, not thresholded, for the same reason as every other ratchet here.
    private let knownCompoundReadings: Set<String> = ["n2-g298", "n3-b510", "n3-b901"]

    @Test("a headword the tokenizer splits across is still read the way its card teaches")
    func boundaryCrossingHeadwordsAreRead() {
        var inspected = 0
        var offenders: [String] = []
        for entry in withExamples {
            guard let cover = Self.coveringReading(of: entry) else { continue }
            inspected += 1
            if !cover.reading.contains(KanaScript.katakanaToHiragana(entry.kana)),
               !knownCompoundReadings.contains(entry.id) {
                offenders.append("\(entry.id) \(entry.surface): card says \(entry.kana), "
                                 + "\(cover.surface) reads \(cover.reading)")
            }
        }
        #expect(inspected > 60, "only \(inspected) boundary-crossing headwords — the walk is wrong")
        #expect(offenders.isEmpty, Comment(rawValue:
            "\(offenders.count) headword(s) the tokenizer split across are misread:\n"
            + offenders.prefix(8).joined(separator: "\n")))
    }

    /// **Two of this file's four ratchets could never go stale, and that is one rule applied to
    /// half the places it applies to — this file's oldest shape.**
    ///
    /// `knownHeadwordReadingMismatch` has `ratchetIsNotStale`; `knownSharedExamples` checks
    /// staleness inline. `knownVariantSpelling` (4 ids) and `knownCompoundReadings` (3 ids) had
    /// no companion at all, so **7 entries were exempted forever** — and if one were fixed the
    /// exemption would stay and hide the next offender behind it. That is verbatim the rationale
    /// this file already gives at `ratchetIsNotStale` for why the other two have companions.
    @Test("the variant-spelling exemption names only entries that still need it")
    func variantSpellingRatchetIsNotStale() {
        let byID = Dictionary(withExamples.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var stale: [String] = []
        for id in knownVariantSpelling.sorted() {
            guard let entry = byID[id] else {
                stale.append("\(id) (no longer in the corpus)")
                continue
            }
            if sentenceUsesTheWord(entry) {
                stale.append("\(id) \(entry.surface) (its sentence now contains the word)")
            }
        }
        #expect(stale.isEmpty, Comment(rawValue:
            "remove from knownVariantSpelling: " + stale.joined(separator: ", ")))
    }

    @Test("the compound-reading exemption names only entries that still need it")
    func compoundReadingRatchetIsNotStale() {
        let byID = Dictionary(withExamples.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var stale: [String] = []
        for id in knownCompoundReadings.sorted() {
            guard let entry = byID[id] else {
                stale.append("\(id) (no longer in the corpus)")
                continue
            }
            guard let cover = Self.coveringReading(of: entry) else {
                // No longer boundary-crossing — the gate that exempts it does not even reach it.
                stale.append("\(id) \(entry.surface) (no longer a boundary-crossing headword)")
                continue
            }
            if cover.reading.contains(KanaScript.katakanaToHiragana(entry.kana)) {
                stale.append("\(id) \(entry.surface) (\(cover.surface) now reads \(cover.reading))")
            }
        }
        #expect(stale.isEmpty, Comment(rawValue:
            "remove from knownCompoundReadings: " + stale.joined(separator: ", ")))
    }

    /// Nothing counted the gates, so one could leave the suite inside the release that added
    /// it and the release would notice nothing — which is exactly what happened to
    /// `readingNotesMatchTheirGenerator` in v1.25 (added in `e71e7be`, removed in `fafae5a`,
    /// whose message is about a different subject entirely and never mentions it).
    ///
    /// **Two defects in the first version of this test, both found by the pre-submission
    /// review, and both are the shape it is written against:**
    ///
    /// * It required three occurrences of each ratchet's name — "the declaration, the gate,
    ///   and a companion" — but the list of names below is ITSELF inside the file it counts,
    ///   so every name got a free occurrence and the real bar was declaration + one use. A
    ///   ratchet with no companion at all passed it. The list is now excised from the text
    ///   before counting, so the three occurrences are three REAL ones.
    /// * Its doc told the `readingNotesMatchTheirGenerator` story while counting named-id
    ///   exemption lists, which that test does not have. Deleting it again would still have
    ///   been invisible. So the gates are now counted too.
    @Test("every ratchet has a staleness companion, and no gate has quietly left")
    func everyRatchetHasACompanion() {
        let source = try? String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let text = source ?? ""
        #expect(!text.isEmpty, "could not read this suite's own source")

        let ratchets = ["knownVariantSpelling", "knownCompoundReadings",
                        "knownHeadwordReadingMismatch", "knownSharedExamples",
                        "knownStemSharedWithOtherWord"]

        // The list above is inside the counted file. Excise it, or every name is credited with
        // an occurrence it did not earn — which is how the first version passed a ratchet that
        // had no companion.
        let marker = "let ratchets = ["
        var counted = text
        if let start = counted.range(of: marker),
           let end = counted.range(of: "]", range: start.upperBound..<counted.endIndex) {
            counted.removeSubrange(start.lowerBound..<end.upperBound)
        } else {
            Issue.record("could not excise the ratchet list — the count would be inflated")
        }

        for name in ratchets {
            let uses = counted.components(separatedBy: name).count - 1
            #expect(uses >= 3, Comment(rawValue:
                "\(name) appears \(uses) time(s) outside this test's own list — a ratchet needs "
                + "a declaration, a gate that consults it, and a companion that can retire an "
                + "entry from it. With fewer, its entries are exempted forever and the next "
                + "offender hides behind them"))
        }

        // Every ratchet DECLARED here must be named above, so a new one cannot be exempt by
        // omission. Matched on the declaration prefix rather than a substring: the first
        // version matched any line containing "let known" and "Set<String>", which flagged its
        // own comment and its own loop condition — a scan measuring its text, not the file.
        let declarations = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("private let known") && $0.contains("Set<String>") }
        #expect(declarations.count == ratchets.count, Comment(rawValue:
            "\(declarations.count) ratchets declared but \(ratchets.count) known to this test"))
        for line in declarations {
            #expect(ratchets.contains { line.contains($0) }, Comment(rawValue:
                "a ratchet this test does not know about: \(line)"))
        }

        // …and the gates themselves, which is the half the story actually described. A gate
        // deleted by accident — the thing that happened — leaves no ratchet behind to miss.
        //
        // Counted as DECLARATIONS, not as occurrences of the substring. The first version
        // counted `text.components(separatedBy: "@Test(")`, which matched its own string
        // literal on this very line and made 25 tests read as 26 — so deleting a gate left
        // exactly 25 and the floor passed. That is the third time in this file a scan has
        // measured its own text instead of the file's structure, and the second time in one
        // release. A floor taken from the runner's count and compared against a substring
        // count is two numbers by two predicates, which is what this release is about.
        let gates = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("@Test(") }
            .count
        #expect(gates >= 25, Comment(rawValue:
            "\(gates) gates in this file, was 25 — a gate has left the suite. If that was "
            + "deliberate, say so in the commit message and lower this floor in the same "
            + "commit; `readingNotesMatchTheirGenerator` was removed by a commit about "
            + "something else and nobody noticed for a release"))
    }

    @Test("a sentence reads its headword the way its own card teaches it")
    func readsItsHeadwordAsTaught() {
        var offenders: [String] = []
        var inspected = 0
        for entry in withExamples {
            guard let readings = Self.headwordReadings(of: entry) else { continue }
            inspected += 1
            if !readings.contains(KanaScript.katakanaToHiragana(entry.kana)),
               !knownHeadwordReadingMismatch.contains(entry.id) {
                offenders.append("\(entry.id) \(entry.surface): card says \(entry.kana), "
                                 + "sentence says \(readings.joined(separator: "/"))")
            }
        }
        // A scan that inspected nothing would report a clean corpus. The span walk inspects
        // 5,862 of 6,738 sentences (87.0%), measured on the shipped corpus AFTER the walk was
        // made span-aware — the number this floor is set against, not the 83.6% the bare-token
        // predicate saw, which is what this comment quoted until the second review pass.
        #expect(inspected > 5_500, "only \(inspected) sentences contain their headword")
        #expect(offenders.isEmpty,
                Comment(rawValue: "\(offenders.count) sentence(s) read their headword a way the "
                                  + "card does not teach:\n" + offenders.prefix(12).joined(separator: "\n")))
    }

    /// The twenty-one that shipped, each one named.
    ///
    /// A ratchet on the `knownSharedExamples` model, and named rather than counted for the same
    /// reason: a threshold lets a new one in as an old one is fixed, and this defect grades a
    /// learner's typing against a reading nobody teaches. Removing a line here means the entry
    /// was genuinely adjudicated — either its `exKana` was corrected, or its sentence was
    /// withdrawn because the sentence is right and the card's minority reading cannot occur in
    /// it. Both outcomes are legitimate; leaving it is not.
    /// The eight that remain, and why each is a deliberate keep rather than a backlog item.
    ///
    /// Fourteen of the original twenty-one were corrected in v1.25 §A. These seven were
    /// classified REGISTER — the two readings mean the same thing in that sentence and differ
    /// only in formality — independently by two models, and v1.21 §C has already decided that a
    /// minority reading is not an error.
    ///
    /// n3-g131 得る was on this list and came OFF it: both models answered "える and うる both
    /// mean to obtain", which is true and is the wrong question. うる is the attributive of the
    /// classical nidan 得, which the card's own `vc: ichidan` cannot produce — a different
    /// conjugation class, not a register. Found by the pre-submission review. Correcting them would overturn a recorded decision, and
    /// would mean authoring Japanese to satisfy a card:
    ///
    ///   n1-g315  獣    けだもの / けもの      both "beast"
    ///   n1-b005  怒る  いかる / おこる        both "to be angry"; いかる is the literary one
    ///   n1-b016  大事  おおごと / だいじ      both "a serious matter" in 大事に至る
    ///   n1-b071  消耗  しょうこう / しょうもう  identical meaning; しょうこう is the original reading
    ///   n1-b072  所々  しょしょ / ところどころ  both "here and there"
    ///   n5-ashita 明日 あした / あす          both "tomorrow"
    ///   n5-g012  私    わたし / わたくし      both "I"; わたくし is formal
    ///
    /// They stay named so the list is a decision with a reason, not a silence. If the register
    /// question is ever reopened, this is where it starts.
    private let knownHeadwordReadingMismatch: Set<String> = [
        "n1-g315", "n1-b005", "n1-b016", "n1-b071", "n1-b072", "n5-ashita", "n5-g012",
    ]

    /// A ratchet that is not shrinking is a list nobody is working through, and one that names
    /// an entry already fixed hides the next offender behind a stale exemption.
    @Test("the headword-reading ratchet names only entries that still offend")
    func ratchetIsNotStale() {
        var stillOffending: Set<String> = []
        for entry in withExamples {
            guard let readings = Self.headwordReadings(of: entry) else { continue }
            if !readings.contains(KanaScript.katakanaToHiragana(entry.kana)) {
                stillOffending.insert(entry.id)
            }
        }
        let stale = knownHeadwordReadingMismatch.subtracting(stillOffending)
        #expect(stale.isEmpty,
                Comment(rawValue: "fixed — remove from knownHeadwordReadingMismatch: "
                                  + stale.sorted().joined(separator: ", ")))
    }

    // MARK: v1.26 §A — the reading of a headword that is never spelled out

    /// Kanji, for deciding whether a stem is one the sentence must spell in kanji too.
    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value)      // CJK unified
                || (0x3400...0x4DBF).contains($0.value)  // extension A
                || $0.value == 0x3005                    // 々
        }
    }

    /// Verb classes whose stem is NOT the headword minus one character.
    ///
    /// 来る conjugates on こ/き/く and する on し/さ/せ — the written stem stays 来 and 為 while
    /// the reading moves, so a stem-reading comparison accuses correct Japanese. 「友達が来ます。」
    /// reads 来 as き against a card teaching くる, and it is right. -ずる verbs alternate onto a
    /// じ stem (存ずる → 存じております), which STATE records as a place the Swift and Python
    /// copies of a rule already drifted apart; excluded here for the same reason.
    ///
    /// Keyed on `vc` rather than on a list of surfaces, so a new irregular is covered by its
    /// data rather than by remembering to add it — the `inflectionalTails` lesson from v1.24.
    private static let irregularVerbClasses: Set<String> = ["kuru", "suru", "zuru"]

    /// How the sentence reads the headword's stem, when the headword itself never appears.
    ///
    /// `headwordReadings` needs the headword as a contiguous token span and `coveringReading`
    /// needs it inside one — but a verb in a sentence is CONJUGATED, so its dictionary form is
    /// not present in any form. Measured on the shipped corpus, 874 of 6,738 sentences are
    /// invisible to the span walk, `coveringReading` rescues 104, and **770 were inspected by
    /// nothing at all**. 778 of the 874 are verbs or i-adjectives, and 236 of them are N4 or N5,
    /// so this was never an N1 tail.
    ///
    /// Three of the 770 taught a reading that is not the word the card teaches, and none of
    /// them could have been caught, because nothing looked:
    ///
    ///   n1-g305  潜る/くぐる  「暖簾を潜って…」   typed もぐって — a different verb entirely
    ///   n1-b045  汚れる/けがれる 「…心は汚れて…」  typed よごれて — the card's other reading
    ///   n1-b393  捲る/まくる  「…袖を捲って…」   typed めくって — the card's other reading
    ///
    /// The rule is derived, never a list of conjugations: a verb's dictionary form is absent
    /// but its KANJI STEM is present, so take the headword minus its okurigana, find every
    /// token written with that stem, and require the card's own reading of the stem to be
    /// prefix-compatible with each. There is no table of surface forms to be wrong about,
    /// which is the `inflectionalTails` mistake this project has already paid for once.
    ///
    /// **EVERY stem-bearing token must agree, not merely one of them.** "Pass if any agrees"
    /// is the obvious rule and it opens a false-negative hole: 「部屋で歌を歌います」 carries the
    /// noun 歌/うた beside the verb 歌い/うたい, so corrupting the verb's reading would pass on
    /// the strength of the noun. Exactly two shipped entries have more than one stem-bearing
    /// token; requiring all of them closes the hole, and the one entry where the disagreement
    /// is legitimate is named below rather than thresholded.
    static func stemReadings(of entry: VocabEntry)
        -> (stem: String, taught: String, found: [(surface: String, reading: String)])? {
        // Only where the two existing walks are blind — this gate exists for their residue.
        guard headwordReadings(of: entry) == nil else { return nil }
        guard let primary = entry.partsOfSpeech.first?.lowercased(),
              (primary.hasPrefix("v") && primary != "vs")
                  || primary == "adj-i" || primary == "i-adjective" else { return nil }
        guard !irregularVerbClasses.contains(entry.vc ?? "") else { return nil }
        let stem = String(entry.surface.dropLast())
        guard !stem.isEmpty, containsKanji(stem) else { return nil }
        guard let tokens = entry.exampleTokens else { return nil }
        let bearing = tokens.filter { $0.count >= 2 && $0[0].hasPrefix(stem) }
        guard !bearing.isEmpty else { return nil }
        let kana = KanaScript.katakanaToHiragana(entry.kana)
        // The card's reading of the STEM: its kana minus the okurigana the stem dropped.
        let taught = entry.surface.count - stem.count < kana.count
            ? String(kana.dropLast(entry.surface.count - stem.count)) : kana
        return (stem, taught,
                bearing.map { (surface: $0[0], reading: KanaScript.katakanaToHiragana($0[1])) })
    }

    /// The one entry where a token legitimately shares the headword's stem and is a different
    /// word: 「湿気でせんべいが湿気ってしまった。」 uses the NOUN 湿気/しっけ beside the verb
    /// 湿気って/しけって. The verb reads correctly; the noun is not this card's word and its
    /// reading is not this card's business.
    ///
    /// Named rather than thresholded, and it has a staleness companion, for the reason the
    /// file's own doc comment gives at `ratchetIsNotStale`: an exemption that outlives its
    /// entry hides the next offender behind it.
    private let knownStemSharedWithOtherWord: Set<String> = ["n1-b269"]

    /// Whether every stem-bearing token agrees with the card. One function, so the gate and its
    /// staleness companion cannot drift apart — the reason `sentenceUsesTheWord` was extracted,
    /// applied to the two companions that had retyped the comparison inline instead.
    private func stemAgreesWithCard(_ walk: (stem: String, taught: String,
                                             found: [(surface: String, reading: String)])) -> Bool {
        walk.found.allSatisfy {
            $0.reading.hasPrefix(walk.taught) || walk.taught.hasPrefix($0.reading)
        }
    }

    @Test("a conjugated headword's stem is read the way its own card teaches it")
    func stemIsReadAsTaught() {
        var inspected = 0
        var offenders: [String] = []
        for entry in withExamples {
            guard let walk = Self.stemReadings(of: entry) else { continue }
            inspected += 1
            if !stemAgreesWithCard(walk), !knownStemSharedWithOtherWord.contains(entry.id) {
                let seen = walk.found.map { "\($0.surface)=\($0.reading)" }.joined(separator: " ")
                offenders.append("\(entry.id) \(entry.surface): card teaches \(entry.kana) "
                                 + "(stem \(walk.stem) → \(walk.taught)), sentence has \(seen)")
            }
        }
        // A scan that inspected nothing would report a clean corpus. Measured on the shipped
        // corpus this walk reaches 648 of the 874 the span walk cannot see.
        #expect(inspected > 600, "only \(inspected) conjugated headwords — the stem walk is wrong")
        #expect(offenders.isEmpty, Comment(rawValue:
            "\(offenders.count) sentence(s) read their headword's stem a way the card does not "
            + "teach:\n" + offenders.prefix(12).joined(separator: "\n")))
    }

    @Test("the stem-reading exemption names only entries that still need it")
    func stemExemptionIsNotStale() {
        var stillOffending: Set<String> = []
        for entry in withExamples {
            guard let walk = Self.stemReadings(of: entry) else { continue }
            if !stemAgreesWithCard(walk) { stillOffending.insert(entry.id) }
        }
        let stale = knownStemSharedWithOtherWord.subtracting(stillOffending)
        #expect(stale.isEmpty, Comment(rawValue:
            "no longer offends — remove from knownStemSharedWithOtherWord: "
            + stale.sorted().joined(separator: ", ")))
    }

    /// The stem's reading where the tokenizer does not split ON the stem's boundary either.
    ///
    /// `stemReadings` needs a token that BEGINS with the stem. Sudachi does not always oblige:
    /// 意気込む comes back as 意気 + 込ん and 気に入る as 気 + に + 入っ, so no token bears the
    /// stem and both entries fell straight through into the uninspected residue — where the
    /// audit this release ran on that residue found them, and both were wrong:
    ///
    ///   n1-b1365  意気込む/いきごむ  typed いきこんで — the rendaku is missing; the word is いきごむ
    ///   n3-b222   気に入る/きにいる   typed きにはいった — 入る in this fixed expression is いる
    ///
    /// **Sudachi agrees with the corpus's error in both.** It reads 込ん as コン and 入っ as
    /// ハイッ, which are the common readings and the wrong ones here — the tokenizer regresses
    /// to exactly the reading under examination. That is the "a gate and the thing it gates
    /// share a blind spot" trap, so the arbiter here is the CARD, never the tokenizer.
    ///
    /// Weaker on purpose, exactly as `coveringReading` is and for the same reason: the span
    /// carries more than the stem, so the stem's own reading cannot be isolated and the card's
    /// reading need only appear SOMEWHERE inside it. The span is taken MINIMAL so the least
    /// foreign context is admitted — a wider span would let 物足りな pass on a なかっ that
    /// belonged to a neighbouring token.
    static func stemSpanReading(of entry: VocabEntry) -> (span: String, reading: String)? {
        guard stemReadings(of: entry) == nil, headwordReadings(of: entry) == nil,
              coveringReading(of: entry) == nil else { return nil }
        guard let primary = entry.partsOfSpeech.first?.lowercased(),
              (primary.hasPrefix("v") && primary != "vs")
                  || primary == "adj-i" || primary == "i-adjective" else { return nil }
        guard !irregularVerbClasses.contains(entry.vc ?? "") else { return nil }
        let stem = String(entry.surface.dropLast())
        guard !stem.isEmpty, containsKanji(stem) else { return nil }
        guard let tokens = entry.exampleTokens else { return nil }
        let content = tokens.filter { $0.count >= 2 }
        var best: (width: Int, span: String, reading: String)?
        for start in content.indices {
            var surface = ""
            for end in start..<content.count {
                surface += content[end][0]
                if surface.contains(stem) {
                    if best == nil || end - start < best!.width {
                        best = (end - start, surface, KanaScript.katakanaToHiragana(
                            content[start...end].map { $0[1] }.joined()))
                    }
                    break
                }
            }
        }
        guard let found = best else { return nil }
        return (found.span, found.reading)
    }

    @Test("a headword the tokenizer splits ACROSS the stem is still read as its card teaches")
    func stemSpanIsReadAsTaught() {
        var inspected = 0
        var offenders: [String] = []
        for entry in withExamples {
            guard let walk = Self.stemSpanReading(of: entry) else { continue }
            inspected += 1
            let kana = KanaScript.katakanaToHiragana(entry.kana)
            let taught = kana.count > 1 ? String(kana.dropLast()) : kana
            if !walk.reading.contains(taught) {
                offenders.append("\(entry.id) \(entry.surface): card teaches \(entry.kana), "
                                 + "\(walk.span) reads \(walk.reading)")
            }
        }
        #expect(inspected > 5, "only \(inspected) split stems — the span walk is wrong")
        #expect(offenders.isEmpty, Comment(rawValue:
            "\(offenders.count) split-stem headword(s) are misread:\n"
            + offenders.prefix(8).joined(separator: "\n")))
    }

    /// What NO reading gate can see, counted rather than assumed empty.
    ///
    /// This is the question v1.25 did not ask about its own gate, twice, at a cost of 240 and
    /// then 106 unexamined entries. It is asked here about the gate this release adds, in the
    /// release that adds it: a scan is not validated by what it catches, so the population it
    /// SKIPS is computed, printed with its level breakdown, and ratcheted.
    ///
    /// It is a ceiling, not an equality, so the number can only fall. It must never be
    /// asserted to be zero — it is 112, and pretending otherwise is the defect itself.
    @Test("the population no reading gate inspects is measured and can only shrink")
    func uninspectedPopulationIsMeasured() {
        var uninspected: [VocabEntry] = []
        for entry in withExamples {
            if Self.headwordReadings(of: entry) != nil { continue }
            if Self.coveringReading(of: entry) != nil { continue }
            if Self.stemReadings(of: entry) != nil { continue }
            if Self.stemSpanReading(of: entry) != nil { continue }
            uninspected.append(entry)
        }
        var byLevel: [Int: Int] = [:]
        for entry in uninspected { byLevel[entry.jlpt.rawValue, default: 0] += 1 }
        let breakdown = byLevel.keys.sorted()
            .map { "N\($0) \(byLevel[$0] ?? 0)" }.joined(separator: ", ")
        print("[v1.26 §A] \(uninspected.count) of \(withExamples.count) sentences are inspected "
              + "by NO reading gate — \(breakdown)")
        #expect(uninspected.count <= 112, Comment(rawValue:
            "\(uninspected.count) sentences are inspected by no reading gate (was 112): "
            + breakdown + ". The corpus grew into the blind spot, or a gate stopped reaching "
            + "entries it used to. NOTE this ratchet does NOT detect a gate being weakened: "
            + "the review measured that neutering `stemReadings` leaves this at exactly 112, "
            + "because `stemSpanReading` then absorbs all 648 into its weaker `contains` check. "
            + "What catches that is each gate's own `inspected` floor, not this number."))
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

    // MARK: v1.18 — the reading that makes a sentence typeable

    /// A typing target that is not pure kana cannot be typed at all: `KanaInputMatcher`
    /// compiles romaji paths for kana, so a stray kanji in `exKana` is an unreachable state
    /// and the learner can never finish the sentence.
    @Test("every sentence reading is pure kana")
    func readingIsKana() {
        let allowed = Set("ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとど"
                          + "なにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんー"
                          )
        var bad: [String] = []
        for e in withExamples {
            guard let kana = e.exampleKana else { continue }
            let stray = kana.filter { !allowed.contains($0) }
            if !stray.isEmpty { bad.append("\(e.id): \(String(stray)) in \(kana)") }
        }
        #expect(bad.isEmpty, Comment(rawValue: "\(bad.count) unreadable:\n"
                                                + bad.prefix(12).joined(separator: "\n")))
    }

    /// Furigana renders each token's reading above that token's surface, so the two lists
    /// must reconstruct the sentence and its reading EXACTLY. Drift by one character and the
    /// reading sits over the wrong kanji, which is worse than showing none.
    @Test("furigana tokens reconstruct both the sentence and its reading")
    func tokensAlign() {
        var bad: [String] = []
        for e in withExamples {
            guard let tokens = e.exampleTokens, let jp = e.exampleJP else { continue }
            let surfaces = tokens.compactMap(\.first).joined()
            // exKana is the TYPING target and carries no punctuation (。 and 、 cannot be
            // produced by romaji, so a target containing them can never be completed —
            // Passage.kana has had this rule since Practice shipped). exTokens keeps the
            // punctuation because furigana renders the sentence as written, so the readings
            // reconstruct exKana only after the punctuation is dropped.
            let punctuation = Set("、。！？「」")
            let readings = tokens.compactMap(\.last).joined().filter { !punctuation.contains($0) }
            if surfaces != jp { bad.append("\(e.id): surfaces rebuild \(surfaces), not \(jp)") }
            if let kana = e.exampleKana, readings != kana {
                bad.append("\(e.id): readings rebuild \(readings), not \(kana)")
            }
            if tokens.contains(where: { $0.count != 2 }) { bad.append("\(e.id): malformed token pair") }
        }
        #expect(bad.isEmpty, Comment(rawValue: "\(bad.count) misaligned:\n"
                                                + bad.prefix(12).joined(separator: "\n")))
    }

    /// The two fields are useless apart: a reading with no tokens cannot be furigana'd, and
    /// tokens with no reading have no typing target. Either both or neither.
    @Test("reading and tokens travel together")
    func pairedFields() {
        var bad: [String] = []
        for e in withExamples {
            let hasKana = !(e.exampleKana ?? "").isEmpty
            let hasTokens = !(e.exampleTokens ?? []).isEmpty
            if hasKana != hasTokens { bad.append("\(e.id): kana=\(hasKana) tokens=\(hasTokens)") }
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.prefix(12).joined(separator: "\n")))
    }

    /// Sentence mode needs enough material to be worth shipping. This is a floor, not a
    /// target: if it trips, the fix is to find out which sentences lost their reading, not to
    /// lower the number.
    @Test("enough sentences are typeable for the mode to exist")
    func coverage() {
        let typeable = withExamples.filter(\.isTypeableSentence).count
        #expect(typeable > 3_000,
                Comment(rawValue: "only \(typeable) of \(withExamples.count) are typeable"))
    }

    // MARK: v1.21 §D — the tidying the corpus work left behind

    /// The part-of-speech vocabulary, after v1.21 §D collapsed 42 spellings down to these.
    ///
    /// Six families had been written three ways each — `n`/`noun`/`Noun`, `v`/`verb`/`Verb`,
    /// and so on — because every generation batch and every reviewer round-trip spelled them
    /// its own way. `import_review_sheets.py` still writes back whatever a reviewer types
    /// with no normalisation, so the pipe that produced the mess is still open; this test is
    /// what closes it. `check_vocab_diff.py` cannot: it does not look at `pos` at all.
    private let canonicalPOS: Set<String> = [
        "n", "v", "adj-i", "adj-na", "adj-no", "adj-t", "adj-f",
        "adv", "adv-to", "conj", "pron", "suf", "pref", "num", "exp", "int",
        "vs", "vt", "vi", "v1", "v5r", "v5s", "v5m", "v5g", "v5u", "v5t",
    ]

    @Test("every part-of-speech tag is spelled the one canonical way")
    func posTagsAreCanonical() {
        var offenders: [String] = []
        for entry in VocabStore.shared.entries {
            for tag in entry.partsOfSpeech where !canonicalPOS.contains(tag) {
                offenders.append("\(entry.id) \(entry.surface): \(tag)")
            }
        }
        #expect(offenders.isEmpty, Comment(rawValue:
            "\(offenders.count) entries carry a non-canonical pos tag — run "
            + "scripts/normalize_pos_tags.py, and add the tag to BOTH lists if it is a "
            + "genuinely new class:\n" + offenders.prefix(10).joined(separator: "\n")))
    }

    /// A tag list is a set written as an array; the same class twice is a merge artifact,
    /// not two senses. Normalising `['n', 'Noun']` would have produced `['n', 'n']` if the
    /// script had not de-duplicated, and nothing else in the pipeline would have noticed.
    @Test("no entry carries the same part-of-speech tag twice")
    func posTagsAreUnique() {
        let dupes = VocabStore.shared.entries.filter {
            Set($0.partsOfSpeech).count != $0.partsOfSpeech.count
        }
        #expect(dupes.isEmpty, Comment(rawValue: "\(dupes.count) entries repeat a pos tag: "
                                                 + dupes.prefix(5).map(\.id).joined(separator: ", ")))
    }

    /// The fourteen sentences that will never have a reading, pinned by id.
    ///
    /// Twelve contain digits, which Sudachi reads one digit at a time — 「荷物は10キロあります」
    /// becomes いちれいきろ, "one-zero kilos" — and two contain the katakana middle dot, which
    /// survives into the reading where no romaji keystroke can produce it. They ship as
    /// display-only sentences, which is correct: a wrong typing target marks a learner wrong
    /// for typing exactly what the sentence says.
    ///
    /// The list is exact rather than a count so the failure says WHICH one moved. It fails in
    /// both directions on purpose: a fifteenth means the reading generator started refusing
    /// something new, and a thirteenth means one of these silently gained a hand-written
    /// reading — and six of them are unit words (キロ, グラム, メートル…) where writing the
    /// reading means committing to じゅっキロ over じっキロ, which is the contested-reading
    /// judgment that put 225 entries beyond teaching.
    @Test("exactly the known fourteen sentences have no typeable reading")
    func sentencesWithoutReadings() {
        let expected: Set<String> = [
            "n5-k008", "n5-k009", "n5-k010", "n5-k012", "n5-k058",
            "n4-g012", "n3-g084", "n3-g085", "n3-g108", "n3-g241",
            "n2-k003", "n2-k006", "n2-k056", "n1-k102",
        ]
        let actual = Set(withExamples.filter { !$0.isTypeableSentence }.map(\.id))
        #expect(actual == expected, Comment(rawValue:
            "gained: \(actual.subtracting(expected).sorted())  "
            + "lost: \(expected.subtracting(actual).sorted())"))
    }

    // MARK: v1.21 §C — the reading notes

    /// Every note must name a real entry that still has no example, and must not point a
    /// learner at a sibling that has since gone. The list is generated from a measurement
    /// file, so it can drift away from the corpus in three directions and none of them
    /// would be visible in the app — the note would simply not appear, or would name a card
    /// the learner cannot find.
    @Test("every reading note resolves, and points somewhere real")
    func readingNotesResolve() {
        let byID = Dictionary(VocabStore.shared.entries.map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        var problems: [String] = []
        for (id, note) in ReadingNotes.all {
            guard let entry = byID[id] else {
                problems.append("\(id): note for an entry that is not in the corpus")
                continue
            }
            if !(entry.exampleJP ?? "").isEmpty {
                problems.append("\(id): has an example now — the note is stale")
            }
            if note.common.isEmpty {
                problems.append("\(id): note names no everyday reading")
            }
            if note.common == entry.kana {
                problems.append("\(id): note says the everyday reading is \(note.common), "
                                + "which is what this card already teaches")
            }
            if let sibling = note.siblingID {
                if let other = byID[sibling] {
                    if other.kana != note.common {
                        problems.append("\(id): points at \(sibling) for \(note.common), "
                                        + "but that entry reads \(other.kana)")
                    }
                    if other.surface != entry.surface {
                        problems.append("\(id): points at \(sibling), a different spelling "
                                        + "(\(other.surface) vs \(entry.surface))")
                    }
                } else {
                    problems.append("\(id): points at \(sibling), which is not in the corpus")
                }
            }
        }
        #expect(problems.isEmpty, Comment(rawValue: "\(problems.count) bad reading note(s):\n"
                                                    + problems.prefix(10).joined(separator: "\n")))
        #expect(ReadingNotes.isLoaded, "the notes must load, or 216 cards silently lose them")
        #expect(ReadingNotes.all.count > 40, Comment(rawValue:
            "only \(ReadingNotes.all.count) notes — the generator kept 64 of 216 after "
            + "dropping every claim it could not corroborate without circular evidence. A "
            + "truncated file makes the cards it covers indistinguishable from their "
            + "siblings again. The floor is well below 64 on purpose: tightening the rule "
            + "SHOULD be able to drop notes without failing the suite, and it already has "
            + "once."))
        // Every note must name a reading taught at an EASIER level than the card's own.
        // Without that the note can be backwards, and three of them were: the にほん card
        // was told にっぽん is the everyday reading, 辛い/からい at N5 was pointed at つらい,
        // and 下/げ at しも while した ships at N5. The check that let them through was
        // circular — it counted how often the corpus reads a spelling each way, and the
        // corpus only contains sentences for the entry that got one.
        var backwards: [String] = []
        for (id, note) in ReadingNotes.all {
            guard let card = byID[id], let sibling = note.siblingID.flatMap({ byID[$0] })
            else { continue }
            if sibling.jlpt.rawValue <= card.jlpt.rawValue {
                backwards.append("\(id) \(card.surface)/\(card.kana) N\(card.jlpt.rawValue) "
                                 + "-> \(sibling.kana) N\(sibling.jlpt.rawValue)")
            }
        }
        #expect(backwards.isEmpty, Comment(rawValue:
            "\(backwards.count) note(s) name a reading that is NOT taught at an easier level, "
            + "so nothing supports calling it the everyday one:\n"
            + backwards.sorted().prefix(8).joined(separator: "\n")))
        // Every shipped note must be the corroborated kind: the sibling exists AND carries a
        // reviewed sentence in which that spelling is read that way. A note without a
        // sibling is the uncorroborated claim this release deliberately cut.
        let uncorroborated = ReadingNotes.all.filter { _, note in
            note.siblingID.flatMap { byID[$0]?.exampleJP } == nil
        }
        #expect(uncorroborated.isEmpty, Comment(rawValue:
            "\(uncorroborated.count) note(s) name an everyday reading nothing else attests: "
            + uncorroborated.keys.sorted().prefix(8).joined(separator: ", ")))
    }

    /// Dictation plays a synthesizer's reading of `exJP` and grades against `exKana`, so a
    /// sentence it is offered must have both plus the tokens the reveal draws its furigana
    /// from. Every id withheld from dictation must also still BE a sentence — an exclusion
    /// list that drifts onto ids the corpus no longer has looks like a shrinking safe pool
    /// and is really a stale file.
    /// The evidence behind every exclusion must still describe the corpus it was measured on.
    ///
    /// Each excluded sentence carries the `exKana` it had when the voice was measured against
    /// it. When the corpus is later corrected — v1.25 rewrote 69 sentences — that record starts
    /// quoting a reading the corpus no longer has, and every later decision about the exclusion
    /// is made against stale evidence.
    ///
    /// **This replaces two attempts at a cleverer test, both of which were wrong.** The first
    /// released an exclusion when the complained-of TOKEN had vanished — but v1.25 corrected
    /// sentences by MERGING token spans, which deletes the very token a complaint names, so the
    /// test could not fail and eight sentences were released whose corpus reading disagrees with
    /// the measured audio (十分 set to じっぷん while the voice says じゅうぶん: in dictation
    /// every keystroke after あと is refused). The second matched the heard reading anywhere in
    /// the sentence and flagged 80 sentences because 「彼 かれ -> か」 finds か in almost any
    /// kana string.
    ///
    /// What is left is the property that can be stated exactly and has no false positives:
    /// evidence must match the data it describes. Releasing an exclusion is then a decision
    /// somebody makes with a re-measurement in hand, which is what it always should have been —
    /// not something a substring test infers.
    /// **A gate v1.25 specified, built, and then deleted by accident.**
    ///
    /// PLAN-V1.25 §A required "a test that the resource equals what the generator emits" — the
    /// defect being that `reading-notes.json` had been one note SHORT of its own generator for
    /// three releases, because the rule was corrected in v1.22 §E and the file was never
    /// regenerated, and nothing compared the two.
    ///
    /// It was written (`readingNotesMatchTheirGenerator`, commit `e71e7be`) and removed in
    /// `fafae5a`, whose message is about merging token spans and blinding the exclusion gate
    /// and **never mentions it**. Its neighbour `exclusionResourceMatchesItsMeasurement` went in
    /// the same commit, but that one was properly SUPERSEDED by `exclusionEvidenceIsCurrent` and
    /// the message says so. One deletion was a decision; the other was an accident, and
    /// PLAN-V1.25's shipped table still counted both.
    ///
    /// The process finding underneath is the cheaper lesson and it is now also fixed:
    /// **nothing counted the gates**, so a gate could leave the suite inside the release that
    /// added it and the release would notice nothing. `everyRatchetHasACompanion` counts them.
    ///
    /// **Restored STRONGER than it was deleted.** The original compared the generator's
    /// reported COUNT against `ReadingNotes.all.count`, so a resource that differed from its
    /// generator in content rather than in length would have passed — and "the shipped resource
    /// equals what the generator emits" is what the plan asked for. `--json` emits the payload
    /// exactly as `--write` would serialise it, and this compares every note.
    @Test("the shipped reading notes are exactly what their generator emits")
    func readingNotesMatchTheirGenerator() throws {
        struct Note: Decodable, Equatable, Comparable {
            let id: String
            let kind: String
            let common: String
            let siblingID: String?
            static func < (a: Note, b: Note) -> Bool { a.id < b.id }
        }
        struct Payload: Decodable { let notes: [Note] }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3",
                             root.appendingPathComponent("scripts/gen_reading_notes.py").path,
                             "--json"]
        process.currentDirectoryURL = root
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read BEFORE waiting: a payload larger than the pipe buffer deadlocks the other way
        // round, and this one is ~7 KB today and grows with the corpus.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, Comment(rawValue:
            "the generator failed (\(process.terminationStatus)): \(errorText.prefix(400))"))

        let emitted = try JSONDecoder().decode(Payload.self, from: data).notes.sorted()
        let shipped = ReadingNotes.all.map {
            Note(id: $0.key, kind: $0.value.kind.rawValue,
                 common: $0.value.common, siblingID: $0.value.siblingID)
        }.sorted()

        // The count first, because a length mismatch is the original defect and its message is
        // the useful one; then the content, which is what the count could not see.
        #expect(emitted.count == shipped.count, Comment(rawValue:
            "the generator emits \(emitted.count) notes and the shipped resource holds "
            + "\(shipped.count) — run `python3 scripts/gen_reading_notes.py --write`"))
        let onlyEmitted = Set(emitted.map(\.id)).subtracting(shipped.map(\.id))
        let onlyShipped = Set(shipped.map(\.id)).subtracting(emitted.map(\.id))
        #expect(onlyEmitted.isEmpty && onlyShipped.isEmpty, Comment(rawValue:
            "generator-only: \(onlyEmitted.sorted()); resource-only: \(onlyShipped.sorted())"))
        #expect(emitted == shipped, Comment(rawValue:
            "same ids, different content — regenerate: "
            + zip(emitted, shipped).filter { $0 != $1 }
                .prefix(4).map { "\($0.0.id): \($0.0) vs \($0.1)" }.joined(separator: "; ")))
        // …and the comparison must have compared something.
        #expect(emitted.count > 50, "only \(emitted.count) notes — the generator produced almost nothing")
    }

    @Test("every dictation exclusion's evidence still matches the sentence it describes")
    func exclusionEvidenceIsCurrent() throws {
        struct Record: Decodable { let id: String; let exKana: String? }
        struct File: Decodable { let excluded: [Record] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/measurements/dictation-reading-mismatches.json")
        let file = try JSONDecoder().decode(File.self, from: try Data(contentsOf: url))
        let byID = Dictionary(VocabStore.shared.entries.map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        var inspected = 0
        var stale: [String] = []
        for record in file.excluded {
            guard let recorded = record.exKana, let entry = byID[record.id],
                  let current = entry.exampleKana else { continue }
            inspected += 1
            if recorded != current {
                stale.append("\(record.id): measured against \(recorded), corpus now says \(current)")
            }
        }
        #expect(inspected > 800, "only \(inspected) records carry an exKana — the reader is wrong")
        #expect(stale.isEmpty, Comment(rawValue:
            "\(stale.count) exclusion(s) rest on evidence the corpus no longer matches — "
            + "re-measure them:\n" + stale.prefix(8).joined(separator: "\n")))
    }

    @Test("every dictation exclusion names a real, otherwise-typeable sentence")
    func dictationExclusionsResolve() {
        let byID = Dictionary(VocabStore.shared.entries.map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        var stale: [String] = []
        for id in DictationSafety.excludedIDs {
            guard let entry = byID[id], entry.isTypeableSentence else {
                stale.append(id)
                continue
            }
        }
        #expect(stale.isEmpty, Comment(rawValue:
            "\(stale.count) excluded ids do not name a typeable sentence: "
            + stale.prefix(10).joined(separator: ", ")))
        #expect(DictationSafety.isLoaded, "the exclusion list must load, or dictation cannot be honest")
        // A list that loaded but is EMPTY passes every assertion above while meaning the
        // opposite of what they check — every sentence would be offered for dictation,
        // including the 27 proven to be spoken differently from their own exKana. The
        // measured list is ~15% of the corpus; a floor well under that catches a truncated
        // or regenerated-from-nothing file without pinning an exact number the next
        // measurement is allowed to move.
        #expect(DictationSafety.excludedIDs.count > 300, Comment(rawValue:
            "only \(DictationSafety.excludedIDs.count) exclusions — the shipped measurement "
            + "found 1,003. An empty or truncated list silently makes dictation dishonest."))
    }

    /// **The shipped list and the evidence behind it are two files, and nothing kept them in
    /// step.** v1.28 released eleven sentences from dictation and all 570 tests stayed green,
    /// which is the same shape as every count-vs-run defect this project has found: two sides
    /// of one fact, agreeing only by inspection.
    ///
    /// The bundle ships ids alone — deliberately, the 240 KB of evidence is for the repo, not
    /// for devices — so this reads the measurement record from the repo and requires the two to
    /// name exactly the same sentences. Withholding a sentence with no recorded reason, and
    /// recording a reason for a sentence that is not withheld, both go red.
    @Test("every withheld sentence has a recorded reason, and every reason a withheld sentence")
    func exclusionsAndEvidenceAgree() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("docs/measurements/dictation-reading-mismatches.json")
        let data = try Data(contentsOf: url)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(json["excluded"] as? [[String: Any]])
        let recorded = Set(rows.compactMap { $0["id"] as? String })
        // A scan that reads nothing cannot report clean.
        #expect(recorded.count > 300, "the evidence record parsed only \(recorded.count) rows")

        let shipped = Set(DictationSafety.excludedIDs)
        let withheldWithoutReason = shipped.subtracting(recorded).sorted()
        let reasonWithoutWithholding = recorded.subtracting(shipped).sorted()
        #expect(withheldWithoutReason.isEmpty, Comment(rawValue:
            "\(withheldWithoutReason.count) sentence(s) are withheld from dictation with no "
            + "recorded reason: " + withheldWithoutReason.prefix(8).joined(separator: ", ")))
        #expect(reasonWithoutWithholding.isEmpty, Comment(rawValue:
            "\(reasonWithoutWithholding.count) sentence(s) have a recorded exclusion reason but "
            + "are offered for dictation: " + reasonWithoutWithholding.prefix(8).joined(separator: ", ")))

        // Every reason must say something. "propagated" is retired: it named an inference
        // drawn from a DIFFERENT sentence, and v1.28 measured it wrong 11 times out of 15.
        let evidences = rows.compactMap { $0["evidence"] as? String }
        #expect(evidences.count == rows.count, "an exclusion row carries no evidence field")
        #expect(!evidences.contains("propagated"), Comment(rawValue:
            "\(evidences.filter { $0 == "propagated" }.count) exclusion(s) are back on "
            + "'propagated' evidence — that rule was retired in v1.28 because the comment "
            + "behind it ('a voice does not change its mind between sentences') is false: "
            + "畑 is proven はたけ in n1-b432 and ばたけ in n1-b1000."))
    }
}
