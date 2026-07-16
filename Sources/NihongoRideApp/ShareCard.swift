import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The shareable image of a finished ride.
///
/// A value type holding finished PNG bytes rather than a view: `Transferable`'s
/// export closure can run off the main actor, and rendering SwiftUI there is not
/// allowed. So the card is rendered ON the main actor when the results screen
/// appears, and this just carries the result.
struct ShareCardImage: Transferable {
    let data: Data
    /// Shown as the suggested filename and in the share sheet's header.
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { "\($0.title).png" }
    }
}

/// Renders ``ShareCardView`` to PNG bytes.
enum ShareCardRenderer {
    /// Returns nil rather than a blank card if rendering fails — the caller hides the
    /// share affordance entirely, so the user never gets a button that produces junk.
    @MainActor
    static func render(summary: GameSummary, zh: Bool, scale: CGFloat = 3) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(summary: summary, zh: zh))
        renderer.scale = scale
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }
}

/// The card art. Deliberately self-contained: fixed size, no `KeyCaptureView`, no
/// native controls, no environment dependencies — everything `ImageRenderer` refuses
/// to draw. (Native `Picker`/`Toggle` render as placeholders under it; Swift Charts,
/// verified in v1.9, does not.) It reads only the values passed in, so the same card
/// renders identically headless and at runtime.
struct ShareCardView: View {
    let summary: GameSummary
    let zh: Bool

    private var gradeTitle: String {
        switch summary.grade {
        case .flawless: return zh ? "完美" : "Flawless"
        case .steady:   return zh ? "稳健" : "Steady"
        case .building: return zh ? "有进步" : "Building"
        case .lap:      return zh ? "再来一程" : "Another lap"
        }
    }

    private var gradeTint: Color {
        switch summary.grade {
        case .flawless: return Theme.gold
        case .steady:   return Theme.done
        case .building: return Theme.accent2
        case .lap:      return Theme.accent
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("🚲").font(.system(size: 26))
                Text(zh ? "にほんご ライド" : "Nihongo Ride")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(gradeTitle.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    // Tracking is a Latin-uppercase device; on CJK it just prises the
                    // characters apart ("稳 健"), so the zh card gets none.
                    .tracking(zh ? 0 : 3)
                    .foregroundStyle(gradeTint)
            }

            Text("\(summary.score)")
                .font(.system(size: 76, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(zh ? "得分" : "SCORE")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(zh ? 0 : 2)
                .foregroundStyle(Theme.dim)
                .padding(.top, -14)

            HStack(spacing: 0) {
                stat("\(Int(summary.distanceMeters))m", zh ? "距离" : "Distance")
                divider
                stat("×\(summary.maxCombo)", zh ? "最高连击" : "Best combo")
                divider
                stat("\(Int(summary.accuracy * 100))%", zh ? "准确率" : "Accuracy")
                divider
                stat("\(summary.wordsCompleted)", zh ? "完成词数" : "Words")
            }

            Text(zh ? "日语打字练习 · Japanese typing practice"
                    : "Japanese typing practice")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim.opacity(0.8))
        }
        .padding(28)
        .frame(width: 540, height: 400)
        .background(Theme.background)
    }

    private var divider: some View {
        Rectangle().fill(Theme.cardStroke).frame(width: 1, height: 34)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}
