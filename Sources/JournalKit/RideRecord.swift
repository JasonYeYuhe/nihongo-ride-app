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

    // Tolerant decoder — see ReviewKit.SRSCard. A journal is append-only history: dropping
    // every ride because one row lost a field would destroy the streak, the lifetime totals
    // and the charts at once. Only `date` is required (a ride with no date cannot be placed
    // on any timeline); everything else degrades to a zero that reads as "not recorded".
    private enum CodingKeys: String, CodingKey {
        case id, date, mode, level, score, wpm, accuracy
        case wordsCompleted, lapsed, distanceMeters, duration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "journey"
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? "all"
        score = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        wpm = try c.decodeIfPresent(Double.self, forKey: .wpm) ?? 0
        accuracy = try c.decodeIfPresent(Double.self, forKey: .accuracy) ?? 0
        wordsCompleted = try c.decodeIfPresent(Int.self, forKey: .wordsCompleted) ?? 0
        lapsed = try c.decodeIfPresent(Int.self, forKey: .lapsed) ?? 0
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
    }

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
