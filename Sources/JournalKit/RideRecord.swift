import Foundation

/// One finished run, as remembered by the ride journal. A flat, stable,
/// Codable shape — append-only history, so fields are primitives (no
/// references into VocabKit) and the schema must stay backward-compatible.
public struct RideRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// When the run ended.
    public var date: Date
    /// `GameMode.rawValue` ("journey" / "timeAttack" / "practice").
    public var mode: String
    /// JLPT level label ("N5"…"N1"), "all" for mixed, or a passage length
    /// ("easy"/"med"/"hard") for passage practice.
    public var level: String
    public var score: Int
    /// Words-per-minute over the whole run (correct keystrokes ÷ 5 ÷ minutes);
    /// 0 when the run was too short to be meaningful.
    public var wpm: Double
    /// 0…1 keystroke accuracy.
    public var accuracy: Double
    public var wordsCompleted: Int
    /// Distinct words that lapsed (skipped / hinted / many typos).
    public var lapsed: Int
    public var distanceMeters: Double
    /// Wall-clock seconds from start to finish.
    public var duration: TimeInterval

    public init(
        id: UUID = UUID(),
        date: Date,
        mode: String,
        level: String,
        score: Int,
        wpm: Double,
        accuracy: Double,
        wordsCompleted: Int,
        lapsed: Int,
        distanceMeters: Double,
        duration: TimeInterval
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.level = level
        self.score = score
        self.wpm = wpm
        self.accuracy = accuracy
        self.wordsCompleted = wordsCompleted
        self.lapsed = lapsed
        self.distanceMeters = distanceMeters
        self.duration = duration
    }
}
