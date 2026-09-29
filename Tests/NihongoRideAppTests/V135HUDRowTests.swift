import Testing
import Foundation
import SwiftUI
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif
import VocabKit
import GameCore
@testable import NihongoRideApp

/// v1.35 — the iPad and Mac ride row below the accessibility sizes: today's row where it fits, then
/// the same pills with the gaps closed, then one pill fewer per rung (`RideHUDRungs`, `HUDRowLayout`,
/// `HUDBar.body`); and at the accessibility sizes an iPad's third row.
///
/// **What these can and cannot prove, stated first.** Everything hosted here is an `NSHostingView` or
/// `NSHostingController` on macOS, never `ImageRenderer` (the v1.35 design round saw it draw a
/// `ViewThatFits` child the live view did not; that did not reproduce on this HUD, and it is not
/// used). A child of the body is hosted through `HUDChild`, which gives it the HUD's environment
/// (see there: built any other way it reads the default size). macOS does not scale `@ScaledMetric`,
/// so the larger sizes are laid out with `emulatedTextScale` set to the size's body-point ratio — an
/// instrument's reading, not a device's: every `scaledSystemFont` scales by the same factor, where
/// iOS scales a style at its own rate. There is no iPhone here; a phone's rows are held by the tables
/// and pins (they are `row(fallback:)`, unchanged), not rendered. The pixel comparison with f37fab7's
/// HUD draws f37fab7's body (`F37fab7HUD`) over this file's rows, which `todaysRowIsVerbatim` holds
/// to f37fab7's bytes. The simulator pass is the device's word on all of it.
@Suite("v1.35: the iPad and Mac ride row sheds pills in one order instead of wrapping")
struct V135HUDRowTests {

    typealias Pill = RideHUDRungs.Pill
    static let all: [Pill] = [.level, .score, .combo, .distance, .progress, .accuracy, .speed]

    // MARK: 1. The order

