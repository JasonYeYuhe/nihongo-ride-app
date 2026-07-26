import Foundation

/// One refused keystroke, with enough context to explain it back to the learner.
///
/// Until v1.15 the app kept none of this. `GameSession.input(_:)` answered a rejection with
/// `currentMistakes += 1; combo = 0` and dropped the character; the matcher leaves its state
/// untouched on rejection by design; the SRS card stores totals. So the app knew *that* a
/// learner made four mistakes on a word and nothing whatsoever about *what* they typed — which
/// makes "you typed `wa`; the は here is written `ha`" impossible to say, however obvious it is
/// from the keystroke.
///
/// Everything here is already available at the moment of rejection. The matcher exposes the
/// accepted romaji, the keys that would have worked, and how many kana are committed; this
/// type is the record nobody was writing.
///
/// ## Privacy
/// A keystroke trace is the most sensitive thing this app could hold — it is, literally, a
/// keylog scoped to a practice session. So it lives **in memory, for the current run only**.
/// It is never written to disk, never enters the SRS card, and never goes near CloudKit. When
/// the run ends the coach reads it, and when the session is released it is gone.
public struct MistakeEvent: Equatable, Sendable {
    /// The kana the learner was typing when this happened.
    public let targetKana: String
    /// The vocabulary row, when the target came from one. Passages have no id.
    public let entryID: String?
    /// The romaji accepted before the refused key — the left-hand side of the replay.
    public let acceptedRomaji: String
    /// The key that was refused.
    public let rejected: Character
    /// The keys that would have been accepted instead. Small; usually one to four.
    public let expectedNext: Set<Character>
    /// How many kana of the target were already committed. With `targetKana` this locates
    /// the mistake at an exact character, which is what the learner needs to see.
    public let kanaIndex: Int
    /// Position within the run, so repeated attempts at the same spot can be told apart
    /// from the same mistake recurring on different words.
    public let order: Int

    public init(targetKana: String, entryID: String?, acceptedRomaji: String,
                rejected: Character, expectedNext: Set<Character>,
                kanaIndex: Int, order: Int) {
        self.targetKana = targetKana
        self.entryID = entryID
        self.acceptedRomaji = acceptedRomaji
        self.rejected = rejected
        self.expectedNext = expectedNext
        self.kanaIndex = kanaIndex
        self.order = order
    }

    /// The kana the learner was standing on when the key was refused — the character to point
    /// at. Nil if the index is past the end, which a rejection should never produce but the
    /// caller should not have to assume.
    public var kanaAtMistake: Character? {
        let kana = Array(targetKana)
        return kanaIndex < kana.count ? kana[kanaIndex] : nil
    }
}

/// A bounded, in-memory log of refused keystrokes for one run.
///
/// Bounded because a determined learner can generate thousands of rejections in a minute by
/// holding a key down, and none of the coaching value is in the tail: the cap keeps the
/// EARLIEST events, since the first time a learner hits a wall is more diagnostic than the
/// two hundredth.
public struct MistakeTrace: Equatable, Sendable {
    public static let capacity = 200

    public private(set) var events: [MistakeEvent] = []
    /// Refusals beyond `capacity`, so the coach can say the trace is partial rather than
    /// quietly reasoning about a truncated sample.
    public private(set) var dropped = 0

    public init() {}

    public mutating func record(_ event: MistakeEvent) {
        guard events.count < Self.capacity else { dropped += 1; return }
        events.append(event)
    }

    public var isEmpty: Bool { events.isEmpty }
    public var count: Int { events.count }
}
