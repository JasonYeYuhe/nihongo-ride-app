import Testing
import Foundation
@testable import SceneryKit

/// The road's colours are the first thing in this app that a designer will want to keep
/// tweaking, and the word card sits directly on top of them. So the readability rule is a
/// test, not a comment: a palette that would put white text under 7:1 fails here, before
/// anyone has to notice it on a screen while trying to type.
@Suite("RideRoute — the road, and the contrast it owes the text")
struct RideRouteTests {

    @Test("every stretch keeps white text at 7:1 or better through its own scrim and the card")
    func everyStageIsReadable() {
        for stage in RideRoute.stages {
            let composite = stage.palette.compositeLuminance(scrim: stage.palette.textScrim)
            let contrast = (1.0 + 0.05) / (composite + 0.05)
            #expect(contrast >= 7.0,
                    "\(stage.name) (\(stage.romaji)) gives white text \(String(format: "%.1f", contrast)):1")
        }
    }

    @Test("brightening the ground cannot break the text, however far it is pushed")
    func brighteningStaysReadable() {
        // The card's own backing carries most of the contrast now, so a plausible ground
        // brightening is absorbed there and the scrim never moves. What must hold is the
        // OUTCOME, not any one mechanism: white text stays at 7:1 no matter how bright the
        // ground is pushed.
        let base = RideRoute.stages[7].palette      // 京都, night
        for ground in [RGB(0.5, 0.55, 0.5), RGB(0.75, 0.80, 0.78), RGB(0.95, 0.97, 0.95)] {
            var bright = base
            bright.land = ground
            let contrast = (1.0 + 0.05) / (bright.compositeLuminance(scrim: bright.textScrim) + 0.05)
            #expect(contrast >= 7.0,
                    "ground \(ground) gives \(String(format: "%.1f", contrast)):1")
        }
    }

    @Test("past what the card alone can absorb, the scrim does start paying")
    func scrimIsTheBackstop() {
        // The coupling still exists for a ground bright enough to defeat the card on its own;
        // it just no longer fires for realistic palettes. Asserted so the backstop cannot be
        // deleted as dead code.
        let base = RideRoute.stages[7].palette
        var extreme = base
        extreme.land = RGB(1, 1, 1)
        #expect(extreme.textScrim > RidePalette.baseScrim,
                "a white ground must still force extra scrim")
    }

    @Test("the first stretch is the palette the app already ships")
    func firstStageIsHome() {
        // Existing riders open the app onto the sky they know, and it still matches the icon.
        let home = RideRoute.stages[0].palette
        #expect(home.skyTop == RGB(0.08, 0.11, 0.26))
        #expect(home.skyLow == RGB(0.98, 0.62, 0.46))
        #expect(home.road == RGB(0.82, 0.21, 0.21))
        #expect(RideRoute.stages[0].startMetres == 0)
    }

    @Test("lifetime distance picks the stretch, and the boundaries are exact")
    func stageSelection() {
        #expect(RideRoute.stage(forLifetimeMetres: 0).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: 399).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: 400).name == "川崎", "a boundary is inclusive")
        #expect(RideRoute.stage(forLifetimeMetres: 1_199).name == "川崎")
        #expect(RideRoute.stage(forLifetimeMetres: 2_500).name == "富士")
        #expect(RideRoute.stage(forLifetimeMetres: 24_999).name == "鈴鹿")
        #expect(RideRoute.stage(forLifetimeMetres: 25_000).name == "京都")
    }

    @Test("arriving is an ending, not a reset")
    func arrivalHolds() {
        #expect(RideRoute.stage(forLifetimeMetres: 1_000_000).name == "京都")
        #expect(RideRoute.metresToNextStage(forLifetimeMetres: 1_000_000) == nil)
        #expect(RideRoute.progressWithinStage(forLifetimeMetres: 1_000_000) == 1)
    }

    @Test("a nonsense odometer degrades to the first stretch instead of crashing")
    func garbageInput() {
        // The odometer is synced and grow-only; a corrupt or absurd value must not blank the
        // scene mid-ride.
        #expect(RideRoute.stage(forLifetimeMetres: -5_000).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: -.infinity).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: .nan).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: .infinity).name == "京都", "infinity is ordered — it belongs at the far end, not at home")
    }

    @Test("thresholds only ever increase, and stage ids match their order")
    func routeIsWellFormed() {
        for (i, stage) in RideRoute.stages.enumerated() {
            #expect(stage.id == i, "id must be the index — the scene indexes stages by it")
            if i > 0 {
                #expect(stage.startMetres > RideRoute.stages[i - 1].startMetres,
                        "\(stage.name) does not come after \(RideRoute.stages[i - 1].name)")
            }
        }
    }

    @Test("progress within a stretch runs 0→1 and never escapes it")
    func progressWithin() {
        #expect(RideRoute.progressWithinStage(forLifetimeMetres: 400) == 0)
        #expect(abs(RideRoute.progressWithinStage(forLifetimeMetres: 800) - 0.5) < 0.001)
        #expect(RideRoute.progressWithinStage(forLifetimeMetres: 1_199) < 1)
        for m in stride(from: -1_000.0, through: 30_000.0, by: 137.0) {
            let p = RideRoute.progressWithinStage(forLifetimeMetres: m)
            #expect(p >= 0 && p <= 1, "progress escaped 0...1 at \(m) m")
        }
    }

    @Test("consecutive stretches actually look different")
    func stagesAreDistinct() {
        // Otherwise the reward for riding 5 km is a road that looks the same.
        for i in 1 ..< RideRoute.stages.count {
            let a = RideRoute.stages[i - 1].palette, b = RideRoute.stages[i].palette
            let skyShift = abs(a.skyMid.luminance - b.skyMid.luminance)
                + abs(a.skyLow.luminance - b.skyLow.luminance)
            #expect(skyShift > 0.02,
                    "\(RideRoute.stages[i - 1].name) → \(RideRoute.stages[i].name) is too subtle to notice")
        }
    }

    @Test("interpolation stays inside the palette and can't blow past a colour")
    func lerpIsBounded() {
        let a = RideRoute.stages[0].palette, b = RideRoute.stages[7].palette
        #expect(a.lerp(to: b, 0) == a)
        #expect(a.lerp(to: b, 1) == b)
        #expect(a.lerp(to: b, -3) == a, "out-of-range t clamps rather than extrapolating")
        #expect(a.lerp(to: b, 9) == b)
        let mid = a.lerp(to: b, 0.5)
        let contrast = (1.0 + 0.05) / (mid.compositeLuminance(scrim: mid.textScrim) + 0.05)
        #expect(contrast >= 7.0, "a half-way blend must be readable too")
    }
}
