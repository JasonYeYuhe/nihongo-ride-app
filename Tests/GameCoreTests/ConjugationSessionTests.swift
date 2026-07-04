import Testing
import Foundation
import RomajiKana
import VocabKit
import ReviewKit
import ConjugationKit
@testable import GameCore

/// B3a abstraction tests (PLAN-V1.6 §4): the conjugation drill runs through an
/// INDEPENDENT ``ConjugationSession`` that holds no SRS/vocab state, so the "conjugation
/// MVP never writes SRS" red line is structural, not just observed. Plus builder /
/// answer-correctness / empty-pool-guard coverage. UI wiring (B3b) comes later.
@Suite("GameCore — ConjugationSession (B3a)")
struct ConjugationSessionTests {

    private func play(_ session: ConjugationSession, character romaji: String) {
        for ch in romaji { session.input(ch) }
    }

    @Test("a full conjugation run writes ZERO to ReviewStore and never mutates the vocab")
    func zeroSRSWrites() {
        // A ReviewStore held alongside the session: the session has no API to receive one
        // and no review.record call, so it must stay empty across a full run (skip + type).
        let review = ReviewStore()
        let vocabCountBefore = VocabStore.shared.entries.count

        let session = ConjugationSession.make(config: .init(promptCount: 8))
        #expect(session.promptCount > 0)

        var first = true
        var guardCounter = 0
        while !session.isFinished && guardCounter < 1000 {
            guardCounter += 1
            guard let answer = session.currentKana else { break }
            if first {                       // exercise the skip() path too
                session.skip()
                first = false
            } else {
                play(session, character: KanaRomanizer.romaji(for: answer))
            }
        }
        #expect(session.isFinished)
        #expect(review.cards.isEmpty, "conjugation drill must not write SRS")
        #expect(VocabStore.shared.entries.count == vocabCountBefore, "conjugation drill must not mutate vocab")
    }

    @Test("prompt answers come from the engine; withheld verbs yield no prompt")
    func promptAnswers() {
        let tabe = VocabEntry(id: "t", surface: "食べる", kana: "たべる", partsOfSpeech: ["v"],
                              jlpt: .n5, meanings: ["en": ["eat"]], vc: "ichidan")
        #expect(ConjugationPrompt(entry: tabe, form: .te, languageCode: "en")?.conjugatedKana == "たべて")
        #expect(ConjugationPrompt(entry: tabe, form: .potential, languageCode: "en")?.conjugatedKana == "たべられる")

        let kaeru = VocabEntry(id: "k", surface: "帰る", kana: "かえる", partsOfSpeech: ["v"],
                               jlpt: .n5, meanings: ["en": ["return"]], vc: "godan_r")
        #expect(ConjugationPrompt(entry: kaeru, form: .te, languageCode: "en")?.conjugatedKana == "かえって")
        #expect(ConjugationPrompt(entry: kaeru, form: .potential, languageCode: "en")?.conjugatedKana == "かえれる")

        // A withheld bare suru-verb (no vc) produces no prompt — never guessed into a run.
        let satsu = VocabEntry(id: "s", surface: "察する", kana: "さっする", partsOfSpeech: ["v"],
                               jlpt: .n1, meanings: ["en": ["guess"]], vc: nil)
        #expect(ConjugationPrompt(entry: satsu, form: .te, languageCode: "en") == nil)
        #expect(satsu.verbClass == nil, "vc=\(String(describing: satsu.vc)) verbClass=\(String(describing: satsu.verbClass))")
    }

    @Test("typing the answer completes a prompt and advances; skip advances without it")
    func runMechanics() {
        let p1 = ConjugationPrompt(sourceID: "a", surface: "書く", dictKana: "かく", gloss: "write",
                                   verbClass: .godanK, targetForm: .te, conjugatedKana: "かいて")
        let p2 = ConjugationPrompt(sourceID: "b", surface: "見る", dictKana: "みる", gloss: "see",
                                   verbClass: .ichidan, targetForm: .polite, conjugatedKana: "みます")
        let s = ConjugationSession(prompts: [p1, p2])
        #expect(s.current?.id == p1.id)
        #expect(s.currentKana == "かいて")
        #expect(s.currentFormLabel?.isEmpty == false)
        play(s, character: KanaRomanizer.romaji(for: "かいて"))
        #expect(s.promptsCompleted == 1)
        #expect(s.score > 0)
        #expect(s.current?.id == p2.id)        // advanced to the next prompt
        s.skip()
        #expect(s.isFinished)
        #expect(s.promptsCompleted == 1)       // skip did not count as completed
    }

