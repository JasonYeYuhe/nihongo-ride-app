import Testing
import Foundation
@testable import DiagnosticsKit
@testable import RomajiKana

/// The coach's text is instructional truth, so these check it says the right thing rather
/// than merely saying something. Both languages, because v1.14's plural bug and the on-device
/// model's Chinese failure came from the same place: a second language nobody asserted on.
/// Local copy — `RomajiKanaTests` has one but test targets don't share code, and the point
/// here is to run the coach's authored claims through the real engine.
private func typesOut(_ romaji: String, as target: String) -> Bool {
    var matcher = KanaInputMatcher(target: target)
    for c in romaji where matcher.input(c) == .rejected { return false }
    return matcher.isComplete
}

@Suite("CoachContent — the rule has to be correct in both languages")
struct CoachContentTests {

    @Test("every diagnosable pattern has advice in both languages")
    func coverage() {
        for pattern in TypingPattern.allCases where pattern != .unknown {
            for zh in [true, false] {
                let a = CoachContent.advice(for: pattern, zh: zh)
                #expect(a != nil, "\(pattern) has no \(zh ? "zh" : "en") advice")
                #expect(!(a?.title.isEmpty ?? true))
                #expect((a?.rule.count ?? 0) > 20, "\(pattern) \(zh ? "zh" : "en") rule is too thin")
            }
        }
    }

    @Test("unknown gets no advice — silence beats invented encouragement")
    func unknownSaysNothing() {
        // "Keep practicing! You're getting the hang of it." is what the on-device model
        // produced when it had nothing. The app should say nothing instead.
        #expect(CoachContent.advice(for: .unknown, zh: false) == nil)
        #expect(CoachContent.advice(for: .unknown, zh: true) == nil)
    }

    @Test("the romaji each rule TELLS you to type is actually accepted by the engine")
    func rulesAreTrue() {
        // The rules name concrete spellings. If any of them were wrong the app would be
        // teaching a wrong answer in the very screen that exists to stop that — so every
        // example in the authored text is fed to the real matcher here.
        let claims: [(String, String)] = [
            ("konnichiha", "こんにちは"),   // particle rule
            ("itte", "いって"), ("kitte", "きって"),   // sokuon rule
            ("kya", "きゃ"), ("sho", "しょ"), ("chu", "ちゅ"),   // small-ya rule
            ("shinbun", "しんぶん"),        // hepburn rule
        ]
        for (romaji, target) in claims {
            #expect(typesOut(romaji, as: target),
                    "the coach tells learners to type ‘\(romaji)’ for ‘\(target)’, and it does not work")
        }
        // And the counter-claims: the spellings the rules say are WRONG really are.
        #expect(!typesOut("konnichiwa", as: "こんにちは"))
        #expect(!typesOut("kiya", as: "きゃ"))
        #expect(!typesOut("shimbun", as: "しんぶん"))
    }

    @Test("replay points at the exact character")
    func replay() {
        var matcher = KanaInputMatcher(target: "こんにちは")
        var event: MistakeEvent?
        for c in "konnichiwa" {
            let before = matcher.typedRomaji
            let expected = matcher.expectedNextCharacters
            let idx = matcher.completedKanaCount
            if matcher.input(c) == .rejected {
                event = MistakeEvent(targetKana: "こんにちは", entryID: nil, acceptedRomaji: before,
                                     rejected: c, expectedNext: expected, kanaIndex: idx, order: 0)
                break
            }
        }
        let replay = MistakeReplay(event!)
        #expect(replay?.kana == "は")
        #expect(replay?.index == 4)
        #expect(replay?.typedPrefix == "konnichi")
        #expect(replay?.rejected == "w")
        #expect(replay?.accepted.contains("h") == true)
    }

    // MARK: drill selection

    private let deck: [(id: String, kana: String)] = [
        ("a", "こんにちは"), ("b", "いって"), ("c", "きゃく"), ("d", "しんぶん"),
        ("e", "ねこ"), ("f", "がっこう"), ("g", "しょくじ"), ("h", "ほんを"),
    ]

    @Test("drills pick words that actually exercise the pattern")
    func drills() {
        // particleSpelling is deliberately absent: its material is sentences, not words.
        // This assertion used to expect ["a", "h"] — こんにちは and ほんを — which encoded the
        // bug rather than the intent, since as single WORDS they are typed konnichiha and
        // honwo correctly first time and teach nothing about the particle. See
        // CoachDrillSourceTests.
        #expect(CoachContent.drillCandidates(for: .particleSpelling, from: deck).isEmpty)
        #expect(Set(CoachContent.drillCandidates(for: .sokuon, from: deck)) == ["b", "f"])
        #expect(Set(CoachContent.drillCandidates(for: .smallYa, from: deck)) == ["c", "g"])
        #expect(Set(CoachContent.drillCandidates(for: .hepburnM, from: deck)) == ["d"])
        #expect(CoachContent.drillCandidates(for: .unknown, from: deck).isEmpty)
    }

    @Test("hepburn drill needs ん immediately before a b/p mora, not just any ん")
    func hepburnIsSpecific() {
        // ねんまつ has ん but no b/p after it — drilling it teaches nothing about the m habit.
        let d: [(id: String, kana: String)] = [("x", "ねんまつ"), ("y", "しんぶん"), ("z", "さんぽ")]
        #expect(Set(CoachContent.drillCandidates(for: .hepburnM, from: d)) == ["y", "z"])
    }

    @Test("the drill is capped")
    func capped() {
        let many = (0..<50).map { (id: "w\($0)", kana: "いって") }
        #expect(CoachContent.drillCandidates(for: .sokuon, from: many, limit: 12).count == 12)
    }

    @Test("keyboard-mechanics patterns don't claim a deck helps")
    func drillHelpsIsHonest() {
        // Knowing that きゃ is kya is one fact. Twelve words containing きゃ does not teach it
        // twelve times better — it just costs the learner their evening.
        #expect(CoachContent.advice(for: .smallYa, zh: false)?.drillHelps == false)
        #expect(CoachContent.advice(for: .hepburnM, zh: false)?.drillHelps == false)
        // Whereas particle spelling and sokuon show up across many words and benefit from it.
        #expect(CoachContent.advice(for: .particleSpelling, zh: false)?.drillHelps == true)
        #expect(CoachContent.advice(for: .sokuon, zh: false)?.drillHelps == true)
    }
}

