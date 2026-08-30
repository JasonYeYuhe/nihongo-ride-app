import Foundation

/// Which of the two journeys a stretch belongs to.
///
/// This exists so the app can say **"the Tōkaidō, arrived"** rather than **"stretch 8 of 16"**,
/// and that distinction is the whole point rather than a label.
///
/// `RideRoute.tokaidoStages` and `RideRoute.westStages` are stored separately and the free road
/// is a prefix of the full one, so *structurally* nothing is ever taken away from anyone. But a
/// structural guarantee does not cover the thing most likely to actually hurt: before Stage 1 the
/// Tōkaidō was **the** road and Kyōto was where it ended, and a rider who got there had finished
/// something. Presenting the same data as one sixteen-stretch bar would quietly convert their
/// completed journey into a half-finished one — no byte removed, and a real loss — and nothing in
/// this app could ever observe that happening, because there is no telemetry and there will not
/// be. So the guard has to be in the design.
///
/// **Stated as what it is: a judgement, not a measurement.** Nobody has watched a rider react to
/// either presentation. What the code can do is make the honest presentation the easy one, which
/// is why the road a stretch belongs to travels *with* the stretch instead of being derived from
/// its index by whoever draws it.
public enum RideRoad: String, Sendable, Equatable, CaseIterable, Codable {
    /// 日本橋 → 京都. Free, complete, and unchanged since v1.12.
    case tokaido
    /// 京都 → 長崎, west along the inland sea. Opened by one non-consumable purchase.
    case west
}

/// One stretch of the old road, with the colours you ride it under.
public struct RideStage: Sendable, Equatable, Identifiable {
    /// Stable index along the WHOLE road, 0-based: 0…7 are the Tōkaidō, 8…15 run west.
    ///
    /// Global rather than per-road so that two stretches never share an id — `Identifiable`
    /// conformance, the screenshot filenames and `progressWithinStage`'s lookup all key on it,
    /// and duplicate ids would make each of those wrong in a different, quiet way.
    public let id: Int
    /// Which journey this stretch belongs to. See `RideRoad`.
    public let road: RideRoad
    /// Place name in Japanese.
    public let name: String
    /// English/romaji label, shown alongside for a learner who can't read it yet.
    public let romaji: String
    /// Lifetime metres at which this stretch begins.
    public let startMetres: Double
    /// Which horizon silhouette this stretch uses (matches RideBackgroundView's kinds:
    /// 0 Fuji, 1 torii, 2 castle, 3 tower).
    ///
    /// ⚠️ `RideBackgroundView.drawLandmark` switches on 1/2/3 and sends **everything else** to a
    /// `default:` that draws Fuji. So an out-of-range value is not a crash — it is a silently
    /// wrong silhouette, which is worse. Held by `RideRouteTests.landmarksAreOnesTheSceneCanDraw`,
    /// which reads the shipped drawing code rather than trusting this sentence: until v1.30 this
    /// comment stated the contract and nothing whatsoever enforced it.
    public let landmark: Int
    public let palette: RidePalette

