import Foundation

/// What VoiceOver says about a stumbled-word chip.
///
/// Extracted from the view for one reason: it is a contract two things depend on, and only one
/// of them could check it. `StumbledWordsFlowTests` — the only gate that proves this feature
/// reaches a real screen on a real device — finds the chips by reading accessibility labels and
/// requiring a Japanese "surface, reading" pair. v1.24 changed the label to "Save 潜入, せんにゅう"
/// and the test could no longer see a single chip: it would have failed on a screen that was
/// rendering perfectly, and it takes a simulator to find that out. Here `swift test` can.
///
/// The label also changed for the better on the way. Putting "Save" in front of the word made
/// the label an instruction; VoiceOver's own convention is that the LABEL names the thing and
/// the HINT says what happens if you act on it. So the word always leads, and the affix that
/// varies goes last or into the hint.
enum StumbleChipLabel {

    /// `"潜入, せんにゅう"`, plus a saved marker when it is saved. Never prefixed.
    ///
    /// The leading two comma-separated components are ALWAYS the surface and the reading, in
    /// that order, and both are always Japanese. That is the property the device test matches
    /// on, and the reason it is stated here rather than left implicit in a string literal.
    static func label(surface: String, reading: String,
                      actionable: Bool, saved: Bool, zh: Bool) -> String {
        let word = "\(surface), \(reading)"
        guard actionable, saved else { return word }
        return zh ? "\(word), 已收藏" : "\(word), saved"
    }

    /// What acting on the chip does — nil for a chip that does nothing, which is the honest
    /// answer for a particle in a dictation result.
    static func hint(actionable: Bool, saved: Bool, zh: Bool) -> String? {
        guard actionable else { return nil }
        if saved { return zh ? "再次点按取消收藏" : "Tap again to unsave" }
        return zh ? "点按收藏,长按加入词单" : "Tap to save, long-press to add to lists"
    }
}
