import Foundation
import CloudKit
import ReviewKit
import JournalKit
import SyncKit
import WordListsKit
import ConjugationReviewKit

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
    /// A non-transient per-record save failure seen during the CURRENT sync pass (set by
    /// handleSent, consumed by syncNow). Setting the status inside the delegate would be
    /// clobbered by the pass's closing `.synced`, so the pass reports it at the end instead.
    private var passFailure: AppModel.SyncStatus?
    /// Set by stop(): an in-flight pass checks it to stand down (no further rounds, no status
    /// writes). Cleared by start() — a stale `true` would make a re-enabled sync a silent no-op.
    private var stopped = false

    /// Last-seen server records, so a re-send reuses the server change tag and
    /// preserves fields unknown to this app version (forward compatibility).
    private var recordCache: [String: CKRecord] = [:]

    private enum RT { static let srs = "SRSCard", ride = "RideRecord", odo = "Odometer", saved = "SavedWords", list = "WordList", conjSRS = "ConjugationSRSCard" }
    /// The legacy v1.4 saved-words deck is one shared record (key "deck"). v1.5
    /// reads/writes it only during the one-time convergence (see AppModel).
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
        // Reset the stop signal and any stale failure from a previous life — a leftover
        // `stopped == true` would make a re-enabled sync a silent no-op, and a stale
        // passFailure would report the OLD session's error on this session's first pass.
        stopped = false
        passFailure = nil
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
        let didBackfill = backfillConjugationSRSIfNeeded(engine)
        await syncNow()
        // Mark the one-time back-fill done only AFTER the pass, so a crash between the enqueue
        // and the engine persisting its state re-runs it next launch instead of losing it
        // (re-enqueuing the same record ids is idempotent).
        if didBackfill { model?.markConjSRSBackfilled() }
    }

    /// Turns sync off. A pass may be suspended inside `await engine.fetchChanges()` right now —
    /// it holds its own strong binding, so nilling `engine` can't dealloc it mid-await. What
    /// `stopped` adds is that the in-flight pass STANDS DOWN: it won't start another round and
    /// won't report a status for a sync the user just switched off (v1.10 §B1).
    func stop() {
        stopped = true
        engine = nil
        recordCache.removeAll()
    }

    /// Enqueue and push the records that just changed locally.
    func recordLocalChanges(srsIDs: [String] = [], rideRecordIDs: [UUID] = [],
                            odometerChanged: Bool = false, listIDs: [String] = [],
                            conjugationSRSIDs: [String] = []) {
        guard let engine else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        changes += srsIDs.map { .saveRecord(recordID(RT.srs, $0)) }
        changes += rideRecordIDs.map { .saveRecord(recordID(RT.ride, $0.uuidString)) }
        if odometerChanged, let device = model?.deviceID {
            changes.append(.saveRecord(recordID(RT.odo, device)))
        }
        changes += listIDs.map { .saveRecord(recordID(RT.list, $0)) }
        // Conjugation SRS: gated OFF for v1.8 (conjSRSSyncAvailable=false) so no
        // ConjugationSRSCard is ever written — the Production schema stays un-JIT'd
        // until device gate E flips it on (PLAN-V1.8 §4). Callers also gate, but guard
        // here too so a stray call can't leak a record.
        if AppModel.conjSRSSyncAvailable {
            changes += conjugationSRSIDs.map { .saveRecord(recordID(RT.conjSRS, $0)) }
        }
        // Keep the legacy v1.4 deck record mirrored to the default list so v1.4
        // peers track the user's ★ edits (the deck is folded back on fetch).
        if listIDs.contains(WordList.defaultID) {
            changes.append(.saveRecord(recordID(RT.saved, Self.savedDeckKey)))
        }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        scheduleSync()
    }

    /// Manual fetch+send. Pull before push. Serialized + coalescing: a call that
    /// arrives while a sync is running just flags a re-run, so we never call into
    /// the engine concurrently (CKSyncEngine forbids re-entrant/overlapping calls)
    /// and never lose a queued change. Must NOT be called from a delegate callback.
    func syncNow() async {
        if syncing { needsResync = true; return }
        syncing = true
        // Every exit path must clear this — an early `return` that skipped it would wedge
        // syncing==true forever and silently kill all future syncs (v1.10 §B1).
        defer { syncing = false }
        repeat {
            needsResync = false
            passFailure = nil
            // Re-read the engine at the TOP of each iteration and hold ONE local strong
            // binding for the whole iteration: the binding keeps the engine alive across this
            // iteration's awaits (stop() nils `self.engine`, and a suspended pass must not
            // dealloc it mid-await), while re-reading each round means a stop→start hands the
            // next round the NEW engine instead of driving the old one against the same
            // cksync-state.json (two engines, one state file). (v1.10 §B1.)
            guard !stopped, let engine = self.engine else { return }
            model?.updateSyncStatus(.syncing)
            do {
                try await engine.fetchChanges()
                // stop() can land while we are suspended INSIDE fetchChanges. v1.10 only
                // checked after the send, so the upload still went out: the user switched
                // sync off and their records were pushed to iCloud anyway. The local `engine`
                // binding deliberately keeps the engine alive across the await, so nothing
                // else was going to prevent it. (v1.12 §C.)
                guard !stopped else { return }
                try await engine.sendChanges()
                // stop() landed while we were awaiting: the user turned sync OFF, so don't
                // report a status for it — reporting `.synced` here is the "sync layer lies"
                // bug this phase exists to kill.
                guard !stopped else { return }
                // A per-record save failure surfaced by handleSent must NOT be clobbered by a
                // blanket .synced — that would re-hide exactly the failures §A3 exists to show
                // (the status is set here, at the end of the pass, not inside the delegate).
                model?.updateSyncStatus(passFailure ?? .synced)
            } catch {
                guard !stopped else { return }
                report(error)
            }
        } while needsResync
    }

    /// Kick a sync from a context where we must NOT await the engine directly —
    /// e.g. inside a delegate callback (handleAccountChange). The fresh Task hops
    /// out of the callback before touching the engine, and syncNow()'s in-flight
    /// guard coalesces it into any pass already running (setting needsResync so
    /// that pass re-runs) — so queued records are always sent, never stranded,
    /// and the engine is never driven re-entrantly from the delegate.
    private func scheduleSync() {
        Task { [weak self] in await self?.syncNow() }
    }

    /// One-time back-fill of conjugation SRS cards (v1.9 §A1). `enqueueAllLocal` only runs on
    /// a nil saved state (first ever sync) or a manual full-resync — so an EXISTING sync user
    /// (non-nil state) who accumulated conjugation cards under v1.8 (while the feature was
    /// gated off) would never upload them when v1.8.1 flipped `conjSRSSyncAvailable` on; only
    /// newly-drilled cards would sync. Push the whole conjugation store once, gated by a
    /// persisted marker on the model so it never repeats. Enqueue-only (state.add) — the send
    /// happens through the caller's `syncNow()`; no engine is driven here.
    /// Returns true when the back-fill was enqueued this launch — the CALLER marks it done
    /// after the sync pass (see start()), not here, so a crash can't lose it.
    private func backfillConjugationSRSIfNeeded(_ engine: CKSyncEngine) -> Bool {
        guard AppModel.conjSRSSyncAvailable, let model, !model.conjSRSBackfilled else { return false }
        let changes = model.conjugationReviewStore.cards.keys.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(RT.conjSRS, $0))
        }
        if !changes.isEmpty { engine.state.add(pendingRecordZoneChanges: changes) }
        return true
    }

    private func enqueueAllLocal() {
        guard let engine, let model else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        changes += model.reviewStore.cards.keys.map { .saveRecord(recordID(RT.srs, $0)) }
        changes += model.journal.records.map { .saveRecord(recordID(RT.ride, $0.id.uuidString)) }
        // ONLY our own slot. OdometerLog's G-Counter contract is "a device only ever mutates
        // its own slot, so the odometer never has a write conflict" — but enqueuing every
        // slot we happen to know about broke exactly that: we'd re-upload each peer's slot,
        // and any peer that had since moved on hands us a guaranteed serverRecordChanged
        // conflict round-trip per full resync, for a value we can only ever echo back. (v1.10 §B3.)
        changes.append(.saveRecord(recordID(RT.odo, model.deviceID)))
        // Every list (incl. tombstoned, so deletions propagate).
        changes += model.allWordListIDs.map { .saveRecord(recordID(RT.list, $0)) }
        // Legacy-deck mirror (= default list ids) so still-v1.4 peers stay in sync.
        changes.append(.saveRecord(recordID(RT.saved, Self.savedDeckKey)))
        // Conjugation SRS cards — gated OFF for v1.8 (see recordLocalChanges).
        if AppModel.conjSRSSyncAvailable {
            changes += model.conjugationReviewStore.cards.keys.map { .saveRecord(recordID(RT.conjSRS, $0)) }
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
            // Same reason as the status cases below: an in-flight pass can deliver these
            // after the user switched sync off, and merging them would keep mutating local
            // stores from iCloud for a feature they just disabled. The records stay in the
            // cloud, so re-enabling sync picks them up again. (v1.12 §C.)
            guard !stopped else { break }
            applyFetched(changes)

        case .sentRecordZoneChanges(let sent):
            handleSent(sent, syncEngine: syncEngine)

        // These fire from an in-flight pass that may outlive stop(). Without the guard they
        // overwrite the `.off` that syncEnabledChanged just set, so the Settings row reads
        // "Synced" while the toggle sits off and nothing ever corrects it. (v1.12 §C.)
        case .willFetchChanges, .willSendChanges, .willFetchRecordZoneChanges:
            guard !stopped else { break }
            model?.updateSyncStatus(.syncing)

        case .didSendChanges, .didFetchChanges:
            guard !stopped else { break }
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
        // WordList records, snapshotted by value (Sendable). The legacy deck
        // record (written only during convergence) carries the default list's ids.
        let lists = model?.wordListsByID ?? [:]
        let defaultIDs = lists[WordList.defaultID]?.ids ?? []
        // Conjugation SRS cards, snapshotted by value (Sendable value type).
        let conjCards = model?.conjugationReviewStore.cards ?? [:]
        // Deep-COPY cached records into the snapshot: the record provider runs
        // off the main actor and mutates these via Self.fill, while the main
        // actor concurrently mutates/replaces the originals in applyFetched /
        // handleSent. Sharing the same CKRecord instances across actors is a data
        // race (CKRecord's backing store isn't thread-safe). Copies give the
        // provider private instances; server records flow back via handleSent.
        // compactMapValues + `as?`: a copy that somehow isn't a CKRecord is dropped
        // (the provider rebuilds a fresh record below via the `?? CKRecord(...)`
        // fallback) rather than `as!`-trapping and crashing the whole sync batch.
        let cache = recordCache.compactMapValues { $0.copy() as? CKRecord }

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
            case RT.list:
                guard let list = lists[key] else { return nil }
                Self.fill(record, from: list)
            case RT.saved:
                Self.fill(record, savedIDs: defaultIDs)
            case RT.conjSRS:
                guard let card = conjCards[key] else { return nil }
                Self.fill(record, from: card)
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
        var lists: [WordList] = []
        var conjCards: [ConjugationSRSCard] = []
        var deckIDs: [String]?
        for modification in changes.modifications {
            let record = modification.record
            recordCache[record.recordID.recordName] = record
            switch record.recordType {
            case RT.srs:  if let c = Self.srsCard(from: record) { cards.append(c) }
            case RT.ride: if let r = Self.rideRecord(from: record) { rides.append(r) }
            case RT.odo:
                let (_, device) = Self.parse(record.recordID.recordName)
                if let s = Self.odometerSlot(from: record) { slots[device] = s }
            case RT.list: if let l = Self.wordList(from: record) { lists.append(l) }
            case RT.saved: deckIDs = Self.savedIDs(from: record)   // legacy deck → fold once
            case RT.conjSRS: if let c = Self.conjSrsCard(from: record) { conjCards.append(c) }
            default: break   // unknown record type (e.g. a newer schema) → safely skipped
            }
        }
        // Deletions are ignored at the record level: SRS/ride/odometer/conjugation are
        // append-only, and word-list deletions travel as the `deleted` FIELD
        // (a tombstone modification), not a CloudKit record delete.
        guard !cards.isEmpty || !rides.isEmpty || !slots.isEmpty
                || !lists.isEmpty || !conjCards.isEmpty || deckIDs != nil else { return }
        model?.applyCloudChanges(cards: cards, records: rides, odometerSlots: slots,
                                 wordLists: lists, legacyDeck: deckIDs, conjugationCards: conjCards)
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
            } else {
                // Every OTHER save failure used to be swallowed silently — the exact blind
                // spot that hid the WordList Production-schema miss for 3 versions (writes to a
                // non-existent Prod record type failed, nothing was logged, status stayed
                // "synced"). Log it, and surface a degraded status for a NON-transient error so
                // it's visible. LOG / STATUS ONLY — never drive the engine from this delegate
                // callback (red line: no engine fetch/send here). (v1.9 §A3.)
                PersistLog.failure("cksync save \(failure.record.recordID.recordName)", error)
                if !Self.isTransient(error) {
                    // Hand it to the pass — syncNow reports it at the end. Setting the status
                    // here would be immediately overwritten by the pass's closing `.synced`.
                    passFailure = Self.status(for: error)
                }
            }
        }
    }

    /// Transient CKErrors that the engine retries on its own — not worth a degraded status.
    private nonisolated static func isTransient(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
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
        case RT.list:
            // Field-level merge (ids union / name LWW / once-true-wins delete) so
            // the re-send materializes the merge winner, not a stale local value.
            if let list = Self.wordList(from: record) {
                model?.applyCloudChanges(wordLists: [list])
            }
        case RT.saved:
            model?.applyCloudChanges(legacyDeck: Self.savedIDs(from: record))
        case RT.conjSRS:
            if let card = Self.conjSrsCard(from: record) {
                model?.applyCloudChanges(conjugationCards: [card])
            }
        default:
            break
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            // New account: queue all local state and schedule a flush. We never
            // call the engine here (that's the delegate-re-entrancy CKSyncEngine
            // forbids); scheduleSync() hops out to syncNow(), which sends the
            // queued records whether or not a sync is already in flight — so a
            // signIn that lands after the in-flight pass's send isn't stranded.
            enqueueAllLocal()
            scheduleSync()
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
            scheduleSync()
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
        // Background (engine-state) write: log on failure, never alert. The write
        // mechanism is unchanged (atomic); only failure handling. (PLAN-V1.7 §D.)
        do { try data.write(to: stateURL, options: .atomic) }
        catch { PersistLog.failure("sync-engine state", error) }
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

    // Conjugation SRS card (v1.8 §C) — same field shape as SRSCard, its own record type
    // ("ConjugationSRSCard"). `cardID` holds the form-level id (`sourceID#form`).
    private nonisolated static func fill(_ record: CKRecord, from card: ConjugationSRSCard) {
        record["cardID"] = card.id
        record["easeFactor"] = card.easeFactor
        record["interval"] = card.interval
        record["repetitions"] = card.repetitions
        record["dueDate"] = card.dueDate
        record["lapses"] = card.lapses
        record["lastReviewed"] = card.lastReviewed
        record["totalReviews"] = card.totalReviews
        record["totalMistakes"] = card.totalMistakes
    }

    private nonisolated static func conjSrsCard(from record: CKRecord) -> ConjugationSRSCard? {
        guard let id = record["cardID"] as? String else { return nil }
        var card = ConjugationSRSCard(id: id)
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

    /// Legacy v1.4 deck record → just its ids (folded into the default list once).
    private nonisolated static func savedIDs(from record: CKRecord) -> [String] {
        record["ids"] as? [String] ?? []
    }

    /// One STRING field, not a per-word record type: a list's meta is only ever read
    /// and written whole, alongside the list itself, so N extra records would buy
    /// nothing and cost a fetch each.
    private nonisolated static func encodeMeta(_ meta: [String: WordMeta]) -> String? {
        guard !meta.isEmpty else { return nil }
        return (try? JSONEncoder().encode(meta)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private nonisolated static func decodeMeta(_ raw: Any?) -> [String: WordMeta] {
        guard let s = raw as? String, let data = s.data(using: .utf8) else { return [:] }
        // A meta blob we can't parse must NOT fail the whole list: dropping to [:]
        // degrades to pre-v1.10 union semantics (a stale word may linger) rather than
        // stranding the user's list entirely.
        return (try? JSONDecoder().decode([String: WordMeta].self, from: data)) ?? [:]
    }

    private nonisolated static func fill(_ record: CKRecord, from list: WordList) {
        record["name"] = list.name
        record["ids"] = list.ids
        record["nameUpdatedAt"] = list.nameUpdatedAt
        record["deleted"] = list.deleted ? 1 : 0
        record["deletedAt"] = list.deletedAt
        // ⚠️ Assigning nil REMOVES the key — the exact mechanism that hid the missing
        // `deletedAt` Prod field for 3 versions (lists synced fine until someone
        // deleted one, because only a deletion wrote the field). So this field only
        // exists on the wire once a word has been removed, which means the Prod schema
        // MUST carry `wordMeta` BEFORE this build ships (Phase 0) — otherwise the
        // failure reappears in the same shape: fine until the first removal.
        record["wordMeta"] = Self.encodeMeta(list.wordMeta)
    }

    private nonisolated static func wordList(from record: CKRecord) -> WordList? {
        let (_, id) = parse(record.recordID.recordName)
        guard !id.isEmpty else { return nil }
        return WordList(
            id: id,
            name: record["name"] as? String ?? "",
            ids: record["ids"] as? [String] ?? [],
            nameUpdatedAt: record["nameUpdatedAt"] as? Date ?? Date(timeIntervalSince1970: 0),
            deleted: (record["deleted"] as? Int ?? 0) != 0,
            deletedAt: record["deletedAt"] as? Date,
            isDefault: id == WordList.defaultID,
            wordMeta: decodeMeta(record["wordMeta"]))
    }
}
