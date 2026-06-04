import SwiftUI

/// A first-person "riding" scene rendered entirely in code — like the screen of
/// a gym exercise bike. A red road with gold lane dashes streams toward the
/// viewer (faster with `speed`), over teal land, a dawn sky, a sun and Mt. Fuji.
/// Palette matches the app icon. (Art can later be swapped for real sprites.)
struct RideBackgroundView: View {
    /// Relative pedalling speed; ~1 idle, higher with combo. Drives dash scroll.
    var speed: Double = 1

    // Icon-matched palette
    private let road = Color(red: 0.85, green: 0.22, blue: 0.22)
    private let lane = Color(red: 0.98, green: 0.80, blue: 0.35)
    private let landTop = Color(red: 0.16, green: 0.55, blue: 0.52)
    private let landBottom = Color(red: 0.09, green: 0.34, blue: 0.37)

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
        let horizon = h * 0.42

        // Sky: deep indigo → dawn coral toward the horizon.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.27),
                                      Color(red: 0.97, green: 0.58, blue: 0.46)]),
                    startPoint: CGPoint(x: cx, y: 0), endPoint: CGPoint(x: cx, y: horizon)))

        // Sun, low and right.
        let sunR = w * 0.055
        ctx.fill(Path(ellipseIn: CGRect(x: cx + w * 0.20 - sunR, y: horizon - sunR * 1.6,
                                        width: sunR * 2, height: sunR * 2)),
                 with: .color(Color(red: 0.99, green: 0.84, blue: 0.5)))

        // Mt. Fuji on the horizon, left of center, with a snow cap.
        let fx = cx - w * 0.17, fw = w * 0.36, fh = horizon * 0.6
        var fuji = Path()
        fuji.move(to: CGPoint(x: fx - fw / 2, y: horizon))
        fuji.addLine(to: CGPoint(x: fx, y: horizon - fh))
        fuji.addLine(to: CGPoint(x: fx + fw / 2, y: horizon))
        fuji.closeSubpath()
        ctx.fill(fuji, with: .color(Color(red: 0.28, green: 0.32, blue: 0.55).opacity(0.9)))
        let capH = fh * 0.28, capHalf = fw * 0.5 * (capH / fh)
        var cap = Path()
        cap.move(to: CGPoint(x: fx - capHalf, y: horizon - fh + capH))
        cap.addLine(to: CGPoint(x: fx, y: horizon - fh))
        cap.addLine(to: CGPoint(x: fx + capHalf, y: horizon - fh + capH))
        cap.closeSubpath()
        ctx.fill(cap, with: .color(.white.opacity(0.92)))

        // Land below the horizon.
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(Gradient(colors: [landTop, landBottom]),
                                       startPoint: CGPoint(x: cx, y: horizon),
                                       endPoint: CGPoint(x: cx, y: h)))

        // Road: a perspective trapezoid from the vanishing point to the bottom.
        let bottomHalf = w * 0.46, topHalf = w * 0.012
        var roadPath = Path()
        roadPath.move(to: CGPoint(x: cx - topHalf, y: horizon))
        roadPath.addLine(to: CGPoint(x: cx + topHalf, y: horizon))
        roadPath.addLine(to: CGPoint(x: cx + bottomHalf, y: h))
        roadPath.addLine(to: CGPoint(x: cx - bottomHalf, y: h))
        roadPath.closeSubpath()
        ctx.fill(roadPath, with: .color(road))

        // Gold lane dashes scrolling toward the viewer (perspective + growth).
        let phase = (t * (0.30 + speed * 0.28)).truncatingRemainder(dividingBy: 1)
        let count = 8
        for i in 0 ..< count {
            let u = (Double(i) / Double(count) + phase).truncatingRemainder(dividingBy: 1)
            let near = u * u                       // ease: things rush in near the bottom
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
            ctx.fill(dash, with: .color(lane.opacity(0.35 + 0.65 * near)))
        }

        // Roadside posts streaming past on both edges (extra motion cue).
        for side in [-1.0, 1.0] {
            for i in 0 ..< count {
                let u = (Double(i) / Double(count) + phase).truncatingRemainder(dividingBy: 1)
                let near = u * u
                let y = horizon + (h - horizon) * near
                let edgeHalf = topHalf + (bottomHalf - topHalf) * near
                let x = cx + side * (edgeHalf + (8 + 60 * near))
                let postH = 6 + 46 * near
                let postW = 1.5 + 7 * near
                ctx.fill(Path(CGRect(x: x - postW / 2, y: y - postH, width: postW, height: postH)),
                         with: .color(Color(red: 0.16, green: 0.22, blue: 0.30).opacity(0.5 + 0.5 * near)))
            }
        }
    }
}