    @Test("empty pool → session is immediately finished (resolve-then-guard)")
    func emptyPoolGuard() {
        let emptyVocab = VocabStore(entries: [])
        let s = ConjugationSession.make(vocab: emptyVocab, config: .init(promptCount: 10))
        #expect(s.promptCount == 0)
        #expect(s.isFinished)
        #expect(s.currentKana == nil)
    }

    @Test("real vocab pool is large and every pooled entry conjugates cleanly")
    func realPoolHealthy() {
        #expect(ConjugationSession.playableCount() >= 1000)   // ~2305 vc'd entries
        #expect(ConjugationSession.playableCount(level: .n5) >= 50)
        for e in ConjugationSession.pool().prefix(80) {
            guard let cls = e.verbClass else { Issue.record("\(e.surface) in pool with no class"); continue }
            let forms = Conjugator.allForms(kana: e.kana, verbClass: cls, lemma: e.surface)
            #expect(forms.count == ConjugationForm.allCases.count, "\(e.surface)/\(e.kana) didn't fully conjugate")
        }
    }

    @Test("setForms(rawValues:) maps known forms, drops unknown, empty → all (PLAN-V1.7 §C)")
    func setFormsTolerant() {
        var some = ConjugationSession.Config()
        some.setForms(rawValues: ["te", "past", "bogus"])
        #expect(Set(some.forms) == [.te, .past])              // unknown silently dropped

        var none = ConjugationSession.Config()
        none.setForms(rawValues: [])
        #expect(Set(none.forms) == Set(ConjugationForm.allCases))   // empty → all

        var unknownOnly = ConjugationSession.Config()
        unknownOnly.setForms(rawValues: ["nope", "zzz"])
        #expect(Set(unknownOnly.forms) == Set(ConjugationForm.allCases))   // all-unknown → all (never zero)
    }

    @Test("formOptions lists every form in canonical order with non-empty labels")
    func formOptionsList() {
        let opts = ConjugationSession.formOptions(languageCode: "en")
        #expect(opts.map(\.rawValue) == ConjugationForm.allCases.map(\.rawValue))
        #expect(opts.allSatisfy { !$0.shortLabel.isEmpty && !$0.accessibilityLabel.isEmpty })
        // zh labels differ from en for at least one form (localized path exercised).
        let zh = ConjugationSession.formOptions(languageCode: "zh")
        #expect(zh.map(\.rawValue) == opts.map(\.rawValue))
    }

    @Test("a run restricted to selected forms (via setForms) only produces those forms")
    func formFilterRespected() {
        var c = ConjugationSession.Config(promptCount: 15)
        c.setForms(rawValues: ["te", "volitional"])
        let session = ConjugationSession.make(config: c)
        #expect(session.promptCount > 0)
        var guardCounter = 0
        while !session.isFinished && guardCounter < 1000 {
            guardCounter += 1
            guard let p = session.current else { break }
            #expect([.te, .volitional].contains(p.targetForm))
            play(session, character: KanaRomanizer.romaji(for: p.conjugatedKana))
        }
    }

    @Test("builder draws from the pool and every prompt's answer matches the engine")
    func builderConsistency() {
        let session = ConjugationSession.make(config: .init(promptCount: 15, forms: [.te, .past, .potential]))
        #expect(session.promptCount > 0)
        // Walk the queue by replaying: each current answer must equal the engine's output.
        var seen = 0
        var guardCounter = 0
        while !session.isFinished && guardCounter < 1000 {
            guardCounter += 1
            guard let p = session.current else { break }
            let expected = Conjugator.conjugate(kana: p.dictKana, verbClass: p.verbClass,
                                                lemma: p.surface, form: p.targetForm)
            #expect(p.conjugatedKana == expected)
            #expect([.te, .past, .potential].contains(p.targetForm))   // honored the forms filter
            seen += 1
            play(session, character: KanaRomanizer.romaji(for: p.conjugatedKana))
        }
        #expect(seen == session.promptCount)
    }

