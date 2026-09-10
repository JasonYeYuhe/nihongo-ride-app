import SwiftUI

/// A screen's title, its one-line subtitle, and the Back button — in the one arrangement that
/// survives the accessibility text sizes.
///
/// # Why this exists
///
/// `JournalView` and `StatsView` carried byte-identical copies of this header: an
/// `HStack(alignment: .firstTextBaseline)` holding a title stack, a `Spacer`, and a Back capsule.
/// Neither the title nor the button had a `lineLimit` or a shrink allowance, so at AX5 on a phone
/// the two together are wider than the screen — and the enclosing `.frame(maxWidth: .infinity)`
/// then CENTRES the oversized row, which clips it on BOTH edges.
///
/// Measured on an iPhone 17 Pro at AX5, 2026-09-10: "Ride Log" rendered with its R off the left
/// edge, "Every ride, remembered" with its E off, and "Back" as "Bac". A screen whose title you
/// cannot read and whose only way out is half off the screen.
///
/// # Why it is one file
///
/// Because it was two, and this project's own rule is that *one rule written twice will drift* —
/// recorded three times, each an instance where a Swift test and a Python gate, or two call sites,
/// disagreed and the copy was the stale one. Fixing the header in `JournalView` and leaving
/// `StatsView` on the old shape would have been *a fix applied to one call site*, which is the
/// rule directly above it in the same list.
///
/// # The arrangement
///
/// At the accessibility sizes the row becomes a column: Back first, then the title. Back FIRST
/// because at those sizes the title alone can fill the viewport, and a way out that has scrolled
/// off the top of a screen is not a way out. Below those sizes the layout is exactly what it was,
/// so nothing changes for the sizes this app has actually shipped screenshots of.
///
/// `MenuView:128` uses the same switch for the route strip and gives the same argument: a
/// horizontal arrangement that cannot fit stops being a horizontal arrangement.
struct ScreenHeader: View {
    let title: String
    let subtitle: String
    let backLabel: String
    let backIdentifier: String
    let isPhoneIdiom: Bool
    let onBack: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                backButton
                titleStack
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline) {
                titleStack
                Spacer()
                backButton
            }
        }
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .scaledSystemFont(isPhoneIdiom ? 28 : 32, weight: .heavy,
                                  design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white)
                // A floor as well as the layout switch. The switch handles AX3–AX5; the sizes
                // just below it squeeze the same way, only less, and a title is the one string on
                // a screen that must never be ambiguous.
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .scaledSystemFont(13)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label(backLabel, systemImage: "chevron.left")
                .scaledSystemFont(14, weight: .semibold)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardStroke))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(backIdentifier)
    }
}
