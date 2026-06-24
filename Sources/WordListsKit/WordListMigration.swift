import Foundation

extension WordListStore {

    /// What ``loadOrMigrate(wordListsURL:legacySavedWordsURL:defaultName:now:)`` did,
    /// for telemetry / logging.
    public enum MigrationOutcome: Equatable, Sendable {
        /// `word-lists.json` existed and decoded.
        case loadedExisting
        /// No `word-lists.json` → built the default list from `saved-words.json`.
        case migratedFromSavedWords
        /// `word-lists.json` existed and was readable but failed to decode → the bad
        /// bytes were quarantined to `.corrupt` and the store rebuilt from
        /// `saved-words.json` (at worst keeps the default list).
        case recoveredFromCorrupt
        /// `word-lists.json` exists but could not be *read* (transient I/O, file
        /// protection unavailable at early launch). The file is left UNTOUCHED — we
        /// return an in-memory default for this session and retry next launch rather
        /// than clobbering possibly-good data with a rebuild.
        case unreadableDeferred
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
            // Distinguish "unreadable" (read throws) from "undecodable" (read OK,
            // decode fails). Only the latter is corruption we should quarantine +
            // rebuild; an unreadable file must NOT be overwritten.
            let data: Data
            do {
                data = try Data(contentsOf: wordListsURL)
            } catch {
                var store = WordListStore()
                store.ensureDefault(name: defaultName, now: now)
                return (store, .unreadableDeferred)   // leave the file untouched, retry next launch
            }

            if let decoded = try? JSONDecoder().decode(WordListStore.self, from: data) {
                // Valid file. Repair (ensure default) only; persist only if changed.
                // Tombstone compaction is intentionally NOT run on the load path —
                // it must run only after a successful cloud merge (see
                // WordListStore.compactTombstones docs), else a not-yet-propagated
                // deletion can be revived by the peer on the first fetch.
                var store = decoded
                store.ensureDefault(name: defaultName, now: now)
                if store != decoded { try? store.save(to: wordListsURL) }
                return (store, .loadedExisting)
            } else {
                // Read OK but undecodable → genuine corruption: quarantine the bytes
                // we already have + rebuild (don't lose silently).
                quarantineCorrupt(data: data, original: wordListsURL)
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

    /// Writes the already-read bytes of a corrupt file to `<name>.corrupt` (atomic),
    /// for post-mortem / recovery. Best-effort; takes the bytes directly so it never
    /// re-reads (and so it works even if the file is replaced right after).
    private static func quarantineCorrupt(data: Data, original url: URL) {
        let dest = url.appendingPathExtension("corrupt")
        try? data.write(to: dest, options: .atomic)
    }
}
