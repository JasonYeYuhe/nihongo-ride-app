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

    /// Replaces a single device's slot wholesale (used when applying a merged
    /// slot pulled from the cloud).
    public mutating func setSlot(_ slot: Slot, for deviceID: String) {
        slots[deviceID] = slot
    }

    /// May this device seed its slot from the local ride journal?
    ///
    /// Only when NO slot exists at all. The obvious guard — "I have no slot of my own
    /// yet" — is wrong, because the journal is not a local-only quantity: a cloud fetch
    /// rebuilds it from the MERGED record set and saves that to disk, so after one sync
    /// it holds the whole fleet's rides. A device that synced before its first ride
    /// therefore satisfied "no slot of mine + journal is non-empty" using data that was
    /// entirely someone else's, and seeded itself with the fleet's lifetime. Slots are
    /// SUMMED, so the total doubled; slots merge by `max`, so it could never come back
    /// down, on any device, ever.
    ///
    /// The presence of ANY slot means this device has already talked to the cloud (or
    /// already ridden), and in both cases the journal can no longer be trusted as a
    /// record of this device alone. An empty slot table is the only state where the
    /// journal is provably local — which is exactly the v1.1→v1.2 upgrader the backfill
    /// was written for.
    public static func shouldBackfill(slots: [String: Slot], localRuns: Int) -> Bool {
        slots.isEmpty && localRuns > 0
    }

    // MARK: Persistence (mirrors ReviewStore / RideJournal)

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> OdometerLog {
        guard let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode(OdometerLog.self, from: data)
        else { return OdometerLog() }
        return log
    }
}
