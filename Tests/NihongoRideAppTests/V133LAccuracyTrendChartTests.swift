import Testing
import SwiftUI
import Foundation
@testable import NihongoRideApp

/// The Stats "Accuracy trend" chart after ONE ride (v1.33 §B L, simulator pass #21).
///
/// A line and an area through a single point draw nothing, so a learner's first ride — the moment
/// the card first appears — showed an empty plot beside its percentage labels. The fix adds a
/// `PointMark` when there is exactly one value. This renders `AccuracyTrendChart` itself with
/// `ImageRenderer` and counts pixels in `Theme.accent`, the colour every mark on this chart uses.
///
/// Headless rendering is fine for THIS question: it is about whether a mark is drawn at all, which
/// does not depend on Dynamic Type — the one thing `ImageRenderer` cannot see (`ScaledFont.swift`).
///
/// **Calibrated both ways before it is believed**, because this repo has a history of instruments
/// that reported "nothing found" because they were broken: an empty chart must count ZERO accent
/// pixels (so axis labels and the background are not mistaken for a mark), and a two-ride chart,
/// whose line always drew, must count some (so the counter can see a mark when one is there).
/// Measured 2026-09-17: one ride 148 accent pixels, two rides 2060, empty 0. Mutation the same day:
/// changing the `PointMark`'s condition so it never draws turned `oneRideIsDrawn` red with 0 pixels
/// — the blank plot the simulator pass saw, reproduced headless — while both controls stayed green.
@Suite("V133L: a one-ride accuracy trend draws a point")
@MainActor
struct V133LAccuracyTrendChartTests {

    /// Pixels close to `Theme.accent` (0.98, 0.45, 0.45) after compositing the chart over black.
    static func accentPixels(_ series: [(Int, Double)]) throws -> Int {
        let renderer = ImageRenderer(content:
            AccuracyTrendChart(series: series, zh: false)
                .frame(width: 320, height: 130)
        )
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "ImageRenderer produced no image")
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn, "could not create a bitmap context — the count below is measuring nothing")
        var count = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
            if r > 200, g > 70, g < 170, b > 70, b < 170, abs(g - b) < 30 { count += 1 }
        }
        return count
    }

    @Test("one ride draws a visible mark")
    func oneRideIsDrawn() throws {
        let pixels = try Self.accentPixels([(0, 0.8)])
        #expect(pixels > 20, "a one-ride accuracy trend drew \(pixels) accent pixels — an empty chart")
    }

    @Test("control: an empty chart counts no accent pixels (labels are not marks)")
    func emptyChartCountsNothing() throws {
        #expect(try Self.accentPixels([]) == 0)
    }

    @Test("control: a two-ride chart, whose line always drew, is counted")
    func twoRidesAreCounted() throws {
        #expect(try Self.accentPixels([(0, 0.6), (1, 0.9)]) > 20)
    }
}
