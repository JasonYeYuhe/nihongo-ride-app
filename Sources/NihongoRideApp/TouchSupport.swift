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
    /// size the rendered pill is identical to before — verified as PIXELS across all 21
    /// headless renders, not as file bytes: PNG encoding is not byte-stable here, and a naive
    /// `cmp` reports differences on screens the change cannot reach. Above the default the
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

extension DynamicTypeSize {
    /// Roomy side-by-side button rows have to stack once the text is accessibility-sized:
    /// three grown pills across a phone don't fit, and SwiftUI's compromise there is to
    /// squeeze each one until its label truncates — the exact failure `ctaLabel` fixes.
    var wantsStackedButtons: Bool { isAccessibilitySize }
}
