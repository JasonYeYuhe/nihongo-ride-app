import Foundation

extension WordListStore {

    /// What ``loadOrMigrate(wordListsURL:legacySavedWordsURL:defaultName:now:)`` did,
    /// for telemetry / logging.
    public enum MigrationOutcome: Equatable, Sendable {
        /// `word-lists.json` existed and decoded.
        case loadedExisting
        /// No `word-lists.json` → built the default list from `saved-words.json`.
        case migratedFromSavedWords
        /// `word-lists.json` existed but was unreadable → quarantined to `.corrupt`
        /// and rebuilt from `saved-words.json` (at worst keeps the default list).
        case recoveredFromCorrupt
        /// Neither file existed → fresh empty default list.
        case freshInstall
    }

    /// Loads the word-list store, performing a one-time, idempotent, corruption-aware
    /// migration from the legacy `saved-words.json` deck when needed.
    ///
    /// Critical (§A2): unlike `SavedWordsStore.load`, a file that *exists but fails
    /// to decode* is **not** silently treated as empty — that would throw away the
    /// user's named lists. Instead the bad file is quarantined (`.corrupt`) and the
    /// store is rebuilt from `saved-words.json` (which is preserved for rollback),
    /// so at minimum the default list survives.
    ///
    /// Idempotent: a valid `word-lists.json` containing a default list is the
    /// "already migrated" signal — a second run is a no-op (returns
    /// `.loadedExisting`). Runs before sync `start()` so the local store is shaped
    /// first and the first cloud fetch merges into it (union ids + name LWW) rather
    /// than an empty store overwriting the cloud.
    ///
    /// All writes are synchronous + atomic. Call on the main actor.
    public static func loadOrMigrate(
        wordListsURL: URL,
        legacySavedWordsURL: URL,
        defaultName: String,
        now: Date = Date()
    ) -> (store: WordListStore, outcome: MigrationOutcome) {
        let fm = FileManager.default

        if fm.fileExists(atPath: wordListsURL.path) {
            if let data = try? Data(contentsOf: wordListsURL),
               let decoded = try? JSONDecoder().decode(WordListStore.self, from: data) {
                // Valid file. Repair (ensure default) + compact, persist only if changed.
                var store = decoded
                store.ensureDefault(name: defaultName, now: now)
                store.compactTombstones(now: now)
                if store != decoded { try? store.save(to: wordListsURL) }
                return (store, .loadedExisting)
            } else {
                // Exists but unreadable → quarantine + rebuild (don't lose silently).
                quarantineCorrupt(wordListsURL)
                let store = migrate(fromSaved: legacySavedWordsURL, defaultName: defaultName, now: now)
                try? store.save(to: wordListsURL)
                return (store, .recoveredFromCorrupt)
            }
        }

        // No word-lists.json yet.
        if fm.fileExists(atPath: legacySavedWordsURL.path) {
            let store = migrate(fromSaved: legacySavedWordsURL, defaultName: defaultName, now: now)
            try? store.save(to: wordListsURL)
            return (store, .migratedFromSavedWords)
        }

        var store = WordListStore()
        store.ensureDefault(name: defaultName, now: now)
        try? store.save(to: wordListsURL)
        return (store, .freshInstall)
    }

    /// Builds a store whose default list holds the legacy saved-words ids (if any).
    private static func migrate(fromSaved url: URL, defaultName: String, now: Date) -> WordListStore {
        var store = WordListStore()
        store.ensureDefault(name: defaultName, now: now)
        for id in legacySavedIDs(url) {
            _ = store.addWord(id, to: WordList.defaultID, now: now)
        }
        return store
    }

    /// Reads `{"ids":[...]}` from the legacy saved-words file. Returns `[]` on any
    /// problem (the legacy file format is `SavedWordsStore`'s; we decode just the
    /// ids to keep this module dependency-free).
    private static func legacySavedIDs(_ url: URL) -> [String] {
        struct Legacy: Decodable { let ids: [String]? }
        guard let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode(Legacy.self, from: data)
        else { return [] }
        return legacy.ids ?? []
    }

    /// Copies the raw bytes of a corrupt file to `<name>.corrupt` (atomic), for
    /// post-mortem / recovery. Best-effort.
    private static func quarantineCorrupt(_ url: URL) {
        let dest = url.appendingPathExtension("corrupt")
        if let data = try? Data(contentsOf: url) {
            try? data.write(to: dest, options: .atomic)
        }
    }
}
