import Testing
@testable import ConjugationKit

private typealias F = ConjugationForm

/// One golden verb and the exact kana expected for the forms under test.
private struct Golden {
    let label: String
    let kana: String
    let cls: VerbClass
    let expect: [F: String]
}

private func check(_ g: Golden, sourceLocation: SourceLocation = #_sourceLocation) {
    for (form, want) in g.expect {
        let got = Conjugator.conjugate(kana: g.kana, verbClass: g.cls, form: form)
        #expect(got == want, "\(g.label) \(form.rawValue): got \(got ?? "nil"), want \(want)", sourceLocation: sourceLocation)
    }
}

@Suite("ConjugationKit — golden vectors")
struct ConjugatorGoldenTests {

    @Test("ichidan (る-verb) full paradigm")
    func ichidan() {
        check(Golden(label: "見る", kana: "みる", cls: .ichidan, expect: [
            .polite: "みます", .te: "みて", .past: "みた", .negative: "みない",
            .pastNegative: "みなかった", .potential: "みられる", .volitional: "みよう",
        ]))
        check(Golden(label: "食べる", kana: "たべる", cls: .ichidan, expect: [
            .polite: "たべます", .te: "たべて", .past: "たべた", .negative: "たべない",
            .pastNegative: "たべなかった", .potential: "たべられる", .volitional: "たべよう",
        ]))
    }

    @Test("godan — every row, full paradigm (incl. 音便 te/ta and う→わ)")
    func godanAllRows() {
        check(Golden(label: "書く v5k", kana: "かく", cls: .godanK, expect: [
            .polite: "かきます", .te: "かいて", .past: "かいた", .negative: "かかない",
            .pastNegative: "かかなかった", .potential: "かける", .volitional: "かこう",
        ]))
        check(Golden(label: "泳ぐ v5g", kana: "およぐ", cls: .godanG, expect: [
            .polite: "およぎます", .te: "およいで", .past: "およいだ", .negative: "およがない",
            .pastNegative: "およがなかった", .potential: "およげる", .volitional: "およごう",
        ]))
        check(Golden(label: "話す v5s", kana: "はなす", cls: .godanS, expect: [
            .polite: "はなします", .te: "はなして", .past: "はなした", .negative: "はなさない",
            .pastNegative: "はなさなかった", .potential: "はなせる", .volitional: "はなそう",
        ]))
        check(Golden(label: "待つ v5t", kana: "まつ", cls: .godanT, expect: [
            .polite: "まちます", .te: "まって", .past: "まった", .negative: "またない",
            .pastNegative: "またなかった", .potential: "まてる", .volitional: "まとう",
        ]))
        check(Golden(label: "死ぬ v5n", kana: "しぬ", cls: .godanN, expect: [
            .polite: "しにます", .te: "しんで", .past: "しんだ", .negative: "しなない",
            .pastNegative: "しななかった", .potential: "しねる", .volitional: "しのう",
        ]))
        check(Golden(label: "遊ぶ v5b", kana: "あそぶ", cls: .godanB, expect: [
            .polite: "あそびます", .te: "あそんで", .past: "あそんだ", .negative: "あそばない",
            .pastNegative: "あそばなかった", .potential: "あそべる", .volitional: "あそぼう",
        ]))
        check(Golden(label: "飲む v5m", kana: "のむ", cls: .godanM, expect: [
            .polite: "のみます", .te: "のんで", .past: "のんだ", .negative: "のまない",
            .pastNegative: "のまなかった", .potential: "のめる", .volitional: "のもう",
        ]))
        check(Golden(label: "帰る v5r", kana: "かえる", cls: .godanR, expect: [
            .polite: "かえります", .te: "かえって", .past: "かえった", .negative: "かえらない",
            .pastNegative: "かえらなかった", .potential: "かえれる", .volitional: "かえろう",
        ]))
        check(Golden(label: "買う v5u (う→わ)", kana: "かう", cls: .godanU, expect: [
            .polite: "かいます", .te: "かって", .past: "かった", .negative: "かわない",
            .pastNegative: "かわなかった", .potential: "かえる", .volitional: "かおう",
        ]))
    }

