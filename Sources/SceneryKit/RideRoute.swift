import Foundation

/// One stretch of the old road, with the colours you ride it under.
public struct RideStage: Sendable, Equatable, Identifiable {
    /// Stable index along the route, 0-based.
    public let id: Int
    /// Place name in Japanese.
    public let name: String
    /// English/romaji label, shown alongside for a learner who can't read it yet.
    public let romaji: String
    /// Lifetime metres at which this stretch begins.
    public let startMetres: Double
    /// Which horizon silhouette this stretch uses (matches RideBackgroundView's kinds:
    /// 0 Fuji, 1 torii, 2 castle, 3 tower).
    public let landmark: Int
    public let palette: RidePalette

    public init(id: Int, name: String, romaji: String, startMetres: Double,
                landmark: Int, palette: RidePalette) {
        self.id = id; self.name = name; self.romaji = romaji
        self.startMetres = startMetres; self.landmark = landmark; self.palette = palette
    }
}

/// The route your lifetime odometer walks you along: Edo to Kyoto, in eight stretches.
///
/// The road itself changes surface as it leaves the capital: the signature red holds for
/// the first two stretches (it is the app's icon), then wet Hakone stone, Fuji volcanic
/// grit, the sandy Hamanako causeway, Nagoya brick, dusk slate at Suzuka, and night
/// cobbles into Kyoto. (v1.12 §D2 — reviewed by Codex, colour distances asserted.)
///
/// Deliberately EIGHT well-known places, not the Tōkaidō's literal 53 post-towns, and
/// deliberately unnumbered. Naming "第14次 原" would be a factual claim about a historical
/// route, and this app teaches Japanese — a wrong reading here is a taught error, not a
/// cosmetic slip. Eight famous names whose readings are not in doubt buys the same feeling
/// of travelling a real road with none of that risk.
///
/// Which stretch you are on is chosen ONCE, when a run starts, and held for the whole run.
/// That is the legibility design, not an optimisation: nothing behind the word card can
/// change while someone is reading kana under time pressure.
public enum RideRoute {

