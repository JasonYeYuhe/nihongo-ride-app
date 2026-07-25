import Testing
import Foundation
import ConjugationKit
@testable import VocabKit

/// Regressions for forms this app once taught WRONG.
///
/// The existing data gate asserts every vc'd entry produces 7 non-nil forms — which is
/// exactly why these shipped: a fabricated form is still a non-nil string. For a teaching
/// app the only check that means anything is against the CORRECT answer, so these pin
/// values, not nil-ness. (v1.14 §A/§B.)
@Suite("Conjugation — forms this app once got wrong")
struct WrongTeachingRegressionTests {

    private func entry(_ id: String) -> VocabEntry? {
        VocabStore.shared.entries.first { $0.id == id }
    }

    @Test("a suru-noun whose reading merely ends in いく is not conjugated like 行く")
    func suruNounsEndingInIku() {
        // The 行く euphonic exception matched on the reading alone, so 保育(ほいく) and friends
        // were drilled as ほいって — a non-word the learner had to type to advance. Their
        // polite forms were always right, which is what made it look plausible.
        let cases = [("ほいく", "保育"), ("はついく", "発育"), ("せいいく", "生育"),
                     ("しいく", "飼育"), ("さいく", "細工")]
        for (kana, label) in cases {
            let te = Conjugator.conjugate(kana: kana, verbClass: .suru, form: .te)
            let past = Conjugator.conjugate(kana: kana, verbClass: .suru, form: .past)
            #expect(te == kana + "して", "\(label): te was \(te ?? "nil")")
            #expect(past == kana + "した", "\(label): past was \(past ?? "nil")")
        }
    }

    @Test("行く itself keeps its euphonic って/った — the fix must not overshoot")
    func ikuKeepsItsException() {
        #expect(Conjugator.conjugate(kana: "いく", verbClass: .godanK, form: .te) == "いって")
        #expect(Conjugator.conjugate(kana: "いく", verbClass: .godanK, form: .past) == "いった")
        // Compounds too (連れて行く).
        #expect(Conjugator.conjugate(kana: "つれていく", verbClass: .godanK, form: .te) == "つれていって")
        // A REAL godan-k verb that isn't 行く still takes the regular いて.
        #expect(Conjugator.conjugate(kana: "かく", verbClass: .godanK, form: .te) == "かいて")
    }

    @Test("suru-nouns that are homophones of godan verbs are tagged suru, not godan")
    func homophoneSuruNounsAreNotGodan() {
        // 披露(ひろう) / 予想(よそう) / 寄贈(きそう) read like 拾う / 装う / 競う, and the vc
        // derivation trusted JMdict's reading match, stamping them godan_u. Every one of
        // their 7 forms then came out of the wrong paradigm (披露 → ひろって, not 披露して).
        for id in ["n2-g040", "n2-g058", "n1-b479"] {
            guard let e = entry(id) else {
                Issue.record("missing entry \(id)"); continue
            }
            #expect(e.vc == "suru", "\(id) \(e.surface) is a suru-noun, got vc=\(e.vc ?? "nil")")
            let te = Conjugator.conjugate(kana: e.kana, verbClass: .suru, form: .te)
            #expect(te == e.kana + "して", "\(e.surface): te was \(te ?? "nil")")
        }
    }

    @Test("no pure-kanji headword carries an inflecting verb class")
    func noPureKanjiInflectingClass() {
        // The structural rule behind the fix: a real godan/ichidan verb always writes its
        // okurigana (拾う, 食べる). A pure-kanji surface with an inflecting class is a
        // homophone mistag — the shape that produced all three bad entries above.
        let inflecting: Set<String> = ["godan_u", "godan_k", "godan_g", "godan_s", "godan_t",
                                       "godan_n", "godan_b", "godan_m", "godan_r", "ichidan"]
        for e in VocabStore.shared.entries {
            guard let vc = e.vc, inflecting.contains(vc), let last = e.surface.last else { continue }
            let isHiragana = last.unicodeScalars.allSatisfy { (0x3041...0x309F).contains(Int($0.value)) }
            #expect(isHiragana, "\(e.id) \(e.surface) (\(e.kana)) is pure-kanji but tagged \(vc)")
        }
    }

