import Testing
@testable import RomajiKana

/// Feeds an entire romaji string into a fresh matcher for `target`.
/// Returns `true` iff every keystroke was accepted and the word ended complete.
func typesOut(_ romaji: String, as target: String) -> Bool {
    var matcher = KanaInputMatcher(target: target)
    for ch in romaji {
        if matcher.input(ch) == .rejected { return false }
    }
    return matcher.isComplete
}

/// Returns `true` iff the keystroke at `index` (0-based) is the *first* rejection:
/// every key before it is accepted, and the key at `index` is rejected.
func firstRejection(of romaji: String, as target: String, at index: Int) -> Bool {
    var matcher = KanaInputMatcher(target: target)
    for (i, ch) in romaji.enumerated() {
        let result = matcher.input(ch)
        if i < index, result == .rejected { return false }   // rejected too early
        if i == index { return result == .rejected }
    }
    return false                                              // never reached the rejection
}
