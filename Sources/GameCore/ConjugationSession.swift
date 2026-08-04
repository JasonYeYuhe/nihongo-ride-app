import Foundation
import Observation
import RomajiKana
import VocabKit
import ConjugationKit
import ReviewKit   // TypingOutcome (value type only — the session still holds NO ReviewStore)

// MARK: vc → VerbClass mapping (lives in GameCore so VocabKit keeps no CK dependency)

extension VocabEntry {
    /// The derived conjugation class, mapped from the opaque `vc` string written by the
    /// B1 enrichment. nil when the word has no class (non-verb, ambiguous, or withheld).
    /// The mapping lives here, in GameCore, so VocabKit needs no ConjugationKit edge
    /// (PLAN-V1.6 §B1 / §4).
    public var verbClass: VerbClass? { vc.flatMap(VerbClass.init(rawValue:)) }

    /// Whether this entry can be drilled in the conjugation mode (has a usable class).
    public var isConjugable: Bool { verbClass != nil }
}

// MARK: ConjugationPrompt

/// One conjugation challenge: show the dictionary form, name the `targetForm`, and the
/// learner types `conjugatedKana`. `conjugatedKana` is computed once at build time by
/// the ``Conjugator`` and is **transient** — it is NEVER persisted as a `VocabEntry`
/// (red line §8.5). The dictionary `surface`/`dictKana` come from a real `VocabEntry`,
/// but the conjugated answer does not round-trip into the vocab store.
public struct ConjugationPrompt: Identifiable, Sendable, Equatable {
    /// Stable id = source entry id + form raw value (so a word can appear under >1 form).
    public let id: String
    /// Dictionary surface (kanji where standard), e.g. "食べる".
    public let surface: String
    /// Dictionary reading, e.g. "たべる".
    public let dictKana: String
    /// Meaning gloss in the UI language, for the prompt card.
    public let gloss: String
    /// The verb's conjugation class.
    public let verbClass: VerbClass
    /// The form to produce.
    public let targetForm: ConjugationForm
    /// The expected answer kana — the typing target, e.g. "たべて".
    public let conjugatedKana: String

    public init(
        sourceID: String,
        surface: String,
        dictKana: String,
        gloss: String,
        verbClass: VerbClass,
        targetForm: ConjugationForm,
        conjugatedKana: String
    ) {
        self.id = "\(sourceID)#\(targetForm.rawValue)"
        self.surface = surface
        self.dictKana = dictKana
        self.gloss = gloss
        self.verbClass = verbClass
        self.targetForm = targetForm
        self.conjugatedKana = conjugatedKana
    }

    /// Builds a prompt from a vocab entry + target form, computing the answer with the
    /// engine. Returns nil if the entry has no class or the engine can't conjugate it
    /// (so the caller withholds it from the queue rather than guessing).
    public init?(entry: VocabEntry, form: ConjugationForm, languageCode: String) {
        guard let cls = entry.verbClass,
              let answer = Conjugator.conjugate(kana: entry.kana, verbClass: cls, lemma: entry.surface, form: form)
        else { return nil }
        self.init(
            sourceID: entry.id,
            surface: entry.surface,
            dictKana: entry.kana,
            gloss: entry.gloss(for: languageCode),
            verbClass: cls,
            targetForm: form,
            conjugatedKana: answer
        )
    }

    /// Bilingual label for the target form, e.g. "て形 / Te-form".
    public func formLabel(for languageCode: String) -> String {
        switch languageCode {
        case "ja": return targetForm.japaneseLabel
        case "zh": return targetForm.label(for: "zh")
        default:   return "\(targetForm.japaneseLabel) / \(targetForm.englishLabel)"
        }
    }
}

// MARK: ConjugationSession

/// Drives one conjugation drill: a queue of ``ConjugationPrompt``s, the current prompt's
/// matcher, and scoring/combo. **It holds no `ReviewStore` and no `VocabStore`** — by
/// construction it cannot write SRS or vocab state. It mirrors the parts of ``GameSession``
/// the playing screen observes, so the same `.playing` view path can drive it.
///
/// v1.8 adds an optional ``onOutcome`` callback: when set, the session *emits* a
/// `(ConjugationPrompt, TypingOutcome)` on each completed/skipped prompt — but it still
/// holds no store, so the "session never writes SRS" red line stays structural. The app
/// (AppModel) owns the `ConjugationReviewStore` and does the actual write in the closure;
/// the default (nil) keeps the pre-v1.8 zero-side-effect behavior.
@Observable
public final class ConjugationSession {
    public struct Config: Sendable {
        public var languageCode: String
        public var assistance: AssistanceMode
        /// How many prompts in a run.
        public var promptCount: Int
        /// JLPT level to draw verbs from; nil mixes all levels.
        public var level: JLPTLevel?
        /// Which forms to drill.
        public var forms: [ConjugationForm]

