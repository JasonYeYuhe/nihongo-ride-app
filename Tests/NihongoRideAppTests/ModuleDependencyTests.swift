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
