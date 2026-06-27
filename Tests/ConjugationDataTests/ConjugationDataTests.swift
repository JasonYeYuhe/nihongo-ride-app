import Testing
import Foundation
@testable import VocabKit
import ConjugationKit

/// B1 data-path golden (PLAN-V1.6 §3 layer-(ii) — the release gate): asserts the `vc`
/// labels DERIVED into the real shipped vocab JSON are self-consistent, that EVERY
/// vc'd entry conjugates cleanly through the engine, and that a curated core set is
/// correct end-to-end (data → vc → engine) against ground truth that is independent of
/// the engine. Unlike `ConjugatorCoreSetGoldenTests` (engine given a hand-fed class),
/// this validates the data DERIVATION — a wrong `vc` shows up here.
@Suite("ConjugationKit — derived vc data path (B1 gate)")
struct ConjugationDataTests {

    private static let entries = VocabStore.shared.entries
    private static let vcEntries = entries.filter { $0.vc != nil }

    // MARK: vc validity + conservation invariants

    @Test("every vc string maps to a real VerbClass")
    func vcParses() {
        for e in Self.vcEntries {
            #expect(VerbClass(rawValue: e.vc!) != nil, "\(e.surface)/\(e.kana) has bogus vc=\(e.vc!)")
        }
    }

    @Test("vc ↔ kana ending is self-consistent (godan row / ichidan る / kuru くる)")
    func kanaEndingConsistent() {
        let godanEnd: [String: Character] = [
            "godan_u": "う", "godan_k": "く", "godan_g": "ぐ", "godan_s": "す",
            "godan_t": "つ", "godan_n": "ぬ", "godan_b": "ぶ", "godan_m": "む", "godan_r": "る",
        ]
        for e in Self.vcEntries {
            let vc = e.vc!, kana = e.kana
            if let end = godanEnd[vc] {
                #expect(kana.last == end, "\(e.surface)/\(kana) vc=\(vc) but kana doesn't end \(end)")
            } else if vc == "ichidan" {
                #expect(kana.hasSuffix("る"), "\(e.surface)/\(kana) ichidan must end る")
            } else if vc == "kuru" {
                #expect(kana.hasSuffix("くる"), "\(e.surface)/\(kana) kuru must end くる")
            }
            // suru: no kana-ending invariant (noun reading りょうり OR べんきょうする) —
            // covered by `conjugatesCleanly`.
        }
    }

    @Test("every vc'd entry conjugates cleanly — all 7 forms non-nil")
    func conjugatesCleanly() {
        for e in Self.vcEntries {
            guard let cls = VerbClass(rawValue: e.vc!) else { continue }
            let forms = Conjugator.allForms(kana: e.kana, verbClass: cls, lemma: e.surface)
            #expect(forms.count == ConjugationForm.allCases.count,
                    "\(e.surface)/\(e.kana) vc=\(e.vc!) produced \(forms.count)/\(ConjugationForm.allCases.count) forms")
        }
    }

    @Test("every vc'd entry has a verb POS (no non-verb got a vc)")
    func nonVerbsHaveNoVC() {
        for e in Self.vcEntries {
            let pos = Set(e.partsOfSpeech.map { $0.lowercased() })
            let verbish = !pos.isDisjoint(with: ["v", "verb", "vi", "vt", "vs", "v1"])
                || pos.contains { $0.hasPrefix("v5") }
            #expect(verbish, "\(e.surface)/\(e.kana) has vc=\(e.vc!) but no verb POS \(e.partsOfSpeech)")
        }
    }

    // MARK: withhold / negative controls

    @Test("bare suru-verbs are withheld (no vc): 察する/愛する/関する/対する/属する")
    func bareSuruVerbsWithheld() {
        for kana in ["さっする", "あいする", "かんする", "たいする", "ぞくする"] {
            if let e = Self.entries.first(where: { $0.kana == kana }) {
                #expect(e.vc == nil, "\(e.surface)/\(kana) is a bare suru-verb — must have no vc, got \(e.vc ?? "")")
            }
        }
    }

    // MARK: end-to-end core-set golden (data → engine, engine-independent ground truth)

    private struct Core { let surface, kana, vc, te, potential: String }
    // Expected vc + the two telltale forms (te + potential, where ichidan and godan_r
    // diverge most). These values were derived from grammar, not from this engine.
    private static let core: [Core] = [
        Core(surface: "食べる", kana: "たべる", vc: "ichidan", te: "たべて", potential: "たべられる"),
        Core(surface: "見る", kana: "みる", vc: "ichidan", te: "みて", potential: "みられる"),
        Core(surface: "書く", kana: "かく", vc: "godan_k", te: "かいて", potential: "かける"),
        Core(surface: "泳ぐ", kana: "およぐ", vc: "godan_g", te: "およいで", potential: "およげる"),
        Core(surface: "話す", kana: "はなす", vc: "godan_s", te: "はなして", potential: "はなせる"),
        Core(surface: "待つ", kana: "まつ", vc: "godan_t", te: "まって", potential: "まてる"),
        Core(surface: "飲む", kana: "のむ", vc: "godan_m", te: "のんで", potential: "のめる"),
        Core(surface: "遊ぶ", kana: "あそぶ", vc: "godan_b", te: "あそんで", potential: "あそべる"),
        Core(surface: "買う", kana: "かう", vc: "godan_u", te: "かって", potential: "かえる"),
        Core(surface: "帰る", kana: "かえる", vc: "godan_r", te: "かえって", potential: "かえれる"),
        Core(surface: "入る", kana: "はいる", vc: "godan_r", te: "はいって", potential: "はいれる"),
        Core(surface: "走る", kana: "はしる", vc: "godan_r", te: "はしって", potential: "はしれる"),
        Core(surface: "来る", kana: "くる", vc: "kuru", te: "きて", potential: "こられる"),
    ]

    @Test("core verbs: derived vc matches expected AND conjugation matches ground truth")
    func coreEndToEnd() {
        for c in Self.core {
            guard let e = Self.entries.first(where: { $0.kana == c.kana && $0.surface == c.surface }) else {
                Issue.record("core verb \(c.surface)/\(c.kana) not found in vocab")
                continue
            }
            #expect(e.vc == c.vc, "\(c.surface)/\(c.kana) derived vc=\(e.vc ?? "nil"), expected \(c.vc)")
            guard let cls = VerbClass(rawValue: e.vc ?? "") else { continue }
            #expect(Conjugator.conjugate(kana: e.kana, verbClass: cls, lemma: e.surface, form: .te) == c.te,
                    "\(c.surface) te")
            #expect(Conjugator.conjugate(kana: e.kana, verbClass: cls, lemma: e.surface, form: .potential) == c.potential,
                    "\(c.surface) potential")
        }
    }

    // MARK: pool sanity (informs whether graceful N5–N3-only degradation is needed)

    @Test("conjugation pool is large and spans classes — no degradation needed")
    func poolHealthy() {
        let n53 = Self.vcEntries.filter { $0.jlpt.rawValue >= 3 }   // N5(5)/N4(4)/N3(3)
        #expect(n53.count >= 500, "N5–N3 pool too thin: \(n53.count)")
        let classes = Set(Self.vcEntries.compactMap { $0.vc })
        #expect(classes.count >= 11, "expected ≥11 classes in pool, got \(classes.count)")
    }
}
