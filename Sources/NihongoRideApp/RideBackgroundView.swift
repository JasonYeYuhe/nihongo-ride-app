import SwiftUI
import SceneryKit

/// A first-person "riding" scene rendered in code — like a gym exercise-bike
/// screen. The road streams toward the viewer (faster with `speed`) under the
/// colours of the current `RideStage`: signature red out of 日本橋, Hakone stone,
/// Fuji grit, Hamanako sand, Nagoya brick, Suzuka slate, Kyoto night cobbles.
/// The stage's landmark grows on the horizon as `landmarkPhase` advances, so
/// both route progress and lifetime progress show in the scene.
struct RideBackgroundView: View {
    var speed: Double = 1
    /// 0→4 across a journey (≈ progress × landmark count); cycles in time-attack.
    var landmarkPhase: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The frozen phase used when the scene must not animate.
    ///
    /// Motion here comes from wall-clock time, so without a fixed value the still frame
    /// would land wherever the clock happened to be — which is precisely why every App
    /// Store screenshot had its clouds and lane dashes in a different, arbitrary place.
    /// Chosen by rendering candidates and picking the composition that keeps clouds off
    /// the HUD strip and spaces the dashes evenly.
    private static let stillPhase: TimeInterval = 1625.6

    /// The stretch of road this run is on. Chosen ONCE when the run starts and held for its
    /// whole length — nothing behind the word card may change while someone is reading kana.
    var stage: RideStage = RideRoute.home
    /// Draw one static frame regardless of Reduce Motion. The results screens use this:
    /// `landmarkPhase` alone only freezes the landmark — clouds and lane dashes are
    /// wall-clock-driven and would keep streaming behind a screen that is meant to be
    /// a stopped moment. (v1.12 §D2, Codex review.)
    var still = false

    private var palette: RidePalette { stage.palette }
    private var road: Color { palette.road.color }
    private var roadFar: Color { palette.roadFar.color }
    private var lane: Color { palette.lane.color }
    private var silhouette: Color { palette.silhouette.color }

