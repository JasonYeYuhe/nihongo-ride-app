import Testing
import Foundation
import VocabKit
import SettingsKit
import SyncKit
import ReviewKit
import JournalKit
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

    /// macOS builds, as `project.yml` numbers them: 1.37 is 62, so 1.38 would be 63.
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
        let model = Self.launch(Self.running([1, 37], 62))
        #expect(model.installCohortAtLaunch == .absent)
        let bytes = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        #expect(String(decoding: bytes, as: UTF8.self)
                == #"{"firstSeenBuild":62,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#)
        // …and the settings blob this launch saved is what a later launch will count as prior data.
        #expect(defaults.object(forKey: AppSettings.defaultsKey) != nil)
    }

    @Test("a second launch, even of a newer build, reads the first marker and writes nothing")
    func secondLaunch() throws {
        let defaults = Self.sandbox()
        _ = Self.launch(Self.running([1, 37], 62))
        let first = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        let again = Self.launch(Self.running([1, 38], 63))
        #expect(again.installCohortAtLaunch?.marker?.firstSeenBuild == 62)
        #expect(again.installCohortAtLaunch?.marker?.firstSeenVersion.components == [1, 37])
        #expect(again.installCohortAtLaunch?.marker?.priorDataPresent == false)
        #expect(defaults.data(forKey: "NihongoRide.installCohort.v1") == first)
    }

    @Test("an install upgrading with saved settings and no marker is recorded as having prior data")
    func upgraderWithSettings() throws {
        let defaults = Self.sandbox { AppSettings.default.sanitized().save(to: $0) }
        let model = Self.launch(Self.running([1, 37], 62))
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
        _ = Self.launch(Self.running([1, 37], 62))
        let bytes = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        #expect(String(decoding: bytes, as: UTF8.self).contains(#""priorDataPresent":true"#))
    }

    /// The rule is "an odometer in ANY state but missing" (`InstallCohort.priorDataPresent`'s
    /// doc), and the only odometer test above writes a valid one, so `outcome == .loaded` in place
    /// of `outcome != .missing` passed every suite (review r1, mutation-1). Each state the loader
    /// can report for a file that exists, with no settings blob beside it.
    @Test("an odometer that is undecodable or unreadable still counts as prior data",
          arguments: ["undecodable", "unreadable"])
    func upgraderWithDamagedOdometer(_ state: String) throws {
        var odometerURL: URL?
        let defaults = Self.sandbox { _ in
            let url = AppModel.supportFileURL("odometer.json")
            odometerURL = url
            try? Data([0xFF, 0x00, 0x7B, 0x22]).write(to: url)   // not JSON at all
            if state == "unreadable" {
                try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            }
        }
        let url = try #require(odometerURL)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        #expect(defaults.object(forKey: AppSettings.defaultsKey) == nil, "the sandbox has settings")
        // The arrangement is a claim: check the file is in the state named, before the launch.
        #expect(FileManager.default.fileExists(atPath: url.path))
        let readable = (try? Data(contentsOf: url)) != nil
        #expect(readable == (state == "undecodable"), "\(state): the odometer is readable = \(readable)")

        _ = Self.launch(Self.running([1, 37], 62))
        if state == "undecodable" {
            // `LossyLoad` quarantines bytes it cannot decode: the loader really saw `.undecodable`.
            let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            #expect(siblings.contains { $0.hasPrefix("odometer.json") && $0.contains("corrupt") },
                    "no quarantine copy, so the load was not undecodable: \(siblings)")
        }
        let bytes = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        #expect(String(decoding: bytes, as: UTF8.self)
                == #"{"firstSeenBuild":62,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":true,"schema":1}"#,
                "\(state): an odometer this install had was not counted")
    }

    /// The documented LIMIT of 1.37's prior-data rule, pinned so the doc stays true: an install
    /// last opened on 1.0 or 1.1 kept only `review.json` and `history.json` (the settings key and
    /// `odometer.json` both arrived in v1.2), and 1.37 counts neither, so it records `false`. Not a
    /// property anyone wants — the orchestrator kept it for 1.37 because 1.37's markers are granted
    /// on their build alone (review r1, marker-1). If the rule is widened on purpose, this goes red:
    /// update `InstallCohort.priorDataPresent`'s doc with it.
    @Test("an install last opened on 1.1 (review and history only) records priorDataPresent false")
    func lastOpenedOn11() throws {
        let defaults = Self.sandbox { _ in
            var review = ReviewStore()
            _ = review.record(entryID: "a", outcome: TypingOutcome(completed: true))
            try? review.save(to: AppModel.supportFileURL("review.json"))
            var journal = RideJournal()
            journal.append(ReviewPromptWiringTests.record(daysAgo: 30))
            try? journal.save(to: AppModel.supportFileURL("history.json"))
        }
        #expect(defaults.object(forKey: AppSettings.defaultsKey) == nil)
        #expect(!FileManager.default.fileExists(atPath: AppModel.supportFileURL("odometer.json").path))
        let model = Self.launch(Self.running([1, 37], 62))
        // The seed is a claim: both stores loaded, so this install does have data.
        #expect(model.reviewStore.count == 1, "the review seed did not load")
        #expect(model.journal.count == 1, "the journal seed did not load")
        let bytes = try #require(defaults.data(forKey: "NihongoRide.installCohort.v1"))
        #expect(String(decoding: bytes, as: UTF8.self)
                == #"{"firstSeenBuild":62,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#,
                "1.37's prior-data rule changed; update InstallCohort.priorDataPresent's doc to match")
    }

    /// The property's doc says a launch that touches nothing of the user's neither reads nor
    /// writes the marker and leaves it nil, and E3 reads that nil as "no marker step ran" (its
    /// §5.5 row 10). Every test above runs a NON-isolated launch, so deleting the
    /// `touchesNothingOfTheUsers` guard passed them all (review r1, marker-4). The sandbox's own
    /// suite stays the settings store here, so a marker the guard let through would land in it.
    @Test("a UI-test or capture launch neither reads nor writes the marker, and reports nil",
          arguments: ["uiTest", "capture"])
    func isolatedLaunchHasNoMarker(_ kind: String) throws {
        let defaults = Self.sandbox()
        let savedTarget = Screenshotter.captureTarget
        let savedCapturing = Screenshotter.isCapturing
        defer {
            AppModel.isUITestOverride = nil
            Screenshotter.captureTarget = savedTarget
            Screenshotter.isCapturing = savedCapturing
        }
        if kind == "uiTest" {
            AppModel.isUITestOverride = true
        } else {
            AppModel.isUITestOverride = false
            Screenshotter.captureTarget = "/tmp/install-cohort-wiring"
            Screenshotter.isCapturing = true
        }
        #expect(AppModel.currentIsolation.touchesNothingOfTheUsers, "\(kind): the launch is not isolated")
        #expect(AppModel.settingsStore == defaults, "\(kind): the store this test reads is not the one init writes")

        let model = Self.launch(Self.running([1, 37], 62))
        #expect(model.installCohortAtLaunch == nil, "\(kind): the marker step ran: \(String(describing: model.installCohortAtLaunch))")
        #expect(defaults.object(forKey: "NihongoRide.installCohort.v1") == nil, "\(kind): a marker was written")
    }
}