    /// The rungs, written out. Queue rides (journey, sentence, dictation, lists): distance, accuracy,
    /// speed, then v1.33's accessibility-size order — score, combo, level; the progress count is never
    /// shed. Time Attack: distance, accuracy, speed, combo, level, and at the last rung its count,
    /// keeping the score its leaderboard takes. Mutations, each red here: `shedOrder` with accuracy
    /// before distance; Time Attack's `.combo` and `.level` swapped; Time Attack's last rung shedding
    /// the score instead of the count; `shows` reading `prefix(rung + 1)`; `leading` counting the
    /// distance pill.
    @Test("each rung sheds one more pill, in one fixed order per mode")
    func sheddingOrder() {
        #expect(Pill.allCases == Self.all, "a new pill: decide where it goes in the order, and update this test")
        #expect(RideHUDRungs.last == 6)
        #expect(RideHUDRungs.shedOrder(scoreIsTheRide: false) == [.distance, .accuracy, .speed, .score, .combo, .level])
        #expect(RideHUDRungs.shedOrder(scoreIsTheRide: true) == [.distance, .accuracy, .speed, .combo, .level, .progress])
        let queue: [[Pill]] = [
            [.level, .score, .combo, .distance, .progress, .accuracy, .speed],
            [.level, .score, .combo, .progress, .accuracy, .speed],
            [.level, .score, .combo, .progress, .speed],
            [.level, .score, .combo, .progress],
            [.level, .combo, .progress],
            [.level, .progress],
            [.progress],
        ]
        let timeAttack: [[Pill]] = [
            [.level, .score, .combo, .distance, .progress, .accuracy, .speed],
            [.level, .score, .combo, .progress, .accuracy, .speed],
            [.level, .score, .combo, .progress, .speed],
            [.level, .score, .combo, .progress],
            [.level, .score, .progress],
            [.score, .progress],
            [.score],
        ]
        for (scoreIsTheRide, table, leading) in [(false, queue, [3, 3, 3, 3, 2, 1, 0]), (true, timeAttack, [3, 3, 3, 3, 2, 1, 1])] {
            for rung in 0...RideHUDRungs.last {
                let shown = Self.all.filter { RideHUDRungs.shows($0, rung: rung, scoreIsTheRide: scoreIsTheRide) }
                #expect(shown == table[rung], "Time Attack \(scoreIsTheRide), rung \(rung): \(shown)")
                #expect(RideHUDRungs.leading(rung: rung, scoreIsTheRide: scoreIsTheRide) == leading[rung],
                        "Time Attack \(scoreIsTheRide), rung \(rung): leading \(RideHUDRungs.leading(rung: rung, scoreIsTheRide: scoreIsTheRide))")
            }
        }
        // Past the last rung nothing more goes: a rung number beyond it is not a new row.
        #expect(Self.all.filter { RideHUDRungs.shows($0, rung: 7, scoreIsTheRide: false) } == [.progress])
    }

    /// Rungs 3, 4 and 5 are, pill for pill, what a phone draws below the accessibility sizes and the
    /// two rows `RideHUDLayout` gives the accessibility sizes — computed here from `RideHUDLayout`'s
    /// own rules, which `V133GRideAndDrillLayoutTests` writes out, so the two orders cannot drift apart.
    /// Mutation, red here: `RideHUDLayout.fallbackDrops` answering `.score` for Time Attack.
    @Test("rungs 3–5 are today's phone row and today's two accessibility-size rows")
    func middleRungsAreTodaysRows() {
        for scoreIsTheRide in [false, true] {
            func rung(_ rung: Int) -> [Pill] { Self.all.filter { RideHUDRungs.shows($0, rung: rung, scoreIsTheRide: scoreIsTheRide) } }
            #expect(rung(3) == Self.pills(.today(fallback: false), narrow: true, .large, scoreIsTheRide: scoreIsTheRide))
            #expect(rung(4) == Self.pills(.today(fallback: false), narrow: false, .accessibility1, scoreIsTheRide: scoreIsTheRide))
            #expect(rung(5) == Self.pills(.today(fallback: true), narrow: false, .accessibility1, scoreIsTheRide: scoreIsTheRide))
            #expect(rung(0) == Self.pills(.today(fallback: false), narrow: false, .large, scoreIsTheRide: scoreIsTheRide))
        }
    }

    /// The pills a child of `HUDBar.body` draws, in HUD order: `row(fallback:)` by `RideHUDLayout`'s
    /// rules (the three informational pills behind `showsInformational`), a compressed rung by
    /// `RideHUDRungs`. The pause button is not a pill; every child has it on a touch device.
    static func pills(_ row: RideHUDRungs.Row, narrow: Bool, _ size: DynamicTypeSize, scoreIsTheRide: Bool) -> [Pill] {
        switch row {
        case .todayOneLine:
            return pills(.today(fallback: false), narrow: narrow, size, scoreIsTheRide: scoreIsTheRide)
        case .today(let fallback):
            func shows(_ pill: RideHUDLayout.Pill) -> Bool {
                RideHUDLayout.shows(pill, size, scoreIsTheRide: scoreIsTheRide, fallback: fallback)
            }
            let informational = RideHUDLayout.showsInformational(narrow: narrow, size)
            return Self.all.filter {
                switch $0 {
                case .level: shows(.level)
                case .score: shows(.score)
                case .combo: shows(.combo)
                case .progress: true
                case .distance, .accuracy, .speed: informational
                }
            }
        case .compressed(let rung):
            return Self.all.filter { RideHUDRungs.shows($0, rung: rung, scoreIsTheRide: scoreIsTheRide) }
        }
    }

    // MARK: 2. What each device is offered

    /// `RideHUDRungs.offered` — `HUDBar.body` as a table (`bodyIsTheTable` holds the two together) —
    /// per device, at each of the 12 sizes, in each mode, with the pills of every child written out.
    /// **Parity:** a phone is offered exactly 1.34's rows (one row below the accessibility sizes, the
    /// same two rows at them, with the same pills), and an iPad at the accessibility sizes 1.34's two
    /// rows first. Mutations, each red here: `offered` giving a phone the ladder below the
    /// accessibility sizes; an iPad at them `.compressed(rung: 5)` before the last rung; the ladder
    /// without its rung 0; `.today(fallback: true)` first at the accessibility sizes.
    @Test("each device is offered today's rows first, and a phone nothing else")
    func offeredRows() {
        let sizes = DynamicTypeSize.allCases
        #expect(sizes.count == 12 && sizes.filter(\.isAccessibilitySize).count == 5)
        let phoneBelow: [[Pill]] = [[.level, .score, .combo, .progress]]
        let phoneAX: [Bool: [[Pill]]] = [false: [[.level, .combo, .progress], [.level, .progress]],
                                         true: [[.level, .score, .progress], [.score, .progress]]]
        let padAX: [Bool: [[Pill]]] = [false: phoneAX[false]! + [[.progress]], true: phoneAX[true]! + [[.score]]]
        let full: [Pill] = [.level, .score, .combo, .distance, .progress, .accuracy, .speed]
        let padBelow: [Bool: [[Pill]]] = [
            false: [full, full, full.filter { $0 != .distance }, [.level, .score, .combo, .progress, .speed],
                    [.level, .score, .combo, .progress], [.level, .combo, .progress], [.level, .progress], [.progress]],
            true: [full, full, full.filter { $0 != .distance }, [.level, .score, .combo, .progress, .speed],
                   [.level, .score, .combo, .progress], [.level, .score, .progress], [.score, .progress], [.score]],
        ]
        for size in sizes {
            for scoreIsTheRide in [false, true] {
                let phone = RideHUDRungs.offered(narrow: true, size)
                let pad = RideHUDRungs.offered(narrow: false, size)
                if size.isAccessibilitySize {
                    #expect(phone == [.today(fallback: false), .today(fallback: true)], "\(size) phone: \(phone)")
                    #expect(pad == [.today(fallback: false), .today(fallback: true), .compressed(rung: 6)], "\(size) iPad: \(pad)")
                    #expect(phone.map { Self.pills($0, narrow: true, size, scoreIsTheRide: scoreIsTheRide) } == phoneAX[scoreIsTheRide]!,
                            "\(size) phone, Time Attack \(scoreIsTheRide)")
                    #expect(pad.map { Self.pills($0, narrow: false, size, scoreIsTheRide: scoreIsTheRide) } == padAX[scoreIsTheRide]!,
                            "\(size) iPad, Time Attack \(scoreIsTheRide)")
                } else {
                    #expect(phone == [.today(fallback: false)], "\(size) phone: \(phone)")
                    #expect(pad == [.todayOneLine] + (0...6).map { .compressed(rung: $0) }, "\(size) iPad: \(pad)")
                    #expect(phone.map { Self.pills($0, narrow: true, size, scoreIsTheRide: scoreIsTheRide) } == phoneBelow,
                            "\(size) phone, Time Attack \(scoreIsTheRide)")
                    #expect(pad.map { Self.pills($0, narrow: false, size, scoreIsTheRide: scoreIsTheRide) } == padBelow[scoreIsTheRide]!,
                            "\(size) iPad, Time Attack \(scoreIsTheRide)")
                }
            }
        }
    }

    // MARK: 3. What VoiceOver hears

    static func shed(_ rung: Int, _ scoreIsTheRide: Bool, zh: Bool, level: String = "N3") -> String? {
        RideHUDSpoken.shedValues(rung: rung, scoreIsTheRide: scoreIsTheRide, level: level, score: 891, combo: 6,
                                 distanceMeters: 150.7, queueLengthIsTheTarget: !scoreIsTheRide,
                                 completed: scoreIsTheRide ? 37 : 6, count: scoreIsTheRide ? 300 : 12,
                                 progressLabel: (scoreIsTheRide ? GameMode.timeAttack : .journey).hudProgressLabel(zh: zh),
                                 accuracy: 0.973, wpm: 42.6, zh: zh)
    }

    /// Each rung's suffix, written out en and zh: what it sheds relative to rung 0 — the full row, an
    /// iPad's and a Mac's base — in HUD order, nil at rung 0. Rungs 4 and 5 say exactly what 1.34's
    /// accessibility-size rows say on an iPad (`RideHUDSpoken.hiddenValues`), since they draw the same
    /// pills. Mutations, each red here: the composer comparing against rung 3 (a phone's base); the
    /// count spoken as "37 words"; the level spoken when there is no current word; the zh separator
    /// "，"; the progress part placed after the speed.
    @Test("each compressed rung speaks exactly what it sheds, en and zh, and nothing at rung 0")
    func composerTable() {
        let queueEN: [String?] = [
            nil,
            ", distance 150 meters",
            ", distance 150 meters, accuracy 97%",
            ", distance 150 meters, accuracy 97%, speed 42 words per minute",
            ", score 891, distance 150 meters, accuracy 97%, speed 42 words per minute",
            ", score 891, combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute",
            ", level N3, score 891, combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute",
        ]
        let queueZH: [String?] = [
            nil,
            "、距离 150 米",
            "、距离 150 米、正确率 97%",
            "、距离 150 米、正确率 97%、速度 每分钟 42 词",
            "、得分 891、距离 150 米、正确率 97%、速度 每分钟 42 词",
            "、得分 891、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词",
            "、等级 N3、得分 891、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词",
        ]
        let timeAttackEN: [String?] = [
            nil,
            ", distance 150 meters",
            ", distance 150 meters, accuracy 97%",
            ", distance 150 meters, accuracy 97%, speed 42 words per minute",
            ", combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute",
            ", level N3, combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute",
            ", level N3, combo 6, distance 150 meters, words 37, accuracy 97%, speed 42 words per minute",
        ]
        let timeAttackZH: [String?] = [
            nil,
            "、距离 150 米",
            "、距离 150 米、正确率 97%",
            "、距离 150 米、正确率 97%、速度 每分钟 42 词",
            "、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词",
            "、等级 N3、连击 6、距离 150 米、正确率 97%、速度 每分钟 42 词",
            "、等级 N3、连击 6、距离 150 米、进度 37、正确率 97%、速度 每分钟 42 词",
        ]
        for rung in 0...6 {
            #expect(Self.shed(rung, false, zh: false) == queueEN[rung], "queue rung \(rung) en: \(String(describing: Self.shed(rung, false, zh: false)))")
            #expect(Self.shed(rung, false, zh: true) == queueZH[rung], "queue rung \(rung) zh: \(String(describing: Self.shed(rung, false, zh: true)))")
            #expect(Self.shed(rung, true, zh: false) == timeAttackEN[rung], "Time Attack rung \(rung) en: \(String(describing: Self.shed(rung, true, zh: false)))")
            #expect(Self.shed(rung, true, zh: true) == timeAttackZH[rung], "Time Attack rung \(rung) zh: \(String(describing: Self.shed(rung, true, zh: true)))")
        }
        // Rungs 4 and 5 against 1.34's composer for the same pills, on an iPad at AX1.
        for scoreIsTheRide in [false, true] {
            for zh in [false, true] {
                for (rung, fallback) in [(4, false), (5, true)] {
                    let old = RideHUDSpoken.hiddenValues(typeSize: .accessibility1, scoreIsTheRide: scoreIsTheRide, fallback: fallback,
                                                         narrow: false, level: "N3", score: 891, combo: 6, distanceMeters: 150.7,
                                                         accuracy: 0.973, wpm: 42.6, zh: zh)
                    #expect(Self.shed(rung, scoreIsTheRide, zh: zh) == old, "rung \(rung), Time Attack \(scoreIsTheRide), zh \(zh)")
                }
            }
        }
        // No current word: the level part is left out, as the capsule draws nothing.
        #expect(Self.shed(6, false, zh: false, level: "")
                == ", score 891, combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute")
    }

    /// Who carries the suffix, and the whole string a VoiceOver rider hears from it: the progress
    /// pill, in every rung that draws it; Time Attack's last rung sheds the count, so its score pill
    /// says the score and then the rest. `scoreWords(_:hidden:)` has `progressWords`' shape: the
    /// suffix follows the whole value. Mutation, red here: `scoreWords(_:hidden:)` returning the
    /// suffix alone.
    @Test("the progress pill carries the suffix, and in Time Attack's last rung the score pill does")
    func carrierSpeaksTheWholeValue() {
        for scoreIsTheRide in [false, true] {
            for rung in 0...6 {
                let progress = RideHUDRungs.shows(.progress, rung: rung, scoreIsTheRide: scoreIsTheRide)
                let score = RideHUDRungs.shows(.score, rung: rung, scoreIsTheRide: scoreIsTheRide)
                #expect(progress || score, "rung \(rung), Time Attack \(scoreIsTheRide): nothing left to carry the suffix")
                #expect(progress == !(scoreIsTheRide && rung == 6), "rung \(rung), Time Attack \(scoreIsTheRide)")
            }
        }
        #expect(RideHUDSpoken.scoreWords(891, hidden: Self.shed(6, true, zh: false))
                == "891, level N3, combo 6, distance 150 meters, words 37, accuracy 97%, speed 42 words per minute")
        #expect(RideHUDSpoken.scoreWords(891, hidden: Self.shed(6, true, zh: true))
                == "891、等级 N3、连击 6、距离 150 米、进度 37、正确率 97%、速度 每分钟 42 词")
        #expect(RideHUDSpoken.scoreWords(891, hidden: nil) == "891")
        #expect(RideHUDSpoken.progressWords(queueLengthIsTheTarget: true, completed: 6, count: 12, zh: false,
                                            hidden: Self.shed(6, false, zh: false))
                == "6 of 12, level N3, score 891, combo 6, distance 150 meters, accuracy 97%, speed 42 words per minute")
    }

    // MARK: 4. The reserves

    /// What the compressed rungs reserve, written out. Mutations, each red here: the speed reserve
    /// two digits ("00"); the accuracy reserve "99%"; `comboReserve` without the dash.
    ///
    /// And an iPad's second accessibility-size row reserves the ride's level labels, where a phone's
    /// reserves none (`RideHUDLayout.levelReserve`): on an iPad a third child follows that row, so its
    /// ideal width decides between drawing the level capsule and shedding it
    /// (`axMixedLevelRidesOnlyMoveDown`), and on a phone it is the last child and decides nothing.
    /// The device is read as `HUDBar.narrow` reads it, as a default argument, so today's row calls
    /// the function as at f37fab7. Mutations, each red here: the guard back to `!fallback` (the
    /// reserve gone from the iPad's second row); `!(fallback || narrow)` (gone from a phone's first
    /// row); the default argument `narrow: Bool = false`.
    @MainActor
    @Test("the compressed rungs reserve the widest level, combo, accuracy and speed a ride can show")
    func reserves() throws {
        #expect(RideHUDRungs.accuracyReserve == ["100%"])
        #expect(RideHUDRungs.speedReserve == ["—", "000"])
        #expect(RideHUDRungs.comboReserve(wordCount: 150) == ["—", "×150"])
        #expect(RideHUDRungs.comboReserve(wordCount: 1) == ["—"])
        let mixed = V133GRideAndDrillLayoutTests.entries([.n5, .n1, .n3, .n1])
        #expect(RideHUDRungs.levelReserve(words: mixed) == ["N1", "N3", "N5"])
        // 1.33's accessibility-size reserves are these same values, still at those sizes only.
        #expect(RideHUDLayout.comboReserve(.accessibility1, fallback: false, wordCount: 150) == RideHUDRungs.comboReserve(wordCount: 150))
        #expect(RideHUDLayout.comboReserve(.large, fallback: false, wordCount: 150) == [])
        for narrow in [false, true] {
            #expect(RideHUDLayout.levelReserve(.accessibility1, fallback: false, words: mixed, narrow: narrow) == ["N1", "N3", "N5"])
            #expect(RideHUDLayout.levelReserve(.accessibility1, fallback: true, words: mixed, narrow: narrow) == (narrow ? [] : ["N1", "N3", "N5"]),
                    "narrow \(narrow): the second row's reserve")
            #expect(RideHUDLayout.levelReserve(.large, fallback: true, words: mixed, narrow: narrow) == [])
            #expect(RideHUDLayout.levelReserve(.large, fallback: false, words: mixed, narrow: narrow) == [])
        }
        // The default is the device, the global `HUDBar.narrow` reads.
        let file = try Self.gameView
        let layout = try #require(file.typeBodies(named: "RideHUDLayout").first)
        let declaration = try #require(file.functions(named: "levelReserve").first { layout.contains($0.keywordOffset) })
        let parameters = Self.collapsed(file.text(try #require(declaration.parameters)))
        #expect(parameters == "_ typeSize: DynamicTypeSize, fallback: Bool, words: [VocabEntry], narrow: Bool = isPhoneIdiom",
                "RideHUDLayout.levelReserve takes (\(parameters))")
        let hud = try #require(file.typeBodies(named: "HUDBar").first)
        #expect(Self.collapsed(file.text(hud)).contains("private var narrow: Bool { isPhoneIdiom }"), "HUDBar.narrow is not the device")
    }

    // MARK: 5. HUDRowLayout

    /// The whole placement rule on made-up widths (items 30, 40, 50, 60 wide; two left of the centre):
    /// today's `HStack` + `Spacer` placement while the centre gap can be 6pt or more, then the other
    /// gaps close evenly, then — nothing fits — every gap at 6pt and the row's right end kept. And the
    /// rows with nothing on one side. Mutations, each red here: the centre never closing below 14
    /// (`centre >= spacing`); the overflow row anchored left; the minimum gap 4; `leading == 0`
    /// placed from the left.
    @Test("HUDRowLayout places as today's row while it can, then closes the gaps, then keeps the pause button")
    func placementRule() {
        #expect(HUDRowLayout.minimumGap == 6)
        func at(_ width: CGFloat, _ widths: [CGFloat] = [30, 40, 50, 60], leading: Int = 2) -> [CGFloat] {
            HUDRowLayout.positions(widths: widths, leading: leading, width: width, spacing: 14)
        }
        #expect(at(400) == [0, 44, 276, 340])          // room: 14 inside each side, the rest in the centre
        #expect(at(220) == [0, 44, 96, 160])           // the centre at 12: every other gap still 14
        #expect(at(214) == [0, 44, 90, 154])           // the centre at exactly 6
        #expect(at(205) == [0, 39.5, 85.5, 145])       // the other gaps 9.5 each, the centre 6
        #expect(at(198) == [0, 36, 82, 138])           // every gap 6: the row's ideal width
        #expect(at(190) == [-8, 28, 74, 130])          // short by 8: the left end goes, the right stays
        // Nothing left of the centre: right-aligned, like a Spacer first.
        #expect(at(300, [50, 44], leading: 0) == [192, 256])
        #expect(at(100, [50, 44], leading: 0) == [0, 56])
        #expect(at(98, [50, 44], leading: 0) == [-2, 54])
        // One item: right with nothing on its left, left with nothing on its right (a Mac has no pause).
        #expect(at(300, [80], leading: 0) == [220])
        #expect(at(300, [80], leading: 1) == [0])
        // Time Attack's last rung on a touch device: the score left, pause right.
        #expect(at(300, [80, 44], leading: 1) == [0, 256])
        #expect(at(0, [], leading: 0) == [])
    }

    #if canImport(AppKit)
    /// Where today's row fits, `HUDRowLayout` draws it as `HStack(spacing: 14)` with a `Spacer` does —
    /// measured, pixel for pixel, on rows of the HUD's own kind (text in capsules, fractional widths),
    /// so that where a ride steps from today's row to rung 0 the only thing that moves is the centre
    /// gap — in either axis: the first item is built like the HUD's level capsule (14pt heavy text,
    /// 6pt vertical padding), shorter than the pills, so a layout that did not centre each item
    /// vertically as the `HStack` does would draw it elsewhere. Control: at a width the `HStack` does
    /// not fit, the two differ. Mutations, each red here: the layout placing from `bounds.minX + 1`;
    /// placing at `bounds.minY` with anchor `.topLeading` (the capsule drawn higher than the stack
    /// draws it; red at all three widths).
    @MainActor
    @Test("where today's row fits, HUDRowLayout draws it exactly as HStack and Spacer do")
    func layoutMatchesTheStackWhereItFits() {
        func pill(_ text: String) -> some View {
            Text(text).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.42), in: Capsule())
        }
        func capsule(_ text: String) -> some View {
            Text(text).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.blue.opacity(0.85), in: Capsule())
        }
        let texts = ["N5", "★ 1234", "×17", "150 m", "19/20", "97%", "42"]
        let stack = HStack(spacing: 14) {
            capsule(texts[0]); pill(texts[1]); pill(texts[2]); Spacer()
            pill(texts[3]); pill(texts[4]); pill(texts[5]); pill(texts[6])
        }
        let layout = HUDRowLayout(leading: 3) {
            capsule(texts[0]); pill(texts[1]); pill(texts[2])
            pill(texts[3]); pill(texts[4]); pill(texts[5]); pill(texts[6])
        }
        #expect(Self.ideal(capsule(texts[0])).height + 4 < Self.ideal(pill(texts[1])).height,
                "control: the capsule is not shorter than the pills, so the vertical placement is not tested")
        let idealStack = Self.ideal(stack).width
        #expect(idealStack > 300, "the instrument is not laying the row out: \(idealStack)")
        for width in [idealStack.rounded(.up), idealStack + 13.5, 900] {
            #expect(Self.pixels(stack, width: width) == Self.pixels(layout, width: width),
                    "at \(width)pt the layout draws the row differently from the stack")
        }
        let tight = idealStack - 20
        #expect(Self.pixels(stack, width: tight) != Self.pixels(layout, width: tight),
                "control: at \(tight)pt the stack no longer fits and the two should differ")
        // Its ideal width is the items' and 6pt between each; ViewThatFits takes it there and not 1pt under.
        let idealLayout = Self.ideal(layout).width
        let items = Self.ideal(capsule(texts[0])).width + texts.dropFirst().map { Self.ideal(pill($0)).width }.reduce(0, +)
        #expect(abs(idealLayout - (items + 6 * 6)) < 0.01, "the layout's ideal width is \(idealLayout), its items \(items)")
        #expect(V133GRideAndDrillLayoutTests.taken(layout, at: idealLayout.rounded(.up)))
        #expect(!V133GRideAndDrillLayoutTests.taken(layout, at: idealLayout.rounded(.up) - 1))
        // Every rung, not only rung 0: the same vertical centring with fewer leading items (rungs 4–6
        // shed the score, then the combo, then the level). Review of 727be4f: a layout that top-aligned
        // only rows whose leading side is shorter than today's passed every other test here.
        for leading in [2, 1] {
            let stackN = HStack(spacing: 14) {
                capsule(texts[0]); if leading == 2 { pill(texts[2]) }; Spacer()
                pill(texts[4]); pill(texts[6])
            }
            let layoutN = HUDRowLayout(leading: leading) {
                capsule(texts[0]); if leading == 2 { pill(texts[2]) }
                pill(texts[4]); pill(texts[6])
            }
            let roomy = Self.ideal(stackN).width.rounded(.up) + 40
            #expect(Self.pixels(stackN, width: roomy) == Self.pixels(layoutN, width: roomy),
                    "with \(leading) leading item(s) the layout draws the row differently from the stack")
        }
    }
    #endif

    // MARK: 6. The source

    static var gameView: CallSiteScanner.File {
        get throws {
            try #require(try CallSiteScanner.shippedSources.get().first { $0.path == "Sources/NihongoRideApp/GameView.swift" })
        }
    }

    static func collapsed(_ text: String) -> String { V133GRideAndDrillLayoutTests.collapsed(text) }

    /// `HUDBar.body`, comment-blanked, against the table: the three `ViewThatFits` are offered exactly
    /// `RideHUDRungs.offered`'s children for their branch, and the one-row branch is a phone's below
    /// the accessibility sizes. Mutations, each red here (and each also against `offeredRows` when
    /// made in `offered` instead): a child removed; two children swapped; `compressed(rung: 5)` in the
    /// iPad's accessibility-size branch; the `if narrow` inside the accessibility branch removed; the
    /// ladder offered on a phone (`} else if narrow {` → `} else if false {`); a child commented out.
    @Test("HUDBar.body offers exactly the rows RideHUDRungs.offered lists")
    func bodyIsTheTable() throws {
        let file = try Self.gameView
        let hud = try #require(file.typeBodies(named: "HUDBar").first)
        let hudText = file.text(hud)
        let declarations = hudText.components(separatedBy: "var body: some View {").count - 1
        #expect(declarations == 1, "HUDBar declares \(declarations) body")
        let start = try #require(hudText.range(of: "var body: some View {"))
        let open = hud.lowerBound + hudText.utf8.distance(from: hudText.startIndex, to: start.upperBound) - 1
        let close = try #require(CallSiteScanner.matching(file.code, open: open))
        let body = open..<(close + 1)
        func fits(_ narrow: Bool, _ size: DynamicTypeSize) -> String {
            let rows = RideHUDRungs.offered(narrow: narrow, size).map(\.description)
            return rows.count == 1 ? rows[0] : "ViewThatFits(in: .horizontal) { \(rows.joined(separator: " ")) }"
        }
        let expected = "{ if typeSize.isAccessibilitySize { if narrow { \(fits(true, .accessibility1)) } "
            + "else { \(fits(false, .accessibility1)) } } else if narrow { \(fits(true, .large)) } "
            + "else { \(fits(false, .large)) } }"
        #expect(Self.collapsed(file.text(body)) == expected, "HUDBar.body is \(Self.collapsed(file.text(body)))")
    }

    /// Rung (a) is today's row: `row(fallback:)` and `stat`, each from its `func` keyword through its
    /// closing brace — the parameter list and its default arguments as well as the body —
    /// comment-blanked with strings kept and whitespace collapsed, hash to exactly what they were at
    /// f37fab7 (the v1.35 step 3 commit this branch starts from). So wherever `ViewThatFits` takes the
    /// first child it draws, and VoiceOver hears, what 1.34 did: not a copy of it, the same code. (The
    /// access modifier before `func` is not hashed: `row` lost its `private` so the tests can host
    /// it.) What reaches that code from outside — `RideHUDLayout`'s rules and reserves,
    /// `RideHUDSpoken`'s words, `IdealWidthReserve` — has its own pins. Recomputing the literals means
    /// reading f37fab7's GameView through this same function (`CallSiteScanner.File(path:source:)` over
    /// `git show f37fab7:Sources/NihongoRideApp/GameView.swift`); a change to either function is a
    /// change to what every fitting row draws, and needs its own proof. Mutations, each red here: one
    /// character of a string in `row(fallback:)` (`"pauseButton"` → `"pausebutton"`); `stat`'s
    /// horizontal padding 12 → 11; a modifier appended to the progress pill in `row(fallback:)`;
    /// `stat`'s default `spoken: String? = ""` (today's score and accuracy pills would speak an empty
    /// value); its default `reserving: [String] = ["000"]`.
    @Test("today's row and its pill are f37fab7's, byte for byte, signature and defaults included")
    func todaysRowIsVerbatim() throws {
        let file = try Self.gameView
        #expect(try Self.digest(file, "row") == Self.f37fab7Row, "row(fallback:) is not f37fab7's")
        #expect(try Self.digest(file, "stat") == Self.f37fab7Stat, "stat is not f37fab7's")
    }

    /// `HUDBar`'s function `name` from `func` through `}`, comment-blanked, strings kept, whitespace
    /// collapsed: its SHA-256.
    static func digest(_ file: CallSiteScanner.File, _ name: String) throws -> String {
        let hud = try #require(file.typeBodies(named: "HUDBar").first)
        let functions = file.functions(named: name).filter { hud.contains($0.keywordOffset) }
        let declaration = try #require(functions.count == 1 ? functions.first : nil, "HUDBar declares \(functions.count) \(name)")
        let body = try #require(declaration.body)
        #expect(file.text(declaration.keywordOffset..<(declaration.keywordOffset + 4)) == "func")
        let text = Self.collapsed(String(decoding: file.codeWithStrings[declaration.keywordOffset..<body.upperBound], as: UTF8.self))
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static let f37fab7Row = "71ff2877d36f9fa4faf457ebece55869aeafb1c8aa4a18ce0603a19487f76f2c"
    static let f37fab7Stat = "d47e84bc51cc05cdaf22b50b2c5b9129b32af6fb3fb9d349a85836908d51e841"

    /// Every child keeps the identifiers the UI tests and the pills' tests find: in `row(fallback:)`
    /// and in `compressed(rung:)` the pause button is `pauseButton` (four iOS UI test files tap it),
    /// the progress pill `hudProgress` and the speed pill `hudSpeed`, each exactly once and on the
    /// element itself. Mutations, each red here: `compressed`'s pause button without its identifier;
    /// its speed pill's identifier moved onto the accuracy pill; `hudProgress` on the combo pill.
    @Test("every child names its pause button, progress pill and speed pill")
    func identifiersOnEveryChild() throws {
        let file = try Self.gameView
        let hud = try #require(file.typeBodies(named: "HUDBar").first)
        for name in ["row", "compressed"] {
            let body = try #require(file.functions(named: name).first { hud.contains($0.keywordOffset) }?.body,
                                    "HUDBar has no \(name)")
            let text = String(decoding: file.codeWithStrings[body], as: UTF8.self)
            for id in ["pauseButton", "hudProgress", "hudSpeed"] {
                #expect(text.components(separatedBy: ".accessibilityIdentifier(\"\(id)\")").count == 2,
                        "\(name): \(id) is not set exactly once")
            }
            #expect(text.components(separatedBy: ".accessibilityIdentifier(").count == 4, "\(name) sets another identifier")
            // Each on its own element: the identifier follows that element's call directly.
            let calls = file.calls(named: "stat").filter { body.contains($0.nameOffset) }
            for (icon, id) in [("checkmark.circle.fill", "hudProgress"), ("speedometer", "hudSpeed")] {
                let pill = calls.filter { call in
                    call.arguments.map { String(decoding: file.codeWithStrings[$0], as: UTF8.self) }?.contains("icon: \"\(icon)\"") ?? false
                }
                #expect(pill.count == 1, "\(name): \(pill.count) \(icon) pills")
                if let call = pill.first {
                    let after = Self.collapsed(String(decoding: file.codeWithStrings[call.extent.upperBound..<min(body.upperBound, call.extent.upperBound + 80)], as: UTF8.self))
                    #expect(after.hasPrefix(".accessibilityIdentifier(\"\(id)\")"), "\(name): the \(icon) pill is followed by \(after)")
                }
            }
            let buttons = file.calls(named: "Button").filter { body.contains($0.nameOffset) }
            #expect(buttons.count == 1, "\(name): \(buttons.count) buttons")
            if let button = buttons.first {
                let after = Self.collapsed(String(decoding: file.codeWithStrings[button.extent.upperBound..<min(body.upperBound, button.extent.upperBound + 200)], as: UTF8.self))
                #expect(after.hasPrefix(".buttonStyle(.plain) .accessibilityLabel(zh ? \"暂停\" : \"Pause\") .accessibilityIdentifier(\"pauseButton\")"),
                        "\(name): the pause button is followed by \(after)")
            }
        }
    }

    /// `compressed(rung:)` builds each pill as `row(fallback:)` does — the same `stat` arguments, the
    /// same level capsule, the same pause button — except where it must differ, each difference written
    /// out: its gates (`if shows(.pill)`), its reserves, and its spoken suffix (`hidden`, and the score
    /// pill's in Time Attack's last rung). So a change to a pill in one row that is not made in the
    /// other goes red. Mutations, each red here: the compressed score pill drawing `"\(session.score)"`;
    /// its combo pill's tint `Theme.dim` always; its distance pill's spoken value dropped; its level
    /// capsule without `.lineLimit(typeSize.isAccessibilitySize ? 1 : nil)`; its pause button 40pt
    /// wide; the progress pill's `hidden: nil`; the score pill's suffix given at every rung
    /// (`spoken: RideHUDSpoken.scoreWords(session.score, hidden: hidden)`).
    @Test("the compressed rows build every pill as today's row does, but for their gates, reserves and suffix")
    func compressedPillsMirrorTodaysRow() throws {
        let file = try Self.gameView
        let hud = try #require(file.typeBodies(named: "HUDBar").first)
        func body(_ name: String) throws -> Range<Int> {
            try #require(file.functions(named: name).first { hud.contains($0.keywordOffset) }?.body)
        }
        let row = try body("row"), compressed = try body("compressed")
        func stats(_ range: Range<Int>) -> [String: String] {
            var out: [String: String] = [:]
            for call in file.calls(named: "stat") where range.contains(call.nameOffset) {
                let arguments = Self.collapsed(call.arguments.map { String(decoding: file.codeWithStrings[$0], as: UTF8.self) } ?? "")
                let icon = arguments.firstMatch(of: /icon: "([^"]*)"/).map { String($0.output.1) } ?? "?"
                #expect(out[icon] == nil, "two \(icon) pills in one row")
                out[icon] = arguments
            }
            return out
        }
        let today = stats(row), rung = stats(compressed)
        #expect(Set(today.keys) == Set(rung.keys) && today.count == 6, "today \(today.keys.sorted()), compressed \(rung.keys.sorted())")
        let differences: [String: (today: String, rung: String)] = [
            "star.fill": ("label: zh ? \"得分\" : \"Score\"",
                          "label: zh ? \"得分\" : \"Score\", spoken: shows(.progress) ? nil : RideHUDSpoken.scoreWords(session.score, hidden: hidden)"),
            "flame.fill": ("reserving: combos", "reserving: RideHUDRungs.comboReserve(wordCount: session.wordCount)"),
            "checkmark.circle.fill": ("hidden: RideHUDSpoken.hiddenValues(typeSize: typeSize, scoreIsTheRide: scoreIsTheRide, "
                                      + "fallback: fallback, narrow: narrow, level: session.currentLevelLabel, score: session.score, "
                                      + "combo: session.combo, distanceMeters: session.distanceMeters, accuracy: session.accuracy, "
                                      + "wpm: wpm, zh: zh))", "hidden: hidden)"),
            "scope": ("label: zh ? \"正确率\" : \"Accuracy\"", "label: zh ? \"正确率\" : \"Accuracy\", reserving: RideHUDRungs.accuracyReserve"),
            "speedometer": ("spoken: RideHUDSpoken.speedWords(wpm, zh: zh)",
                            "spoken: RideHUDSpoken.speedWords(wpm, zh: zh), reserving: RideHUDRungs.speedReserve"),
        ]
        for (icon, arguments) in today {
            var expected = arguments
            if let difference = differences[icon] {
                #expect(arguments.hasSuffix(difference.today), "today's \(icon) pill ends \(arguments.suffix(80))")
                expected = String(arguments.dropLast(difference.today.count)) + difference.rung
            }
            #expect(rung[icon] == expected, "compressed \(icon) pill: \(rung[icon] ?? "none"), expected \(expected)")
        }
        // Today's progress pill's comment lines are blanked, so its arguments collapse the same way.
        // Each compressed pill is directly behind its own gate, in HUD order, in the layout's closure.
        let layout = try #require(file.calls(named: "HUDRowLayout").first { compressed.contains($0.nameOffset) })
        #expect(layout.arguments.map { Self.collapsed(file.text($0)) } == "leading: RideHUDRungs.leading(rung: rung, scoreIsTheRide: scoreIsTheRide)")
        let closure = try #require(layout.closures.first)
        let heads = file.calls(named: "stat").filter { closure.contains($0.nameOffset) }.map { call in
            V133GRideAndDrillLayoutTests.blockHead(file.innermostBlock(containing: call.nameOffset, within: closure)!, in: file)
        }
        #expect(heads == ["if shows(.score)", "if shows(.combo)", "if shows(.distance)", "if shows(.progress)",
                          "if shows(.accuracy)", "if shows(.speed)"], "compressed pills are behind \(heads)")

        // The level capsule and the pause button: the same chains, but for the capsule's reserve.
        func chain(_ range: Range<Int>, from start: String, to end: String) -> String? {
            let text = Self.collapsed(String(decoding: file.codeWithStrings[range], as: UTF8.self))
            guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else { return nil }
            return String(text[from.lowerBound..<to.upperBound])
        }
        let capsuleToday = try #require(chain(row, from: "Text(session.currentLevelLabel)", to: "\"Level \\(session.currentLevelLabel)\")"))
        let capsuleRung = try #require(chain(compressed, from: "Text(session.currentLevelLabel)", to: "\"Level \\(session.currentLevelLabel)\")"))
        #expect(capsuleRung == capsuleToday.replacingOccurrences(of: ".reservingIdealWidth(for: levels)",
                                                                 with: ".reservingIdealWidth(for: RideHUDRungs.levelReserve(words: session.wordList))"),
                "the compressed level capsule is \(capsuleRung)")
        let pauseToday = try #require(chain(row, from: "if let onPause {", to: ".accessibilityIdentifier(\"pauseButton\")"))
        #expect(chain(compressed, from: "if let onPause {", to: ".accessibilityIdentifier(\"pauseButton\")") == pauseToday)
        #expect(Self.collapsed(file.text(compressed)).hasSuffix(".scaledSystemFont(narrow ? 15 : 17, weight: .semibold, design: .rounded) }"),
                "the compressed row's font is not today's")

        // The suffix is this rung's own: `shedValues` handed `rung` and the session, read once, here.
        let compressedCode = Self.collapsed(file.text(compressed))
        let hidden = compressedCode.firstMatch(of: /let hidden = (.*?) return HUDRowLayout\(/)
        #expect(hidden.map { String($0.output.1) } == "RideHUDSpoken.shedValues(rung: rung, scoreIsTheRide: scoreIsTheRide, "
                + "level: session.currentLevelLabel, score: session.score, combo: session.combo, distanceMeters: session.distanceMeters, "
                + "queueLengthIsTheTarget: session.mode.queueLengthIsTheTarget, completed: session.wordsCompleted, count: session.wordCount, "
                + "progressLabel: session.mode.hudProgressLabel(zh: zh), accuracy: session.accuracy, wpm: wpm, zh: zh)",
                "compressed(rung:) composes \(String(describing: hidden?.output.1))")
        var sites: [String] = []
        for other in try CallSiteScanner.shippedSources.get() {
            for call in other.calls(named: "shedValues") where CallSiteScanner.receiverComponents(call.receiver) == ["RideHUDSpoken"] {
                sites.append(other.location(call.nameOffset))
                #expect(other.path == file.path && compressed.contains(call.nameOffset), "shedValues read at \(other.location(call.nameOffset))")
            }
        }
        #expect(sites.count == 1, "RideHUDSpoken.shedValues is read at \(sites)")
        // The gate helper asks `RideHUDRungs` with the row's own rung and mode.
        #expect(Self.collapsed(file.text(compressed)).hasPrefix("{ func shows(_ pill: RideHUDRungs.Pill) -> Bool { "
                                                                + "RideHUDRungs.shows(pill, rung: rung, scoreIsTheRide: scoreIsTheRide) }"))
    }

    /// The composer builds its words from the pills' functions and formats no number itself, as
    /// `hiddenValues` does (`V134B3HUDSpokenTests.composerFormatsNothingItself`). Mutation, red here:
    /// the composer's score part as `"score \(score)"`.
    @Test("shedValues formats nothing itself")
    func shedComposerFormatsNothingItself() throws {
        let file = try Self.gameView
        let composer = try #require(file.typeBodies(named: "RideHUDSpoken").first)
        let body = try #require(file.functions(named: "shedValues").first { composer.contains($0.keywordOffset) }?.body)
        let text = Self.collapsed(String(decoding: file.codeWithStrings[body], as: UTF8.self))
        for part in ["parts.append((zh ? \"得分 \" : \"score \") + scoreWords(score))",
                     "parts.append((zh ? \"连击 \" : \"combo \") + comboWords(combo, zh: zh))",
                     "parts.append((zh ? \"距离 \" : \"distance \") + distanceWords(distanceMeters, zh: zh))",
                     "progressWords(queueLengthIsTheTarget: queueLengthIsTheTarget, completed: completed, count: count, zh: zh, hidden: nil))",
                     "parts.append((zh ? \"正确率 \" : \"accuracy \") + accuracyWords(accuracy))",
                     "parts.append((zh ? \"速度 \" : \"speed \") + speedWords(wpm, zh: zh))",
                     "return suffix(parts, zh: zh)"] {
            #expect(text.contains(part), "shedValues no longer has \(part)")
        }
        #expect(text.matches(of: /\\\(/).count == 2, "shedValues interpolates something besides the level: \(text)")
        let code = Self.collapsed(file.text(body))
        #expect(!code.contains("Int(") && !code.contains("* 100") && !code.contains(".joined"), "shedValues formats something itself")
    }

    /// `emulatedTextScale` is an instrument's: nothing the app ships sets it, and its default is 1,
    /// so every `scaledSystemFont` in the app is what it was. Pinned three ways: no shipped source but
    /// its declaration and `ScaledSystemFont` mentions it; the declaration and the one product are
    /// the text below; and an environment nobody set reads exactly 1. Mutations, each red here:
    /// `.environment(\.emulatedTextScale, 1.1)` on the ride screen; the default `= 1.25` (which grew
    /// every scaled font in the app by a quarter with the whole suite green before this pin); the
    /// product `size * emulatedTextScale * 1.01`.
    @Test("no shipped source sets emulatedTextScale, and its default is 1")
    func emulatedTextScaleIsNeverSet() throws {
        var mentions: [String] = []
        for file in try CallSiteScanner.shippedSources.get() {
            for offset in file.mentions(of: "emulatedTextScale") { mentions.append(file.location(offset)) }
        }
        #expect(mentions.count == 4 && mentions.allSatisfy { $0.hasPrefix("Sources/NihongoRideApp/ScaledFont.swift") },
                "emulatedTextScale is mentioned at \(mentions); expected its declaration and ScaledSystemFont's property, key path and product")
        let font = try #require(try CallSiteScanner.shippedSources.get().first { $0.path == "Sources/NihongoRideApp/ScaledFont.swift" })
        let code = Self.collapsed(font.allCode)
        #expect(code.contains("@Entry var emulatedTextScale: CGFloat = 1 }"), "emulatedTextScale's declaration is not `= 1`")
        #expect(code.contains("let scaled = size * emulatedTextScale let resolved = maxScaled.map { Swift.min(scaled, $0) } ?? scaled"),
                "ScaledSystemFont no longer scales by the factor alone")
        #expect(EnvironmentValues().emulatedTextScale == 1)
    }

    /// The hosted tests lay the HUD out in `GameView.padding(phone:keyboardUp:)`, so the ride screen
    /// must pad with that function and nothing else, or the sweep's window-to-width mapping is a copy.
    /// Mutation, red here: the call site's padding replaced by a literal.
    @Test("the ride screen pads with GameView.padding, the function the hosted tests use")
    func rideScreenPadsWithTheTestedFunction() throws {
        let file = try Self.gameView
        let code = Self.collapsed(file.allCode)
        #expect(code.components(separatedBy: ".padding(Self.padding(phone: isPhoneIdiom, keyboardUp: keyboardUp))").count == 2,
                "GameView's ride column is not padded by Self.padding(phone:keyboardUp:) exactly once")
        let game = try #require(file.typeBodies(named: "GameView").first)
        let padding = try #require(file.functions(named: "padding").first { game.contains($0.keywordOffset) }?.body)
        #expect(Self.collapsed(file.text(padding)) == "{ phone ? (keyboardUp ? 10 : 16) : (keyboardUp ? 14 : 32) }")
    }

    // MARK: 7. Hosted

    #if canImport(AppKit)
    /// The iOS body point size at each size this file lays out, over the default's 17.
    static let bodyScale: [DynamicTypeSize: CGFloat] = [.large: 1, .xxxLarge: 23.0 / 17, .accessibility1: 28.0 / 17]

    @MainActor
    static func sized<V: View>(_ view: V, _ size: DynamicTypeSize) -> some View {
        view.environment(\.dynamicTypeSize, size).environment(\.emulatedTextScale, bodyScale[size] ?? 1)
    }

    @MainActor
    static func ideal<V: View>(_ view: V) -> CGSize {
        NSHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 5_000, height: 1_000))
    }

    @MainActor
    static func natural<V: View>(_ view: V, _ width: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 1_000))
    }

    /// `view` laid out `width` wide in an `NSHostingView`, its pixels.
    @MainActor
    static func pixels<V: View>(_ view: V, width: CGFloat) -> Data? {
        render(ZStack(alignment: .topLeading) { Color(white: 0.2); view.frame(width: width) }
            .frame(width: width, height: 80, alignment: .topLeading), CGSize(width: width, height: 80)).data
    }

    @MainActor
    static func render<V: View>(_ view: V, _ size: CGSize) -> (data: Data?, rep: NSBitmapImageRep?) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), let _ = rep.bitmapData else { return (nil, nil) }
        host.cacheDisplay(in: host.bounds, to: rep)
        return (Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh), rep)
    }

    /// The runs of columns (in points) holding any pixel unlike the top-left corner's: on the HUD's
    /// flat background, one run per pill, the pause button last.
    static func segments(_ rep: NSBitmapImageRep) -> [(left: CGFloat, right: CGFloat)] {
        let perRow = rep.bytesPerRow, height = rep.pixelsHigh, width = rep.pixelsWide, samples = rep.samplesPerPixel
        guard let bytes = rep.bitmapData else { return [] }
        let scale = CGFloat(width) / rep.size.width
        let background = (bytes[0], bytes[1], bytes[2])
        var ink = [Bool](repeating: false, count: width)
        for y in 0..<height {
            let row = bytes + y * perRow
            for x in 0..<width where !ink[x] {
                let o = x * samples
                if row[o] != background.0 || row[o + 1] != background.1 || row[o + 2] != background.2 { ink[x] = true }
            }
        }
        var out: [(CGFloat, CGFloat)] = []
        var x = 0
        while x < width {
            guard ink[x] else { x += 1; continue }
            var end = x
            while end + 1 < width, ink[end + 1] { end += 1 }
            out.append((CGFloat(x) / scale, CGFloat(end + 1) / scale))
            x = end + 1
        }
        return out
    }

    static let margin: CGFloat = 20

    /// The HUD in GameView's padding (`GameView.padding`, the screen's own constant), in a window
    /// `window` wide, on a canvas `margin` wider each side: its pixels, and the padding.
    @MainActor
    static func canvas<V: View>(_ hud: V, window: CGFloat, keyboardUp: Bool) -> (data: Data?, rep: NSBitmapImageRep?, pad: CGFloat) {
        let pad = GameView.padding(phone: false, keyboardUp: keyboardUp)
        let canvas = ZStack(alignment: .topLeading) {
            Color(white: 0.2)
            hud.padding(.horizontal, pad).frame(width: window).offset(x: margin, y: 8)
        }
        .frame(width: window + 2 * margin, height: 96, alignment: .topLeading)
        let drawn = render(canvas, CGSize(width: window + 2 * margin, height: 96))
        return (drawn.data, drawn.rep, pad)
    }

    /// The pills' runs in a `canvas`, relative to the HUD's own frame.
    static func runs(_ canvas: (data: Data?, rep: NSBitmapImageRep?, pad: CGFloat)) -> [(left: CGFloat, right: CGFloat)] {
        guard let rep = canvas.rep else { return [] }
        return segments(rep).map { (left: $0.left - margin - canvas.pad, right: $0.right - margin - canvas.pad) }
    }

    /// The pills' runs of `hud` drawn in a `canvas`.
    @MainActor
    static func drawn<V: View>(_ hud: V, window: CGFloat, keyboardUp: Bool) -> [(left: CGFloat, right: CGFloat)] {
        runs(canvas(hud, window: window, keyboardUp: keyboardUp))
    }

    static func words(_ count: Int, levels: [JLPTLevel] = [.n5]) -> [VocabEntry] {
        (0..<count).map { VocabEntry(id: "hud\($0)", surface: "みず", kana: "みず", partsOfSpeech: ["n"],
                                     jlpt: levels[$0 % levels.count], meanings: [:]) }
    }

    /// A ride `done` words in, the first `misses` of them after one wrong key.
    static func session(_ mode: GameMode, count: Int, done: Int, misses: Int, levels: [JLPTLevel] = [.n5]) -> GameSession {
        let session = GameSession(words: words(count, levels: levels),
                                  config: .init(newWordCount: count, reviewWordCount: 0, mode: mode))
        for index in 0..<done {
            if index < misses { session.input("x") }
            for key in "mizu" { session.input(key) }
        }
        return session
    }

    /// The 16 ride states the design sweeps measured: journeys from the first key to the last word,
    /// sentence and dictation rides, 150- and 500-word lists (one mixing levels, one at 112 wpm), and
    /// Time Attack from 0 to 200 words.
    static let states: [(name: String, mode: GameMode, count: Int, done: Int, misses: Int, wpm: Double, levels: [JLPTLevel])] = [
        ("journey-start", .journey, 12, 0, 0, 0, [.n5]),
        ("journey-1", .journey, 12, 1, 0, 9, [.n5]),
        ("journey-miss", .journey, 12, 1, 1, 9, [.n5]),
        ("journey-mid", .journey, 12, 6, 1, 42, [.n5]),
        ("journey-late", .journey, 20, 19, 1, 58, [.n5]),
        ("sentence-start", .sentence, 5, 0, 0, 0, [.n5]),
        ("sentence-late", .sentence, 5, 4, 2, 30, [.n5]),
        ("dictation-start", .dictation, 5, 0, 0, 0, [.n5]),
        ("list-late", .journey, 150, 149, 5, 60, [.n5]),
        ("list-mixed-late", .journey, 150, 149, 5, 60, [.n5, .n3, .n1]),
        ("list500-late", .journey, 500, 499, 5, 60, [.n5]),
        ("list-fast", .journey, 150, 149, 5, 112, [.n5]),
        ("timeattack-start", .timeAttack, 300, 0, 0, 0, [.n5]),
        ("timeattack-mid", .timeAttack, 300, 37, 2, 50, [.n5]),
        ("timeattack-late", .timeAttack, 300, 110, 3, 71, [.n5]),
        ("timeattack-200", .timeAttack, 300, 200, 3, 80, [.n5]),
    ]

    /// iPad windows: 320pt (the narrowest Split View / Stage Manager tile measured), Slide Over and
    /// Split View tiles, every portrait and landscape width from the iPad mini to the 13-inch.
    static let windows: [CGFloat] = [320, 375, 438, 507, 551, 600, 678, 694, 716, 744, 768, 810, 820, 834, 981, 1024, 1133, 1180, 1194, 1366]

    /// The row in every state and window, both keyboard positions, at the default size, xxxLarge and
    /// AX1 (1,920 cells, the iPad's padding taken from `GameView.padding`): one line, no wider than
    /// the width it is given, every pill inside that width (so nothing reaches into the margin the
    /// JourneyBar keeps), and the pause button — the last run, 44pt — whole.
    ///
    /// And **wherever f37fab7's HUD fitted, the same pixels.** `F37fab7HUD` is f37fab7's body over this
    /// file's rows, which `todaysRowIsVerbatim` holds to f37fab7's bytes. Where it is one line inside
    /// the width — and, at the accessibility sizes, where the row its `ViewThatFits` took fitted by
    /// its ideal width — the HUD is drawn beside it and compared pixel for pixel, whichever child
    /// `ViewThatFits` took (below the accessibility sizes today's row wherever it is one line, below).
    /// Measured: L 285/285, xxxL 186/186, AX1 612/612. The cells left out at AX1 are the 13 where
    /// neither of f37fab7's rows fitted and it drew its second row anyway, the level capsule squeezed
    /// toward its 0.7 floor (320pt with the keyboard down in a journey, 320–375pt late in a list ride);
    /// the HUD takes rung 6 there, the level spoken. (The second row's ideal width read here carries
    /// the v1.35 level reserve an iPad's second row now has; the 13 cells and the 612 are the same with
    /// it as they were at 9667144 without it.) Mutations, each
    /// red here: `OneLineFit` removed from the body (today's row wraps where its ideal width fits);
    /// `compressed(rung: 6)` removed from the iPad's accessibility-size branch (the pause button past
    /// the edge at 320pt and 375pt); `HUDRowLayout`'s placement offset 1pt. (No cell here overflows a
    /// compressed rung; the one measured overflow is `overCapListsAtAX1`'s.)
    ///
    /// **And every value is drawn whole, in every cell.** "One line" above is read from the layout's
    /// own answer, so a compressed rung that proposed its pills less than their width — "318…",
    /// "×1…", "149/1…", a level "…" — passed it (review of step 4b). So each cell's runs are held to
    /// the widths of the same pills drawn whole: today's row alone in a 2,400pt window, an `HStack`,
    /// not the layout under test, one run per pill and the pause button. The child the cell must
    /// draw is the first `RideHUDRungs.offered` child whose ideal width fits (checked by these same
    /// runs: another child draws other pills). Bound: 0.6pt, a pixel at 2x and its antialiasing.
    /// Measured: every value whole, and the predicted child drawn, in all 1,920 cells — 837 of them a
    /// compressed rung or the last rung. Mutations, each red here: `HUDRowLayout` proposing 8pt less
    /// than each pill's width in rows of fewer than seven items (rungs 2–6 — the review's truncating
    /// mutant, which every other test passed; red in 475 cells); the same in every row (809).
    ///
    /// **And below the accessibility sizes today's row is the child wherever it is one line** — not
    /// rung 0 drawing its pixels (`OneLineFit`, to within its 0.25pt resolution): measured, in all 471
    /// such cells. Mutations, each red here: `OneLineFit.steps` `[8, 16, 32, 64]`; `[64]`.
    @MainActor
    @Test("in every window the row is one line, inside its width, every value whole, the pause button whole, and f37fab7's wherever that fitted")
    func everyWindowOneLineWithPause() {
        var cells = 0, todayTaken = 0
        var fitted: [DynamicTypeSize: Int] = [:], same: [DynamicTypeSize: Int] = [:], whole: [DynamicTypeSize: Int] = [:]
        var taken: [DynamicTypeSize: [RideHUDRungs.Row: Int]] = [:]
        var squeezed: [String] = []
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility1] {
            let rows = RideHUDRungs.offered(narrow: false, size)
            for state in Self.states {
                let session = Self.session(state.mode, count: state.count, done: state.done, misses: state.misses, levels: state.levels)
                let bar = HUDBar(session: session, language: "en", wpm: state.wpm, onPause: {})
                let hud = Self.sized(bar, size)
                let before = Self.sized(F37fab7HUD(bar: bar), size)
                let line = Self.ideal(hud).height
                let lineBefore = Self.ideal(before).height
                let ideals = rows.map { Self.ideal(Self.sized(Self.child(bar, $0), size)).width }
                let wholeWidths = Self.wholeWidths(bar, size, scoreIsTheRide: state.mode == .timeAttack)
                #expect(!wholeWidths.isEmpty, "\(size) \(state.name): today's row did not draw one run per pill with room")
                // At the accessibility sizes f37fab7's `ViewThatFits` took a row only where its ideal
                // width fitted; where neither did it drew the second anyway, the level capsule
                // squeezed toward its 0.7 floor or "…" (v1.33 round 3's "not fitted").
                let idealRows = size.isAccessibilitySize
                    ? [false, true].map { Self.ideal(Self.sized(Self.child(bar, .today(fallback: $0)), size)).width } : []
                for window in Self.windows {
                    for keyboardUp in [false, true] {
                        let width = window - 2 * GameView.padding(phone: false, keyboardUp: keyboardUp)
                        let here = "\(size) \(state.name) \(Int(window))pt keyboard \(keyboardUp ? "up" : "down")"
                        let natural = Self.natural(hud, width)
                        #expect(natural.width <= width + 0.01, "\(here): the row is \(natural.width) wide in \(width)")
                        #expect(natural.height <= line + 0.5, "\(here): the row is \(natural.height) tall, a line is \(line)")
                        let canvas = Self.canvas(hud, window: window, keyboardUp: keyboardUp)
                        let runs = Self.runs(canvas)
                        let first = runs.first?.left ?? -1, last = runs.last?.right ?? .infinity
                        let pause = runs.last.map { $0.right - $0.left } ?? 0
                        #expect(first >= -0.01 && last <= width + 0.01, "\(here): ink from \(first) to \(last) in a row \(width) wide")
                        #expect(abs(pause - 44) < 0.6, "\(here): the last run is \(pause)pt, not the 44pt pause button")
                        // Every value whole: the predicted child's pills at their whole widths.
                        let child = ideals.firstIndex { $0 <= width } ?? rows.count - 1
                        taken[size, default: [:]][rows[child], default: 0] += 1
                        let expected = (Self.pills(rows[child], narrow: false, size, scoreIsTheRide: state.mode == .timeAttack).map(Optional.some) + [nil])
                            .map { wholeWidths[$0] ?? -100 }
                        let widths = runs.map { $0.right - $0.left }
                        let isWhole = widths.count == expected.count && zip(widths, expected).allSatisfy { abs($0 - $1) <= 0.6 }
                        #expect(isWhole, "\(here): \(rows[child]) should draw its pills whole, \(expected); it drew \(widths)")
                        if isWhole { whole[size, default: 0] += 1 }
                        let old = Self.natural(before, width)
                        let oneLine = old.height <= lineBefore + 0.5 && old.width <= width + 0.01
                        // Below the accessibility sizes `before` is today's row alone.
                        if !size.isAccessibilitySize && oneLine {
                            todayTaken += 1
                            #expect(child == 0 || ideals[0] - width <= 0.25 + 0.001,
                                    "\(here): today's row is one line in \(width) and ViewThatFits takes \(rows[child]) (OneLineFit answers \(ideals[0]))")
                        }
                        if oneLine && !idealRows.isEmpty && !idealRows.contains(where: { $0 <= width }) {
                            squeezed.append(here)
                        } else if oneLine {
                            fitted[size, default: 0] += 1
                            let pixels = Self.canvas(before, window: window, keyboardUp: keyboardUp).data
                            #expect(canvas.data != nil && canvas.data == pixels, "\(here): f37fab7's row fitted, and the HUD draws something else")
                            if canvas.data != nil && canvas.data == pixels { same[size, default: 0] += 1 }
                        }
                        cells += 1
                    }
                }
            }
        }
        #expect(cells == 3 * 16 * 20 * 2)
        // Controls: the comparison ran, at every size, on cells of both kinds; and the whole-value
        // check ran on compressed rungs, not only on today's rows.
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility1] {
            #expect((fitted[size] ?? 0) > 0 && (fitted[size] ?? 0) < 16 * 20 * 2, "\(size): f37fab7's row fitted in \(fitted[size] ?? 0) cells")
            let rungs = (taken[size] ?? [:]).filter { if case .compressed = $0.key { true } else { false } }.values.reduce(0, +)
            #expect(rungs > 0, "\(size): no cell drew a compressed rung, so no rung's values were checked")
        }
        #expect(todayTaken > 0)
        print("V135HUDRowTests sweep: \(cells) cells; f37fab7's row fitted and the HUD drew it at L \(same[.large] ?? 0)/\(fitted[.large] ?? 0), "
              + "xxxL \(same[.xxxLarge] ?? 0)/\(fitted[.xxxLarge] ?? 0), AX1 \(same[.accessibility1] ?? 0)/\(fitted[.accessibility1] ?? 0); "
              + "f37fab7 squeezed its second row into \(squeezed.count) AX1 cells: \(squeezed)")
        print("V135HUDRowTests sweep: every value whole at L \(whole[.large] ?? 0), xxxL \(whole[.xxxLarge] ?? 0), AX1 \(whole[.accessibility1] ?? 0) of 640 cells; "
              + "today's row one line and taken in \(todayTaken) cells; children taken: "
              + [DynamicTypeSize.large, .xxxLarge, .accessibility1].map { size in
                  "\(size) " + RideHUDRungs.offered(narrow: false, size).map { "\((taken[size] ?? [:])[$0] ?? 0)" }.joined(separator: "/")
              }.joined(separator: ", "))
    }

    /// Each pill's width drawn whole — today's row, `row(fallback: false)`, alone in a 2,400pt window,
    /// where nothing wraps, shrinks or is proposed less than it needs — by pill, and the pause button's
    /// under nil. Every child of the body draws a subset of these pills (at the accessibility sizes the
    /// first row has every pill the others draw), and a pill's drawn width does not depend on its
    /// row. Empty if the row did not draw one run per pill.
    @MainActor
    static func wholeWidths(_ bar: HUDBar, _ size: DynamicTypeSize, scoreIsTheRide: Bool) -> [Pill?: CGFloat] {
        let runs = Self.drawn(Self.sized(Self.child(bar, .today(fallback: false)), size), window: 2_400, keyboardUp: false)
        let pills: [Pill?] = Self.pills(.today(fallback: false), narrow: false, size, scoreIsTheRide: scoreIsTheRide).map(Optional.some) + [nil]
        guard runs.count == pills.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(pills, runs.map { $0.right - $0.left }))
    }

    /// The runs of columns holding ink, as `segments`, with each run's top and bottom ink row — in
    /// points, relative to the HUD's frame in a `canvas`.
    static func inked(_ canvas: (data: Data?, rep: NSBitmapImageRep?, pad: CGFloat))
        -> [(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat)] {
        guard let rep = canvas.rep, let bytes = rep.bitmapData else { return [] }
        let perRow = rep.bytesPerRow, height = rep.pixelsHigh, width = rep.pixelsWide, samples = rep.samplesPerPixel
        let scale = CGFloat(width) / rep.size.width
        let background = (bytes[0], bytes[1], bytes[2])
        var top = [Int](repeating: Int.max, count: width), bottom = [Int](repeating: -1, count: width)
        for y in 0..<height {
            let row = bytes + y * perRow
            for x in 0..<width {
                let o = x * samples
                if row[o] != background.0 || row[o + 1] != background.1 || row[o + 2] != background.2 {
                    top[x] = min(top[x], y)
                    bottom[x] = y
                }
            }
        }
        var out: [(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat)] = []
        var x = 0
        while x < width {
            guard bottom[x] >= 0 else { x += 1; continue }
            var end = x, high = top[x], low = bottom[x]
            while end + 1 < width, bottom[end + 1] >= 0 { end += 1; high = min(high, top[end]); low = max(low, bottom[end]) }
            out.append((left: CGFloat(x) / scale - margin - canvas.pad, right: CGFloat(end + 1) / scale - margin - canvas.pad,
                        top: CGFloat(high) / scale - 8, bottom: CGFloat(low + 1) / scale - 8))
            x = end + 1
        }
        return out
    }

    /// A ride stepped key by key — a 150-word list with a wrong key every seventh word and two in a row
    /// every 23rd, and a 120-word Time Attack the same way, the speed swinging between about 30 and 115
    /// wpm so it crosses 99/100 — in the windows where the ladder moves (680, 716, 810, 820 and 834pt,
    /// keyboard up and down) at the default size. The child `ViewThatFits` takes is the first whose
    /// ideal width fits (below the accessibility sizes each child can be hosted alone; checked against
    /// the drawn row at every change). It never moves back up once it has left today's row, except
    /// from rung 0 back to today's row, the same pills. **Every step between those two is measured**,
    /// with the values held, in both axes: rung 0 against today's row drawn alone where that row is
    /// one line — every edge of every pill's ink, left, right, top and bottom, and the row's height —
    /// and otherwise across against today's placement with room and up and down against today's row
    /// drawn with room. Bound: 0.5pt, the instrument's pixel at 2x. Measured: 0.0 across and 0.0 up
    /// or down at all 61 such steps, 27 of them against today's row alone (byte-identical in all 27;
    /// every step into rung 0 falls where today's row would wrap). The count of those steps per ride
    /// and window is printed; it is these rides' count, not a bound — it grows with a ride's length.
    /// Mutations, each red here: `OneLineFit` removed from the body with the table (20 of 82 steps
    /// then move a pill 14pt; with the body alone, the drawn row is no longer the predicted child); the
    /// compressed rungs' reserves removed (`RideHUDRungs.accuracyReserve = []`); the speed reserve two
    /// digits; `HUDRowLayout` placing its items top-aligned (`y: bounds.minY`, `.topLeading`: 6pt up or
    /// down at all 61 steps, 0.0pt across, which only the vertical bound sees).
    @MainActor
    @Test("stepped key by key, the ladder only moves down after today's row, and the one step back moves nothing")
    func steppedRidesOnlyMoveDown() {
        let windows: [CGFloat] = [680, 716, 810, 820, 834]
        let rows = RideHUDRungs.offered(narrow: false, .large)
        var backToToday = 0, toRungZero = 0, changes = 0, largestShift: CGFloat = 0, largestLift: CGFloat = 0, largestStep: CGFloat = 0
        var switches: [String: Int] = [:], moved = 0, oneLineSteps = 0, identical = 0
        for (name, mode, count, words) in [("150-word list", GameMode.journey, 150, 150), ("Time Attack", .timeAttack, 300, 120)] {
            // `lag` takes every key one step after `session`, so at a change both states can be drawn.
            let session = GameSession(words: Self.words(count), config: .init(newWordCount: count, reviewWordCount: 0, mode: mode))
            let lag = GameSession(words: Self.words(count), config: .init(newWordCount: count, reviewWordCount: 0, mode: mode))
            var previous: [String: Int] = [:]
            var step = 0, lagWPM = 0.0, pending: Character?
            func key(_ character: Character, word: Int) {
                if let pending { lag.input(pending) }
                session.input(character)
                pending = character
                let wpm: Double = word < 2 ? 0 : (45 + 15 * sin(Double(step) / 7)).rounded() + (step % 50 < 25 ? 0 : 55)
                let hud = HUDBar(session: session, language: "en", wpm: wpm, onPause: {})
                let ideals = rows.map { Self.ideal(Self.child(hud, $0)).width }
                let line = Self.ideal(Self.child(hud, rows[0])).height
                for window in windows {
                    for keyboardUp in [false, true] {
                        let width = window - 2 * GameView.padding(phone: false, keyboardUp: keyboardUp)
                        let place = "\(name) \(Int(window))pt keyboard \(keyboardUp ? "up" : "down")"
                        let child = ideals.firstIndex { $0 <= width } ?? rows.count - 1
                        defer { previous[place] = child }
                        guard let before = previous[place], before != child else { continue }
                        changes += 1
                        #expect(child > before || (before == 1 && child == 0),
                                "\(place), key \(step) (\(session.wordsCompleted) words): \(rows[before]) back up to \(rows[child])")
                        let nowCanvas = Self.canvas(hud, window: window, keyboardUp: keyboardUp)
                        let now = Self.runs(nowCanvas)
                        #expect(now.map { [$0.left, $0.right] } == Self.drawn(Self.child(hud, rows[child]), window: window, keyboardUp: keyboardUp).map { [$0.left, $0.right] },
                                "\(place), key \(step): the row drawn is not \(rows[child])")
                        guard (before, child) == (1, 0) || (before, child) == (0, 1) else { continue }
                        switches[place, default: 0] += 1
                        if child == 0 { backToToday += 1 } else { toRungZero += 1 }
                        // What the switch itself moves, with the values held, in both axes: rung 0
                        // against today's row drawn alone where that row is one line inside the width
                        // (every edge of every pill's ink, and the row's height); where it is not (it
                        // would wrap, as 1.34 did), across against where today's row puts the same
                        // pills with room — the level, score and combo from the left, the rest from the
                        // right, 14pt apart — which rung 0 keeps until its centre gap reaches 6pt, and
                        // up and down against today's row drawn with room.
                        let rungZeroCanvas = child == 1 ? nowCanvas
                            : Self.canvas(Self.child(hud, .compressed(rung: 0)), window: window, keyboardUp: keyboardUp)
                        let rungZero = Self.inked(rungZeroCanvas)
                        #expect(rungZero.count == 8, "\(place), key \(step): rung 0 drew \(rungZero.count) runs")
                        guard rungZero.count == 8 else { continue }
                        let todayAlone = Self.child(hud, .today(fallback: false))
                        let todayNatural = Self.natural(todayAlone, width)
                        let rungZeroHeight = Self.natural(Self.child(hud, .compressed(rung: 0)), width).height
                        var shift: CGFloat = 0, lift = abs(rungZeroHeight - line)
                        if todayNatural.height <= line + 0.5 && todayNatural.width <= width + 0.01 {
                            oneLineSteps += 1
                            let todayCanvas = Self.canvas(todayAlone, window: window, keyboardUp: keyboardUp)
                            let today = Self.inked(todayCanvas)
                            #expect(today.count == 8, "\(place), key \(step): today's row drew \(today.count) runs")
                            for (a, b) in zip(rungZero, today) {
                                shift = max(shift, abs(a.left - b.left), abs(a.right - b.right))
                                lift = max(lift, abs(a.top - b.top), abs(a.bottom - b.bottom))
                            }
                            lift = max(lift, abs(rungZeroHeight - todayNatural.height))
                            if todayCanvas.data != nil && todayCanvas.data == rungZeroCanvas.data { identical += 1 }
                        } else {
                            #expect(child == 1, "\(place), key \(step): back to today's row where it is not one line")
                            if child == 0 {
                                for (a, b) in zip(rungZero, now) { shift = max(shift, abs(a.left - b.left), abs(a.right - b.right)) }
                            }
                            var placed: [CGFloat] = []
                            var x: CGFloat = 0
                            for run in rungZero.prefix(3) { placed.append(x); x += run.right - run.left + 14 }
                            var trailing: [CGFloat] = []
                            x = width
                            for run in rungZero.suffix(5).reversed() { x -= run.right - run.left; trailing.insert(x, at: 0); x -= 14 }
                            placed += trailing
                            for (run, left) in zip(rungZero, placed) { shift = max(shift, abs(run.left - left)) }
                            let roomy = Self.inked(Self.canvas(todayAlone, window: 1_600, keyboardUp: keyboardUp))
                            #expect(roomy.count == 8, "\(place), key \(step): today's row with room drew \(roomy.count) runs")
                            for (a, b) in zip(rungZero, roomy) { lift = max(lift, abs(a.top - b.top), abs(a.bottom - b.bottom)) }
                        }
                        largestShift = max(largestShift, shift)
                        largestLift = max(largestLift, lift)
                        if shift > 0.5 || lift > 0.5 { moved += 1 }
                        // For the record: how far the pills moved between the two keys, the values' change included.
                        let then = Self.drawn(HUDBar(session: lag, language: "en", wpm: lagWPM, onPause: {}), window: window, keyboardUp: keyboardUp)
                        if then.count == now.count {
                            for (a, b) in zip(then, now) { largestStep = max(largestStep, min(abs(a.left - b.left), abs(a.right - b.right))) }
                        }
                    }
                }
                lagWPM = wpm
                step += 1
            }
            for index in 0..<words {
                if index % 7 == 3 { key("x", word: index) }
                if index % 23 == 11 { key("q", word: index); key("q", word: index) }
                for character in "mizu" { key(character, word: index) }
            }
            #expect(session.wordsCompleted == words, "\(name): the ride was not stepped through (\(session.wordsCompleted))")
        }
        #expect(changes > 0, "control: no ride changed rows in these windows, so nothing was checked")
        #expect(backToToday > 0, "control: no ride stepped back to today's row, so the shift was never measured")
        #expect(oneLineSteps > 0, "control: no step between the two was compared with today's row drawn alone")
        #expect(largestShift <= 0.5, "rung 0 put a pill \(largestShift)pt across from where today's row puts it, at a step between the two")
        #expect(largestLift <= 0.5, "rung 0 put a pill \(largestLift)pt up or down from where today's row puts it, or the row changed height, at a step between the two")
        print("V135HUDRowTests stepped: \(changes) row changes, \(toRungZero) to rung 0 and \(backToToday) back to today's row; "
              + "rung 0 at most \(largestShift)pt across and \(largestLift)pt up or down from today's placement, more than 0.5pt at \(moved) of those steps; "
              + "\(oneLineSteps) steps compared with today's row alone (\(identical) byte-identical), the rest with today's placement with room; "
              + "pills moved at most \(largestStep)pt over those keys, the values' change included")
        for (place, count) in switches.sorted(by: { $0.key < $1.key }) { print("V135HUDRowTests switches: \(place): \(count)") }
    }

    /// **An iPad at AX1: a ride that mixes JLPT levels moves only down its rows**, stepped key by key
    /// in every window from 320 to 1024pt, every 2pt, keyboard up and down. The review of step 4b
    /// found the iPad's second accessibility-size row, which reserved no level label, bordering the
    /// last rung, which sheds the level: the child followed the current word's label. Measured on
    /// these rides before the fix: a 150-word list of N4, N2, N5 and N1 words changed rows 92 times in
    /// a 330pt window with the keyboard up, 46 of them back up — the level capsule blinking in and out
    /// word by word — and moved back up in 10 of the 706 window × keyboard cells before its finishing
    /// key (328–330, 346–348pt up; 346–348, 364–366, 382–384pt down); a 500-word list mixing N5, N3
    /// and N1, 268 times at 346pt up, 134 back up; a 20-word journey of N5 and N1 words in 4 cells.
    /// And every ride that finishes, one level or several, moved back up at its finishing key, in
    /// 13–32 cells each (its level label is empty then; Time Attack does not finish here). Now that
    /// row reserves the ride's labels (`RideHUDLayout.levelReserve`), so its ideal width only grows,
    /// and the finished ride's empty label keeps the width it reserved. The child is the first
    /// `RideHUDRungs.offered` child whose ideal width fits (at a sample of the changes, one window in
    /// ten, checked against the drawn row). Asserted: no move back up anywhere, the finishing key
    /// included (its level label is empty, and the reserve holds its width). Controls: the rides do
    /// change rows in these windows, and the labels they mix differ in width. The one-level ride is
    /// the control that the reserve changes nothing where a ride has one label. Mutation, red here:
    /// `levelReserve`'s guard back to `!fallback` (before this fix — the counts the commit message
    /// gives per ride and window).
    @MainActor
    @Test("at AX1 on an iPad, a ride mixing levels moves only down its rows, word after word")
    func axMixedLevelRidesOnlyMoveDown() {
        let size = DynamicTypeSize.accessibility1
        let rows = RideHUDRungs.offered(narrow: false, size)
        let windows = stride(from: CGFloat(320), through: 1024, by: 2).map { $0 }
        let capsule = { (label: String) in
            Self.ideal(Self.sized(Text(label).scaledSystemFont(14, weight: .heavy, design: .rounded), size)).width
        }
        #expect(capsule("N5") - capsule("N1") > 1, "control: N1 and N5 are as wide as each other, so a mixed ride tests nothing")
        var ups = 0, changes = 0, checked = 0
        var perRide: [String] = []
        let rides: [(name: String, mode: GameMode, count: Int, words: Int, levels: [JLPTLevel])] = [
            ("150-word list N4 N2 N5 N1", .journey, 150, 150, [.n4, .n2, .n5, .n1]),
            ("150-word list N1 N5", .journey, 150, 150, [.n1, .n5]),
            ("20-word journey N5 N4", .journey, 20, 20, [.n5, .n4]),
            ("120-word Time Attack, all levels", .timeAttack, 300, 120, [.n5, .n4, .n3, .n2, .n1]),
            ("150-word list N5", .journey, 150, 150, [.n5]),
        ]
        for ride in rides {
            let session = GameSession(words: Self.words(ride.count, levels: ride.levels),
                                      config: .init(newWordCount: ride.count, reviewWordCount: 0, mode: ride.mode))
            var previous: [Int: Int] = [:]
            var rideUps = 0, rideChanges = 0, cellsChanged = Set<Int>()
            var step = 0
            func key(_ character: Character) {
                session.input(character)
                let hud = HUDBar(session: session, language: "en", wpm: 42, onPause: {})
                let ideals = rows.map { Self.ideal(Self.sized(Self.child(hud, $0), size)).width }
                for (index, window) in windows.enumerated() {
                    for keyboardUp in [false, true] {
                        let width = window - 2 * GameView.padding(phone: false, keyboardUp: keyboardUp)
                        let cell = index * 2 + (keyboardUp ? 1 : 0)
                        let child = ideals.firstIndex { $0 <= width } ?? rows.count - 1
                        defer { previous[cell] = child }
                        guard let before = previous[cell], before != child else { continue }
                        rideChanges += 1
                        cellsChanged.insert(cell)
                        let place = "\(ride.name) \(Int(window))pt keyboard \(keyboardUp ? "up" : "down")"
                        if child < before {
                            rideUps += 1
                            Issue.record("\(place), key \(step) (\(session.wordsCompleted) words, \(session.currentLevelLabel.isEmpty ? "finished" : session.currentLevelLabel)): \(rows[before]) back up to \(rows[child])")
                        }
                        if index % 10 == 0 {
                            checked += 1
                            let drawn = Self.drawn(Self.sized(hud, size), window: window, keyboardUp: keyboardUp).map { [$0.left, $0.right] }
                            let predicted = Self.drawn(Self.sized(Self.child(hud, rows[child]), size), window: window, keyboardUp: keyboardUp).map { [$0.left, $0.right] }
                            #expect(drawn == predicted, "\(place), key \(step): the row drawn is not \(rows[child])")
                        }
                    }
                }
                step += 1
            }
            for index in 0..<ride.words {
                if index % 7 == 3 { key("x") }
                if index % 23 == 11 { key("q"); key("q") }
                for character in "mizu" { key(character) }
            }
            #expect(session.wordsCompleted == ride.words, "\(ride.name): the ride was not stepped through (\(session.wordsCompleted))")
            ups += rideUps
            changes += rideChanges
            perRide.append("\(ride.name): \(rideChanges) changes in \(cellsChanged.count) of \(windows.count * 2) cells, \(rideUps) back up")
        }
        #expect(changes > 0, "control: no ride changed rows in these windows, so nothing was checked")
        #expect(checked > 0)
        print("V135HUDRowTests AX1 stepped: \(changes) row changes, \(ups) back up, \(checked) checked against the drawn row; " + perRide.joined(separator: "; "))
    }

    /// **`OneLineFit` decides from the row's own one line, not from the height it is proposed.** The
    /// ride screen's `VStack` proposes the HUD a share of its height, and when `OneLineFit` measured
    /// the row at that height, a short proposal inside the wrap band let today's row lay out one line
    /// tall by truncating a value — "9980…" — and be taken (review of step 4b). Here the HUD is framed
    /// at widths inside the band (today's row's ideal width +1pt and +3pt, where it wraps when tall —
    /// a control) and at heights from a line to under two, in the two states with the widest band;
    /// it must draw rung 0, byte for byte, and today's row alone there must not (the control that the
    /// frame is short enough to truncate). Mutation, red here: `OneLineFit` measuring at
    /// `height: proposal.height` again.
    @MainActor
    @Test("OneLineFit ignores the height it is proposed: a short HUD in the wrap band draws rung 0, not a truncated row")
    func oneLineFitIgnoresTheProposedHeight() {
        var cells = 0
        for size in [DynamicTypeSize.large, .xxxLarge] {
            for name in ["list500-late", "list-late"] {
                guard let state = Self.states.first(where: { $0.name == name }) else { Issue.record("no state \(name)"); continue }
                let session = Self.session(state.mode, count: state.count, done: state.done, misses: state.misses, levels: state.levels)
                let bar = HUDBar(session: session, language: "en", wpm: state.wpm, onPause: {})
                let today = Self.sized(Self.child(bar, .today(fallback: false)), size)
                let rungZero = Self.sized(Self.child(bar, .compressed(rung: 0)), size)
                let ideal = Self.ideal(today)
                for extra in [1.0, 3.0] as [CGFloat] {
                    let width = ideal.width + extra
                    let wrapped = Self.natural(today, width).height
                    guard wrapped > ideal.height + 0.5 else { continue }   // no band this wide in this state
                    for height in stride(from: ideal.height + 1, to: wrapped - 1, by: 4) {
                        let here = "\(size) \(name) \(width)×\(height)"
                        let hud = Self.framed(Self.sized(bar, size), width: width, height: height)
                        #expect(hud != nil && hud == Self.framed(rungZero, width: width, height: height), "\(here): the HUD does not draw rung 0")
                        #expect(Self.framed(today, width: width, height: height) != hud,
                                "control, \(here): today's row alone draws rung 0's pixels, so the frame does not test the height")
                        cells += 1
                    }
                }
            }
        }
        #expect(cells >= 8, "control: only \(cells) short cells inside a wrap band were drawn")
        print("V135HUDRowTests short heights: \(cells) cells in the wrap band, rung 0 in all")
    }

    /// `view` framed `width` × `height`, on a canvas 20pt taller: its pixels.
    @MainActor
    static func framed<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> Data? {
        render(ZStack(alignment: .topLeading) { Color(white: 0.2); view.frame(width: width, height: height) }
            .frame(width: width, height: height + 20, alignment: .topLeading), CGSize(width: width, height: height + 20)).data
    }

    /// **Today's row is offered from the first width at which it is one line, to within 0.25pt.**
    /// `OneLineFit`'s steps and resolution are written out, and in all 16 states at the default size
    /// and xxxLarge today's row is laid out at every quarter point from its ideal width up to what
    /// `OneLineFit` answers: it must wrap at every one below the answer and be one line at it. So the
    /// band where rung 0 stands in for today's row is exactly the band where today's row wraps.
    /// Measured: the widest band 4.75pt at L and 9.5pt at xxxL (a late 500-word list), every other
    /// state 0–1.5pt; bound 9.75pt. Mutations, each red here: `steps` `[8, 16, 32, 64]`; `[64]`;
    /// no halving between steps (`resolution` 64).
    @MainActor
    @Test("OneLineFit answers the first width at which today's row is one line")
    func oneLineFitAnswersTheFirstOneLineWidth() {
        #expect(OneLineFit.steps == [0, 1, 2, 4, 8, 16, 32, 64])
        #expect(OneLineFit.resolution == 0.25)
        var widest: [DynamicTypeSize: CGFloat] = [:]
        for size in [DynamicTypeSize.large, .xxxLarge] {
            for state in Self.states {
                let session = Self.session(state.mode, count: state.count, done: state.done, misses: state.misses, levels: state.levels)
                let bar = HUDBar(session: session, language: "en", wpm: state.wpm, onPause: {})
                let today = Self.sized(Self.child(bar, .today(fallback: false)), size)
                let ideal = Self.ideal(today)
                let answer = Self.ideal(Self.sized(Self.child(bar, .todayOneLine), size)).width
                func oneLine(_ width: CGFloat) -> Bool {
                    let laid = Self.natural(today, width)
                    return laid.height <= ideal.height + 0.5 && laid.width <= width + 0.01
                }
                let band = answer - ideal.width
                widest[size] = max(widest[size] ?? 0, band)
                #expect(band >= 0 && band <= 9.75, "\(size) \(state.name): OneLineFit answers \(band)pt above the row's ideal width")
                #expect(oneLine(answer), "\(size) \(state.name): today's row is not one line at OneLineFit's answer, \(answer)")
                var width = ideal.width
                // A quarter point written out, not read from `OneLineFit`: the scan must not step by
                // the constant it checks.
                while width < answer - 0.001 {
                    #expect(!oneLine(width), "\(size) \(state.name): today's row is one line at \(width), below OneLineFit's answer \(answer)")
                    width += 0.25
                }
            }
        }
        // Control: a band exists at both sizes, so the halving is exercised.
        #expect((widest[.large] ?? 0) > 2 && (widest[.xxxLarge] ?? 0) > 2, "control: no state has a wrap band wider than 2pt: \(widest)")
        print("V135HUDRowTests OneLineFit: the widest band \(widest[.large] ?? -1)pt at L, \(widest[.xxxLarge] ?? -1)pt at xxxL")
    }

    /// **The one measured exception to "the row stays in its frame".** A grandfathered default list
    /// over the 500-word cap (`WordListStore.seedDefaultIDs`) rides with a four-digit count, and at AX1
    /// its last rung is the progress pill ("1199/1200", every value whole) and the pause button:
    /// 268pt, which nothing in the design can narrow — a queue ride never sheds its count, no value is
    /// cut or wrapped, the pause button is 44pt, the gap is at its 6pt minimum. So in an iPad window
    /// narrower than 332pt with the keyboard down (a 256pt row at 320pt) the pill starts up to 12pt
    /// left of the frame, inside `GameView`'s 32pt margin, and the pause button stays whole and in the
    /// frame (`HUDRowLayout` keeps the right end). Written out here: the bleed at every window from
    /// 320 to 344pt, both keyboards, is `max(0, 332 − window)` with the keyboard down and 0 up; the
    /// vocabulary (fewer than 10,000 words) caps a count at four digits, and the tabular digits make
    /// "1999/2000" exactly as wide as "1199/1200". At the default size and xxxLarge the same rides fit.
    @MainActor
    @Test("over-cap lists at AX1: the last rung reaches at most 12pt into the margin, only below 332pt with the keyboard down")
    func overCapListsAtAX1() {
        let long = Self.session(.journey, count: 1_200, done: 1_199, misses: 5)
        let longer = Self.session(.journey, count: 2_000, done: 1_999, misses: 5)
        var bleeds: [String] = []
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility1] {
            let bar = HUDBar(session: long, language: "en", wpm: 60, onPause: {})
            let hud = Self.sized(bar, size)
            if size.isAccessibilitySize {
                let rung = Self.ideal(Self.sized(Self.child(bar, .compressed(rung: 6)), size)).width
                let rungLonger = Self.ideal(Self.sized(Self.child(HUDBar(session: longer, language: "en", wpm: 60, onPause: {}), .compressed(rung: 6)), size)).width
                #expect(abs(rung - 268) < 0.6 && rung == rungLonger, "the last rung is \(rung)pt at 1199/1200 and \(rungLonger)pt at 1999/2000")
            }
            for window in stride(from: CGFloat(320), through: 344, by: 2).map({ $0 }) + [375, 438] {
                for keyboardUp in [false, true] {
                    let width = window - 2 * GameView.padding(phone: false, keyboardUp: keyboardUp)
                    let here = "\(size) \(Int(window))pt keyboard \(keyboardUp ? "up" : "down")"
                    let runs = Self.drawn(hud, window: window, keyboardUp: keyboardUp)
                    let first = runs.first?.left ?? -100, last = runs.last?.right ?? .infinity
                    let pause = runs.last.map { $0.right - $0.left } ?? 0
                    #expect(abs(pause - 44) < 0.6 && last <= width + 0.01, "\(here): the pause button is \(pause)pt, ending at \(last) in \(width)")
                    let expected = size.isAccessibilitySize && !keyboardUp ? max(0, 332 - window) : 0
                    #expect(abs(max(0, -first) - expected) < 0.6, "\(here): the row starts at \(first), expected \(-expected)")
                    if first < -0.01 { bleeds.append("\(here): \(-first)pt") }
                }
            }
        }
        #expect(!bleeds.isEmpty, "control: no window drew the over-cap row into the margin, so the exception is not where this says")
        print("V135HUDRowTests over-cap: \(bleeds.count) cells reach into the margin: \(bleeds)")
    }

    /// One child of `HUDBar.body`, hosted on its own (`HUDChild`).
    @MainActor
    static func child(_ hud: HUDBar, _ row: RideHUDRungs.Row) -> AnyView {
        AnyView(HUDChild(bar: hud, row: row))
    }
    #endif
}