    @Test("する / くる full irregular paradigms")
    func suruKuru() {
        check(Golden(label: "する", kana: "する", cls: .suru, expect: [
            .polite: "します", .te: "して", .past: "した", .negative: "しない",
            .pastNegative: "しなかった", .potential: "できる", .volitional: "しよう",
        ]))
        check(Golden(label: "くる", kana: "くる", cls: .kuru, expect: [
            .polite: "きます", .te: "きて", .past: "きた", .negative: "こない",
            .pastNegative: "こなかった", .potential: "こられる", .volitional: "こよう",
        ]))
    }

    @Test("suru-noun conjugates as noun-reading + する (NOT godan-by-ending)")
    func suruNoun() {
        check(Golden(label: "勉強(する)", kana: "べんきょう", cls: .suru, expect: [
            .polite: "べんきょうします", .te: "べんきょうして", .past: "べんきょうした",
            .negative: "べんきょうしない", .pastNegative: "べんきょうしなかった",
            .potential: "べんきょうできる", .volitional: "べんきょうしよう",
        ]))
        // Real N5 data stores some suru-nouns with する already in the kana
        // (勉強/べんきょうする, pos:["v"]). suruForm drops the trailing する, so the
        // paradigm is identical to the no-する representation above — lock that in.
        check(Golden(label: "勉強する (kana incl. する)", kana: "べんきょうする", cls: .suru, expect: [
            .polite: "べんきょうします", .te: "べんきょうして", .past: "べんきょうした",
            .negative: "べんきょうしない", .pastNegative: "べんきょうしなかった",
            .potential: "べんきょうできる", .volitional: "べんきょうしよう",
        ]))
        // Negative control: the suru-noun must NOT be conjugated as godan_u (べんきょって).
        #expect(Conjugator.conjugate(kana: "べんきょう", verbClass: .suru, form: .te) != "べんきょって")
        // The former golden here pinned 察する(さっする).potential = さっできる — a real
        // grammar BUG (察する is a bare suru-VERB, vs-s; its potential is 察せる). The
        // engine can't tell さっする(→せる) from べんきょうする(→できる) by reading alone,
        // so bare suru-verbs are WITHHELD at the data-derivation layer (no `vc`) — that
        // protection is tested in B1's data-path golden (察する must carry no `vc`), not
        // here. The `.suru` class contract is suru-nouns + standalone する only.
        #expect(Conjugator.conjugate(kana: "する", verbClass: .suru, form: .potential) == "できる")
    }

    @Test("lemma exceptions: 行く て/た, ある negative, v5aru keigo polite stem")
    func lemmaExceptions() {
        // 行く: te/ta are って/った, not いて/いた; rest regular godan-k.
        check(Golden(label: "行く", kana: "いく", cls: .godanK, expect: [
            .polite: "いきます", .te: "いって", .past: "いった", .negative: "いかない",
            .pastNegative: "いかなかった", .potential: "いける", .volitional: "いこう",
        ]))
        #expect(Conjugator.conjugate(kana: "いく", verbClass: .godanK, form: .te) != "いいて")  // the trap

        // ある: negative ない / なかった (not あらない); rest regular godan-r.
        check(Golden(label: "ある", kana: "ある", cls: .godanR, expect: [
            .polite: "あります", .te: "あって", .past: "あった", .negative: "ない",
            .pastNegative: "なかった", .potential: "あれる", .volitional: "あろう",
        ]))

        // v5aru keigo: polite stem り→い (くださいます), rest = godan-r.
        check(Golden(label: "くださる", kana: "くださる", cls: .godanR, expect: [
            .polite: "くださいます", .te: "くださって", .past: "くださった",
            .negative: "くださらない", .volitional: "くださろう",
        ]))
        #expect(Conjugator.conjugate(kana: "くださる", verbClass: .godanR, form: .polite) != "くださります")  // the trap
        check(Golden(label: "いらっしゃる", kana: "いらっしゃる", cls: .godanR, expect: [
            .polite: "いらっしゃいます", .te: "いらっしゃって",
        ]))
    }

    @Test("compounds: 連れて行く euphonic, 持ってくる kuru")
    func compounds() {
        check(Golden(label: "連れて行く", kana: "つれていく", cls: .godanK, expect: [
            .polite: "つれていきます", .te: "つれていって", .past: "つれていった",
        ]))
        check(Golden(label: "持ってくる", kana: "もってくる", cls: .kuru, expect: [
            .polite: "もってきます", .te: "もってきて", .negative: "もってこない", .volitional: "もってこよう",
        ]))
    }

