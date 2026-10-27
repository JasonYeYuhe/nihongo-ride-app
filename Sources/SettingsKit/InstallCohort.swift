import Foundation

/// Which build this install first ran, written once and never again. (v1.37, PLAN-V1.37 §C P0-12.)
///
/// ## Why it exists before anything reads it
///
/// E3's grandfather rule (PLAN-V1.37 §E) must never depend on `AppTransaction` or the network: an
/// existing rider on a plane must lose nothing. Its rules 1–2 read THIS marker, so every launch of
/// a build that writes it turns an existing install into offline proof of when it arrived — before
/// E3 exists. It changes nothing offered and nothing about who arrives.
///
/// ## The three properties, and where each one is kept
///
/// * **Write-once / monotonic.** A present, readable marker is never rewritten — not by a newer
///   build, not by an older one after a downgrade, not by a launch that sees different prior data.
///   `decide` has exactly one branch that writes, and it is reached only when nothing at all is
///   stored. So no comparison is needed to keep "a later value never overwrites a smaller one":
///   a later value never overwrites ANY value.
/// * **Unreadable bytes stay where they are.** See `Observation.unreadable`.
/// * **Local only.** Its own `UserDefaults` key, never a field of `AppSettings`, never in a CloudKit
///   record, never sent. `InstallCohortTests.theKeyIsReachedFromNowhereElse` pins it by scanning
///   `Sources/`.
///
/// ## Why its own key, and not a field of `AppSettings`
///
/// `AppSettings` is loaded, sanitised and saved back on every launch, and its encoder writes only
/// the fields the RUNNING build knows. A first-seen field added there by 1.37 would be erased the
/// first time the install launched 1.36 again — and rewritten with 1.36 on the next 1.37 launch.
/// That is the one shape this marker exists to refuse.
public enum InstallCohort {

    /// Where the marker lives. Local `UserDefaults`, never synced, never transmitted.
    public static let defaultsKey = "NihongoRide.installCohort.v1"

    /// The schema this build writes and the only one it reads. A marker carrying any other value
    /// was written by a build that meant something else by it, so it is `unreadable` here and is
    /// left for that build to read.
    public static let schema = 1

    public enum Platform: String, Codable, Sendable, Equatable {
        case macOS, iOS

        /// The platform this binary was compiled for. An iPad app running on a Mac is an iOS binary
        /// with iOS build numbers, and reports `.iOS` — which is the comparison it needs.
        public static var current: Platform {
            #if os(macOS)
            return .macOS
            #else
            return .iOS
            #endif
        }
    }

    // MARK: - Version

    /// A marketing version as INTEGER components: "1.4" < "1.9" < "1.10" < "1.36" < "1.36.1" < "1.40".
    ///
    /// As strings, "1.10" < "1.9" and "1.4" < "1.40" < "1.5" — and a grandfather check that compared
    /// strings would put 1.10 before 1.9, which is the kind of mistake that reads as correct.
    ///
    /// **"1.36" == "1.36.0".** Missing trailing components compare as zero, which is how Apple orders
    /// `CFBundleShortVersionString`. Pinned by `InstallCohortTests.trailingZerosAreEqual`.
    public struct Version: Sendable, Comparable, Codable, CustomStringConvertible {

        /// As parsed, never normalised: a marker keeps the bytes the build that wrote it saw.
        public let components: [Int]

        /// Nil unless the string is one or more runs of ASCII digits separated by single dots:
        /// no sign, no whitespace, no empty component, no suffix ("1.37b").
        public init?(_ string: String) {
            let parts = string.split(separator: ".", omittingEmptySubsequences: false)
            var parsed: [Int] = []
            for part in parts {
                guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                      let value = Int(part) else { return nil }
                parsed.append(value)
            }
            self.init(components: parsed)
        }

        public init?(components: [Int]) {
            guard !components.isEmpty, components.allSatisfy({ $0 >= 0 }) else { return nil }
            self.components = components
        }

        public static func < (lhs: Version, rhs: Version) -> Bool {
            let count = max(lhs.components.count, rhs.components.count)
            for i in 0 ..< count {
                let l = i < lhs.components.count ? lhs.components[i] : 0
                let r = i < rhs.components.count ? rhs.components[i] : 0
                if l != r { return l < r }
            }
            return false
        }

        public static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

