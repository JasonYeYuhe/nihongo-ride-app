import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Cross-platform helpers for touch-only devices (iPad). On macOS every helper
/// compiles to a no-op so the desktop app is unchanged.
extension View {
    /// Mirrors software-keyboard visibility into `isUp` (iOS). Layouts use it
    /// to compact themselves while the keyboard occupies the lower screen.
    @ViewBuilder
    func observingKeyboard(_ isUp: Binding<Bool>) -> some View {
        #if os(iOS)
        self
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { isUp.wrappedValue = true }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { isUp.wrappedValue = false }
            }
        #else
        self
        #endif
    }

    /// Tap anywhere on the screen to bring the on-screen keyboard back if the
    /// user dismissed it. Implemented as a *simultaneous* gesture so it never
    /// consumes a tap: buttons receive their taps normally, and a screen that
    /// is mid-transition (the outgoing view briefly overlaps the incoming one)
    /// can't swallow touches meant for the new screen.
    @ViewBuilder
    func summonKeyboardOnTap() -> some View {
        #if os(iOS)
        self
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { KeyboardSummon.summon() })
        #else
        self
        #endif
    }
}

/// True on touch-first devices — used to swap keyboard-shortcut hints for
/// tappable buttons.
var isTouchDevice: Bool {
    #if os(iOS)
    true
    #else
    false
    #endif
}

/// True on iPhone (portrait-only, ~390pt wide) — views swap in narrow layout
/// variants: tighter padding, scaled-down type, stacked instead of side-by-side.
/// A static device check (not a size class) because the iPhone app is locked to
/// portrait, so the narrow layout is a property of the device, not the window.
@MainActor
var isPhoneIdiom: Bool {
    #if os(iOS)
    UIDevice.current.userInterfaceIdiom == .phone
    #else
    false
    #endif
}

/// Lays children out in an HStack on roomy screens, a VStack on narrow ones.
@MainActor
@ViewBuilder
func adaptiveStack(horizontal: Bool, spacing: CGFloat,
                   @ViewBuilder content: () -> some View) -> some View {
    if horizontal {
        HStack(spacing: spacing) { content() }
    } else {
        VStack(spacing: spacing) { content() }
    }
}

extension View {
    /// Sizes a pill button's LABEL. Replaces the fixed `.frame(width:height:)` these
    /// buttons used to carry.
    ///
    /// v1.14 §C: the label text scales with Dynamic Type (`scaledSystemFont`) but the pill
    /// around it did not, so at the larger accessibility sizes the app's primary calls to
    /// action — 出発 / Ride again / Menu / Get started — were the first things to become
    /// unreadable. A fixed frame proposes exactly WxH to the text, and text that needs more
    /// height than that gets truncated; nothing about the button hinted it was clipped.
    ///
    /// `minWidth`/`minHeight` keep the original dimensions as a FLOOR, so at the default text
    /// size the pill keeps its exact geometry. Its LABEL can land up to half a pixel
    /// differently — one more layout layer, one more rounding — which the headless renders
    /// show as a faint antialiasing change on onboarding.png and conjugation-results.png and
    /// which is invisible side by side. (I first claimed "pixel-identical" here on the
    /// strength of a check that could not have detected otherwise: `getbbox()` on an RGBA
    /// difference image reads the ALPHA channel only. Use `scripts/compare_renders.py`.)
    /// Above the default the
    /// pill grows with its text, and the padding keeps the glyphs off the capsule edge. If the
    /// screen is too narrow to grow into, the text now wraps and the pill gets taller instead
    /// of losing characters.
    func ctaLabel(minWidth: CGFloat, minHeight: CGFloat,
                  hPadding: CGFloat = 14, vPadding: CGFloat = 8) -> some View {
        self.multilineTextAlignment(.center)
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
    }
}

/// Wraps a screen so it scrolls only when it has to, without moving it when it doesn't.
///
/// A bare `ScrollView` is not a no-op for these layouts: the results screens center
/// themselves with `Spacer()`s, and a scroll view proposes unbounded height, so the spacers
/// collapse and the content jumps to the top. Giving the content a `minHeight` of the
/// viewport restores the spacers' room — identical rendering while it fits, scrolling once
/// it doesn't.
///
/// It has to fit on every device, not just iPhone: the results screen's height depends on how
/// long the run's review list is, and the accessibility text sizes multiply it, so an iPad
/// mini in portrait or a small macOS window could push the primary button off the bottom with
/// no way to reach it. (v1.15 §A.)
/// 🔴 Skipped while capturing. `ImageRenderer` draws a `ScrollView`'s content as NOTHING —
/// wrapping these screens rendered them as bare scenery, which would silently have emptied
/// the macOS App Store screenshots, since those come out of the same headless pipeline.
/// Verified on an iPad simulator that the wrapped screen is correct at runtime; the empty
/// output was the renderer, not the layout.
@MainActor
@ViewBuilder
func scrollsWhenTall(@ViewBuilder content: @escaping () -> some View) -> some View {
    if Screenshotter.isCapturing {
        content()
    } else {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                content().frame(minHeight: geo.size.height)
            }
        }
    }
}

extension DynamicTypeSize {
    /// Roomy side-by-side button rows have to stack once the text is accessibility-sized:
    /// three grown pills across a phone don't fit, and SwiftUI's compromise there is to
    /// squeeze each one until its label truncates — the exact failure `ctaLabel` fixes.
    var wantsStackedButtons: Bool { isAccessibilitySize }
}
