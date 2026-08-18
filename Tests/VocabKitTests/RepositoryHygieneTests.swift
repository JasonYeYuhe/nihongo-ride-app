import Testing
import Foundation

/// The Finder/iCloud duplicate trap, turned into something that fails a build on purpose.
///
/// On 2026-08-18, two hours after v1.23 shipped, `ListsView 2.swift` and `PracticeView 2.swift`
/// materialised inside `Sources/NihongoRideApp/` carrying their original July mtimes, and
/// `swift build` went red with `invalid redeclaration` against code nobody had touched. The
/// same mechanism produced the seven `NihongoRide N.xcodeproj` copies at the repo root.
///
/// Neither existing defence covers it. `.gitignore` does not stop SPM compiling a file — git
/// ignoring something is not the compiler ignoring it — and `git status` does not show it
/// either, because these arrive untracked. What makes it worth a test rather than a habit is
/// the failure mode that has NOT happened yet: a duplicate that compiles. A stale copy of a
/// view whose symbols were since renamed redeclares nothing, builds clean, and ships whichever
/// of the two the linker preferred. The redeclaration error is the lucky case.
///
/// Scoped to what the compiler actually reads. Copies elsewhere in the tree are litter; copies
/// under a target's source directory are a release risk.
@Suite("Repository hygiene")
struct RepositoryHygieneTests {

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/VocabKitTests/RepositoryHygieneTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Extensions the compiler or the app bundle actually reads. A stray `.md` copy is litter;
    /// a stray `.swift` copy is a build failure at best and a shipped stale view at worst.
    static let compiledExtensions: Set<String> = ["swift", "json", "plist", "entitlements"]

    /// `Foo 2.swift`, `Bar 10.json` — a space, then digits, then the extension. Finder's own
    /// copy naming, and the shape every instance of this has taken.
    ///
    /// Written as a function rather than a stored `Regex` because `Regex` is not `Sendable` and
    /// a static one will not compile under strict concurrency.
    static func isDuplicateName(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: name)
        guard compiledExtensions.contains(url.pathExtension) else { return false }
        let stem = url.deletingPathExtension().lastPathComponent
        guard let space = stem.lastIndex(of: " ") else { return false }
        let head = stem[stem.startIndex..<space]
        let tail = stem[stem.index(after: space)...]
        return !head.isEmpty && !tail.isEmpty && tail.allSatisfy(\.isNumber)
    }

    @Test("no Finder/iCloud duplicate files are sitting in a compiled source tree")
    func noDuplicateSourceFiles() throws {
        var inspected = 0
        var duplicates: [String] = []
        for tree in ["Sources", "Tests"] {
            let root = Self.repoRoot.appendingPathComponent(tree)
            let enumerator = try #require(FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey]))
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                else { continue }
                inspected += 1
                if Self.isDuplicateName(url.lastPathComponent) {
                    duplicates.append(url.path.replacingOccurrences(
                        of: Self.repoRoot.path + "/", with: ""))
                }
            }
        }
        // A scan that read nothing would report a clean tree, which is the exact failure this
        // project logs over and over: a null result from an instrument nobody checked.
        #expect(inspected > 100, "the scan saw only \(inspected) files — it is looking in the wrong place")
        #expect(duplicates.isEmpty, """
            \(duplicates.count) duplicate file(s) in a compiled source tree — delete them, they \
            are Finder/iCloud copies and SPM will compile them:
            \(duplicates.joined(separator: "\n"))
            """)
    }

    /// The rule has to fire, or it is decoration. These are the two files that actually turned
    /// the build red, plus the shapes that must NOT trip it.
    @Test("the rule flags real duplicate names and only those")
    func ruleIsCalibrated() {
        for name in ["ListsView 2.swift", "PracticeView 2.swift", "n5 3.json",
                     "Info 10.plist", "NihongoRide 7.entitlements"] {
            #expect(Self.isDuplicateName(name), "missed \(name)")
        }
        // Legitimate names that contain digits, spaces, or both.
        for name in ["AppModel.swift", "PLAN-V1.24.swift", "n5.json", "Test 2 Helper.swift",
                     "V1.5-Verification.swift", "2.swift"] {
            #expect(!Self.isDuplicateName(name), "false positive on \(name)")
        }
    }
}
