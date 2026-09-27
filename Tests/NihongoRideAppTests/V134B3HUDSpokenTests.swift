import Testing
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import NihongoRideApp

/// v1.34 §B3 — VoiceOver keeps the values 1.33 hid.
///
/// **What these can and cannot prove, stated first.** `NSHostingView` exposes no accessibility
/// children to a probe without an assistive client (v1.33 §G measured that), so nothing here reads
/// the live accessibility tree: the simulator's Accessibility Inspector at AX5 is a simulator
/// observation for the orchestrator, and VoiceOver on a physical iPhone is the owner's errand after
/// the walk (§H). What is decidable here: the string a VoiceOver rider hears is composed by a pure
/// function whose table this file writes out by hand, en and zh, for every row 1.33 can draw; it is
/// nil — not empty — at every size below the accessibility sizes, so the default size cannot change;
/// the progress pill's call site reads it with the row's own `fallback`; and nothing drawn does.
@Suite("v1.34 §B3: VoiceOver keeps the values 1.33 hid")
struct V134B3HUDSpokenTests {

    static let belowAccessibility = DynamicTypeSize.allCases.filter { !$0.isAccessibilitySize }
    static let accessibility = DynamicTypeSize.allCases.filter(\.isAccessibilitySize)

    /// One ride's HUD state — a good ride on an N3 word: 891 points, a streak of six, 150.7m
    /// ridden, 97.3% accuracy, 42.6 words per minute. The fractions are on purpose: the pills show
    /// whole numbers, and so must the words.
    static func spoken(_ typeSize: DynamicTypeSize, scoreIsTheRide: Bool, fallback: Bool, narrow: Bool,
                       zh: Bool, level: String = "N3", combo: Int = 6, wpm: Double = 42.6) -> String? {
        RideHUDSpoken.hiddenValues(typeSize: typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback,
                                   narrow: narrow, level: level, score: 891, combo: combo, distanceMeters: 150.7,
                                   accuracy: 0.973, wpm: wpm, zh: zh)
    }

    struct Row {
        let name: String
        let scoreIsTheRide: Bool
        let fallback: Bool
        let narrow: Bool
        let en: String
        let zh: String
    }

    /// The eight rows 1.33 can draw at the accessibility sizes and what each hides, written out from
    /// `RideHUDLayout`'s comment rather than computed: a queue ride hides the score and its second
    /// row the combo too; Time Attack hides the combo and its second row the level capsule, spoken
    /// in the capsule's own words ("Level N3" / "等级 N3") and first, as the capsule is drawn first;
    /// an iPad hides distance, accuracy and speed as well, in HUD order after the combo. Each suffix
    /// begins with the list separator, because the call site appends it as it is.
    static let rows: [Row] = [
        Row(name: "phone, journey, first row: the score",
            scoreIsTheRide: false, fallback: false, narrow: true,
            en: ", score 891", zh: "、得分 891"),
        Row(name: "phone, journey, second row: the score and the combo",
            scoreIsTheRide: false, fallback: true, narrow: true,
            en: ", score 891, combo 6", zh: "、得分 891、连击 6"),
        Row(name: "phone, Time Attack, first row: the combo",
            scoreIsTheRide: true, fallback: false, narrow: true,
            en: ", combo 6", zh: "、连击 6"),
        Row(name: "phone, Time Attack, second row: the level, then the combo",
            scoreIsTheRide: true, fallback: true, narrow: true,
            en: ", level N3, combo 6", zh: "、等级 N3、连击 6"),
        Row(name: "iPad, journey, first row: the score, then distance, accuracy and speed",
            scoreIsTheRide: false, fallback: false, narrow: false,
            en: ", score 891, distance 150 meters, accuracy 97%, speed 42 words per minute",
            zh: "、得分 891、距离 150 米、正确率 97%、速度 每分钟 42 词"),
        Row(name: "iPad, journey, second row: the score and the combo, then the three",
            scoreIsTheRide: false, fallback: true, narrow: false,
            en: ", score 891, combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute",
            zh: "、得分 891、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词"),
        Row(name: "iPad, Time Attack, first row: the combo, then the three",
            scoreIsTheRide: true, fallback: false, narrow: false,
            en: ", combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute",
            zh: "、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词"),
        Row(name: "iPad, Time Attack, second row: the level, the combo, then the three",
            scoreIsTheRide: true, fallback: true, narrow: false,
            en: ", level N3, combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute",
            zh: "、等级 N3、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词"),
    ]

