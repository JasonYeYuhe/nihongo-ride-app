import Foundation
import Observation
import RomajiKana
import VocabKit
import ReviewKit

/// Drives one play-through of the typing game: a queue of words (new + due
/// review), the current word's matcher, scoring/combo, the bike-journey
/// distance, and recording each outcome into the SRS store.
///
/// UI-independent — it imports `Observation` (so SwiftUI can observe it) but not
/// SwiftUI. The game mode (bike journey vs. conveyor belt) lives entirely in the
/// view layer; this type only knows "type the word, advance, score".
/// Which game mode a run uses. The engine/loop are identical; modes differ only
/// in word supply and how the run ends (route distance vs. a countdown).
public enum GameMode: String, Sendable, CaseIterable {
    case journey       // ride a route; ends when the word queue is done
    case timeAttack    // sprint; ends when the timer (UI-driven) runs out
    case practice      // calm, distraction-free passage typing
    case conjugation   // verb-conjugation drill (driven by ConjugationSession, no SRS)
    case sentence      // type a whole example sentence (v1.18); no SRS — see RunCompletion
    case dictation     // hear a sentence and type it (v1.21); no SRS, same reason as .sentence
}
extension GameMode {
    /// The mode's name on the menu capsule — the one place a learner reads it.
    ///
    /// It lives here, beside the mode, for the reason `completedUnitLabel` gives one property
    /// down: a call site choosing its own string is how the unit labels drifted the first time.
    /// The menu built this list by hand, and the ONBOARDING built a different one — which is how
    /// three of the six modes came to be advertised nowhere a new user would look. (v1.32 §F1.)
    public func shortLabel(zh: Bool) -> String {
        switch self {
        case .journey:     return zh ? "环游" : "Journey"
        case .timeAttack:  return zh ? "限时" : "Time"
        case .practice:    return zh ? "练习" : "Practice"
        case .conjugation: return zh ? "变形" : "Verbs"
        case .sentence:    return zh ? "例句" : "Sentence"
        case .dictation:   return zh ? "听写" : "Listen"
        }
    }

    /// One clause describing the mode, for the first-launch intro.
    ///
    /// Beside `shortLabel` and driven by `allCases` at the call site, so **a seventh mode cannot
    /// ship unadvertised**: adding a case is a compile error here, and `OnboardingModesTests`
    /// fails if the intro page stops naming one. That is the structural half of the fix — the
    /// copy edit on its own would have drifted again the next time a mode was added, which is
    /// exactly what happened between v1.6 and v1.21.
    ///
    /// Deliberately says nothing about the road, a route, or a destination: the intro carries no
    /// offer language and must not gain any (`PLAN-WINDOW` constraint 1).
    public func onboardingClause(zh: Bool) -> String {
        switch self {
        case .journey:     return zh ? "打字穿越日本,解锁地标" : "type across Japan and unlock landmarks"
        case .timeAttack:  return zh ? "60 秒冲刺" : "a 60-second sprint"
        case .practice:    return zh ? "沉浸式文章打字,平静不计分" : "calm, score-free passage typing"
        case .conjugation: return zh ? "动词变形专项练习" : "drill verb conjugations"
        case .sentence:    return zh ? "整句打字,不只是单词" : "type a whole sentence, not just a word"
        case .dictation:   return zh ? "听一句,然后打出来" : "hear a sentence, then type it"
        }
    }

    /// Whether a lapsed entry in this mode is a WORD the learner can be shown as one.
    ///
    /// False for sentence and dictation, where `GameSession.sentenceSession` wraps each
    /// sentence as a `VocabEntry` whose `surface` is the whole sentence and whose `kana` is the
    /// whole reading. Anything that renders a lapsed entry as a word — a grid cell, a saved-word
    /// row, a VoiceOver label — is rendering a sentence in a word's clothes, which is exactly
    /// what the v1.25 §B render showed: 「友達と映画を見ました。」 inside a 116pt cell captioned
    /// "movie, film".
    ///
    /// One predicate, so the tile that counts them and the list that draws them cannot disagree
    /// about what they are.
    public var lapsesAreWords: Bool { self != .sentence && self != .dictation }

    /// What ONE completed item in this mode is called, for the counter that counts them.
    ///
    /// v1.25 §B taught the results screen this distinction and reached three call sites of five.
    /// The ride HUD and the share card kept saying "Words" for a queue of sentences, so a single
    /// sentence run showed three units for one number: "Words 2/5" mid-ride, "Sentences 5" on
    /// results, and a card the learner POSTS PUBLICLY saying "Words 5".
    ///
    /// It lives here, beside the predicate, so the four places that name the unit cannot name it
    /// differently — the same reason `RunClock.wpm` gives for owning its own arithmetic. A call
    /// site choosing its own string is how this drifted the first time.
    ///
    /// The ride HUD deliberately passes neither: its Chinese has always been 进度 ("progress"),
    /// which is mode-neutral and right in all six modes.
    public func completedUnitLabel(zh: Bool) -> String {
        if lapsesAreWords { return zh ? "完成词数" : "Words" }
        return zh ? "完成句数" : "Sentences"
    }

