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

    /// A marker exactly as 1.37 writes it on macOS — version 1.37, build 62 (`project.yml`'s
    /// `NihongoRide` target, `CURRENT_PROJECT_VERSION: "62"`) — spelled out byte for byte. These
    /// bytes outlive 1.37 (E3 reads them), so they are the real build, not a hypothetical one.
    static let markerJSON137 =
        #"{"firstSeenBuild":62,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#

    /// The same on iOS — version 1.37, build 63 (`NihongoRideiOS`, `CURRENT_PROJECT_VERSION: "63"`).
    static let markerJSON137iOS =
        #"{"firstSeenBuild":63,"firstSeenVersion":[1,37],"platform":"iOS","priorDataPresent":false,"schema":1}"#

    /// A defaults suite for one test (and one argument of a parameterised test), emptied before it
    /// is handed out. The name is FIXED per checkout, test and argument, never a UUID: a UUID suite
    /// leaves a new plist in ~/Library/Preferences on every run (`removePersistentDomain` empties a
    /// file, it does not delete it), and those piled up by the hundred (review r2, marker-r2-3). A
    /// fixed name reuses one file. The checkout's digest keeps two clones running at once apart, and
    /// the argument keeps parameterised cases, which Swift Testing may run in parallel, apart.
    static func suite(_ argument: String = "", function: String = #function) -> (UserDefaults, String) {
        let name = suiteName(argument, function: function)
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    static func suiteName(_ argument: String = "", function: String = #function) -> String {
        // FNV-1a of the checkout's path: stable across processes, unlike `hashValue`.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in #filePath.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        let label = (function + (argument.isEmpty ? "" : "." + argument))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "." }
        return "InstallCohortTests.\(String(hash, radix: 16)).\(String(String.UnicodeScalarView(label)))"
    }

    @Test("suite names are fixed per test and argument, so a rerun reuses its plist instead of adding one")
    func suiteNamesAreFixed() {
        let first = Self.suiteName("x", function: "someTest()")
        #expect(first == Self.suiteName("x", function: "someTest()"), "two calls named two suites: a new plist per run")
        #expect(first != Self.suiteName("y", function: "someTest()"), "two arguments share one suite")
        #expect(first != Self.suiteName("x", function: "otherTest()"), "two tests share one suite")
        #expect(first.hasPrefix("InstallCohortTests.") && !first.contains("-"), "\(first) is not the fixed form")
    }

    // MARK: - Write-once

    @Test("an absent marker is written once, with exactly the running build and the prior-data flag")
    func absentIsWritten() throws {
        let decision = Cohort.decide(stored: .nothing, running: Self.running("1.37", 62),
                                     priorDataPresent: false)
        #expect(decision.observation == .absent)
        let bytes = try #require(decision.write)
        #expect(String(decoding: bytes, as: UTF8.self) == Self.markerJSON137)
    }

    @Test("a present marker is not written again by the same build")
    func presentIsNotRewritten() {
        let stored = Data(Self.markerJSON137.utf8)
        let decision = Cohort.decide(stored: .bytes(stored), running: Self.running("1.37", 62),
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
        for (version, build) in [("1.38", 63), ("1.37", 62), ("1.36", 61)] {
            let decision = Cohort.decide(stored: .bytes(stored), running: Self.running(version, build),
                                         priorDataPresent: false)
            #expect(decision.write == nil, "\(version) (\(build)) rewrote the marker")
        }
    }

    @Test("a launch that sees different prior data does not rewrite it")
    func priorDataDoesNotRewrite() {
        let stored = Data(Self.markerJSON137.utf8)   // priorDataPresent: false
        let decision = Cohort.decide(stored: .bytes(stored), running: Self.running("1.37", 62),
                                     priorDataPresent: true)
        #expect(decision.write == nil)
    }

    @Test("through UserDefaults: the bytes of the first launch survive every later launch, up and down")
    func launchSequenceThroughDefaults() throws {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }

        let first = Cohort.recordLaunch(in: defaults, running: Self.running("1.37", 62),
                                        priorDataPresent: false)
        #expect(first == .absent)
        let written = try #require(defaults.data(forKey: Cohort.defaultsKey))
        #expect(String(decoding: written, as: UTF8.self) == Self.markerJSON137)

        let expected = Cohort.Marker(firstSeen: Self.running("1.37", 62), priorDataPresent: false)
        for (version, build, prior) in [("1.38", 63, true), ("1.36", 61, true), ("1.40", 70, false),
                                        ("1.37", 62, true)] {
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
        let fresh = Cohort.recordLaunch(in: defaults, running: Self.running("1.38", 63),
                                        priorDataPresent: false)
        #expect(fresh == .absent)
        #expect(defaults.data(forKey: Cohort.defaultsKey) != nil)

        // Present: the observation is the stored value, field by field, as written by hand.
        let (other, otherName) = Self.suite("other")
        defer { other.removePersistentDomain(forName: otherName) }
        other.set(Data(#"{"firstSeenBuild":62,"firstSeenVersion":[1,36],"platform":"iOS","priorDataPresent":true,"schema":1}"#.utf8),
                  forKey: Cohort.defaultsKey)
        let observed = Cohort.recordLaunch(in: other, running: Self.running("1.37", 63, .iOS),
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
        ("future schema", Data(#"{"firstSeenBuild":62,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":2}"#.utf8)),
        ("missing field", Data(#"{"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("unknown platform", Data(#"{"firstSeenBuild":62,"firstSeenVersion":[1,37],"platform":"visionOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("empty version", Data(#"{"firstSeenBuild":62,"firstSeenVersion":[],"platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("negative build", Data(#"{"firstSeenBuild":-1,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
        ("version as a string", Data(#"{"firstSeenBuild":62,"firstSeenVersion":"1.37","platform":"macOS","priorDataPresent":false,"schema":1}"#.utf8)),
    ]

    @Test("unreadable bytes are reported as unreadable and never replaced by a fresh marker",
          arguments: unreadable.map(\.0))
    func unreadableIsLeftAlone(label: String) throws {
        let bytes = try #require(Self.unreadable.first { $0.0 == label }?.1)
        let decision = Cohort.decide(stored: .bytes(bytes), running: Self.running("1.37", 62),
                                     priorDataPresent: true)
        #expect(decision.observation == .unreadable)
        #expect(decision.write == nil)

        let (defaults, name) = Self.suite(label)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(bytes, forKey: Cohort.defaultsKey)
        let observed = Cohort.recordLaunch(in: defaults, running: Self.running("1.37", 62),
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
        let observed = Cohort.recordLaunch(in: defaults, running: Self.running("1.37", 62),
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

    /// Leading zeros are accepted and read as the integer they spell — the choice `Version
    /// .components` documents (a refused version would write no marker at all). Trailing zero
    /// COMPONENTS are the part kept as written (`trailingZerosAreEqual`).
    @Test("a leading zero inside a component is that component's integer: \"01.37\" is [1, 37]")
    func leadingZerosAreTheirInteger() throws {
        let plain = try #require(Cohort.Version("1.37"))
        for raw in ["01.37", "1.037", "001.0037"] {
            let padded = try #require(Cohort.Version(raw), "\"\(raw)\" was refused")
            #expect(padded.components == [1, 37], "\"\(raw)\" parsed as \(padded.components)")
            #expect(padded == plain)
            #expect(padded.description == "1.37")
        }
        #expect(try #require(Cohort.Version("1.037.0")).components == [1, 37, 0])
        #expect(try #require(Cohort.Version("0.0")).components == [0, 0])
    }

    @Test("only dot-separated ASCII digits parse",
          arguments: ["", ".", "1.", ".1", "1..2", "1.x", "-1", "+1", " 1.2", "1.2 ", "1.37b", "１.２", "1,2"])
    func malformedVersionsDoNotParse(_ raw: String) {
        #expect(Cohort.Version(raw) == nil, "\"\(raw)\" parsed")
    }

    @Test("the running build: integer version and integer build, or nothing")
    func runningParse() {
        #expect(Cohort.Running(marketingVersion: "1.37", build: "62", platform: .macOS)
                == Cohort.Running(version: Cohort.Version(components: [1, 37])!, build: 62, platform: .macOS))
        #expect(Cohort.Running(marketingVersion: "1.37", build: "63", platform: .iOS)
                == Cohort.Running(version: Cohort.Version(components: [1, 37])!, build: 63, platform: .iOS))
        #expect(Cohort.Running(marketingVersion: "1.37", build: "61.1", platform: .macOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37", build: "", platform: .macOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37", build: "-3", platform: .macOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37", build: nil, platform: .iOS) == nil)
        #expect(Cohort.Running(marketingVersion: nil, build: "63", platform: .iOS) == nil)
        #expect(Cohort.Running(marketingVersion: "1.37b", build: "63", platform: .iOS) == nil)
    }

    /// Every app and widget target's `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
    /// `project.yml` must parse as a `Running`. A build the parser refuses ("64.1" is legal for
    /// Apple) writes no marker, and the install's first marker then comes from a LATER build —
    /// the shape the marker exists to refuse. `AppModel` logs that case at launch; this keeps it
    /// from shipping. The expected count is written by hand: two apps and two widgets.
    ///
    /// The bundle does not read those settings directly: it reads `CFBundleShortVersionString` and
    /// `CFBundleVersion` from each target's `info.properties`, which xcodegen writes into the
    /// Info.plist the archive ships. So those must still EXPAND the two settings — a literal written
    /// there ("64.1") would ship while the settings above stayed green (review r2, marker-r2-4).
    @Test("every version and build project.yml ships parses as the marker's running build")
    func projectVersionsParse() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        func values(_ key: String) -> [String] {
            project.split(separator: "\n").compactMap { line -> String? in
                let live = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                let trimmed = live.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(key + ":") else { return nil }
                return trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        let versions = values("MARKETING_VERSION"), builds = values("CURRENT_PROJECT_VERSION")
        #expect(versions.count == 4 && builds.count == 4,
                "project.yml sets \(versions.count) versions and \(builds.count) builds — the scan is misdirected")
        for (version, build) in zip(versions, builds) {
            #expect(Cohort.Running(marketingVersion: version, build: build, platform: .macOS) != nil,
                    "project.yml ships version \"\(version)\" build \"\(build)\", which writes no install-cohort marker")
        }
        let shortVersions = values("CFBundleShortVersionString"), bundleVersions = values("CFBundleVersion")
        #expect(shortVersions == Array(repeating: "$(MARKETING_VERSION)", count: 4),
                "a target's info.properties no longer expands MARKETING_VERSION: \(shortVersions)")
        #expect(bundleVersions == Array(repeating: "$(CURRENT_PROJECT_VERSION)", count: 4),
                "a target's info.properties no longer expands CURRENT_PROJECT_VERSION: \(bundleVersions)")
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
        let written = try #require(Cohort.decide(stored: .nothing, running: Self.running("1.37", 63, .iOS),
                                                 priorDataPresent: false).write)
        #expect(String(decoding: written, as: UTF8.self) == Self.markerJSON137iOS)
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
        let written = try #require(Cohort.decide(stored: .nothing, running: Self.running("1.37", 62),
                                                 priorDataPresent: prior).write)
        #expect(String(decoding: written, as: UTF8.self)
                == #"{"firstSeenBuild":62,"firstSeenVersion":[1,37],"platform":"macOS","priorDataPresent":\#(prior),"schema":1}"#)
    }

    // MARK: - Never synced, never sent

    @Test("whatever decide writes reads back as present, with the running build — never as unreadable")
    func writtenBytesReadBack() throws {
        for (version, components, build, platform, prior) in [("1.37", [1, 37], 62, Cohort.Platform.macOS, false),
                                                              ("1.37", [1, 37], 63, .iOS, true),
                                                              ("2.0", [2, 0], 1, .iOS, false)] {
            let decision = Cohort.decide(stored: .nothing, running: Self.running(version, build, platform),
                                         priorDataPresent: prior)
            let bytes = try #require(decision.write)
            #expect(!bytes.isEmpty)
            guard case .present(let marker) = Cohort.observe(.bytes(bytes)) else {
                Issue.record("\(version) (\(build)) wrote bytes that do not read back as present"); continue
            }
            #expect(marker.firstSeenVersion.components == components, "\(version) read back as \(marker.firstSeenVersion)")
            #expect(marker.firstSeenBuild == build)
            #expect(marker.platform == platform)
            #expect(marker.priorDataPresent == prior)
        }
    }

    /// The marker is written in `AppModel.init`, and its reads assume the defaults store is readable
    /// then: `Stored.read` cannot tell an empty domain from one it could not read (before the first
    /// unlock, protected data reads as nothing), and `.nothing` is the one input `decide` writes on.
    /// This test closes the launch paths that a `project.yml` key opens — background modes, push,
    /// background tasks. Adding any of them (CloudKitSyncController's note on moving to push-driven
    /// sync names `aps-environment`) must reopen that question, so this goes red.
    ///
    /// **It does not close iOS prewarming**, which needs no key: iOS may run an app's launch sequence
    /// ahead of use, and `NihongoRideApp` builds `AppModel` eagerly (`@State private var model =
    /// AppModel()`). Whether that init falls inside a prewarm before the first unlock is UNMEASURED
    /// — it needs one device check (reboot, wait for a prewarm, log `isProtectedDataAvailable` in
    /// `AppModel.init`). For 1.37 it costs nothing: a marker minted there holds what 1.37 writes
    /// anyway, and E3 grants every 1.37/1.38 marker on its build alone. The guard is E3's:
    /// DESIGN-E3-SAMPLER §5.5 row 0a writes neither a marker nor a grant on a launch whose own
    /// stores read `.unreadable` (or whose settings key reads nil beside existing support files),
    /// which is that window's signature. 1.37 keeps its launch path unchanged (review r2,
    /// marker-r2-2, both refuters).
    @Test("no background launch path exists, so the marker is never decided before the first unlock")
    func noLaunchBeforeFirstUnlock() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let live = project.split(separator: "\n")
            .map { $0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "" }
            .joined(separator: "\n")
        for key in ["UIBackgroundModes", "aps-environment", "BGTaskSchedulerPermittedIdentifiers"] {
            #expect(!live.contains(key), "project.yml sets \(key): the install-cohort marker may then be decided before the first unlock")
        }
    }

    /// The marker is local. Nothing in `Sources/` may name its key except this module; nothing may
    /// name the type, or the model's `installCohortAtLaunch` that holds it, except this module and
    /// the one launch call in `AppModel`; and nothing may sweep the defaults domain wholesale —
    /// into iCloud key-value storage, an export, or anywhere else. (SyncKit cannot reach it at
    /// compile time either: it does not depend on SettingsKit — see Package.swift.)
    ///
    /// The name scans are CASE-INSENSITIVE ("installcohort" in any spelling), because the type is
    /// `InstallCohort` and the property is `installCohortAtLaunch`: a reader elsewhere that writes
    /// `model.installCohortAtLaunch?.marker?.firstSeenBuild` names no type, and a case-sensitive
    /// scan for the type passed it. The API scan covers the sweeps: iCloud key-value storage,
    /// `dictionaryRepresentation`, `persistentDomain(forName:)`, the whole `CFPreferences` family
    /// (`CFPreferencesCopyKeyList`, `CFPreferencesCopyMultiple`, …), and any path into
    /// `Library/Preferences`, where the defaults plist can be read as a file.
    ///
    /// Comments are stripped before the API scan so prose can name what is forbidden (`codeOnly`,
    /// which keeps string literals whole, so a `"https://…"` on a line no longer hides the rest of
    /// it), and whitespace is removed, so a call split across lines (`persistentDomain(\n forName:`)
    /// is still one string. The name scans read comments too, which is stricter.
    ///
    /// **Uses, not just files** (review r2, marker-r2-1). `AppModel.swift` is a sanctioned holder,
    /// and it is also the file that builds the CloudKit change payload and the widget snapshot, so
    /// a second reader there passed a per-file check. Its code is pinned to exactly the uses that
    /// exist: `installCohortAtLaunch` twice (the declaration and the one assignment),
    /// `installCohortRunningOverride` twice (the declaration and the one read), and nine names in
    /// all. E3 changes these counts on purpose, and updates them here when it does.
    ///
    /// **What it cannot see**, stated so it is not read as more: a key or selector built at run
    /// time (`"NihongoRide." + "install…"`, `NSSelectorFromString`), Objective-C or C anywhere,
    /// non-Swift files (plists, entitlements, scripts), code outside `Sources/` (every shipping
    /// target's Swift is under it today, per `project.yml`; a target added elsewhere would not be
    /// read), and — for the comment stripper — a string literal nested inside a string
    /// interpolation (`"\(x ? "a//b" : "")"`), where a `//` can still cut the rest of that line. It
    /// proves the names are not reached; it does not prove the bytes cannot be.
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

        func holders(_ name: String) -> [String] {
            files.filter { $0.value.range(of: name, options: .caseInsensitive) != nil }.keys.sorted()
        }
        #expect(holders("NihongoRide.installCohort") == ["SettingsKit/InstallCohort.swift"])
        // The type and every property named after it, in any case: only the module and the launch.
        #expect(holders("installcohort") == ["NihongoRideApp/AppModel.swift", "SettingsKit/InstallCohort.swift"])
        // The pre-launch observation has no reader until E3: E3 adds its file here, deliberately.
        #expect(holders("installCohortAtLaunch") == ["NihongoRideApp/AppModel.swift"])

        // Uses in AppModel, counted in its code (comments stripped). Hand-counted at 2cf6161.
        let appModel = Self.codeOnly(try #require(files["NihongoRideApp/AppModel.swift"]))
        func uses(_ name: String) -> Int {
            appModel.lowercased().components(separatedBy: name.lowercased()).count - 1
        }
        #expect(uses("installCohortAtLaunch") == 2, "AppModel uses installCohortAtLaunch \(uses("installCohortAtLaunch")) times — a new reader?")
        #expect(appModel.contains("private(set) var installCohortAtLaunch: InstallCohort.Observation?"))
        #expect(appModel.contains("installCohortAtLaunch = InstallCohort.recordLaunch("))
        #expect(uses("installCohortRunningOverride") == 2)
        #expect(uses("installcohort") == 9, "AppModel names the marker \(uses("installcohort")) times in code, not 9")

        for (path, source) in files {
            let body = Self.codeOnly(source).replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            for sweep in ["NSUbiquitousKeyValueStore", "dictionaryRepresentation", ".persistentDomain(forName",
                          "CFPreferences", "Library/Preferences"] {
                #expect(body.range(of: sweep, options: .caseInsensitive) == nil,
                        "\(path) uses \(sweep), which could carry the marker off the device")
            }
        }
    }

    /// Swift source with its comments removed and everything else kept: `//` and nested `/* */`
    /// comments go; string literals — plain, multi-line `"""`, and raw `#"…"#` — are kept whole, so
    /// a `//` inside one is not read as a comment. Known limit: a string nested inside an
    /// interpolation ends the outer string early (stated on the scan above).
    static func codeOnly(_ source: String) -> String {
        let s = Array(source.unicodeScalars)
        var out = String.UnicodeScalarView()
        func starts(_ literal: String, at k: Int) -> Bool {
            let l = Array(literal.unicodeScalars)
            return k + l.count <= s.count && Array(s[k ..< k + l.count]) == l
        }
        var i = 0
        while i < s.count {
            if starts("//", at: i) {
                while i < s.count && s[i] != "\n" { i += 1 }
                continue
            }
            if starts("/*", at: i) {
                var depth = 0
                repeat {
                    if starts("/*", at: i) { depth += 1; i += 2 }
                    else if starts("*/", at: i) { depth -= 1; i += 2 }
                    else { i += 1 }
                } while depth > 0 && i < s.count
                out.append(" ")
                continue
            }
            var j = i, hashes = 0
            while j < s.count && s[j] == "#" { hashes += 1; j += 1 }
            if j < s.count && s[j] == "\"" {
                let quotes = starts("\"\"\"", at: j) ? 3 : 1
                let close = String(repeating: "\"", count: quotes) + String(repeating: "#", count: hashes)
                let closeCount = close.unicodeScalars.count
                out.append(contentsOf: s[i ..< j + quotes])
                i = j + quotes
                while i < s.count {
                    if hashes == 0 && s[i] == "\\" {
                        out.append(contentsOf: s[i ..< min(i + 2, s.count)]); i += 2; continue
                    }
                    if starts(close, at: i) { out.append(contentsOf: s[i ..< i + closeCount]); i += closeCount; break }
                    out.append(s[i]); i += 1
                }
                continue
            }
            out.append(s[i]); i += 1
        }
        return String(out)
    }

    /// The stripper is an instrument, so it is checked before its silence is believed.
    @Test("codeOnly drops comments and keeps strings — a // inside a literal hides nothing")
    func codeOnlyIsCalibrated() {
        let source = #"""
            let a = "https://example.com"; let b = NSUbiquitousKeyValueStore.default // NSUbiquitousKeyValueStore
            /* CFPreferences /* nested */ dictionaryRepresentation */ let c = 1
            let d = #"raw "quoted" // still a string"#; let e = "esc \" // still" + "x"
            let f = """
              multi // line
              """
            """#
        let code = Self.codeOnly(source)
        #expect(code.components(separatedBy: "NSUbiquitousKeyValueStore").count - 1 == 1,
                "the code after a URL literal was cut, or the comment was kept: \(code)")
        #expect(!code.contains("CFPreferences") && !code.contains("dictionaryRepresentation") && !code.contains("nested"),
                "a block comment survived: \(code)")
        #expect(code.contains("let c = 1"), "code after a block comment was lost")
        #expect(code.contains(##"#"raw "quoted" // still a string"#"##), "a raw string was cut")
        #expect(code.contains(#""esc \" // still" + "x""#), "an escaped quote ended the string")
        #expect(code.contains("multi // line"), "a multi-line string was cut")
    }
}
