import Foundation

/// Pure, zero-dependency Japanese verb conjugator (PLAN-V1.5 §B2). Given a
/// dictionary-form reading (kana), a ``VerbClass``, and the form to produce, it
/// returns the conjugated **kana** — the learner's typing target. No IO, no state,
/// Sendable. Output is transient and is NEVER persisted as a `VocabEntry`
/// (red line §8.5).
///
/// Lemma exceptions are checked BEFORE the regular class rules (行く→行って,
/// ある→ない, v5aru keigo polite stem り→い, etc.); する/くる are full irregular
/// paradigms; suru-nouns conjugate as `noun-reading + する` composition.
public enum Conjugator {

    // う-row dictionary-ending → the row used by each stem (る intentionally
    // included for godan-r; ichidan handles る separately).
    private static let iStem: [Character: Character] = [
        "う": "い", "く": "き", "ぐ": "ぎ", "す": "し", "つ": "ち",
        "ぬ": "に", "ぶ": "び", "む": "み", "る": "り",
    ]
    private static let aStem: [Character: Character] = [
        "う": "わ", "く": "か", "ぐ": "が", "す": "さ", "つ": "た",   // う→わ (not あ)
        "ぬ": "な", "ぶ": "ば", "む": "ま", "る": "ら",
    ]
    private static let eStem: [Character: Character] = [
        "う": "え", "く": "け", "ぐ": "げ", "す": "せ", "つ": "て",
        "ぬ": "ね", "ぶ": "べ", "む": "め", "る": "れ",
    ]
    private static let oStem: [Character: Character] = [
        "う": "お", "く": "こ", "ぐ": "ご", "す": "そ", "つ": "と",
        "ぬ": "の", "ぶ": "ぼ", "む": "も", "る": "ろ",
    ]
    // て / た euphonic (音便) by dictionary-ending kana.
    private static let euphonic: [Character: (te: String, ta: String)] = [
        "う": ("って", "った"), "つ": ("って", "った"), "る": ("って", "った"),
        "ぶ": ("んで", "んだ"), "む": ("んで", "んだ"), "ぬ": ("んで", "んだ"),
        "く": ("いて", "いた"), "ぐ": ("いで", "いだ"), "す": ("して", "した"),
    ]
    /// v5aru keigo verbs: regular godan-r everywhere EXCEPT the polite stem (り→い):
    /// くださる→くださいます (not くださります).
    private static let v5aru: Set<String> = [
        "くださる", "いらっしゃる", "なさる", "おっしゃる", "ござる",
    ]

    /// Conjugates `kana` (a dictionary-form reading) to `form`. Returns nil if the
    /// input can't be conjugated for that class (e.g. a godan kana not ending in an
    /// う-row sound). `lemma` (surface) is accepted for future exceptions but the
    /// current table keys off the reading.
    public static func conjugate(
        kana: String,
        verbClass: VerbClass,
        lemma: String? = nil,
        form: ConjugationForm
    ) -> String? {
        if let ex = lemmaException(kana: kana, form: form) { return ex }
        switch verbClass {
        case .suru:    return suruForm(kana: kana, form: form)
        case .kuru:    return kuruForm(kana: kana, form: form)
        case .ichidan: return ichidanForm(kana: kana, form: form)
        default:       return godanForm(kana: kana, form: form)   // all godan_*
        }
    }

    /// All first-batch forms, omitting any that don't apply.
    public static func allForms(kana: String, verbClass: VerbClass, lemma: String? = nil) -> [ConjugationForm: String] {
        var out: [ConjugationForm: String] = [:]
        for f in ConjugationForm.allCases {
            if let v = conjugate(kana: kana, verbClass: verbClass, lemma: lemma, form: f) { out[f] = v }
        }
        return out
    }

    // MARK: Lemma exceptions (checked first)

