import Testing
@testable import ConjugationKit

// MARK: - Form tokens are persisted, so renaming one is a migration

/// `ConjugationSRSCard.id` is `"<entryID>#<form.rawValue>"`, written to disk and to CloudKit.
/// The raw values are therefore storage, not labels.
///
/// This matters beyond the usual "don't break decoding". The app icon badge and the due-review
/// push count conjugation cards with a predicate that only asks whether the card's VERB still
/// exists, while the drill that has to deliver them additionally needs `ConjugationForm(rawValue:)`
/// to parse. Rename a case and the two part company silently: the badge keeps promising reviews
/// the drill can never produce, and no existing test notices, because every test builds its cards
/// from the same enum it is asserting against. As of v1.23 that is the ONLY way to open the gap —
/// a withdrawn entry fails both predicates alike, and `vc` is frozen by the vocabulary guard — so
/// pinning the tokens is what keeps it shut.
///
/// If you are here because this failed: adding a case is fine, just extend the list. Renaming or
/// removing one needs a migration for stored cards first.
@Suite("Persisted form tokens")
struct ConjugationFormTokenTests {

    @Test("the stored raw values are exactly these")
    func tokensArePinned() {
        #expect(Set(ConjugationForm.allCases.map(\.rawValue)) ==
                ["polite", "te", "past", "negative", "pastNegative", "potential", "volitional"])
    }

    @Test("every token a card can carry parses back")
    func everyTokenRoundTrips() {
        for form in ConjugationForm.allCases {
            #expect(ConjugationForm(rawValue: form.rawValue) == form)
        }
    }
}