    var body: some View {
        Group {
            if still || reduceMotion || Screenshotter.isCapturing {
                // Reduce Motion: the scene is decorative, so it simply stops. Nothing about
                // the ride is communicated by the drift — progress lives in the landmark and
                // the HUD — so a still frame loses the user nothing.
                //
                // Capture: a frozen phase is what makes a headless render reproducible. The
                // same render run twice used to differ.
                Canvas { ctx, size in draw(ctx, size, Self.stillPhase) }
            } else {
                // 30fps, not display-link rate. This is a full-canvas repaint — sky, sun,
                // glow, 3 clouds, 3 hills, a landmark, road, 8 lane dashes and 16 posts —
                // and it ran at up to 120Hz for the entire length of every ride. Drifting
                // clouds and streaming dashes read identically at 30, on a device that is
                // otherwise idle waiting for keystrokes.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { ctx, size in
                        draw(ctx, size, timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .ignoresSafeArea()
        // The whole scene is decoration; the HUD and the word card carry the real
        // information. Hide it so VoiceOver users don't sweep through a Canvas.
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: TimeInterval) {
        let w = size.width, h = size.height
        let cx = w / 2
        let horizon = h * 0.46

        // Sky
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(
                    Gradient(colors: [palette.skyTop.color, palette.skyMid.color,
                                      palette.skyLow.color]),
                    startPoint: CGPoint(x: cx, y: 0), endPoint: CGPoint(x: cx, y: horizon)))

        // Sun + glow
        let sunC = CGPoint(x: cx + w * 0.22, y: horizon - h * 0.10)
        ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - w * 0.22, y: sunC.y - w * 0.22, width: w * 0.44, height: w * 0.44)),
                 with: .radialGradient(Gradient(colors: [palette.sun.color.opacity(palette.sunGlow), .clear]),
                                       center: sunC, startRadius: 0, endRadius: w * 0.22))
        let sunR = w * 0.05
        ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - sunR, y: sunC.y - sunR, width: sunR * 2, height: sunR * 2)),
                 with: .color(palette.sun.color))

        // Clouds
        for c in cloudSpecs {
            let drift = (t * c.speed).truncatingRemainder(dividingBy: 1)
            drawCloud(ctx, at: CGPoint(x: (1 - drift) * (w + 240) - 120, y: horizon * c.y),
                      scale: c.scale * w, alpha: palette.cloudAlpha)
        }

        // Distant hills
        for hill in [(0.12, 0.10), (0.78, 0.12), (0.45, 0.08)] {
            let hw = w * 0.5
            ctx.fill(Path(ellipseIn: CGRect(x: w * hill.0 - hw / 2, y: horizon - h * hill.1, width: hw, height: h * hill.1 * 2)),
                     with: .color(palette.landFar.color.opacity(0.85)))
        }

        // Approaching landmark
        // The KIND of landmark now belongs to the stretch of road you are on, so it is
        // stable for the whole run; landmarkPhase still governs how near it has come.
        let idx = stage.landmark
        let frac = max(0, landmarkPhase) - max(0, landmarkPhase).rounded(.down)
        // Size is capped against WIDTH as well as the horizon. Scaling by `horizon` alone
        // (a fraction of HEIGHT) made the landmark tower over the word card on a tall,
        // narrow phone — verified in the iPhone simulator, where Tokyo Tower's spire ran
        // straight through the kanji. The wide Mac layout is unaffected: there `horizon` is
        // already the smaller of the two.
        let lmH = min(horizon, w * 0.34) * (0.34 + 0.42 * frac)   // far → near
        drawLandmark(ctx, kind: idx, cx: cx - w * 0.16, horizon: horizon, height: lmH)

        // Horizon haze
        ctx.fill(Path(CGRect(x: 0, y: horizon - h * 0.05, width: w, height: h * 0.1)),
                 with: .linearGradient(Gradient(colors: [.clear, Color(red: 1, green: 0.75, blue: 0.6).opacity(0.35), .clear]),
                                       startPoint: CGPoint(x: cx, y: horizon - h * 0.05), endPoint: CGPoint(x: cx, y: horizon + h * 0.05)))

        // Land
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(Gradient(colors: [palette.landFar.color, palette.land.color]),
                                       startPoint: CGPoint(x: cx, y: horizon), endPoint: CGPoint(x: cx, y: h)))

        // Road
        let bottomHalf = w * 0.46, topHalf = w * 0.012
        var roadPath = Path()
        roadPath.move(to: CGPoint(x: cx - topHalf, y: horizon))
        roadPath.addLine(to: CGPoint(x: cx + topHalf, y: horizon))
        roadPath.addLine(to: CGPoint(x: cx + bottomHalf, y: h))
        roadPath.addLine(to: CGPoint(x: cx - bottomHalf, y: h))
        roadPath.closeSubpath()
        ctx.fill(roadPath, with: .linearGradient(Gradient(colors: [roadFar, road]),
                                                 startPoint: CGPoint(x: cx, y: horizon), endPoint: CGPoint(x: cx, y: h)))
        for side in [-1.0, 1.0] {
            var edge = Path()
            edge.move(to: CGPoint(x: cx + side * topHalf, y: horizon))
            edge.addLine(to: CGPoint(x: cx + side * bottomHalf, y: h))
            ctx.stroke(edge, with: .color(.white.opacity(0.35)), lineWidth: 3)
        }

        // Lane dashes + roadside posts
        let phase = (t * (0.30 + speed * 0.30)).truncatingRemainder(dividingBy: 1)
        for i in 0 ..< 8 {
            let u = (Double(i) / 8 + phase).truncatingRemainder(dividingBy: 1)
            let near = u * u, far = min(1, u * u + 0.07)
            let y0 = horizon + (h - horizon) * near, y1 = horizon + (h - horizon) * far
            let half0 = (topHalf + (bottomHalf - topHalf) * near) * 0.085
            let half1 = (topHalf + (bottomHalf - topHalf) * far) * 0.085
            var dash = Path()
            dash.move(to: CGPoint(x: cx - half0, y: y0)); dash.addLine(to: CGPoint(x: cx + half0, y: y0))
            dash.addLine(to: CGPoint(x: cx + half1, y: y1)); dash.addLine(to: CGPoint(x: cx - half1, y: y1)); dash.closeSubpath()
            ctx.fill(dash, with: .color(lane.opacity(0.45 + 0.55 * near)))
        }
        for side in [-1.0, 1.0] {
            for i in 0 ..< 8 {
                let u = (Double(i) / 8 + phase + 0.04).truncatingRemainder(dividingBy: 1)
                let near = u * u
                let y = horizon + (h - horizon) * near
                let x = cx + side * (topHalf + (bottomHalf - topHalf) * near + (10 + 70 * near))
                ctx.fill(Path(CGRect(x: x - (1.5 + 8 * near) / 2, y: y - (6 + 52 * near), width: 1.5 + 8 * near, height: 6 + 52 * near)),
                         with: .color(Color(red: 0.14, green: 0.20, blue: 0.28).opacity(0.4 + 0.6 * near)))
            }
        }
    }

    // MARK: Landmarks (silhouettes)

    /// A landmark's characteristic hue, carried into the stage's own light.
    ///
    /// The torii and the tower used to be hardcoded daylight vermilion and orange, so they
    /// ignored the palette entirely — a torii at midnight over Kyoto was still painted for
    /// noon, and on the ride screen that saturated shape read as noise behind the word card.
    /// (Fuji and the castle were always palette-driven; these two were the ones that got
    /// missed.) Blending toward `silhouette` keeps them recognisable while putting them in
    /// the same light as everything else on the horizon.
    private func landmarkTint(_ characteristic: RGB) -> Color {
        palette.silhouette.lerp(to: characteristic, 0.45).color
    }

    private func drawLandmark(_ ctx: GraphicsContext, kind: Int, cx: CGFloat, horizon: CGFloat, height h: CGFloat) {
        let base = horizon
        switch kind {
        case 1:   // ⛩ torii
            let bw = h * 0.95, postW = h * 0.11, postX = bw * 0.32
            let vermilion = landmarkTint(RGB(0.80, 0.22, 0.18))
            for s in [-1.0, 1.0] {
                ctx.fill(Path(CGRect(x: cx + s * postX - postW / 2, y: base - h, width: postW, height: h)), with: .color(vermilion))
            }
            ctx.fill(Path(CGRect(x: cx - bw / 2, y: base - h, width: bw, height: h * 0.13)), with: .color(vermilion))            // kasagi
            ctx.fill(Path(CGRect(x: cx - bw * 0.42, y: base - h + h * 0.28, width: bw * 0.84, height: h * 0.09)), with: .color(vermilion)) // nuki
        case 2:   // 城 castle keep (stacked tiers)
            let levels = 3
            for k in 0 ..< levels {
                let frac = CGFloat(k) / CGFloat(levels)
                let nextFrac = CGFloat(k + 1) / CGFloat(levels)
                let yBot = base - h * frac, yTop = base - h * nextFrac
                let wBot = h * 0.8 * (1 - 0.24 * CGFloat(k)), wTop = h * 0.8 * (1 - 0.24 * CGFloat(k + 1))
                var tier = Path()
                tier.move(to: CGPoint(x: cx - wBot / 2, y: yBot)); tier.addLine(to: CGPoint(x: cx - wTop / 2, y: yTop))
                tier.addLine(to: CGPoint(x: cx + wTop / 2, y: yTop)); tier.addLine(to: CGPoint(x: cx + wBot / 2, y: yBot)); tier.closeSubpath()
                ctx.fill(tier, with: .color(silhouette))
                // eave (overhanging roof line)
                ctx.fill(Path(CGRect(x: cx - wTop * 0.62, y: yTop - h * 0.02, width: wTop * 1.24, height: h * 0.035)),
                         with: .color(Color(red: 0.16, green: 0.18, blue: 0.34)))
            }
        case 3:   // 塔 tower (Tokyo-Tower-ish)
            let orange = landmarkTint(RGB(0.90, 0.36, 0.20))
            var tri = Path()
            tri.move(to: CGPoint(x: cx - h * 0.26, y: base)); tri.addLine(to: CGPoint(x: cx, y: base - h))
            tri.addLine(to: CGPoint(x: cx + h * 0.26, y: base)); tri.closeSubpath()
            ctx.fill(tri, with: .color(orange))
            for level in [0.35, 0.62] {                                  // crossbars
                let y = base - h * level, half = h * 0.26 * (1 - level)
                ctx.fill(Path(CGRect(x: cx - half, y: y, width: half * 2, height: h * 0.02)), with: .color(orange))
            }
            ctx.fill(Path(CGRect(x: cx - h * 0.012, y: base - h - h * 0.12, width: h * 0.024, height: h * 0.12)), with: .color(orange)) // mast
        default:  // 富士山 Fuji
            let bw = h * 1.15
            var fuji = Path()
            fuji.move(to: CGPoint(x: cx - bw / 2, y: base)); fuji.addLine(to: CGPoint(x: cx, y: base - h))
            fuji.addLine(to: CGPoint(x: cx + bw / 2, y: base)); fuji.closeSubpath()
            ctx.fill(fuji, with: .color(silhouette))
            let capH = h * 0.26, capHalf = bw * 0.5 * (capH / h)
            var cap = Path()
            cap.move(to: CGPoint(x: cx - capHalf, y: base - h + capH)); cap.addLine(to: CGPoint(x: cx, y: base - h))
            cap.addLine(to: CGPoint(x: cx + capHalf, y: base - h + capH)); cap.closeSubpath()
            ctx.fill(cap, with: .color(.white.opacity(0.92)))
        }
    }

    private struct CloudSpec { let y: Double; let scale: Double; let speed: Double }
    private let cloudSpecs = [CloudSpec(y: 0.35, scale: 0.16, speed: 0.012),
                              CloudSpec(y: 0.55, scale: 0.11, speed: 0.018),
                              CloudSpec(y: 0.30, scale: 0.13, speed: 0.009)]

    private func drawCloud(_ ctx: GraphicsContext, at p: CGPoint, scale s: CGFloat, alpha: Double) {
        let color = GraphicsContext.Shading.color(.white.opacity(alpha))
        for (dx, dy, r) in [(-0.5, 0.1, 0.45), (0.0, -0.1, 0.6), (0.5, 0.1, 0.45), (0.15, 0.15, 0.4)] {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x + dx * s - r * s / 2, y: p.y + dy * s - r * s / 2, width: r * s, height: r * s * 0.7)), with: color)
        }
    }
}

extension RGB {
    /// SceneryKit stores plain components so palettes can be tested; this is the one place
    /// they become something SwiftUI can draw.
    var color: Color { Color(red: r, green: g, blue: b) }
}
