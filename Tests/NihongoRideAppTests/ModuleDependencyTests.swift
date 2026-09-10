import Testing
import Foundation

/// **Two files declare one dependency list, and only one of them is checked by `swift test`.**
///
/// This exists because of a defect it did not catch. v1.31 added `CustomTextKit`, imported it in
/// `AppModel`, and forgot it in `Package.swift`'s app target. That failed at the LINK step, which
/// is loud and cheap. The dangerous half is the other file: `project.yml` lists the same products
/// again, per app target, and **xcodegen's project is what the release build uses**. A product
/// missing there compiles and links under `swift build`, passes the whole suite, and fails when
/// an archive is cut — or, if the macOS target happens to list it and the iOS target does not,
/// fails on one platform only, which is the shape v1.25's crossed build numbers had.
///
/// *One rule written twice will drift* is this repo's own entry, recorded three times. This is
/// that rule pointed at the two files that describe the app's module graph.
@Suite("Package.swift and project.yml describe the same app")
struct ModuleDependencyTests {

    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The products `NihongoRideApp` declares in Package.swift.
    static func packageDependencies() throws -> [String] {
        let text = try String(contentsOf: repo.appendingPathComponent("Package.swift"),
                              encoding: .utf8)
        // BACKWARDS on purpose: `name: "NihongoRideApp"` appears first in `products:`, as the
        // executable declaration, whose next `dependencies: [` belongs to an unrelated target.
        // The first draft anchored forwards, parsed one entry, and **the floor below caught it**
        // — which is the whole reason the floor is there and not a formality.
        guard let anchor = text.range(of: "name: \"NihongoRideApp\"", options: .backwards)
        else { return [] }
        let after = text[anchor.upperBound...]
        guard let start = after.range(of: "dependencies: ["),
              let end = after[start.upperBound...].firstIndex(of: "]") else { return [] }
        return after[start.upperBound..<end]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"")) }
            .filter { !$0.isEmpty }
    }

    /// The products each Xcode app target lists, keyed by target name.
    static func projectDependencies() throws -> [String: Set<String>] {
        let text = try String(contentsOf: repo.appendingPathComponent("project.yml"),
                              encoding: .utf8)
        var out: [String: Set<String>] = [:]
        var target: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            // A target header is exactly two spaces of indent, e.g. "  NihongoRideiOS:".
            if let m = line.range(of: #"^  (\w[\w.-]*):\s*$"#, options: .regularExpression) {
                target = String(line[m]).trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            }
            if let t = target, let r = line.range(of: "product: ") {
                out[t, default: []].insert(String(line[r.upperBound...])
                    .trimmingCharacters(in: .whitespaces))
            }
        }
        return out
    }

    @Test("every product the SPM app target uses is listed for BOTH Xcode app targets")
    func theTwoFilesAgree() throws {
        let declared = try Self.packageDependencies()
        let project = try Self.projectDependencies()

        // A scan that read nothing must not report clean — the shape ResolvesCallSiteTests uses.
        // The floor is well below today's count so a genuine removal does not trip it, and well
        // above zero so a parser that stops matching does.
        #expect(declared.count >= 10, Comment(rawValue:
            "parsed only \(declared.count) dependencies out of Package.swift — the declaration "
            + "shape changed and this check is reading nothing"))
        for target in ["NihongoRide", "NihongoRideiOS"] {
            let listed = project[target] ?? []
            #expect(listed.count >= 10, Comment(rawValue:
                "parsed only \(listed.count) products for \(target) out of project.yml"))
            let missing = Set(declared).subtracting(listed).sorted()
            #expect(missing.isEmpty, Comment(rawValue:
                "\(target) is missing \(missing) — the SPM build links them and the RELEASE "
                + "build would not. This is the file `swift test` cannot see."))
        }
    }

    // MARK: What a TEST target imports vs what it declares

    /// Modules that come from the platform, not from this package.
    static let platformModules: Set<String> = [
        "Testing", "Foundation", "XCTest", "SwiftUI", "CloudKit", "UIKit", "AppKit", "os",
        "Combine", "UserNotifications", "WidgetKit", "StoreKit", "AVFoundation", "Observation",
    ]

    /// Every `.testTarget` and the dependency list it declares.
    static func testTargetDependencies() throws -> [String: Set<String>] {
        let text = try String(contentsOf: repo.appendingPathComponent("Package.swift"), encoding: .utf8)
        var out: [String: Set<String>] = [:]
        var rest = Substring(text)
        while let marker = rest.range(of: ".testTarget(name: \"") {
            let after = rest[marker.upperBound...]
            guard let closeQuote = after.firstIndex(of: "\"") else { break }
            let name = String(after[..<closeQuote])
            guard let depsOpen = after.range(of: "dependencies: ["),
                  let depsClose = after[depsOpen.upperBound...].firstIndex(of: "]")
            else { rest = after; continue }
            let body = after[depsOpen.upperBound..<depsClose]
            var deps: Set<String> = []
            var scan = body
            while let q = scan.firstIndex(of: "\"") {
                let tail = scan[scan.index(after: q)...]
                guard let end = tail.firstIndex(of: "\"") else { break }
                deps.insert(String(tail[..<end]))
                scan = tail[tail.index(after: end)...]
            }
            out[name] = deps
            rest = after
        }
        return out
    }

    /// **A test target must DECLARE every module it imports, and `swift test` on this machine
    /// cannot tell you when it does not.**
    ///
    /// Found by CI's first run, not by any local one. `ConjugationReviewKitTests` imported
    /// `GameCore` while `Package.swift` declared only `ConjugationReviewKit`. On a machine with a
    /// warm `.build` every module is already emitted and the import resolves; on a fresh checkout
    /// the test target is compiled before `GameCore` exists and the build dies with
    /// `error: no such module 'GameCore'`. Six targets, twenty-two undeclared imports.
    ///
    /// So the outcome depended on BUILD ORDER — the same shape as a test that passes because of
    /// state the previous test left behind. The only environment that can observe it is one with
    /// no `.build`, and this repo has not had one since those targets were written. A source scan
    /// has no such blind spot, which is why the rule lives here rather than in a hosted runner.
    @Test("every test target declares the modules its files import")
    func testTargetsDeclareWhatTheyImport() throws {
        let declared = try Self.testTargetDependencies()
        #expect(declared.count >= 10,
                Comment(rawValue: "parsed only \(declared.count) test targets — the scan is misdirected"))

        var offenders: [String] = []
        var filesRead = 0
        for (target, deps) in declared.sorted(by: { $0.key < $1.key }) {
            let dir = Self.repo.appendingPathComponent("Tests/\(target)")
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files where file.hasSuffix(".swift") {
                filesRead += 1
                let source = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
                for line in source.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("import ") || trimmed.hasPrefix("@testable import ") else { continue }
                    let module = String(trimmed
                        .replacingOccurrences(of: "@testable ", with: "")
                        .dropFirst("import ".count))
                        .trimmingCharacters(in: .whitespaces)
                    guard !module.isEmpty, !Self.platformModules.contains(module),
                          !deps.contains(module) else { continue }
                    offenders.append("\(target)/\(file) imports \(module), which \(target) does not declare")
                }
            }
        }
        #expect(filesRead >= 40, Comment(rawValue: "only \(filesRead) test files read — the scan is misdirected"))
        #expect(offenders.isEmpty, Comment(rawValue:
            "\(offenders.count) undeclared import(s). These compile on a warm .build and fail on a "
            + "fresh checkout: \(offenders.prefix(8))"))
    }

    /// `IsolatedLaunch.swift` opens with *"Every UI-test launch goes through here, and none of
    /// them may call `app.launch()` directly."* Nothing enforced that.
    ///
    /// The stake is the one that file names: those tests complete REAL runs, and an unisolated
    /// launch pushes a phantom ride into the owner's real CloudKit database, which cannot be
    /// cleaned up from the simulator that created it. v1.24's App Group incident is the same shape
    /// with a smaller blast radius, and it happened.
    ///
    /// A source scan rather than a behavioural test, because the iOS UI target is not built by
    /// `swift test` at all — so this is the only instrument that can see it from here.
    @Test("no iOS UI test launches the app unisolated")
    func everyUITestLaunchIsIsolated() throws {
        let dir = Self.repo.appendingPathComponent("Tests/NihongoRideiOSUITests")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 4, Comment(rawValue: "only \(files.count) UI test files — the scan is misdirected"))

        var bare: [String] = []
        var isolated = 0
        for file in files where file != "IsolatedLaunch.swift" {
            let source = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                if trimmed.contains("launchIsolated(") { isolated += 1 }
                if trimmed.contains(".launch()") {
                    bare.append("\(file):\(index + 1) \(trimmed)")
                }
            }
        }
        // The floor: a scan that found no launches at all would report clean.
        #expect(isolated >= 8, Comment(rawValue:
            "only \(isolated) isolated launch(es) found — the scan is not reading the tests"))
        #expect(bare.isEmpty, Comment(rawValue:
            "\(bare.count) unisolated launch(es): \(bare). An unisolated UI-test launch completes a "
            + "REAL run and pushes a phantom ride into the owner's real CloudKit database."))
    }

    @Test("…and the two Xcode app targets agree with each other")
    func theTwoPlatformsAgree() throws {
        let project = try Self.projectDependencies()
        let mac = project["NihongoRide"] ?? []
        let ios = project["NihongoRideiOS"] ?? []
        // Widget products legitimately differ per platform; the shared kits must not.
        let macOnly = mac.subtracting(ios).sorted()
        let iosOnly = ios.subtracting(mac).sorted()
        #expect(macOnly.isEmpty && iosOnly.isEmpty, Comment(rawValue:
            "macOS-only \(macOnly), iOS-only \(iosOnly) — a kit on one platform and not the "
            + "other is a defect that ships on exactly one store"))
    }
}