        public var description: String { components.map(String.init).joined(separator: ".") }

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode([Int].self)
            guard let version = Version(components: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "not a version: \(raw)"))
            }
            self = version
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(components)
        }
    }

    // MARK: - The running build

    /// What this launch is running. Nil from `init?` when the bundle does not say, or says
    /// something that is not an integer version and an integer build — a `swift run` binary has
    /// no Info.plist at all. Then nothing is written: a marker recording a guess would be read
    /// later as evidence.
    public struct Running: Sendable, Equatable {
        public let version: Version
        public let build: Int
        public let platform: Platform

        public init(version: Version, build: Int, platform: Platform) {
            self.version = version
            self.build = build
            self.platform = platform
        }

        /// From `CFBundleShortVersionString` and `CFBundleVersion`. The build must be a plain
        /// non-negative integer (61, 62): that is what `project.yml` sets on both platforms.
        public init?(marketingVersion: String?, build: String?, platform: Platform) {
            guard let marketingVersion, let version = Version(marketingVersion),
                  let build, !build.isEmpty, build.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let number = Int(build) else { return nil }
            self.init(version: version, build: number, platform: platform)
        }
    }

    // MARK: - The marker

    public struct Marker: Codable, Sendable, Equatable {
        public let schema: Int
        public let firstSeenVersion: Version
        /// Per platform: macOS and iOS number their builds separately (1.36 is mac 61 / iOS 62), so
        /// this means nothing without `platform`. See `firstSeenBuild(isBefore:on:)`.
        public let firstSeenBuild: Int
        public let platform: Platform
        /// Whether this install already had an odometer or saved settings when the marker was
        /// first written — so an install that predates the marker is known as one, rather than
        /// looking like a fresh install that happened to arrive on 1.37. See
        /// `InstallCohort.priorDataPresent(settingsStored:odometerStored:)`.
        public let priorDataPresent: Bool

        public init(firstSeen running: Running, priorDataPresent: Bool) {
            schema = InstallCohort.schema
            firstSeenVersion = running.version
            firstSeenBuild = running.build
            platform = running.platform
            self.priorDataPresent = priorDataPresent
        }

        private enum CodingKeys: String, CodingKey {
            case schema, firstSeenVersion, firstSeenBuild, platform, priorDataPresent
        }

        /// Strict, unlike `AppSettings`: every field is required, and a schema this build did not
        /// write is refused. A tolerant decode would fill a missing field with a default, and a
        /// defaulted first-seen build is an invented fact about when somebody arrived.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decode(Int.self, forKey: .schema)
            guard schema == InstallCohort.schema else {
                throw DecodingError.dataCorruptedError(forKey: .schema, in: c,
                                                       debugDescription: "schema \(schema) is not \(InstallCohort.schema)")
            }
            firstSeenVersion = try c.decode(Version.self, forKey: .firstSeenVersion)
            firstSeenBuild = try c.decode(Int.self, forKey: .firstSeenBuild)
            guard firstSeenBuild >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .firstSeenBuild, in: c,
                                                       debugDescription: "negative build")
            }
            platform = try c.decode(Platform.self, forKey: .platform)
            priorDataPresent = try c.decode(Bool.self, forKey: .priorDataPresent)
        }

        /// Whether this install was first seen on a build strictly earlier than `build` on
        /// `platform`. **Nil when the marker was written on the other platform**: build 61 on a Mac
        /// and build 62 on an iPhone are the same 1.36, so comparing across them answers a question
        /// nobody asked.
        public func firstSeenBuild(isBefore build: Int, on platform: Platform) -> Bool? {
            guard platform == self.platform else { return nil }
            return firstSeenBuild < build
        }

        /// Nil if encoding fails, so `decide` writes nothing and the next launch tries again. Empty
        /// bytes would be written once and then read as `.unreadable` forever, and write-once would
        /// keep them there.
        public func encoded() -> Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try? encoder.encode(self)
        }
    }

    // MARK: - What was stored before this launch

    /// What sat under the key before this launch touched it.
    public enum Stored: Sendable, Equatable {
        case nothing
        case bytes(Data)
        /// Something that is not `Data` — nothing in this app writes one, but a value of the wrong
        /// type is still a value, and `UserDefaults.data(forKey:)` would report it as nothing.
        case notData

        public static func read(from defaults: UserDefaults, key: String = defaultsKey) -> Stored {
            guard let object = defaults.object(forKey: key) else { return .nothing }
            guard let data = object as? Data else { return .notData }
            return .bytes(data)
        }
    }

    /// The marker **as it stood before this launch's write** — what E3's check must read (§E
    /// "Order"). Reading the key after the write instead would hand a legacy rider who reinstalled
    /// offline a marker minted a second ago: first-seen = this build, so no grant and no grace.
    public enum Observation: Sendable, Equatable {
        /// Nothing was stored. This launch writes the first marker (if it knows its own build).
        case absent
        case present(Marker)
        /// Something is stored and this build cannot read it: corrupt bytes, a value of the wrong
        /// type, or a schema / platform a later build wrote.
        ///
        /// **It is left exactly where it is, and nothing is written over it.** That is the house
        /// rule for unreadable records — never let a failed read become a write — in the one form
        /// that fits a write-once value. `EntitlementLedger.load` copies its unreadable blob to a
        /// `.unreadable` key because that record IS going to be overwritten by the next store read,
        /// so the evidence has to move first. Nothing ever overwrites this key, so the key itself is
        /// the quarantine: no copy, and no second key that would also have to be kept out of sync.
        ///
        /// Why not replace it with a fresh marker: a fresh marker says "first seen on this build",
        /// which for an install that has been here since 1.37 is a LATER first-seen written over an
        /// earlier one — the monotonic rule broken by the error path — and it would look like a new
        /// install to E3's rule 1. And a schema a later build wrote is readable by that build: after
        /// a downgrade and an upgrade again, the bytes are intact for it.
        ///
        /// The cost, stated: this install has no readable marker on this build, so E3 falls back to
        /// its rule 3 (`AppTransaction`) or the session grace — exactly where every install that
        /// predates 1.37 already stands. It is never worse off than having no marker.
        case unreadable

        public var marker: Marker? {
            if case .present(let marker) = self { return marker }
            return nil
        }
    }

    public static func observe(_ stored: Stored) -> Observation {
        switch stored {
        case .nothing: return .absent
        case .notData: return .unreadable
        case .bytes(let data):
            guard let marker = try? JSONDecoder().decode(Marker.self, from: data) else { return .unreadable }
            return .present(marker)
        }
    }

    // MARK: - The decision

    public struct Decision: Sendable, Equatable {
        /// The marker before this launch. Hand THIS to anything that grandfathers.
        public let observation: Observation
        /// Bytes to store under `defaultsKey`, or nil to write nothing.
        public let write: Data?
    }

    /// The whole rule, pure. `stored` is what was under the key BEFORE this launch; `running` is this
    /// build (nil if it could not be read); `priorDataPresent` is whether the install already had an
    /// odometer or saved settings before anything this launch wrote.
    public static func decide(stored: Stored, running: Running?, priorDataPresent: Bool) -> Decision {
        let observation = observe(stored)
        switch observation {
        case .absent:
            guard let running else { return Decision(observation: observation, write: nil) }
            return Decision(observation: observation,
                            write: Marker(firstSeen: running, priorDataPresent: priorDataPresent).encoded())
        case .present, .unreadable:
            // Write-once. Nothing that is already here is ever written over — see `Observation`.
            return Decision(observation: observation, write: nil)
        }
    }

    /// Whether this install had data before the marker's first write.
    ///
    /// The two stores that every build since v1.2 has kept, named so a reader can check them:
    /// * `settingsStored` — anything under `AppSettings.defaultsKey` ("NihongoRide.settings.v1"),
    ///   which every launch saves (it carries the minted `deviceID`), so any install that has
    ///   launched once before has it;
    /// * `odometerStored` — `Application Support/NihongoRide/odometer.json`
    ///   (`SyncKit.OdometerLog`), in any state other than missing: a corrupt or unreadable odometer
    ///   is still an odometer this install had.
    public static func priorDataPresent(settingsStored: Bool, odometerStored: Bool) -> Bool {
        settingsStored || odometerStored
    }

    /// Reads, decides and writes in ONE branch, and returns the pre-launch observation.
    ///
    /// The `EntitlementLedger.apply(_:savingTo:)` shape, for its reason: the decision and the save
    /// sit on one line of control flow so a caller cannot take one without the other.
    @discardableResult
    public static func recordLaunch(in defaults: UserDefaults, running: Running?,
                                    priorDataPresent: Bool,
                                    key: String = defaultsKey) -> Observation {
        let decision = decide(stored: Stored.read(from: defaults, key: key), running: running,
                              priorDataPresent: priorDataPresent)
        if let bytes = decision.write { defaults.set(bytes, forKey: key) }
        return decision.observation
    }
}
