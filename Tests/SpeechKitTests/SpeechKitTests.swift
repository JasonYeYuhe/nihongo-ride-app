import Testing
import AVFoundation
@testable import SpeechKit

@MainActor
@Suite("SpeechKit — synthesizer wrapper")
struct SpeechKitTests {

    @Test("clampedRate keeps the rate inside AVSpeech's valid range")
    func clampRate() {
        #expect(SpeechSynthesizer.clampedRate(-5) == AVSpeechUtteranceMinimumSpeechRate)
        #expect(SpeechSynthesizer.clampedRate(99) == AVSpeechUtteranceMaximumSpeechRate)
        let mid = AVSpeechUtteranceDefaultSpeechRate
        #expect(SpeechSynthesizer.clampedRate(mid) == mid)     // in-range value unchanged
    }

    @Test("isJapaneseAvailable returns a Bool without crashing")
    func japaneseAvailability() {
        _ = SpeechSynthesizer.isJapaneseAvailable   // may be true or false in CI; must not trap
    }

    @Test("speak degrades gracefully: empty / whitespace text is a silent no-op")
    func speakEmptyNoOp() {
        let s = SpeechSynthesizer()
        s.speak("", rate: AVSpeechUtteranceDefaultSpeechRate)      // no crash, nothing queued
        s.speak("   \n", rate: AVSpeechUtteranceDefaultSpeechRate)
        s.stop()                                                   // stop with nothing speaking is safe
    }

    @Test("speak + stop with real text never traps")
    func speakStop() {
        let s = SpeechSynthesizer()
        s.speak("たべる", rate: AVSpeechUtteranceDefaultSpeechRate)  // may or may not have a voice; must not crash
        s.stop()
    }
}
