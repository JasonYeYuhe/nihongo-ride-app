import Testing
import Foundation
@testable import SceneryKit

/// The road's colours are the first thing in this app that a designer will want to keep
/// tweaking, and the word card sits directly on top of them. So the readability rule is a
/// test, not a comment: a palette that would put white text under 7:1 fails here, before
/// anyone has to notice it on a screen while trying to type.
@Suite("RideRoute — the road, and the contrast it owes the text")
struct RideRouteTests {

    /// The road an unentitled rider is on. These tests are about how the FREE road resolves, so
    /// they name it rather than taking whatever `stages(westOpen:)` happens to return — a test
    /// that silently followed the entitlement would stop testing the thing it is named for the
    /// moment the flag moved.
    ///
    /// The palette and well-formedness tests below deliberately go the other way and cover
    /// `westOpen: true`: a paid stretch that is unreadable or indistinguishable from its
    /// neighbour is a defect somebody paid for.
    private let free = RideRoute.stages(westOpen: false)

    @Test("every stretch keeps white text at 7:1 or better through its own scrim and the card")
    func everyStageIsReadable() {
        for stage in RideRoute.stages(westOpen: true) {
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
        let base = RideRoute.tokaidoStages[7].palette      // 京都, night
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
        let base = RideRoute.tokaidoStages[7].palette
        var extreme = base
        extreme.land = RGB(1, 1, 1)
        #expect(extreme.textScrim > RidePalette.baseScrim,
                "a white ground must still force extra scrim")
    }

    @Test("the first stretch is the palette the app already ships")
    func firstStageIsHome() {
        // Existing riders open the app onto the sky they know, and it still matches the icon.
        let home = RideRoute.home.palette
        #expect(home.skyTop == RGB(0.08, 0.11, 0.26))
        #expect(home.skyLow == RGB(0.98, 0.62, 0.46))
        #expect(home.road == RGB(0.82, 0.21, 0.21))
        #expect(RideRoute.home.startMetres == 0)
    }

    @Test("lifetime distance picks the stretch, and the boundaries are exact")
    func stageSelection() {
        #expect(RideRoute.stage(forLifetimeMetres: 0, in: free).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: 399, in: free).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: 400, in: free).name == "川崎", "a boundary is inclusive")
        #expect(RideRoute.stage(forLifetimeMetres: 1_199, in: free).name == "川崎")
        #expect(RideRoute.stage(forLifetimeMetres: 2_500, in: free).name == "富士")
        #expect(RideRoute.stage(forLifetimeMetres: 24_999, in: free).name == "鈴鹿")
        #expect(RideRoute.stage(forLifetimeMetres: 25_000, in: free).name == "京都")
    }

    @Test("arriving is an ending, not a reset")
    func arrivalHolds() {
        #expect(RideRoute.stage(forLifetimeMetres: 1_000_000, in: free).name == "京都")
        #expect(RideRoute.metresToNextStage(forLifetimeMetres: 1_000_000, in: free) == nil)
        #expect(RideRoute.progressWithinStage(forLifetimeMetres: 1_000_000, in: free) == 1)
    }

    @Test("a nonsense odometer degrades to the first stretch instead of crashing")
    func garbageInput() {
        // The odometer is synced and grow-only; a corrupt or absurd value must not blank the
        // scene mid-ride.
        #expect(RideRoute.stage(forLifetimeMetres: -5_000, in: free).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: -.infinity, in: free).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: .nan, in: free).name == "日本橋")
        #expect(RideRoute.stage(forLifetimeMetres: .infinity, in: free).name == "京都", "infinity is ordered — it belongs at the far end, not at home")
    }

