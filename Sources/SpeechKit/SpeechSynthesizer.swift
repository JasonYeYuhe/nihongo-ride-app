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
}