    @Test("zuru (演ずる/感ずる…): ず→じ stem, ichidan-style endings, no euphonic change")
    func zuru() {
        // Ground truth = grammar (ずる verbs inflect on the じ-stem: 演ずる → 演じます/演じて…).
        // These are the 13 real "Ichidan verb - zuru verb" entries in the shipped vocab.
        func z(_ label: String, _ kana: String, _ stem: String) -> Golden {
            Golden(label: label, kana: kana, cls: .zuru, expect: [
                .polite: stem + "ます", .te: stem + "て", .past: stem + "た",
                .negative: stem + "ない", .pastNegative: stem + "なかった",
                .potential: stem + "られる", .volitional: stem + "よう",
            ])
        }
        check(z("演ずる", "えんずる", "えんじ"))
        check(z("応ずる", "おうずる", "おうじ"))
        check(z("感ずる", "かんずる", "かんじ"))
        check(z("信ずる", "しんずる", "しんじ"))
        check(z("存ずる", "ぞんずる", "ぞんじ"))
        check(z("生ずる", "しょうずる", "しょうじ"))
        check(z("通ずる", "つうずる", "つうじ"))
        check(z("命ずる", "めいずる", "めいじ"))
        check(z("論ずる", "ろんずる", "ろんじ"))
        check(z("禁ずる", "きんずる", "きんじ"))
        check(z("準ずる", "じゅんずる", "じゅんじ"))
        check(z("報ずる", "ほうずる", "ほうじ"))
        check(z("重んずる", "おもんずる", "おもんじ"))

        // Guard: a kana not ending ずる yields nil (never a bogus form).
        #expect(Conjugator.conjugate(kana: "たべる", verbClass: .zuru, form: .te) == nil)
        #expect(Conjugator.conjugate(kana: "えんずる", verbClass: .zuru, form: .te) == "えんじて")
        // The trap: 演ずる is NOT a plain ichidan (ichidan would drop る → えんず + ます = えんずます).
        #expect(Conjugator.conjugate(kana: "えんずる", verbClass: .ichidan, form: .polite) == "えんずます")
        #expect(Conjugator.conjugate(kana: "えんずる", verbClass: .zuru, form: .polite) == "えんじます")
        // Red line: genuine godan_r ずる verbs (削る/譲る) stay godan_r, NOT zuru — a data-layer
        // guarantee tested in ConjugationDataTests; here we just pin the godan_r te-form.
        #expect(Conjugator.conjugate(kana: "けずる", verbClass: .godanR, form: .te) == "けずって")
        #expect(Conjugator.conjugate(kana: "ゆずる", verbClass: .godanR, form: .te) == "ゆずって")
    }

    @Test("る-disambiguation: 帰る(v5r) vs 食べる(ichidan) produce different te-forms")
    func ruDisambiguation() {
        #expect(Conjugator.conjugate(kana: "かえる", verbClass: .godanR, form: .te) == "かえって")
        #expect(Conjugator.conjugate(kana: "たべる", verbClass: .ichidan, form: .te) == "たべて")
        // Same kana ending る, different class → different result (the core ambiguity).
        #expect(Conjugator.conjugate(kana: "かえる", verbClass: .godanR, form: .te)
                != Conjugator.conjugate(kana: "たべる", verbClass: .ichidan, form: .te))
    }

    @Test("negative control: a non-verb kana yields nil rather than a wrong form")
    func negativeControl() {
        // i-adjective reading mis-fed with a verb class: い isn't an う-row ending,
        // and たかい doesn't end in る → engine returns nil, never a bogus conjugation.
        #expect(Conjugator.conjugate(kana: "たかい", verbClass: .godanU, form: .te) == nil)
        #expect(Conjugator.conjugate(kana: "たかい", verbClass: .ichidan, form: .polite) == nil)
    }

    @Test("allForms returns the full first-batch set")
    func allFormsComplete() {
        let forms = Conjugator.allForms(kana: "かく", verbClass: .godanK)
        #expect(forms.count == ConjugationForm.allCases.count)
        #expect(forms[.te] == "かいて")
    }
}