    @Test("thresholds only ever increase, and stage ids match their order")
    func routeIsWellFormed() {
        for (i, stage) in RideRoute.stages(westOpen: true).enumerated() {
            #expect(stage.id == i, "id must be the index — the scene indexes stages by it")
            if i > 0 {
                #expect(stage.startMetres > RideRoute.stages(westOpen: true)[i - 1].startMetres,
                        "\(stage.name) does not come after \(RideRoute.stages(westOpen: true)[i - 1].name)")
            }
        }
    }

    @Test("every stretch's landmark is one the scene can actually draw")
    func landmarksAreOnesTheSceneCanDraw() throws {
        // `RideStage.landmark`'s doc comment has named four kinds — 0 Fuji, 1 torii, 2 castle,
        // 3 tower — since v1.12, and until v1.30 **nothing whatsoever enforced it**: zero test
        // files contained the word `landmark`. `RideBackgroundView.drawLandmark` switches on
        // 1/2/3 and sends everything else to a `default:` that draws Fuji, so a typo'd value is
        // not a crash, it is a stretch quietly wearing the wrong silhouette forever.
        //
        // This project's cheapest detector, applied: where a comment states a contract, check
        // whether anything enforces it. So rather than hardcoding 0...3 here — which would be
        // the same unenforced claim written a second time, the "one rule written twice will
        // drift" trap — the drawable set is READ OUT of the shipping drawing code.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = root.appendingPathComponent("Sources/NihongoRideApp/RideBackgroundView.swift")
        let source = try String(contentsOf: view, encoding: .utf8)

        // Bounded to drawLandmark's OWN body. Reading "from the declaration to the end of file"
        // was the first version of this and it is the project's rule-5 defect — correct rule,
        // wrong population: drawLandmark starts at line 184 of 252, so the scan also read
        // `drawCloud`. Harmless today because drawCloud has no numeric cases, and the moment any
        // function added after it switches over a cloud style or a lane count, that number would
        // be admitted as a drawable landmark and a stage asking for a silhouette the scene cannot
        // draw would ship as Fuji with this guard still green.
        let start = try #require(source.range(of: "private func drawLandmark"))
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    private func") ?? rest.range(of: "\n}")
        let body = String(end.map { rest[..<$0.lowerBound] } ?? rest)
        #expect(body.count < source.count / 2,
                "the scan read \(body.count) of \(source.count) characters — it is not bounded to one function")
        var drawable = Set<Int>()
        for match in body.matches(of: /\n\s*case (\d+):/) {
            drawable.insert(Int(match.output.1)!)
        }
        // `default:` is the Fuji branch, so 0 is drawable without a case of its own.
        #expect(body.contains("default:"), "drawLandmark lost its default branch — re-read this test")
        drawable.insert(0)
        #expect(drawable.count >= 4,
                "only found \(drawable.sorted()) in drawLandmark — the scan read too little to judge")

        for stage in RideRoute.stages(westOpen: true) {
            let kinds = drawable.sorted()
            #expect(drawable.contains(stage.landmark),
                    "\(stage.name) asks for landmark \(stage.landmark); drawLandmark draws \(kinds) and silently substitutes Fuji for anything else")
        }
    }

    @Test("progress within a stretch runs 0→1 and never escapes it")
    func progressWithin() {
        #expect(RideRoute.progressWithinStage(forLifetimeMetres: 400, in: free) == 0)
        #expect(abs(RideRoute.progressWithinStage(forLifetimeMetres: 800, in: free) - 0.5) < 0.001)
        #expect(RideRoute.progressWithinStage(forLifetimeMetres: 1_199, in: free) < 1)
        for m in stride(from: -1_000.0, through: 30_000.0, by: 137.0) {
            let p = RideRoute.progressWithinStage(forLifetimeMetres: m, in: free)
            #expect(p >= 0 && p <= 1, "progress escaped 0...1 at \(m) m")
        }
    }

    @Test("consecutive stretches actually look different — sky AND road surface")
    func stagesAreDistinct() {
        // Luminance delta was the first version of this check and it was the wrong proxy:
        // Kawasaki red → Hakone blue-grey is a large visible material change at a luminance
        // delta of 0.013. Colour DISTANCE in component space is what the eye gets.
        func dist(_ a: RGB, _ b: RGB) -> Double {
            ((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g)
             + (a.b - b.b) * (a.b - b.b)).squareRoot()
        }
        // Across BOTH roads, and specifically across the seam: 京都 → 大阪 is the one boundary a
        // rider crosses by paying, so it is the one boundary where "the road barely changes"
        // would read as having been sold nothing.
        let road = RideRoute.stages(westOpen: true)
        for i in 1 ..< road.count {
            let a = road[i - 1].palette, b = road[i].palette
            let skyShift = dist(a.skyMid, b.skyMid) + dist(a.skyLow, b.skyLow)
            #expect(skyShift > 0.10,
                    "sky \(road[i - 1].name) → \(road[i].name) too subtle")
            // The road is the dominant on-screen element; every boundary must change its
            // surface visibly. 0.12 is what the shipped values clear with margin (min 0.146).
            #expect(dist(a.road, b.road) >= 0.12,
                    "road \(road[i - 1].name) → \(road[i].name) barely changes")
        }
    }

    @Test("interpolation stays inside the palette and can't blow past a colour")
    func lerpIsBounded() {
        let a = RideRoute.home.palette, b = RideRoute.tokaidoStages[7].palette
        #expect(a.lerp(to: b, 0) == a)
        #expect(a.lerp(to: b, 1) == b)
        #expect(a.lerp(to: b, -3) == a, "out-of-range t clamps rather than extrapolating")
        #expect(a.lerp(to: b, 9) == b)
        let mid = a.lerp(to: b, 0.5)
        let contrast = (1.0 + 0.05) / (mid.compositeLuminance(scrim: mid.textScrim) + 0.05)
        #expect(contrast >= 7.0, "a half-way blend must be readable too")
    }
}