    /// Thresholds are front-loaded on purpose. The second stretch arrives after a handful of
    /// rides so a new rider actually sees the road change and learns that it does; later ones
    /// stretch out so the road still has somewhere to go months in. Roughly: a journey ride is
    /// ~150 m and a time-attack ~350 m, so the last stretch is a few months of daily practice.
    ///
    /// ⚠️ These are effectively permanent. Retuning them moves every existing rider backwards
    /// or forwards along the road, which reads as the app taking something away.
    public static let stages: [RideStage] = [
        RideStage(id: 0, name: "日本橋", romaji: "Nihonbashi", startMetres: 0, landmark: 3,
                  palette: RidePalette(
                    // The shipped dawn, preserved exactly: it matches the app icon and it is
                    // what every existing rider already knows as home.
                    skyTop: RGB(0.08, 0.11, 0.26), skyMid: RGB(0.36, 0.30, 0.50),
                    skyLow: RGB(0.98, 0.62, 0.46),
                    sun: RGB(0.99, 0.86, 0.55), sunGlow: 0.55, cloudAlpha: 0.50,
                    landFar: RGB(0.16, 0.55, 0.52), land: RGB(0.08, 0.32, 0.35),
                    roadFar: RGB(0.45, 0.14, 0.18), road: RGB(0.82, 0.21, 0.21),
                    lane: RGB(0.98, 0.80, 0.35), silhouette: RGB(0.24, 0.28, 0.50))),

        RideStage(id: 1, name: "川崎", romaji: "Kawasaki", startMetres: 400, landmark: 1,
                  palette: RidePalette(
                    // River morning: the night lifts, haze on the water.
                    skyTop: RGB(0.10, 0.16, 0.32), skyMid: RGB(0.30, 0.38, 0.58),
                    skyLow: RGB(0.86, 0.72, 0.60),
                    sun: RGB(0.98, 0.90, 0.72), sunGlow: 0.42, cloudAlpha: 0.44,
                    landFar: RGB(0.14, 0.44, 0.48), land: RGB(0.07, 0.26, 0.32),
                    roadFar: RGB(0.36, 0.16, 0.20), road: RGB(0.68, 0.24, 0.24),
                    lane: RGB(0.96, 0.82, 0.44), silhouette: RGB(0.20, 0.26, 0.44))),

        RideStage(id: 2, name: "箱根", romaji: "Hakone", startMetres: 1_200, landmark: 0,
                  palette: RidePalette(
                    // The mountain pass: cold, high, thin air.
                    skyTop: RGB(0.06, 0.12, 0.28), skyMid: RGB(0.20, 0.34, 0.56),
                    skyLow: RGB(0.62, 0.74, 0.84),
                    sun: RGB(0.86, 0.90, 0.96), sunGlow: 0.22, cloudAlpha: 0.40,
                    landFar: RGB(0.12, 0.34, 0.44), land: RGB(0.06, 0.20, 0.30),
                    roadFar: RGB(0.21, 0.20, 0.24), road: RGB(0.38, 0.36, 0.44),
                    lane: RGB(0.80, 0.82, 0.72), silhouette: RGB(0.16, 0.24, 0.42))),

        RideStage(id: 3, name: "富士", romaji: "Fuji", startMetres: 2_500, landmark: 0,
                  palette: RidePalette(
                    // Clear day under the mountain — the widest, brightest sky on the road.
                    skyTop: RGB(0.10, 0.24, 0.48), skyMid: RGB(0.28, 0.50, 0.74),
                    skyLow: RGB(0.72, 0.86, 0.94),
                    sun: RGB(0.94, 0.90, 0.78), sunGlow: 0.20, cloudAlpha: 0.40,
                    landFar: RGB(0.13, 0.42, 0.42), land: RGB(0.06, 0.24, 0.28),
                    roadFar: RGB(0.22, 0.18, 0.17), road: RGB(0.40, 0.32, 0.30),
                    lane: RGB(0.92, 0.84, 0.60), silhouette: RGB(0.22, 0.30, 0.52))),

        RideStage(id: 4, name: "浜名湖", romaji: "Hamanako", startMetres: 5_000, landmark: 1,
                  palette: RidePalette(
                    // Lakeside: water light, low sun, everything a little green.
                    skyTop: RGB(0.08, 0.20, 0.36), skyMid: RGB(0.24, 0.46, 0.58),
                    skyLow: RGB(0.80, 0.80, 0.66),
                    sun: RGB(0.99, 0.92, 0.66), sunGlow: 0.40, cloudAlpha: 0.46,
                    landFar: RGB(0.10, 0.44, 0.44), land: RGB(0.05, 0.26, 0.30),
                    roadFar: RGB(0.32, 0.26, 0.19), road: RGB(0.58, 0.48, 0.34),
                    lane: RGB(0.42, 0.28, 0.16), silhouette: RGB(0.18, 0.30, 0.46))),

        RideStage(id: 5, name: "名古屋", romaji: "Nagoya", startMetres: 9_000, landmark: 2,
                  palette: RidePalette(
                    // The plain, late afternoon, warm and open.
                    skyTop: RGB(0.12, 0.14, 0.30), skyMid: RGB(0.42, 0.34, 0.48),
                    skyLow: RGB(0.96, 0.72, 0.48),
                    sun: RGB(1.00, 0.88, 0.58), sunGlow: 0.50, cloudAlpha: 0.42,
                    landFar: RGB(0.16, 0.48, 0.44), land: RGB(0.08, 0.28, 0.30),
                    roadFar: RGB(0.33, 0.17, 0.11), road: RGB(0.60, 0.30, 0.20),
                    lane: RGB(0.98, 0.82, 0.38), silhouette: RGB(0.24, 0.26, 0.44))),

        RideStage(id: 6, name: "鈴鹿", romaji: "Suzuka", startMetres: 15_000, landmark: 2,
                  palette: RidePalette(
                    // Hills at dusk: the light goes, the silhouettes come forward.
                    skyTop: RGB(0.06, 0.07, 0.20), skyMid: RGB(0.30, 0.20, 0.40),
                    skyLow: RGB(0.86, 0.46, 0.40),
                    sun: RGB(0.98, 0.68, 0.44), sunGlow: 0.46, cloudAlpha: 0.38,
                    landFar: RGB(0.12, 0.36, 0.38), land: RGB(0.05, 0.20, 0.26),
                    roadFar: RGB(0.19, 0.15, 0.18), road: RGB(0.34, 0.28, 0.32),
                    lane: RGB(0.88, 0.78, 0.50), silhouette: RGB(0.14, 0.16, 0.34))),

        RideStage(id: 7, name: "京都", romaji: "Kyōto", startMetres: 25_000, landmark: 1,
                  palette: RidePalette(
                    // Arrival: night over the old capital, lantern-warm.
                    skyTop: RGB(0.04, 0.05, 0.16), skyMid: RGB(0.16, 0.14, 0.34),
                    skyLow: RGB(0.52, 0.30, 0.42),
                    sun: RGB(0.98, 0.84, 0.62), sunGlow: 0.34, cloudAlpha: 0.30,
                    landFar: RGB(0.10, 0.30, 0.34), land: RGB(0.04, 0.16, 0.22),
                    roadFar: RGB(0.12, 0.11, 0.20), road: RGB(0.22, 0.20, 0.36),
                    lane: RGB(0.98, 0.76, 0.36), silhouette: RGB(0.12, 0.14, 0.30))),
    ]

    /// The stretch a rider with this lifetime distance is on.
    ///
    /// Clamps at both ends: below zero is the first stretch (a nonsense odometer must not
    /// crash or blank the scene), and past the last threshold you simply stay in Kyoto —
    /// arriving is an ending, not a reset to the start.
    ///
    /// Only NaN is special-cased, because only NaN is genuinely un-orderable: every
    /// comparison against it is false, which would silently pick the first stretch anyway.
    /// Infinities are ordered, so they fall out at the ends on their own.
    public static func stage(forLifetimeMetres metres: Double) -> RideStage {
        guard !metres.isNaN else { return stages[0] }
        var current = stages[0]
        for stage in stages where metres >= stage.startMetres { current = stage }
        return current
    }

    /// How far into the current stretch, 0-1, for a progress readout. The final stretch has
    /// no end, so it reports 1 once reached.
    public static func progressWithinStage(forLifetimeMetres metres: Double) -> Double {
        let stage = self.stage(forLifetimeMetres: metres)
        guard stage.id + 1 < stages.count else { return 1 }
        let next = stages[stage.id + 1]
        let span = next.startMetres - stage.startMetres
        guard span > 0 else { return 1 }
        return min(max((metres - stage.startMetres) / span, 0), 1)
    }

    /// Metres still to ride before the road changes, or nil once at the last stretch.
    public static func metresToNextStage(forLifetimeMetres metres: Double) -> Double? {
        let stage = self.stage(forLifetimeMetres: metres)
        guard stage.id + 1 < stages.count else { return nil }
        return max(0, stages[stage.id + 1].startMetres - metres)
    }
}
