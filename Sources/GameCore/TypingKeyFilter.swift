import Foundation

/// Which key presses are the learner *typing*, as opposed to operating the machine.
///
/// On macOS the key handler forwarded `charactersIgnoringModifiers` for anything its keyCode
/// switch did not claim. AppKit reports Tab as `\t` and the arrows, F-keys, Home/End/Page
/// keys as characters in a private-use block, so all of them reached the matcher, came back
/// `.rejected`, and each booked a typo and zeroed the combo. Three stray arrow presses on one
/// word recorded that word as an SM-2 lapse — the app rescheduled a word the learner had
/// typed perfectly, and the Ride Log's accuracy was wrong too.
///
/// Pure and testable on every platform, because the app target has no unit tests and this is
/// exactly the kind of rule that is easy to get subtly wrong.
public enum TypingKeyFilter {

    /// AppKit maps arrows, F-keys, Home/End/Page-Up/Down and friends into this Unicode
    /// private-use block. Nothing a learner can type lives here.
    static let functionKeyRange: ClosedRange<UInt32> = 0xF700...0xF8FF

    /// Whether `character` should be offered to the matcher.
    ///
    /// Rejects control characters (Tab, newline, the rest of C0) and AppKit's function-key
    /// block. Everything else is allowed through — including characters that are simply
    /// wrong for the current word, because typing the wrong letter IS a typo and must still
    /// count as one. The distinction this draws is "not typing" versus "typing badly".
    public static func accepts(_ character: Character) -> Bool {
        if isControl(character) { return false }
        if character.unicodeScalars.count == 1,
           let scalar = character.unicodeScalars.first,
           functionKeyRange.contains(scalar.value) {
            return false
        }
        return true
    }

    /// Whether a key EVENT should reach the matcher.
    ///
    /// - Parameter commandOrControl: the event carried ⌘ or ⌃. Those are shortcuts, not
    ///   typing: ⌘Q, ⌘W, ⌘, all delivered a bare letter to the matcher and scored a typo on
    ///   the way to doing something else entirely.
    public static func accepts(_ character: Character, commandOrControl: Bool) -> Bool {
        guard !commandOrControl else { return false }
        return accepts(character)
    }

    private static func isControl(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.controlCharacters.contains($0)
        }
    }
}
