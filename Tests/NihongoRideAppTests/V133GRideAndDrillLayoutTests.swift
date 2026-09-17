import Testing
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
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

    @Test("the score pill is hidden at exactly the accessibility sizes")
    func scoreHiddenOnlyAtAccessibilitySizes() {
        #expect(Self.accessibility.count == 5 && Self.belowAccessibility.count == 7,
                "DynamicTypeSize changed shape; re-read what this test assumes")
        for size in Self.belowAccessibility {
            #expect(RideHUDLayout.showsScore(size), "default-size HUD must not change at \(size)")
            for scoreIsTheRide in [false, true] {
                #expect(RideHUDLayout.showsScore(size, scoreIsTheRide: scoreIsTheRide)
                        && RideHUDLayout.showsCombo(size, scoreIsTheRide: scoreIsTheRide),
                        "default-size HUD must not change at \(size)")
            }
        }
        for size in Self.accessibility {
            #expect(!RideHUDLayout.showsScore(size), "\(size)")
            #expect(RideHUDLayout.showsCombo(size), "\(size): a ride that drops its score keeps its combo")
            // Time Attack: the score stays, the combo goes — exactly one pill hidden either way.
            #expect(RideHUDLayout.showsScore(size, scoreIsTheRide: true), "\(size): Time Attack lost its score")
            #expect(!RideHUDLayout.showsCombo(size, scoreIsTheRide: true), "\(size)")
        }
    }

    @Test("Time Attack is the ride that keeps its score, and the drill is not")
    func timeAttackKeepsItsScore() throws {
        let game = Self.codeLines(try Self.source("GameView.swift"))
        #expect(game.contains("private var scoreIsTheRide: Bool { session.mode == .timeAttack }"),
                "GameView no longer derives scoreIsTheRide from Time Attack")
        let combo = game.indices.filter { game[$0].hasPrefix("stat(icon: \"flame.fill\"") }
        #expect(combo.count == 1, "GameView: expected one combo pill, found \(combo.count)")
        for index in combo {
            let previous = game[..<index].last { !$0.isEmpty } ?? ""
            #expect(previous == "if RideHUDLayout.showsCombo(typeSize, scoreIsTheRide: scoreIsTheRide) {",
                    "GameView:\(index + 1): the combo pill is not behind RideHUDLayout.showsCombo")
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
                    ? "if RideHUDLayout.showsScore(typeSize, scoreIsTheRide: scoreIsTheRide) {"
                    : "if RideHUDLayout.showsScore(typeSize) {"
                #expect(previous == expected,
                        "\(file):\(index + 1): the score pill is not behind RideHUDLayout.showsScore")
            }
        }
    }

    /// The v1.31 fix, now on the ride's row too: no HUD value may wrap.
    @Test("every HUD value and the level capsule carry a one-line limit")
    func hudValuesNeverWrap() throws {
        let lines = Self.codeLines(try Self.source("GameView.swift"))
        guard let valueLine = lines.firstIndex(of: "Text(value).foregroundStyle(.white).monospacedDigit()"),
              let levelLine = lines.firstIndex(of: "Text(session.currentLevelLabel)") else {
            Issue.record("the HUD's value Text or level capsule moved; update this test")
            return
        }
        let valueChain = lines[(valueLine + 1)...].prefix { $0.hasPrefix(".") }
        #expect(valueChain.contains(".lineLimit(1)"))
        #expect(valueChain.contains(".fixedSize(horizontal: true, vertical: false)"))
        let levelChain = lines[(levelLine + 1)...].prefix { $0.hasPrefix(".") }
        #expect(levelChain.contains(".lineLimit(1)"))
        #expect(levelChain.contains(".minimumScaleFactor(0.7)"))
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
