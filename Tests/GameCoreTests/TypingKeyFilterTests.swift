import Testing
import Foundation
@testable import GameCore

/// On macOS every key the keyCode switch did not claim was forwarded to the matcher, so Tab
/// and the arrow keys were graded as typos: each one booked a mistake and zeroed the combo,
/// and three on one word recorded that word as an SM-2 lapse. The app then rescheduled a word
/// the learner had typed perfectly, and reported an accuracy they had not earned.
@Suite("TypingKeyFilter — machine keys are not typos")
struct TypingKeyFilterTests {

    /// AppKit's private-use encodings, by name so the intent survives a reader who does not
    /// recognise the code points.
    private let upArrow: Character = "\u{F700}"
    private let downArrow: Character = "\u{F701}"
    private let leftArrow: Character = "\u{F702}"
    private let f1: Character = "\u{F704}"
    private let home: Character = "\u{F729}"
    private let pageUp: Character = "\u{F72C}"

    @Test("ordinary typing is accepted")
    func acceptsTyping() {
        for c in "abcdefghijklmnopqrstuvwxyz" { #expect(TypingKeyFilter.accepts(c), "rejected \(c)") }
        for c in "AQZ" { #expect(TypingKeyFilter.accepts(c)) }
        for c in "0123456789-'" { #expect(TypingKeyFilter.accepts(c)) }
    }

    @Test("a WRONG letter is still typing — it must keep counting as a typo")
    func wrongLetterStillCounts() {
        // The filter separates "not typing" from "typing badly". Silently swallowing wrong
        // letters would inflate accuracy and stop lapses being recorded at all, which is a
        // worse bug than the one being fixed.
        #expect(TypingKeyFilter.accepts("q"))
        #expect(TypingKeyFilter.accepts("x"))
        #expect(TypingKeyFilter.accepts("ñ"))
    }

    @Test("Tab and the other control characters are rejected")
    func rejectsControls() {
        #expect(!TypingKeyFilter.accepts("\t"))
        #expect(!TypingKeyFilter.accepts("\n"))
        #expect(!TypingKeyFilter.accepts("\r"))
        #expect(!TypingKeyFilter.accepts("\u{1B}"))   // Esc
        #expect(!TypingKeyFilter.accepts("\u{7F}"))   // Delete
    }

    @Test("arrows, F-keys and navigation keys are rejected")
    func rejectsFunctionKeys() {
        for c in [upArrow, downArrow, leftArrow, f1, home, pageUp] {
            #expect(!TypingKeyFilter.accepts(c), "accepted U+\(String(c.unicodeScalars.first!.value, radix: 16))")
        }
        // The whole private-use block, at both ends.
        #expect(!TypingKeyFilter.accepts("\u{F700}"))
        #expect(!TypingKeyFilter.accepts("\u{F8FF}"))
        // …and only that block: the character just below it is ordinary text.
        #expect(TypingKeyFilter.accepts("\u{F6FF}"))
    }

    @Test("⌘ and ⌃ combinations never reach the matcher")
    func rejectsShortcuts() {
        // ⌘Q / ⌘W / ⌘, all deliver a bare letter, and each scored a typo on the way to doing
        // something else — quitting, closing the window, opening settings.
        #expect(!TypingKeyFilter.accepts("q", commandOrControl: true))
        #expect(!TypingKeyFilter.accepts("a", commandOrControl: true))
        #expect(TypingKeyFilter.accepts("q", commandOrControl: false))
    }

    @Test("kana and multi-scalar characters pass — the app is not ASCII-only")
    func acceptsNonASCII() {
        // An IME or a Japanese keyboard can deliver kana directly, and the matcher handles it.
        #expect(TypingKeyFilter.accepts("か"))
        #expect(TypingKeyFilter.accepts("ー"))
        #expect(TypingKeyFilter.accepts("ぱ"))
    }
}
