import Testing
import Foundation
@testable import SceneryKit

/// **The red line, as a test rather than a promise.**
///
/// Stage 1's first hard constraint is that no existing install loses anything, ever, *enforced in
/// code*. This file is that enforcement. It is separate from `RideRouteTests` because those tests
/// are about whether the road is well-made; these are about whether v1.30's road is, for an
/// unentitled rider, indistinguishable from v1.29's.
///
/// ## Why a golden file and not an assertion
///
/// The obvious test — "the Tōkaidō still resolves correctly" — is circular: it checks v1.30's
/// code against v1.30's code, and would stay green through any change made consistently in both
/// places. `Fixtures/tokaido-v1.29-sweep.json` was produced by **compiling v1.29's own
/// `RideRoute.swift` out of git (`48de373`) and running it**, so the thing being compared against
/// is the shipped behaviour, not a restatement of the current behaviour.
///
/// ## What the previous suite would NOT have caught
///
/// Measured before writing this, by appending one paid stage at 40,000 m to the v1.29 array and
/// re-running the old tests: `arrivalHolds` fails only **one of its three assertions**, because it
/// probes at 1,000,000 m — past the new threshold too, where the new last stage is terminal in its
/// turn. The real damage lands at 30,000 m, a rider just past Kyōto, and **no test in the suite
/// asserted anything there at all.** The assertion point had been chosen for the old array's
/// geometry, so the number the test checked and the property the comment claimed were computed
/// over different domains — this project's signature defect, sitting inside the safety net.
///
/// The sweep below covers −2,000 … 40,000 at 37 m, every threshold ±1, both infinities and NaN.
@Suite("The Tōkaidō is frozen")
struct RideRouteFreezeTests {

