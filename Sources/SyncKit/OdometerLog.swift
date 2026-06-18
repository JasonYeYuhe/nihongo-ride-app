import Foundation

/// Lifetime odometer as a grow-only counter (G-Counter CRDT).
///
/// Each device owns exactly one slot, keyed by its install id, and only ever
/// mutates its own slot — so the odometer never has a write conflict. The global
/// lifetime totals are the **sum of all slots**.
///
/// This is the fix for the merge bug a single shared counter would have: if two
/// devices each ride offline (+50 and +20), summing slots yields +70, whereas a
/// naive `max()` over one shared counter would keep only +50 and silently drop
/// the other device's progress. A fresh second device also reconstructs the full
/// lifetime correctly, because each slot is that device's own running total and
/// is never affected by history trimming.
public struct OdometerLog: Codable, Equatable, Sendable {
    public struct Slot: Codable, Equatable, Sendable {
        public var words: Int
        public var distanceMeters: Double
        public var runs: Int

        public init(words: Int = 0, distanceMeters: Double = 0, runs: Int = 0) {
            self.words = words
            self.distanceMeters = distanceMeters
            self.runs = runs
        }
    }

    /// deviceID → that device's lifetime contribution.
    public private(set) var slots: [String: Slot]

    public init(slots: [String: Slot] = [:]) {
        self.slots = slots
    }

    public var totalWords: Int { slots.values.reduce(0) { $0 + $1.words } }
    public var totalDistanceMeters: Double { slots.values.reduce(0) { $0 + $1.distanceMeters } }
    public var totalRuns: Int { slots.values.reduce(0) { $0 + $1.runs } }

    /// Adds one (or more) runs' contribution to *this device's* slot.
    public mutating func record(deviceID: String, words: Int, distanceMeters: Double, runs: Int = 1) {
        var slot = slots[deviceID] ?? Slot()
        slot.words += words
        slot.distanceMeters += distanceMeters
        slot.runs += runs
        slots[deviceID] = slot
    }
}
