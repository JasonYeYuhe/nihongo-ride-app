import Foundation

/// Loading a JSON store from disk without losing everything to one bad element.
///
/// Every store the app owns used to load like this:
///
///     guard let data = try? Data(contentsOf: url),
///           let store = try? JSONDecoder().decode(Store.self, from: data)
///     else { return Store() }
///
/// which fails in three separate ways, all silent:
///
/// 1. **One malformed element discards the whole store.** These element types use Swift's
///    synthesized decoder, so a single missing key throws for the entire array. Nine hundred
///    review cards become zero because one of them lost a field. The very next write makes
///    that permanent, and iCloud cannot heal it — the persisted change token means the server
///    never re-sends records this device has already seen.
/// 2. **It cannot tell "unreadable" from "undecodable."** A file the process momentarily could
///    not READ (a file-coordination hiccup, a device still unlocking) is treated exactly like
///    corruption: the app starts empty and then overwrites the good bytes.
/// 3. **The bad bytes are thrown away**, so nothing can be recovered afterwards.
///
/// `WordListsKit` already got all three right (`WordListMigration.loadOrMigrate`). This module
/// is that approach, extracted so the review stores, the ride journal and the odometer share
/// it instead of the pattern being written a fifth time — which is how the medium widget and
/// the reminder plurals each shipped wrong.
public enum LossyLoad {

    /// What happened when a store was loaded. Callers that can WRITE the store back must
    /// check for ``unreadable``: continuing to run on an empty store is survivable, but
    /// saving over a file that was merely unreadable is not.
    public enum Outcome: Equatable, Sendable {
        /// No file yet — a fresh install. Safe to write.
        case missing
        /// Decoded cleanly.
        case loaded
        /// Decoded, but `skipped` elements were malformed and were dropped. The rest is
        /// intact and safe to write; the count is for logging, not for a decision.
        case loadedWithSkips(skipped: Int)
        /// The bytes could not be READ. The file may be perfectly good. **Do not write.**
        case unreadable
        /// Read fine, could not be decoded at all. The bytes were copied to a `.corrupt`
        /// sibling first. Safe to write.
        case undecodable
    }

    /// A store that could be written back without destroying something.
    public static func isSafeToWrite(_ outcome: Outcome) -> Bool {
        outcome != .unreadable
    }

    /// Reads and decodes `url`, quarantining bytes it cannot decode.
    ///
    /// - Parameters:
    ///   - url: the store file.
    ///   - decoder: configured decoder (date strategy etc.).
    ///   - type: the store type.
    /// - Returns: the decoded store (or nil, for the caller to substitute an empty one) and
    ///   what happened. Element-level tolerance is the store type's own job — see
    ///   ``lossyArray(_:from:)``; this handles the file level.
    public static func load<T: Decodable>(
        _ type: T.Type, from url: URL, decoder: JSONDecoder = JSONDecoder()
    ) -> (value: T?, outcome: Outcome) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, .missing) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return (nil, .unreadable)
        }
        if let decoded = try? decoder.decode(type, from: data) {
            return (decoded, .loaded)
        }
        quarantine(data, from: url)
        return (nil, .undecodable)
    }

    /// Copies bytes that could not be decoded next to the original, once, before anything
    /// overwrites them. Best-effort: a failure here must not stop the app from starting.
    public static func quarantine(_ data: Data, from url: URL) {
        try? data.write(to: url.appendingPathExtension("corrupt"), options: .atomic)
    }

    /// Decodes an array, keeping the elements that decode and counting the ones that don't.
    ///
    /// Use inside a store's `init(from:)`. The wrapper is required rather than merely
    /// convenient: `JSONDecoder` does NOT advance an unkeyed container's index when an
    /// element throws, so the obvious `while !container.isAtEnd { try? container.decode(…) }`
    /// spins forever on the first bad element. Decoding into a wrapper that never throws
    /// keeps the index moving.
    public static func lossyArray<Element: Decodable, Key: CodingKey>(
        _ elementType: Element.Type,
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> (elements: [Element], skipped: Int) {
        let wrapped = try container.decode([Tolerant<Element>].self, forKey: key)
        let kept = wrapped.compactMap(\.value)
        return (kept, wrapped.count - kept.count)
    }

    /// Decodes a `[String: Element]` map, keeping the entries that decode.
    ///
    /// The SRS stores are keyed by card id rather than being arrays, and one unreadable card
    /// must cost exactly that card.
    public static func lossyDictionary<Element: Decodable, Key: CodingKey>(
        _ elementType: Element.Type,
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> (elements: [String: Element], skipped: Int) {
        let wrapped = try container.decode([String: Tolerant<Element>].self, forKey: key)
        let kept = wrapped.compactMapValues(\.value)
        return (kept, wrapped.count - kept.count)
    }

    /// Same, for a bare top-level array.
    public static func lossyArray<Element: Decodable>(
        _ elementType: Element.Type, from data: Data, decoder: JSONDecoder = JSONDecoder()
    ) throws -> (elements: [Element], skipped: Int) {
        let wrapped = try decoder.decode([Tolerant<Element>].self, from: data)
        let kept = wrapped.compactMap(\.value)
        return (kept, wrapped.count - kept.count)
    }

    /// Decodes `Element`, or nothing, but never throws — so the enclosing container keeps
    /// advancing past an element it could not read.
    public struct Tolerant<Element: Decodable>: Decodable {
        public let value: Element?
        public init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }
}
