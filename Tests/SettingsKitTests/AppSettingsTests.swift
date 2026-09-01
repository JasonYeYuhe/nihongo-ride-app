import Testing
import Foundation
@testable import SettingsKit

@Suite("AppSettings persistence")
struct AppSettingsTests {

    @Test("encode → decode round-trips every field")
    func roundTrip() throws {
        let original = AppSettings(
            languageCode: "zh",
            showRomajiHint: false,
            soundEnabled: false,
            selectedMode: "timeAttack",
            selectedLevel: 2,
            practicePassages: false,
            practicePassageLevel: "hard",
            iCloudSyncEnabled: false,
            dueReminderEnabled: true,
            dueReminderHour: 7,
            deviceID: "device-abc",
            hasSeenOnboarding: true,
            conjugationForms: ["te", "volitional"]
        )
        let decoded = try #require(AppSettings.decode(original.encoded()))
        #expect(decoded == original)
    }

    @Test("conjugationForms round-trips and defaults to empty (= all forms)")
    func conjugationFormsRoundTrip() throws {
        #expect(AppSettings.default.conjugationForms == [])
        var s = AppSettings.default
        s.conjugationForms = ["te", "past"]
        let decoded = try #require(AppSettings.decode(s.encoded()))
        #expect(decoded.conjugationForms == ["te", "past"])
    }

