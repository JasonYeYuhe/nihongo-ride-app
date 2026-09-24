import Testing
import Foundation
import GameCore
@testable import NihongoRideApp

/// v1.34 §C3 — the headless render tool stops lying. These pin the three properties the plan
/// names: per-target isolation, honest output, and a seeded (reproducible) capture.
///
/// Each test was shown red under a named mutation before it was trusted (2026-09-25):
/// - `captureIsolationPerTarget` and `digestKnownAnswers`: `StableDigest.tag` returning a
///   constant → two targets share a container; the vectors fail.
/// - `renderIsHonest`: the `try?` put back in front of `png.write` → the pin names the line.
/// - `onlyCaptureSeeds`: `DeckRandomness.seed = 1` added to `AppModel.init` → a second setter.
/// - `captureReseedsPerScreen`: `makeModel` seeding from a constant instead of the screen name.
@MainActor
@Suite("v1.34 §C3: the headless render tool")
struct CaptureToolTests {

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func source(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// Lines with comments stripped — whole-line and trailing — so a rule mentioned in prose
    /// does not count as code. (Screenshot.swift has no string literal containing `//`.)
    static func codeLines(_ source: String) -> [String] {
        source.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { return "" }
            return trimmed.components(separatedBy: "//").first ?? trimmed
        }
    }

    static func isolation(_ target: String?) -> AppModel.LaunchIsolation {
        AppModel.launchIsolation(uiTest: false, layoutHarness: false, captureTarget: target,
                                 supportOverride: nil, widgetOverride: nil, settingsOverride: nil)
    }

    // MARK: 1. Per-target isolation