        public init(
            languageCode: String = "en",
            assistance: AssistanceMode = .always,
            promptCount: Int = 12,
            level: JLPTLevel? = nil,
            forms: [ConjugationForm] = ConjugationForm.allCases
        ) {
            self.languageCode = languageCode
            self.assistance = assistance
            self.promptCount = promptCount
            self.level = level
            self.forms = forms.isEmpty ? ConjugationForm.allCases : forms
        }

        /// Sets ``forms`` from persisted raw `ConjugationForm` values (e.g.
        /// `AppSettings.conjugationForms`). Unknown raw values are tolerantly dropped
        /// (`compactMap`), and an empty / all-unknown selection falls back to all forms
        /// — so the app never has to import ConjugationKit to pick forms, and a stale
        /// stored value can never strand the drill with zero forms (PLAN-V1.7 §C).
        public mutating func setForms(rawValues: [String]) {
            let parsed = rawValues.compactMap(ConjugationForm.init(rawValue:))
            forms = parsed.isEmpty ? ConjugationForm.allCases : parsed
        }
    }

    // MARK: Public state (observed by the UI)

    public private(set) var current: ConjugationPrompt?
    public private(set) var index = 0
    public private(set) var score = 0
    public private(set) var combo = 0
    public private(set) var maxCombo = 0
    public private(set) var promptsCompleted = 0
    public private(set) var totalKeystrokes = 0
    public private(set) var correctKeystrokes = 0
    public private(set) var isFinished = false
    /// Same policy and same struggle machinery as GameSession (v1.16 §A). The drill's
    /// "hint" is the conjugated answer itself, so the reveal costs are identical in kind.
    public var assistance: AssistanceMode { config.assistance }
    public var romajiVisible: Bool { assistance == .always || currentRevealed }
    public private(set) var assistanceOffered = false
    public var isRevealed: Bool { currentRevealed }
    private var struggle = StruggleDetector()
    private let now: () -> Date

    /// Optional per-prompt outcome sink (v1.8 §B). Fired once per completed or skipped
    /// prompt with the prompt and its `TypingOutcome`. Default nil = the session emits
    /// nothing (pre-v1.8 MVP behavior). The session itself still writes no SRS — the app
    /// wires this to its `ConjugationReviewStore`. Non-throwing by design; the app closure
    /// swallows/logs its own persistence errors so a bad write never crashes the drill.
    public var onOutcome: ((ConjugationPrompt, TypingOutcome) -> Void)?

    public let config: Config

    private let queue: [ConjugationPrompt]
    private var matcher: KanaInputMatcher?
    private var currentMistakes = 0
    private var currentRevealed = false

    // MARK: Init

    /// Designated initializer with an explicit prompt list (used by tests + the builder).
    public init(prompts: [ConjugationPrompt], config: Config = .init(),
                now: @escaping () -> Date = Date.init) {
        self.queue = prompts
        self.config = config
        self.now = now
        loadCurrent()
    }

    // MARK: Derived state for the UI (mirrors GameSession naming)

    public var currentKana: String? { current?.conjugatedKana }
    public var currentSurface: String? { current?.surface }
    public var currentDictKana: String? { current?.dictKana }
    public var currentGloss: String? { current?.gloss }
    public var currentFormLabel: String? { current.map { $0.formLabel(for: config.languageCode) } }
    public var currentRomaji: String? { current.map { KanaRomanizer.romaji(for: $0.conjugatedKana) } }
    public var typedRomaji: String { matcher?.typedRomaji ?? "" }
    public var expectedNextCharacters: Set<Character> { matcher?.expectedNextCharacters ?? [] }
    public var completedKanaCount: Int { matcher?.completedKanaCount ?? 0 }
    public var promptCount: Int { queue.count }
    public var accuracy: Double {
        totalKeystrokes == 0 ? 1 : Double(correctKeystrokes) / Double(totalKeystrokes)
    }
    public var progress: Double {
        queue.isEmpty ? 1 : Double(promptsCompleted) / Double(queue.count)
    }