    private static func lemmaException(kana: String, form: ConjugationForm) -> String? {
        // 行く-type: te/ta euphonic is って/った (not いて/いた). Catches 行く and
        // compounds (連れて行く). Other forms fall through to godan-k rules.
        if kana.hasSuffix("いく") {
            let stem = String(kana.dropLast())   // drop く
            switch form {
            case .te:   return stem + "って"
            case .past: return stem + "った"
            default: break
            }
        }
        // ある: negative is ない / なかった (not あらない). Other forms regular godan-r.
        if kana == "ある" {
            switch form {
            case .negative:     return "ない"
            case .pastNegative: return "なかった"
            default: break
            }
        }
        // v5aru keigo: polite stem is い (くださ+います), not り. Rest = godan-r.
        if v5aru.contains(kana), form == .polite {
            return String(kana.dropLast()) + "います"
        }
        return nil
    }

    // MARK: Class paradigms

    private static func ichidanForm(kana: String, form: ConjugationForm) -> String? {
        guard kana.hasSuffix("る") else { return nil }
        let stem = String(kana.dropLast())
        switch form {
        case .polite:       return stem + "ます"
        case .te:           return stem + "て"
        case .past:         return stem + "た"
        case .negative:     return stem + "ない"
        case .pastNegative: return stem + "なかった"
        case .potential:    return stem + "られる"
        case .volitional:   return stem + "よう"
        }
    }

    private static func godanForm(kana: String, form: ConjugationForm) -> String? {
        guard let last = kana.last else { return nil }
        let stem = String(kana.dropLast())
        switch form {
        case .polite:
            guard let i = iStem[last] else { return nil }
            return stem + String(i) + "ます"
        case .negative:
            guard let a = aStem[last] else { return nil }
            return stem + String(a) + "ない"
        case .pastNegative:
            guard let a = aStem[last] else { return nil }
            return stem + String(a) + "なかった"
        case .potential:
            guard let e = eStem[last] else { return nil }
            return stem + String(e) + "る"
        case .volitional:
            guard let o = oStem[last] else { return nil }
            return stem + String(o) + "う"
        case .te:
            guard let euph = euphonic[last] else { return nil }
            return stem + euph.te
        case .past:
            guard let euph = euphonic[last] else { return nil }
            return stem + euph.ta
        }
    }

    /// `.suru` is the class for standalone する and **suru-NOUN composition**
    /// (noun reading + する: 勉強/べんきょう → べんきょう+します, potential べんきょうできる).
    /// The noun reading is the stem; a kana that already shows する drops it, so both
    /// data shapes — べんきょう and べんきょうする — yield the same paradigm.
    ///
    /// NOT modeled here: a bare suru-VERB (single stem + する, e.g. 察する/さっする, a
    /// `vs-s` verb with pos:["v"] and no noun) whose potential is 〜せる (察せる), NOT
    /// 〜できる. The engine cannot tell べんきょうする (→できる) from さっする (→せる) from
    /// the reading alone, so these are WITHHELD at the data-derivation layer (no `vc`,
    /// §3) and never reach the engine as `.suru`. The class contract is therefore:
    /// `.suru` inputs are always suru-nouns or standalone する — never a bare suru-verb.
    private static func suruForm(kana: String, form: ConjugationForm) -> String? {
        let stem = kana.hasSuffix("する") ? String(kana.dropLast(2)) : kana
        switch form {
        case .polite:       return stem + "します"
        case .te:           return stem + "して"
        case .past:         return stem + "した"
        case .negative:     return stem + "しない"
        case .pastNegative: return stem + "しなかった"
        case .potential:    return stem + "できる"
        case .volitional:   return stem + "しよう"
        }
    }

    /// くる / 来る and compounds (持ってくる→もって+…). Output is kana (きます/こない…).
    private static func kuruForm(kana: String, form: ConjugationForm) -> String? {
        let prefix = kana.hasSuffix("くる") ? String(kana.dropLast(2)) : ""
        switch form {
        case .polite:       return prefix + "きます"
        case .te:           return prefix + "きて"
        case .past:         return prefix + "きた"
        case .negative:     return prefix + "こない"
        case .pastNegative: return prefix + "こなかった"
        case .potential:    return prefix + "こられる"
        case .volitional:   return prefix + "こよう"
        }
    }
}
