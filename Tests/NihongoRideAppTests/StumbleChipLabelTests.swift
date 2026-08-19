import Testing
@testable import NihongoRideApp

/// The contract `StumbledWordsFlowTests` matches on, checked where a simulator is not required.
///
/// That device test is the only evidence this feature reaches a real screen, and it finds the
/// chips by reading accessibility labels: it splits on a comma and requires the leading parts to
/// be Japanese. v1.24 changed the label to "Save 潜入, せんにゅう" and the test stopped seeing any
/// chip at all — it would have failed on a screen that rendered perfectly, and it takes a
/// simulator run to discover that. These run in `swift test`.
@Suite("The stumbled-chip accessibility label")
struct StumbleChipLabelTests {

    /// What the device test actually asserts, expressed once so both sides mean the same thing.
    static func leadingJapanesePair(of label: String) -> (String, String)? {
        let parts = label.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        for part in parts.prefix(2) where !part.unicodeScalars.allSatisfy({ $0.value > 0x3000 }) {
            return nil
        }
        return (parts[0], parts[1])
    }

    @Test("the word always leads, in every language and every state")
    func wordAlwaysLeads() {
        for zh in [false, true] {
            for saved in [false, true] {
                for actionable in [false, true] {
                    let label = StumbleChipLabel.label(surface: "潜入", reading: "せんにゅう",
                                                       actionable: actionable, saved: saved, zh: zh)
                    let pair = Self.leadingJapanesePair(of: label)
                    #expect(pair?.0 == "潜入" && pair?.1 == "せんにゅう",
                            "zh=\(zh) saved=\(saved) actionable=\(actionable): \(label)")
                }
            }
        }
    }

    /// The regression, named. This is the string that broke the device test.
    @Test("the label is never prefixed with an instruction")
    func neverPrefixed() {
        let label = StumbleChipLabel.label(surface: "潜入", reading: "せんにゅう",
                                           actionable: true, saved: false, zh: false)
        #expect(label == "潜入, せんにゅう")
        #expect(!label.hasPrefix("Save"), "an instruction belongs in the hint, not the label")
    }

    /// VoiceOver still has to tell the two kinds of chip apart — visually the difference is a
    /// missing star and a paler stroke, neither of which it can convey. The hint carries it.
    @Test("only an actionable chip offers an action")
    func onlyActionableChipsHint() {
        #expect(StumbleChipLabel.hint(actionable: false, saved: false, zh: false) == nil)
        #expect(StumbleChipLabel.hint(actionable: true, saved: false, zh: false) != nil)
        #expect(StumbleChipLabel.hint(actionable: true, saved: true, zh: false)
                != StumbleChipLabel.hint(actionable: true, saved: false, zh: false))
        for zh in [false, true] {
            #expect(StumbleChipLabel.hint(actionable: true, saved: false, zh: zh)?.isEmpty == false)
        }
    }

    /// The detector must be able to say no, or "every label matches" would pass everything.
    @Test("the detector rejects labels that are not a Japanese pair")
    func detectorIsCalibrated() {
        #expect(Self.leadingJapanesePair(of: "Save 潜入, せんにゅう") == nil)
        #expect(Self.leadingJapanesePair(of: "Ride these 3 words") == nil)
        #expect(Self.leadingJapanesePair(of: "潜入") == nil)
        #expect(Self.leadingJapanesePair(of: "潜入, せんにゅう, saved") != nil)
    }
}
