import Testing
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import VocabKit
import GameCore
@testable import NihongoRideApp

/// v1.33 §B group G — the ride HUD, the conjugation drill and the typing coach at the
/// accessibility text sizes.
///
/// **What these can and cannot prove, stated first.** `ImageRenderer` ignores Dynamic Type, and
/// `swift test` has no iPhone, so nothing here shows an AX5 screen. What they hold is the part
/// that is decidable off a device: that each rule is a no-op at every size below the accessibility
/// sizes (the default-size renders depend on that), that the rule says what its comment says, and
/// — where a number was measured to choose it — that the number still covers what it was chosen
/// for, re-measured here with the real fonts and the real `Image(systemName:)` layout instead of
/// being restated. The screens themselves are the AX5 simulator pass's job.
@Suite("v1.33 §B G: ride and drill at the accessibility sizes")
struct V133GRideAndDrillLayoutTests {

    static let belowAccessibility = DynamicTypeSize.allCases.filter { !$0.isAccessibilitySize }
    static let accessibility = DynamicTypeSize.allCases.filter(\.isAccessibilitySize)

    static var appDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NihongoRideApp")
    }

    static func source(_ file: String) throws -> String {
        try String(contentsOf: appDirectory.appendingPathComponent(file), encoding: .utf8)
    }

    /// Lines with comments stripped, so a rule mentioned in prose does not count as code.
    static func codeLines(_ source: String) -> [String] {
        source.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { return "" }
            return trimmed
        }
    }

    // MARK: 1. HUD — the score pill

    /// Below the accessibility sizes every pill shows in both rows, so the default-size HUD cannot
    /// change. Mutation, 2026-09-18: the second row dropping its pill below them too goes red here.
    /// (v1.33 pre-submission review, round 3)
    @Test("the score pill is hidden at exactly the accessibility sizes")
    func scoreHiddenOnlyAtAccessibilitySizes() {
        #expect(Self.accessibility.count == 5 && Self.belowAccessibility.count == 7,
                "DynamicTypeSize changed shape; re-read what this test assumes")
        for size in Self.belowAccessibility {
            #expect(RideHUDLayout.showsScore(size), "default-size HUD must not change at \(size)")
            for scoreIsTheRide in [false, true] {
                for fallback in [false, true] {
                    for pill in RideHUDLayout.Pill.allCases {
                        #expect(RideHUDLayout.shows(pill, size, scoreIsTheRide: scoreIsTheRide, fallback: fallback),
                                "default-size HUD must not change at \(size): \(pill) hidden")
                    }
                }
            }
        }
        for size in Self.accessibility {
            #expect(!RideHUDLayout.showsScore(size), "\(size)")
            #expect(!RideHUDLayout.shows(.score, size, scoreIsTheRide: false, fallback: false), "\(size)")
            #expect(RideHUDLayout.shows(.combo, size, scoreIsTheRide: false, fallback: false),
                    "\(size): a ride that drops its score keeps its combo")
            // Time Attack: the score stays, the combo goes — exactly one pill hidden either way.
            #expect(RideHUDLayout.shows(.score, size, scoreIsTheRide: true, fallback: false), "\(size): Time Attack lost its score")
            #expect(!RideHUDLayout.shows(.combo, size, scoreIsTheRide: true, fallback: false), "\(size)")
            for scoreIsTheRide in [false, true] {
                #expect(RideHUDLayout.shows(.level, size, scoreIsTheRide: scoreIsTheRide, fallback: false), "\(size)")
            }
        }
    }

    /// Round 3 of the pre-submission review: at the accessibility sizes `HUDBar` offers `ViewThatFits`
    /// a second row, and that row gives up exactly one pill more — the combo in a ride whose queue is
    /// the target, the level capsule in Time Attack — and never Time Attack's score. Progress and
    /// pause cannot be given up at all: they are not `Pill`s, and `HUDBar` does not gate them
    /// (`informationalPillsFollowThePhoneAtAccessibilitySizes`). Mutations, 2026-09-18, each red here:
    /// `fallbackDrops` answering `.combo` for Time Attack; `shows` ignoring `fallback`; Time Attack's
    /// second row dropping its score as well. (v1.33 pre-submission review, round 3)
    @Test("the second row gives up exactly one pill more: the combo in a queue ride, the level in Time Attack")
    func fallbackRowDropsOneMorePill() {
        #expect(RideHUDLayout.Pill.allCases == [.level, .score, .combo],
                "a new pill a rule may hide: decide whether it may, and update this test")
        func shown(_ size: DynamicTypeSize, _ scoreIsTheRide: Bool, _ fallback: Bool) -> Set<RideHUDLayout.Pill> {
            Set(RideHUDLayout.Pill.allCases.filter {
                RideHUDLayout.shows($0, size, scoreIsTheRide: scoreIsTheRide, fallback: fallback)
            })
        }
        for size in Self.accessibility {
            for scoreIsTheRide in [false, true] {
                let first = shown(size, scoreIsTheRide, false), second = shown(size, scoreIsTheRide, true)
                let dropped: RideHUDLayout.Pill = scoreIsTheRide ? .level : .combo
                #expect(RideHUDLayout.fallbackDrops(scoreIsTheRide: scoreIsTheRide) == dropped)
                #expect(second.isSubset(of: first) && first.subtracting(second) == [dropped],
                        "\(size), Time Attack \(scoreIsTheRide): first row \(first), second \(second)")
            }
            #expect(shown(size, true, true) == [.score], "\(size): Time Attack's second row must keep its score")
            #expect(shown(size, false, true) == [.level], "\(size): a queue ride's second row")
        }
    }

    /// Round 3: the combo and level pills are asked with the row's own `fallback`, or the second row
    /// would not give them up. Mutations, 2026-09-18: either call site passing `fallback: false` goes
    /// red here. (v1.33 pre-submission review, round 3)
    @Test("Time Attack is the ride that keeps its score, and the drill is not")
    func timeAttackKeepsItsScore() throws {
        let game = Self.codeLines(try Self.source("GameView.swift"))
        #expect(game.contains("private var scoreIsTheRide: Bool { session.mode == .timeAttack }"),
                "GameView no longer derives scoreIsTheRide from Time Attack")
        let combo = game.indices.filter { game[$0].hasPrefix("stat(icon: \"flame.fill\"") }
        #expect(combo.count == 1, "GameView: expected one combo pill, found \(combo.count)")
        for index in combo {
            let previous = game[..<index].last { !$0.isEmpty } ?? ""
            #expect(previous == "if RideHUDLayout.shows(.combo, typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback) {",
                    "GameView:\(index + 1): the combo pill is not behind RideHUDLayout.shows(.combo, …)")
        }
        // Round 3: the level capsule is the pill Time Attack's second row gives up.
        let level = game.indices.filter { game[$0] == "Text(session.currentLevelLabel)" }
        #expect(level.count == 1, "GameView: expected one level capsule, found \(level.count)")
        for index in level {
            let previous = game[..<index].last { !$0.isEmpty } ?? ""
            #expect(previous == "if RideHUDLayout.shows(.level, typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback) {",
                    "GameView:\(index + 1): the level capsule is not behind RideHUDLayout.shows(.level, …)")
        }
    }

    /// The rule is only a rule if both rows obey it. Two HUDs drifting apart is how this defect
    /// shipped the first time: v1.31 fixed the drill's row and not the ride's.
    @Test("both HUDs put their score pill behind the one rule")
    func bothHUDsConsultTheRule() throws {
        for file in ["GameView.swift", "ConjugationGameView.swift"] {
            let lines = Self.codeLines(try Self.source(file))
            let scorePills = lines.indices.filter { lines[$0].hasPrefix("stat(icon: \"star.fill\"") }
            #expect(scorePills.count == 1, "\(file): expected one score pill, found \(scorePills.count)")
            for index in scorePills {
                let previous = lines[..<index].last { !$0.isEmpty } ?? ""
                let expected = file == "GameView.swift"
                    ? "if RideHUDLayout.shows(.score, typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback) {"
                    : "if RideHUDLayout.showsScore(typeSize) {"
                #expect(previous == expected,
                        "\(file):\(index + 1): the score pill is not behind `\(expected)`")
            }
        }
    }

    /// The v1.31 fix, on the ride's row too — **at the accessibility sizes only**. It first shipped
    /// at every size, and the results-and-ride review measured what that did at the default size: a
    /// late journey row needs ~752pt, so the unwrappable row pushed the pause button off an iPad mini
    /// in portrait and out of iPad Split View (`HUDBar`'s comment). Below the accessibility sizes the
    /// values and the capsule carry 1.32's modifiers — none — again. Mutation, 2026-09-17: the
    /// value's limit back to an unconditional `.lineLimit(1)` goes red here, and so does the
    /// capsule's `.minimumScaleFactor(0.7)`.
    ///
    /// Round 4: the value's reserve comes after `fixedSize`, which proposes no width to what it
    /// wraps — inside it, `IdealWidthReserve` would answer its reserved width at every layout and the
    /// pill would be drawn as wide as the widest value (`idealWidthReserveChangesOnlyTheIdealWidth`
    /// measures that). Mutation, 2026-09-18: the reserve moved above `.fixedSize` goes red here.
    /// (v1.33 pre-submission review, round 4)
    @Test("the HUD's values and level capsule keep to one line at the accessibility sizes, and wrap as in 1.32 below them")
    func hudValuesNeverWrap() throws {
        let lines = Self.codeLines(try Self.source("GameView.swift"))
        guard let valueLine = lines.firstIndex(of: "Text(value).foregroundStyle(.white).monospacedDigit()"),
              let levelLine = lines.firstIndex(of: "Text(session.currentLevelLabel)") else {
            Issue.record("the HUD's value Text or level capsule moved; update this test")
            return
        }
        let valueChain = Array(lines[(valueLine + 1)...].prefix { $0.hasPrefix(".") })
        #expect(valueChain == [".lineLimit(typeSize.isAccessibilitySize ? 1 : nil)",
                               ".fixedSize(horizontal: typeSize.isAccessibilitySize, vertical: false)",
                               ".reservingIdealWidth(for: reserving) { Text($0).monospacedDigit() }"],
                "the HUD value's modifiers are \(valueChain)")
        let levelChain = Array(lines[(levelLine + 1)...].prefix { $0.hasPrefix(".") })
        #expect(levelChain.contains(".lineLimit(typeSize.isAccessibilitySize ? 1 : nil)"), "\(levelChain)")
        #expect(levelChain.contains(".minimumScaleFactor(typeSize.isAccessibilitySize ? 0.7 : 1)"), "\(levelChain)")
        #expect(!levelChain.contains { $0.hasPrefix(".lineLimit(1") || $0.hasPrefix(".minimumScaleFactor(0.") || $0.hasPrefix(".fixedSize(") },
                "the level capsule has an unconditional limit again: \(levelChain)")
    }

    #if canImport(AppKit)
    /// What makes the modifiers above "1.32's below the accessibility sizes" is that their false
    /// forms — `lineLimit(nil)`, `minimumScaleFactor(1)`, `fixedSize` in neither axis — change
    /// nothing. That is SwiftUI's behaviour, not this app's, so it is measured rather than assumed:
    /// each HUD shape is laid out bare (1.32) and with the false forms, at a width that makes the
    /// value wrap and at one that does not, and the sizes must be equal. Control: the true forms at
    /// the narrow width must NOT equal the bare size, or the width is not narrow enough to tell.
    @MainActor
    @Test("the HUD modifiers' below-accessibility forms lay out exactly as no modifiers")
    func hudModifiersAreInertBelowAccessibility() {
        func size<V: View>(_ view: V, _ width: CGFloat) -> CGSize {
            NSHostingController(rootView: view.font(.system(size: 17, weight: .semibold, design: .rounded)))
                .sizeThatFits(in: CGSize(width: width, height: 1_000))
        }
        func pill<V: View>(_ value: V) -> some View {
            HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill"); value }
                .padding(.horizontal, 9).padding(.vertical, 7)
        }
        let value = "1234/5678"
        let level = "Journey · Beginner"
        for width in [40, 400] as [CGFloat] {
            let bare = size(pill(Text(value).monospacedDigit()), width)
            let below = size(pill(Text(value).monospacedDigit()
                .lineLimit(nil).fixedSize(horizontal: false, vertical: false)), width)
            #expect(bare == below, "pill at \(width)pt: 1.32 \(bare), below-AX modifiers \(below)")

            let bareLevel = size(Text(level).padding(.horizontal, 10), width)
            let belowLevel = size(Text(level).lineLimit(nil).minimumScaleFactor(1).padding(.horizontal, 10), width)
            #expect(bareLevel == belowLevel, "level at \(width)pt: 1.32 \(bareLevel), below-AX modifiers \(belowLevel)")
        }
        let narrowBare = size(pill(Text(value).monospacedDigit()), 40)
        let narrowAX = size(pill(Text(value).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)), 40)
        #expect(narrowAX != narrowBare && narrowAX.height < narrowBare.height,
                "control: at 40pt the one-line value should differ from the wrapping one (\(narrowAX) vs \(narrowBare))")
        let narrowLevelBare = size(Text(level).padding(.horizontal, 10), 40)
        let narrowLevelAX = size(Text(level).lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 10), 40)
        #expect(narrowLevelAX != narrowLevelBare, "control: the level capsule's one-line form is indistinguishable at 40pt")

        // The row's Spacer (round 2): `Spacer(minLength: nil)` below the accessibility sizes. That is
        // the value `Spacer()` builds — its only initializer defaults `minLength` to nil — and it is
        // laid out here anyway, at a width where the Spacer's minimum decides the row's width.
        // Control: the accessibility-size form, `minLength: 0`, must come out narrower there.
        func row(_ spacer: Spacer) -> some View {
            HStack(spacing: 8) { Text("N5").fixedSize(); spacer; Text("19/20").fixedSize() }
        }
        #expect(Spacer().minLength == nil)
        for width in [10, 400] as [CGFloat] {
            #expect(size(row(Spacer(minLength: nil)), width) == size(row(Spacer()), width),
                    "Spacer(minLength: nil) and Spacer() lay out differently at \(width)pt")
        }
        #expect(size(row(Spacer(minLength: 0)), 10).width < size(row(Spacer()), 10).width,
                "control: at 10pt a collapsible Spacer should make the row narrower")
    }
    #endif

    // MARK: 1b. HUD — an iPad's row at the accessibility sizes

    /// Where the line that opens `block` starts.
    static func blockHeadStart(_ block: Range<Int>, in file: CallSiteScanner.File) -> Int {
        var start = block.lowerBound
        while start > 0, file.code[start - 1] != 10 { start -= 1 }
        return start
    }

    /// The text of the line that opens `block`, up to its `{` — an `if` condition, or a call.
    static func blockHead(_ block: Range<Int>, in file: CallSiteScanner.File) -> String {
        file.text(blockHeadStart(block, in: file)..<block.lowerBound).trimmingCharacters(in: .whitespaces)
    }

    /// `text` with every run of whitespace, newlines included, collapsed to one space.
    static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `RideHUDLayout`'s arithmetic was a phone's, and round 2 of the pre-submission review found
    /// what that left out: `narrow` is the device, so an iPad at the accessibility sizes kept
    /// distance, accuracy and speed, and with values that may not wrap its row — 846pt late in a
    /// journey at AX1 — pushed the pause button off an iPad mini in portrait and out of every
    /// narrower window. At those sizes an iPad now hides the three as a phone does. Pinned on
    /// comment-blanked code, so a gate switched off as `if false { // if !(narrow || …` does not
    /// pass: each of the three sits directly in a block whose condition is exactly
    /// `if !(narrow || typeSize.isAccessibilitySize)`, and no other pill is behind an `if` on
    /// `narrow`. The widths themselves are `RideHUDLayout`'s, measured with the real `HUDBar`.
    /// Mutation, 2026-09-18: either gate back to `if !narrow {` goes red here.
    /// (v1.33 pre-submission review, round 2)
    ///
    /// **And the progress pill and the pause button are never conditional**, at any size, in either
    /// row `ViewThatFits` is offered: the progress pill sits directly in the row's `HStack`, the pause
    /// button directly in `if let onPause` (a touch device's) directly in that `HStack`. The pin above
    /// once let the progress pill go behind `if !typeSize.isAccessibilitySize {` with every test green.
    /// Mutations, 2026-09-18: that wrap, and the pause button behind `if !fallback {`, each go red
    /// here. (v1.33 pre-submission review, round 3)
    @Test("an iPad hides distance, accuracy and speed at the accessibility sizes, as a phone always does")
    func informationalPillsFollowThePhoneAtAccessibilitySizes() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        let hud = try #require(file.typeBodies(named: "HUDBar").first, "GameView has no HUDBar")
        let informational = ["bicycle", "scope", "speedometer"]
        var icons: [String] = []
        for call in file.calls(named: "stat") where hud.contains(call.nameOffset) && call.receiver.isEmpty {
            let here = file.location(call.nameOffset)
            let arguments = call.arguments.map { String(decoding: file.codeWithStrings[$0], as: UTF8.self) } ?? ""
            guard let quoted = arguments.range(of: #"icon:\s*"[^"]*""#, options: .regularExpression) else {
                Issue.record("\(here): a stat pill with no icon: literal")
                continue
            }
            let icon = String(arguments[quoted].drop { $0 != "\"" }.dropFirst().dropLast())
            icons.append(icon)
            let block = try #require(file.innermostBlock(containing: call.nameOffset, within: hud))
            let head = Self.blockHead(block, in: file)
            if informational.contains(icon) {
                #expect(head == "if !(narrow || typeSize.isAccessibilitySize)",
                        "\(here): the \(icon) pill is behind `\(head)`")
            } else if icon == "checkmark.circle.fill" {
                #expect(head == "HStack(spacing: narrow ? 8 : 14)", "\(here): the progress pill is behind `\(head)`")
            } else {
                #expect(!(head.hasPrefix("if") && head.contains("narrow")),
                        "\(here): the \(icon) pill is hidden on a phone: `\(head)`")
            }
        }
        #expect(icons.filter(informational.contains) == informational,
                "HUDBar's pills are \(icons); expected distance, accuracy and speed once each, in that order")
        #expect(icons.filter { $0 == "checkmark.circle.fill" }.count == 1, "HUDBar's pills are \(icons)")
        #expect(icons.count == 6, "HUDBar's pills are \(icons)")

        let buttons = file.calls(named: "Button").filter { hud.contains($0.nameOffset) }
        #expect(buttons.count == 1, "HUDBar has \(buttons.count) Button(s); expected the pause button")
        for button in buttons {
            let here = file.location(button.nameOffset)
            let block = try #require(file.innermostBlock(containing: button.nameOffset, within: hud))
            #expect(Self.blockHead(block, in: file) == "if let onPause",
                    "\(here): the pause button is behind `\(Self.blockHead(block, in: file))`")
            let outer = try #require(file.innermostBlock(containing: Self.blockHeadStart(block, in: file), within: hud))
            #expect(Self.blockHead(outer, in: file) == "HStack(spacing: narrow ? 8 : 14)",
                    "\(here): the pause button's `if let onPause` is behind `\(Self.blockHead(outer, in: file))`")
        }
    }

    /// Round 3 of the pre-submission review. The accessibility-size row's pills were chosen by rules
    /// alone, and its values may not wrap, so as the values grew the row outgrew the screen: late in a
    /// 150- or 500-word list ride ("149/150", "×149") it needed 368pt on a 320pt Display Zoom iPhone at
    /// AX1 — 20 of the pause button's 44pt on screen — and tighter rows that did fit showed the level
    /// capsule as "…". So at those sizes `HUDBar.body` offers `ViewThatFits(in: .horizontal)` the row
    /// as it was and then `row(fallback: true)`, which `RideHUDLayout.shows` gives one pill fewer; below
    /// them `body` is the one row and has no `ViewThatFits`, so the default-size HUD is 1.32's. Pinned
    /// on comment-blanked code. Mutations, 2026-09-18, each red here: the second row removed; the second
    /// row commented out; the two rows swapped; `ViewThatFits` at every size (the `if` removed); the
    /// else branch offering `row(fallback: true)`. (v1.33 pre-submission review, round 3)
    ///
    /// **And `row` only ever hands `fallback` on**, as `fallback: fallback` to the three `shows` gates,
    /// the two reserves and (v1.34 §B3) the progress pill's spoken suffix: every mention of the name
    /// in the body is half of such a pair. Round 3's
    /// review found `let fallback = false` at the top of the row's `HStack` made both rows identical —
    /// the fix switched off — with every test green. Mutations, 2026-09-18, each red here: that line;
    /// `if let onPause, !fallback {`. (v1.33 pre-submission review, round 4)
    @Test("the ride row falls back through ViewThatFits at the accessibility sizes, and only there")
    func rideRowFallsBackAtAccessibilitySizesOnly() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        let hud = try #require(file.typeBodies(named: "HUDBar").first, "GameView has no HUDBar")
        let fits = file.calls(named: "ViewThatFits").filter { hud.contains($0.nameOffset) }
        #expect(fits.count == 1, "HUDBar has \(fits.count) ViewThatFits")
        let rows = file.calls(named: "row").filter { hud.contains($0.nameOffset) && $0.receiver.isEmpty }
        let arguments = rows.map { call in call.arguments.map { Self.collapsed(file.text($0)) } ?? "" }
        #expect(arguments == ["fallback: false", "fallback: true", "fallback: false"], "HUDBar builds its rows as \(arguments)")
        guard let fit = fits.first, rows.count == 3 else { return }

        #expect(fit.arguments.map { Self.collapsed(file.text($0)) } == "in: .horizontal")
        let accessible = try #require(file.innermostBlock(containing: fit.nameOffset, within: hud))
        #expect(Self.blockHead(accessible, in: file) == "if typeSize.isAccessibilitySize",
                "ViewThatFits is behind `\(Self.blockHead(accessible, in: file))`")
        let children = fit.closures.map { Self.collapsed(file.text($0)) }
        #expect(children == ["{ row(fallback: false) row(fallback: true) }"], "ViewThatFits is offered \(children)")

        let below = try #require(file.innermostBlock(containing: rows[2].nameOffset, within: hud))
        #expect(Self.blockHead(below, in: file) == "} else" && file.line(of: accessible.upperBound - 1) == file.line(of: below.lowerBound),
                "the one-row branch is not the else of `if typeSize.isAccessibilitySize`")
        #expect(Self.collapsed(file.text(below)) == "{ row(fallback: false) }", "below the accessibility sizes: \(file.text(below))")

        // `row` is the whole row: every pill and the pause button are built inside it.
        let rowFunctions = file.functions(named: "row").filter { hud.contains($0.keywordOffset) }
        #expect(rowFunctions.count == 1, "HUDBar declares \(rowFunctions.count) row function(s)")
        if let body = rowFunctions.first?.body {
            let parts = (file.calls(named: "stat") + file.calls(named: "Button")).filter { hud.contains($0.nameOffset) }
            #expect(parts.count == 7 && parts.allSatisfy { body.contains($0.nameOffset) },
                    "a pill or the pause button is built outside row(fallback:)")

            let handedOn = try NSRegularExpression(pattern: #"\bfallback:\s*fallback\b(?=\s*[,)])"#)
            let text = file.text(body)
            let pairs = handedOn.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            let mentions = file.mentions(of: "fallback").filter { body.contains($0) }.count
            // Six since v1.34 §B3: the three `shows` gates, the two reserves, and the progress
            // pill's `RideHUDSpoken.hiddenValues` — the suffix must be the row's own, or the row
            // `ViewThatFits` draws would speak the other row's hidden values.
            #expect(pairs == 6 && mentions == 2 * pairs,
                    "row(fallback:) mentions `fallback` \(mentions) times with \(pairs) `fallback: fallback` pairs; expected 12 and 6")
        }
    }

    #if canImport(AppKit)
    /// Whether `ViewThatFits` takes a child at `width`: the child is marked by a frame taller than a
    /// line, and the last child by a taller one still. **The marker must not be shorter than a line.**
    /// Round 3's version framed the child 10pt tall, which made a 17pt Text shrink to fit the HEIGHT
    /// and report that shrunk width — so it measured a shrinking label "taken at 0.8 of its width", and
    /// a comment and a commit message said `ViewThatFits` counts the level capsule's shrink as room.
    /// With a marker a line tall or more the same label is taken only at its full width.
    /// (v1.33 pre-submission review, round 4)
    @MainActor
    static func taken<V: View>(_ first: V, at width: CGFloat, marker: CGFloat = 60) -> Bool {
        NSHostingController(rootView: ViewThatFits(in: .horizontal) {
            first.frame(height: marker)
            Color.clear.frame(width: 1, height: marker + 10)
        }).sizeThatFits(in: CGSize(width: width, height: marker + 100)).height == marker
    }

    /// A view's ideal width: `fixedSize` proposes no width, as `ViewThatFits` asks.
    @MainActor
    static func idealWidth<V: View>(_ view: V) -> CGFloat {
        NSHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 2_000, height: 200)).width
    }

    /// What `HUDBar`'s `ViewThatFits` counts as fitting — SwiftUI's behaviour, so measured rather than
    /// assumed. It compares each child's ideal width, so a one-line label with a 0.7 shrink floor is
    /// taken at its full width and not 2pt narrower, where it could only shrink; a value with
    /// `fixedSize` likewise. So `HUDBar`'s first row is kept only while it fits with the level capsule
    /// unshrunk — the capsule is never shrunk or "…" in a first row. Round 3's version of this test
    /// claimed the opposite because its marker squeezed the label's height (`taken`). Mutation,
    /// 2026-09-18: the marker back to round 3's 10pt, which is the whole of round 3's finding, goes red
    /// here. (Dropping the label's `lineLimit(1)` does NOT: a Text's ideal width is its single line
    /// either way, which is the same fact this test is about.) (v1.33 pre-submission review, round 4)
    @MainActor
    @Test("ViewThatFits takes a row only at its unshrunk width")
    func viewThatFitsTakesARowOnlyAtItsUnshrunkWidth() {
        let font = Font.system(size: 17, weight: .heavy, design: .rounded)
        let label = Text("Journey Beginner").font(font)
        let full = Self.idealWidth(label)
        #expect(full > 100, "the instrument is not laying the label out: \(full)pt")
        let capsule = label.lineLimit(1).minimumScaleFactor(0.7)
        #expect(Self.taken(capsule, at: full.rounded(.up)), "a shrinkable label was not taken at its full width")
        #expect(!Self.taken(capsule, at: full.rounded(.up) - 2), "a shrinking label was counted as room")
        let value = Text("149/150").font(font).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
        let valueWidth = Self.idealWidth(value)
        #expect(Self.taken(value, at: valueWidth.rounded(.up)))
        #expect(!Self.taken(value, at: valueWidth.rounded(.up) - 2), "a fixed-size value was taken narrower than itself")
    }
    #endif

    // MARK: 1c. HUD — the first row's ideal width grows only with the ride (round 4)

    static func entries(_ levels: [JLPTLevel]) -> [VocabEntry] {
        levels.enumerated().map { index, level in
            VocabEntry(id: "reserve\(index)", surface: "みず", kana: "みず", partsOfSpeech: ["n"], jlpt: level, meanings: [:])
        }
    }

    /// Round 4 of the pre-submission review. `ViewThatFits` compares ideal widths, and the first row's
    /// depended on the current combo ("—", "×9", "×10") and the current word's level label ("N1" is
    /// narrower than "N5"), so at tight widths the combo pill left as a streak passed ×9 and came
    /// back after every mistake, and a mixed-level list changed rows word to word. So the first row,
    /// at the accessibility sizes only, reserves the widest of each (`IdealWidthReserve`), and these
    /// are the values reserved. Expected values are literals. Mutations, 2026-09-18, each red here:
    /// `comboReserve` without the dash; `comboReserve` for the second row too; `levelReserve` below
    /// the accessibility sizes; `levelReserve` of every JLPT level rather than the ride's.
    /// (v1.33 pre-submission review, round 4)
    @Test("the first row reserves the ride's widest combo and level label, at the accessibility sizes only")
    func firstRowReservesTheRidesWidestValues() {
        for (combo, shown) in [(0, "—"), (1, "—"), (2, "×2"), (9, "×9"), (10, "×10"), (149, "×149"), (499, "×499")] {
            #expect(RideHUDLayout.comboValue(combo) == shown, "combo \(combo)")
        }
        let combos: [(wordCount: Int, reserve: [String])] =
            [(0, ["—"]), (1, ["—"]), (2, ["—", "×2"]), (9, ["—", "×9"]), (20, ["—", "×20"]), (150, ["—", "×150"]),
             (500, ["—", "×500"])]
        let levels: [(levels: [JLPTLevel], reserve: [String])] =
            [([], []), ([.n5, .n5], ["N5"]), ([.n4], ["N4"]), ([.n5, .n1, .n4, .n1], ["N1", "N4", "N5"]),
             ([.n3, .n2, .n1, .n4, .n5], ["N1", "N2", "N3", "N4", "N5"])]
        for size in Self.belowAccessibility {
            for fallback in [false, true] {
                for (wordCount, _) in combos {
                    #expect(RideHUDLayout.comboReserve(size, fallback: fallback, wordCount: wordCount) == [], "\(size)")
                }
                for (list, _) in levels {
                    #expect(RideHUDLayout.levelReserve(size, fallback: fallback, words: Self.entries(list)) == [], "\(size)")
                }
            }
        }
        for size in Self.accessibility {
            for (wordCount, reserve) in combos {
                #expect(RideHUDLayout.comboReserve(size, fallback: false, wordCount: wordCount) == reserve,
                        "\(size), \(wordCount) words")
                #expect(RideHUDLayout.comboReserve(size, fallback: true, wordCount: wordCount) == [],
                        "\(size): the second row is ViewThatFits' last child and needs no reserve")
            }
            for (list, reserve) in levels {
                #expect(RideHUDLayout.levelReserve(size, fallback: false, words: Self.entries(list)) == reserve,
                        "\(size), levels \(list)")
                #expect(RideHUDLayout.levelReserve(size, fallback: true, words: Self.entries(list)) == [], "\(size)")
            }
        }
    }

    /// The reserve's premises, on a real `GameSession` stepped key by key: a streak grows by one per
    /// word completed, so the combo pill never shows more digits than "×\(wordCount)", and a clean ride
    /// reaches that value (the reserve is not wider than the ride can be); every level label the ride
    /// shows is one it reserved. Mutations, 2026-09-18, each red here: `comboReserve` without the dash;
    /// `comboValue` with an ASCII "x"; a reserve a digit short ("×\(wordCount / 10)") and a
    /// `levelReserve` of the first word's level only — those two with the literal table above moved to
    /// match, so this test is the only one that sees them. An off-by-one reserve ("×\(wordCount - 1)")
    /// is caught by the table, not here: it is the same width, which is all this asks about.
    @Test("no combo or level label a ride shows is wider than its first row reserves")
    func reserveCoversWhatARideShows() {
        let mixed: [JLPTLevel] = [.n5, .n1, .n4, .n2, .n3]
        for (count, streaks) in [(12, [12]), (12, [3, 1, 8]), (30, [9, 1, 10, 2, 8])] {
            let words = (0..<count).map { index in
                VocabEntry(id: "ride\(index)", surface: "ねこ", kana: "ねこ", partsOfSpeech: ["n"],
                           jlpt: mixed[index % mixed.count], meanings: [:])
            }
            let session = GameSession(words: words, config: .init(newWordCount: count, reviewWordCount: 0))
            let combos = RideHUDLayout.comboReserve(.accessibility1, fallback: false, wordCount: session.wordCount)
            let labels = RideHUDLayout.levelReserve(.accessibility1, fallback: false, words: session.wordList)
            let widest = combos.last ?? ""
            var seen = Set<String>()
            func check() {
                let shown = RideHUDLayout.comboValue(session.combo)
                #expect(combos.contains(shown) || (shown.hasPrefix("×") && shown.count <= widest.count),
                        "\(count) words: the pill shows \(shown), the reserve is \(combos)")
                #expect(session.currentLevelLabel.isEmpty || labels.contains(session.currentLevelLabel),
                        "the level capsule shows \(session.currentLevelLabel), the reserve is \(labels)")
                seen.insert(shown)
            }
            check()
            for streak in streaks {
                for _ in 0..<streak {
                    while let key = session.expectedNextCharacters.sorted().first {
                        let result = session.input(key)
                        check()
                        if case .completed = result { break }
                    }
                }
                _ = session.input("q")
                check()
            }
            #expect(session.isFinished)
            if streaks == [count] {
                #expect(seen.contains(widest), "a clean \(count)-word ride never showed \(widest): \(seen.sorted())")
            }
        }
    }

    /// The reserve reaches the pills: at the top of `row(fallback:)` the two reserves are asked with
    /// the row's own `fallback`, the level capsule's Text carries its reserve before its font (so the
    /// placeholders are set in that font), and the combo pill draws `comboValue` and is handed its
    /// reserve. Pinned on comment-blanked code. Mutations, 2026-09-18, each red here: the level
    /// capsule's `.reservingIdealWidth(for: levels)` removed; moved below `.scaledSystemFont`; the combo
    /// pill without `reserving: combos`; `comboReserve` asked with `fallback: true`; the combo value
    /// spelled out again at the call site instead of `RideHUDLayout.comboValue`.
    /// (v1.33 pre-submission review, round 4)
    @Test("the ride row hands its level capsule and combo pill the first row's reserve")
    func rideRowHandsThePillsTheirReserve() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        let hud = try #require(file.typeBodies(named: "HUDBar").first, "GameView has no HUDBar")
        let row = try #require(file.functions(named: "row").first { hud.contains($0.keywordOffset) }?.body)
        let code = Self.collapsed(file.text(row))
        for declaration in ["let levels = RideHUDLayout.levelReserve(typeSize, fallback: fallback, words: session.wordList)",
                            "let combos = RideHUDLayout.comboReserve(typeSize, fallback: fallback, wordCount: session.wordCount)"] {
            #expect(code.contains(declaration), "row(fallback:) no longer declares `\(declaration)`")
        }
        #expect(code.contains("Text(session.currentLevelLabel) .reservingIdealWidth(for: levels) "
                              + ".scaledSystemFont(14, weight: .heavy, design: .rounded)"),
                "the level capsule's Text is not reserved, or not before its font")
        for name in ["levels", "combos"] {
            let uses = file.mentions(of: name).filter { row.contains($0) }.count
            #expect(uses == 2, "`\(name)` is mentioned \(uses) times in row(fallback:); expected its declaration and one use")
        }
        let flames = file.calls(named: "stat").filter { call in
            row.contains(call.nameOffset)
                && (call.arguments.map { String(decoding: file.codeWithStrings[$0], as: UTF8.self) } ?? "")
                    .contains("\"flame.fill\"")
        }
        #expect(flames.count == 1, "row(fallback:) has \(flames.count) combo pill(s)")
        for flame in flames {
            let arguments = flame.arguments.map { Self.collapsed(file.text($0)) } ?? ""
            #expect(arguments.contains("value: RideHUDLayout.comboValue(session.combo),") && arguments.hasSuffix("reserving: combos"),
                    "the combo pill is built as stat(\(arguments))")
        }
        #expect(file.calls(named: "reservingIdealWidth").filter { hud.contains($0.nameOffset) }.count == 2,
                "HUDBar reserves somewhere other than the level capsule and the pill value")
    }

    #if canImport(AppKit)
    /// `IdealWidthReserve` is only a fix if it changes what `ViewThatFits` compares and nothing it
    /// draws. Measured with the HUD value's own modifiers at its two AX1 sizes (15 and 17pt × 28/17):
    /// the reserved "—" answers the widest value's ideal width, lays out and renders byte for byte as
    /// the plain "—" at a real width, and is taken by `ViewThatFits` at the widest value's width and not
    /// 2pt narrower, where the plain one is. The reserve's premise — tabular digits, so "×\(wordCount)"
    /// is as wide as any value of as many digits — is measured too. Control: the reserve INSIDE
    /// `fixedSize` lays out at the widest value's width, which is why `stat` applies it after.
    /// Mutations, 2026-09-18, each red here: the Layout reserving for every proposal (its
    /// `guard proposal.width == nil` removed); the placeholders not `.hidden()`; the Layout ignoring
    /// its placeholders. (v1.33 pre-submission review, round 4)
    @MainActor
    @Test("IdealWidthReserve changes a view's ideal width and nothing it draws")
    func idealWidthReserveChangesOnlyTheIdealWidth() {
        func value(_ text: String) -> some View {
            Text(text).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        func laidOut<V: View>(_ view: V, at width: CGFloat) -> CGSize {
            NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 200))
        }
        func pixels<V: View>(_ view: V, at width: CGFloat) -> Data? {
            let renderer = ImageRenderer(content: ZStack(alignment: .leading) {
                Color.white
                HStack(spacing: 8) { view; Color.red.frame(width: 20, height: 20); Spacer(minLength: 0) }
            }.frame(width: width, height: 60))
            renderer.scale = 2
            return renderer.cgImage?.dataProvider?.data as Data?
        }
        for points in [15 * 28 / 17, 17 * 28 / 17] as [CGFloat] {
            let font = Font.system(size: points, weight: .semibold, design: .rounded)
            let three = ["×100", "×111", "×149", "×150", "×499", "×500", "×999"].map { Self.idealWidth(value($0).font(font)) }
            let two = ["×10", "×11", "×19", "×99"].map { Self.idealWidth(value($0).font(font)) }
            #expect(Set(three).count == 1 && Set(two).count == 1 && two[0] < three[0],
                    "\(points)pt: the combo's digits are not tabular — three digits \(three), two \(two)")

            let reserve = ["—", "×150"]
            let plain = value("—").font(font)
            let reserved = value("—").reservingIdealWidth(for: reserve) { Text($0).monospacedDigit() }.font(font)
            let widest = Self.idealWidth(value("×150").font(font))
            #expect(widest > Self.idealWidth(plain) + 10, "\(points)pt: the instrument cannot tell the values apart")
            #expect(Self.idealWidth(reserved) == widest, "\(points)pt: the reserve's ideal width is \(Self.idealWidth(reserved)), not \(widest)")
            for width in [widest + 40, 400] {
                #expect(laidOut(reserved, at: width) == laidOut(plain, at: width), "\(points)pt at \(width)pt: the reserve changed the layout")
                let drawn = pixels(reserved, at: width)
                #expect(drawn != nil && drawn == pixels(plain, at: width), "\(points)pt at \(width)pt: the reserve changed what is drawn")
            }
            #expect(Self.taken(reserved, at: widest.rounded(.up)), "\(points)pt: the reserved value was not taken at the widest width")
            #expect(!Self.taken(reserved, at: widest.rounded(.up) - 2), "\(points)pt: the reserve does not reach ViewThatFits")
            #expect(Self.taken(plain, at: widest.rounded(.up) - 2), "control: the plain value should fit 2pt under the widest")

            let inside = Text("—").monospacedDigit().lineLimit(1)
                .reservingIdealWidth(for: reserve) { Text($0).monospacedDigit() }
                .fixedSize(horizontal: true, vertical: false).font(font)
            #expect(laidOut(inside, at: 400).width == widest, "control: a reserve inside fixedSize should lay out at the widest width")
        }
    }
    #endif

    /// The same review's cheaper finding: a 320pt Display Zoom iPhone late in a journey needed a
    /// 328pt row at AX1, the pause button 4pt past the edge, and the 8pt it lacked was the Spacer's
    /// default minimum. So the row's Spacer may collapse at the accessibility sizes, as
    /// `ConjugationHUD`'s already does, and is `Spacer()`'s value below them (measured above).
    /// Mutation, 2026-09-18: `Spacer()` goes red here.
    @Test("the ride row's Spacer may collapse at the accessibility sizes, and only there")
    func rideSpacerCollapsesAtAccessibilitySizes() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        let hud = try #require(file.typeBodies(named: "HUDBar").first, "GameView has no HUDBar")
        let spacers = file.calls(named: "Spacer").filter { hud.contains($0.nameOffset) }
        #expect(spacers.count == 1, "HUDBar has \(spacers.count) Spacer(s)")
        for spacer in spacers {
            let arguments = spacer.arguments.map { file.text($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            #expect(arguments == "minLength: typeSize.isAccessibilitySize ? 0 : nil",
                    "\(file.location(spacer.nameOffset)): Spacer(\(arguments))")
        }
    }

    // MARK: 2. Drill HUD — the mode badge

    @Test("the badge keeps today's words below the accessibility sizes and the menu's name at them")
    func badgeLabel() {
        #expect(ConjugationHUDLayout.badgeLabel(zh: false, accessibilitySize: false) == "Conjugate")
        #expect(ConjugationHUDLayout.badgeLabel(zh: true, accessibilitySize: false) == "变形")
        for zh in [false, true] {
            #expect(ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: true)
                    == GameMode.conjugation.shortLabel(zh: zh))
        }
    }

    #if canImport(AppKit)
    /// The room the badge was given is a measurement (`ConjugationHUD`'s comment): late in a drill,
    /// score hidden, badge laid out first, Spacer collapsed, on a 393pt phone with the keyboard
    /// dismissed — **69pt**. The label has to fit that at its 0.7 shrink floor, with its 20pt of
    /// capsule padding, at AX1 (14pt body-relative → 14 × 28/17). Measured with the same font the
    /// badge uses, so a rename of the menu chip that would truncate the badge again fails here.
    @Test("the accessibility-size badge fits the worst measured room at its shrink floor")
    func badgeFitsWorstCaseRoom() {
        let room: CGFloat = 69
        let size: CGFloat = 14 * 28 / 17
        var font = NSFont.systemFont(ofSize: size, weight: .heavy)
        if let rounded = font.fontDescriptor.withDesign(.rounded),
           let resolved = NSFont(descriptor: rounded, size: size) { font = resolved }
        for zh in [false, true] {
            let label = ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: true)
            let width = NSAttributedString(string: label, attributes: [.font: font]).size().width
            let atFloor = width * 0.7 + 20
            #expect(atFloor <= room, "\(label): \(atFloor)pt at its floor, room \(room)pt")
        }
        // Negative control: the label this replaced must NOT fit, or the test measures nothing.
        let old = NSAttributedString(string: "Conjugate", attributes: [.font: font]).size().width
        #expect(old * 0.7 + 20 > room, "the control fits — the instrument cannot tell the labels apart")
    }
    #endif

    // MARK: 3. The typing target wraps

    /// `ViewThatFits` with today's `HStack` first and `MenuFlow` second, the glyphs drawn by one
    /// helper — and those glyphs never given a shrink allowance, because shrinking the thing being
    /// typed is the fix this replaced being ruled out.
    @Test("the drill answer and the coach's word wrap instead of overflowing, and never shrink")
    func glyphRowsWrap() throws {
        for (file, helper, spacing) in [("ConjugationGameView.swift", "answerGlyphs(", "2"),
                                        ("CoachView.swift", "replayGlyphs(", "2")] {
            let lines = Self.codeLines(try Self.source(file))
            guard let start = lines.firstIndex(of: "ViewThatFits(in: .horizontal) {") else {
                Issue.record("\(file): no ViewThatFits(in: .horizontal)")
                continue
            }
            #expect(lines[start + 1].hasPrefix("HStack(spacing: \(spacing)) { \(helper)"),
                    "\(file): the first child must be today's row")
            #expect(lines[start + 2].hasPrefix("MenuFlow(spacing: \(spacing), rowSpacing: 4) { \(helper)"),
                    "\(file): the fallback must wrap")
            guard let body = lines.firstIndex(where: { $0.hasPrefix("private func \(helper)") }) else {
                Issue.record("\(file): \(helper) not found")
                continue
            }
            let helperBody = lines[body...].prefix { $0 != "}" }
            #expect(!helperBody.contains { $0.contains("minimumScaleFactor") },
                    "\(file): the typing target must not shrink")
        }
    }

    // MARK: 4. Drill prompt — the verb and its reading

    /// Base point sizes of the verb (largeTitle-relative) and its reading (body-relative), as
    /// `ConjugationCard` declares them, for the keyboard-up and keyboard-down cards.
    static let cards: [(verb: CGFloat, reading: CGFloat)] = [(36, 18), (56, 24)]
    /// Dynamic Type point sizes (iOS table): largeTitle 34 and body 17 at the default size, then
    /// AX1…AX5. The game screens cap at AX1; the rest cover a raised cap.
    static let accessibilityScales: [(largeTitle: CGFloat, body: CGFloat)] =
        [(44, 28), (48, 33), (52, 40), (56, 47), (60, 53)].map { ($0.0 / 34, $0.1 / 17) }

    @Test("below the accessibility sizes the verb's floor is today's 0.4")
    func verbFloorUnchangedBelowAccessibility() {
        for card in Self.cards {
            for factor in [1.0, 1.1, 1.35] as [CGFloat] {
                #expect(ConjugationCardLayout.verbScaleFloor(
                    verbPoints: card.verb * factor, readingPoints: card.reading * factor,
                    accessibilitySize: false) == 0.4)
            }
        }
        #expect(ConjugationCardLayout.showsFormArrow(accessibilitySize: false))
    }

    @Test("at the accessibility sizes the verb can never be smaller than its reading")
    func verbNeverBelowReading() {
        for card in Self.cards {
            for scale in Self.accessibilityScales {
                let verb = card.verb * scale.largeTitle, reading = card.reading * scale.body
                let floor = ConjugationCardLayout.verbScaleFloor(
                    verbPoints: verb, readingPoints: reading, accessibilitySize: true)
                #expect(verb * floor >= reading - 0.001,
                        "verb \(verb)pt × \(floor) = \(verb * floor) < reading \(reading)pt")
                #expect(floor >= 0.4 && floor <= 1)
            }
        }
        // Where the defect was seen — AX1, keyboard up — the rule must actually bite.
        let ax1 = Self.accessibilityScales[0]
        #expect(ConjugationCardLayout.verbScaleFloor(verbPoints: 36 * ax1.largeTitle,
                                                     readingPoints: 18 * ax1.body,
                                                     accessibilitySize: true) > 0.6)
        #expect(!ConjugationCardLayout.showsFormArrow(accessibilitySize: true))
    }

    // MARK: 5. Ride card — the corner controls

    @Test("the corner reserve is zero below the accessibility sizes")
    func cornerReserveZeroBelowAccessibility() {
        for glyph in [15, 18, 20.3, 24.4] as [CGFloat] {
            for (pad, card) in [(10, 14), (14, 24)] as [(CGFloat, CGFloat)] {
                #expect(RideCardLayout.cornerControlReserve(glyphPoints: glyph, controlPadding: pad,
                                                            cardPadding: card, accessibilitySize: false) == 0)
            }
        }
    }

    #if canImport(AppKit)
    /// The reserve is built from a measured em width; this re-measures the real glyphs' layout
    /// width rather than restating the constant, so the reserve is checked against the controls
    /// it is for — the ★ and `SpeakButton`'s speaker — at the AX1 sizes of both card layouts.
    ///
    /// **Why the comparison is `reserve >= reach` and not `reserve >= reach + 1`.** The first
    /// constant (1.42) passed here by 0.08pt, fitted to one Mac's measurement, so a CI runner whose
    /// SF Symbols metrics or rounding differ by a tenth of a point could fail — or, worse, a real
    /// device could overlap while this passed. The headroom went into the product instead
    /// (`RideCardLayout.widestCornerGlyphEm`, 1.46: ≥ 1pt at AX1 on this Mac in both layouts). The
    /// test keeps asking only the product's question — does the reserve clear what the glyph
    /// reaches on THIS machine — because demanding the headroom here would tie the test to this
    /// Mac's numbers again. Mutation, 2026-09-17: 1.41 goes red on the speaker keyboard-up.
    @MainActor
    @Test("at the accessibility sizes the reserve clears both corner controls as SwiftUI lays them out")
    func cornerReserveClearsTheControls() {
        func layoutWidth(_ symbol: String, _ points: CGFloat) -> CGFloat {
            NSHostingView(rootView: Image(systemName: symbol).font(.system(size: points)).fixedSize())
                .fittingSize.width
        }
        let ax1 = CGFloat(28) / 17
        for (base, pad, card) in [(15, 10, 14), (18, 14, 24)] as [(CGFloat, CGFloat, CGFloat)] {
            let glyph = base * ax1
            let reserve = RideCardLayout.cornerControlReserve(glyphPoints: glyph, controlPadding: pad,
                                                              cardPadding: card, accessibilitySize: true)
            for symbol in ["star", "star.fill", "speaker.wave.2"] {
                let width = layoutWidth(symbol, glyph)
                #expect(width > glyph * 0.5, "\(symbol) measured \(width)pt — the instrument is not laying out")
                let reach = width + 2 * pad - card
                #expect(reserve >= reach, "\(symbol) at \(glyph)pt reaches \(reach)pt, reserve \(reserve)pt")
            }
        }
    }
    #endif

    // MARK: 5b. Every rule above is handed the real size

    /// The pure rules above are each tested at `accessibilitySize: false` and `true`, which says
    /// nothing about what the views pass. The review passed a literal `false` at the verb's shrink
    /// floor, the drill badge's label and the ride card's corner reserve, one at a time, and the
    /// target stayed green each time — the AX5 fixes switched off, the tests unaware. So every call
    /// to a rule that takes `accessibilitySize:` must pass `typeSize.isAccessibilitySize`, or a
    /// `let` in an enclosing block that is exactly that, where `typeSize` is the view's
    /// `@Environment(\.dynamicTypeSize)`.
    static let accessibilityRules: [(receiver: String, name: String, minimumCalls: Int)] = [
        ("ConjugationHUDLayout", "badgeLabel", 1),
        ("ConjugationCardLayout", "verbScaleFloor", 1),
        ("ConjugationCardLayout", "showsFormArrow", 1),
        ("RideCardLayout", "cornerControlReserve", 1),
    ]

    /// What is wrong with the `accessibilitySize:` argument of each call to `receiver.name` in
    /// `file`, and how many calls were read.
    static func accessibilityArgumentProblems(_ file: CallSiteScanner.File, receiver: String, name: String)
        -> (calls: Int, problems: [String]) {
        let code = file.code
        let calls = file.calls(named: name).filter { CallSiteScanner.receiverComponents($0.receiver) == [receiver] }
        let environment = #"@Environment\(\s*\\\.dynamicTypeSize\s*\)\s*(?:private\s+)?var\s+typeSize\b"#
        var problems: [String] = []
        for call in calls {
            let here = "\(file.location(call.nameOffset)) \(receiver).\(name)"
            guard let arguments = call.arguments else { problems.append("\(here): no arguments"); continue }
            // The `accessibilitySize:` argument, up to the next top-level comma.
            let text = file.text(arguments)
            guard let label = text.range(of: #"\baccessibilitySize\s*:"#, options: .regularExpression) else {
                problems.append("\(here): no accessibilitySize: argument"); continue
            }
            var depth = 0
            var value = ""
            for character in text[label.upperBound...] {
                if "([{".contains(character) { depth += 1 } else if ")]}".contains(character) { depth -= 1 }
                if depth < 0 || (depth == 0 && character == ",") { break }
                value.append(character)
            }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value != "typeSize.isAccessibilitySize" {
                // A local: the nearest `let <value> =` before the call, in a block that holds the call.
                let local = CallSiteScanner.occurrences(of: Array("let".utf8), in: code)
                    .filter { $0 < call.nameOffset }
                    .compactMap { at -> (Int, String)? in
                        let nameStart = CallSiteScanner.skipSpace(code, at + 3, newlines: false)
                        guard let (word, end) = CallSiteScanner.word(in: code, at: nameStart), word == value else { return nil }
                        var lineEnd = end
                        while lineEnd < code.count, code[lineEnd] != 10 { lineEnd += 1 }
                        return (at, String(decoding: code[end..<lineEnd], as: UTF8.self).trimmingCharacters(in: .whitespaces))
                    }
                    .last
                guard let (letOffset, initialiser) = local,
                      initialiser == "= typeSize.isAccessibilitySize",
                      file.innermostBlock(containing: letOffset, within: 0..<code.count)?.contains(call.nameOffset) == true
                else {
                    problems.append("\(here) is passed accessibilitySize: \(value), not the view's typeSize.isAccessibilitySize")
                    continue
                }
            }
            let owner = file.declarations
                .filter { CallSiteScanner.typeKeywords.contains($0.keyword) && $0.body?.contains(call.nameOffset) == true }
                .min { $0.body!.count < $1.body!.count }
            if let owner, let body = owner.body,
               file.text(body).range(of: environment, options: .regularExpression) != nil {
                continue
            }
            problems.append("\(here): typeSize is not the enclosing view's @Environment(\\.dynamicTypeSize)")
        }
        return (calls.count, problems)
    }

    @Test("every accessibility-size rule is passed the view's real size, never a constant")
    func rulesAreHandedTheRealSize() throws {
        // Controls, through the same function: the shapes the views use pass; each mutation the
        // review ran (a literal `false`), a local that is not the size, a local from another block,
        // and a `typeSize` that is not the environment's are each reported.
        let sample = CallSiteScanner.File(path: "Sample.swift", source: #"""
            struct Good: View {
                @Environment(\.dynamicTypeSize) private var typeSize
                var body: some View {
                    let accessibilitySize = typeSize.isAccessibilitySize
                    Text(ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: accessibilitySize))
                        .padding(.horizontal, RideCardLayout.cornerControlReserve(glyphPoints: g, controlPadding: 1,
                            cardPadding: 2, accessibilitySize: typeSize.isAccessibilitySize))
                }
            }
            struct Bad: View {
                @Environment(\.dynamicTypeSize) private var typeSize
                var other: some View {
                    let accessibilitySize = typeSize.isAccessibilitySize
                    return Text(x)
                }
                var body: some View {
                    let big = typeSize >= .xxLarge
                    Text(ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: false))
                    Text(ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: big))
                    Text(ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: accessibilitySize))
                }
            }
            struct NotTheEnvironment: View {
                let typeSize: DynamicTypeSize
                var body: some View {
                    Text(ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: typeSize.isAccessibilitySize))
                }
            }
            """#)
        let badge = Self.accessibilityArgumentProblems(sample, receiver: "ConjugationHUDLayout", name: "badgeLabel")
        #expect(badge.calls == 5)
        #expect(badge.problems.map { $0.split(separator: " ").first.map(String.init) ?? "" }
                == ["Sample.swift:18", "Sample.swift:19", "Sample.swift:20", "Sample.swift:26"],
                "\(badge.problems)")
        let reserve = Self.accessibilityArgumentProblems(sample, receiver: "RideCardLayout", name: "cornerControlReserve")
        #expect(reserve.calls == 1 && reserve.problems.isEmpty, "a multi-line call passing the size was reported: \(reserve.problems)")

        let files = try CallSiteScanner.shippedSources.get()
        for rule in Self.accessibilityRules {
            var calls = 0
            for file in files {
                let result = Self.accessibilityArgumentProblems(file, receiver: rule.receiver, name: rule.name)
                calls += result.calls
                #expect(result.problems.isEmpty, "\(result.problems)")
            }
            #expect(calls >= rule.minimumCalls, "\(rule.receiver).\(rule.name) has \(calls) call(s) — the scan found nothing to check")
        }
    }

    // MARK: 6. Coach — the key pills

    @Test("the coach's one-line floor never lets text drop below its default size")
    func coachFloorKeepsDefaultSize() {
        #expect(CoachLayout.legibleScaleFloor(basePoints: 14, scaledPoints: 14) == 1)
        #expect(CoachLayout.legibleScaleFloor(basePoints: 14, scaledPoints: 12) == 1,
                "a size below the base must never be told to grow past 1")
        for bodyAtSize in [28, 33, 40, 47, 53] as [CGFloat] {
            let scaled = 14 * bodyAtSize / 17
            let floor = CoachLayout.legibleScaleFloor(basePoints: 14, scaledPoints: scaled)
            #expect(scaled * floor >= 14 - 0.001, "\(scaled)pt × \(floor)")
            #expect(floor < 1, "at \(scaled)pt a long spelling must be allowed to shrink at all")
        }
    }

    @Test("the coach stacks its key pills only at the accessibility sizes, with the floor applied")
    func coachStacksOnlyAtAccessibilitySizes() throws {
        let lines = Self.codeLines(try Self.source("CoachView.swift"))
        guard let branch = lines.firstIndex(of: "if typeSize.isAccessibilitySize {") else {
            Issue.record("CoachView: the accessibility-size branch is gone")
            return
        }
        let stacked = lines[branch...].prefix { $0 != "} else {" }
        #expect(stacked.contains { $0.hasPrefix("VStack(") })
        #expect(stacked.filter { $0 == ".lineLimit(1).minimumScaleFactor(pillFloor).truncationMode(.head)" }.count == 2,
                "both pills must be held to one line with the legibility floor")
        #expect(stacked.contains { $0.contains("CoachLayout.legibleScaleFloor(basePoints: 14, scaledPoints: keyPillPoints)") })
    }
}