    /// The results headline for a ride that ended before anything was typed, in the same unit.
    ///
    /// v1.33 wrote "The ride ended before the first word" for every mode, and the simulator pass of
    /// 2026-09-18 saw it on a sentence and a dictation run above a tile counting "Sentences" /
    /// 完成句数 — the three-units-for-one-run shape the doc above records, on the screen that
    /// replaced a false arrival. Beside `completedUnitLabel` so the two cannot name different units.
    /// (v1.33 pre-submission review, round 3.)
    public func endedBeforeFirstUnitHeadline(zh: Bool) -> String {
        if lapsesAreWords { return zh ? "第一个词还没打,这一程就结束了" : "The ride ended before the first word" }
        return zh ? "第一句还没打,这一程就结束了" : "The ride ended before the first sentence"
    }

    /// The ride HUD's progress label, including the rule about Chinese.
    ///
    /// The HUD's Chinese has always been 进度 ("progress"), which is mode-neutral and therefore
    /// right in all six modes — one language had solved this and the other had not. That rule
    /// lived at the call site as `zh ? "进度" : mode.completedUnitLabel(zh: false)`, which still
    /// left `GameView` CHOOSING, and the pre-submission review measured what that costs:
    /// reverting the call site to a bare "Words" left the entire suite green, because the test
    /// below can only see this file. So the choice is moved here. The view now asks one
    /// question and gets one answer, the same shape `MenuView` was given for §B1 and §B2.
    public func hudProgressLabel(zh: Bool) -> String {
        zh ? "进度" : completedUnitLabel(zh: false)
    }

    /// Whether the queue's LENGTH is a target the learner is working towards.
    ///
    /// **It is not, in Time Attack, and the HUD was claiming otherwise.** That mode ends on the
    /// clock, and `startGame` fills its queue with `newWordCount = 300` — the comment there says
    /// why in as many words: *"plenty for a 60s sprint"*. It is a pool size. But the HUD renders
    /// `wordsCompleted/wordCount` in every mode, so a rider opening a sixty-second sprint was
    /// shown **"0/300"** under a "Done" label, which reads as a target and is one nobody comes
    /// within an order of magnitude of. Seen on an iPhone; no store screenshot carries it.
    ///
    /// Every other mode's queue IS the target: journey and practice ride the queue to its end,
    /// sentence and dictation ride five, the conjugation drill twelve.
    ///
    /// It lives here for the reason `hudProgressLabel` gives directly above — a view choosing
    /// this for itself is how the unit labels drifted the first time, and a call site's choice
    /// is invisible to the tests in this file.
    public var queueLengthIsTheTarget: Bool { self != .timeAttack }

    /// The same distinction for the tile that counts what went wrong on a run persisting no SRS.
    public func struggledLabel(zh: Bool) -> String {
        if lapsesAreWords { return zh ? "吃力" : "Struggled" }
        return zh ? "吃力句" : "Tough lines"
    }
}


/// What a finished run persists and where it lands — the single source of truth for
/// `AppModel.finishGame`'s side-effect gating, extracted as a pure value so the
/// cram/practice red lines are unit-testable (PLAN-V1.7 §D test seam).
public struct RunCompletion: Equatable, Sendable {
    /// Persist SRS progress — real rides only (never practice or a weak-words cram).
    public var persistsSRS: Bool
    /// Append to the ride journal + lifetime odometer — everything except a cram.
    public var logsRide: Bool
    /// Report score / achievements to Game Center — real rides only.
    public var reportsGameCenter: Bool
    /// Show the results screen (true) vs go straight back to the menu (practice).
    public var showsResults: Bool

