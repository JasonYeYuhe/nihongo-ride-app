import SwiftUI

/// Dynamic-Type-aware replacement for `.font(.system(size:weight:design:))`.
///
/// v1.7 Phase A: the app shipped ~132 fixed `.system(size:)` sites that ignored the
/// system "Larger Text" accessibility setting. This wraps the EXACT existing size in
/// a `@ScaledMetric`, so at the default text size the rendered size is byte-identical
/// to before — the headless render gate relies on that (ImageRenderer ignores
/// `dynamicTypeSize`, so only the default size is render-verifiable; large-type
/// layout is device-verified, Gate E). Above the default size it now scales.
///
/// - `relativeTo` picks the text style the size scales against (a title scales at a
///   different rate than body), preserving visual hierarchy.
/// - `maxScaled` caps the scaled size for tight game-screen elements (the big kana /
///   HUD pills) so a huge accessibility size can't blow out the fixed game layout.
struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    @Environment(\.emulatedTextScale) private var emulatedTextScale
    private let weight: Font.Weight
    private let design: Font.Design
    private let monospacedDigit: Bool
    private let maxScaled: CGFloat?

    init(size: CGFloat, weight: Font.Weight, design: Font.Design,
         relativeTo style: Font.TextStyle, monospacedDigit: Bool, maxScaled: CGFloat?) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.monospacedDigit = monospacedDigit
        self.maxScaled = maxScaled
    }

    func body(content: Content) -> some View {
        let scaled = size * emulatedTextScale
        let resolved = maxScaled.map { Swift.min(scaled, $0) } ?? scaled
        var font = Font.system(size: resolved, weight: weight, design: design)
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }
}

extension View {
    /// Dynamic-Type scaling wrapper for a fixed system-font size. At the default text
    /// size this is identical to `.font(.system(size:weight:design:))`; above it the
    /// size scales with the user's setting.
    ///
    /// - Parameters:
    ///   - size: the base (default-size) point size — unchanged from before.
    ///   - weight: font weight (default `.regular`).
    ///   - design: font design (default `.default`; the app often uses `.rounded`).
    ///   - relativeTo: the text style the size scales against (default `.body`).
    ///   - monospacedDigit: apply `.monospacedDigit()` to the font (tabular figures).
    ///   - maxScaled: optional upper bound on the scaled size (tight game layouts).
    func scaledSystemFont(_ size: CGFloat,
                          weight: Font.Weight = .regular,
                          design: Font.Design = .default,
                          relativeTo style: Font.TextStyle = .body,
                          monospacedDigit: Bool = false,
                          maxScaled: CGFloat? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design,
                                  relativeTo: style, monospacedDigit: monospacedDigit,
                                  maxScaled: maxScaled))
    }
}

extension EnvironmentValues {
    /// A factor on every `scaledSystemFont` size, applied where `@ScaledMetric` would scale it and
    /// before `maxScaled` caps it — **1 in the app, which never sets it**, so every size is what it
    /// was (a product by 1 is exact). It exists for hosted tests: macOS does not scale `@ScaledMetric`
    /// for any `dynamicTypeSize`, so a test that lays out an iOS screen at, say, AX1 on a Mac sets
    /// this to that size's body-point ratio (28/17) as well as the size itself.
    /// `V135HUDRowTests` pins that no shipped source sets it. (v1.35)
    @Entry var emulatedTextScale: CGFloat = 1
}
