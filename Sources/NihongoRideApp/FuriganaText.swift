import SwiftUI
import VocabKit

/// A Japanese sentence with its reading set above the kanji.
///
/// This exists because of a measured problem, not for decoration. v1.17 found 25 N3 entries
/// that teach a MINORITY reading of a kanji with a commoner alternative — 工場 as こうば where
/// nearly every reader produces こうじょう, 魚 as うお against さかな. A learner reading the
/// example sentence has no way to know which reading the card means, so the sentence teaches
/// the wrong association. Furigana removes that ambiguity for every sentence at once, which
/// no amount of sentence rewriting could.
///
/// It renders from `exTokens`, whose surfaces reconstruct the sentence exactly — a data
/// invariant with a test behind it, because furigana that drifts by one token puts the reading
/// over the wrong character, which is worse than showing none.
struct FuriganaText: View {
    /// `[[surface, reading], ...]` covering the whole sentence.
    let tokens: [[String]]
    var size: CGFloat = 16
    var color: Color = .white.opacity(0.7)

    /// Kana and punctuation get no ruby — a reading over 「です」 is noise, and it is the
    /// kanji the learner cannot read.
    private func needsRuby(_ surface: String, _ reading: String) -> Bool {
        guard surface != reading else { return false }
        return surface.contains { ch in
            let s = String(ch).unicodeScalars.first!.value
            return (0x4E00...0x9FFF).contains(s)      // CJK ideographs
        }
    }

    var body: some View {
        // A wrapping row of per-token columns. Each column reserves the ruby line whether or
        // not it has ruby, so the baseline of the sentence stays flat instead of stepping up
        // and down around the kanji.
        FlowLayout(spacing: 0, lineSpacing: 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, pair in
                let surface = pair.first ?? ""
                let reading = pair.count > 1 ? pair[1] : ""
                VStack(spacing: 0) {
                    Text(needsRuby(surface, reading) ? reading : " ")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(color.opacity(0.75))
                    Text(surface)
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(color)
                }
                .fixedSize()
            }
        }
    }
}

/// Minimal wrapping layout — SwiftUI has no built-in flow, and a sentence must wrap by token
/// so a kanji never separates from its own reading.
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
