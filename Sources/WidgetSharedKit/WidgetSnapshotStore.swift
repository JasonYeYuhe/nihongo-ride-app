import Foundation

/// Reads and writes the widget snapshot in the shared App Group container.
///
/// Split write/read intent by asymmetric error handling: a WRITE reports failure (the
/// app wants to know the App Group isn't wired up), a READ never throws (a widget must
/// render *something* — a missing or corrupt file becomes nil → placeholder, never a
/// crash on the user's home screen).
public enum WidgetSnapshotStore {
    static let filename = "widget-snapshot.json"

    /// Why a write can fail to report to the app layer.
    public enum WriteError: Error, Equatable {
        /// The App Group container is unavailable — entitlement missing or not yet in
        /// effect. Distinct from an I/O failure so the app can log the actionable cause.
        case containerUnavailable
        case io(String)
    }

    /// The snapshot file URL inside the group container, or nil if the group is
    /// unavailable. Exposed so a caller can supply an explicit container (tests, and the
    /// capture path, which must NOT write the real group container).
    public static func url(in container: URL? = AppGroup.containerURL()) -> URL? {
        container?.appendingPathComponent(filename)
    }

    /// Atomically writes `snapshot`. Pass an explicit `container` to target somewhere
    /// other than the real App Group (tests; and the capture path hands a throwaway dir
    /// so a headless render never overwrites the user's live snapshot).
    public static func write(_ snapshot: WidgetSnapshot,
                             to container: URL? = AppGroup.containerURL()) -> Result<Void, WriteError> {
        guard let container else { return .failure(.containerUnavailable) }
        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: container.appendingPathComponent(filename), options: .atomic)
            return .success(())
        } catch {
            return .failure(.io(String(describing: error)))
        }
    }

    /// Reads the snapshot, or nil if absent / unreadable / from a newer schema. NEVER
    /// throws: the widget's whole contract is that it renders regardless.
    public static func read(from container: URL? = AppGroup.containerURL()) -> WidgetSnapshot? {
        guard let url = url(in: container),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion <= WidgetSnapshot.currentSchema
        else { return nil }
        return snapshot
    }
}