    /// Decides a run's completion from its mode + whether it records SRS:
    /// - a **weak-words cram** (`recordsSRS == false`) advances nothing — no SRS,
    ///   journal, odometer, or Game Center — but still shows its review-these results;
    /// - **practice** records no SRS but still logs a ride, and returns to the menu;
    /// - **sentence** records no SRS either, and the reason is worth stating: a sentence run
    ///   counts mistakes across the WHOLE sentence, so a typo in an unrelated clause would
    ///   land on the review card of the one word the sentence teaches. That card is
    ///   calibrated for typing a word; grading it on a whole sentence records an
    ///   incomparable signal into the same scheduler. Sentence mode still logs a ride and
    ///   still shows results — it is a real run, just not a review of anything.
    /// - **dictation** is sentence mode with the sentence heard instead of seen, so it
    ///   inherits the same answer — mistakes are still counted across a whole sentence, and
    ///   a listening failure is an even worse thing to charge to one word's card than a
    ///   typing one.
    /// - every real ride persists everything and shows results.
    public init(mode: GameMode, recordsSRS: Bool) {
        let isCram = !recordsSRS
        let isPractice = mode == .practice
        let isSentence = mode == .sentence || mode == .dictation
        persistsSRS = !isPractice && !isSentence && !isCram
        logsRide = !isCram
        reportsGameCenter = !isPractice && !isCram
        showsResults = !isPractice
    }
}

@Observable
public final class GameSession {
    public struct Config: Sendable {
        /// Meaning display language code (e.g. "en", "zh").
        public var languageCode: String
        public var assistance: AssistanceMode
        /// How many new words to introduce per run.
        public var newWordCount: Int
        /// How many due review words to mix in.
        public var reviewWordCount: Int
        /// Baseline seconds per kana, used to derive the speed grade.
        public var secondsPerKanaBaseline: Double
        /// JLPT level to draw new words from; `nil` mixes all levels.
        public var level: JLPTLevel?
        public var mode: GameMode
        /// Countdown for time-attack, in seconds (UI-driven); `nil` for journey.
        public var timeLimit: TimeInterval?
        /// Whether typing outcomes are written to the SRS store during the run.
        /// `true` for real rides; **`false` for the weak-words cram** — early-reviewing
        /// not-yet-due cards would corrupt the SM-2 schedule, so a cram must never
        /// write SRS (PLAN-V1.7 §B red line). Default `true` preserves all real runs.
        public var recordsSRS: Bool

        public init(
            languageCode: String = "en",
            assistance: AssistanceMode = .always,
            newWordCount: Int = 12,
            reviewWordCount: Int = 8,
            secondsPerKanaBaseline: Double = 0.8,
            level: JLPTLevel? = nil,
            mode: GameMode = .journey,
            timeLimit: TimeInterval? = nil,
            recordsSRS: Bool = true
        ) {
            self.languageCode = languageCode
            self.assistance = assistance
            self.newWordCount = newWordCount
            self.reviewWordCount = reviewWordCount
            self.secondsPerKanaBaseline = secondsPerKanaBaseline
            self.level = level
            self.mode = mode
            self.timeLimit = timeLimit
            self.recordsSRS = recordsSRS
        }
    }

    // MARK: Public state (observed by the UI)

    public private(set) var current: VocabEntry?
    /// Refused keystrokes for this run, with the context needed to explain them back.
    /// In memory only; never persisted, never synced. (v1.15.)
    public private(set) var mistakes = MistakeTrace()
    public private(set) var index = 0
    public private(set) var score = 0
    public private(set) var combo = 0
    public private(set) var maxCombo = 0
    public private(set) var wordsCompleted = 0
    public private(set) var totalKeystrokes = 0
    public private(set) var correctKeystrokes = 0
    /// Bike-journey progress in (game) meters; advances on each completed word.
    public private(set) var distanceMeters = 0.0
    /// Words that lapsed this run (skipped, hinted, or many typos) — worth reviewing.
    public private(set) var lapsedEntries: [VocabEntry] = []
    /// How many times the learner asked to hear a sentence again, across the whole run
    /// (dictation only). Replaying is free and never scored — this trains listening, not
    /// memory — but the count is kept and shown, because a run that needed twelve replays
    /// and a run that needed none are different outcomes and the score alone hides that.
    public private(set) var replays = 0
    /// Replays spent on the sentence currently playing, so the card can show them live.
    public private(set) var currentReplays = 0
    public private(set) var isFinished = false
    /// The assistance policy for this run (v1.16 §A — one policy, not two hint systems).
    public var assistance: AssistanceMode { config.assistance }
    /// Whether the romaji answer is visible RIGHT NOW: study mode, or this word was revealed.
    /// Replaces the old mutable `showRomajiHint`, which `revealHint()` flipped session-wide —
    /// one reveal turned hints on for every later word in the run.
    public var romajiVisible: Bool { assistance == .always || currentRevealed }
    /// A reveal control is being offered because the learner is genuinely stuck (distinct
    /// refusals at the same matcher state, threshold `struggleOfferThreshold`). Never in
    /// Time Attack — the timer runs regardless, so any reading costs competitive time.
    public private(set) var assistanceOffered = false
    /// Whether the current word has been revealed (charged as a hint on completion).
    public var isRevealed: Bool { currentRevealed }

    static let struggleOfferThreshold = 3
    private var struggle = StruggleDetector()

