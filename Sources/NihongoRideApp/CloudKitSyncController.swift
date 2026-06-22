import Foundation
import CloudKit
import ReviewKit
import JournalKit
import SavedWordsKit
import SyncKit

/// Drives iCloud sync of SRS cards, ride history, and the lifetime odometer
/// through a private-database `CKSyncEngine`. The local JSON files remain the
/// system-of-record; this controller pushes local changes up and merges fetched
/// changes down via the **pure, unit-tested `SyncKit` merges** — so there is one
/// merge implementation, exercised both here and in tests.
///
/// v1.2 runs the engine in **manual mode** (`automaticallySync = false`): we
/// fetch/send on launch, on app-active, and after each run. That keeps the
/// capability surface minimal (no push entitlement / background mode). Switching
/// to push-driven automatic sync later only needs `aps-environment` + the
/// remote-notification background mode added back.
///
/// NOTE: this is compile-verified but NOT yet device-verified — real two-device
/// sync needs an iCloud account on two devices and the CloudKit schema deployed
/// to Production (see docs/PLAN-V1.2.md §3.7, the human-verification gate).
@MainActor
final class CloudKitSyncController: NSObject, CKSyncEngineDelegate {
    private weak var model: AppModel?
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "NihongoRide")
    private let stateURL: URL
    private var engine: CKSyncEngine?
    /// Serializes fetch/send so two drivers (launch start + scene-active + a
    /// local change) never call into the engine concurrently. A request that
    /// arrives mid-sync sets `needsResync` and the running pass loops again.
    private var syncing = false
    private var needsResync = false

    /// Last-seen server records, so a re-send reuses the server change tag and
    /// preserves fields unknown to this app version (forward compatibility).
    private var recordCache: [String: CKRecord] = [:]

    private enum RT { static let srs = "SRSCard", ride = "RideRecord", odo = "Odometer", saved = "SavedWords" }
    /// The saved-words deck is one shared record.
    private static let savedDeckKey = "deck"
    private static let containerID = "iCloud.com.jasonye.nihongoride"

    /// Fails when CloudKit can't run (e.g. `swift run` has no entitlement/bundle,
    /// or headless screenshot mode), so the app degrades to local-only.
    init?(model: AppModel) {
        guard Bundle.main.bundleIdentifier != nil, !Screenshotter.isCapturing else { return nil }
        self.model = model
        self.database = CKContainer(identifier: Self.containerID).privateCloudDatabase
        self.stateURL = AppModel.supportFileURL("cksync-state.json")
        super.init()
    }

    // MARK: Lifecycle

    /// - Parameter fullResync: re-enqueue all local records (used when the user
    ///   just turned sync on, since edits made while it was off aren't tracked).
    func start(fullResync: Bool = false) async {
        let saved = loadState()
        var config = CKSyncEngine.Configuration(
            database: database, stateSerialization: saved, delegate: self)
        config.automaticallySync = false
        let engine = CKSyncEngine(config)
        self.engine = engine
        // Ensure our record zone exists (saving an existing zone is a no-op), and
        // on first run / re-enable queue all local records to upload.
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        if saved == nil || fullResync { enqueueAllLocal() }
        await syncNow()
    }

    func stop() {
        engine = nil
        recordCache.removeAll()
    }

    /// Enqueue and push the records that just changed locally.
    func recordLocalChanges(srsIDs: [String], rideRecordIDs: [UUID],
                            odometerChanged: Bool, savedChanged: Bool = false) {
        guard let engine else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        changes += srsIDs.map { .saveRecord(recordID(RT.srs, $0)) }
        changes += rideRecordIDs.map { .saveRecord(recordID(RT.ride, $0.uuidString)) }
        if odometerChanged, let device = model?.deviceID {
            changes.append(.saveRecord(recordID(RT.odo, device)))
        }
        if savedChanged {
            changes.append(.saveRecord(recordID(RT.saved, Self.savedDeckKey)))
        }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        Task { [weak self] in await self?.syncNow() }
    }

    /// Manual fetch+send. Pull before push. Serialized + coalescing: a call that
    /// arrives while a sync is running just flags a re-run, so we never call into
    /// the engine concurrently (CKSyncEngine forbids re-entrant/overlapping calls)
    /// and never lose a queued change. Must NOT be called from a delegate callback.
    func syncNow() async {
        guard let engine else { return }
        if syncing { needsResync = true; return }
        syncing = true
        repeat {
            needsResync = false
            model?.updateSyncStatus(.syncing)
            do {
                try await engine.fetchChanges()
                try await engine.sendChanges()
                model?.updateSyncStatus(.synced)
            } catch {
                report(error)
            }
        } while needsResync
        syncing = false
    }

    private func enqueueAllLocal() {
        guard let engine, let model else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        changes += model.reviewStore.cards.keys.map { .saveRecord(recordID(RT.srs, $0)) }
        changes += model.journal.records.map { .saveRecord(recordID(RT.ride, $0.id.uuidString)) }
        changes += model.odometer.slots.keys.map { .saveRecord(recordID(RT.odo, $0)) }
        if !model.savedWords.isEmpty {
            changes.append(.saveRecord(recordID(RT.saved, Self.savedDeckKey)))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes)

        case .sentRecordZoneChanges(let sent):
            handleSent(sent, syncEngine: syncEngine)

        case .willFetchChanges, .willSendChanges, .willFetchRecordZoneChanges:
            model?.updateSyncStatus(.syncing)

        case .didSendChanges, .didFetchChanges:
            model?.updateSyncStatus(.synced)

        case .fetchedDatabaseChanges, .sentDatabaseChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        // Snapshot the local state up front so the record provider reads value
        // types only (no actor hop inside the closure).
        let cards = model?.reviewStore.cards ?? [:]
        let rides = Dictionary((model?.journal.records ?? []).map { ($0.id.uuidString, $0) },
                               uniquingKeysWith: { a, _ in a })
        let slots = model?.odometer.slots ?? [:]
        let savedIDs = model?.savedWords.ids ?? []
        // Deep-COPY cached records into the snapshot: the record provider runs
        // off the main actor and mutates these via Self.fill, while the main
        // actor concurrently mutates/replaces the originals in applyFetched /
        // handleSent. Sharing the same CKRecord instances across actors is a data
        // race (CKRecord's backing store isn't thread-safe). Copies give the
        // provider private instances; server records flow back via handleSent.
        let cache = recordCache.mapValues { $0.copy() as! CKRecord }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            let name = recordID.recordName
            let (type, key) = Self.parse(name)
            let record = cache[name] ?? CKRecord(recordType: type, recordID: recordID)
            switch type {
            case RT.srs:
                guard let card = cards[key] else { return nil }
                Self.fill(record, from: card)
            case RT.ride:
                guard let ride = rides[key] else { return nil }
                Self.fill(record, from: ride)
            case RT.odo:
                guard let slot = slots[key] else { return nil }
                Self.fill(record, from: slot, deviceID: key)
            case RT.saved:
                Self.fill(record, savedIDs: savedIDs)
            default:
                return nil
            }
            return record
        }
    }

    // MARK: Fetched changes → local merge

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var cards: [SRSCard] = []
        var rides: [RideRecord] = []
        var slots: [String: OdometerLog.Slot] = [:]
        var saved: SavedWordsStore?
        for modification in changes.modifications {
            let record = modification.record
            recordCache[record.recordID.recordName] = record
            switch record.recordType {
            case RT.srs:  if let c = Self.srsCard(from: record) { cards.append(c) }
            case RT.ride: if let r = Self.rideRecord(from: record) { rides.append(r) }
            case RT.odo:
                let (_, device) = Self.parse(record.recordID.recordName)
                if let s = Self.odometerSlot(from: record) { slots[device] = s }
            case RT.saved: saved = Self.savedWords(from: record)
            default: break
            }
        }
        // Deletions are ignored: this app never deletes synced records (history is
        // append-only; SRS cards, odometer slots, and saved words are never removed).
        guard !cards.isEmpty || !rides.isEmpty || !slots.isEmpty || saved != nil else { return }
        model?.applyCloudChanges(cards: cards, records: rides, odometerSlots: slots, savedWords: saved)
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        for saved in sent.savedRecords {
            recordCache[saved.recordID.recordName] = saved
        }
        for failure in sent.failedRecordSaves {
            let error = failure.error
            if error.code == .serverRecordChanged, let serverRecord = error.serverRecord {
                // Cache the server copy (its change tag + any unknown fields), then
                // MERGE it into local via the same SyncKit rules BEFORE re-enqueuing.
                // Without the merge, the re-send would blindly push the local value
                // and could clobber a newer remote lastReviewed (data loss).
                recordCache[serverRecord.recordID.recordName] = serverRecord
                mergeServerRecord(serverRecord)
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(serverRecord.recordID)])
            }
            // Other errors are left for the engine's own retry handling.
        }
    }

    /// Merges a single conflicting server record into the local store so the next
    /// send materializes the merge *winner* (not a stale local value).
    private func mergeServerRecord(_ record: CKRecord) {
        switch record.recordType {
        case RT.srs:
            if let card = Self.srsCard(from: record) {
                model?.applyCloudChanges(cards: [card], records: [], odometerSlots: [:])
            }
        case RT.ride:
            if let ride = Self.rideRecord(from: record) {
                model?.applyCloudChanges(cards: [], records: [ride], odometerSlots: [:])
            }
        case RT.odo:
            let (_, device) = Self.parse(record.recordID.recordName)
            if let slot = Self.odometerSlot(from: record) {
                model?.applyCloudChanges(cards: [], records: [], odometerSlots: [device: slot])
            }
        case RT.saved:
            model?.applyCloudChanges(savedWords: Self.savedWords(from: record))
        default:
            break
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            // New account: queue our local state. Sent by the syncNow already in
            // flight (this event arrives during its fetch) or the next one — NOT
            // driven from here: calling the engine from inside a delegate callback
            // is what CKSyncEngine forbids.
            enqueueAllLocal()
            model?.updateSyncStatus(.waiting)
        case .signOut:
            // Keep local data (it's the system-of-record); just stop syncing and
            // drop sync state so we never write this data into another account.
            clearState()
            model?.updateSyncStatus(.noAccount)
        case .switchAccounts:
            clearState()
            recordCache.removeAll()
            enqueueAllLocal()
            model?.updateSyncStatus(.waiting)
        @unknown default:
            break
        }
    }

    // MARK: State persistence

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ serialization: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(serialization) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func clearState() {
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func report(_ error: Error) {
        model?.updateSyncStatus(Self.status(for: error))
    }

    private nonisolated static func status(for error: Error) -> AppModel.SyncStatus {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return .noAccount
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return .waiting   // transient — retried on the next launch / app-active
            default:
                break
            }
        }
        return .error(error.localizedDescription)
    }

    // MARK: Record id helpers

    private func recordID(_ type: String, _ key: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(type):\(key)", zoneID: zoneID)
    }

    /// Splits "Type:key" — key may itself contain ':' (UUIDs don't, ids don't).
    private nonisolated static func parse(_ recordName: String) -> (type: String, key: String) {
        guard let sep = recordName.firstIndex(of: ":") else { return ("", recordName) }
        return (String(recordName[..<sep]), String(recordName[recordName.index(after: sep)...]))
    }

    // MARK: CKRecord <-> model field mapping

    private nonisolated static func fill(_ record: CKRecord, from card: SRSCard) {
        record["vocabID"] = card.id
        record["easeFactor"] = card.easeFactor
        record["interval"] = card.interval
        record["repetitions"] = card.repetitions
        record["dueDate"] = card.dueDate
        record["lapses"] = card.lapses
        record["lastReviewed"] = card.lastReviewed
        record["totalReviews"] = card.totalReviews
        record["totalMistakes"] = card.totalMistakes
    }

    private nonisolated static func srsCard(from record: CKRecord) -> SRSCard? {
        guard let id = record["vocabID"] as? String else { return nil }
        var card = SRSCard(id: id)
        card.easeFactor = record["easeFactor"] as? Double ?? card.easeFactor
        card.interval = record["interval"] as? Int ?? card.interval
        card.repetitions = record["repetitions"] as? Int ?? card.repetitions
        card.dueDate = record["dueDate"] as? Date ?? card.dueDate
        card.lapses = record["lapses"] as? Int ?? card.lapses
        card.lastReviewed = record["lastReviewed"] as? Date
        card.totalReviews = record["totalReviews"] as? Int ?? card.totalReviews
        card.totalMistakes = record["totalMistakes"] as? Int ?? card.totalMistakes
        return card
    }

    private nonisolated static func fill(_ record: CKRecord, from ride: RideRecord) {
        record["uuid"] = ride.id.uuidString
        record["date"] = ride.date
        record["mode"] = ride.mode
        record["level"] = ride.level
        record["score"] = ride.score
        record["wpm"] = ride.wpm
        record["accuracy"] = ride.accuracy
        record["wordsCompleted"] = ride.wordsCompleted
        record["lapsed"] = ride.lapsed
        record["distanceMeters"] = ride.distanceMeters
        record["duration"] = ride.duration
    }

    private nonisolated static func rideRecord(from record: CKRecord) -> RideRecord? {
        guard let uuidString = record["uuid"] as? String, let id = UUID(uuidString: uuidString),
              let date = record["date"] as? Date,
              let mode = record["mode"] as? String,
              let level = record["level"] as? String
        else { return nil }
        return RideRecord(
            id: id, date: date, mode: mode, level: level,
            score: record["score"] as? Int ?? 0,
            wpm: record["wpm"] as? Double ?? 0,
            accuracy: record["accuracy"] as? Double ?? 0,
            wordsCompleted: record["wordsCompleted"] as? Int ?? 0,
            lapsed: record["lapsed"] as? Int ?? 0,
            distanceMeters: record["distanceMeters"] as? Double ?? 0,
            duration: record["duration"] as? Double ?? 0)
    }

    private nonisolated static func fill(_ record: CKRecord, from slot: OdometerLog.Slot, deviceID: String) {
        record["deviceID"] = deviceID
        record["words"] = slot.words
        record["distanceMeters"] = slot.distanceMeters
        record["runs"] = slot.runs
    }

    private nonisolated static func odometerSlot(from record: CKRecord) -> OdometerLog.Slot? {
        OdometerLog.Slot(
            words: record["words"] as? Int ?? 0,
            distanceMeters: record["distanceMeters"] as? Double ?? 0,
            runs: record["runs"] as? Int ?? 0)
    }

    private nonisolated static func fill(_ record: CKRecord, savedIDs: [String]) {
        record["ids"] = savedIDs
    }

    private nonisolated static func savedWords(from record: CKRecord) -> SavedWordsStore {
        SavedWordsStore(ids: record["ids"] as? [String] ?? [])
    }
}
