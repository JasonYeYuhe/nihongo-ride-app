import Foundation
import RomajiKana

/// What the learner is shown for a diagnosed pattern: the rule, and their own mistake
/// replayed at the exact character.
///
/// The text is AUTHORED, not generated. That is the whole point of the v1.15 design: this is
/// instructional truth, it has to be right in both languages, and an on-device model that
/// advised practising kanji calligraphy for a romaji problem is not going to write it. If the
/// optional phrasing layer ever lands, it sits underneath this — labeled, and additional.
public struct CoachAdvice: Equatable, Sendable {
    /// Short name of the pattern, e.g. "Words that aren't spelled how they sound".
    public let title: String
    /// One or two sentences: what the rule is and how to type it. Concrete, no jargon.
    public let rule: String
    /// Whether repetition helps here. Reading confusions want words; keyboard mechanics want
    /// the rule and one correct repetition, not a deck.
    public let drillHelps: Bool
}

/// A learner's own refused keystroke, prepared for display.
///
/// The value of this over "you made 4 mistakes" is that it points at ONE character and shows
/// both sides: what they typed, and what that same position wanted.
public struct MistakeReplay: Equatable, Sendable {
    /// The word, as kana.
    public let target: String
    /// Index of the kana the learner was standing on.
    public let index: Int
    /// The romaji accepted before the refusal.
    public let typedPrefix: String
    /// The key that was refused.
    public let rejected: Character
    /// The keys that would have worked, sorted so the display is stable.
    public let accepted: [Character]

    public init?(_ event: MistakeEvent) {
        guard event.kanaAtMistake != nil else { return nil }
        target = event.targetKana
        index = event.kanaIndex
        typedPrefix = event.acceptedRomaji
        rejected = event.rejected
        accepted = event.expectedNext.sorted()
    }

    /// The kana being typed when the key was refused.
    public var kana: Character { Array(target)[index] }
}

public enum CoachContent {

    /// Authored advice per pattern, in the app's two languages.
    ///
    /// `unknown` deliberately has none: there is nothing honest to say about a keystroke the
    /// app cannot explain, and inventing encouragement to fill the space is what the
    /// on-device model did when it answered "Keep practicing! You're getting the hang of it."
    public static func advice(for pattern: TypingPattern, zh: Bool) -> CoachAdvice? {
        switch pattern {
        case .particleSpelling:
            return zh
                ? CoachAdvice(
                    title: "有些假名不按读音拼",
                    // No Markdown. `Text(_:)` given a String variable takes the StringProtocol
                    // overload, which does not parse it — only a string LITERAL becomes a
                    // LocalizedStringKey — so the asterisks rendered verbatim on two screens.
                    // The English sibling below already carries the emphasis as capitalised
                    // WRITTEN, with no markup; this now matches it. (v1.32.)
                    rule: "は、へ、を 作助词时读作 wa、e、o,但打字要按写法:ha、he、wo。"
                        + "「こんにちは」要打 konnichiha。",
                    drillHelps: true)
                : CoachAdvice(
                    title: "Some kana aren't spelled how they sound",
                    rule: "As particles, は へ を are pronounced wa, e, o — but you type them "
                        + "as they're WRITTEN: ha, he, wo. こんにちは is konnichiha.",
                    drillHelps: true)
        case .sokuon:
            return zh
                ? CoachAdvice(
                    title: "小さい っ:辅音要双写",
                    rule: "っ 不单独打,而是把下一个辅音写两遍:いって 是 itte,きって 是 kitte。",
                    drillHelps: true)
                : CoachAdvice(
                    title: "The small っ doubles the next consonant",
                    rule: "You don't type っ on its own — you double the consonant that follows "
                        + "it: いって is itte, きって is kitte.",
                    drillHelps: true)
        case .smallYa:
            return zh
                ? CoachAdvice(
                    title: "きゃ 是一个音,不是两个",
                    rule: "きゃ 直接打 kya——中间没有 i。しょ 是 sho,ちゅ 是 chu。"
                        + "打成 kiya 会得到きや(两个假名)。",
                    drillHelps: false)
                : CoachAdvice(
                    title: "きゃ is one sound, not two",
                    rule: "Type きゃ as kya — there's no i in the middle. しょ is sho, ちゅ is chu. "
                        + "Typing kiya gives you きや, which is two separate kana.",
                    drillHelps: false)
        case .hepburnM:
            return zh
                ? CoachAdvice(
                    title: "ん 永远打 n,即使后面是 b/p",
                    rule: "罗马字转写里 しんぶん 常写成 shimbun,但输入法只认 n:打 shinbun。",
                    drillHelps: false)
                : CoachAdvice(
                    title: "ん is always n, even before b and p",
                    rule: "Romanisations often write しんぶん as shimbun, but an IME only takes n: "
                        + "type shinbun.",
                    drillHelps: false)
        case .unknown:
            return nil
        }
    }

    /// Where a pattern's drill material has to come from.
    public enum DrillSource: Equatable, Sendable {
        case words
        case passages
    }

    /// Particle spelling is the one pattern single words cannot drill.
    ///
    /// は is only a particle inside a SENTENCE. A vocabulary entry whose reading happens to
    /// contain は — はな (flower), はし (bridge) — is typed `hana`, `hashi` and works first
    /// time, so a word drill for this pattern practises nothing and quietly reports success.
    /// The corpus has 233 passages and 152 of them contain particle は, which is the material
    /// that actually exercises the rule.
    public static func drillSource(for pattern: TypingPattern) -> DrillSource {
        pattern == .particleSpelling ? .passages : .words
    }

    /// Whether a kana string exercises `pattern` — one definition, used by both the word path
    /// and the passage path so they cannot drift.
    public static func exercises(_ kana: String, pattern: TypingPattern) -> Bool {
        switch pattern {
        case .particleSpelling:
            // Inside a sentence, a bare は/へ/を is overwhelmingly the particle. A false
            // positive costs one extra line of practice; it cannot teach anything wrong.
            return kana.contains(where: { "はへを".contains($0) })
        case .sokuon:
            return kana.contains("っ")
        case .smallYa:
            return kana.contains(where: { "ゃゅょ".contains($0) })
        case .hepburnM:
            // ん immediately before a b/p mora — the only place the m habit bites.
            let chars = Array(kana)
            return chars.indices.dropLast().contains { i in
                chars[i] == "ん" && "ばびぶべぼぱぴぷぺぽ".contains(chars[i + 1])
            }
        case .unknown:
            return false
        }
    }

    /// Which already-known words would exercise this pattern.
    ///
    /// Candidates come from the caller (the app passes words the learner has already reviewed)
    /// for two reasons: DiagnosticsKit stays free of VocabKit, and an unfamiliar word adds a
    /// second reason to fail on top of the one being remediated — the drill is supposed to
    /// isolate the keyboard problem, not test vocabulary at the same time.
    ///
    /// Returns nothing for a pattern whose material is sentences; see `drillSource`.
    public static func drillCandidates(for pattern: TypingPattern,
                                       from candidates: [(id: String, kana: String)],
                                       limit: Int = 12) -> [String] {
        guard drillSource(for: pattern) == .words else { return [] }
        return candidates.filter { exercises($0.kana, pattern: pattern) }.prefix(limit).map(\.id)
    }
}