    @Test("a pre-v1.7 blob without conjugationForms decodes to empty (= all forms)")
    func conjugationFormsAbsent() throws {
        let json = Data(#"{"languageCode":"en","deviceID":"d1"}"#.utf8)
        let decoded = try #require(AppSettings.decode(json))
        #expect(decoded.conjugationForms == [])
    }

    @Test("conjugationSRSEnabled defaults true, round-trips, and a pre-v1.8 blob stays true")
    func conjugationSRSEnabled() throws {
        #expect(AppSettings.default.conjugationSRSEnabled)                       // default on
        var s = AppSettings.default
        s.conjugationSRSEnabled = false
        let decoded = try #require(AppSettings.decode(s.encoded()))
        #expect(!decoded.conjugationSRSEnabled)                                  // round-trips false
        // A pre-v1.8 blob (no key) decodes to the default true — never silently off.
        let old = try #require(AppSettings.decode(Data(#"{"languageCode":"en","deviceID":"d1"}"#.utf8)))
        #expect(old.conjugationSRSEnabled)
    }

    @Test("tts settings default off/0.5, round-trip, and a pre-v1.8 blob keeps defaults")
    func ttsSettings() throws {
        #expect(!AppSettings.default.ttsEnabled)
        #expect(AppSettings.default.ttsRate == 0.5)
        var s = AppSettings.default
        s.ttsEnabled = true
        s.ttsRate = 0.42
        let decoded = try #require(AppSettings.decode(s.encoded()))
        #expect(decoded.ttsEnabled)
        #expect(decoded.ttsRate == 0.42)
        let old = try #require(AppSettings.decode(Data(#"{"languageCode":"en","deviceID":"d1"}"#.utf8)))
        #expect(!old.ttsEnabled)
        #expect(old.ttsRate == 0.5)
    }

    @Test("conjSRSBackfilled defaults false, round-trips, and a pre-v1.9 blob stays false (v1.9 §A1)")
    func conjSRSBackfilled() throws {
        #expect(!AppSettings.default.conjSRSBackfilled)
        var s = AppSettings.default
        s.conjSRSBackfilled = true
        #expect(try #require(AppSettings.decode(s.encoded())).conjSRSBackfilled)
        let old = try #require(AppSettings.decode(Data(#"{"languageCode":"en","deviceID":"d1"}"#.utf8)))
        #expect(!old.conjSRSBackfilled)   // a pre-v1.9 blob must not read as "already backfilled"
    }

    @Test("hasSeenOnboarding defaults to false and a pre-v1.5 blob without it stays false")
    func onboardingFlagDefaults() throws {
        #expect(AppSettings.default.hasSeenOnboarding == false)
        let json = Data(#"{"languageCode":"en","deviceID":"d1"}"#.utf8)
        let decoded = try #require(AppSettings.decode(json))
        #expect(decoded.hasSeenOnboarding == false)
    }

    @Test("nil selectedLevel (mix all) survives a round-trip")
    func nilLevelRoundTrips() throws {
        var s = AppSettings.default
        s.selectedLevel = nil
        let decoded = try #require(AppSettings.decode(s.encoded()))
        #expect(decoded.selectedLevel == nil)
    }

    @Test("a partial JSON blob fills missing keys with defaults")
    func partialBlob() throws {
        let json = Data(#"{"languageCode":"zh","dueReminderEnabled":true}"#.utf8)
        let decoded = try #require(AppSettings.decode(json))
        #expect(decoded.languageCode == "zh")
        #expect(decoded.dueReminderEnabled == true)
        // Untouched keys fall back to defaults.
        #expect(decoded.soundEnabled == AppSettings.default.soundEnabled)
        #expect(decoded.dueReminderHour == AppSettings.default.dueReminderHour)
        #expect(decoded.selectedMode == "journey")
    }

    @Test("non-JSON data decodes to nil (caller falls back to defaults)")
    func corruptData() {
        #expect(AppSettings.decode(Data("not json".utf8)) == nil)
    }

    @Test("sanitize clamps the reminder hour into 0…23")
    func clampHour() {
        var high = AppSettings.default; high.dueReminderHour = 99
        #expect(high.sanitized().dueReminderHour == 23)
        var low = AppSettings.default; low.dueReminderHour = -5
        #expect(low.sanitized().dueReminderHour == 0)
    }

    @Test("sanitize repairs an unknown language to en")
    func sanitizeLanguage() {
        var s = AppSettings.default; s.languageCode = "fr"
        #expect(s.sanitized().languageCode == "en")
    }

    @Test("sanitize mints a deviceID when missing and keeps an existing one")
    func deviceID() {
        let minted = AppSettings.default.sanitized()
        #expect(!minted.deviceID.isEmpty)
        var existing = AppSettings.default; existing.deviceID = "keep-me"
        #expect(existing.sanitized().deviceID == "keep-me")
    }

    @Test("load on a fresh store returns sanitized defaults with a deviceID")
    func loadFresh() throws {
        let defaults = try #require(UserDefaults(suiteName: "settings-fresh-\(UUID().uuidString)"))
        let loaded = AppSettings.load(from: defaults, key: "k")
        #expect(loaded.languageCode == "en")
        #expect(!loaded.deviceID.isEmpty)
    }

    @Test("save then load preserves settings through UserDefaults")
    func saveLoad() throws {
        let defaults = try #require(UserDefaults(suiteName: "settings-saveload-\(UUID().uuidString)"))
        var s = AppSettings.default
        s.languageCode = "zh"
        s.dueReminderEnabled = true
        s.deviceID = "stable-id"
        s.save(to: defaults, key: "k")

        let loaded = AppSettings.load(from: defaults, key: "k")
        #expect(loaded.languageCode == "zh")
        #expect(loaded.dueReminderEnabled == true)
        #expect(loaded.deviceID == "stable-id")
    }
}

/// v1.16 §A migration: the assistance policy replaces the hint boolean, and an EXISTING
/// user's explicit choice must survive the upgrade exactly.
@Suite("Assistance migration")
struct AssistanceMigrationTests {

    private func decoded(_ json: String) -> AppSettings {
        AppSettings.decode(Data(json.utf8))!.sanitized()
    }

    @Test("a pre-v1.16 blob maps the boolean the user actually set")
    func mapsOldBoolean() {
        // Hints on → always; hints off → off. NOT the new default: a learner who chose
        // blind practice must not wake up to "offer after struggle" they never asked for.
        #expect(decoded(#"{"showRomajiHint": true}"#).assistance == "always")
        #expect(decoded(#"{"showRomajiHint": false}"#).assistance == "off")
    }

    @Test("only a genuinely fresh install gets the new default")
    func freshDefault() {
        #expect(AppSettings.default.assistance == "struggle")
    }

    @Test("a garbage value sanitizes back to the boolean's meaning")
    func sanitizes() {
        let s = decoded(#"{"showRomajiHint": false, "assistance": "sometimes-ish"}"#)
        #expect(s.assistance == "off")
    }

    @Test("round-trips")
    func roundTrip() {
        var s = AppSettings.default
        s.assistance = "struggle"
        let back = AppSettings.decode(s.encoded())!
        #expect(back.assistance == "struggle")
    }
}

/// `practiceSource` replaced a boolean, and v1.16 already paid for getting that wrong once.
///
/// When `assistance` replaced `showRomajiHint`, the fix needed two parts and the second was
/// found late: derive the new value from the old on migration, AND keep the legacy boolean
/// derived on EVERY sanitise — otherwise a stale `true` survives and resurrects a setting the
/// owner never chose. The same two parts are asserted here, for the same reason.
@Suite("practiceSource replaces practicePassages without losing the learner's choice")
struct PracticeSourceMigrationTests {

    private func decoded(_ json: String) -> AppSettings? {
        AppSettings.decode(Data(json.utf8))
    }

    @Test("a pre-v1.31 blob keeps the choice its owner actually made")
    func migratesFromTheBoolean() throws {
        let passages = try #require(decoded(#"{"practicePassages": true}"#))
        #expect(passages.practiceSource == "passages")
        let words = try #require(decoded(#"{"practicePassages": false}"#))
        #expect(words.practiceSource == "words",
                "a learner who chose the word stream must not be moved to passages")
    }

    @Test("an explicit practiceSource wins over the legacy boolean")
    func newKeyWins() throws {
        let s = try #require(decoded(#"{"practicePassages": true, "practiceSource": "custom"}"#))
        #expect(s.practiceSource == "custom")
    }

    @Test("the legacy boolean stays DERIVED — the half v1.16 got wrong first time")
    func booleanIsDerivedOnEverySanitise() throws {
        // A blob where the two disagree is exactly what an older build writes after the learner
        // used a newer one. Sanitising must resolve it in one direction, always.
        var s = try #require(decoded(#"{"practicePassages": false, "practiceSource": "passages"}"#))
        s = s.sanitized()
        #expect(s.practicePassages, "the boolean must follow the source, not persist beside it")

        var custom = try #require(decoded(#"{"practicePassages": false, "practiceSource": "custom"}"#))
        custom = custom.sanitized()
        #expect(custom.practicePassages, Comment(rawValue:
            "\"custom\" has no boolean to be; it maps to true so an older build shows bundled "
            + "passages — a sensible screen — rather than the word stream, a different mode"))

        var words = try #require(decoded(#"{"practicePassages": true, "practiceSource": "words"}"#))
        words = words.sanitized()
        #expect(!words.practicePassages, Comment(rawValue: "…and the control: 'words' must drive "
                + "it the other way, or the derivation is a constant"))
    }

    @Test("an unknown source falls back to the legacy boolean, not to a blank screen")
    func unknownSourceRepairs() throws {
        let s = try #require(decoded(#"{"practicePassages": false, "practiceSource": "nonsense"}"#))
            .sanitized()
        #expect(s.practiceSource == "words")
    }

    @Test("it survives its own round trip")
    func roundTrip() throws {
        var s = AppSettings.default
        s.practiceSource = "custom"
        let back = try #require(AppSettings.decode(s.sanitized().encoded()))
        #expect(back.practiceSource == "custom")
    }
}