    // MARK: Input

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
            if config.assistance == .afterStruggle, !currentRevealed, let m = self.matcher {
                let state = StruggleDetector.StateKey(
                    wordIndex: index, kanaIndex: m.completedKanaCount, acceptedRomaji: m.typedRomaji)
                if struggle.record(Character(character.lowercased()), at: state, time: now())
                    >= GameSession.struggleOfferThreshold {
                    assistanceOffered = true
                }
            }
        case .accepted:
            correctKeystrokes += 1
            struggle.reset()
            assistanceOffered = false
        case .completed:
            correctKeystrokes += 1
            completeCurrent()
        }
        return result
    }

    /// Reveals the answer for the current prompt: breaks the combo, scores minimally.
    public func revealHint() {
        currentRevealed = true
        assistanceOffered = false
        struggle.reset()
        combo = 0
    }

    public func resetStruggle() {
        struggle.reset()
        assistanceOffered = false
    }

    /// Gives up on the current prompt and advances. Emits an incomplete outcome (if a sink
    /// is set) — the session still holds no store; the app decides what to persist.
    public func skip() {
        combo = 0
        if let prompt = current {
            onOutcome?(prompt, TypingOutcome(completed: false, mistakes: currentMistakes, usedHint: currentRevealed))
        }
        advance()
    }

    // MARK: Internals (note: NO ReviewStore held — outcomes only EMIT via onOutcome; the
    // session persists nothing itself, so "session writes no SRS" stays structural)

    private func loadCurrent() {
        if index < queue.count {
            current = queue[index]
            matcher = KanaInputMatcher(target: queue[index].conjugatedKana)
        } else {
            current = nil
            matcher = nil
            isFinished = true
        }
    }

    private func completeCurrent() {
        promptsCompleted += 1
        if currentRevealed {
            combo = 0
        } else {
            combo += 1
            maxCombo = max(maxCombo, combo)
        }
        score += currentRevealed ? 10 : promptScore(mistakes: currentMistakes, combo: combo)
        if let prompt = current {
            onOutcome?(prompt, TypingOutcome(completed: true, mistakes: currentMistakes, usedHint: currentRevealed))
        }
        advance()
    }

    private func advance() {
        index += 1
        currentMistakes = 0
        currentRevealed = false
        struggle.reset()
        assistanceOffered = false
        loadCurrent()
    }

    private func promptScore(mistakes: Int, combo: Int) -> Int {
        let base = 100
        let penalty = mistakes * 15
        let comboMultiplier = 1.0 + Double(min(combo, 10)) * 0.1
        return max(10, Int(Double(max(0, base - penalty)) * comboMultiplier))
    }
}

// MARK: Form options (menu facade — keeps the app free of a ConjugationKit import)

/// One selectable conjugation form for the menu form-picker. Carries raw value +
/// localized labels so the app renders the picker without importing ConjugationKit
/// (the vc/form types stay behind GameCore, per the v1.6 boundary).
public struct ConjugationFormOption: Identifiable, Sendable, Equatable {
    /// The `ConjugationForm` raw value — the token stored in `AppSettings.conjugationForms`.
    public let rawValue: String
    /// Ultra-short tag for the chip (e.g. "て", "なかった").
    public let shortLabel: String
    /// Localized full label for accessibility (e.g. "Te-form", "ます形（敬体）").
    public let accessibilityLabel: String
    public var id: String { rawValue }
}

extension ConjugationSession {
    /// Bridges an app-provided, String-token weak-form picker into a `chooseForm` closure
    /// for ``make``/``makeReview``. This lets the app bias form selection using its
    /// `ConjugationReviewStore` WITHOUT importing ConjugationKit (it speaks only form
    /// raw-value tokens) AND without GameCore importing ConjugationReviewKit (red line §6):
    /// the store stays entirely behind the app's closure. `weakBiasedPick` returns a chosen
    /// token, or nil to fall back to a uniform random form. An unknown / out-of-set token
    /// also falls back, so a stale token can never strand form selection.
    public static func weightedFormChooser(
        weakBiasedPick: @escaping (_ entryID: String, _ formTokens: [String]) -> String?
    ) -> (String, [ConjugationForm]) -> ConjugationForm {
        { entryID, forms in
            let tokens = forms.map(\.rawValue)
            if let picked = weakBiasedPick(entryID, tokens),
               let f = ConjugationForm(rawValue: picked), forms.contains(f) {
                return f
            }
            return forms.randomElement() ?? .polite
        }
    }

