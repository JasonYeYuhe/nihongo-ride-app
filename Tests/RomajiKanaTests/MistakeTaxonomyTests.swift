import Testing
@testable import RomajiKana

/// What the engine ACTUALLY rejects.
///
/// v1.15's Coach design twice named a "mistake pattern" that this engine accepts —
/// kunrei-shiki (`si`/`ti`/`tu`) and lenient single-`n` before a vowel (`renai` → れんあい).
/// Both were caught in review, both after the taxonomy had been written from intuition
/// rather than from the matcher. A diagnosis can only exist for input the engine refuses, so
/// this suite is the taxonomy's source of truth: a pattern may be added to the Coach only
/// with a case here proving the engine rejects it, and the ACCEPTED half exists to stop the
/// same mistake being made a third time.
@Suite("Mistake taxonomy — what the engine really refuses")
struct MistakeTaxonomyTests {

    // MARK: Accepted — these are NOT mistakes, whatever they look like

    @Test("alternative romanisations are accepted and must never be diagnosed", arguments: [
        ("si", "し"), ("shi", "し"),          // kunrei vs Hepburn
        ("ti", "ち"), ("chi", "ち"),
        ("tu", "つ"), ("tsu", "つ"),
        ("hu", "ふ"), ("fu", "ふ"),
        ("zi", "じ"), ("ji", "じ"),
        ("renai", "れんあい"),                 // lenient single n before a vowel
        ("rennai", "れんあい"),
        ("ren'ai", "れんあい"),
        ("kinyoubi", "きんようび"),            // …and before y
        ("sinbun", "しんぶん"),                // kunrei inside a longer word
    ])
    func accepted(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target),
                "‘\(c.input)’ is accepted input for ‘\(c.target)’ — it is not a mistake")
    }

    // MARK: Rejected — these are the only things a Coach may diagnose

    @Test("particle は typed phonetically as wa")
    func particleHa() {
        // こんにちは is passage #1 of 233, and 152 of them contain は. A learner types what
        // they hear and gets こんにちわ. The engine refuses at the は.
        #expect(firstRejection(of: "konnichiwa", as: "こんにちは", at: 8))
    }

    @Test("particle を typed as o, particle へ typed as e")
    func particleWoHe() {
        #expect(firstRejection(of: "o", as: "を", at: 0))
        #expect(firstRejection(of: "e", as: "へ", at: 0))
        #expect(firstRejection(of: "wa", as: "は", at: 0))
    }

    @Test("Hepburn m before b/p, as a real IME refuses it")
    func hepburnM() {
        #expect(firstRejection(of: "shimbun", as: "しんぶん", at: 3))
    }

    @Test("small ya typed as a full-size ya")
    func smallYa() {
        #expect(firstRejection(of: "kiyaku", as: "きゃく", at: 2))
    }

    @Test("dropped sokuon")
    func droppedSokuon() {
        #expect(firstRejection(of: "ite", as: "いって", at: 2))
    }
}
