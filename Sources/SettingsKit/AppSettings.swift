import Foundation

/// Persisted app settings.
///
/// Stored as a single JSON blob under one `UserDefaults` key so the schema is
/// easy to evolve. Enum-typed app concepts (game mode, JLPT level, passage
/// level) are stored here as their *raw values* and validated back into enums at
/// the `AppModel` boundary — that keeps this type dependency-free (no GameCore /
/// VocabKit import) and fully unit-testable.
///
/// Before v1.2 these settings lived only in memory and reset to defaults on every
/// launch; persisting them is the first v1.2 fix.
public struct AppSettings: Codable, Equatable, Sendable {
    // Settings that previously only lived in memory.
    public var languageCode: String          // "en" | "zh"
    public var showRomajiHint: Bool
    public var soundEnabled: Bool
    public var selectedMode: String          // GameMode raw value
    public var selectedLevel: Int?           // JLPTLevel raw value; nil = mix all levels
    public var practicePassages: Bool
    public var practicePassageLevel: String  // Passage.Level raw value

    // v1.2 additions.
    public var iCloudSyncEnabled: Bool
    public var dueReminderEnabled: Bool
    public var dueReminderHour: Int          // 0…23
    /// Stable per-install id for the lifetime-odometer G-Counter (see SyncKit).
    public var deviceID: String

    // v1.5 additions.
    /// Whether the one-time first-launch onboarding has been shown. Defaults false;
    /// flipped true when the user finishes/skips it (or silently for an upgrading
    /// user who already has data — see AppModel).
    public var hasSeenOnboarding: Bool

    // v1.7 additions.
    /// Which verb-conjugation forms to drill, as `ConjugationForm` raw values.
    /// Empty = all forms (the default). Stored opaquely (raw strings, like
    /// `selectedMode`); unknown raw values are tolerated and dropped at the
    /// `AppModel` boundary (`compactMap(ConjugationForm.init(rawValue:))`).
    public var conjugationForms: [String]

    // v1.8 additions.
    /// Whether a verb-conjugation drill records to the (separate) conjugation SRS store.
    /// Default true — the drill is a learning tool now, not a transient practice. A flag
    /// so future UI can turn it off; the weak-words cram and Practice NEVER feed it.
    public var conjugationSRSEnabled: Bool

    /// Read-aloud (TTS) of the kana on the game cards. Opt-in (default off). `ttsRate` is
    /// an `AVSpeechUtterance` rate — stored as a plain Float (0.5 = the platform default)
    /// so this type keeps no AVFoundation dependency; SpeechKit clamps it to the valid range.
    public var ttsEnabled: Bool
    public var ttsRate: Float

    // v1.9 additions.
    /// One-time marker: the conjugation SRS cards accumulated before conjugation iCloud
    /// sync was enabled (v1.8.1) have been enqueued for upload once. Prevents re-enqueuing
    /// the whole store on every launch. Set true after the back-fill fires. (v1.9 §A1.)
    public var conjSRSBackfilled: Bool
    /// Whether the one-time odometer backfill has already been CONSIDERED on this device.
    /// Set once the condition has been evaluated, whether or not it fired — see
    /// `OdometerLog.shouldBackfill`. Without it the decision was re-taken on every launch,
    /// so a device that legitimately declined could still fire later once transient state
    /// (an unreadable odometer file, a half-finished first sync) made it look eligible.
    public var odometerBackfillDone: Bool

    public init(
        languageCode: String = "en",
        showRomajiHint: Bool = true,
        soundEnabled: Bool = true,
        selectedMode: String = "journey",
        selectedLevel: Int? = 5,
        practicePassages: Bool = true,
        practicePassageLevel: String = "med",
        iCloudSyncEnabled: Bool = true,
        dueReminderEnabled: Bool = false,
        dueReminderHour: Int = 20,
        deviceID: String = "",
        hasSeenOnboarding: Bool = false,
        conjugationForms: [String] = [],
        conjugationSRSEnabled: Bool = true,
        ttsEnabled: Bool = false,
        ttsRate: Float = 0.5,
        conjSRSBackfilled: Bool = false,
        odometerBackfillDone: Bool = false
    ) {
        self.languageCode = languageCode
        self.showRomajiHint = showRomajiHint
        self.soundEnabled = soundEnabled
        self.selectedMode = selectedMode
        self.selectedLevel = selectedLevel
        self.practicePassages = practicePassages
        self.practicePassageLevel = practicePassageLevel
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.dueReminderEnabled = dueReminderEnabled
        self.dueReminderHour = dueReminderHour
        self.deviceID = deviceID
        self.hasSeenOnboarding = hasSeenOnboarding
        self.conjugationForms = conjugationForms
        self.conjugationSRSEnabled = conjugationSRSEnabled
        self.ttsEnabled = ttsEnabled
        self.ttsRate = ttsRate
        self.conjSRSBackfilled = conjSRSBackfilled
        self.odometerBackfillDone = odometerBackfillDone
    }

    public static let `default` = AppSettings()

    /// The `UserDefaults` key the settings blob lives under.
    public static let defaultsKey = "NihongoRide.settings.v1"

    private static let validLanguages: Set<String> = ["en", "zh"]