/// v1.15 §J — the particle drill was being built from the wrong material.
@Suite("Coach drill — the right material for each pattern")
struct CoachDrillSourceTests {

    @Test("particle spelling drills sentences; everything else drills words")
    func sources() {
        #expect(CoachContent.drillSource(for: .particleSpelling) == .passages)
        for p: TypingPattern in [.sokuon, .smallYa, .hepburnM] {
            #expect(CoachContent.drillSource(for: p) == .words, "\(p) should drill words")
        }
    }

    @Test("a word drill for particle spelling returns nothing, on purpose")
    func wordsCannotDrillParticles() {
        // The bug this closes: はな (flower) and はし (bridge) contain は, so they matched, and
        // the drill handed the learner words they type `hana`/`hashi` — first time, correctly,
        // learning nothing about the particle while the app reported it as remediation.
        let words = [("a", "はな"), ("b", "はし"), ("c", "がっこう")]
        #expect(CoachContent.drillCandidates(for: .particleSpelling, from: words).isEmpty)
        // …while the same words still drill the patterns they genuinely exercise.
        #expect(CoachContent.drillCandidates(for: .sokuon, from: words) == ["c"])
    }

    @Test("one definition decides what exercises a pattern")
    func exercisesIsShared() {
        // Both paths — the word list and the passage filter — go through `exercises`, so a
        // sentence and a word cannot disagree about what practises what.
        #expect(CoachContent.exercises("こんにちは", pattern: .particleSpelling))
        #expect(CoachContent.exercises("がっこうへいきます", pattern: .particleSpelling))
        #expect(!CoachContent.exercises("ねこがいます", pattern: .particleSpelling))
        #expect(CoachContent.exercises("しんぶん", pattern: .hepburnM))
        #expect(!CoachContent.exercises("にほん", pattern: .hepburnM))
        #expect(!CoachContent.exercises("がっこう", pattern: .unknown))
    }
}
