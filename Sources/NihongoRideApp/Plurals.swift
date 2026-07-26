import Foundation

/// "1 word" / "0 words" / "3 conjugations" — English count phrases.
///
/// English is the only language here that inflects for number: the Chinese strings say
/// 「3 个词」 with no plural form at all, so callers keep their own zh text and use this
/// for the en branch. It exists because the ternary was already copy-pasted at four call
/// sites and the fifth (the reminder body's mixed case, v1.14 §B) simply forgot it and
/// shipped "1 words".
///
/// - Parameters:
///   - n: the count. Zero takes the plural, as English does.
///   - singular: the noun in its singular form ("word").
///   - plural: only when adding "s" is wrong. Every noun this app counts is regular.
func countLabel(_ n: Int, _ singular: String, plural: String? = nil) -> String {
    "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
}

/// "is" / "are" for a count — the other half of agreement, and just as easy to forget.
func countVerb(_ n: Int, _ singular: String = "is", plural: String = "are") -> String {
    n == 1 ? singular : plural
}
