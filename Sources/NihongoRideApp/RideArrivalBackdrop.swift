import SwiftUI
import SceneryKit

/// The sky you arrived under, behind a results screen.
///
/// One shared implementation because there are TWO results screens — `ResultsView` for
/// rides and `ConjugationResultsView` for drills — and both ride the same road. (The first
/// draft of this feature put the backdrop only on ResultsView; the Codex review caught it.)
///
/// Drawn `still`: a results screen is a stopped moment, and `landmarkPhase` alone would
/// only freeze the landmark while the wall-clock-driven clouds and lane dashes kept
/// streaming. Phase 3.99 puts the stage's landmark at its closest — you got there.
///
/// Legibility follows the same principle as the game screen: the scene stays vivid, and
/// the CONTENT carries its own contrast on a dark panel (`RidePalette.cardAlpha`). A scrim
/// alone can never make naked white text readable over the sun disc, and `Theme.dim`
/// captions cannot reach 7:1 over anything — so the panel, not the scrim, is the guarantee.
struct RideArrivalBackdrop: View {
    let stage: RideStage

    var body: some View {
        ZStack {
            RideBackgroundView(speed: 0, landmarkPhase: 3.99, stage: stage, still: true)
            Color.black.opacity(stage.palette.textScrim + 0.15).ignoresSafeArea()
        }
    }
}

extension View {
    /// The dark backing a results column sits on — the results-screen counterpart of the
    /// game's word card, and the thing that actually buys the text its contrast.
    func arrivalPanel(compact: Bool) -> some View {
        self
            .padding(.horizontal, compact ? 16 : 28)
            .padding(.vertical, compact ? 18 : 24)
            .background(.black.opacity(RidePalette.cardAlpha),
                        in: RoundedRectangle(cornerRadius: compact ? 24 : 32))
            .overlay(RoundedRectangle(cornerRadius: compact ? 24 : 32)
                .strokeBorder(.white.opacity(0.10)))
    }
}
