import Testing
import Foundation
import JournalKit
import ReviewKit
import VocabKit
@testable import NihongoRideApp

/// v1.34 §B1 — "Tomorrow, said out loud": the results screen states the streak and what comes due.
///
/// Four claims, held apart because each fails differently. The copy matrix, row by row, every
/// expected string written out by hand (mutating the streak threshold to ≥ 3 turns the 2-day rows
/// red). The wiring from a real ride through `finishGame` to `model.tomorrowLine(zh:)`, with the
/// words-due count computed by THIS file from the raw `SRSCard`s and never by `dueForecast` (memory:
/// a test that grades itself). The view — a model-level test passes while the screen draws nothing
/// (v1.26 §D), so the shipped `ResultsView` source is read with comments stripped. And the simulator
/// hook, pinned to the gate that keeps the writing harness off a real device.
@MainActor
@Suite("v1.34 §B1: the results screen says what comes tomorrow")
struct V134B1TomorrowLineTests {

    // MARK: - The copy matrix

    struct Row: Sendable, CustomTestStringConvertible {
        let streak: Int
        let words: Int
        let forms: Int
        let en: String
        let zh: String
        var testDescription: String { "streak \(streak) · \(words) words · \(forms) forms" }
    }

    /// PLAN-V1.34 §B1's table, plus the rows it names in prose: the boundary (2 days is a streak,
    /// 1 is not, 0 — a chain that broke — is not), the English singulars, and a count past 99.
    nonisolated static let matrix: [Row] = [
        Row(streak: 3, words: 12, forms: 4,
            en: "3-day streak · 12 words and 4 forms due tomorrow",
            zh: "连续 3 天 · 明天到期 12 个词、4 个变形"),
        Row(streak: 3, words: 12, forms: 0,
            en: "3-day streak · 12 words due tomorrow",
            zh: "连续 3 天 · 明天到期 12 个词"),
        Row(streak: 3, words: 0, forms: 1,
            en: "3-day streak · 1 form due tomorrow",
            zh: "连续 3 天 · 明天到期 1 个变形"),
        Row(streak: 3, words: 0, forms: 0,
            en: "3-day streak · nothing due tomorrow",
            zh: "连续 3 天 · 明天没有到期的复习"),
        Row(streak: 1, words: 12, forms: 0,
            en: "12 words due tomorrow",
            zh: "明天到期 12 个词"),
        Row(streak: 1, words: 12, forms: 4,
            en: "12 words and 4 forms due tomorrow",
            zh: "明天到期 12 个词、4 个变形"),
        Row(streak: 1, words: 0, forms: 1,
            en: "1 form due tomorrow",
            zh: "明天到期 1 个变形"),
        Row(streak: 1, words: 0, forms: 0,
            en: "nothing due tomorrow",
            zh: "明天没有到期的复习"),
        Row(streak: 0, words: 5, forms: 0,
            en: "5 words due tomorrow",
            zh: "明天到期 5 个词"),
        Row(streak: 2, words: 1, forms: 1,
            en: "2-day streak · 1 word and 1 form due tomorrow",
            zh: "连续 2 天 · 明天到期 1 个词、1 个变形"),
        Row(streak: 2, words: 1, forms: 0,
            en: "2-day streak · 1 word due tomorrow",
            zh: "连续 2 天 · 明天到期 1 个词"),
        Row(streak: 2, words: 0, forms: 2,
            en: "2-day streak · 2 forms due tomorrow",
            zh: "连续 2 天 · 明天到期 2 个变形"),
        Row(streak: 30, words: 100, forms: 0,
            en: "30-day streak · 100 words due tomorrow",
            zh: "连续 30 天 · 明天到期 100 个词"),
    ]

