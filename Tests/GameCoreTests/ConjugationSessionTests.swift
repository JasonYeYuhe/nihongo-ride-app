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
        #expect(satsu.verbClass == nil)
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
}
