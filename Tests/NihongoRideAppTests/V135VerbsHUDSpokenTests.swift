import Testing
import Foundation
import SwiftUI
import GameCore
#if canImport(AppKit)
import AppKit
#endif
@testable import NihongoRideApp

/// v1.35 step 3 (`PLAN-V1.34.md` §F) — the Verbs (conjugation) HUD's hidden score, for VoiceOver.
///
/// 1.33 hid the drill row's score pill at the accessibility sizes, by the ride's rule; 1.34 §B3 made
/// the RIDE row's progress pill speak what its row hides and left this row out. The same limits as
/// `V134B3HUDSpokenTests` apply and are stated first: `NSHostingView` exposes no accessibility
/// children to a probe without an assistive client, so nothing here reads the live accessibility
/// tree. What is decidable: the words come from a pure function whose table is written out below
/// for every `DynamicTypeSize`, en and zh; it is nil below the accessibility sizes, so the default
/// size cannot change; the progress pill's `spoken:` reads it; the score pill and the composer
/// format the number through one function; and an accessibility value draws nothing.
@Suite("v1.35: the Verbs HUD speaks the score it hides")
struct V135VerbsHUDSpokenTests {

    static let belowAccessibility = DynamicTypeSize.allCases.filter { !$0.isAccessibilitySize }
    static let accessibility = DynamicTypeSize.allCases.filter(\.isAccessibilitySize)

