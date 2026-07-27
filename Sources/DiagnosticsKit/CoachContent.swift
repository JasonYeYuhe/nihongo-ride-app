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
                    rule: "は、へ、を 作助词时读作 wa、e、o,但**打字要按写法**:ha、he、wo。"
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

    /// Which already-known words would exercise this pattern.
    ///
    /// Candidates come from the caller (the app passes words the learner has already reviewed)
    /// for two reasons: DiagnosticsKit stays free of VocabKit, and an unfamiliar word adds a
    /// second reason to fail on top of the one being remediated — the drill is supposed to
    /// isolate the keyboard problem, not test vocabulary at the same time.
    public static func drillCandidates(for pattern: TypingPattern,
                                       from candidates: [(id: String, kana: String)],
                                       limit: Int = 12) -> [String] {
        let matches: (String) -> Bool
        switch pattern {
        case .particleSpelling: matches = { $0.contains(where: { "はへを".contains($0) }) }
        case .sokuon:           matches = { $0.contains("っ") }
        case .smallYa:          matches = { $0.contains(where: { "ゃゅょ".contains($0) }) }
        case .hepburnM:         matches = { kana in
            // ん immediately before a b/p mora — the only place the m habit bites.
            let chars = Array(kana)
            return chars.indices.dropLast().contains { i in
                chars[i] == "ん" && "ばびぶべぼぱぴぷぺぽ".contains(chars[i + 1])
            }
        }
        case .unknown:          return []
        }
        return candidates.filter { matches($0.kana) }.prefix(limit).map(\.id)
    }
}
