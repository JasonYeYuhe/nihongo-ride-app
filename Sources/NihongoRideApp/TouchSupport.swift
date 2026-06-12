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
