import SwiftUI

/// Tap-to-read-aloud control for the game cards (v1.8 §D). Reads the given kana with
/// the app's `SpeechSynthesizer`.
///
/// **Focus red line (PLAN-V1.8 §5 / Gemini #3):** the game screens capture keystrokes
/// through a hidden `KeyCaptureView` first responder. This control is an `Image` +
/// `.onTapGesture` — NOT a `Button` — exactly like the ★ save control, because a
/// `Button` tap would resign that first responder (dropping keys on macOS, dismissing
/// the software keyboard on iOS). After speaking it also re-summons the keyboard on iOS
/// as belt-and-suspenders. Shown only when TTS is on AND a Japanese voice is installed
/// (graceful degradation — never an alert).
struct SpeakButton: View {
    @Environment(AppModel.self) private var model
    /// The kana to read (e.g. a word reading, or a verb's dictionary reading).
    let kana: String?
    var compact: Bool = false
    var language: String = "en"

    var body: some View {
        if model.ttsEnabled, model.ttsAvailable, let kana, !kana.isEmpty {
            let zh = language == "zh"
            Image(systemName: "speaker.wave.2")
                .scaledSystemFont(compact ? 15 : 18)
                .foregroundStyle(Theme.dim)
                .padding(compact ? 10 : 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.speak(kana)
                    #if os(iOS)
                    // Keep the hidden key-capture view as first responder so a tap here
                    // never strands the drill without a keyboard.
                    KeyboardSummon.summon()
                    #endif
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(zh ? "朗读假名" : "Read aloud")
        }
    }
}