    // MARK: Config / dependencies

    public let config: Config
    public private(set) var review: ReviewStore

    private let queue: [VocabEntry]
    private let now: () -> Date
    private var matcher: KanaInputMatcher?
    private var currentMistakes = 0
    private var currentRevealed = false
    /// Time on the current word, excluding pauses. Was a bare `Date` and raw wall clock:
    /// the ride's `RunClock` stopped for the pause overlay, the sheet and backgrounding
    /// while this did not, so a word interrupted by any of the three was graded on time the
    /// rider spent away from the keyboard. See `PromptClock`.
    private var promptClock: PromptClock

    // MARK: Init

    /// Designated initializer with an explicit word list (used by tests for determinism).
    public init(
        words: [VocabEntry],
        review: ReviewStore = ReviewStore(),
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) {
        self.queue = words
        self.review = review
        self.config = config
        self.now = now
        self.promptClock = PromptClock(startedAt: now())
        loadCurrent()
    }

    /// Builds a run over sentences the LEARNER supplied.
    ///
    /// **GameCore takes plain values here, deliberately.** `makeReview` already established the
    /// rule — it takes `(entryID, formToken)` strings so GameCore never imports
    /// ConjugationReviewKit — and the same reason applies: CustomTextKit owns the reading
    /// pipeline and the store, and GameCore knowing about either would put the app's newest
    /// data type behind the module every mode is built on.
    ///
    /// **This mode is `.practice` and that is a safety property, not a category.**
    /// `RunCompletion(mode: .practice)` sets `persistsSRS = false`, so a pasted sentence cannot
    /// reach the review scheduler. `SRSCard(id:)` is keyed on corpus entry ids and `SyncMerge`
    /// merges those across devices through CloudKit; giving pasted words card identities is the
    /// expensive and dangerous half of "bring your own Japanese", and running on the one mode
    /// that records nothing is what keeps this the cheap half.
    ///
    /// - Parameter sentences: `(id, displayKana, kana, source, tokens)` per sentence, already
    ///   filtered to the typeable ones by the caller. `kana` is the typing target; `displayKana`
    ///   is the same readings with their punctuation, which the practice screen renders; `source`
    ///   and `tokens` are the learner's own text and its per-token readings, shown above.
    public static func makeCustomText(
        sentences: [(id: String, displayKana: String, kana: String, source: String,
                     tokens: [[String]])],
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        let words = sentences.map { sentence in
            VocabEntry(
                id: "customtext-\(sentence.id)",
                // The practice screen renders `surface` for the typing line, so it carries the
                // punctuated reading; the engine consumes `kana`, which has none.
                surface: sentence.displayKana,
                kana: sentence.kana,
                partsOfSpeech: ["customtext"],
                jlpt: .n5,
                meanings: [:],
                exampleJP: sentence.source,
                exampleTokens: sentence.tokens
            )
        }
        var custom = config
        custom.mode = .practice
        // **`recordsSRS` is deliberately LEFT ALONE, and the reason is a trap.** Setting it
        // false looks like belt-and-braces on the SRS guarantee, and it is not: `RunCompletion`
        // reads `!recordsSRS` as "this is a weak-words cram" and switches off `logsRide` too.
        // A learner who typed five hundred characters of their own text would watch the road
        // not move, with nothing on screen saying why. The SRS guarantee comes from the mode —
        // `RunCompletion(mode: .practice).persistsSRS == false`, the same guarantee ordinary
        // practice has had since v1.7 — and `AppModelTests` observes it on a real run rather
        // than trusting this sentence.
        return GameSession(words: words, config: custom, now: now)
    }

    /// Builds a passage-driven session: every queue item is a full sentence
    /// (the passage's kana) — used by Practice "long-text" mode. Uses passages
    /// at or below `level`; difficulty rises as you progress through the run.
    /// - Parameter matching: when given, selects passages by CONTENT across every level
    ///   instead of by level. The coach's particle drill needs the sentences that actually
    ///   contain は/へ/を, and those are spread over all three lengths. (v1.15 §J.)
    public static func makePractice(
        passages: PassageStore = .shared,
        level: Passage.Level = .hard,
        matching: ((Passage) -> Bool)? = nil,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = matching.map { passages.passages.filter($0) }
            ?? passages.passages.filter { $0.level == level }
        if pool.isEmpty { pool = passages.passages }   // safety net
        DeckRandomness.shuffle(&pool)
        let words = pool.prefix(max(8, config.newWordCount)).map { passage -> VocabEntry in
            VocabEntry(
                id: "passage-\(passage.id)",
                surface: passage.kana,
                kana: passage.kana,
                partsOfSpeech: ["passage"],
                jlpt: .n5,
                meanings: passage.meanings.mapValues { [$0] }
            )
        }
        var practiceConfig = config
        practiceConfig.mode = .practice
        return GameSession(words: Array(words), config: practiceConfig, now: now)
    }

