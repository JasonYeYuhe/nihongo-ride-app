import Testing
import Foundation
import GameCore
import VocabKit
import ReviewKit
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
///
/// The C3 review (2026-09-25) then found mutations that list missed, all of them green against
/// 8fb7b4b. Mutation, 2026-09-25, on the fixed branch (filtered run of this suite,
/// `AppModelTests` and `DeckRandomnessTests`; each restored after): each goes red, and where.
/// - U7, the consumer severed (`captureTarget: nil` in `AppModel.currentIsolation`):
///   `AppModelTests.captureIsolationIsConsumed` on three doors — `supportFileURL` not
///   redirected, `settingsStore` is `.standard`, `touchesNothingOfTheUsers` false — and
///   `captureWritesEveryScreenOrSaysSo` refuses to ride (its isolation guard records the issue).
/// - U3, `failed += 1` deleted from `render`'s catch: `captureWritesEveryScreenOrSaysSo`,
///   `refused == Self.defaultScreenCount` and `refused == pngs.count`.
/// - U4, `if failures > 0 { exit(1) }` replaced by `_ = failures` at the macOS call site:
///   `renderIsHonest`, the verbatim exit-line pin.
/// - C4, `clearCaptureStores()` moved after `AppModel.init()` in `makeModel`:
///   `captureReseedsPerScreen`, `seedAt < clearAt && clearAt < initAt`.
/// - C1, `captureTarget` declared `String?` with no environment initialiser and `capture`
///   assigning it unconditionally: `captureStateComesFromTheEnvironment`, on the declaration
///   pin and on the nil-fallback-only assignment pin.
/// (U1 and U8 are `DeckRandomnessTests`' records.)
///
/// The round-2 review (2026-09-27) found five more mutations green against 47dafc7, and the
/// fix added the checks below. Mutation, 2026-09-27, on the fixed branch (`--filter
/// CaptureToolTests`; each restored byte-for-byte after): each goes red, and where.
/// - B, the create-failure branch's `return 1` → `return 0`: `captureWritesEveryScreenOrSaysSo`,
///   `aborted == 1`.
/// - C, `report("FAILED \(path): …")` → `report("FAILED: …")`: `renderIsHonest` (the verbatim
///   failure-line pin) and `captureWritesEveryScreenOrSaysSo`, `failureLines.contains { $0.hasPrefix("FAILED \(sealed.path)/\(png): ") }`.
/// - D, `written += 1` hoisted above render's `do`: `captureWritesEveryScreenOrSaysSo`,
///   `Screenshotter.written == 0` after the read-only capture and both closing-line checks.
/// - E, the end-of-capture `clearCaptureStores()` deleted: `expectLeftNothing`,
///   `!FileManager.default.fileExists(atPath: base.path)`, after the writable and the read-only
///   captures (and the stuck capture's count, 16 → 15).
/// - F, the seed-clearing `defer` turned into a leading `do`: `expectLeftNothing`,
///   `DeckRandomness.seed == nil`, and `captureReseedsPerScreen`, `opening == ["defer {", …]`.
/// - G (the NOTE), `unprepared += 1` deleted from `clearCaptureStores`' catch:
///   `captureWritesEveryScreenOrSaysSo`, `Screenshotter.unprepared == 16`.
/// - H, the fixed-odometer line deleted from `makeModel`: `captureReseedsPerScreen`, the
///   seed / clear / odometer / init lines not all found.
/// - I, `seedDemoReviewForecast`'s capture guard deleted: `reviewForecastFixture`,
///   `model.reviewStore.count == 0`.
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

    /// The source's lines with EVERY comment removed — `//` to the end of the line and
    /// `/* … */` (nested, as Swift allows, and across lines) — string literals kept intact
    /// (a `//` inside one is code), each line trimmed, the line count unchanged. So a rule
    /// mentioned in prose never counts as code, and a line commented out with `/* */` never
    /// satisfies a pin. (The first version stripped `//` only.) A twin of
    /// `DeckRandomnessTests.codeLines`: the two test targets share no module.
    static func codeLines(_ source: String) -> [String] {
        let chars = Array(source)
        var out = ""
        var i = 0
        var blockDepth = 0
        var inString = false
        var multiline = false
        func at(_ k: Int) -> Character? { k < chars.count ? chars[k] : nil }
        while i < chars.count {
            let c = chars[i]
            let next = at(i + 1)
            if blockDepth > 0 {
                if c == "/" && next == "*" { blockDepth += 1; i += 2; continue }
                if c == "*" && next == "/" { blockDepth -= 1; i += 2; continue }
                if c == "\n" { out.append(c) }
                i += 1
                continue
            }
            if inString {
                out.append(c)
                if c == "\\", let next { out.append(next); i += 2; continue }
                if multiline {
                    if c == "\"" && next == "\"" && at(i + 2) == "\"" {
                        out += "\"\""; i += 3; inString = false; multiline = false; continue
                    }
                } else if c == "\"" || c == "\n" {
                    inString = false
                }
                i += 1
                continue
            }
            if c == "/" && next == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/" && next == "*" { blockDepth = 1; i += 2; continue }
            if c == "\"" {
                inString = true
                if next == "\"" && at(i + 2) == "\"" { multiline = true; out += "\"\"\""; i += 3; continue }
            }
            out.append(c)
            i += 1
        }
        return out.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The stripper is itself an instrument, so it is checked against text whose answer is
    /// written out here, not computed by it.
    @Test("codeLines strips // and /* */ comments, keeps strings, keeps the line count")
    func codeLinesStripsBothCommentKinds() {
        let source = "let a = 1 // trailing\n/* whole\nblock */ let b = 2\nlet c = \"x // y\" /* in /* nested */ line */\n// only prose"
        #expect(Self.codeLines(source) == ["let a = 1", "", "let b = 2", "let c = \"x // y\"", ""])
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
        // The failure line names the path, verbatim. Two of the three errors it reports
        // (`renderProducedNoImage`, `emptyFile`) carry no file name of their own, so without
        // `\(path)` here the gate could not say which screen failed; the review dropped it and
        // the suite stayed green. `captureWritesEveryScreenOrSaysSo` holds the same line by
        // behaviour for the error it can provoke.
        let failedLines = body.filter { $0.contains("report(\"FAILED") }
        #expect(failedLines == ["report(\"FAILED \\(path): \\(error.localizedDescription)\")"],
                "render's failure line changed: \(failedLines)")
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
    /// "0 screens written", and exited 0. So this drives `capture` itself, four times, in this
    /// process: a target it can write gets every screen on disk with size > 0 and a count of 0;
    /// a target it cannot write (mode 555) gets no file and the count of what it attempted —
    /// which the pinned call sites turn into the exit code, and the two counts must agree; a
    /// target that cannot be created (its parent is mode 555) gets 1, a line naming it, and
    /// nothing on disk; and a capture container that cannot be cleared is counted. After each,
    /// what the run SAID is read too (`Screenshotter.reported`: the summary, the path in every
    /// failure line) and what it LEFT (`expectLeftNothing`: seed, container, suite). Added
    /// 2026-09-27, when the review's mutations B, C, D, E and F each stayed green.
    ///
    /// Every override is cleared for the duration, exactly as `captureIsolationIsConsumed`
    /// does, so the capture's stores land in the container its own target names (and are
    /// removed by `capture` itself) rather than in whichever sandbox the previous test left in
    /// the static overrides.
    @Test("capture returns 0 with every PNG on disk, the attempted count with none, 1 when it cannot start, and leaves nothing")
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
        let lockedParent = root.appendingPathComponent("locked-parent", isDirectory: true)
        defer {
            // Unseal before removing, or the removal fails and the directory outlives the test.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedParent.path)
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
        let openStores = AppModel.currentIsolation
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
        // The summary counts what is on disk: `written` is the numerator of both summary lines,
        // and the review hoisted `written += 1` above the write — "24 of 48 screens FAILED" for
        // 24 screens, suite green — because only the returned count was read.
        #expect(Screenshotter.written == pngs.count && Screenshotter.unprepared == 0)
        #expect(Screenshotter.reported.last == "\(pngs.count) screens written to \(open.path)",
                "the closing line is \(String(describing: Screenshotter.reported.last))")
        Self.expectLeftNothing(openStores, after: "the writable capture")

        // 2. A target that exists and refuses writes: nothing lands, and the count says so.
        try FileManager.default.createDirectory(at: sealed, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sealed.path)
        Screenshotter.captureTarget = sealed.path
        let sealedStores = AppModel.currentIsolation
        let refused = Screenshotter.capture(into: sealed.path)
        let landed = try FileManager.default.contentsOfDirectory(atPath: sealed.path)
        #expect(landed.isEmpty, "a read-only target received files: \(landed)")
        #expect(refused == Self.defaultScreenCount,
                "capture reported \(refused) failures for \(Self.defaultScreenCount) unwritable screens")
        #expect(refused == pngs.count, "the attempted count and the written count disagree")
        #expect(Screenshotter.written == 0, "\(Screenshotter.written) screens counted as written into a read-only directory")
        #expect(Screenshotter.reported.last == "\(pngs.count) of \(pngs.count) screens FAILED",
                "the closing line is \(String(describing: Screenshotter.reported.last))")
        // Every failure line names its file: one per screen the writable run produced.
        let failureLines = Screenshotter.reported.filter { $0.hasPrefix("FAILED") }
        #expect(failureLines.count == pngs.count)
        for png in pngs {
            #expect(failureLines.contains { $0.hasPrefix("FAILED \(sealed.path)/\(png): ") },
                    "no failure line names \(png): \(failureLines.prefix(2))")
        }
        Self.expectLeftNothing(sealedStores, after: "the read-only capture")

        // 3. A target that cannot be CREATED (its parent is mode 555): the abort path. It
        // returns 1 — non-zero, so the call sites exit 1 — names the path, and creates nothing.
        // Nothing drove this branch before; the review changed its `return 1` to `return 0`
        // and the suite stayed green while the tool exited 0 having written nothing.
        try FileManager.default.createDirectory(at: lockedParent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedParent.path)
        let unreachable = lockedParent.appendingPathComponent("target", isDirectory: true)
        Screenshotter.captureTarget = unreachable.path
        let abortedStores = AppModel.currentIsolation
        let aborted = Screenshotter.capture(into: unreachable.path)
        #expect(aborted == 1, "a target that cannot be created returned \(aborted)")
        #expect(!FileManager.default.fileExists(atPath: unreachable.path), "the unreachable target exists after all")
        #expect(Screenshotter.written == 0)
        #expect(Screenshotter.reported.first?.hasPrefix("cannot create \(unreachable.path): ") == true,
                "the abort does not name the path: \(Screenshotter.reported)")
        #expect(Screenshotter.reported.last == "capture aborted: nothing was written")
        Self.expectLeftNothing(abortedStores, after: "the aborted capture")

        // 4. A capture container that cannot be cleared (a mode-555 directory inside it):
        // every screen still renders, but none of them started from nothing, and the run says
        // so in its return value — not only on stderr, where the first version left it.
        let stuck = root.appendingPathComponent("stuck", isDirectory: true)
        Screenshotter.captureTarget = stuck.path
        let stuckStores = AppModel.currentIsolation
        let stuckBase = try #require(stuckStores.supportBase)
        let pinned = stuckBase.appendingPathComponent("pinned", isDirectory: true)
        try FileManager.default.createDirectory(at: pinned, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: pinned.appendingPathComponent("file"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: pinned.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pinned.path)
            try? FileManager.default.removeItem(at: stuckBase)
            if let suite = stuckStores.settingsSuite {
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
        }
        let unclean = Screenshotter.capture(into: stuck.path)
        // 15 models in a default run, each cleared first, plus the end-of-run clear: 16.
        #expect(Screenshotter.unprepared == 16, "\(Screenshotter.unprepared) failed clears, expected 15 + 1")
        #expect(unclean == 16 && Screenshotter.failed == 0 && Screenshotter.written == pngs.count,
                "returned \(unclean), failed \(Screenshotter.failed), written \(Screenshotter.written)")
        #expect(Screenshotter.reported.contains { $0.hasPrefix("could not clear capture container \(stuckBase.path): ") })
        #expect(DeckRandomness.seed == nil)
    }

    /// After a capture, whatever happened: the seed is cleared (the `defer`), and neither the
    /// capture's container nor its defaults suite is left behind (the end-of-run clear). The
    /// review turned the defer into a leading `do` and deleted the end-of-run clear; both
    /// stayed green, and the second left `NihongoRideCapture-<tag>` containers in $TMPDIR.
    static func expectLeftNothing(_ stores: AppModel.LaunchIsolation, after what: String,
                                  sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(DeckRandomness.seed == nil, "\(what) left the deck seeded", sourceLocation: sourceLocation)
        guard let base = stores.supportBase, let suite = stores.settingsSuite else {
            Issue.record("\(what): the isolation names no container or suite: \(stores)", sourceLocation: sourceLocation)
            return
        }
        #expect(base.lastPathComponent.hasPrefix("NihongoRideCapture-"), sourceLocation: sourceLocation)
        #expect(!FileManager.default.fileExists(atPath: base.path),
                "\(what) left its container behind: \(base.path)", sourceLocation: sourceLocation)
        let domain = UserDefaults(suiteName: suite)?.persistentDomain(forName: suite) ?? [:]
        #expect(domain.isEmpty, "\(what) left its defaults suite behind: \(suite) \(domain.keys.sorted())",
                sourceLocation: sourceLocation)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        #expect(!FileManager.default.fileExists(atPath: plist.path),
                "\(what) left its defaults suite's plist behind: \(plist.path)", sourceLocation: sourceLocation)
    }

    /// The default set: 15 models write 16 files (the road twice from one model), plus four
    /// widget previews and three accessories drawn from data alone, plus one share card drawn
    /// from the results model's summary — 16 + 4 + 3 + 1 = 24. (The sixteenth `makeModel` call
    /// in the source, the stage sheet's, runs only under NIHONGO_SHOT_STAGES.) A new screen
    /// changes this number on purpose, in the same commit that adds it.
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
    /// name; the render-level proof is a mutation recorded in `docs/PLAN-V1.34.md` §C3's
    /// 2026-09-27 addendum (with `results-sentence` removed, the other 23 screens byte-identical
    /// to the unmutated run); this pins the order.
    @Test("capture reseeds and clears the stores before every screen's model, and clears the seed at the end")
    func captureReseedsPerScreen() throws {
        let lines = Self.codeLines(try Self.source("Sources/NihongoRideApp/Screenshot.swift"))
        #expect(lines.contains { $0.contains("DeckRandomness.seed = StableDigest.fnv1a64(screen)") },
                "makeModel no longer seeds from the screen name")
        // The seed is cleared by a `defer` that is the FIRST statement of `capture`, so every
        // way out — the abort's `return 1` included — passes through it. The first pin only
        // asked that some line read `DeckRandomness.seed = nil`; the review turned the defer
        // into a leading `do { … }`, which clears nothing at the end, and stayed green.
        if let start = lines.firstIndex(where: { $0.contains("static func capture(into directory: String) -> Int {") }) {
            let opening = Array(lines[(start + 1)...].filter { !$0.isEmpty }.prefix(3))
            #expect(opening == ["defer {", "DeckRandomness.seed = nil", "}"],
                    "capture's first statement is not the seed-clearing defer: \(opening)")
        } else {
            Issue.record("Screenshot.swift no longer declares capture(into:) -> Int; the pin is reading nothing")
        }
        // Order inside makeModel: seed, clear, the fixed odometer (for the screens that have
        // one), THEN build. The first `clearCaptureStores()` in the file must sit between the
        // seed line and the odometer line; the end-of-capture clear comes later and does not
        // satisfy this. The odometer must follow the clear (or the clear deletes it) and precede
        // the init (or `AppModel.init` — `recordLaunch` included — reads zero).
        let seedAt = lines.firstIndex { $0.contains("DeckRandomness.seed = StableDigest.fnv1a64(screen)") }
        let clearAt = lines.firstIndex { $0 == "clearCaptureStores()" }
        let odometerAt = lines.firstIndex { $0 == "if let metres = fixedOdometerMetres[screen] { writeFixedOdometer(metres) }" }
        let initAt = lines.firstIndex { $0 == "let m = AppModel.init()" }
        if let seedAt, let clearAt, let odometerAt, let initAt {
            #expect(seedAt < clearAt && clearAt < odometerAt && odometerAt < initAt,
                    "makeModel's order is not seed → clear → odometer → init: seed:\(seedAt + 1) clear:\(clearAt + 1) odometer:\(odometerAt + 1) init:\(initAt + 1)")
        } else {
            Issue.record("makeModel's seed / clear / odometer / init lines were not all found: \(String(describing: seedAt)) \(String(describing: clearAt)) \(String(describing: odometerAt)) \(String(describing: initAt))")
        }
        // The fixture table, by value: 700 m is the lifetime at which the frozen Road screen
        // reads what 1.33's baseline read (24.3 km to Kyōto at 25 000 m, Kawasaki at 400 m
        // reached, Hakone at 1 200 m not), and these three models are the ones that read it.
        #expect(Screenshotter.fixedOdometerMetres == ["road": 700, "about": 700, "conjugation-results": 700])
        let named = lines.filter { $0.contains("makeModel(\"") }.count
        let bare = lines.filter { $0.contains("makeModel()") }.count
        // Sixteen named `makeModel` calls in the source: fifteen run in a default capture and
        // build its 24 files (the road renders twice from one model; the widgets, accessories
        // and share card take no model of their own), and the sixteenth is the stage sheet's,
        // which runs only under NIHONGO_SHOT_STAGES. Fewer means the scan is not reading them.
        #expect(named >= 16, "only \(named) named makeModel calls — the per-screen seeding is not what renders the screens")
        #expect(bare == 0, "\(bare) makeModel() call(s) build a model without a screen seed")
        // Different screens draw different decks — the seeds are not accidentally equal.
        let seeds = ["menu", "game", "game-mid", "results", "practice", "conjugation"].map(StableDigest.fnv1a64)
        #expect(Set(seeds).count == seeds.count)
    }

    /// The Ride Log's forecast fixture: seven cards due tomorrow, only under capture. Expected
    /// values are written out: seven cards, each a clean first review today → SM-2 interval 1 →
    /// the next calendar day, so the forecast is (today 0, tomorrow 7, this week 0).
    @Test("seedDemoReviewForecast puts seven cards in tomorrow's row, and only under capture")
    func reviewForecastFixture() {
        let savedCapturing = Screenshotter.isCapturing
        defer { Screenshotter.isCapturing = savedCapturing }
        let entries = (0 ..< 10).map {
            VocabEntry(id: "fx\($0)", surface: "語\($0)", kana: "ご", partsOfSpeech: ["n"], jlpt: .n5,
                       meanings: ["en": ["word \($0)"], "zh": ["词 \($0)"]])
        }
        let model = AppModelTests.makeModel(vocab: VocabStore(entries: entries))
        Screenshotter.isCapturing = false
        model.seedDemoReviewForecast()
        #expect(model.reviewStore.count == 0, "the forecast fixture wrote cards outside capture")
        Screenshotter.isCapturing = true
        model.seedDemoReviewForecast()
        let forecast = model.reviewStore.dueForecast(resolves: model.vocab.resolvesID)
        #expect(forecast == DueForecast(today: 0, tomorrow: 7, thisWeek: 0), "forecast \(forecast)")
    }
}
