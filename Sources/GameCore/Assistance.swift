import Foundation

/// The one assistance policy (v1.16 §A).
///
/// The app used to have two hint systems that did not know about each other: an always-on
/// romaji display (`showRomajiHint`), and `revealHint()` — a reveal that charges the honest
/// price (usedHint, minimal score, SRS lapse), fully scored and fully tested, and reachable
/// from **nowhere**: no view ever called it. Both reviewers independently rejected the plan's
/// first draft (auto-showing a correction mid-word) for overriding the learner's explicit
/// blind-practice choice and for handing out answers without the lapse; this is what replaced
/// it. The answer is never injected, only OFFERED; taking it costs exactly what the reveal
/// path always charged; and off means off.
public enum AssistanceMode: String, Codable, Sendable, CaseIterable {
    /// Full romaji and next-key hints, always visible. The pre-v1.16 hints-on behaviour.
    case always
    /// Nothing shown. After repeated distinct refusals at the SAME matcher state, a reveal
    /// control is offered. Using it goes through the existing lapse-charging path.
    case afterStruggle = "struggle"
    /// Nothing, ever. The learner chose blind practice and is left alone.
    case off
}

/// Decides when a learner is genuinely stuck, as opposed to slipping or holding a key.
///
/// "Second refusal at the same kana" — the first draft's trigger — was rejected as too vague
/// to implement, and the review forced the definitions this type encodes:
///
/// - **Same state** means (word index, kana index, accepted romaji prefix). Two refusals on
///   the same CHARACTER in different words are unrelated events; two at the same prefix of
///   the same word are one learner against one wall.
/// - **Distinct attempts, not repeats.** A held key autorepeats the same character at
///   ~15 keys/s; the trace layer already documents hundreds of refusals arriving that way.
///   A repeat of the same character within `repeatGap` counts once.
///
/// Pure value type, clock injected per call — testable without waiting.
public struct StruggleDetector: Equatable, Sendable {

    public struct StateKey: Equatable, Sendable {
        public let wordIndex: Int
        public let kanaIndex: Int
        public let acceptedRomaji: String

        public init(wordIndex: Int, kanaIndex: Int, acceptedRomaji: String) {
            self.wordIndex = wordIndex
            self.kanaIndex = kanaIndex
            self.acceptedRomaji = acceptedRomaji
        }
    }

    /// Faster than this between identical characters is key autorepeat, not a decision.
    ///
    /// A hold is not one clean stream: macOS waits an INITIAL delay (system default 375 ms,
    /// user-configurable and only ever longer on this Mac's settings pane) before repeating,
    /// then repeats fast (default 90 ms). So the first repeat of a hold lands ABOVE this gap
    /// and is counted, while every later one is not — a held key is worth at most **2**
    /// attempts, whatever the user's key-repeat settings, because only the initial delay can
    /// ever exceed the gap. That bound is what makes `struggleOfferThreshold = 3` safe, and
    /// `heldKeyNeverReachesThreshold` pins it: lowering the threshold to 2 would make a
    /// single stuck key pop the offer.
    public static let repeatGap: TimeInterval = 0.35

    private var key: StateKey?
    public private(set) var attempts = 0
    private var lastCharacter: Character?
    private var lastAt: Date?

    public init() {}

    /// Records a refusal; returns the distinct-attempt count at this state.
    @discardableResult
    public mutating func record(_ character: Character, at state: StateKey, time: Date) -> Int {
        if key != state {
            key = state
            attempts = 0
            lastCharacter = nil
            lastAt = nil
        }
        let isAutorepeat = character == lastCharacter
            && lastAt.map { time.timeIntervalSince($0) < Self.repeatGap } ?? false
        if !isAutorepeat { attempts += 1 }
        lastCharacter = character
        lastAt = time
        return attempts
    }

    /// Accepted progress, a word change, a pause, or backgrounding: the struggle signal is
    /// stale and starts over.
    public mutating func reset() {
        key = nil
        attempts = 0
        lastCharacter = nil
        lastAt = nil
    }
}
