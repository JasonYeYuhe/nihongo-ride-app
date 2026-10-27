import Testing
import Foundation
@testable import SettingsKit

/// The install-cohort marker (v1.37 P0-12). Every expected value below is written out by hand — as
/// a JSON literal, or as the integers it should hold — never derived from `decide` or `observe`.
@Suite("Install-cohort marker")
struct InstallCohortTests {

    typealias Cohort = InstallCohort

    static func running(_ version: String, _ build: Int, _ platform: Cohort.Platform = .macOS) -> Cohort.Running {
        Cohort.Running(version: Cohort.Version(version)!, build: build, platform: platform)
    }

    /// A marker as 1.37 (mac 63) writes it, spelled out byte for byte.
    static let markerJSON137 =
        #"{"firstSeenBuild":63,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#

    static func suite() -> (UserDefaults, String) {
        let name = "InstallCohortTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    // MARK: - Write-once

    @Test("an absent marker is written once, with exactly the running build and the prior-data flag")
    func absentIsWritten() throws {
        let decision = Cohort.decide(stored: .nothing, running: Self.running("1.37", 63),
                                     priorDataPresent: false)
        #expect(decision.observation == .absent)
        let bytes = try #require(decision.write)
        #expect(String(decoding: bytes, as: UTF8.self) == Self.markerJSON137)
    }

    @Test("a present marker is not written again by the same build")
    func presentIsNotRewritten() {
        let stored = Data(Self.markerJSON137.utf8)
        let decision = Cohort.decide(stored: .bytes(stored), running: Self.running("1.37", 63),
                                     priorDataPresent: false)
        #expect(decision.write == nil)
    }

    @Test("a newer build never raises the first-seen version or build")
    func neverRaisedByNewerBuild() {
        let stored = Data(Self.markerJSON137.utf8)
        for (version, build) in [("1.37.1", 63), ("1.38", 64), ("1.40", 70), ("2.0", 100)] {
            let decision = Cohort.decide(stored: .bytes(stored), running: Self.running(version, build),
                                         priorDataPresent: true)
            #expect(decision.write == nil, "\(version) (\(build)) rewrote the marker")
        }
    }

    @Test("an older build after a downgrade never lowers it either")
    func neverLoweredByOlderBuild() {
        let stored = Data(#"{"firstSeenBuild":65,"firstSeenVersion":[1,39],"platform":"macOS","priorDataPresent":true,"schema":1}"#.utf8)
        for (version, build) in [("1.38", 64), ("1.37", 63), ("1.36", 61)] {
            let decision = Cohort.decide(stored: .bytes(stored), running: Self.running(version, build),
                                         priorDataPresent: false)
            #expect(decision.write == nil, "\(version) (\(build)) rewrote the marker")
        }
    }

    @Test("a launch that sees different prior data does not rewrite it")
    func priorDataDoesNotRewrite() {
        let stored = Data(Self.markerJSON137.utf8)   // priorDataPresent: false
        let decision = Cohort.decide(stored: .bytes(stored), running: Self.running("1.37", 63),
                                     priorDataPresent: true)
        #expect(decision.write == nil)
    }

    @Test("through UserDefaults: the bytes of the first launch survive every later launch, up and down")
    func launchSequenceThroughDefaults() throws {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }

        let first = Cohort.recordLaunch(in: defaults, running: Self.running("1.37", 63),
                                        priorDataPresent: false)
        #expect(first == .absent)
        let written = try #require(defaults.data(forKey: Cohort.defaultsKey))
        #expect(String(decoding: written, as: UTF8.self) == Self.markerJSON137)

        let expected = Cohort.Marker(firstSeen: Self.running("1.37", 63), priorDataPresent: false)
        for (version, build, prior) in [("1.38", 64, true), ("1.36", 61, true), ("1.40", 70, false),
                                        ("1.37", 63, true)] {
            let observed = Cohort.recordLaunch(in: defaults, running: Self.running(version, build),
                                               priorDataPresent: prior)
            #expect(observed == .present(expected), "\(version): observed \(observed)")
            #expect(defaults.data(forKey: Cohort.defaultsKey) == written,
                    "\(version) (\(build)) changed the stored bytes")
        }
    }

    @Test("a build that cannot read its own version writes nothing — no guessed first-seen")
    func unknownRunningWritesNothing() {
        let decision = Cohort.decide(stored: .nothing, running: nil, priorDataPresent: true)
        #expect(decision.observation == .absent)
        #expect(decision.write == nil)
    }

    // MARK: - The pre-launch observation

    @Test("the observation is the marker as it stood BEFORE this launch's write")
    func observationIsPreLaunch() throws {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }

        // Fresh: the key holds a marker afterwards, but the observation says there was none.
        let fresh = Cohort.recordLaunch(in: defaults, running: Self.running("1.38", 64),
                                        priorDataPresent: false)
        #expect(fresh == .absent)
        #expect(defaults.data(forKey: Cohort.defaultsKey) != nil)