#if canImport(AppKit)
/// **Test-only**, so a view that stores a `HUDBar` gets the HUD's own `@Environment` installed.
/// `row(fallback:)` and `compressed(rung:)` read `typeSize`; called on a `HUDBar` that is not itself
/// in a view hierarchy they read the default size (`.large`) whatever the environment says —
/// measured: at AX1 a journey's `row(fallback: false)` built that way laid out 889pt with the
/// distance, accuracy and speed pills, and 394pt without them once hosted like this. A stored
/// property that is a `DynamicProperty` has its own dynamic properties installed with its owner's.
extension HUDBar: DynamicProperty {}

/// One child of `HUDBar.body`, built as the body builds it, in a hierarchy of its own.
struct HUDChild: View {
    let bar: HUDBar
    let row: RideHUDRungs.Row
    var body: some View {
        switch row {
        case .today(let fallback): AnyView(bar.row(fallback: fallback))
        case .todayOneLine: AnyView(OneLineFit { bar.row(fallback: false) })
        case .compressed(let rung): AnyView(bar.compressed(rung: rung))
        }
    }
}

/// f37fab7's `HUDBar.body` on an iPad or a Mac, over this HUD's rows: `row(fallback: false)` alone
/// below the accessibility sizes, `ViewThatFits` over it and `row(fallback: true)` at them (the
/// v1.33 round 3 body, which f37fab7 carried; `todaysRowIsVerbatim` holds the rows to f37fab7's).
struct F37fab7HUD: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let bar: HUDBar
    var body: some View {
        if typeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                bar.row(fallback: false)
                bar.row(fallback: true)
            }
        } else {
            bar.row(fallback: false)
        }
    }
}
#endif
