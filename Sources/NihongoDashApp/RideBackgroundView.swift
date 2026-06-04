import SwiftUI

/// A first-person "riding" scene rendered entirely in code — like the screen of
/// a gym exercise bike. A red road with gold lane dashes streams toward the
/// viewer (faster with `speed`), over teal land, a dawn sky, sun, drifting
/// clouds, distant hills and Mt. Fuji. Palette matches the app icon.
/// (Art can later be swapped for real sprites/layers.)
struct RideBackgroundView: View {
    /// Relative pedalling speed; ~1 idle, higher with combo. Drives the scroll.
    var speed: Double = 1

    // Icon-matched palette
    private let road = Color(red: 0.82, green: 0.21, blue: 0.21)
    private let roadFar = Color(red: 0.45, green: 0.14, blue: 0.18)
    private let lane = Color(red: 0.98, green: 0.80, blue: 0.35)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(ctx, size, t) }
        }
        .ignoresSafeArea()
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: TimeInterval) {
        let w = size.width, h = size.height
        let cx = w / 2
        let horizon = h * 0.46

        // Sky: deep indigo → dawn coral toward the horizon.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.08, green: 0.11, blue: 0.26),
                                      Color(red: 0.36, green: 0.30, blue: 0.50),
                                      Color(red: 0.98, green: 0.62, blue: 0.46)]),
                    startPoint: CGPoint(x: cx, y: 0), endPoint: CGPoint(x: cx, y: horizon)))

        // Sun with a soft glow, low and right.
        let sunC = CGPoint(x: cx + w * 0.22, y: horizon - h * 0.10)
        ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - w * 0.22, y: sunC.y - w * 0.22, width: w * 0.44, height: w * 0.44)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.5).opacity(0.55), .clear]),
                                       center: sunC, startRadius: 0, endRadius: w * 0.22))
        let sunR = w * 0.05
        ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - sunR, y: sunC.y - sunR, width: sunR * 2, height: sunR * 2)),
                 with: .color(Color(red: 0.99, green: 0.86, blue: 0.55)))

        // Drifting clouds (slow parallax).
        for c in cloudSpecs {
            let drift = (t * c.speed).truncatingRemainder(dividingBy: 1)
            let x = (1 - drift) * (w + 240) - 120
            drawCloud(ctx, at: CGPoint(x: x, y: horizon * c.y), scale: c.scale * w)
        }

        // Distant hills straddling the horizon (behind Fuji).
        for hill in [(0.12, 0.10), (0.78, 0.12), (0.45, 0.08)] {
            let hw = w * 0.5
            ctx.fill(Path(ellipseIn: CGRect(x: w * hill.0 - hw / 2, y: horizon - h * hill.1,
                                            width: hw, height: h * hill.1 * 2)),
                     with: .color(Color(red: 0.13, green: 0.40, blue: 0.42).opacity(0.85)))
        }

        // Mt. Fuji on the horizon, left of center, with a snow cap.
        let fx = cx - w * 0.18, fw = w * 0.38, fh = horizon * 0.62
        var fuji = Path()
        fuji.move(to: CGPoint(x: fx - fw / 2, y: horizon))
        fuji.addLine(to: CGPoint(x: fx, y: horizon - fh))
        fuji.addLine(to: CGPoint(x: fx + fw / 2, y: horizon))
        fuji.closeSubpath()
        ctx.fill(fuji, with: .color(Color(red: 0.26, green: 0.30, blue: 0.52).opacity(0.92)))
        let capH = fh * 0.26, capHalf = fw * 0.5 * (capH / fh)
        var cap = Path()
        cap.move(to: CGPoint(x: fx - capHalf, y: horizon - fh + capH))
        cap.addLine(to: CGPoint(x: fx, y: horizon - fh))
        cap.addLine(to: CGPoint(x: fx + capHalf, y: horizon - fh + capH))
        cap.closeSubpath()
        ctx.fill(cap, with: .color(.white.opacity(0.92)))

        // Horizon haze for depth.
        ctx.fill(Path(CGRect(x: 0, y: horizon - h * 0.05, width: w, height: h * 0.1)),
                 with: .linearGradient(Gradient(colors: [.clear, Color(red: 1, green: 0.75, blue: 0.6).opacity(0.35), .clear]),
                                       startPoint: CGPoint(x: cx, y: horizon - h * 0.05),
                                       endPoint: CGPoint(x: cx, y: horizon + h * 0.05)))

        // Land below the horizon.
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.55, blue: 0.52),
                                                         Color(red: 0.08, green: 0.32, blue: 0.35)]),
                                       startPoint: CGPoint(x: cx, y: horizon), endPoint: CGPoint(x: cx, y: h)))

        // Road: a perspective trapezoid, dark at the horizon → vivid near you.
        let bottomHalf = w * 0.46, topHalf = w * 0.012
        var roadPath = Path()
        roadPath.move(to: CGPoint(x: cx - topHalf, y: horizon))
        roadPath.addLine(to: CGPoint(x: cx + topHalf, y: horizon))
        roadPath.addLine(to: CGPoint(x: cx + bottomHalf, y: h))
        roadPath.addLine(to: CGPoint(x: cx - bottomHalf, y: h))
        roadPath.closeSubpath()
        ctx.fill(roadPath, with: .linearGradient(Gradient(colors: [roadFar, road]),
                                                 startPoint: CGPoint(x: cx, y: horizon),
                                                 endPoint: CGPoint(x: cx, y: h)))

        // Soft road edges.
        for side in [-1.0, 1.0] {
            var edge = Path()
            edge.move(to: CGPoint(x: cx + side * topHalf, y: horizon))
            edge.addLine(to: CGPoint(x: cx + side * bottomHalf, y: h))
            ctx.stroke(edge, with: .color(.white.opacity(0.35)), lineWidth: 3)
        }

        // Gold lane dashes scrolling toward the viewer (perspective + growth).
        let phase = (t * (0.30 + speed * 0.30)).truncatingRemainder(dividingBy: 1)
        let count = 8
        for i in 0 ..< count {
            let u = (Double(i) / Double(count) + phase).truncatingRemainder(dividingBy: 1)
            let near = u * u
            let far = min(1, near + 0.07)
            let y0 = horizon + (h - horizon) * near
            let y1 = horizon + (h - horizon) * far
            let half0 = (topHalf + (bottomHalf - topHalf) * near) * 0.085
            let half1 = (topHalf + (bottomHalf - topHalf) * far) * 0.085
            var dash = Path()
            dash.move(to: CGPoint(x: cx - half0, y: y0))
            dash.addLine(to: CGPoint(x: cx + half0, y: y0))
            dash.addLine(to: CGPoint(x: cx + half1, y: y1))
            dash.addLine(to: CGPoint(x: cx - half1, y: y1))
            dash.closeSubpath()
            ctx.fill(dash, with: .color(lane.opacity(0.45 + 0.55 * near)))
        }

        // Roadside posts streaming past on both edges.
        for side in [-1.0, 1.0] {
            for i in 0 ..< count {
                let u = (Double(i) / Double(count) + phase + 0.04).truncatingRemainder(dividingBy: 1)
                let near = u * u
                let y = horizon + (h - horizon) * near
                let edgeHalf = topHalf + (bottomHalf - topHalf) * near
                let x = cx + side * (edgeHalf + (10 + 70 * near))
                let postH = 6 + 52 * near, postW = 1.5 + 8 * near
                ctx.fill(Path(CGRect(x: x - postW / 2, y: y - postH, width: postW, height: postH)),
                         with: .color(Color(red: 0.14, green: 0.20, blue: 0.28).opacity(0.4 + 0.6 * near)))
            }
        }
    }

    private struct CloudSpec { let y: Double; let scale: Double; let speed: Double }
    private let cloudSpecs = [CloudSpec(y: 0.35, scale: 0.16, speed: 0.012),
                              CloudSpec(y: 0.55, scale: 0.11, speed: 0.018),
                              CloudSpec(y: 0.30, scale: 0.13, speed: 0.009)]

    private func drawCloud(_ ctx: GraphicsContext, at p: CGPoint, scale s: CGFloat) {
        let color = GraphicsContext.Shading.color(.white.opacity(0.5))
        for (dx, dy, r) in [(-0.5, 0.1, 0.45), (0.0, -0.1, 0.6), (0.5, 0.1, 0.45), (0.15, 0.15, 0.4)] {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x + dx * s - r * s / 2, y: p.y + dy * s - r * s / 2,
                                            width: r * s, height: r * s * 0.7)), with: color)
        }
    }
}