    /// One fixed `NihongoRideCapture` meant two captures started together shared one odometer,
    /// one journal and one defaults suite, so v1.33's renders had to run one after the other.
    /// Now the names are derived from the target: same target, same names (a re-run reproduces);
    /// different targets, nothing in common.
    @Test("capture isolation is derived from the target: same target same names, different targets never meet")
    func captureIsolationPerTarget() {
        let a1 = Self.isolation("/tmp/a")
        let a2 = Self.isolation("/tmp/a")
        let b = Self.isolation("/tmp/b")
        #expect(a1 == a2, "the same target must map to the same names every time")
        #expect(a1.touchesNothingOfTheUsers && b.touchesNothingOfTheUsers)
        #expect(a1.supportBase != b.supportBase, "two targets share a capture container")
        #expect(a1.widgetContainer != b.widgetContainer, "two targets share a widget container")
        #expect(a1.settingsSuite != b.settingsSuite, "two targets share a defaults suite")
        let tag = StableDigest.tag("/tmp/a")
        #expect(a1.supportBase?.lastPathComponent == "NihongoRideCapture-" + tag)
        #expect(a1.settingsSuite == "NihongoRideCapture-" + tag,
                "the suite and the container carry the same tag, so a capture's stores can be paired")
        #expect(a1.widgetContainer?.path.hasPrefix(a1.supportBase?.path ?? "/nowhere") == true,
                "the widget container must live inside the capture container")
        #expect(a1.supportBase?.path.hasPrefix(FileManager.default.temporaryDirectory.path) == true,
                "the capture container must be throwaway")
        // The negative control: with no target, nothing is isolated (the shipping launch).
        #expect(Self.isolation(nil).touchesNothingOfTheUsers == false)
    }

    /// FNV-1a's published vectors, plus the two tags `captureIsolationPerTarget` relies on
    /// (computed independently in Python, not by this code). A digest that drifted would move
    /// every seeded screen's deck and look like a layout regression in the render gate.
    @Test("the digest is FNV-1a 64, pinned to published vectors")
    func digestKnownAnswers() {
        #expect(StableDigest.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(StableDigest.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(StableDigest.fnv1a64("/tmp/a") == 0x6cc1_3bdd_f274_6ce7)
        #expect(StableDigest.tag("/tmp/a") == "f2746ce7")
        #expect(StableDigest.tag("/tmp/b") == "f2746e9a")
        #expect(StableDigest.tag("/tmp/a").count == 8)
    }

    // MARK: 2. Honest output

    /// `render` used `try?` and printed "wrote <path>" whatever happened: two agents printed 24
    /// "wrote" lines into a directory that did not exist, and the process exited 0. The pin:
    /// no `try?` in `render`, the write is a `try`, and the ONE "wrote" print sits after the
    /// `guard size > 0` that checked the file is on disk and non-empty.
    @Test("render has no try?, and prints \"wrote\" only after the file's size was checked")
    func renderIsHonest() throws {
        let lines = Self.codeLines(try Self.source("Sources/NihongoRideApp/Screenshot.swift"))
        guard let start = lines.firstIndex(where: { $0.contains("static func render(") }) else {
            Issue.record("Screenshot.swift no longer declares render(); the pin is reading nothing")
            return
        }
        var depth = 0
        var opened = false
        var end = start
        scan: for index in start ..< lines.count {
            for character in lines[index] {
                if character == "{" { depth += 1; opened = true }
                if character == "}" { depth -= 1 }
            }
            if opened && depth == 0 { end = index; break scan }
        }
        #expect(end > start + 5, "render's body was not found by brace matching")
        let body = lines[start ... end]
        let tryQuestion = body.indices.filter { body[$0].contains("try?") }
        #expect(tryQuestion.isEmpty, Comment(rawValue:
            "render swallows an error again at Screenshot.swift:" + tryQuestion.map { "\($0 + 1)" }.joined(separator: ",")))
        let wrote = body.indices.filter { body[$0].contains("\"wrote ") }
        let sizeGuard = body.indices.filter { body[$0].contains("guard size > 0") }
        let write = body.indices.filter { body[$0].contains("try png.write(") }
        #expect(wrote.count == 1, "expected exactly one \"wrote\" print in render, found \(wrote.count)")
        #expect(sizeGuard.count == 1, "expected exactly one `guard size > 0` in render, found \(sizeGuard.count)")
        #expect(write.count == 1, "expected exactly one `try png.write(` in render, found \(write.count)")
        if let w = wrote.first, let g = sizeGuard.first, let p = write.first {
            #expect(p < g && g < w, "the order must be write → size check → \"wrote\"; got write:\(p + 1) guard:\(g + 1) wrote:\(w + 1)")
        }
        // …and nowhere else in the file prints "wrote", so the count above is the whole story.
        #expect(lines.filter { $0.contains("\"wrote ") }.count == 1)
        // The call sites exit non-zero on failure: the count `capture` returns is consumed.
        let app = Self.codeLines(try Self.source("Sources/NihongoRideApp/NihongoRideApp.swift"))
        #expect(app.contains { $0.contains("Screenshotter.capture(into: dir)") && $0.contains("failures") },
                "the macOS call site no longer reads capture's failure count")
        #expect(app.contains { $0.contains("exit(Screenshotter.capture(into: dir) > 0 ? 1 : 0)") },
                "the iOS call site no longer exits non-zero on failure")
    }

    // MARK: 3. Deterministic capture

    /// Only the capture may seed the deck: a seed set anywhere else would make a shipping ride
    /// repeat itself. Comment-stripped scan of every source file for the setter.
    @Test("Screenshotter is the only place that seeds the deck")
    func onlyCaptureSeeds() throws {
        let sources = Self.repoRoot.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var setters: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in Self.codeLines(source).enumerated() {
                let assigns = line.range(of: #"DeckRandomness\.seed\s*=[^=]"#, options: .regularExpression) != nil
                if assigns || line.contains("DeckRandomness.withSeed(") {
                    setters.append("\(url.lastPathComponent):\(number + 1)  \(line)")
                }
            }
        }
        #expect(scanned > 50, "only \(scanned) source files scanned — the walk is not reading Sources")
        let elsewhere = setters.filter { !$0.hasPrefix("Screenshot.swift:") }
        #expect(elsewhere.isEmpty, Comment(rawValue: "the deck is seeded outside capture:\n" + elsewhere.joined(separator: "\n")))
        #expect(setters.count >= 2, Comment(rawValue:
            "capture sets the seed per screen and clears it at the end; a scan that finds fewer "
            + "(\(setters.count)) is not reading Screenshot.swift"))
    }

    /// The seed is reset from the screen's own file name before that screen's model is built,
    /// so adding or removing a screen upstream cannot change a later one — and every model is
    /// built through that one closure with a literal name.
    @Test("capture reseeds every screen from its own name, and clears the seed at the end")
    func captureReseedsPerScreen() throws {
        let lines = Self.codeLines(try Self.source("Sources/NihongoRideApp/Screenshot.swift"))
        #expect(lines.contains { $0.contains("DeckRandomness.seed = StableDigest.fnv1a64(screen)") },
                "makeModel no longer seeds from the screen name")
        #expect(lines.contains { $0 == "DeckRandomness.seed = nil" },
                "capture no longer clears the seed when it is done")
        let named = lines.filter { $0.contains("makeModel(\"") }.count
        let bare = lines.filter { $0.contains("makeModel()") }.count
        // Sixteen models build the 24 screens (the road renders twice from one model; the
        // widgets and the share card take no model). Fewer means the scan is not reading them.
        #expect(named >= 16, "only \(named) named makeModel calls — the per-screen seeding is not what renders the screens")
        #expect(bare == 0, "\(bare) makeModel() call(s) build a model without a screen seed")
        // Different screens draw different decks — the seeds are not accidentally equal.
        let seeds = ["menu", "game", "game-mid", "results", "practice", "conjugation"].map(StableDigest.fnv1a64)
        #expect(Set(seeds).count == seeds.count)
    }
}
