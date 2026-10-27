import Testing
import Foundation
import VocabKit
import SettingsKit
import SyncKit
@testable import NihongoRideApp

/// The marker's ONE call site (v1.37 P0-12) — the half `InstallCohortTests` cannot see.
///
/// The pure rule is right about the inputs it is handed. What only the app can get wrong is WHEN
/// it reads them: `init` saves the settings blob at its end, so a call placed after that save would
/// record every fresh install as one with prior data, and every pure test would still pass.
@MainActor
@Suite("The install-cohort marker is written once, at launch, from data read before any write")
struct InstallCohortWiringTests {

    static func vocab() -> VocabStore {
        VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")])
    }

    static func running(_ version: [Int], _ build: Int) -> InstallCohort.Running {
        InstallCohort.Running(version: InstallCohort.Version(components: version)!, build: build,
                              platform: .macOS)
    }

    /// A fresh sandbox, the same three redirects `AppModelTests.sandboxed` sets, with `arrange` run
    /// on it BEFORE any model reads it. Returns the suite so a test can read what `init` wrote.
    static func sandbox(arrange: (UserDefaults) -> Void = { _ in }) -> UserDefaults {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NihongoRideAppTests-\(UUID().uuidString)", isDirectory: true)
        AppModel.supportDirectoryOverride = dir
        AppModel.widgetContainerOverride = dir.appendingPathComponent("group", isDirectory: true)
        let suite = "NihongoRideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        AppModel.settingsDefaults = defaults
        AppModel.settingsSuiteOverride = suite
        arrange(defaults)
        return defaults
    }

    static func launch(_ running: InstallCohort.Running) -> AppModel {
        AppModel.installCohortRunningOverride = running
        defer { AppModel.installCohortRunningOverride = nil }
        return AppModel(vocab: vocab())
    }

    @Test("a fresh install: no marker before, one after, with priorDataPresent false")
    func freshInstall() throws {
        let defaults = Self.sandbox()
        #expect(defaults.object(forKey: AppSettings.defaultsKey) == nil, "the sandbox is not fresh")
        let model = Self.launch(Self.running([1, 37], 63))
        #expect(model.installCohortAtLaunch == .absent)
        let bytes = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        #expect(String(decoding: bytes, as: UTF8.self)
                == #"{"firstSeenBuild":63,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#)
        // …and the settings blob this launch saved is what a later launch will count as prior data.
        #expect(defaults.object(forKey: AppSettings.defaultsKey) != nil)
    }

    @Test("a second launch, even of a newer build, reads the first marker and writes nothing")
    func secondLaunch() throws {
        let defaults = Self.sandbox()
        _ = Self.launch(Self.running([1, 37], 63))
        let first = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        let again = Self.launch(Self.running([1, 38], 64))
        #expect(again.installCohortAtLaunch?.marker?.firstSeenBuild == 63)
        #expect(again.installCohortAtLaunch?.marker?.firstSeenVersion.components == [1, 37])
        #expect(again.installCohortAtLaunch?.marker?.priorDataPresent == false)
        #expect(defaults.data(forKey: "NihongoRide.installCohort.v1") == first)
    }

    @Test("an install upgrading with saved settings and no marker is recorded as having prior data")
    func upgraderWithSettings() throws {
        let defaults = Self.sandbox { AppSettings.default.sanitized().save(to: $0) }
        let model = Self.launch(Self.running([1, 37], 63))
        #expect(model.installCohortAtLaunch == .absent)
        let bytes = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        #expect(String(decoding: bytes, as: UTF8.self).contains(#""priorDataPresent":true"#))
    }

    @Test("an install with only an odometer on disk is recorded as having prior data")
    func upgraderWithOdometer() throws {
        let defaults = Self.sandbox { _ in
            var log = OdometerLog()
            log.setSlot(.init(words: 12, distanceMeters: 300, runs: 2), for: "device-before")
            try? log.save(to: AppModel.supportFileURL("odometer.json"))
        }
        #expect(defaults.object(forKey: AppSettings.defaultsKey) == nil)
        _ = Self.launch(Self.running([1, 37], 63))
        let bytes = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        #expect(String(decoding: bytes, as: UTF8.self).contains(#""priorDataPresent":true"#))
    }
}
