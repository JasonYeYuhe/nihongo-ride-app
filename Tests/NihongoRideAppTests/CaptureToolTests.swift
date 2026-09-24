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
        // The call sites exit non-zero on failure: the count `capture` returns is consumed, and
        // the conditional that turns it into the exit code is pinned VERBATIM (comment-stripped,
        // trimmed). The first version of this pin only asked that some line mention both
        // `capture(into: dir)` and `failures`, which `let failures = …` satisfies on its own; the
        // review deleted `if failures > 0 { exit(1) }` and the suite stayed green while the tool
        // exited 0 after "24 of 24 screens FAILED".
        let app = Self.codeLines(try Self.source("Sources/NihongoRideApp/NihongoRideApp.swift"))
        #expect(app.contains { $0 == "let failures = Screenshotter.capture(into: dir)" },
                "the macOS call site no longer reads capture's failure count")
        #expect(app.contains { $0 == "if failures > 0 { exit(1) }" },
                "the macOS call site no longer exits non-zero on failure")
        #expect(app.contains { $0 == "exit(Screenshotter.capture(into: dir) > 0 ? 1 : 0)" },
                "the iOS call site no longer exits non-zero on failure")
    }

    /// Property B by BEHAVIOUR, not by the order of three lines: `renderIsHonest` pins the
    /// write → size check → "wrote" order, but the review deleted `failed += 1` from render's
    /// catch and the suite stayed green while the tool printed 24 FAILED lines, then
    /// "0 screens written", and exited 0. So this drives `capture` itself, twice, in this
    /// process: a target it can write gets every screen on disk with size > 0 and a count of 0;
    /// a target it cannot write (mode 555) gets no file and the count of what it attempted —
    /// which the pinned call sites turn into the exit code. The two counts must agree.
    ///
    /// Every override is cleared for the duration, exactly as `captureIsolationIsConsumed`
    /// does, so the capture's stores land in the container its own target names (and are
    /// removed by `capture` itself) rather than in whichever sandbox the previous test left in
    /// the static overrides.
    @Test("capture returns 0 with every PNG on disk, and the attempted count with none of them")
    func captureWritesEveryScreenOrSaysSo() throws {
        let savedTarget = Screenshotter.captureTarget
        let savedCapturing = Screenshotter.isCapturing
        let savedSupport = AppModel.supportDirectoryOverride
        let savedWidget = AppModel.widgetContainerOverride
        let savedDefaults = AppModel.settingsDefaults
        let savedSuite = AppModel.settingsSuiteOverride
        defer {
            Screenshotter.captureTarget = savedTarget
            Screenshotter.isCapturing = savedCapturing
            AppModel.supportDirectoryOverride = savedSupport
            AppModel.widgetContainerOverride = savedWidget
            AppModel.settingsDefaults = savedDefaults
            AppModel.settingsSuiteOverride = savedSuite
        }
        AppModel.supportDirectoryOverride = nil
        AppModel.widgetContainerOverride = nil
        AppModel.settingsDefaults = nil
        AppModel.settingsSuiteOverride = nil

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NihongoRideCaptureTest-\(UUID().uuidString)", isDirectory: true)
        let sealed = root.appendingPathComponent("sealed", isDirectory: true)
        defer {
            // Unseal before removing, or the removal fails and the directory outlives the test.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path)
            try? FileManager.default.removeItem(at: root)
        }

        // 1. A target that does not exist yet: capture creates it and writes every screen.
        let open = root.appendingPathComponent("open", isDirectory: true)
        Screenshotter.captureTarget = open.path
        Screenshotter.isCapturing = true
        // Refuse to render into the owner's data. The ride screens below finish real runs whose
        // saves are gated by the load outcome, not by `isCapturing`; if a set target does not
        // reach the doors (the consumer severed), that is `captureIsolationIsConsumed`'s red
        // line, and this test stops here rather than logging invented rides into the real
        // journal on the way to its own.
        guard AppModel.currentIsolation.touchesNothingOfTheUsers else {
            Issue.record("a set captureTarget does not isolate this process: \(AppModel.currentIsolation) — not rendering")
            return
        }
        let failures = Screenshotter.capture(into: open.path)
        let pngs = try FileManager.default.contentsOfDirectory(atPath: open.path).filter { $0.hasSuffix(".png") }
        #expect(failures == 0, "\(failures) screen(s) failed into a writable directory")
        #expect(pngs.count == Self.defaultScreenCount,
                "expected \(Self.defaultScreenCount) screens, found \(pngs.count): \(pngs.sorted())")
        for png in pngs {
            let attributes = try FileManager.default.attributesOfItem(atPath: open.appendingPathComponent(png).path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            #expect(size > 0, "\(png) is on disk but empty")
        }

        // 2. A target that exists and refuses writes: nothing lands, and the count says so.
        try FileManager.default.createDirectory(at: sealed, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sealed.path)
        Screenshotter.captureTarget = sealed.path
        let refused = Screenshotter.capture(into: sealed.path)
        let landed = try FileManager.default.contentsOfDirectory(atPath: sealed.path)
        #expect(landed.isEmpty, "a read-only target received files: \(landed)")
        #expect(refused == Self.defaultScreenCount,
                "capture reported \(refused) failures for \(Self.defaultScreenCount) unwritable screens")
        #expect(refused == pngs.count, "the attempted count and the written count disagree")
    }

    /// The default set: 16 models render 24 files (the road twice from one model, five widget
    /// previews and three accessories from data alone, one share card). A new screen changes
    /// this number on purpose, in the same commit that adds it.
    static let defaultScreenCount = 24

    /// Capture mode is a property of the PROCESS, not of `capture`: both statics are read from
    /// `NIHONGO_SHOT` when first touched, and `capture` never assigns the target. The review
    /// measured why: the App struct's eager `AppModel()` is built before
    /// `applicationDidFinishLaunching` calls `capture`, and while `capture` was the one that set
    /// the target, that model resolved to the owner's Application Support and bumped the launch
    /// counter in the dev binary's defaults domain on every headless render. The raw string,
    /// not `standardizedFileURL`, because that strips `/private` only once the directory exists
    /// and a first run and its re-run were digested into two containers.
    @Test("capture state is read from NIHONGO_SHOT at first use, and capture never assigns the target")
    func captureStateComesFromTheEnvironment() throws {
        let lines = Self.codeLines(try Self.source("Sources/NihongoRideApp/Screenshot.swift"))
        #expect(lines.contains {
            $0 == "@MainActor static var isCapturing = ProcessInfo.processInfo.environment[\"NIHONGO_SHOT\"] != nil"
        }, "isCapturing is no longer initialised from the environment")
        #expect(lines.contains {
            $0 == "@MainActor static var captureTarget: String? = ProcessInfo.processInfo.environment[\"NIHONGO_SHOT\"]"
        }, "captureTarget is no longer initialised from the environment")
        #expect(!lines.contains { $0.contains("standardizedFileURL") },
                "the target is standardised again, so a first run and a re-run digest differently")
        // The one assignment `capture` may make is the fallback for a test that calls it with no
        // environment — and it must be a fallback, never an overwrite.
        let assignments = lines.filter { $0.contains("captureTarget = ") && !$0.contains("static var captureTarget") }
        #expect(assignments == ["if captureTarget == nil { captureTarget = directory }"],
                "capture assigns the target somewhere other than the nil fallback: \(assignments)")
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

    /// The seed is reset from the screen's own file name, and the capture's stores are cleared,
    /// before that screen's model is built — both inside the one closure every model is built
    /// through, with a literal name. The seed alone made each screen's DECK its own; the review
    /// showed that was not screen independence: road.png read the odometer the screens above
    /// had ridden into the shared container, and removing one upstream ride screen moved four
    /// screens below it. The clearing is what makes the later screens a function of their own
    /// name; the render-level proof is a mutation in the §C3 record, this pins the order.
    @Test("capture reseeds and clears the stores before every screen's model, and clears the seed at the end")
    func captureReseedsPerScreen() throws {
        let lines = Self.codeLines(try Self.source("Sources/NihongoRideApp/Screenshot.swift"))
        #expect(lines.contains { $0.contains("DeckRandomness.seed = StableDigest.fnv1a64(screen)") },
                "makeModel no longer seeds from the screen name")
        #expect(lines.contains { $0 == "DeckRandomness.seed = nil" },
                "capture no longer clears the seed when it is done")
        // Order inside makeModel: seed, clear, THEN build. The first `clearCaptureStores()` in
        // the file must sit between the seed line and the init line; the end-of-capture clear
        // comes later and does not satisfy this.
        let seedAt = lines.firstIndex { $0.contains("DeckRandomness.seed = StableDigest.fnv1a64(screen)") }
        let clearAt = lines.firstIndex { $0 == "clearCaptureStores()" }
        let initAt = lines.firstIndex { $0 == "let m = AppModel.init()" }
        if let seedAt, let clearAt, let initAt {
            #expect(seedAt < clearAt && clearAt < initAt,
                    "the stores are not cleared between the seed and the model: seed:\(seedAt + 1) clear:\(clearAt + 1) init:\(initAt + 1)")
        } else {
            Issue.record("makeModel's seed / clear / init lines were not all found: \(String(describing: seedAt)) \(String(describing: clearAt)) \(String(describing: initAt))")
        }
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