    // Decode tolerantly: any missing key falls back to the default value, so a
    // partial / older / forward-version blob still loads instead of throwing.
    private enum CodingKeys: String, CodingKey {
        case languageCode, showRomajiHint, soundEnabled, selectedMode, selectedLevel
        case practicePassages, practicePassageLevel
        case iCloudSyncEnabled, dueReminderEnabled, dueReminderHour, deviceID
        case hasSeenOnboarding
        case conjugationForms
        case conjugationSRSEnabled
        case ttsEnabled, ttsRate
        case conjSRSBackfilled
        case odometerBackfillDone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        languageCode = try c.decodeIfPresent(String.self, forKey: .languageCode) ?? d.languageCode
        showRomajiHint = try c.decodeIfPresent(Bool.self, forKey: .showRomajiHint) ?? d.showRomajiHint
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? d.soundEnabled
        selectedMode = try c.decodeIfPresent(String.self, forKey: .selectedMode) ?? d.selectedMode
        // `nil` is meaningful here (mix all levels), so distinguish an absent key
        // (older / partial blob → default) from an explicit null (mix all).
        selectedLevel = c.contains(.selectedLevel)
            ? try c.decode(Int?.self, forKey: .selectedLevel)
            : d.selectedLevel
        practicePassages = try c.decodeIfPresent(Bool.self, forKey: .practicePassages) ?? d.practicePassages
        practicePassageLevel = try c.decodeIfPresent(String.self, forKey: .practicePassageLevel) ?? d.practicePassageLevel
        iCloudSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? d.iCloudSyncEnabled
        dueReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .dueReminderEnabled) ?? d.dueReminderEnabled
        dueReminderHour = try c.decodeIfPresent(Int.self, forKey: .dueReminderHour) ?? d.dueReminderHour
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID) ?? d.deviceID
        hasSeenOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? d.hasSeenOnboarding
        conjugationForms = try c.decodeIfPresent([String].self, forKey: .conjugationForms) ?? d.conjugationForms
        conjugationSRSEnabled = try c.decodeIfPresent(Bool.self, forKey: .conjugationSRSEnabled) ?? d.conjugationSRSEnabled
        ttsEnabled = try c.decodeIfPresent(Bool.self, forKey: .ttsEnabled) ?? d.ttsEnabled
        ttsRate = try c.decodeIfPresent(Float.self, forKey: .ttsRate) ?? d.ttsRate
        conjSRSBackfilled = try c.decodeIfPresent(Bool.self, forKey: .conjSRSBackfilled) ?? d.conjSRSBackfilled
        odometerBackfillDone = try c.decodeIfPresent(Bool.self, forKey: .odometerBackfillDone) ?? d.odometerBackfillDone
    }

    // Always write every key — including `selectedLevel` as an explicit null when
    // nil — so a round-trip preserves "mix all levels" (the synthesized encoder
    // would omit a nil optional, making absent vs. mix-all ambiguous on decode).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(languageCode, forKey: .languageCode)
        try c.encode(showRomajiHint, forKey: .showRomajiHint)
        try c.encode(soundEnabled, forKey: .soundEnabled)
        try c.encode(selectedMode, forKey: .selectedMode)
        try c.encode(selectedLevel, forKey: .selectedLevel)
        try c.encode(practicePassages, forKey: .practicePassages)
        try c.encode(practicePassageLevel, forKey: .practicePassageLevel)
        try c.encode(iCloudSyncEnabled, forKey: .iCloudSyncEnabled)
        try c.encode(dueReminderEnabled, forKey: .dueReminderEnabled)
        try c.encode(dueReminderHour, forKey: .dueReminderHour)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encode(hasSeenOnboarding, forKey: .hasSeenOnboarding)
        try c.encode(conjugationForms, forKey: .conjugationForms)
        try c.encode(conjugationSRSEnabled, forKey: .conjugationSRSEnabled)
        try c.encode(ttsEnabled, forKey: .ttsEnabled)
        try c.encode(ttsRate, forKey: .ttsRate)
        try c.encode(conjSRSBackfilled, forKey: .conjSRSBackfilled)
        try c.encode(odometerBackfillDone, forKey: .odometerBackfillDone)
    }

    /// Clamps/repairs out-of-range primitive values and guarantees a `deviceID`.
    /// Enum raw values (mode / level) are validated at the `AppModel` boundary,
    /// where an unknown raw maps to a safe default.
    public func sanitized() -> AppSettings {
        var s = self
        if !Self.validLanguages.contains(s.languageCode) { s.languageCode = "en" }
        s.dueReminderHour = min(23, max(0, s.dueReminderHour))
        if s.deviceID.isEmpty { s.deviceID = UUID().uuidString }
        return s
    }

    // MARK: Persistence

    /// Decodes a settings blob, or `nil` if the data isn't valid settings JSON.
    public static func decode(_ data: Data) -> AppSettings? {
        try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// Loads (and sanitizes) settings from `defaults`. A fresh install with no
    /// stored blob returns sanitized defaults — which mints a new `deviceID`.
    public static func load(from defaults: UserDefaults, key: String = defaultsKey) -> AppSettings {
        guard let data = defaults.data(forKey: key), let decoded = decode(data) else {
            return AppSettings.default.sanitized()
        }
        return decoded.sanitized()
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        defaults.set(encoded(), forKey: key)
    }
}
