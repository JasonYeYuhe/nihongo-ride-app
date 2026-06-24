import Foundation

/// A Japanese verb's conjugation class. Raw values match the `vc` field the B0/B1
/// enrichment writes into vocab JSON and `VocabEntry.verbClass` (PLAN-V1.5 §B1),
/// so the same string is the single source of truth across the pipeline.
///
/// `v5aru` keigo verbs (くださる/いらっしゃる/なさる/おっしゃる/ござる) are stored as
/// `godanR` in data; their one irregular form (polite stem り→い) is handled by the
/// engine's lemma-exception table, not a separate class.
public enum VerbClass: String, Codable, Sendable, CaseIterable, Equatable {
    case ichidan                       // 一段 (る-verb): 食べる/見る
    case godanU = "godan_u"            // 五段 う: 買う
    case godanK = "godan_k"            // 五段 く: 書く
    case godanG = "godan_g"            // 五段 ぐ: 泳ぐ
    case godanS = "godan_s"            // 五段 す: 話す
    case godanT = "godan_t"            // 五段 つ: 待つ
    case godanN = "godan_n"            // 五段 ぬ: 死ぬ
    case godanB = "godan_b"            // 五段 ぶ: 遊ぶ
    case godanM = "godan_m"            // 五段 む: 飲む
    case godanR = "godan_r"            // 五段 る: 帰る (incl. v5aru keigo)
    case suru                          // サ変 する / noun+する (勉強する)
    case kuru                          // カ変 来る/くる

    var isGodan: Bool {
        switch self {
        case .ichidan, .suru, .kuru: return false
        default: return true
        }
    }
}

/// The conjugated forms ConjugationKit produces (the v1.5/1.6 "first batch",
/// PLAN-V1.5 §9.5). Output is always a transient kana string — the learner's
/// typing target — and is NEVER persisted as a `VocabEntry` (red line §8.5).
public enum ConjugationForm: String, Codable, Sendable, CaseIterable, Equatable {
    case polite          // ～ます
    case te              // ～て
    case past            // ～た (plain past)
    case negative        // ～ない (plain negative)
    case pastNegative    // ～なかった
    case potential       // 可能 ～(ら)れる / できる
    case volitional      // 意志 ～(よ)う

    /// Short Japanese label for the form, e.g. "ます形".
    public var japaneseLabel: String {
        switch self {
        case .polite: return "ます形"
        case .te: return "て形"
        case .past: return "た形（過去）"
        case .negative: return "ない形（否定）"
        case .pastNegative: return "なかった形"
        case .potential: return "可能形"
        case .volitional: return "意志形"
        }
    }

    /// Short English label, e.g. "Polite (-masu)".
    public var englishLabel: String {
        switch self {
        case .polite: return "Polite (-masu)"
        case .te: return "Te-form"
        case .past: return "Past (-ta)"
        case .negative: return "Negative (-nai)"
        case .pastNegative: return "Past negative"
        case .potential: return "Potential"
        case .volitional: return "Volitional"
        }
    }

    /// Bilingual label (zh uses the Japanese grammar term + a Chinese gloss).
    public func label(for languageCode: String) -> String {
        switch languageCode {
        case "ja": return japaneseLabel
        case "zh":
            switch self {
            case .polite: return "ます形（敬体）"
            case .te: return "て形"
            case .past: return "た形（过去）"
            case .negative: return "ない形（否定）"
            case .pastNegative: return "なかった形（过去否定）"
            case .potential: return "可能形"
            case .volitional: return "意志形（う/よう）"
            }
        default: return englishLabel
        }
    }
}