    @Test("the copy matrix, row by row, in both languages", arguments: matrix)
    func matrixRow(_ row: Row) {
        #expect(TomorrowLine.compose(streakDays: row.streak, wordsDue: row.words,
                                     formsDue: row.forms, zh: false) == row.en)
        #expect(TomorrowLine.compose(streakDays: row.streak, wordsDue: row.words,
                                     formsDue: row.forms, zh: true) == row.zh)
    }

    /// "1-day streak" is a rider on their first day, and the plan says it is never shown. Held over
    /// every due combination, because a prefix that leaked on only the "nothing due" row would
    /// pass the table above.
    @Test("a one-day or broken streak never becomes a prefix, whatever is due")
    func noOneDayStreak() {
        for streak in [0, 1] {
            for words in [0, 1, 12] {
                for forms in [0, 1, 4] {
                    let en = TomorrowLine.compose(streakDays: streak, wordsDue: words, formsDue: forms, zh: false)
                    let zh = TomorrowLine.compose(streakDays: streak, wordsDue: words, formsDue: forms, zh: true)
                    #expect(!en.contains("streak") && !en.contains("-day") && !en.contains(" · "), Comment(rawValue: en))
                    #expect(!zh.contains("连续") && !zh.contains(" · "), Comment(rawValue: zh))
                }
            }
        }
    }

    // MARK: - The wiring: a real ride through finishGame

    static func vocab() -> VocabStore {
        VocabStore(entries: [AppModelTests.entry("a", "水", "みず"),
                             AppModelTests.entry("b", "火", "ひ"),
                             AppModelTests.entry("c", "山", "やま")])
    }

    /// A one-minute ride at noon, `daysAgo` days back. Noon, deliberately: `riddenDays` also counts
    /// the day a ride STARTED on, and `ReviewPromptWiringTests.record` subtracts whole days from
    /// `Date()`, so a suite run a minute past midnight would put that ride's start on the day
    /// before and lengthen the chain by one. The streak this file expects must not depend on the
    /// clock the suite happens to run at.
    static func noonRide(daysAgo: Int) -> RideRecord {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        return RideRecord(date: day.addingTimeInterval(12 * 3600), mode: "journey", level: "n5",
                          score: 100, wpm: 30, accuracy: 1, wordsCompleted: 3, lapsed: 0,
                          distanceMeters: 500, duration: 60)
    }

    /// The count the line must show, read from the raw cards: those whose `dueDate` falls on
    /// tomorrow's calendar day. Calendar arithmetic here and not `dueForecast` — the read the line
    /// is wired to is exactly the thing this number must be independent of.
    static func cardsDueTomorrow(_ store: ReviewStore) -> Int {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        return store.cards.values.filter { cal.isDate($0.dueDate, inSameDayAs: tomorrow) }.count
    }

    /// Yesterday and the day before, seeded through the journal's own writer, then today's ride:
    /// three consecutive days. The words-due count is the three ridden words — SM-2's first success
    /// is a one-day interval — and the arrangement is asserted before the line is read, so a ride
    /// that reviewed nothing cannot agree with "nothing due" for the wrong reason.
    @Test("a third consecutive day, ridden cleanly, reads the streak and the cards due tomorrow")
    func thirdDayRide() throws {
        let model = ReviewPromptWiringTests.seededJournal([Self.noonRide(daysAgo: 2),
                                                           Self.noonRide(daysAgo: 1)])
        ReviewPromptWiringTests.rideCleanly(model)
        #expect(model.journal.count == 3, "today's ride was not logged — nothing below measures the line")
        let due = Self.cardsDueTomorrow(model.reviewStore)
        #expect(due == 3, "three words ridden for the first time should all be due tomorrow; raw cards say \(due)")

        let line = try #require(model.tomorrowLine(zh: false))
        #expect(line.hasPrefix("3-day streak · "), Comment(rawValue: line))
        #expect(line == "3-day streak · \(due) words due tomorrow", Comment(rawValue: line))
        #expect(model.tomorrowLine(zh: true) == "连续 3 天 · 明天到期 \(due) 个词")
    }

    @Test("a rider with no prior rides gets the due half alone — no streak, never '1-day'")
    func firstDayRide() throws {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        ReviewPromptWiringTests.rideCleanly(model)
        let due = Self.cardsDueTomorrow(model.reviewStore)
        #expect(due == 3, "three words ridden for the first time should all be due tomorrow; raw cards say \(due)")

        let line = try #require(model.tomorrowLine(zh: false))
        #expect(line == "\(due) words due tomorrow", Comment(rawValue: line))
        #expect(!line.contains("streak") && !line.contains("1-day"), Comment(rawValue: line))
        #expect(model.tomorrowLine(zh: true) == "明天到期 \(due) 个词")
    }

    /// The same rule the headline and `logRun` apply. Seeded with a streak so that, were the guard
    /// missing, the line would have something to say — "2-day streak · nothing due tomorrow" — and
    /// nil is the guard's doing and nothing else's.
    @Test("a run that typed nothing has no tomorrow line")
    func typedNothingHasNoLine() throws {
        let model = ReviewPromptWiringTests.seededJournal([Self.noonRide(daysAgo: 2),
                                                           Self.noonRide(daysAgo: 1)])
        model.startGame()
        model.finishGame()
        #expect(model.screen == .results)
        #expect(try #require(model.lastSummary).typedNothing,
                "the arrangement typed something — this measures nothing")
        #expect(model.tomorrowLine(zh: false) == nil)
        #expect(model.tomorrowLine(zh: true) == nil)
    }

    /// What the simulator hook seeds. From the raw records, not from `streakDays`: the seed skips
    /// four and nine days ago, so today, yesterday, two and three days ago are ridden — a four-day
    /// chain as of today, which is what lets the AX5 pass see the streak half at all.
    @Test("the demo journal the simulator hook seeds rides through today, four days deep")
    func demoJournalCarriesAStreak() throws {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        model.seedDemoJournal()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let ridden = Set(model.journal.records.map { cal.startOfDay(for: $0.date) })
        for daysAgo in 0...3 {
            #expect(ridden.contains(cal.date(byAdding: .day, value: -daysAgo, to: today)!),
                    "the demo journal has no ride \(daysAgo) day(s) ago")
        }
        #expect(!ridden.contains(cal.date(byAdding: .day, value: -4, to: today)!),
                "the seed's rest day moved; the 4 below is no longer the seed's own number")
        ReviewPromptWiringTests.rideCleanly(model)
        let line = try #require(model.tomorrowLine(zh: false))
        #expect(line.hasPrefix("4-day streak · "), Comment(rawValue: line))
    }

    // MARK: - The view, and the hook

    static func source(_ file: String) throws -> String {
        try V133GRideAndDrillLayoutTests.source(file)
    }

    /// **A scan, not a behavioural test.** `tomorrowLine` is a model method, so every test above
    /// stays green with the one line in `ResultsView` deleted — v1.26 §B's measurement. Deletion is
    /// what a scan can see. The Text's limit and floor are pinned here too, because the line sits
    /// in a `VStack` and `HorizontalTextFitTests` deliberately does not look there.
    @Test("ResultsView draws the line once, under the stage line and above the coach entry, text only")
    func resultsViewDrawsTheLine() throws {
        let raw = try Self.source("ResultsView.swift").components(separatedBy: "\n")
        let code = V133GRideAndDrillLayoutTests.codeLines(raw.joined(separator: "\n"))
        let calls = code.indices.filter { code[$0].contains("model.tomorrowLine(") }
        #expect(calls.count == 1, "ResultsView must call tomorrowLine exactly once, found \(calls.count)")
        let call = try #require(calls.first)
        let stage = try #require(code.firstIndex(of: "stageLine"), "the bare `stageLine` statement is gone")
        let coach = try #require(code.firstIndex(of: "coachEntry"), "the bare `coachEntry` statement is gone")
        #expect(stage < call && call < coach, "the line must sit under the stage line and above the coach entry")

        // Same block: the three statements share one indentation, and nothing between the stage
        // line and the coach entry is indented less — no block closes in between.
        func indent(_ i: Int) -> Int { raw[i].prefix { $0 == " " }.count }
        #expect(indent(stage) == indent(call) && indent(call) == indent(coach),
                "the call is not a sibling of stageLine and coachEntry")
        for i in (stage + 1)..<coach where !code[i].isEmpty {
            #expect(indent(i) >= indent(stage), "line \(i + 1) leaves the panel's block: \(code[i])")
        }

        // The Text and its chain: the limit and the floor, and nothing a finger could act on.
        let chain = code[(call + 1)..<coach].joined(separator: "\n")
        #expect(chain.contains("Text(line)"))
        #expect(chain.contains(".lineLimit("), "a long Chinese count must not break mid-number")
        #expect(chain.contains(".minimumScaleFactor("), "…and needs a floor to shrink to")
        for forbidden in ["Button(", "onTapGesture", ".sheet(", "Link(", "confirmationDialog", ".alert("] {
            #expect(!chain.contains(forbidden), "the tomorrow line must be text only, found \(forbidden)")
        }

        // …and no other screen draws it. The plan puts it on the results screen and nowhere else.
        let files = try FileManager.default.contentsOfDirectory(
            at: V133GRideAndDrillLayoutTests.appDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 20, "the scanner found only \(files.count) sources; it is broken, not clean")
        var callers: [String] = []
        for file in files where file.lastPathComponent != "AppModel.swift" {
            let lines = V133GRideAndDrillLayoutTests.codeLines(try String(contentsOf: file, encoding: .utf8))
            if lines.contains(where: { $0.contains("tomorrowLine(") }) { callers.append(file.lastPathComponent) }
        }
        #expect(callers == ["ResultsView.swift"], "found \(callers)")
    }

    /// `jumpToDebugScreen` writes — its `finishGame` persists SRS and a ride — and is gated to the
    /// simulator for exactly that reason. The hook seeds fourteen demo rides into the journal that
    /// write then saves, so it must sit inside the same `#if`, not beside it. Held by reading the
    /// source: the block does not compile on macOS, where this suite runs.
    @Test("the demo-journal hook sits in the results case, inside the simulator-only gate, before the ride")
    func hookIsGatedToTheSimulator() throws {
        let code = V133GRideAndDrillLayoutTests.codeLines(try Self.source("AppModel.swift"))
        let hooks = code.indices.filter { code[$0].contains("NIHONGO_DEBUG_DEMO_JOURNAL") }
        #expect(hooks.count == 1, "one hook, found \(hooks.count)")
        let hook = try #require(hooks.first)
        let fn = try #require(code.firstIndex { $0.hasPrefix("func jumpToDebugScreen(") })
        let gate = try #require(code[..<fn].lastIndex(of: "#if DEBUG && targetEnvironment(simulator)"),
                                "jumpToDebugScreen is no longer under the simulator gate")
        #expect(gate < fn && fn < hook)
        for i in (gate + 1)..<hook {
            #expect(!code[i].hasPrefix("#if") && !code[i].hasPrefix("#endif") && !code[i].hasPrefix("#else"),
                    "line \(i + 1) opens or closes a gate between the simulator #if and the hook: \(code[i])")
        }
        #expect(code[hook...].contains("#endif"), "the simulator gate never closes after the hook")

        let resultsCase = try #require(code[fn...].firstIndex(of: "case \"results\":"))
        let nextCase = try #require(code[(resultsCase + 1)...].firstIndex { $0.hasPrefix("case \"") })
        #expect(resultsCase < hook && hook < nextCase, "the hook is not in the \"results\" case")
        let seed = try #require(code[resultsCase..<nextCase].firstIndex(of: "seedDemoJournal()"),
                                "the results case never seeds the demo journal")
        let start = try #require(code[resultsCase..<nextCase].firstIndex(of: "startGame()"))
        #expect(hook < seed && seed < start,
                "the seed must run before startGame(), or the ride is logged into an empty journal")
    }
}