    /// All drillable forms in canonical order, with labels for the menu picker.
    public static func formOptions(languageCode: String) -> [ConjugationFormOption] {
        ConjugationForm.allCases.map {
            ConjugationFormOption(rawValue: $0.rawValue,
                                  shortLabel: $0.shortLabel,
                                  accessibilityLabel: $0.label(for: languageCode))
        }
    }
}

// MARK: Building a run from the vocab pool

extension ConjugationSession {

    /// The conjugation pool: vocab entries that carry a usable verb class, optionally
    /// filtered by level. Used to build runs AND to gate the menu entry by pool size.
    public static func pool(vocab: VocabStore = .shared, level: JLPTLevel? = nil) -> [VocabEntry] {
        vocab.entries.filter { $0.isConjugable && (level == nil || $0.jlpt == level) }
    }

    /// How many distinct verbs are available to drill (for menu gating).
    public static func playableCount(vocab: VocabStore = .shared, level: JLPTLevel? = nil) -> Int {
        pool(vocab: vocab, level: level).count
    }

    /// Builds a run: pick `promptCount` verbs from the pool, assign each a target form,
    /// compute the answer with the engine. Verbs the engine can't conjugate are skipped
    /// (resolve-then-guard). If the pool is empty the session is immediately finished, so
    /// the UI can guard against a dead empty screen (PLAN-V1.6 §4 空池守卫).
    public static func make(
        vocab: VocabStore = .shared,
        config: Config = .init(),
        pick: ([VocabEntry], Int) -> [VocabEntry] = { entries, n in Array(entries.shuffled().prefix(n)) },
        chooseForm: (String, [ConjugationForm]) -> ConjugationForm = { _, forms in forms.randomElement() ?? .polite }
    ) -> ConjugationSession {
        let candidates = pool(vocab: vocab, level: config.level)
        let chosen = pick(candidates, config.promptCount)
        var prompts: [ConjugationPrompt] = []
        for entry in chosen {
            let form = chooseForm(entry.id, config.forms)
            if let p = ConjugationPrompt(entry: entry, form: form, languageCode: config.languageCode) {
                prompts.append(p)
            }
        }
        return ConjugationSession(prompts: prompts, config: config)
    }

    /// Builds a **due-review** run (v1.8 §B): the caller's due `(entryID, formToken)` pairs
    /// first (in the given, soonest-first order), then fills up to `promptCount` with fresh
    /// (verb, form) prompts not already queued. GameCore takes only plain strings — `due`
    /// carries no ConjugationReviewKit type, so GameCore never imports it (red line §6).
    ///
    /// `formToken` is a `ConjugationForm` raw value; a due pair whose entry is unresolvable,
    /// unconjugable, or whose token is unknown is skipped (resolve-then-guard). An empty
    /// result finishes the session immediately so the UI can guard the empty screen.
    public static func makeReview(
        due: [(entryID: String, formToken: String)],
        vocab: VocabStore = .shared,
        config: Config = .init(),
        fillPick: ([VocabEntry], Int) -> [VocabEntry] = { entries, n in Array(entries.shuffled().prefix(n)) },
        chooseForm: (String, [ConjugationForm]) -> ConjugationForm = { _, forms in forms.randomElement() ?? .polite }
    ) -> ConjugationSession {
        var prompts: [ConjugationPrompt] = []
        var seen = Set<String>()

        // 1) Due prompts, in order, capped at promptCount.
        for pair in due {
            if prompts.count >= config.promptCount { break }
            guard let entry = vocab.entry(id: pair.entryID),
                  let form = ConjugationForm(rawValue: pair.formToken),
                  let p = ConjugationPrompt(entry: entry, form: form, languageCode: config.languageCode)
            else { continue }
            if seen.insert(p.id).inserted { prompts.append(p) }
        }

        // 2) Fill the remainder with fresh prompts not already queued. Over-draw candidates
        //    so dedup against the due set can't leave the run short.
        if prompts.count < config.promptCount {
            let remaining = config.promptCount - prompts.count
            let candidates = pool(vocab: vocab, level: config.level)
            for entry in fillPick(candidates, remaining * 2 + 16) {
                if prompts.count >= config.promptCount { break }
                let form = chooseForm(entry.id, config.forms)
                guard let p = ConjugationPrompt(entry: entry, form: form, languageCode: config.languageCode) else { continue }
                if seen.insert(p.id).inserted { prompts.append(p) }
            }
        }

        return ConjugationSession(prompts: prompts, config: config)
    }
}
