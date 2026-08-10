import Foundation
import AVFoundation

/// Thin @MainActor wrapper over `AVSpeechSynthesizer` for on-demand kana read-aloud
/// (PLAN-V1.8 §D). Offline Japanese (`ja-JP`) system voice; opt-in, never auto-plays.
///
/// A LEAF module: the app depends on it directly (the ConjugationKit boundary red line
/// §6 does not apply to a plain synthesizer). Switching cards cancels any in-flight
/// utterance. Degrades gracefully — if no Japanese voice is installed, `speak` is a
/// silent no-op (the caller shows no alert).
@MainActor
public final class SpeechSynthesizer {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    /// Whether an offline Japanese voice is available on this device. Used for graceful
    /// degradation — the UI can hide/disable the speak button when false rather than
    /// firing an utterance that produces nothing.
    public static var isJapaneseAvailable: Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix("ja") }
    }

    /// Clamps a stored rate into AVSpeech's valid range. Exposed for testing; the stored
    /// default (0.5) is `AVSpeechUtteranceDefaultSpeechRate` on current Apple platforms.
    public static func clampedRate(_ rate: Float) -> Float {
        min(AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, rate))
    }

    /// Speaks `text` in Japanese at `rate`, cancelling any in-flight utterance first
    /// (so switching cards never queues a backlog). No-ops on empty text or when no
    /// Japanese voice is available — never throws, never alerts.
    public func speak(_ text: String, rate: Float) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let voice = AVSpeechSynthesisVoice(language: "ja-JP") else { return }
        stop()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = Self.clampedRate(rate)
        synthesizer.speak(utterance)
    }

    /// Cancels any in-flight or queued utterance immediately (call on card switch / exit).
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: Audio session (iOS) — v1.21 §A

    /// Claims the audio session for spoken prompts, and returns whether it worked.
    ///
    /// The app has never configured an `AVAudioSession`, so it runs under the default
    /// category — which the iPhone Ring/Silent switch mutes. For the read-aloud BUTTON that
    /// is a minor annoyance a user can diagnose by flicking the switch. For dictation it is
    /// fatal and undiagnosable: the whole mode becomes a silent screen asking you to type
    /// what you heard, which is indistinguishable from a bug. So a dictation run claims
    /// `.playback` (the category that ignores the mute switch) for its duration only, and
    /// gives it back on the way out. Nothing else in the app's audio behaviour changes,
    /// because nothing else calls this.
    ///
    /// `.duckOthers` rather than plain `.playback`: someone practising with music on should
    /// keep their music, quietened, rather than have it stopped.
    ///
    /// Failure is reported, not thrown. A refused session is not a reason to refuse the run
    /// — the audio may well still be audible — but it IS a reason to tell the learner where
    /// to look if they hear nothing, which the caller does.
    @discardableResult
    public static func beginSpokenPrompts() -> Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            return true
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    /// Releases the session claimed by `beginSpokenPrompts`, letting other audio back up.
    public static func endSpokenPrompts() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
