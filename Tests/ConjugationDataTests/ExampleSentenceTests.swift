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
        #expect(ReadingNotes.all.count > 60, Comment(rawValue:
            "only \(ReadingNotes.all.count) notes — the generator kept 87 of 216 after "
            + "dropping every claim with no second source. A truncated file makes the cards "
            + "it covers indistinguishable from their siblings again."))
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
}