    @Test("a kanji headword is never a truncated prefix of its own reading")
    func surfaceIsNotTruncated() {
        // お手伝いさ (kana おてつだいさん) shipped as the 64pt prompt — a non-word missing its
        // final ん.
        //
        // The rule has to be narrow. A first draft flagged any kana surface whose length
        // differed from its reading and caught eight PERFECTLY VALID entries: キロ/キログラム,
        // やはり/やっぱり, ジェット/ジェット機, けれど/けれども, そうして/そして, じゃ/じゃあ,
        // コンピュータ/コンピューター — common contractions and variant spellings, not errors.
        // What made お手伝いさ wrong was specifically that it is a strict PREFIX of its own
        // reading while containing kanji: a mixed kanji/kana headword whose trailing okurigana
        // stops short. Contractions differ in shape, not by truncation, so they don't match.
        // No structural sweep here: every version of that rule I tried either missed this
        // entry or flagged the valid contractions above, because "truncated" and "variant
        // spelling" are not distinguishable from the strings alone. The pure-kanji audit in
        // `noPureKanjiInflectingClass` is the structural check that DOES hold; this one pins
        // the fact.
        guard let helper = entry("n2-b214") else { Issue.record("missing n2-b214"); return }
        #expect(helper.surface == "お手伝いさん", "surface was \(helper.surface)")
        #expect(helper.kana == "おてつだいさん")
    }

    @Test("a suru-verb headword writes its する, matching the reading it asks for")
    func suruVerbSurfacesIncludeSuru() {
        // 勉強 / 散歩 / 掃除 / 練習 shipped as the 64pt prompt while the typing target was
        // べんきょうする / さんぽする / … — the four most common suru-verbs an N5 learner meets,
        // each showing a headword whose reading is NOT what it wanted typed.
        //
        // The cause is visible only next to the noun entries: 勉強/べんきょう already exists as
        // n5-benkyou, and 散歩・掃除・練習 exist at N3. These are the VERB copies, and the する
        // was appended to the READING alone to get past the global reading-uniqueness gate —
        // which it did, at the cost of a headword that no longer matched. Writing 勉強する is
        // both correct Japanese and the thing that makes surface and reading agree again.
        //
        // The rule below is structural and exact: across all 7074 entries it selects these
        // four and nothing else. 擦る/こする is a genuine godan-r verb, not a suru-verb, and
        // its class keeps it out.
        for e in VocabStore.shared.entries where e.vc == "suru" && e.kana.hasSuffix("する") {
            #expect(e.surface.hasSuffix("する"),
                    "\(e.id) shows \(e.surface) but asks for \(e.kana)")
        }
        // And the four are still present, still conjugating from the noun stem.
        for id in ["n5-b078", "n5-b095", "n5-b164", "n5-b197"] {
            guard let e = entry(id) else { Issue.record("missing \(id)"); continue }
            let polite = Conjugator.conjugate(kana: e.kana, verbClass: .suru, form: .polite)
            #expect(polite == String(e.kana.dropLast(2)) + "します",
                    "\(e.surface): polite was \(polite ?? "nil")")
        }
        // The noun entries they were colliding with are untouched — the fix must not have
        // been "make them unique by deleting one".
        #expect(entry("n5-benkyou")?.kana == "べんきょう")
    }

    @Test("より is taught as より, not as 方")
    func yoriIsNotHou() {
        // n5-b380 displayed より while teaching the reading ほう and the meaning "direction"
        // — the same level already teaches より correctly at n5-b200. A beginner met the
        // most common N5 particle with a false reading AND a false meaning.
        guard let e = entry("n5-b380") else { Issue.record("missing n5-b380"); return }
        #expect(e.kana == "ほう")
        #expect(e.surface == "方", "surface was \(e.surface)")
        // And the real より is still there and still correct.
        guard let yori = entry("n5-b200") else { Issue.record("missing n5-b200"); return }
        #expect(yori.surface == "より" && yori.kana == "より")
    }
}
