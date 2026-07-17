import Foundation

/// The shared App Group both the app and its widget extensions use to hand the
/// widget its snapshot.
public enum AppGroup {
    /// 🔴 Platform-conditional ON PURPOSE. macOS requires the team-id prefix on the
    /// group identifier; iOS must NOT have it. Get this wrong and
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil, the snapshot
    /// silently never lands, and the widget shows a placeholder forever with no error —
    /// exactly the "reports success, does nothing" failure class v1.10 was about. This
    /// must match the `com.apple.security.application-groups` entitlement on every
    /// target (app + both extensions), which project.yml sets per platform.
    public static let identifier: String = {
        #if os(macOS)
        return "KHMK6Q3L3K.group.com.jasonye.nihongoride"
        #else
        return "group.com.jasonye.nihongoride"
        #endif
    }()

    /// The App Group container URL, or nil if the entitlement isn't in effect. Callers
    /// MUST treat nil as "sharing unavailable" and degrade — never force-unwrap.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
