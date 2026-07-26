import Testing
import Foundation

/// `countLabel` lives in the app target, which has no test target of its own, so its
/// behaviour is pinned here against a local copy of the same rule. That is weaker than
/// testing the real symbol — if the two ever diverge this suite goes quiet — so the value of
/// these cases is the RULE they fix, not the linkage: v1.14 §B shipped
/// "1 words + 1 conjugations" in the reminder body's mixed branch because the plural was
/// written by hand at each of four call sites and the fifth was missed.
private func countLabel(_ n: Int, _ singular: String, plural: String? = nil) -> String {
    "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
}

private func countVerb(_ n: Int, _ singular: String = "is", plural: String = "are") -> String {
    n == 1 ? singular : plural
}

@Suite("English count phrases")
struct CountLabelTests {

    @Test("one is singular, everything else is plural — including zero")
    func singularOnlyAtOne() {
        #expect(countLabel(1, "word") == "1 word")
        #expect(countLabel(2, "word") == "2 words")
        #expect(countLabel(0, "word") == "0 words")   // English pluralises zero
        #expect(countLabel(1, "conjugation") == "1 conjugation")
        #expect(countLabel(7, "conjugation") == "7 conjugations")
    }

    @Test("verb agreement follows the same boundary")
    func verbAgreement() {
        #expect(countVerb(1) == "is")
        #expect(countVerb(0) == "are")
        #expect(countVerb(2) == "are")
    }

    @Test("the reminder body's mixed branch reads correctly at 1 + 1")
    func mixedBranchAtOne() {
        // The exact string v1.14 got wrong: both counts non-zero, so the outer noun is plural
        // while both inner ones are singular.
        let vocab = 1, conj = 1
        let body = "\(vocab + conj) reviews are due today "
                 + "(\(countLabel(vocab, "word")) + \(countLabel(conj, "conjugation")))."
        #expect(body == "2 reviews are due today (1 word + 1 conjugation).")
    }
}
