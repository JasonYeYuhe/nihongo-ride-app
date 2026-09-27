import Testing
import Foundation
import SwiftUI
import GameCore
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
                       zh: Bool, level: String = "N3", combo: Int = 6, accuracy: Double = 0.973,
                       wpm: Double = 42.6) -> String? {
        RideHUDSpoken.hiddenValues(typeSize: typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback,
                                   narrow: narrow, level: level, score: 891, combo: combo, distanceMeters: 150.7,
                                   accuracy: accuracy, wpm: wpm, zh: zh)
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
        // 150.7 → 150 and 42.6 → 42: truncated, as `Int(_:)` truncates in the pills. 0.973 cannot
        // tell truncation from rounding — 97.3 is 97 either way — so the accuracy's own boundary is
        // 0.976 and 0.978 below. (Review round 2: the comment here claimed 0.973 checked it.)
        #expect(Self.spoken(.accessibility5, scoreIsTheRide: false, fallback: false, narrow: false, zh: false)
                == ", score 891, distance 150 meters, accuracy 97%, speed 42 words per minute")
        // The accuracy pill truncates (`accuracyWords`, which it draws), so 97.6% and 97.8% are
        // heard as the pill shows them, "97%" — rounding would say "98%". Review round 2, M1:
        // `Int((accuracy * 100).rounded())` in the composer was green; it is red here and in
        // `composerFormatsNothingItself`.
        for accuracy in [0.976, 0.978] {
            #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: false, narrow: false, zh: false,
                                accuracy: accuracy)
                    == ", combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute", "accuracy \(accuracy)")
            #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: false, narrow: false, zh: true,
                                accuracy: accuracy)
                    == "、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词", "accuracy \(accuracy)")
        }
        // The speed's boundary is exactly 1.0: a number, as the pill draws "1". Review round 2, M2:
        // `wpm > 1` in the composer was green, since 0, 0.99 and 42.6 answer alike either way.
        #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: false, narrow: false, zh: false, wpm: 1.0)
                == ", combo 6, distance 150 meters, accuracy 97%, speed 1 words per minute")
        #expect(Self.spoken(.accessibility1, scoreIsTheRide: true, fallback: false, narrow: false, zh: true, wpm: 1.0)
                == "、连击 6、距离 150 米、正确率 97%、速度 每分钟 1 词")
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

    /// The pills' words at their boundaries, written out: the one function per value that the pill
    /// calls for what it draws or speaks and the composer calls for what it appends
    /// (`composerFormatsNothingItself` pins both). Review round 2: the composer had its own copy of
    /// each, and rounding the accuracy (M1) or `wpm > 1` (M2) in that copy stayed green.
    /// Mutations, 2026-09-27, each red here: `Int((accuracy * 100).rounded())` in `accuracyWords`;
    /// `wpm > 1` in `paceIsKnown`.
    @Test("each pill's value, in words, at its boundaries")
    func pillWordsAtTheirBoundaries() {
        // Accuracy: truncated, never rounded. 0.976 and 0.978 are where the two differ.
        #expect(RideHUDSpoken.accuracyWords(0.976) == "97%")
        #expect(RideHUDSpoken.accuracyWords(0.978) == "97%")
        #expect(RideHUDSpoken.accuracyWords(0.973) == "97%")
        #expect(RideHUDSpoken.accuracyWords(0.999) == "99%")
        #expect(RideHUDSpoken.accuracyWords(1.0) == "100%")
        #expect(RideHUDSpoken.accuracyWords(0.0) == "0%")
        #expect(RideHUDSpoken.accuracyWords(0.5) == "50%")

        // Speed: a number from exactly 1.0 wpm; "—" / "not yet" below it.
        #expect(RideHUDSpoken.paceIsKnown(0.99) == false)
        #expect(RideHUDSpoken.paceIsKnown(1.0) == true)
        #expect(RideHUDSpoken.speedValue(0) == "—")
        #expect(RideHUDSpoken.speedValue(0.99) == "—")
        #expect(RideHUDSpoken.speedValue(1.0) == "1")
        #expect(RideHUDSpoken.speedValue(42.6) == "42")
        #expect(RideHUDSpoken.speedWords(0.99, zh: false) == "not yet")
        #expect(RideHUDSpoken.speedWords(0.99, zh: true) == "尚未开始计算")
        #expect(RideHUDSpoken.speedWords(1.0, zh: false) == "1 words per minute")
        #expect(RideHUDSpoken.speedWords(1.0, zh: true) == "每分钟 1 词")
        #expect(RideHUDSpoken.speedWords(42.6, zh: false) == "42 words per minute")
        #expect(RideHUDSpoken.speedWords(42.6, zh: true) == "每分钟 42 词")

        // Distance: whole metres, truncated as the drawn "150 m" is.
        #expect(RideHUDSpoken.distanceWords(150.7, zh: false) == "150 meters")
        #expect(RideHUDSpoken.distanceWords(150.7, zh: true) == "150 米")
        #expect(RideHUDSpoken.distanceWords(0.9, zh: false) == "0 meters")

        // Combo: a streak from two; "none" / 无 below, where the pill draws "—".
        #expect(RideHUDSpoken.comboWords(0, zh: false) == "none")
        #expect(RideHUDSpoken.comboWords(1, zh: true) == "无")
        #expect(RideHUDSpoken.comboWords(2, zh: false) == "2")
        #expect(RideHUDSpoken.comboWords(6, zh: true) == "6")
    }

    /// Each pill hands its value to the shared function, and the composer builds its words from the
    /// same functions and formats no number of its own — so the two cannot drift. Pinned on
    /// comment-blanked code (the scanner blanks `//` and `/* */`), per argument, exactly.
    /// Mutations, 2026-09-27, each red here: the composer's accuracy written back out as
    /// `"accuracy \(Int((accuracy * 100).rounded()))%"` (M1); its speed as
    /// `wpm > 1 ? ... : "not yet"` (M2); the accuracy pill's `value:` back to its own
    /// `"\(Int(session.accuracy * 100))%"`.
    @Test("the pills and the composer call the same functions, and the composer formats nothing itself")
    func composerFormatsNothingItself() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        let hud = try #require(file.typeBodies(named: "HUDBar").first)
        func pill(_ icon: String) -> String? {
            let calls = file.calls(named: "stat").filter { hud.contains($0.nameOffset) && $0.receiver.isEmpty }
                .compactMap { $0.arguments }
                .map { V133GRideAndDrillLayoutTests.collapsed(String(decoding: file.codeWithStrings[$0], as: UTF8.self)) }
                .filter { $0.hasPrefix("icon: \"\(icon)\"") }
            return calls.count == 1 ? calls[0] : nil
        }
        /// `argument` is one whole argument: followed by the next one or by the end of the call.
        func passes(_ arguments: String?, _ argument: String) -> Bool {
            guard let arguments else { return false }
            return arguments.hasSuffix(", " + argument) || arguments.contains(", " + argument + ", ")
        }
        let combo = try #require(pill("flame.fill"), "HUDBar has no single combo pill")
        let distance = try #require(pill("bicycle"), "HUDBar has no single distance pill")
        let accuracy = try #require(pill("scope"), "HUDBar has no single accuracy pill")
        let speed = try #require(pill("speedometer"), "HUDBar has no single speed pill")
        #expect(passes(combo, "spoken: RideHUDSpoken.comboWords(session.combo, zh: zh)"), "combo pill: \(combo)")
        #expect(passes(distance, "spoken: RideHUDSpoken.distanceWords(session.distanceMeters, zh: zh)"), "distance pill: \(distance)")
        #expect(passes(accuracy, "value: RideHUDSpoken.accuracyWords(session.accuracy)"), "accuracy pill: \(accuracy)")
        #expect(!accuracy.contains("spoken:"), "the accuracy pill speaks something other than what it draws: \(accuracy)")
        #expect(passes(speed, "value: RideHUDSpoken.speedValue(wpm)"), "speed pill: \(speed)")
        #expect(passes(speed, "spoken: RideHUDSpoken.speedWords(wpm, zh: zh)"), "speed pill: \(speed)")

        let composer = try #require(file.typeBodies(named: "RideHUDSpoken").first)
        let composers = file.functions(named: "hiddenValues").filter { composer.contains($0.keywordOffset) }
        #expect(composers.count == 1, "RideHUDSpoken declares \(composers.count) hiddenValues")
        let body = try #require(composers.first?.body)
        let text = V133GRideAndDrillLayoutTests.collapsed(String(decoding: file.codeWithStrings[body], as: UTF8.self))
        for part in ["parts.append((zh ? \"连击 \" : \"combo \") + comboWords(combo, zh: zh))",
                     "parts.append((zh ? \"距离 \" : \"distance \") + distanceWords(distanceMeters, zh: zh))",
                     "parts.append((zh ? \"正确率 \" : \"accuracy \") + accuracyWords(accuracy))",
                     "parts.append((zh ? \"速度 \" : \"speed \") + speedWords(wpm, zh: zh))"] {
            #expect(text.contains(part), "hiddenValues no longer appends \(part)")
        }
        // Nothing numeric of its own: no conversion, no percentage, no threshold on a literal.
        let code = V133GRideAndDrillLayoutTests.collapsed(file.text(body))
        #expect(!code.contains("Int("), "hiddenValues converts a number itself")
        #expect(!code.contains("* 100") && !code.contains(".rounded"), "hiddenValues computes a percentage itself")
        #expect(code.range(of: #"[<>]=?\s*[0-9]"#, options: .regularExpression) == nil,
                "hiddenValues compares against a number itself")

        // The level capsule is not a `stat`: its words are its accessibility label.
        let hudText = String(decoding: file.codeWithStrings[hud], as: UTF8.self)
        #expect(hudText.contains(#".accessibilityLabel(zh ? "等级 \(session.currentLevelLabel)" : "Level \(session.currentLevelLabel)")"#),
                "the level capsule's label changed")
        let composerText = String(decoding: file.codeWithStrings[composer], as: UTF8.self)
        #expect(composerText.contains(#""等级 \(level)" : "level \(level)""#), "RideHUDSpoken does not speak the level as the capsule does")
    }

    // MARK: 3. The call site

    /// The progress pill's spoken value, composed through the function the pill calls, for every
    /// mode: a ride whose queue is the target speaks "6 of 12" and then what the row hides; Time
    /// Attack speaks its bare count and then what the row hides. Review round 2, M3: written inline
    /// at the call site, removing the outer parentheses made Swift read `a ? b : c + suffix`, so
    /// every queue ride — journey, sentence, word list — lost the suffix, and every test stayed
    /// green. Mutation, 2026-09-27, red here: the same parentheses removed in `progressWords`
    /// (`let own = ...` folded into `return queueLengthIsTheTarget ? ... : "\(completed)" + (hidden ?? "")`).
    @Test("the progress pill's spoken value is its count followed by the suffix, in every mode")
    func progressWordsInEveryMode() {
        #expect(GameMode.allCases.count == 6)
        for mode in GameMode.allCases {
            // Written out from `queueLengthIsTheTarget`'s comment: Time Attack's queue is a pool;
            // every other mode's queue is the target.
            let queue = mode != .timeAttack
            #expect(mode.queueLengthIsTheTarget == queue, "\(mode)")
            let scoreIsTheRide = !queue
            let en = RideHUDSpoken.progressWords(
                queueLengthIsTheTarget: mode.queueLengthIsTheTarget, completed: 6, count: 12, zh: false,
                hidden: Self.spoken(.accessibility1, scoreIsTheRide: scoreIsTheRide, fallback: false, narrow: true, zh: false))
            let zh = RideHUDSpoken.progressWords(
                queueLengthIsTheTarget: mode.queueLengthIsTheTarget, completed: 6, count: 12, zh: true,
                hidden: Self.spoken(.accessibility1, scoreIsTheRide: scoreIsTheRide, fallback: false, narrow: true, zh: true))
            #expect(en == (queue ? "6 of 12, score 891" : "6, combo 6"), "\(mode), en: \(en)")
            #expect(zh == (queue ? "6 / 12、得分 891" : "6、连击 6"), "\(mode), zh: \(zh)")
            // Below the accessibility sizes: 1.33's value, unchanged.
            let plain = RideHUDSpoken.progressWords(
                queueLengthIsTheTarget: mode.queueLengthIsTheTarget, completed: 6, count: 12, zh: false,
                hidden: Self.spoken(.large, scoreIsTheRide: scoreIsTheRide, fallback: false, narrow: true, zh: false))
            #expect(plain == (queue ? "6 of 12" : "6"), "\(mode), default size: \(plain)")
        }
        #expect(RideHUDSpoken.progressWords(queueLengthIsTheTarget: true, completed: 0, count: 5, zh: true, hidden: nil)
                == "0 / 5")
    }

    /// The progress pill — the one element drawn in every row — is where the suffix is heard: its
    /// `spoken:` argument is exactly `RideHUDSpoken.progressWords(...)` handed the pill's own count
    /// and `RideHUDSpoken.hiddenValues(...)` with the row's own `fallback`, the view's `typeSize` and
    /// its `narrow`; and `progressWords` joins the two in exactly the shape that suffixes the whole
    /// count. And nothing drawn reads the composer: it is called once in shipped code, inside that
    /// argument, not in `value:`.
    /// Mutations, 2026-09-27, each red here: the suffix dropped from `spoken:`; `fallback: false`
    /// passed instead of the row's; a second call from the score pill's `value:`; (review round 2)
    /// the call site written back inline as 1.34's first draft with its outer parentheses removed;
    /// `progressWords`' parentheses removed.
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
        // Exactly, so no operator can be slipped around either call. (Review round 2, M3.)
        #expect(spoken == "RideHUDSpoken.progressWords( queueLengthIsTheTarget: session.mode.queueLengthIsTheTarget, "
                + "completed: session.wordsCompleted, count: session.wordCount, zh: zh, "
                + "hidden: RideHUDSpoken.hiddenValues(typeSize: typeSize, scoreIsTheRide: scoreIsTheRide, "
                + "fallback: fallback, narrow: narrow, level: session.currentLevelLabel, score: session.score, "
                + "combo: session.combo, distanceMeters: session.distanceMeters, accuracy: session.accuracy, "
                + "wpm: wpm, zh: zh))",
                "the progress pill's spoken value is \(spoken)")
        #expect(spoken.contains("RideHUDSpoken.hiddenValues("), "the progress pill's spoken value is \(spoken)")
        #expect(spoken.contains("session.wordsCompleted"), "the suffix replaced the progress value: \(spoken)")
        for pair in ["typeSize: typeSize", "scoreIsTheRide: scoreIsTheRide", "fallback: fallback", "narrow: narrow",
                     "level: session.currentLevelLabel", "score: session.score", "combo: session.combo", "distanceMeters: session.distanceMeters",
                     "accuracy: session.accuracy", "wpm: wpm", "zh: zh"] {
            #expect(spoken.contains(pair), "the composer is not handed \(pair): \(spoken)")
        }
        // `progressWords`' body, with strings: its own count in parentheses as a whole, then the
        // suffix, nil as nothing. Collapsed, so line breaks do not matter; a parenthesis does.
        let enumBody = try #require(file.typeBodies(named: "RideHUDSpoken").first)
        let joiners = file.functions(named: "progressWords").filter { enumBody.contains($0.keywordOffset) }
        let joiner = try #require(joiners.count == 1 ? joiners.first?.body : nil, "RideHUDSpoken.progressWords moved")
        #expect(V133GRideAndDrillLayoutTests.collapsed(String(decoding: file.codeWithStrings[joiner], as: UTF8.self))
                == #"{ let own = queueLengthIsTheTarget ? (zh ? "\(completed) / \(count)" : "\(completed) of \(count)") : "\(completed)" return own + (hidden ?? "") }"#,
                "progressWords' shape changed")
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