        // Present: the observation is the stored value, field by field, as written by hand.
        let (other, otherName) = Self.suite()
        defer { other.removePersistentDomain(forName: otherName) }
        other.set(Data(#"{"firstSeenBuild":62,"firstSeenVersion":[1,36],"platform":"iOS","priorDataPresent":true,"schema":1}"#.utf8),
                  forKey: Cohort.defaultsKey)
        let observed = Cohort.recordLaunch(in: other, running: Self.running("1.37", 64, .iOS),
                                           priorDataPresent: false)
        let marker = try #require(observed.marker)
        #expect(marker.schema == 1)
        #expect(marker.firstSeenVersion.components == [1, 36])
        #expect(marker.firstSeenBuild == 62)
        #expect(marker.platform == .iOS)
        #expect(marker.priorDataPresent == true)
    }

    // MARK: - Unreadable bytes

    static let unreadable: [(String, Data)] = [
        ("garbage", Data([0xFF, 0x00, 0x7B])),
        ("empty", Data()),
        ("not an object", Data("[1,37]".utf8)),
        ("future schema", Data(#"{"firstSeenBuild":63,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":2}"#.utf8)),
        ("missing field", Data(#"{"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("unknown platform", Data(#"{"firstSeenBuild":63,"firstSeenVersion":[1,37],"platform":"visionOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("empty version", Data(#"{"firstSeenBuild":63,"firstSeenVersion":[],"platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("negative build", Data(#"{"firstSeenBuild":-1,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("version as a string", Data(#"{"firstSeenBuild":63,"firstSeenVersion":"1.37","platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
    ]

    @Test("unreadable bytes are reported as unreadable and never replaced by a fresh marker",
          arguments: unreadable.map(\.0))
    func unreadableIsLeftAlone(label: String) throws {
        let bytes = try #require(Self.unreadable.first { $0.0 == label }?.1)
        let decision = Cohort.decide(stored: .bytes(bytes), running: Self.running("1.37", 63),
                                     priorDataPresent: true)
        #expect(decision.observation == .unreadable)
        #expect(decision.write == nil)

        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(bytes, forKey: Cohort.defaultsKey)
        let observed = Cohort.recordLaunch(in: defaults, running: Self.running("1.37", 63),
                                           priorDataPresent: true)
        #expect(observed == .unreadable)
        #expect(defaults.data(forKey: Cohort.defaultsKey) == bytes, "\(label): the bytes were replaced")
        // No quarantine copy either: the key itself is left as the evidence.
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(Cohort.defaultsKey) }
                == [Cohort.defaultsKey])
    }

    @Test("a stored value that is not Data is unreadable, not absent, and is not overwritten")
    func notDataIsUnreadable() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("1.37", forKey: Cohort.defaultsKey)
        #expect(Cohort.Stored.read(from: defaults) == .notData)
        let observed = Cohort.recordLaunch(in: defaults, running: Self.running("1.37", 63),
                                           priorDataPresent: false)
        #expect(observed == .unreadable)
        #expect(defaults.string(forKey: Cohort.defaultsKey) == "1.37")
    }

    // MARK: - Integer versions

    @Test("versions compare as integers, not strings")
    func integerOrdering() throws {
        func v(_ s: String) throws -> Cohort.Version { try #require(Cohort.Version(s)) }
        #expect(try v("1.4") < v("1.40"))
        #expect(try v("1.9") < v("1.10"))
        #expect(try !(v("1.10") < v("1.9")))
        #expect(try v("1.5") < v("1.40"))
        #expect(try v("1.36") < v("1.36.1"))
        #expect(try v("1.36.1") < v("1.40"))
        #expect(try v("1.99") < v("2.0"))
        // The ascending chain the grandfather rule will meet, sorted by integers.
        let shuffled = try ["1.40", "1.10", "1.36.1", "1.4", "1.9", "1.36"].map(v)
        #expect(shuffled.sorted().map(\.description) == ["1.4", "1.9", "1.10", "1.36", "1.36.1", "1.40"])
    }

    @Test("\"1.36\" == \"1.36.0\": missing trailing components are zero")
    func trailingZerosAreEqual() throws {
        let short = try #require(Cohort.Version("1.36"))
        let long = try #require(Cohort.Version("1.36.0"))
        #expect(short == long)
        #expect(!(short < long) && !(long < short))
        // …but stored as parsed, not normalised.
        #expect(short.components == [1, 36])
        #expect(long.components == [1, 36, 0])
        #expect(try #require(Cohort.Version("1.36.0.1")) > short)
    }

    @Test("only dot-separated ASCII digits parse",
          arguments: ["", ".", "1.", ".1", "1..2", "1.x", "-1", "+1", " 1.2", "1.2 ", "1.37b", "１.２", "1,2"])
    func malformedVersionsDoNotParse(_ raw: String) {
        #expect(Cohort.Version(raw) == nil, "\"\(raw)\" parsed")
    }

    @Test("the running build: integer version and integer build, or nothing")
    func runningParse() {
        #expect(Cohort.Running(marketingVersion: "1.37", build: "63", platform: .macOS)
                == Cohort.Running(version: Cohort.Version(components: [1, 37])!, build: 63, platform: .macOS))
        #expect(Cohort.Running(marketingVersion: "1.37", build: "61.1", platform: .macOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37", build: "", platform: .macOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37", build: "-3", platform: .macOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37", build: nil, platform: .iOS) == nil)
        #expect(Cohort.Running(marketingVersion: nil, build: "63", platform: .iOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37b", build: "63", platform: .iOS) == nil)
    }

    // MARK: - Per platform

    @Test("builds compare only within a platform: mac 61 and iOS 62 are the same 1.36")
    func perPlatformBuild() throws {
        let mac = Cohort.Marker(firstSeen: Self.running("1.36", 61, .macOS), priorDataPresent: true)
        #expect(mac.firstSeenBuild(isBefore: 62, on: .macOS) == true)
        #expect(mac.firstSeenBuild(isBefore: 61, on: .macOS) == false)
        #expect(mac.firstSeenBuild(isBefore: 60, on: .macOS) == false)
        #expect(mac.firstSeenBuild(isBefore: 62, on: .iOS) == nil)

        let iOS = Cohort.Marker(firstSeen: Self.running("1.36", 62, .iOS), priorDataPresent: true)
        #expect(iOS.firstSeenBuild(isBefore: 62, on: .iOS) == false)
        #expect(iOS.firstSeenBuild(isBefore: 63, on: .iOS) == true)
        #expect(iOS.firstSeenBuild(isBefore: 99, on: .macOS) == nil)

        // And the platform the running build reports is the one stored.
        let written = try #require(Cohort.decide(stored: .nothing, running: Self.running("1.37", 64, .iOS),
                                                 priorDataPresent: false).write)
        #expect(String(decoding: written, as: UTF8.self)
                == #"{"firstSeenBuild":64,"firstSeenVersion":[1,37],"platform":"iOS","priorDataPresent":false,"schema":1}"#)
    }

    // MARK: - priorDataPresent

    @Test("prior data is an odometer OR saved settings")
    func priorDataTable() {
        #expect(Cohort.priorDataPresent(settingsStored: false, odometerStored: false) == false)
        #expect(Cohort.priorDataPresent(settingsStored: true, odometerStored: false) == true)
        #expect(Cohort.priorDataPresent(settingsStored: false, odometerStored: true) == true)
        #expect(Cohort.priorDataPresent(settingsStored: true, odometerStored: true) == true)
    }

    @Test("priorDataPresent true and false are each written as given", arguments: [true, false])
    func priorDataIsRecorded(_ prior: Bool) throws {
        let written = try #require(Cohort.decide(stored: .nothing, running: Self.running("1.37", 63),
                                                 priorDataPresent: prior).write)
        #expect(String(decoding: written, as: UTF8.self)
                == #"{"firstSeenBuild":63,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":\#(prior),"schema":1}"#)
    }

    // MARK: - Never synced, never sent

    /// The marker is local. Nothing in `Sources/` may name its key except this module, nothing may
    /// name the type except this module and the one launch call in `AppModel`, and nothing may sweep
    /// UserDefaults wholesale into iCloud key-value storage or an export. (SyncKit cannot reach it at
    /// compile time either: it does not depend on SettingsKit — see Package.swift.)
    ///
    /// Comments are stripped before the API scan so prose can name what is forbidden; the key and
    /// type scans read comments too, which is stricter.
    @Test("the key is reached from nowhere else — not SyncKit, not CloudKit, not an export")
    func theKeyIsReachedFromNowhereElse() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(atPath: sources.path))
        var files: [String: String] = [:]
        for case let path as String in enumerator where path.hasSuffix(".swift") {
            files[path] = try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
        }
        // The floor (97 files on 2026-10-27): the scan must have read the sync paths it clears.
        #expect(files.count >= 90, "the scan read \(files.count) files — it is misdirected")
        for required in ["SyncKit/SyncMerge.swift", "SyncKit/OdometerLog.swift",
                         "NihongoRideApp/CloudKitSyncController.swift", "NihongoRideApp/AppModel.swift",
                         "SettingsKit/InstallCohort.swift"] {
            #expect(files[required] != nil, "the scan did not read \(required)")
        }

        let keyHolders = files.filter { $0.value.contains("NihongoRide.installCohort") }.keys.sorted()
        #expect(keyHolders == ["SettingsKit/InstallCohort.swift"])

        let typeHolders = files.filter { $0.value.contains("InstallCohort") }.keys.sorted()
        #expect(typeHolders == ["NihongoRideApp/AppModel.swift", "SettingsKit/InstallCohort.swift"])

        func code(_ source: String) -> String {
            source.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    guard let slashes = line.range(of: "//") else { return line }
                    return line[line.startIndex ..< slashes.lowerBound]
                }
                .joined(separator: "\n")
        }
        for (path, source) in files {
            let body = code(source)
            for sweep in ["NSUbiquitousKeyValueStore", "dictionaryRepresentation", ".persistentDomain(forName"] {
                #expect(!body.contains(sweep), "\(path) uses \(sweep), which could carry the marker off the device")
            }
        }
    }
}