    /// Builds a sentence-typing run: the target is a whole example sentence's reading.
    ///
    /// Mechanically this is the same trick as `makePractice` — a synthetic `VocabEntry` whose
    /// `kana` is what gets typed — but the surface stays the KANJI sentence, because that is
    /// what the learner reads while typing, and the id stays the real entry's so the results
    /// screen can say which word each sentence was teaching.
    ///
    /// Only entries with `isTypeableSentence` are eligible. Fourteen shipped sentences have
    /// no reading on purpose (digits read one digit at a time), and offering one as a target
    /// would mark a learner wrong for typing what the sentence actually says.
    public static func makeSentence(
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = vocab.ordered(level: config.level).filter { $0.isTypeableSentence }
        // Level-scoped first; if that level has no typeable sentence yet, fall back to the
        // whole corpus rather than starting an empty run.
        if pool.isEmpty { pool = vocab.ordered().filter { $0.isTypeableSentence } }
        DeckRandomness.shuffle(&pool)
        return sentenceSession(from: Array(pool.prefix(max(5, config.newWordCount))),
                               config: config, now: now)
    }

    /// The entries from `ids` that can actually carry a sentence run, in the given order and
    /// de-duplicated. Ids that no longer resolve are dropped, and so are entries with no
    /// typeable sentence — a saved list is a list of WORDS, and 5% of the corpus has no
    /// sentence to type.
    ///
    /// Exposed so the menu can show the real number before the run starts rather than
    /// after: "this list has 20 words and 6 of them have a sentence" is a different fact
    /// from "this list has 20 words", and the learner is entitled to the first one.
    public static func sentenceEntries(ids: [String], vocab: VocabStore = .shared) -> [VocabEntry] {
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let entry = vocab.entry(id: id),
                  entry.isTypeableSentence else { return nil }
            return entry
        }
    }

    /// Builds a sentence run from a chosen set of vocab ids — a saved word list, or the
    /// due-review stack (PLAN-V1.21 §B).
    ///
    /// **It never falls back to the level or corpus pool.** `makeSentence` does, because
    /// "this level has no sentences yet" was a content gap with a sensible substitute. Here
    /// the ids ARE the request: padding a three-sentence list up to five with unrelated
    /// corpus sentences would answer a question the learner did not ask, and they would have
    /// no way to tell which two were not theirs. A short run is the honest outcome, and an
    /// empty one leaves `isFinished` true at construction so the caller's build-then-guard
    /// keeps them on the menu (the v1.15 empty-pool lesson).
    ///
    /// Like `makeSentence` it is handed no `ReviewStore`: a sentence run counts mistakes
    /// across a whole sentence, so it must not be able to reach the real SM-2 schedule even
    /// if `RunCompletion`'s gate were ever loosened.
    public static func makeSentence(
        ids: [String],
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = sentenceEntries(ids: ids, vocab: vocab)
        DeckRandomness.shuffle(&pool)
        return sentenceSession(from: Array(pool.prefix(max(5, config.newWordCount))),
                               config: config, now: now)
    }

    /// Builds a sentence run from the words whose SRS review is due (PLAN-V1.21 §B), so the
    /// run doubles as review reading even though — like every sentence run — it writes no SRS.
    ///
    /// The due query filters on "has a typeable sentence" rather than filtering afterwards,
    /// for the same reason `make` filters on "still resolves": asking for `limit` cards and
    /// then dropping most of them returns a run shorter than the badge promised.
    public static func makeSentence(
        due review: ReviewStore,
        on date: Date = Date(),
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        let ids = review.dueCards(
            on: date,
            limit: max(5, config.newWordCount),
            resolves: { vocab.entry(id: $0)?.isTypeableSentence == true }
        ).map(\.id)
        return makeSentence(ids: ids, vocab: vocab, config: config, now: now)
    }

    /// How many due cards could carry a sentence right now — the menu's honest count.
    public static func dueSentenceCount(
        review: ReviewStore,
        on date: Date = Date(),
        vocab: VocabStore = .shared
    ) -> Int {
        review.dueCount(on: date, resolves: { vocab.entry(id: $0)?.isTypeableSentence == true })
    }

    /// Builds a DICTATION run (PLAN-V1.21 §A): the sentence is spoken, not shown, and the
    /// target is the same `exKana` sentence mode types.
    ///
    /// The pool is narrower than sentence mode's by design. A dictation item is only honest
    /// if the audio a learner hears matches the answer they are graded against, and the
    /// synthesizer resolves a kanji sentence's readings by itself — it agrees with `exKana`
    /// most of the time and not always. `DictationSafety` carries the ids where a measured
    /// comparison said it does not; they stay in sentence mode, where the reading is shown
    /// rather than spoken, and are simply never offered here. A smaller honest set is the
    /// same call that was made for `exKana` itself.
    public static func makeDictation(
        vocab: VocabStore = .shared,
        excluding excluded: Set<String> = DictationSafety.excludedIDs,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = vocab.ordered(level: config.level)
            .filter { $0.isTypeableSentence && !excluded.contains($0.id) }
        // No whole-corpus fallback: an empty level pool must leave the run empty so the
        // caller's build-then-guard can say so, rather than quietly drilling another level.
        DeckRandomness.shuffle(&pool)
        return sentenceSession(from: Array(pool.prefix(max(5, config.newWordCount))),
                               config: config, mode: .dictation, now: now)
    }

    /// The entries from `ids` a DICTATION run may use: a typeable sentence, and one the
    /// synthesizer was not measured to read differently from it.
    ///
    /// Two filters stack, and the second is invisible from the first. A word can have a
    /// perfectly good sentence and still be unusable here — which is why the count the menu
    /// shows for dictation has to be its own number and not the sentence one. "20 words, 14
    /// sentences, 11 you can hear" is three facts, and only the last one describes the run
    /// the learner is about to get.
    public static func dictationEntries(
        ids: [String],
        vocab: VocabStore = .shared,
        excluding excluded: Set<String> = DictationSafety.excludedIDs
    ) -> [VocabEntry] {
        sentenceEntries(ids: ids, vocab: vocab).filter { !excluded.contains($0.id) }
    }

    /// Builds a dictation run from a chosen set of vocab ids — a saved list, or the due
    /// stack (PLAN-V1.22 §A). Never padded, for the reason `makeSentence(ids:)` is not: the
    /// ids ARE the request, and a learner who asked to hear their own list and got two of
    /// somebody else's cannot tell which two.
    public static func makeDictation(
        ids: [String],
        vocab: VocabStore = .shared,
        excluding excluded: Set<String> = DictationSafety.excludedIDs,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var pool = dictationEntries(ids: ids, vocab: vocab, excluding: excluded)
        DeckRandomness.shuffle(&pool)
        return sentenceSession(from: Array(pool.prefix(max(5, config.newWordCount))),
                               config: config, mode: .dictation, now: now)
    }

    /// Builds a dictation run over the words whose review is due. Asks the store for cards
    /// that can carry a dictation prompt rather than asking for five and discarding four.
    public static func makeDictation(
        due review: ReviewStore,
        on date: Date = Date(),
        vocab: VocabStore = .shared,
        excluding excluded: Set<String> = DictationSafety.excludedIDs,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        let ids = review.dueCards(
            on: date,
            limit: max(5, config.newWordCount),
            resolves: { id in
                !excluded.contains(id) && vocab.entry(id: id)?.isTypeableSentence == true
            }
        ).map(\.id)
        return makeDictation(ids: ids, vocab: vocab, excluding: excluded, config: config, now: now)
    }

    /// How many due cards could carry a dictation prompt right now — smaller than the
    /// sentence count, and the menu must show this one.
    public static func dueDictationCount(
        review: ReviewStore,
        on date: Date = Date(),
        vocab: VocabStore = .shared,
        excluding excluded: Set<String> = DictationSafety.excludedIDs
    ) -> Int {
        review.dueCount(on: date, resolves: { id in
            !excluded.contains(id) && vocab.entry(id: id)?.isTypeableSentence == true
        })
    }

    /// Wraps chosen entries as sentence-typing cards. The surface stays the KANJI sentence
    /// (that is what the learner reads while typing) and the id stays the real entry's, so
    /// the results screen can still say which word each sentence was teaching.
    private static func sentenceSession(
        from entries: [VocabEntry],
        config: Config,
        mode: GameMode = .sentence,
        now: @escaping () -> Date
    ) -> GameSession {
        let words = entries.map { entry in
            VocabEntry(
                id: entry.id,
                surface: entry.exampleJP ?? entry.surface,
                kana: entry.exampleKana ?? entry.kana,
                partsOfSpeech: ["sentence"],
                jlpt: entry.jlpt,
                meanings: entry.meanings,
                exampleJP: entry.exampleJP,
                exampleEN: entry.exampleEN,
                exampleZH: entry.exampleZH,
                exampleKana: entry.exampleKana,
                exampleTokens: entry.exampleTokens
            )
        }
        var sentenceConfig = config
        sentenceConfig.mode = mode
        return GameSession(words: words, config: sentenceConfig, now: now)
    }

    /// Builds a session by mixing due review words with new words from the store.
    public static func make(
        config: Config = .init(),
        vocab: VocabStore = .shared,
        review: ReviewStore = ReviewStore(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        // Ask for cards that still resolve, rather than asking for all of them and dropping
        // the rest — otherwise a run silently returns fewer words than the badge promised.
        let dueWords = review.dueCards(on: now(), limit: config.reviewWordCount,
                                       resolves: vocab.resolvesID)
            .compactMap { vocab.entry(id: $0.id) }
        let seen = Set(review.cards.keys)
        let newWords = vocab.ordered(level: config.level)
            .filter { !seen.contains($0.id) }
            .prefix(config.newWordCount)
        var words = dueWords + Array(newWords)
        DeckRandomness.shuffle(&words)
        return GameSession(words: words, review: review, config: config, now: now)
    }

    /// Builds a journey-mode run from a saved-words deck (the user's curated
    /// vocab ids). Ids that no longer resolve are skipped; the deck is shuffled.
    /// Outcomes count toward SRS like a normal run.
    public static func makeSaved(
        ids: [String],
        vocab: VocabStore = .shared,
        review: ReviewStore = ReviewStore(),
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var words = ids.compactMap { vocab.entry(id: $0) }
        DeckRandomness.shuffle(&words)
        var savedConfig = config
        savedConfig.mode = .journey
        return GameSession(words: words, review: review, config: savedConfig, now: now)
    }

    /// Builds a **weak-words cram** from the user's hardest reviewed words: the same
    /// journey loop, but it records NO SRS (`recordsSRS = false`) — a cram must not
    /// touch the SM-2 schedule (PLAN-V1.7 §B). Ids that no longer resolve are skipped.
    /// No `ReviewStore` is passed in: nothing is recorded, so the run can't reach the
    /// real store at all (the red line is structural at the session level).
    public static func makeWeak(
        ids: [String],
        vocab: VocabStore = .shared,
        config: Config = .init(),
        now: @escaping () -> Date = Date.init
    ) -> GameSession {
        var words = ids.compactMap { vocab.entry(id: $0) }
        DeckRandomness.shuffle(&words)
        var weakConfig = config
        weakConfig.mode = .journey
        weakConfig.recordsSRS = false
        return GameSession(words: words, config: weakConfig, now: now)
    }

    // MARK: Derived state for the UI

    public var currentKana: String? { current?.kana }
    public var currentSurface: String? { current?.surface }
    public var currentRomaji: String? { current?.romaji }
    public var currentGloss: String? { current?.gloss(for: config.languageCode) }
    public var mode: GameMode { config.mode }
    /// The full ordered word list of this run (for passage rendering in Practice).
    public var wordList: [VocabEntry] { queue }
    public var currentLevelLabel: String { current?.jlpt.label ?? "" }
    public var currentExampleJP: String? { current?.exampleJP }
    /// Surface/reading pairs for furigana over the example sentence.
    public var currentExampleTokens: [[String]]? { current?.exampleTokens }
    public var currentExampleTranslation: String? { current?.exampleTranslation(for: config.languageCode) }
    public var typedRomaji: String { matcher?.typedRomaji ?? "" }
    public var expectedNextCharacters: Set<Character> { matcher?.expectedNextCharacters ?? [] }
    public var completedKanaCount: Int { matcher?.completedKanaCount ?? 0 }
    public var wordCount: Int { queue.count }
    public var accuracy: Double {
        totalKeystrokes == 0 ? 1 : Double(correctKeystrokes) / Double(totalKeystrokes)
    }
    public var progress: Double {
        queue.isEmpty ? 1 : Double(wordsCompleted) / Double(queue.count)
    }

    // MARK: Input

    /// Feeds one keystroke to the current word.
    @discardableResult
    public func input(_ character: Character) -> InputResult {
        guard !isFinished, var matcher else { return .rejected }
        totalKeystrokes += 1
        let result = matcher.input(character)
        self.matcher = matcher
        switch result {
        case .rejected:
            currentMistakes += 1
            combo = 0
            if config.assistance == .afterStruggle, config.mode != .timeAttack, !currentRevealed,
               let m = self.matcher {
                let state = StruggleDetector.StateKey(
                    wordIndex: index, kanaIndex: m.completedKanaCount, acceptedRomaji: m.typedRomaji)
                let attempts = struggle.record(Character(character.lowercased()),
                                               at: state, time: now())
                if attempts >= Self.struggleOfferThreshold { assistanceOffered = true }
            }
            // Record WHAT was refused, not just that something was (v1.15). Everything here
            // was already on hand at this instant and was being thrown away, which is why the
            // app could count a learner's mistakes but never explain one. In memory, this run
            // only — see MistakeTrace on why a keystroke log goes no further than that.
            if let kana = current?.kana {
                mistakes.record(MistakeEvent(
                    targetKana: kana,
                    entryID: current?.id,
                    acceptedRomaji: matcher.typedRomaji,
                    rejected: Character(character.lowercased()),
                    expectedNext: matcher.expectedNextCharacters,
                    kanaIndex: matcher.completedKanaCount,
                    order: mistakes.count + mistakes.dropped))
            }
        case .accepted:
            correctKeystrokes += 1
            struggle.reset()
            assistanceOffered = false
        case .completed:
            correctKeystrokes += 1
            completeCurrentWord()
        }
        return result
    }

    /// Reveals the romaji answer for the current word. Counts as a hint: it
    /// breaks the combo and the word will score minimally / count as an SRS lapse.
    public func revealHint() {
        currentRevealed = true
        assistanceOffered = false
        struggle.reset()
        combo = 0
    }

    /// Records that the current sentence was played again. Deliberately NOT scored and not
    /// an SRS signal: charging for replays would train a learner to guess rather than listen,
    /// which is the opposite of what dictation is for.
    public func noteReplay() {
        replays += 1
        currentReplays += 1
    }

    /// A pause or backgrounding makes the struggle signal stale: the learner had time to
    /// think, so the count starts over. (v1.16 §A.)
    public func resetStruggle() {
        struggle.reset()
        assistanceOffered = false
    }

    /// The rider stopped typing because the app said so — pause overlay, a sheet over the
    /// game, or the app leaving the foreground. The same three signals that already stop the
    /// ride's `RunClock`; before v1.31 they stopped the ride's clock and not the word's, so a
    /// word interrupted by any of them was graded on time the rider was not there for.
    public func pauseTyping() { promptClock.pause(at: now()) }

    /// The rider resumed. Idempotent, and ignored when not paused.
    public func resumeTyping() { promptClock.resume(at: now()) }

    /// Whether the word clock is currently stopped. Exposed so a test can assert the app's
    /// three signals actually reach the session, rather than asserting that the method exists.
    public var isTypingPaused: Bool { promptClock.isPaused }

    /// Gives up on the current word, recording it as not completed, and advances.
    public func skip() {
        if let entry = current {
            // Gate ONLY the SRS write on recordsSRS (a cram must not touch SM-2);
            // lapsedEntries still collects so the review-these feedback works.
            if config.recordsSRS {
                review.record(
                    entryID: entry.id,
                    outcome: TypingOutcome(completed: false, mistakes: currentMistakes),
                    on: now()
                )
            }
            lapsedEntries.append(entry)
        }
        combo = 0
        advance()
    }

    // MARK: Internals

    private func loadCurrent() {
        if index < queue.count {
            current = queue[index]
            matcher = KanaInputMatcher(target: queue[index].kana)
            promptClock.restart(at: now())
        } else {
            current = nil
            matcher = nil
            isFinished = true
        }
    }

    private func completeCurrentWord() {
        guard let entry = current else { return }
        wordsCompleted += 1
        // A revealed word doesn't build the combo (and scores minimally).
        if currentRevealed {
            combo = 0
        } else {
            combo += 1
            maxCombo = max(maxCombo, combo)
        }

        let ratio = durationRatio(for: entry)
        let outcome = TypingOutcome(
            completed: true,
            mistakes: currentMistakes,
            usedHint: currentRevealed,
            durationRatio: ratio
        )
        if config.recordsSRS {
            review.record(entryID: entry.id, outcome: outcome, on: now())
        }
        if SRSCard.quality(from: outcome) < 3 { lapsedEntries.append(entry) }

        score += currentRevealed ? 10 : wordScore(entry: entry, mistakes: currentMistakes, combo: combo)
        distanceMeters += Double(entry.kana.count) * 10

        advance()
    }

    private func advance() {
        index += 1
        currentMistakes = 0
        currentReplays = 0
        currentRevealed = false
        struggle.reset()
        assistanceOffered = false
        loadCurrent()
    }

    private func durationRatio(for entry: VocabEntry) -> Double {
        let elapsed = promptClock.elapsed(at: now())
        let baseline = Double(max(1, entry.kana.count)) * config.secondsPerKanaBaseline
        return baseline > 0 ? elapsed / baseline : 1
    }

    private func wordScore(entry: VocabEntry, mistakes: Int, combo: Int) -> Int {
        let base = 100 + entry.kana.count * 5
        let penalty = mistakes * 15
        let comboMultiplier = 1.0 + Double(min(combo, 10)) * 0.1   // up to 2× at a 10-combo
        return max(10, Int(Double(max(0, base - penalty)) * comboMultiplier))
    }
}