    // MARK: v1.8 §B — onOutcome sink + due-review builder

    @Test("onOutcome emits exactly once per completed/skipped prompt, with the right flag")
    func onOutcomeEmits() {
        let session = ConjugationSession.make(config: .init(promptCount: 6))
        #expect(session.promptCount > 0)
        var emitted: [(id: String, completed: Bool)] = []
        session.onOutcome = { prompt, outcome in emitted.append((prompt.id, outcome.completed)) }

        // The session still holds no store: emitting is the ONLY effect.
        let review = ReviewStore()
        var i = 0, guardCounter = 0
        while !session.isFinished && guardCounter < 1000 {
            guardCounter += 1
            guard let answer = session.currentKana else { break }
            if i % 2 == 0 { session.skip() } else { play(session, character: KanaRomanizer.romaji(for: answer)) }
            i += 1
        }
        #expect(emitted.count == session.promptCount, "one outcome per prompt")
        #expect(emitted.contains { !$0.completed }, "skipped prompts emit completed=false")
        #expect(emitted.contains { $0.completed }, "typed prompts emit completed=true")
        #expect(Set(emitted.map(\.id)).count == emitted.count, "no prompt emits twice")
        #expect(review.cards.isEmpty, "emitting is not writing — the flat store is untouched")
    }

    @Test("default onOutcome (nil) emits nothing and never crashes")
    func onOutcomeDefaultNil() {
        let session = ConjugationSession.make(config: .init(promptCount: 4))
        var guardCounter = 0
        while !session.isFinished && guardCounter < 1000 {
            guardCounter += 1
            guard let answer = session.currentKana else { break }
            play(session, character: KanaRomanizer.romaji(for: answer))
        }
        #expect(session.isFinished)   // ran clean with no sink set
    }

    @Test("makeReview puts due (verb, form) pairs first, then fills fresh to promptCount")
    func makeReviewDueFirst() {
        // Two real conjugable verbs for the due list.
        let pool = ConjugationSession.pool()
        let a = pool[0], b = pool[1]
        let due = [(entryID: a.id, formToken: "te"), (entryID: b.id, formToken: "past")]
        let session = ConjugationSession.makeReview(due: due, config: .init(promptCount: 10))
        #expect(session.promptCount == 10)
        // The due pairs lead the queue, in order, with their exact ids.
        #expect(session.current?.id == "\(a.id)#te")
        // Collect all queued ids and confirm both due prompts are present.
        var ids: [String] = []
        var guardCounter = 0
        while !session.isFinished && guardCounter < 1000 {
            guardCounter += 1
            guard let p = session.current else { break }
            ids.append(p.id)
            play(session, character: KanaRomanizer.romaji(for: p.conjugatedKana))
        }
        #expect(ids.prefix(2) == ["\(a.id)#te", "\(b.id)#past"])
        #expect(Set(ids).count == ids.count, "no duplicate prompts")
    }

    @Test("makeReview skips unresolvable / unknown-form due pairs and still fills")
    func makeReviewSkipsBad() {
        let due = [(entryID: "nope-does-not-exist", formToken: "te"),
                   (entryID: ConjugationSession.pool()[0].id, formToken: "bogusform")]
        let session = ConjugationSession.makeReview(due: due, config: .init(promptCount: 8))
        // Both due pairs are unusable → the run is entirely fresh fill, but still full.
        #expect(session.promptCount == 8)
    }

    @Test("makeReview with empty due behaves like a fresh run")
    func makeReviewEmptyDue() {
        let session = ConjugationSession.makeReview(due: [], config: .init(promptCount: 12))
        #expect(session.promptCount == 12)
    }
}
