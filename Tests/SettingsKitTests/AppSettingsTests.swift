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
            deviceID: "device-abc"
        )
        let decoded = try #require(AppSettings.decode(original.encoded()))
        #expect(decoded == original)
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
