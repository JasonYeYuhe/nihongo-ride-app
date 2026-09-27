import Testing
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import JournalKit
import ReviewKit
import ConjugationReviewKit
import VocabKit
@testable import NihongoRideApp

/// v1.34 §B1 — "Tomorrow, said out loud": the results screen states the streak and what comes due.
///
/// Six claims, held apart because each fails differently. The copy matrix, row by row, every
/// expected string written out by hand (mutating the streak threshold to ≥ 3 turns the 2-day rows
/// red). The wiring from a real ride through `finishGame` to `model.tomorrowLine(zh:)`, for words
/// AND forms, with every count computed by THIS file from the raw cards and never by `dueForecast`
/// (memory: a test that grades itself), over arrangements that put cards in every neighbouring
/// bucket — overdue, today, tomorrow, two and three days out, a retired entry, and (forms) a card
/// whose verb resolves but cannot be drilled — so a read of the wrong window cannot agree by
/// accident. The view — a model-level test passes while the screen draws nothing (v1.26 §D), so the shipped `ResultsView` source is read with `//` AND `/* */` comments
/// stripped, and its chain is pinned line for line. The line's colour, computed over every panel the
/// arrival backdrop can produce. Its line limit and floor, measured with CoreText at AX5. And the
/// simulator hook, pinned to the gate that keeps the writing harness off a real device.
///
/// What none of this proves: that the line is SEEN. That is the headless `results.png` render and
/// the simulator pass (PLAN-V1.34 §B1's proof, §G.2/§G.3), which run after merge — not a unit test.
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

    /// Which calendar day a due date falls on, counted from today: 0 today, 1 tomorrow, 3 three
    /// days out, negative when overdue. Calendar arithmetic here and never `dueForecast` — the read
    /// the line is wired to is exactly the thing the numbers below must be independent of.
    static func dayOffset(_ due: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: due)).day!
    }

    /// The count the line must show, from the raw cards: every card due on or before tomorrow's
    /// calendar day — overdue, due today and not reviewed, or due tomorrow — whose entry still
    /// exists. What will be waiting when the rider opens the app tomorrow (PLAN-V1.34 §B1 addendum
    /// 2026-09-27). `known` is the set of entry ids THIS file put in the vocabulary.
    static func dueByTomorrow(_ dues: [(entry: String, due: Date)], known: Set<String>) -> Int {
        dues.filter { known.contains($0.entry) && dayOffset($0.due) <= 1 }.count
    }

    static func words(_ store: ReviewStore) -> [(entry: String, due: Date)] {
        store.cards.values.map { (entry: $0.id, due: $0.dueDate) }
    }

    static func forms(_ store: ConjugationReviewStore) -> [(entry: String, due: Date)] {
        store.cards.values.map { (entry: $0.sourceID, due: $0.dueDate) }
    }

    static func ids(_ vocab: VocabStore) -> Set<String> { Set(vocab.entries.map(\.id)) }

    /// Yesterday and the day before, seeded through the journal's own writer, then today's ride:
    /// three consecutive days. The words-due count is the three ridden words — SM-2's first success
    /// is a one-day interval — and the arrangement is asserted before the line is read, so a ride
    /// that reviewed nothing cannot agree with "nothing due" for the wrong reason. (This one holds
    /// the streak half; which buckets the due half reads is `wordsReadTodayAndTomorrow`'s job.)
    @Test("a third consecutive day, ridden cleanly, reads the streak and the cards due tomorrow")
    func thirdDayRide() throws {
        let model = ReviewPromptWiringTests.seededJournal([Self.noonRide(daysAgo: 2),
                                                           Self.noonRide(daysAgo: 1)])
        ReviewPromptWiringTests.rideCleanly(model)
        #expect(model.journal.count == 3, "today's ride was not logged — nothing below measures the line")
        let due = Self.dueByTomorrow(Self.words(model.reviewStore), known: Self.ids(model.vocab))
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
        let due = Self.dueByTomorrow(Self.words(model.reviewStore), known: Self.ids(model.vocab))
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

    // MARK: - Which cards the due half counts: today + tomorrow, never the week, never a retired entry

    /// A sandboxed model whose journal, review store and conjugation store are all seeded before
    /// `init` reads them — `AppModelTests.seeded` seeds the stores and `seededJournal` the journal,
    /// and the forms test needs a streak, words and forms at once. Each seed is checked after load:
    /// a helper that silently seeded nothing would make every assertion below read zero and pass.
    static func seededRider(vocab: VocabStore, rides: [RideRecord],
                            review: ReviewStore, conjugation: ConjugationReviewStore) -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("V134B1-\(UUID().uuidString)", isDirectory: true)
        AppModel.supportDirectoryOverride = dir
        AppModel.widgetContainerOverride = dir.appendingPathComponent("group", isDirectory: true)
        let suite = "V134B1-\(UUID().uuidString)"
        AppModel.settingsDefaults = UserDefaults(suiteName: suite)
        AppModel.settingsSuiteOverride = suite
        var journal = RideJournal()
        for ride in rides { journal.append(ride) }
        try? journal.save(to: AppModel.supportFileURL("history.json"))
        let encoder = JSONEncoder()
        try? encoder.encode(review).write(to: AppModel.supportFileURL("review.json"))
        try? encoder.encode(conjugation).write(to: AppModel.supportFileURL("conjugation-review.json"))
        let model = AppModel(vocab: vocab)
        #expect(model.journal.count == rides.count, "the journal seed did not load")
        #expect(model.reviewStore.count == review.count, "the review seed did not load")
        #expect(model.conjugationReviewStore.count == conjugation.count, "the conjugation seed did not load")
        return model
    }

    /// Noon on the calendar day `offset` days from today (negative: overdue). Noon for the reason
    /// `noonRide` gives: a date near midnight would move day with the clock the suite runs at.
    static func noon(_ offset: Int) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
            .addingTimeInterval(12 * 3600)
    }

    static func card(_ id: String, due: Date) -> SRSCard {
        var card = SRSCard(id: id)
        card.dueDate = due
        card.totalReviews = 1
        card.repetitions = 1
        return card
    }

    static func formCard(_ sourceID: String, due: Date) -> ConjugationSRSCard {
        var card = ConjugationSRSCard(id: "\(sourceID)#te")
        card.dueDate = due
        card.totalReviews = 1
        card.repetitions = 1
        return card
    }

    /// Words: a backlog the ride cannot clear, cards due tomorrow, a card due in two days, cards due
    /// in three days, and two cards whose entries were retired (one due tomorrow, one overdue). A
    /// Journey ride takes at most eight due words (`GameSession.Config.reviewWordCount`), so ten
    /// overdue cards leave a backlog after it. Every neighbour of "today + tomorrow" is populated
    /// AFTER the ride, and the test says so before it reads the line, so each wrong window disagrees
    /// with the right one: tomorrow alone misses the backlog, a window one day too wide (through
    /// day+2) counts `d0`, adding the week counts the day+2 and day+3 cards, and dropping the
    /// retired-entry filter counts `gone-t` and `gone-o`.
    @Test("words: the line counts the backlog and tomorrow, never two or three days out, never a retired entry")
    func wordsReadTodayAndTomorrow() throws {
        var entries = [AppModelTests.entry("a", "水", "みず"), AppModelTests.entry("b", "火", "ひ"),
                       AppModelTests.entry("c", "山", "やま")]
        let backlog = (0..<10).map { "o\($0)" }, tomorrow = ["t0", "t1"], dayTwo = ["d0"], later = ["w0", "w1"]
        let kana = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "さ", "し", "す", "せ", "そ"]
        for (i, id) in (backlog + tomorrow + dayTwo + later).enumerated() {
            entries.append(AppModelTests.entry(id, kana[i], kana[i]))
        }
        var cards: [String: SRSCard] = [:]
        for (i, id) in backlog.enumerated() { cards[id] = Self.card(id, due: Self.noon(-1 - i)) }
        for id in tomorrow { cards[id] = Self.card(id, due: Self.noon(1)) }
        for id in dayTwo { cards[id] = Self.card(id, due: Self.noon(2)) }
        for id in later { cards[id] = Self.card(id, due: Self.noon(3)) }
        cards["gone-t"] = Self.card("gone-t", due: Self.noon(1))
        cards["gone-o"] = Self.card("gone-o", due: Self.noon(-2))
        let vocab = VocabStore(entries: entries)
        let model = Self.seededRider(vocab: vocab, rides: [], review: ReviewStore(cards: cards),
                                     conjugation: ConjugationReviewStore())
        ReviewPromptWiringTests.rideCleanly(model)
        #expect(model.journal.count == 1, "the ride was not logged — nothing below measures the line")

        let raw = Self.words(model.reviewStore), known = Self.ids(vocab)
        let live = raw.filter { known.contains($0.entry) }
        let backlogLeft = live.filter { Self.dayOffset($0.due) <= 0 }.count
        let dueTomorrow = live.filter { Self.dayOffset($0.due) == 1 }.count
        let dayAfter = live.filter { Self.dayOffset($0.due) == 2 }.count
        let thisWeek = live.filter { (3...6).contains(Self.dayOffset($0.due)) }.count
        let retired = raw.filter { !known.contains($0.entry) && Self.dayOffset($0.due) <= 1 }.count
        #expect(backlogLeft >= 1, "the ride cleared the backlog — tomorrow alone would agree")
        #expect(dueTomorrow >= 1 && dayAfter >= 1 && thisWeek >= 1 && retired >= 1,
                "an empty neighbour: tomorrow \(dueTomorrow), day+2 \(dayAfter), day+3…6 \(thisWeek), retired \(retired)")
        let due = Self.dueByTomorrow(raw, known: known)
        #expect(due == backlogLeft + dueTomorrow && due >= 2, "raw cards say \(due)")

        let line = try #require(model.tomorrowLine(zh: false))
        #expect(line == "\(due) words due tomorrow", Comment(rawValue: line))
        #expect(model.tomorrowLine(zh: true) == "明天到期 \(due) 个词")
        // Agreement, not the oracle: the Ride Log's Today and Tomorrow rows sum to the line.
        let log = model.reviewStore.dueForecast(resolves: model.vocab.resolvesID)
        #expect(log.today + log.tomorrow == due, "the Ride Log shows \(log.today) + \(log.tomorrow)")
    }

    /// Forms, the half no wiring test used to reach: every other test here rides with an empty
    /// conjugation store, so the forms count was 0 whatever the model read (round-2 review, three
    /// mutations green). A Journey ride never writes conjugation cards, so the seeded dates are
    /// still the dates when the line is read: one overdue, one due today, one tomorrow — counted —
    /// and one two days out, one three days out, one whose verb is retired, and one due tomorrow
    /// whose verb resolves but cannot be drilled — not counted. Rideable verbs from
    /// `AppModelTests.verbEntries`, the same seed `ConjugationRideableTests` counts as rideable; the
    /// undrillable one is that suite's `stranded` door, an entry present with `vc: nil`, so only
    /// the forms read's `rideable:` filter keeps it out.
    @Test("forms: the line counts overdue, today and tomorrow, never two or three days out, never a retired or undrillable verb")
    func formsReadTodayAndTomorrow() throws {
        let verbs = AppModelTests.verbEntries(5)
        let stranded = VocabEntry(id: "stranded", surface: "開ける", kana: "あける",
                                  partsOfSpeech: ["v"], jlpt: .n5,
                                  meanings: ["en": ["to open"], "zh": ["打开"]], vc: nil)
        let vocab = VocabStore(entries: Self.vocab().entries + verbs + [stranded])
        let cal = Calendar.current
        let dueToday = cal.startOfDay(for: Date()).addingTimeInterval(60)   // today, whatever the hour
        let form = [Self.formCard("v0", due: Self.noon(-1)), Self.formCard("v1", due: dueToday),
                    Self.formCard("v2", due: Self.noon(1)), Self.formCard("v4", due: Self.noon(2)),
                    Self.formCard("v3", due: Self.noon(3)), Self.formCard("gone", due: Self.noon(1)),
                    Self.formCard("stranded", due: Self.noon(1))]
        let model = Self.seededRider(
            vocab: vocab, rides: [Self.noonRide(daysAgo: 2), Self.noonRide(daysAgo: 1)],
            review: ReviewStore(), conjugation: ConjugationReviewStore(
                cards: Dictionary(uniqueKeysWithValues: form.map { ($0.id, $0) })))
        ReviewPromptWiringTests.rideCleanly(model)
        #expect(model.journal.count == 3, "today's ride was not logged — nothing below measures the line")

        let known = Self.ids(vocab)
        let rawForms = Self.forms(model.conjugationReviewStore)
        #expect(rawForms.count == 7, "the ride changed the conjugation store; this arrangement assumed it cannot")
        let strandedCard = try #require(model.conjugationReviewStore.cards["stranded#te"])
        #expect(model.vocab.resolvesID("stranded") && !model.conjugationRideable(strandedCard),
                "`stranded` must resolve and be undrillable, or only `resolves:` is being measured")
        // Drillable is the one property the raw cards do not carry, so it is written out by name:
        // `stranded` has no verb class, and nothing else in this seed lacks one.
        let formsDue = Self.dueByTomorrow(rawForms, known: known.subtracting(["stranded"]))
        #expect(formsDue == 3, "raw forms say \(formsDue): v0 overdue, v1 today, v2 tomorrow — not v4, not v3, not gone, not stranded")
        let wordsDue = Self.dueByTomorrow(Self.words(model.reviewStore), known: known)
        #expect(wordsDue >= 2, "the words half is plural in the string below; raw cards say \(wordsDue)")

        let line = try #require(model.tomorrowLine(zh: false))
        #expect(line == "3-day streak · \(wordsDue) words and \(formsDue) forms due tomorrow", Comment(rawValue: line))
        #expect(model.tomorrowLine(zh: true) == "连续 3 天 · 明天到期 \(wordsDue) 个词、\(formsDue) 个变形")
        // Agreement, not the oracle: Stats' conjugation Today and Tomorrow rows sum to the line.
        let stats = model.conjugationDueForecast
        #expect(stats.today + stats.tomorrow == formsDue, "Stats shows \(stats.today) + \(stats.tomorrow)")
    }

    // MARK: - The view, and the hook

    static func source(_ file: String) throws -> String {
        try V133GRideAndDrillLayoutTests.source(file)
    }

    /// Source lines with BOTH comment forms removed — `//` to the end of the line, and `/* … */`
    /// nested as Swift nests it — one output line per input line, each trimmed. The shared
    /// `V133GRideAndDrillLayoutTests.codeLines` blanks only lines that START with `//`, so the
    /// round-2 review wrapped the drawing block in `/* … */` and every pin here stayed green while
    /// the view drew nothing. String literals are skipped so a "//" inside one is not a comment.
    static func codeLines(_ source: String) -> [String] {
        var out = "", depth = 0, inString = false
        var i = source.startIndex
        while i < source.endIndex {
            let c = source[i], next = source.index(after: i)
            let n: Character? = next < source.endIndex ? source[next] : nil
            if depth > 0 {
                if c == "*", n == "/" { depth -= 1; i = source.index(after: next); continue }
                if c == "/", n == "*" { depth += 1; i = source.index(after: next); continue }
                if c == "\n" { out.append(c) }
                i = next
                continue
            }
            if inString {
                out.append(c)
                if c == "\\", let n { out.append(n); i = source.index(after: next); continue }
                if c == "\"" || c == "\n" { inString = false }
                i = next
                continue
            }
            if c == "/", n == "/" {
                while i < source.endIndex, source[i] != "\n" { i = source.index(after: i) }
                continue
            }
            if c == "/", n == "*" { depth = 1; i = source.index(after: next); continue }
            if c == "\"" { inString = true }
            out.append(c)
            i = next
        }
        return out.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The stripper is an instrument, so it is tested before it is trusted: it keeps the line count
    /// (the pin below reads indentation off the raw lines by index), it removes a block comment
    /// that spans lines and one that sits mid-line, it leaves a "//" inside a string alone, and —
    /// the control — the SHIPPED ResultsView with its drawing block wrapped in `/* … */` has no
    /// call left, which is the mutation the shared stripper let through.
    @Test("the comment stripper sees // and /* */, and keeps the line count")
    func strippedSeesBlockComments() throws {
        let sample = "a // x\n/* one\ntwo */ b\nc /* d */ e\nlet u = \"http://x\"\n/* /* nested */ still */ f"
        #expect(Self.codeLines(sample) == ["a", "", "b", "c  e", "let u = \"http://x\"", "f"])

        let shipped = try Self.source("ResultsView.swift")
        #expect(Self.codeLines(shipped).count == shipped.components(separatedBy: "\n").count)
        let open = "if let line = model.tomorrowLine(zh: zh) {"
        let start = try #require(shipped.range(of: open), "the drawing block moved")
        let close = try #require(shipped.range(of: "}\n", range: start.upperBound..<shipped.endIndex))
        let wrapped = shipped.replacingCharacters(in: start.lowerBound..<close.upperBound,
                                                  with: "/*" + shipped[start.lowerBound..<close.lowerBound] + "}*/\n")
        #expect(Self.codeLines(wrapped).filter { $0.contains("tomorrowLine(") }.isEmpty,
                "a block-commented call still counts as code")
        #expect(!V133GRideAndDrillLayoutTests.codeLines(wrapped).filter { $0.contains("tomorrowLine(") }.isEmpty,
                "control: the //-only stripper should still see the commented call, or this proves nothing")
    }

    /// **A scan, not a behavioural test.** `tomorrowLine` is a model method, so every test above
    /// stays green with the one line in `ResultsView` deleted — v1.26 §B's measurement. So the
    /// drawing block is pinned LINE FOR LINE on comment-stripped code: the call with the view's own
    /// `zh` (the round-2 review set it to `zh: false` and the old pin, which read only
    /// `model.tomorrowLine(`, stayed green), the colour, limit and floor by their names — their
    /// values are pinned below — and nothing else in the chain. An added modifier turns this red,
    /// `.opacity(0)` included, but that is a side effect: that the line is SEEN is the headless
    /// render's and the simulator pass's to show, after merge.
    @Test("ResultsView draws the line once, under the stage line and above the coach entry, text only")
    func resultsViewDrawsTheLine() throws {
        let raw = try Self.source("ResultsView.swift").components(separatedBy: "\n")
        let code = Self.codeLines(raw.joined(separator: "\n"))
        let calls = code.indices.filter { code[$0].contains("tomorrowLine(") }
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

        // The block, exactly. Nothing a finger could act on, because nothing else is allowed.
        let between = code[(stage + 1)..<call].filter { !$0.isEmpty }
        #expect(between.isEmpty, "something sits between the stage line and the call: \(between)")
        #expect(Array(code[call..<coach].filter { !$0.isEmpty }) == [
            "if let line = model.tomorrowLine(zh: zh) {",
            "Text(line)",
            ".font(.caption)",
            ".foregroundStyle(Self.tomorrowLineColor)",
            ".multilineTextAlignment(.center)",
            ".lineLimit(Self.tomorrowLineLimit(accessibilitySize: typeSize.isAccessibilitySize))",
            ".minimumScaleFactor(Self.tomorrowLineScaleFloor)",
            ".fixedSize(horizontal: false, vertical: true)",
            "}",
        ])
        #expect(code.contains("@Environment(\\.dynamicTypeSize) private var typeSize"),
                "`typeSize` is no longer the environment's Dynamic Type size")

        // …and no other screen draws it. The plan puts it on the results screen and nowhere else.
        let files = try FileManager.default.contentsOfDirectory(
            at: V133GRideAndDrillLayoutTests.appDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 20, "the scanner found only \(files.count) sources; it is broken, not clean")
        var callers: [String] = []
        for file in files where file.lastPathComponent != "AppModel.swift" {
            let lines = Self.codeLines(try String(contentsOf: file, encoding: .utf8))
            if lines.contains(where: { $0.contains("tomorrowLine(") }) { callers.append(file.lastPathComponent) }
        }
        #expect(callers == ["ResultsView.swift"], "found \(callers)")
    }

    // MARK: - The limit and the floor, by value and by measurement

    /// By value, so `.lineLimit(nil)` / `.minimumScaleFactor(1.0)` — or a constant quietly moved —
    /// is red here rather than green by name (round-2 review). Two below the accessibility sizes is
    /// the line's first build, which the default-size renders were taken with.
    @Test("the line limit is 2 below the accessibility sizes and 3 at them; the floor is 0.7")
    func limitAndFloorByValue() {
        #expect(DynamicTypeSize.allCases.filter(\.isAccessibilitySize).count == 5)
        for size in DynamicTypeSize.allCases {
            #expect(ResultsView.tomorrowLineLimit(accessibilitySize: size.isAccessibilitySize)
                    == (size.isAccessibilitySize ? 3 : 2), "\(size)")
        }
        #expect(ResultsView.tomorrowLineScaleFloor == 0.7)
    }

    #if canImport(AppKit)
    /// How many lines CoreText breaks `text` into at `points` in a column `width` wide — the same
    /// measurement `V133SSettingsAboutTests` makes with the system UI font.
    static func lineCount(_ text: String, points: Double, width: Double) throws -> Int {
        let font = try #require(CTFontCreateUIFontForLanguage(.system, points, nil))
        let setter = CTFramesetterCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as? [CTLine] ?? []).count
    }

    /// The column the line gets on the 402pt iPhone 17 Pro the AX5 pass uses, from the source:
    /// the screen's own padding on a phone and `arrivalPanel`'s compact horizontal padding, each
    /// read rather than copied, so a change to either is re-measured here.
    static func panelColumn() throws -> Double {
        let results = Self.codeLines(try Self.source("ResultsView.swift")).joined(separator: "\n")
        let screen = try #require(results.firstMatch(of: /\.padding\(isPhoneIdiom \? ([0-9]+) : [0-9]+\)/),
                                  "ResultsView's content padding moved")
        let backdrop = Self.codeLines(try Self.source("RideArrivalBackdrop.swift")).joined(separator: "\n")
        let panel = try #require(backdrop.firstMatch(of: /\.padding\(\.horizontal, compact \? ([0-9]+) : [0-9]+\)/),
                                 "arrivalPanel's horizontal padding moved")
        return 402 - 2 * (try #require(Double(screen.1))) - 2 * (try #require(Double(panel.1)))
    }

    /// The widest realistic rows, in both languages, fit the accessibility-size limit at the floor
    /// on the AX5 phone, so SwiftUI never has to truncate — the round-2 finding was that two lines
    /// cut "due tomorrow" off the English streak rows. `.caption` at AX5 is 43pt in Apple's Dynamic
    /// Type table (the same table `V133GRideAndDrillLayoutTests.accessibilityScales` copies body
    /// and largeTitle from); 40pt, `.caption2`'s, is measured too because the review used it.
    /// The control: at the old limit of two, the English row does NOT fit at the floor, or this
    /// instrument could not have seen the finding.
    @Test("at AX5 the widest rows fit the accessibility limit at the floor, and did not fit two lines")
    func widestRowsFitAtAX5() throws {
        let column = try Self.panelColumn()
        #expect(column == 322, "the column was 322pt when the limit was measured; now \(column)pt — re-measure")
        let widest = ["365-day streak · 999 words and 999 forms due tomorrow",
                      "连续 365 天 · 明天到期 999 个词、999 个变形"]
        // The rows are the composer's own output, not a guess at it.
        #expect(TomorrowLine.compose(streakDays: 365, wordsDue: 999, formsDue: 999, zh: false) == widest[0])
        #expect(TomorrowLine.compose(streakDays: 365, wordsDue: 999, formsDue: 999, zh: true) == widest[1])
        let limit = ResultsView.tomorrowLineLimit(accessibilitySize: true)
        let floor = Double(ResultsView.tomorrowLineScaleFloor)
        for points in [43.0, 40.0] {
            for row in widest {
                let lines = try Self.lineCount(row, points: points * floor, width: column)
                #expect(lines <= limit, "\(points)pt × \(floor): \(lines) lines for a limit of \(limit) — \(row)")
            }
        }
        // Measured 2026-09-27: at 43pt the English row fits three lines from a 0.865 scale down and
        // the Chinese row fits three at full size, so the floor has room.
        let enRoom = try Self.lineCount(widest[0], points: 43 * 0.86, width: column)
        let zhFull = try Self.lineCount(widest[1], points: 43, width: column)
        #expect(enRoom <= limit && zhFull <= limit, "en at 0.86: \(enRoom) lines; zh at full size: \(zhFull)")
        // The control: two lines at the floor truncated the English row.
        let twoLineControl = try Self.lineCount(widest[0], points: 43 * floor, width: column)
        #expect(twoLineControl > 2,
                "control: the English row fits two lines at the floor — the instrument cannot see the finding")
    }
    #endif

    // MARK: - The colour

    typealias RGB = V133SContrastTests.RGB

    /// A number from a source file, read rather than copied, so a change there is recomputed here.
    static func sourceNumber(_ path: String, _ pattern: Regex<(Substring, Substring)>) throws -> Double {
        let url = V133GRideAndDrillLayoutTests.appDirectory.deletingLastPathComponent().appendingPathComponent(path)
        let code = Self.codeLines(try String(contentsOf: url, encoding: .utf8)).joined(separator: "\n")
        let match = try #require(code.firstMatch(of: pattern), "\(path): the value moved")
        return try #require(Double(match.1))
    }

    /// Every colour the arrival panel can resolve to: black at `RidePalette.cardAlpha` over the
    /// backdrop, which is the scene under a black scrim of `textScrim + 0.15`, and `textScrim` is
    /// never below `baseScrim`. Scenes over a 0.1 RGB grid, from black to white, and scrims from
    /// the lowest the backdrop can use up to fully black — a superset of the real skies, so the
    /// worst case here is no better than the worst real one.
    static func arrivalPanels() throws -> [RGB] {
        let cardAlpha = try Self.sourceNumber("SceneryKit/RidePalette.swift", /public static let cardAlpha = ([0-9.]+)/)
        let baseScrim = try Self.sourceNumber("SceneryKit/RidePalette.swift", /public static let baseScrim = ([0-9.]+)/)
        let extra = try Self.sourceNumber("NihongoRideApp/RideArrivalBackdrop.swift",
                                          /Color\.black\.opacity\(stage\.palette\.textScrim \+ ([0-9.]+)\)/)
        let panelCode = Self.codeLines(try Self.source("RideArrivalBackdrop.swift"))
        #expect(panelCode.contains(".background(.black.opacity(RidePalette.cardAlpha),"),
                "arrivalPanel no longer backs its content with black at cardAlpha")
        let lowest = baseScrim + extra
        #expect(abs(lowest - 0.25) < 1e-9, "the lowest scrim was 0.25 when this was computed; now \(lowest)")
        let grid = (0...10).map { Double($0) / 10 }
        var panels: [RGB] = []
        for scrim in [lowest, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0] {
            for r in grid { for g in grid { for b in grid {
                let backdrop = V133SContrastTests.over(Color.black.opacity(scrim), (r, g, b))
                panels.append(V133SContrastTests.over(Color.black.opacity(cardAlpha), backdrop))
            } } }
        }
        return panels
    }

    static func worstContrast(_ color: Color, over panels: [RGB]) -> Double {
        panels.map { V133SContrastTests.contrast(V133SContrastTests.over(color, $0), $0) }.min() ?? 0
    }

    /// The line's colour clears WCAG AA's 4.5:1 for small text over every panel above, with 8-bit
    /// quantisation applied at the worst one; `Theme.dim`, which it first copied from the stage
    /// line, computes under — the control, or this suite could not fail. And 0.46 is the smallest:
    /// one hundredth less does not clear. (Round-2 review: 4.41–4.53:1 measured for `Theme.dim`.)
    @MainActor
    @Test("the tomorrow line's colour clears 4.5:1 on every arrival panel, and Theme.dim does not")
    func tomorrowLineColorClearsAA() throws {
        let panels = try Self.arrivalPanels()
        #expect(panels.count == 7 * 1331)
        let now = Self.worstContrast(ResultsView.tomorrowLineColor, over: panels)
        #expect(now >= 4.5, "the tomorrow line computes to \(now):1 at its worst")
        let dim = Self.worstContrast(Theme.dim, over: panels)
        #expect(dim < 4.5 && dim > 4.3, "control: Theme.dim computed \(dim):1 — measured 4.41:1")
        let lower = V133SContrastTests.resolved(ResultsView.tomorrowLineColor).alpha - 0.01
        #expect(Self.worstContrast(Color.white.opacity(lower), over: panels) < 4.5,
                "white at \(lower) also clears — the constant is not the smallest opacity that does")

        // 8-bit: the worst panel and the text over it, each rounded to a byte, still clear.
        func q(_ c: RGB) -> RGB { ((c.r * 255).rounded() / 255, (c.g * 255).rounded() / 255, (c.b * 255).rounded() / 255) }
        let worst = try #require(panels.min {
            V133SContrastTests.contrast(V133SContrastTests.over(ResultsView.tomorrowLineColor, $0), $0)
                < V133SContrastTests.contrast(V133SContrastTests.over(ResultsView.tomorrowLineColor, $1), $1)
        })
        let quantised = V133SContrastTests.contrast(q(V133SContrastTests.over(ResultsView.tomorrowLineColor, worst)), q(worst))
        #expect(quantised >= 4.5, "after 8-bit quantisation: \(quantised):1 over \(worst)")
    }

    /// `jumpToDebugScreen` writes — its `finishGame` persists SRS and a ride — and is gated to the
    /// simulator for exactly that reason. The hook seeds fourteen demo rides into the journal that
    /// write then saves, so it must sit inside the same `#if`, not beside it. Held by reading the
    /// source: the block does not compile on macOS, where this suite runs.
    @Test("the demo-journal hook sits in the results case, inside the simulator-only gate, before the ride")
    func hookIsGatedToTheSimulator() throws {
        let code = Self.codeLines(try Self.source("AppModel.swift"))
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