    public init(id: Int, road: RideRoad, name: String, romaji: String, startMetres: Double,
                landmark: Int, palette: RidePalette) {
        self.id = id; self.road = road; self.name = name; self.romaji = romaji
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

    /// The Tōkaidō. **Free, complete, and frozen** — these eight are exactly what shipped in
    /// v1.29 and nothing may ever be appended to this array.
    ///
    /// Thresholds are front-loaded on purpose. The second stretch arrives after a handful of
    /// rides so a new rider actually sees the road change and learns that it does; later ones
    /// stretch out so the road still has somewhere to go months in.
    ///
    /// **The ride distances that sentence rests on, measured 2026-08-30 rather than estimated.**
    /// This comment used to read "a journey ride is ~150 m and a time-attack ~350 m, so the last
    /// stretch is a few months of daily practice", and the 150 was not wrong so much as
    /// calibrated on the wrong population and then used as a constant: **the FIRST ride is
    /// exactly 150 m** — its twelve words are き・て・め・に・ご・え・く・は・せ・みず・あさ・よる,
    /// nine of them a single kana — because `VocabStore.ordered` deals by `difficulty`, whose
    /// `0.6 × length` term puts the short words first. Averaged over the road to Kyōto a journey
    /// ride is **351 m** on new words alone and **535 m** with the review mix, so Kyōto is
    /// **47–72 rides**, and the last stretch is roughly 19–28 rides rather than months.
    /// `Tests/RoadDataTests` pins those numbers by riding real `GameSession`s, so the next corpus
    /// change reports the new figure instead of leaving this paragraph to rot the way the old one
    /// did.
    ///
    /// ⚠️ These are effectively permanent. Retuning them moves every existing rider backwards
    /// or forwards along the road, which reads as the app taking something away.
    public static let tokaidoStages: [RideStage] = [
        RideStage(id: 0, road: .tokaido, name: "日本橋", romaji: "Nihonbashi", startMetres: 0, landmark: 3,
                  palette: RidePalette(
                    // The shipped dawn, preserved exactly: it matches the app icon and it is
                    // what every existing rider already knows as home.
                    skyTop: RGB(0.08, 0.11, 0.26), skyMid: RGB(0.36, 0.30, 0.50),
                    skyLow: RGB(0.98, 0.62, 0.46),
                    sun: RGB(0.99, 0.86, 0.55), sunGlow: 0.55, cloudAlpha: 0.50,
                    landFar: RGB(0.16, 0.55, 0.52), land: RGB(0.08, 0.32, 0.35),
                    roadFar: RGB(0.45, 0.14, 0.18), road: RGB(0.82, 0.21, 0.21),
                    lane: RGB(0.98, 0.80, 0.35), silhouette: RGB(0.24, 0.28, 0.50))),

        RideStage(id: 1, road: .tokaido, name: "川崎", romaji: "Kawasaki", startMetres: 400, landmark: 1,
                  palette: RidePalette(
                    // River morning: the night lifts, haze on the water.
                    skyTop: RGB(0.10, 0.16, 0.32), skyMid: RGB(0.30, 0.38, 0.58),
                    skyLow: RGB(0.86, 0.72, 0.60),
                    sun: RGB(0.98, 0.90, 0.72), sunGlow: 0.42, cloudAlpha: 0.44,
                    landFar: RGB(0.14, 0.44, 0.48), land: RGB(0.07, 0.26, 0.32),
                    roadFar: RGB(0.36, 0.16, 0.20), road: RGB(0.68, 0.24, 0.24),
                    lane: RGB(0.96, 0.82, 0.44), silhouette: RGB(0.20, 0.26, 0.44))),

        RideStage(id: 2, road: .tokaido, name: "箱根", romaji: "Hakone", startMetres: 1_200, landmark: 0,
                  palette: RidePalette(
                    // The mountain pass: cold, high, thin air.
                    skyTop: RGB(0.06, 0.12, 0.28), skyMid: RGB(0.20, 0.34, 0.56),
                    skyLow: RGB(0.62, 0.74, 0.84),
                    sun: RGB(0.86, 0.90, 0.96), sunGlow: 0.22, cloudAlpha: 0.40,
                    landFar: RGB(0.12, 0.34, 0.44), land: RGB(0.06, 0.20, 0.30),
                    roadFar: RGB(0.21, 0.20, 0.24), road: RGB(0.38, 0.36, 0.44),
                    lane: RGB(0.80, 0.82, 0.72), silhouette: RGB(0.16, 0.24, 0.42))),

        RideStage(id: 3, road: .tokaido, name: "富士", romaji: "Fuji", startMetres: 2_500, landmark: 0,
                  palette: RidePalette(
                    // Clear day under the mountain — the widest, brightest sky on the road.
                    skyTop: RGB(0.10, 0.24, 0.48), skyMid: RGB(0.28, 0.50, 0.74),
                    skyLow: RGB(0.72, 0.86, 0.94),
                    sun: RGB(0.94, 0.90, 0.78), sunGlow: 0.20, cloudAlpha: 0.40,
                    landFar: RGB(0.13, 0.42, 0.42), land: RGB(0.06, 0.24, 0.28),
                    roadFar: RGB(0.22, 0.18, 0.17), road: RGB(0.40, 0.32, 0.30),
                    lane: RGB(0.92, 0.84, 0.60), silhouette: RGB(0.22, 0.30, 0.52))),

        RideStage(id: 4, road: .tokaido, name: "浜名湖", romaji: "Hamanako", startMetres: 5_000, landmark: 1,
                  palette: RidePalette(
                    // Lakeside: water light, low sun, everything a little green.
                    skyTop: RGB(0.08, 0.20, 0.36), skyMid: RGB(0.24, 0.46, 0.58),
                    skyLow: RGB(0.80, 0.80, 0.66),
                    sun: RGB(0.99, 0.92, 0.66), sunGlow: 0.40, cloudAlpha: 0.46,
                    landFar: RGB(0.10, 0.44, 0.44), land: RGB(0.05, 0.26, 0.30),
                    roadFar: RGB(0.32, 0.26, 0.19), road: RGB(0.58, 0.48, 0.34),
                    lane: RGB(0.42, 0.28, 0.16), silhouette: RGB(0.18, 0.30, 0.46))),

        RideStage(id: 5, road: .tokaido, name: "名古屋", romaji: "Nagoya", startMetres: 9_000, landmark: 2,
                  palette: RidePalette(
                    // The plain, late afternoon, warm and open.
                    skyTop: RGB(0.12, 0.14, 0.30), skyMid: RGB(0.42, 0.34, 0.48),
                    skyLow: RGB(0.96, 0.72, 0.48),
                    sun: RGB(1.00, 0.88, 0.58), sunGlow: 0.50, cloudAlpha: 0.42,
                    landFar: RGB(0.16, 0.48, 0.44), land: RGB(0.08, 0.28, 0.30),
                    roadFar: RGB(0.33, 0.17, 0.11), road: RGB(0.60, 0.30, 0.20),
                    lane: RGB(0.98, 0.82, 0.38), silhouette: RGB(0.24, 0.26, 0.44))),

        RideStage(id: 6, road: .tokaido, name: "鈴鹿", romaji: "Suzuka", startMetres: 15_000, landmark: 2,
                  palette: RidePalette(
                    // Hills at dusk: the light goes, the silhouettes come forward.
                    skyTop: RGB(0.06, 0.07, 0.20), skyMid: RGB(0.30, 0.20, 0.40),
                    skyLow: RGB(0.86, 0.46, 0.40),
                    sun: RGB(0.98, 0.68, 0.44), sunGlow: 0.46, cloudAlpha: 0.38,
                    landFar: RGB(0.12, 0.36, 0.38), land: RGB(0.05, 0.20, 0.26),
                    roadFar: RGB(0.19, 0.15, 0.18), road: RGB(0.34, 0.28, 0.32),
                    lane: RGB(0.88, 0.78, 0.50), silhouette: RGB(0.14, 0.16, 0.34))),

        RideStage(id: 7, road: .tokaido, name: "京都", romaji: "Kyōto", startMetres: 25_000, landmark: 1,
                  palette: RidePalette(
                    // Arrival: night over the old capital, lantern-warm.
                    skyTop: RGB(0.04, 0.05, 0.16), skyMid: RGB(0.16, 0.14, 0.34),
                    skyLow: RGB(0.52, 0.30, 0.42),
                    sun: RGB(0.98, 0.84, 0.62), sunGlow: 0.34, cloudAlpha: 0.30,
                    landFar: RGB(0.10, 0.30, 0.34), land: RGB(0.04, 0.16, 0.22),
                    roadFar: RGB(0.12, 0.11, 0.20), road: RGB(0.22, 0.20, 0.36),
                    lane: RGB(0.98, 0.76, 0.36), silhouette: RGB(0.12, 0.14, 0.30))),
    ]

    /// The road west out of Kyōto, opened by one non-consumable purchase.
    ///
    /// **Eight more famous places whose readings are not in doubt** — 大阪 おおさか, 神戸 こうべ,
    /// 姫路 ひめじ, 岡山 おかやま, 広島 ひろしま, 下関 しものせき, 博多 はかた, 長崎 ながさき.
    /// The same discipline the Tōkaidō was built under, and for the same reason: this app teaches
    /// Japanese, so a place name whose reading is arguable is a taught error, not a cosmetic slip.
    /// Deliberately NOT named as a historical highway — 山陽道 would be a factual claim, and
    /// 長崎 is not on it.
    ///
    /// Colours run a second full day: out of the capital in the small hours, first light at the
    /// harbour, bright noon inland, gold over the sea, dusk on the strait, lanterns, and dawn
    /// again over the water where the road stops. Every value here was generated from the same
    /// table a checker verified against `RidePalette`'s own contrast rules, rather than typed by
    /// hand — 96 RGB triples is exactly the quantity where a transcription slip hides.
    ///
    /// Thresholds restart the Tōkaidō's own rhythm rather than continuing its acceleration, for
    /// the reason the array above states in its first paragraph: **a new road should change
    /// early enough that a rider learns it changes.** 大阪 arrives 3 km past Kyōto — about six
    /// rides — and the gaps then stretch to 35 km, so the road still goes somewhere a year in.
    ///
    /// ⚠️ Same permanence as the Tōkaidō, and one more constraint on top: these thresholds are
    /// what somebody PAID for. Moving them moves a buyer along a road they own.
    public static let westStages: [RideStage] = [

        RideStage(id: 8, road: .west, name: "大阪", romaji: "Ōsaka",
                  startMetres: 28_000, landmark: 2,
                  palette: RidePalette(
                    // Out of the capital in the small hours: city glow on the underside of the
                    // cloud, neon on wet asphalt. Still night, but a CITY night.
                    skyTop: RGB(0.05, 0.06, 0.18), skyMid: RGB(0.22, 0.20, 0.42),
                    skyLow: RGB(0.62, 0.42, 0.30),
                    sun: RGB(0.96, 0.78, 0.52), sunGlow: 0.3, cloudAlpha: 0.36,
                    landFar: RGB(0.10, 0.26, 0.36), land: RGB(0.05, 0.14, 0.24),
                    roadFar: RGB(0.17, 0.19, 0.22), road: RGB(0.30, 0.33, 0.36),
                    lane: RGB(0.62, 0.92, 0.94), silhouette: RGB(0.14, 0.16, 0.34))),

        RideStage(id: 9, road: .west, name: "神戸", romaji: "Kōbe",
                  startMetres: 32_000, landmark: 3,
                  palette: RidePalette(
                    // First light over the harbour — the blue goes cold, then rose.
                    skyTop: RGB(0.08, 0.14, 0.34), skyMid: RGB(0.26, 0.34, 0.58),
                    skyLow: RGB(0.92, 0.66, 0.58),
                    sun: RGB(0.99, 0.86, 0.70), sunGlow: 0.46, cloudAlpha: 0.44,
                    landFar: RGB(0.12, 0.38, 0.46), land: RGB(0.06, 0.22, 0.30),
                    roadFar: RGB(0.26, 0.26, 0.29), road: RGB(0.44, 0.44, 0.47),
                    lane: RGB(0.96, 0.86, 0.56), silhouette: RGB(0.18, 0.24, 0.44))),

        RideStage(id: 10, road: .west, name: "姫路", romaji: "Himeji",
                  startMetres: 38_000, landmark: 2,
                  palette: RidePalette(
                    // Bright morning under the white castle: the palest sky on either road.
                    skyTop: RGB(0.16, 0.32, 0.56), skyMid: RGB(0.40, 0.60, 0.80),
                    skyLow: RGB(0.86, 0.92, 0.96),
                    sun: RGB(0.98, 0.96, 0.88), sunGlow: 0.18, cloudAlpha: 0.38,
                    landFar: RGB(0.16, 0.46, 0.42), land: RGB(0.08, 0.26, 0.26),
                    roadFar: RGB(0.42, 0.38, 0.33), road: RGB(0.66, 0.60, 0.52),
                    lane: RGB(0.99, 0.94, 0.72), silhouette: RGB(0.24, 0.32, 0.54))),

        RideStage(id: 11, road: .west, name: "岡山", romaji: "Okayama",
                  startMetres: 47_000, landmark: 0,
                  palette: RidePalette(
                    // Inland noon. Deep green, dark earth, the sun small and straight overhead.
                    skyTop: RGB(0.10, 0.26, 0.50), skyMid: RGB(0.24, 0.48, 0.66),
                    skyLow: RGB(0.66, 0.82, 0.78),
                    sun: RGB(0.96, 0.94, 0.82), sunGlow: 0.16, cloudAlpha: 0.34,
                    landFar: RGB(0.10, 0.44, 0.34), land: RGB(0.05, 0.24, 0.20),
                    roadFar: RGB(0.22, 0.17, 0.13), road: RGB(0.36, 0.28, 0.22),
                    lane: RGB(0.90, 0.86, 0.58), silhouette: RGB(0.16, 0.30, 0.40))),

        RideStage(id: 12, road: .west, name: "広島", romaji: "Hiroshima",
                  startMetres: 60_000, landmark: 1,
                  palette: RidePalette(
                    // Late gold over the sea, the torii standing in the water.
                    skyTop: RGB(0.10, 0.16, 0.36), skyMid: RGB(0.38, 0.34, 0.50),
                    skyLow: RGB(0.98, 0.68, 0.42),
                    sun: RGB(1.00, 0.84, 0.50), sunGlow: 0.52, cloudAlpha: 0.4,
                    landFar: RGB(0.12, 0.40, 0.44), land: RGB(0.06, 0.22, 0.28),
                    roadFar: RGB(0.34, 0.22, 0.17), road: RGB(0.58, 0.38, 0.30),
                    lane: RGB(0.99, 0.86, 0.44), silhouette: RGB(0.22, 0.22, 0.42))),

        RideStage(id: 13, road: .west, name: "下関", romaji: "Shimonoseki",
                  startMetres: 78_000, landmark: 3,
                  palette: RidePalette(
                    // The strait at dusk: wind, steel, the light going out over open water.
                    skyTop: RGB(0.05, 0.10, 0.24), skyMid: RGB(0.18, 0.30, 0.44),
                    skyLow: RGB(0.56, 0.62, 0.66),
                    sun: RGB(0.84, 0.88, 0.92), sunGlow: 0.24, cloudAlpha: 0.48,
                    landFar: RGB(0.08, 0.32, 0.40), land: RGB(0.04, 0.18, 0.26),
                    roadFar: RGB(0.18, 0.20, 0.24), road: RGB(0.30, 0.34, 0.40),
                    lane: RGB(0.86, 0.90, 0.82), silhouette: RGB(0.12, 0.20, 0.36))),

        RideStage(id: 14, road: .west, name: "博多", romaji: "Hakata",
                  startMetres: 103_000, landmark: 1,
                  palette: RidePalette(
                    // Night, and the lanterns are lit — the warmest dark on either road.
                    skyTop: RGB(0.06, 0.04, 0.14), skyMid: RGB(0.24, 0.12, 0.26),
                    skyLow: RGB(0.72, 0.34, 0.30),
                    sun: RGB(0.99, 0.72, 0.44), sunGlow: 0.44, cloudAlpha: 0.28,
                    landFar: RGB(0.12, 0.28, 0.30), land: RGB(0.06, 0.15, 0.19),
                    roadFar: RGB(0.26, 0.14, 0.12), road: RGB(0.46, 0.24, 0.20),
                    lane: RGB(0.99, 0.80, 0.40), silhouette: RGB(0.14, 0.10, 0.26))),

        RideStage(id: 15, road: .west, name: "長崎", romaji: "Nagasaki",
                  startMetres: 138_000, landmark: 3,
                  palette: RidePalette(
                    // Dawn over the harbour. The road ends where the water starts.
                    skyTop: RGB(0.06, 0.10, 0.28), skyMid: RGB(0.20, 0.26, 0.50),
                    skyLow: RGB(0.86, 0.72, 0.70),
                    sun: RGB(0.99, 0.90, 0.78), sunGlow: 0.4, cloudAlpha: 0.34,
                    landFar: RGB(0.10, 0.34, 0.44), land: RGB(0.05, 0.20, 0.28),
                    roadFar: RGB(0.20, 0.19, 0.26), road: RGB(0.34, 0.32, 0.42),
                    lane: RGB(0.94, 0.84, 0.62), silhouette: RGB(0.16, 0.20, 0.40))),
    ]

    /// 日本橋 — where every rider starts, and the only safe default for a view or a model that
    /// has not been handed a stretch yet.
    ///
    /// Named rather than written as `tokaidoStages[0]` at each site because a default is exactly
    /// where a paid palette would leak to an unentitled rider without anyone noticing: this one
    /// is free by construction and cannot be re-pointed at the west road by an off-by-one.
    public static let home = tokaidoStages[0]

    // MARK: - The one place entitlement is read

    /// The stretches a rider can reach.
    ///
    /// **This is the only function in the package that takes an entitlement**, and everything
    /// below takes the resulting array instead of a Boolean. That split is deliberate and it is
    /// this project's most-repeated defect answered in advance: twenty-two times now a number
    /// shown and a run produced have been computed by different predicates, and every durable fix
    /// was to leave the two sides no way to disagree. If `stage(forLifetimeMetres:)` also took a
    /// `westOpen:` flag, the Settings row and the ride could each pass their own — and they would
    /// eventually differ. Here there is one array, and whoever holds it cannot be wrong about it.
    ///
    /// **`westOpen` has no default value, on purpose.** v1.24 §C removed ten `= { _ in true }`
    /// defaults from `resolves:` for exactly this reason: a defaulted argument lets every call
    /// site keep compiling while silently testing only the default, and one later flip rewrites
    /// what hundreds of green tests mean without a single one going red. Every caller states it.
    public static func stages(westOpen: Bool) -> [RideStage] {
        westOpen ? tokaidoStages + westStages : tokaidoStages
    }

    /// Every stretch that exists, **regardless of whether anyone paid for it.**
    ///
    /// For contact sheets, contrast checking and tests — never for a rider. It exists so that
    /// `stages(westOpen:)` is never called with a literal in shipping code: the developer
    /// screenshot pass legitimately needs all sixteen, and if it got them by passing `true` then
    /// `true` would be a normal thing to write at that call site, and the next person needing
    /// "all of them" for a less legitimate reason would write it too.
    ///
    /// `RouteSelectorTests.entitlementIsNeverALiteral` reads the shipped sources and fails if any
    /// file under `Sources/` hands `westOpen:` a constant. That is the enforcement; this comment
    /// is not — a contract stated in prose with nothing checking it is the defect this project
    /// finds most cheaply and keeps finding anyway.
    public static let everyStage: [RideStage] = tokaidoStages + westStages

    // MARK: - Resolution, over whichever road was handed in

    /// The stretch a rider with this lifetime distance is on.
    ///
    /// Clamps at both ends: below zero is the first stretch (a nonsense odometer must not
    /// crash or blank the scene), and past the last threshold you simply stay where the road
    /// ends — arriving is an ending, not a reset to the start.
    ///
    /// Only NaN is special-cased, because only NaN is genuinely un-orderable: every
    /// comparison against it is false, which would silently pick the first stretch anyway.
    /// Infinities are ordered, so they fall out at the ends on their own.
    ///
    /// The algorithm is byte-for-byte the one that shipped in v1.29, scanning every element and
    /// keeping the last one passed. That matters: `RideRouteFreezeTests.theTokaidoResolvesExactlyAsItDid`
    /// sweeps this against a golden table of v1.29's own answers, so "an unentitled rider's road
    /// is unchanged" is a checked property rather than a claim in a commit message.
    public static func stage(forLifetimeMetres metres: Double, in stages: [RideStage]) -> RideStage {
        precondition(!stages.isEmpty, "a road with no stretches cannot be ridden")
        guard !metres.isNaN else { return stages[0] }
        var current = stages[0]
        for stage in stages where metres >= stage.startMetres { current = stage }
        return current
    }

    /// How far into the current stretch, 0-1, for a progress readout. The final stretch has
    /// no end, so it reports 1 once reached.
    ///
    /// Locates the current stretch by SEARCHING the array rather than indexing it by `stage.id`.
    /// The two agree for every road this type can produce — and "they agree today" is precisely
    /// the reasoning that has failed here twenty-two times, so the code does not rely on it.
    public static func progressWithinStage(forLifetimeMetres metres: Double,
                                           in stages: [RideStage]) -> Double {
        let stage = self.stage(forLifetimeMetres: metres, in: stages)
        guard let i = stages.firstIndex(where: { $0.id == stage.id }), i + 1 < stages.count
        else { return 1 }
        let span = stages[i + 1].startMetres - stage.startMetres
        guard span > 0 else { return 1 }
        return min(max((metres - stage.startMetres) / span, 0), 1)
    }

    /// Metres still to ride before the road changes, or nil once at the last stretch.
    public static func metresToNextStage(forLifetimeMetres metres: Double,
                                         in stages: [RideStage]) -> Double? {
        let stage = self.stage(forLifetimeMetres: metres, in: stages)
        guard let i = stages.firstIndex(where: { $0.id == stage.id }), i + 1 < stages.count
        else { return nil }
        return max(0, stages[i + 1].startMetres - metres)
    }

    /// True once a rider has reached the end of the FREE road — the moment 京都 begins.
    ///
    /// Deliberately expressed against `tokaidoStages.last` rather than a literal 25,000, so the
    /// road and the thing that says you finished it cannot drift apart. Read by the offer copy
    /// ("how far away is this still useful") and by the local counter's furthest-reached bucket;
    /// both must mean the same "arrived" as the scene does.
    public static func hasArrivedAtKyoto(lifetimeMetres metres: Double) -> Bool {
        guard !metres.isNaN, let last = tokaidoStages.last else { return false }
        return metres >= last.startMetres
    }
}
