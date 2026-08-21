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
    @Test("a sentence reads its headword the way its own card teaches it")
    func readsItsHeadwordAsTaught() {
        var offenders: [String] = []
        var inspected = 0
        for entry in withExamples {
            guard let tokens = entry.exampleTokens else { continue }
            let own = tokens.filter { $0.count >= 2 && $0[0] == entry.surface }
            guard !own.isEmpty else { continue }
            inspected += 1
            let readings = own.map { KanaScript.katakanaToHiragana($0[1]) }
            if !readings.contains(KanaScript.katakanaToHiragana(entry.kana)),
               !knownHeadwordReadingMismatch.contains(entry.id) {
                offenders.append("\(entry.id) \(entry.surface): card says \(entry.kana), "
                                 + "sentence says \(readings.joined(separator: "/"))")
            }
        }
        // A scan that inspected nothing would report a clean corpus. Most sentences do contain
        // their headword as a bare token — 83.6% of them, measured — so this floor is far below
        // what a working walk sees and far above what a broken one does.
        #expect(inspected > 4_000, "only \(inspected) sentences contain their headword as a token")
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
    /// Thirteen of the original twenty-one were corrected in v1.25 §A. These eight were
    /// classified REGISTER — the two readings mean the same thing in that sentence and differ
    /// only in formality — independently by two models, and v1.21 §C has already decided that a
    /// minority reading is not an error. Correcting them would overturn a recorded decision, and
    /// would mean authoring Japanese to satisfy a card:
    ///
    ///   n1-g315  獣    けだもの / けもの      both "beast"
    ///   n1-b005  怒る  いかる / おこる        both "to be angry"; いかる is the literary one
    ///   n1-b016  大事  おおごと / だいじ      both "a serious matter" in 大事に至る
    ///   n1-b071  消耗  しょうこう / しょうもう  identical meaning; しょうこう is the original reading
    ///   n1-b072  所々  しょしょ / ところどころ  both "here and there"
    ///   n3-g131  得る  える / うる            both "to obtain"; うる is formal
    ///   n5-ashita 明日 あした / あす          both "tomorrow"
    ///   n5-g012  私    わたし / わたくし      both "I"; わたくし is formal
    ///
    /// They stay named so the list is a decision with a reason, not a silence. If the register
    /// question is ever reopened, this is where it starts.
    private let knownHeadwordReadingMismatch: Set<String> = [
        "n1-g315", "n1-b005", "n1-b016", "n1-b071", "n1-b072",
        "n3-g131", "n5-ashita", "n5-g012",
    ]

    /// A ratchet that is not shrinking is a list nobody is working through, and one that names
    /// an entry already fixed hides the next offender behind a stale exemption.
    @Test("the headword-reading ratchet names only entries that still offend")
    func ratchetIsNotStale() {
        var stillOffending: Set<String> = []
        for entry in withExamples {
            guard let tokens = entry.exampleTokens else { continue }
            let own = tokens.filter { $0.count >= 2 && $0[0] == entry.surface }
            guard !own.isEmpty else { continue }
            let readings = own.map { KanaScript.katakanaToHiragana($0[1]) }
            if !readings.contains(KanaScript.katakanaToHiragana(entry.kana)) {
                stillOffending.insert(entry.id)
            }
        }
        let stale = knownHeadwordReadingMismatch.subtracting(stillOffending)
        #expect(stale.isEmpty,
                Comment(rawValue: "fixed — remove from knownHeadwordReadingMismatch: "
                                  + stale.sorted().joined(separator: ", ")))
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
    /// An exclusion whose reason has been repaired is content withheld for nothing.
    ///
    /// Each excluded sentence carries a recorded complaint of the form `箱 ばこ -> はこ`: the
    /// checker measured that `exKana` said ばこ where the voice says はこ. When the corpus is
    /// later corrected to what the voice says — which is exactly what v1.25 §A did for 箱, 言う
    /// and eleven headwords — the complaint no longer describes anything, and the sentence is
    /// being kept out of dictation by a reason that has been fixed.
    ///
    /// v1.25 found 27 such exclusions by hand and released them, taking the dictation pool from
    /// 5,720 to 5,747. This is the check that finds the next one without anybody looking. It is
    /// deliberately NOT a re-decision of the 961 exclusions whose complaint still matches the
    /// corpus — those stand or fall on the instrument that made them, which is a separate
    /// argument recorded in PLAN-V1.25 §C.
    ///
    /// It reads the measurement file rather than the shipped resource because the resource
    /// carries only ids; the reason lives with the measurement, which is where a reason belongs.
    /// The shipped reading notes must be what their generator emits today.
    ///
    /// `gen_reading_notes.py` derives every note from the corpus: a card teaching a minority
    /// reading gets a line naming the everyday reading of its spelling and the card that teaches
    /// it, but only when a sibling at an EASIER level exists to be the second source. The rule
    /// was corrected in v1.22 §E — three notes had been printing backwards — and the resource was
    /// never regenerated afterwards, so it shipped one note short of its own rule for three
    /// releases and nothing compared the two.
    ///
    /// This is not a check that the notes are good; it is a check that the file and the
    /// generator have not drifted. Derivable data that is checked in as a resource needs one of
    /// these or it silently becomes a snapshot of whenever somebody last remembered.
    @Test("the shipped reading notes are what the generator produces from today's corpus")
    func readingNotesMatchTheirGenerator() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("scripts/gen_reading_notes.py").path]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let printed = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // The generator's report line is the one number both sides can be compared on without
        // re-implementing its rule here — which would be the same rule written twice.
        guard let line = printed.split(separator: "\n").first(where: { $0.hasPrefix("notes:") }),
              let emitted = Int(line.dropFirst("notes:".count)
                  .trimmingCharacters(in: .whitespaces).prefix(while: \.isNumber))
        else {
            Issue.record("could not read the generator's note count from: \(printed.prefix(200))")
            return
        }
        #expect(emitted == ReadingNotes.all.count, Comment(rawValue:
                "the generator emits \(emitted) notes and the shipped resource holds "
                + "\(ReadingNotes.all.count) — regenerate it"))
    }

    @Test("no dictation exclusion rests on a reading the corpus no longer contains")
    func exclusionReasonsStillHold() throws {
        struct Record: Decodable { let id: String; let heardInstead: String? }
        struct File: Decodable { let excluded: [Record] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/measurements/dictation-reading-mismatches.json")
        let file = try JSONDecoder().decode(File.self, from: try Data(contentsOf: url))
        let byID = Dictionary(VocabStore.shared.entries.map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        var inspected = 0
        var voided: [String] = []
        for record in file.excluded {
            // "surface reading -> whatTheVoiceSays". Anything else (propagated exclusions say
            // so in prose) carries no per-sentence claim to check.
            guard let complaint = record.heardInstead else { continue }
            let parts = complaint.split(separator: " ")
            guard parts.count >= 3, parts[2] == "->" else { continue }
            let surface = String(parts[0]), reading = String(parts[1])
            guard let entry = byID[record.id], let tokens = entry.exampleTokens else { continue }
            inspected += 1
            if !tokens.contains(where: { $0.count >= 2 && $0[0] == surface && $0[1] == reading }) {
                voided.append("\(record.id): withheld because \(complaint), which no longer occurs")
            }
        }
        // A parse that matched nothing would report every exclusion sound. The file records
        // ~1,000 exclusions and the great majority carry a parseable complaint.
        #expect(inspected > 800, "only \(inspected) complaints parsed — the reader is wrong")
        #expect(voided.isEmpty, Comment(rawValue:
            "\(voided.count) exclusion(s) rest on a repaired reason — release them:\n"
            + voided.prefix(10).joined(separator: "\n")))
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
}