    private static var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tokaido-v1.29-sweep.json")
    }

    private static func golden() throws -> [[String: String]] {
        let data = try Data(contentsOf: fixture)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
    }

    /// Re-derives one golden row from a road. Used by the real assertion AND by its negative
    /// control, so the control cannot pass by testing something else.
    private static func answer(_ raw: String, on stages: [RideStage]) -> (String, String, String) {
        let m = raw == "nan" ? Double.nan : Double(raw)!
        let stage = RideRoute.stage(forLifetimeMetres: m, in: stages)
        let p = RideRoute.progressWithinStage(forLifetimeMetres: m, in: stages)
        let n = RideRoute.metresToNextStage(forLifetimeMetres: m, in: stages)
        return (stage.name,
                String(format: "%.9f", p),
                n.map { $0.isNaN ? "nan" : String(format: "%.6f", $0) } ?? "nil")
    }

    @Test("an unentitled rider's road answers exactly what v1.29 answered, at 1,167 points")
    func theTokaidoResolvesExactlyAsItDid() throws {
        let golden = try Self.golden()
        #expect(golden.count > 1_000, "the golden is too small to have covered anything")

        let free = RideRoute.stages(westOpen: false)
        var mismatches: [String] = []
        for row in golden {
            let (name, progress, next) = Self.answer(row["m"]!, on: free)
            if name != row["stage"] || progress != row["progress"] || next != row["next"] {
                mismatches.append("at \(row["m"]!): v1.29 said \(row["stage"]!)/\(row["progress"]!)/\(row["next"]!), "
                                  + "now \(name)/\(progress)/\(next)")
            }
        }
        let detail = mismatches.prefix(8).joined(separator: "\n")
        #expect(mismatches.isEmpty, "the free road moved under existing riders:\n\(detail)")
    }

    @Test("and that sweep is proven able to fail, on the exact mistake it exists to catch")
    func theSweepCanFail() throws {
        // The committed negative control. A green invariant that has never been shown to go red
        // is indistinguishable from one that reads nothing — this project has paid for that five
        // times. So the mistake is constructed here and the sweep is required to reject it:
        // one paid stage appended to what an UNENTITLED rider is handed.
        let golden = try Self.golden()
        let leaked = RideRoute.tokaidoStages + [RideRoute.westStages[0]]

        var mismatches = 0
        var firstDivergence: String?
        for row in golden {
            let (name, progress, next) = Self.answer(row["m"]!, on: leaked)
            if name != row["stage"] || progress != row["progress"] || next != row["next"] {
                mismatches += 1
                if firstDivergence == nil { firstDivergence = row["m"]! }
            }
        }
        #expect(mismatches > 0, "the sweep accepted a paid stage on the free road — it proves nothing")
        // And it must catch it well before the far end: the old suite's 1,000,000 m probe was
        // blind to exactly this because both roads are terminal out there.
        let divergedAt = Double(try #require(firstDivergence)) ?? .infinity
        #expect(divergedAt < 30_000,
                "the sweep only notices past 30 km, which is where the old suite already looked")
    }

    @Test("the eight free stretches are exactly the eight that shipped, field by field")
    func theTokaidoIsFrozen() {
        // Per-stage digests rather than one hash for the array: a single digest tells you
        // something broke and not what, and a failure message that cannot name the stage gets
        // "fixed" by pasting in the new value.
        func digest(_ s: RideStage) -> String {
            func rgb(_ c: RGB) -> String { String(format: "%.2f,%.2f,%.2f", c.r, c.g, c.b) }
            let p = s.palette
            return [String(s.id), s.road.rawValue, s.name, s.romaji, String(s.startMetres),
                    String(s.landmark),
                    rgb(p.skyTop), rgb(p.skyMid), rgb(p.skyLow), rgb(p.sun),
                    String(format: "%.2f", p.sunGlow), String(format: "%.2f", p.cloudAlpha),
                    rgb(p.landFar), rgb(p.land), rgb(p.roadFar), rgb(p.road),
                    rgb(p.lane), rgb(p.silhouette)].joined(separator: "|")
        }
        let expected = [
            "0|tokaido|日本橋|Nihonbashi|0.0|3|0.08,0.11,0.26|0.36,0.30,0.50|0.98,0.62,0.46|0.99,0.86,0.55|0.55|0.50|0.16,0.55,0.52|0.08,0.32,0.35|0.45,0.14,0.18|0.82,0.21,0.21|0.98,0.80,0.35|0.24,0.28,0.50",
            "1|tokaido|川崎|Kawasaki|400.0|1|0.10,0.16,0.32|0.30,0.38,0.58|0.86,0.72,0.60|0.98,0.90,0.72|0.42|0.44|0.14,0.44,0.48|0.07,0.26,0.32|0.36,0.16,0.20|0.68,0.24,0.24|0.96,0.82,0.44|0.20,0.26,0.44",
            "2|tokaido|箱根|Hakone|1200.0|0|0.06,0.12,0.28|0.20,0.34,0.56|0.62,0.74,0.84|0.86,0.90,0.96|0.22|0.40|0.12,0.34,0.44|0.06,0.20,0.30|0.21,0.20,0.24|0.38,0.36,0.44|0.80,0.82,0.72|0.16,0.24,0.42",
            "3|tokaido|富士|Fuji|2500.0|0|0.10,0.24,0.48|0.28,0.50,0.74|0.72,0.86,0.94|0.94,0.90,0.78|0.20|0.40|0.13,0.42,0.42|0.06,0.24,0.28|0.22,0.18,0.17|0.40,0.32,0.30|0.92,0.84,0.60|0.22,0.30,0.52",
            "4|tokaido|浜名湖|Hamanako|5000.0|1|0.08,0.20,0.36|0.24,0.46,0.58|0.80,0.80,0.66|0.99,0.92,0.66|0.40|0.46|0.10,0.44,0.44|0.05,0.26,0.30|0.32,0.26,0.19|0.58,0.48,0.34|0.42,0.28,0.16|0.18,0.30,0.46",
            "5|tokaido|名古屋|Nagoya|9000.0|2|0.12,0.14,0.30|0.42,0.34,0.48|0.96,0.72,0.48|1.00,0.88,0.58|0.50|0.42|0.16,0.48,0.44|0.08,0.28,0.30|0.33,0.17,0.11|0.60,0.30,0.20|0.98,0.82,0.38|0.24,0.26,0.44",
            "6|tokaido|鈴鹿|Suzuka|15000.0|2|0.06,0.07,0.20|0.30,0.20,0.40|0.86,0.46,0.40|0.98,0.68,0.44|0.46|0.38|0.12,0.36,0.38|0.05,0.20,0.26|0.19,0.15,0.18|0.34,0.28,0.32|0.88,0.78,0.50|0.14,0.16,0.34",
            "7|tokaido|京都|Kyōto|25000.0|1|0.04,0.05,0.16|0.16,0.14,0.34|0.52,0.30,0.42|0.98,0.84,0.62|0.34|0.30|0.10,0.30,0.34|0.04,0.16,0.22|0.12,0.11,0.20|0.22,0.20,0.36|0.98,0.76,0.36|0.12,0.14,0.30",
        ]
        #expect(RideRoute.tokaidoStages.count == 8, "a stretch was added to or removed from the free road")
        for (stage, want) in zip(RideRoute.tokaidoStages, expected) {
            #expect(digest(stage) == want, "\(stage.name) changed")
        }
    }

    @Test("opening the west road only ever APPENDS — the free road is a prefix of the full one")
    func theFullRoadIsAdditive() {
        let free = RideRoute.stages(westOpen: false)
        let full = RideRoute.stages(westOpen: true)
        #expect(full.count > free.count)
        #expect(Array(full.prefix(free.count)) == free,
                "buying the road west rewrote a stretch the rider already had")
        #expect(free == RideRoute.tokaidoStages)
    }

    @Test("ids are indices on both roads, which is what makes a stage addressable at all")
    func idsAreIndices() {
        for (i, stage) in RideRoute.stages(westOpen: true).enumerated() {
            #expect(stage.id == i, "\(stage.name) has id \(stage.id) at index \(i)")
        }
        #expect(Set(RideRoute.stages(westOpen: true).map(\.id)).count == 16, "two stretches share an id")
    }

    @Test("the free road is entirely Tōkaidō and the paid road is entirely not")
    func roadsAreLabelledHonestly() {
        #expect(RideRoute.tokaidoStages.allSatisfy { $0.road == .tokaido })
        #expect(RideRoute.westStages.allSatisfy { $0.road == .west })
        #expect(RideRoute.home.road == .tokaido, "the default stretch must never be one somebody paid for")
    }

    @Test("arriving at Kyōto is defined by the road itself, not by a number written twice")
    func arrivalTracksTheRoad() {
        let kyoto = RideRoute.tokaidoStages.last!.startMetres
        #expect(!RideRoute.hasArrivedAtKyoto(lifetimeMetres: kyoto - 1))
        #expect(RideRoute.hasArrivedAtKyoto(lifetimeMetres: kyoto))
        #expect(RideRoute.hasArrivedAtKyoto(lifetimeMetres: 1_000_000))
        #expect(!RideRoute.hasArrivedAtKyoto(lifetimeMetres: .nan), "a corrupt odometer must not claim arrival")
        #expect(!RideRoute.hasArrivedAtKyoto(lifetimeMetres: -.infinity))
        #expect(RideRoute.hasArrivedAtKyoto(lifetimeMetres: .infinity))
    }
}