    // MARK: 1. The table

    /// Mutations, 2026-09-27, each red here (40 of the 80 row checks, or all 40 zh ones for the
    /// separator): the composer ignoring `fallback` (the second rows' combo and level go unspoken);
    /// the score spoken in Time Attack; the three informational pills spoken on a phone;
    /// `showsInformational` returning `!narrow`; the zh separator "，".
    @Test("at every accessibility size, each row speaks exactly the values it hides, en and zh")
    func eachRowSpeaksWhatItHides() {
        for row in Self.rows {
            for size in Self.accessibility {
                let en = Self.spoken(size, scoreIsTheRide: row.scoreIsTheRide, fallback: row.fallback,
                                     narrow: row.narrow, zh: false)
                #expect(en == row.en, "\(row.name), \(size), en: \(String(describing: en))")
                let zh = Self.spoken(size, scoreIsTheRide: row.scoreIsTheRide, fallback: row.fallback,
                                     narrow: row.narrow, zh: true)
                #expect(zh == row.zh, "\(row.name), \(size), zh: \(String(describing: zh))")
            }
        }
        // The rows differ from each other where 1.33's rows do: a second row is never its first.
        for first in stride(from: 0, to: Self.rows.count, by: 2) {
            #expect(Self.rows[first].en != Self.rows[first + 1].en && Self.rows[first].zh != Self.rows[first + 1].zh,
                    "control: \(Self.rows[first].name) and its second row should speak different suffixes")
        }
    }

    /// The default-size renders and every VoiceOver string below the accessibility sizes rest on
    /// this: the suffix is nil there, so the progress pill's value is byte for byte 1.33's. Nil and
    /// not "" — `Optional("")` is a suffix, and a call site appending it would still be fine, but a
    /// composer that returns it has stopped saying that nothing is hidden. Mutation, 2026-09-27:
    /// `guard !parts.isEmpty else { return "" }` goes red here in all 112 cases (7 sizes × 16 rows).
    @Test("below the accessibility sizes nothing is hidden, so nothing is spoken — nil, not an empty suffix")
    func nilBelowAccessibilitySizes() {
        #expect(Self.belowAccessibility.count == 7 && Self.belowAccessibility.contains(.large))
        for size in Self.belowAccessibility {
            for scoreIsTheRide in [false, true] {
                for fallback in [false, true] {
                    for narrow in [true, false] {
                        for zh in [false, true] {
                            let suffix = Self.spoken(size, scoreIsTheRide: scoreIsTheRide, fallback: fallback,
                                                     narrow: narrow, zh: zh)
                            #expect(suffix == nil,
                                    "\(size) scoreIsTheRide \(scoreIsTheRide) fallback \(fallback) narrow \(narrow) zh \(zh): \(String(describing: suffix))")
                        }
                    }
                }
            }
        }
        // The default size by name — the one the headless renders and the pins are read at — in
        // the row that hides the most at the accessibility sizes.
        #expect(Self.spoken(.large, scoreIsTheRide: false, fallback: true, narrow: false, zh: false) == nil)
        #expect(RideHUDSpoken.defaultSize == .large)
    }

    /// The forms the pills use for a value that is not a number yet: a streak under two is "none"
    /// / 无 (the pill draws "—"), and a speed under 1 wpm — `RunClock.wpm`'s "not meaningful yet" —
    /// is "not yet" / 尚未开始计算 (the pill draws "—"). Whole numbers, never fractions.
    @Test("a streak under two is none, a speed under one is not yet, and the numbers are whole")
    func valueForms() {
        for combo in [0, 1] {
            #expect(Self.spoken(.accessibility1, scoreIsTheRide: false, fallback: true, narrow: true, zh: false, combo: combo)
                    == ", score 891, combo none")
            #expect(Self.spoken(.accessibility1, scoreIsTheRide: false, fallback: true, narrow: true, zh: true, combo: combo)
                    == "、得分 891、连击 无")
        }
        #expect(Self.spoken(.accessibility1, scoreIsTheRide: false, fallback: true, narrow: true, zh: false, combo: 2)
                == ", score 891, combo 2")
        for wpm in [0, 0.99] {
            #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: false, narrow: false, zh: false, wpm: wpm)
                    == ", combo 6, distance 150 meters, accuracy 97%, speed not yet")
            #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: false, narrow: false, zh: true, wpm: wpm)
                    == "、连击 6、距离 150 米、正确率 97%、速度 尚未开始计算")
        }
        // 150.7 → 150, 0.973 → 97, 42.6 → 42: truncated, as `Int(_:)` truncates in the pills.
        #expect(Self.spoken(.accessibility5, scoreIsTheRide: false, fallback: false, narrow: false, zh: false)
                == ", score 891, distance 150 meters, accuracy 97%, speed 42 words per minute")
        // No current word, no level label: the capsule draws an empty label, and nothing is said.
        #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: true, narrow: true, zh: false, level: "")
                == ", combo 6")
        #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: true, narrow: true, zh: true, level: "N1")
                == "、等级 N1、连击 6")
    }

    // MARK: 2. The rules it calls

    /// `RideHUDLayout.showsInformational` is the row's gate for distance, accuracy and speed as a
    /// function, and the row draws the three behind the same expression written out (pinned by
    /// `V133GRideAndDrillLayoutTests`). Both are held here: the function's truth table, written
    /// out per size, and its body read back as the gate's text.
    @Test("distance, accuracy and speed are shown on an iPad below the accessibility sizes and nowhere else")
    func informationalRule() throws {
        let sizes = DynamicTypeSize.allCases
        #expect(sizes.count == 12 && sizes[3] == .large && sizes[7] == .accessibility1)
        #expect(sizes.map { RideHUDLayout.showsInformational(narrow: false, $0) }
                == [true, true, true, true, true, true, true, false, false, false, false, false],
                "an iPad shows the three at the seven sizes below the accessibility sizes")
        #expect(sizes.map { RideHUDLayout.showsInformational(narrow: true, $0) }
                == Array(repeating: false, count: 12), "a phone never shows the three")

        let lines = V133GRideAndDrillLayoutTests.codeLines(try V133GRideAndDrillLayoutTests.source("GameView.swift"))
        let declaration = try #require(lines.firstIndex(of: "static func showsInformational(narrow: Bool, _ typeSize: DynamicTypeSize) -> Bool {"),
                                       "showsInformational moved; update this test")
        #expect(lines[declaration + 1] == "!(narrow || typeSize.isAccessibilitySize)" && lines[declaration + 2] == "}",
                "the function's body is no longer the row's gate: \(lines[declaration + 1])")
        #expect(lines.filter { $0 == "if !(narrow || typeSize.isAccessibilitySize) {" }.count == 2,
                "the row's two gates on distance / accuracy and speed are no longer that expression")
    }

    /// The composer's words are the pills' own, so a rider hears the same value whichever row is
    /// drawn: the unit and placeholder fragments each `stat` pill passes as `spoken:` must appear in
    /// `RideHUDSpoken`'s body, and there be attached to their label.
    @Test("the spoken forms are the pills' own")
    func spokenFormsAreThePills() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        let hud = try #require(file.typeBodies(named: "HUDBar").first)
        let composer = try #require(file.typeBodies(named: "RideHUDSpoken").first)
        let pills = file.calls(named: "stat").filter { hud.contains($0.nameOffset) && $0.receiver.isEmpty }
            .compactMap { $0.arguments }.map { String(decoding: file.codeWithStrings[$0], as: UTF8.self) }
        let body = String(decoding: file.codeWithStrings[composer], as: UTF8.self)
        for fragment in ["\"无\"", "\"none\"", " 米\"", " meters\"", "每分钟 ", " words per minute\"",
                         "尚未开始计算\"", "not yet\""] {
            #expect(pills.contains { $0.contains(fragment) }, "no HUD pill speaks \(fragment) any more")
            #expect(body.contains(fragment), "RideHUDSpoken does not speak \(fragment)")
        }
        // The level capsule is not a `stat`: its words are its accessibility label.
        let hudText = String(decoding: file.codeWithStrings[hud], as: UTF8.self)
        #expect(hudText.contains(#".accessibilityLabel(zh ? "等级 \(session.currentLevelLabel)" : "Level \(session.currentLevelLabel)")"#),
                "the level capsule's label changed")
        #expect(body.contains(#""等级 \(level)" : "level \(level)""#), "RideHUDSpoken does not speak the level as the capsule does")
    }

    // MARK: 3. The call site

    /// The progress pill — the one element drawn in every row — is where the suffix is heard: its
    /// `spoken:` argument appends `RideHUDSpoken.hiddenValues(` to its own value, handing on the
    /// row's own `fallback`, the view's `typeSize` and its `narrow`. And nothing drawn reads the
    /// composer: it is called once in shipped code, inside that argument, not in `value:`.
    /// Mutations, 2026-09-27, each red here: the suffix dropped from `spoken:`; `fallback: false`
    /// passed instead of the row's; a second call from the score pill's `value:`.
    @Test("the progress pill's spoken value reads the composer with the row's own fallback, and nothing drawn does")
    func progressPillSpeaksTheSuffix() throws {
        let files = try CallSiteScanner.shippedSources.get()
        let file = try #require(files.first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        let hud = try #require(file.typeBodies(named: "HUDBar").first, "GameView has no HUDBar")
        let progress = file.calls(named: "stat").filter { hud.contains($0.nameOffset) && $0.receiver.isEmpty }
            .filter { call in
                call.arguments.map { String(decoding: file.codeWithStrings[$0], as: UTF8.self) }?
                    .contains("icon: \"checkmark.circle.fill\"") ?? false
            }
        #expect(progress.count == 1, "HUDBar has \(progress.count) progress pill(s)")
        let call = try #require(progress.first)
        let arguments = try #require(call.arguments)
        let text = file.text(arguments)
        let spokenLabel = try #require(text.range(of: #"\bspoken\s*:"#, options: .regularExpression),
                                       "the progress pill has no spoken: argument")
        let valueLabel = try #require(text.range(of: #"\bvalue\s*:"#, options: .regularExpression))
        let spoken = V133GRideAndDrillLayoutTests.collapsed(String(text[spokenLabel.upperBound...]))
        #expect(spoken.contains("RideHUDSpoken.hiddenValues("), "the progress pill's spoken value is \(spoken)")
        #expect(spoken.contains("session.wordsCompleted"), "the suffix replaced the progress value: \(spoken)")
        for pair in ["typeSize: typeSize", "scoreIsTheRide: scoreIsTheRide", "fallback: fallback", "narrow: narrow",
                     "level: session.currentLevelLabel", "score: session.score", "combo: session.combo", "distanceMeters: session.distanceMeters",
                     "accuracy: session.accuracy", "wpm: wpm", "zh: zh"] {
            #expect(spoken.contains(pair), "the composer is not handed \(pair): \(spoken)")
        }
        #expect(spoken.hasSuffix("?? \"\")") || spoken.hasSuffix("?? \"\"))"),
                "the suffix is appended as it is, nil as nothing: \(spoken)")
        #expect(!text[valueLabel.upperBound..<spokenLabel.lowerBound].contains("RideHUDSpoken"),
                "the progress pill's drawn value reads the composer")

        var sites: [(path: String, offset: Int)] = []
        for other in files {
            for hit in other.calls(named: "hiddenValues")
            where CallSiteScanner.receiverComponents(hit.receiver) == ["RideHUDSpoken"] {
                sites.append((other.path, hit.nameOffset))
            }
        }
        #expect(sites.count == 1 && sites.first?.path == file.path && sites.first.map { arguments.contains($0.offset) } == true,
                "RideHUDSpoken.hiddenValues is read at \(sites.map { "\($0.path):\($0.offset)" }); expected once, in the progress pill's spoken: argument")
    }

    #if canImport(AppKit)
    /// "Nothing drawn changes" is SwiftUI's behaviour — an accessibility value is not laid out or
    /// painted — so it is measured rather than assumed: the same pill with 1.33's value and with
    /// the longest suffix renders byte for byte alike. Together with the nil above, the default
    /// size cannot differ from 1.33 by a pixel or a word.
    @MainActor
    @Test("an accessibility value draws nothing")
    func accessibilityValueDrawsNothing() {
        func pixels(_ value: String, drawn: String = "6/12") -> Data? {
            let pill = HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.done)
                Text(drawn).foregroundStyle(.white).monospacedDigit()
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(.black.opacity(0.42), in: Capsule())
            .accessibilityElement()
            .accessibilityLabel("Words")
            .accessibilityValue(value)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            let renderer = ImageRenderer(content: ZStack { Color.white; pill }.frame(width: 200, height: 60))
            renderer.scale = 2
            return renderer.cgImage?.dataProvider?.data as Data?
        }
        let plain = pixels("6 of 12")
        let suffixed = pixels("6 of 12" + Self.rows[5].en)
        #expect(plain != nil && plain == suffixed, "the suffix moved a pixel")
        // Control: the same pill with one drawn digit changed is seen as different.
        #expect(plain != pixels("6 of 12", drawn: "7/12"), "control: the instrument cannot see a change")
    }
    #endif
}