    static var drillFile: CallSiteScanner.File {
        get throws {
            try #require(try CallSiteScanner.shippedSources.get()
                .first { $0.path == "Sources/NihongoRideApp/ConjugationGameView.swift" })
        }
    }

    static var rideFile: CallSiteScanner.File {
        get throws {
            try #require(try CallSiteScanner.shippedSources.get()
                .first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        }
    }

    /// The `stat(...)` calls directly in `ConjugationHUD`, as (icon, comment-blanked arguments with
    /// strings, collapsed, the call itself).
    static func drillPills(_ file: CallSiteScanner.File) throws -> [(icon: String, arguments: String, call: CallSiteScanner.Call)] {
        let hud = try #require(file.typeBodies(named: "ConjugationHUD").first, "ConjugationGameView has no ConjugationHUD")
        return file.calls(named: "stat").filter { hud.contains($0.nameOffset) && $0.receiver.isEmpty }.compactMap { call in
            guard let range = call.arguments else { return nil }
            let arguments = V133GRideAndDrillLayoutTests.collapsed(String(decoding: file.codeWithStrings[range], as: UTF8.self))
            guard let quoted = arguments.range(of: #"icon: "[^"]*""#, options: .regularExpression) else { return nil }
            let icon = String(arguments[quoted].drop { $0 != "\"" }.dropFirst().dropLast())
            return (icon, arguments, call)
        }
    }

    // MARK: 1. The table

    /// Every `DynamicTypeSize`, written out: nil at the seven below the accessibility sizes, the
    /// score at the five accessibility sizes, in both languages, with the ride composer's separators.
    /// Mutations, 2026-09-29, each red here: the composer asking the Time Attack rule,
    /// `RideHUDLayout.shows(.score, $0, scoreIsTheRide: true, fallback: false)`, so the score is never
    /// hidden (24 issues in three tests); the zh label "分数 " (12); `RideHUDSpoken.suffix` returning
    /// "" for no parts (128, here and in `V134B3HUDSpokenTests`' nil test).
    @Test("at every size, the drill row speaks exactly the score it hides, en and zh, and nil below the accessibility sizes")
    func everySize() {
        let sizes = DynamicTypeSize.allCases
        #expect(sizes.count == 12 && sizes[3] == .large && sizes[7] == .accessibility1,
                "DynamicTypeSize changed shape; re-read what this table assumes")
        let en: [String?] = [nil, nil, nil, nil, nil, nil, nil,
                             ", score 891", ", score 891", ", score 891", ", score 891", ", score 891"]
        let zh: [String?] = [nil, nil, nil, nil, nil, nil, nil,
                             "、得分 891", "、得分 891", "、得分 891", "、得分 891", "、得分 891"]
        for (index, size) in sizes.enumerated() {
            #expect(ConjugationHUDSpoken.hiddenValues(typeSize: size, score: 891, zh: false) == en[index], "\(size), en")
            #expect(ConjugationHUDSpoken.hiddenValues(typeSize: size, score: 891, zh: true) == zh[index], "\(size), zh")
        }
        // The default size by name — the size the headless renders are read at.
        #expect(ConjugationHUDSpoken.hiddenValues(typeSize: RideHUDSpoken.defaultSize, score: 891, zh: false) == nil)
        // A score of nothing yet, and a long one: the number as the pill draws it.
        #expect(ConjugationHUDSpoken.hiddenValues(typeSize: .accessibility5, score: 0, zh: false) == ", score 0")
        #expect(ConjugationHUDSpoken.hiddenValues(typeSize: .accessibility1, score: 23456, zh: true) == "、得分 23456")
    }

    /// The progress pill's whole spoken value, built the way its call site builds it: the drill's
    /// done-of-total count, then the suffix. Below the accessibility sizes it is 1.34's literal —
    /// "6 of 12" / "6 / 12" — which the call site wrote out before v1.35.
    @Test("the progress pill says its count, then the score it hides; below the accessibility sizes, 1.34's words")
    func progressWords() {
        func spoken(_ size: DynamicTypeSize, zh: Bool, completed: Int = 6, count: Int = 12) -> String {
            RideHUDSpoken.progressWords(queueLengthIsTheTarget: true, completed: completed, count: count, zh: zh,
                                        hidden: ConjugationHUDSpoken.hiddenValues(typeSize: size, score: 891, zh: zh))
        }
        for size in Self.accessibility {
            #expect(spoken(size, zh: false) == "6 of 12, score 891", "\(size)")
            #expect(spoken(size, zh: true) == "6 / 12、得分 891", "\(size)")
        }
        for size in Self.belowAccessibility {
            #expect(spoken(size, zh: false) == "6 of 12", "\(size)")
            #expect(spoken(size, zh: true) == "6 / 12", "\(size)")
        }
        #expect(spoken(.accessibility3, zh: false, completed: 0, count: 20) == "0 of 20, score 891")
    }

    /// The shared formatter at its edges: the whole score, as both HUDs' pills have always drawn it.
    @Test("scoreWords is the whole score")
    func scoreWords() {
        #expect(RideHUDSpoken.scoreWords(0) == "0")
        #expect(RideHUDSpoken.scoreWords(891) == "891")
        #expect(RideHUDSpoken.scoreWords(23456) == "23456")
    }

    // MARK: 2. What the row hides

    /// Every `{ }` block inside `range`, braces included, in the order they open.
    static func blocks(in file: CallSiteScanner.File, within range: Range<Int>) -> [Range<Int>] {
        var stack: [Int] = []
        var found: [Range<Int>] = []
        for index in range {
            if file.code[index] == UInt8(ascii: "{") { stack.append(index) }
            else if file.code[index] == UInt8(ascii: "}"), let open = stack.popLast() { found.append(open..<(index + 1)) }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// The composer speaks the score and nothing else because that is the only pill this row hides
    /// relative to the default size (`ConjugationHUDSpoken`'s comment). That rests on the row's
    /// gates, pinned here on comment-blanked code, in three parts:
    /// * each pill's WHOLE chain of enclosing blocks, innermost out to the type: the score pill
    ///   behind `RideHUDLayout.showsScore` (also `V133GRideAndDrillLayoutTests.bothHUDsConsultTheRule`),
    ///   the accuracy pill behind exactly `if !narrow`, the combo and progress pills directly in the
    ///   row's `HStack`, and that `HStack` directly in `body`;
    /// * every block in `ConjugationHUD`, by the line that opens it, in order — so a gate added
    ///   beside the chain rather than around it (`if X { EmptyView() } else` on the line above an
    ///   `if !narrow {`) is a block this list does not have;
    /// * `narrow` declared once, exactly `private var narrow: Bool { isPhoneIdiom }`, and no other
    ///   plain `let` / `var` name bound in the type (a tuple pattern such as `let (narrow, _) = …`
    ///   is not read — measured green in review round 2).
    ///
    /// What it does not hold: the global `isPhoneIdiom` (TouchSupport.swift) is read by name, not
    /// pinned; a modifier that hides a drawn pill (`.opacity(0)`, `.hidden()`), or an expression
    /// that is not a block (a ternary choosing `EmptyView()`, `AnyView`), is not read here. Before v1.35's review round 1 this test read each pill's innermost block only,
    /// and a nested gate or a redefined `narrow` stayed green (measured below).
    ///
    /// Mutations, 2026-09-29, each red here: the accuracy gate as `if !(narrow || typeSize.isAccessibilitySize) {`;
    /// the combo pill behind `if !accessibilitySize {`; (review round 1, each GREEN on the innermost-block
    /// test) `if !typeSize.isAccessibilitySize {` wrapped around the whole `if !narrow { … }`;
    /// `narrow` redefined as `{ isPhoneIdiom || typeSize.isAccessibilitySize }`; `narrow` shadowed in
    /// `body` by `let narrow = self.narrow || accessibilitySize`; and, red on the block list alone,
    /// `if typeSize.isAccessibilitySize { EmptyView() } else` on the line above `if !narrow {`.
    @Test("the drill row hides only its score at the accessibility sizes, on either idiom")
    func onlyTheScoreIsHidden() throws {
        let file = try Self.drillFile
        let hud = try #require(file.typeBodies(named: "ConjugationHUD").first)
        let pills = try Self.drillPills(file)
        #expect(pills.map(\.icon) == ["star.fill", "flame.fill", "checkmark.circle.fill", "scope"],
                "ConjugationHUD's pills are \(pills.map(\.icon)); decide whether the new one is hidden, and update the composer and this test")
        let blocks = Self.blocks(in: file, within: hud)
        func head(_ block: Range<Int>) -> String { V133GRideAndDrillLayoutTests.blockHead(block, in: file) }

        // 1. Each pill's chain, innermost first, out to the type's own braces.
        let row = ["HStack(spacing: narrow ? 8 : 14)", "var body: some View", "struct ConjugationHUD: View"]
        let expected = ["star.fill": ["if RideHUDLayout.showsScore(typeSize)"] + row,
                        "flame.fill": row, "checkmark.circle.fill": row, "scope": ["if !narrow"] + row]
        for pill in pills {
            let chain = blocks.filter { $0.contains(pill.call.nameOffset) }.sorted { $0.count < $1.count }.map(head)
            #expect(chain == expected[pill.icon],
                    "\(file.location(pill.call.nameOffset)): the \(pill.icon) pill is behind \(chain)")
        }

        // 2. Every block in the type, in order.
        #expect(blocks.map(head) == [
            "struct ConjugationHUD: View",
            "private var narrow: Bool", "private var zh: Bool",
            "var body: some View", "HStack(spacing: narrow ? 8 : 14)",
            "if RideHUDLayout.showsScore(typeSize)", "if !narrow", "if let onPause", "Button(action: onPause)",
            "func stat(icon: String, value: String, tint: Color, label: String, spoken: String? = nil) -> some View",
            "HStack(spacing: 6)",
        ], "ConjugationHUD's blocks are \(blocks.map(head)); a new one may gate a pill — read it against the composer")

        // 3. What `narrow` is, and that nothing else is bound to it.
        let code = String(decoding: file.code[hud], as: UTF8.self)
        let bound = code.matches(of: /\b(?:let|var)\s+(\w+)/).map { String($0.output.1) }
        #expect(bound == ["typeSize", "session", "language", "onPause", "narrow", "zh", "body", "accessibilitySize", "onPause"],
                "ConjugationHUD binds \(bound)")
        let declaration = try #require(code.firstMatch(of: /private var narrow: Bool \{[^}]*\}/))
        #expect(V133GRideAndDrillLayoutTests.collapsed(String(declaration.output)) == "private var narrow: Bool { isPhoneIdiom }",
                "narrow is \(declaration.output)")
    }

    // MARK: 3. The call sites

    /// The progress pill's `spoken:` is exactly the joiner handed the drill's own count and the
    /// composer handed the view's `typeSize` and the session's score; the drawn `value:` reads
    /// neither; the composer is read once in shipped code, there; and `stat` hands `spoken` to
    /// VoiceOver. Mutations, 2026-09-29, each red here: `spoken:` back to 1.34's inline "of" string
    /// (the suffix dropped); `typeSize: .large` passed to the composer; `hidden: nil`;
    /// `.accessibilityValue(value)` in `ConjugationHUD.stat`.
    @Test("the progress pill's spoken value reads the composer, and nothing drawn does")
    func progressPillSpeaksTheSuffix() throws {
        let file = try Self.drillFile
        let hud = try #require(file.typeBodies(named: "ConjugationHUD").first)
        let progress = try Self.drillPills(file).filter { $0.icon == "checkmark.circle.fill" }
        #expect(progress.count == 1, "ConjugationHUD has \(progress.count) progress pill(s)")
        let arguments = try #require(progress.first?.arguments)
        let spokenLabel = try #require(arguments.range(of: "spoken: "), "the progress pill has no spoken: argument")
        let valueLabel = try #require(arguments.range(of: "value: "))
        #expect(String(arguments[spokenLabel.upperBound...])
                == "RideHUDSpoken.progressWords( queueLengthIsTheTarget: true, "
                + "completed: session.promptsCompleted, count: session.promptCount, zh: zh, "
                + "hidden: ConjugationHUDSpoken.hiddenValues(typeSize: typeSize, score: session.score, zh: zh))",
                "the progress pill's spoken value is \(arguments[spokenLabel.upperBound...])")
        let drawn = String(arguments[valueLabel.upperBound..<spokenLabel.lowerBound])
        #expect(!drawn.contains("Spoken"), "the progress pill's drawn value reads a composer: \(drawn)")

        var sites: [(path: String, offset: Int)] = []
        for other in try CallSiteScanner.shippedSources.get() {
            for hit in other.calls(named: "hiddenValues")
            where CallSiteScanner.receiverComponents(hit.receiver) == ["ConjugationHUDSpoken"] {
                sites.append((other.path, hit.nameOffset))
            }
        }
        let range = try #require(progress.first?.call.arguments)
        #expect(sites.count == 1 && sites.first?.path == file.path && sites.first.map { range.contains($0.offset) } == true,
                "ConjugationHUDSpoken.hiddenValues is read at \(sites.map { "\($0.path):\($0.offset)" }); expected once, in the progress pill's spoken: argument")

        let stats = file.functions(named: "stat").filter { hud.contains($0.keywordOffset) }
        let statBody = try #require(stats.count == 1 ? stats.first?.body : nil, "ConjugationHUD declares \(stats.count) stat")
        let statCode = V133GRideAndDrillLayoutTests.collapsed(String(decoding: file.codeWithStrings[statBody], as: UTF8.self))
        #expect(statCode.components(separatedBy: ".accessibilityValue(").count - 1 == 1,
                "ConjugationHUD.stat sets .accessibilityValue more than once, or not at all")
        #expect(statCode.hasSuffix(".accessibilityElement() .accessibilityLabel(label) .accessibilityValue(spoken ?? value) }"),
                "ConjugationHUD.stat no longer ends in .accessibilityValue(spoken ?? value): \(statCode.suffix(120))")
    }

    /// The number is formatted once. Both HUDs' score pills draw `RideHUDSpoken.scoreWords`, and both
    /// composers append it — so the drill's spoken score cannot drift from its drawn one, nor from the
    /// ride's. The drill's composer, comment-blanked, has no interpolation, `Int(` or `.joined` of its
    /// own (`String(score)` is not banned — review round 2) and uses the ride's
    /// separator helper. Mutations, 2026-09-29, each red here: the drill's score pill back to
    /// `value: "\(session.score)"`; the ride's score pill likewise; the drill composer appending
    /// `"score \(score)"`; the ride composer's `"score \(score)"` restored; the drill composer
    /// building its own `", "` join. Review round 1, 2026-09-29: the drill composer appending
    /// `"score \(score)"` is also red on the interpolation check itself, and a composer that keeps its
    /// scoreWords line and adds `parts = parts.map { "\($0)" }` — green before, when that check read
    /// the code view — is red on it alone.
    @Test("the score pills and both composers format the score through scoreWords")
    func oneScoreFormatter() throws {
        let drill = try Self.drillFile
        let score = try Self.drillPills(drill).filter { $0.icon == "star.fill" }
        #expect(score.count == 1, "ConjugationHUD has \(score.count) score pill(s)")
        #expect(score.first?.arguments.contains("value: RideHUDSpoken.scoreWords(session.score), ") == true,
                "the drill's score pill: \(score.first?.arguments ?? "none")")

        let composerType = try #require(drill.typeBodies(named: "ConjugationHUDSpoken").first,
                                        "ConjugationGameView has no ConjugationHUDSpoken")
        let composers = drill.functions(named: "hiddenValues").filter { composerType.contains($0.keywordOffset) }
        let body = try #require(composers.count == 1 ? composers.first?.body : nil,
                                "ConjugationHUDSpoken declares \(composers.count) hiddenValues")
        let withStrings = V133GRideAndDrillLayoutTests.collapsed(String(decoding: drill.codeWithStrings[body], as: UTF8.self))
        #expect(withStrings.contains(#"parts.append((zh ? "得分 " : "score ") + RideHUDSpoken.scoreWords(score))"#),
                "the drill composer does not append the score through scoreWords: \(withStrings)")
        #expect(withStrings.contains("return RideHUDSpoken.suffix(parts, zh: zh)"),
                "the drill composer does not join through RideHUDSpoken.suffix: \(withStrings)")
        #expect(withStrings.contains("hid(RideHUDLayout.showsScore)")
                && withStrings.contains("!shows(typeSize) && shows(RideHUDSpoken.defaultSize)"),
                "the drill composer no longer compares the score rule against the default size: \(withStrings)")
        // Interpolation is read on the view WITH strings: the code view blanks `\(` together with the
        // string around it, so the same check there could never fire (v1.35 review round 1 — the
        // mutant below that keeps the scoreWords line was green). `\#(` counts too. Control: the
        // ride composer, read the same way, has its level interpolation (`"level \(level)"`).
        let interpolation = /\\#*\(/
        #expect(withStrings.firstMatch(of: interpolation) == nil,
                "the drill composer interpolates something itself: \(withStrings)")
        let code = V133GRideAndDrillLayoutTests.collapsed(drill.text(body))
        #expect(!code.contains("Int(") && !code.contains(".joined"),
                "the drill composer formats or joins something itself: \(code)")

        let ride = try Self.rideFile
        let hud = try #require(ride.typeBodies(named: "HUDBar").first)
        let rideScore = ride.calls(named: "stat").filter { hud.contains($0.nameOffset) && $0.receiver.isEmpty }
            .compactMap { $0.arguments }
            .map { V133GRideAndDrillLayoutTests.collapsed(String(decoding: ride.codeWithStrings[$0], as: UTF8.self)) }
            .filter { $0.hasPrefix("icon: \"star.fill\"") }
        // v1.35: two — today's row's and the compressed rows'.
        #expect(rideScore.count == 2 && rideScore.allSatisfy { $0.contains("value: RideHUDSpoken.scoreWords(session.score), ") },
                "the ride's score pills: \(rideScore)")
        let rideComposer = try #require(ride.typeBodies(named: "RideHUDSpoken").first)
        let rideBody = try #require(ride.functions(named: "hiddenValues").first { rideComposer.contains($0.keywordOffset) }?.body)
        let rideText = V133GRideAndDrillLayoutTests.collapsed(String(decoding: ride.codeWithStrings[rideBody], as: UTF8.self))
        #expect(rideText.contains(#"parts.append((zh ? "得分 " : "score ") + scoreWords(score))"#),
                "the ride composer does not append the score through scoreWords")
        #expect(!rideText.contains(#"\(score)"#), "the ride composer formats the score itself")
        #expect(rideText.firstMatch(of: interpolation) != nil,
                "control: the interpolation check cannot see the ride composer's \"level \\(level)\": \(rideText)")
    }

    #if canImport(AppKit)
    /// "The default size cannot change" rests on the nil above and on this: an accessibility value is
    /// not drawn. What is rendered is the SHIPPED pill — `ConjugationHUD.stat`, internal for this
    /// test — as the progress pill, spoken 1.34's "6 of 12" and spoken the longest suffixed value:
    /// byte for byte alike. Control: against a render the suffixed one matched, one drawn digit
    /// changed ("7/12") is seen.
    ///
    /// What that covers, and what it does not. A change to `stat` that draws its spoken value goes
    /// red here; one that draws something other than `value` goes red on the control. The pill is
    /// rendered alone, at the row's 17pt font set here (the row's `.scaledSystemFont` is outside
    /// `stat`), with `narrow` false as on this Mac, and `ImageRenderer` does not drive Dynamic Type —
    /// so this is not a render of the row at an accessibility size. It reads no accessibility tree:
    /// that `stat` hands `spoken` to VoiceOver is the source pin in
    /// `progressPillSpeaksTheSuffix`. Before v1.35's review round 1 this test drew a copy of the pill,
    /// so no change to `stat` could fail it; the first mutation below was green then.
    ///
    /// **The instrument is not deterministic, so a pair is rendered up to three times.** Measured on
    /// 2026-09-29, all on unchanged rendering code: in the whole `swift test` runs the
    /// implementation recorded (11, 8 with their summary line kept), this test — then comparing a
    /// single pair, before the retry was added — failed in one, a 63.9s run, and
    /// `V134B3HUDSpokenTests`' test of the same name (which renders once) failed in another, a 107.3s
    /// run; the other 6 passed. In review, B3's test failed once in 17 filtered runs of three suites
    /// (`V135…|V134B3…|V133G…`, a 1.4s run), and both passed in 6 more whole runs and in one whole
    /// run at load average ~600 that took 390s. After review, 15 more filtered runs of the same three
    /// suites (this test rendering through `stat`, up to three times): B3's failed in one, a 0.64s
    /// run; this one in none. So the failure is not confined to whole-suite or to slow runs; it is
    /// rare, and nothing measured predicts it. A real drawing difference is the
    /// same on every render, so it fails all three attempts, and the control still has to see its
    /// digit. Mutations, 2026-09-29, each red here: `stat` also drawing its spoken value,
    /// `.overlay { Text(spoken ?? value).opacity(0.01) }` before `.accessibilityElement()`;
    /// `stat` drawing `Text(label)` for `Text(value)` (on the control).
    @MainActor
    @Test("an accessibility value draws nothing")
    func accessibilityValueDrawsNothing() {
        let hud = ConjugationHUD(session: ConjugationSession(prompts: []), language: "en")
        func pixels(_ spoken: String, drawn: String = "6/12") -> Data? {
            let pill = hud.stat(icon: "checkmark.circle.fill", value: drawn, tint: Theme.done, label: "Done", spoken: spoken)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            let renderer = ImageRenderer(content: ZStack { Color.white; pill }.frame(width: 200, height: 60))
            renderer.scale = 2
            return renderer.cgImage?.dataProvider?.data as Data?
        }
        let spoken = RideHUDSpoken.progressWords(
            queueLengthIsTheTarget: true, completed: 6, count: 12, zh: false,
            hidden: ConjugationHUDSpoken.hiddenValues(typeSize: .accessibility5, score: 23456, zh: false))
        #expect(spoken == "6 of 12, score 23456")
        var matched: Data?
        for _ in 0..<3 where matched == nil {
            let plain = pixels("6 of 12")
            if plain != nil, plain == pixels(spoken) { matched = plain }
        }
        #expect(matched != nil, "the suffix moved a pixel in three renders of three")
        // Against a render another render matched, so the instrument was steady for that pair.
        #expect(matched != nil && matched != pixels("6 of 12", drawn: "7/12"),
                "control: the instrument cannot see a change")
    }
    #endif
}
