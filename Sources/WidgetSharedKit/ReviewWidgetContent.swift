import SwiftUI

/// The resolved numbers a widget entry shows. A plain value (no WidgetKit), so the
/// view that renders it lives here in the shared module and can be rendered BOTH by
/// the widget extension and headlessly by the app's Screenshotter for a visual check
/// — the same de-risking that caught a layout bug in the v1.10 share card.
public struct ReviewWidgetData: Sendable, Equatable {
    public var hasData: Bool
    public var stale: Bool
    public var vocabDue: Int
    public var conjugationDue: Int
    public var streakDays: Int
    /// Follows the app's in-app language choice (carried by the snapshot), not the
    /// system locale.
    public var zh: Bool

    public init(hasData: Bool, stale: Bool, vocabDue: Int, conjugationDue: Int,
                streakDays: Int, zh: Bool = false) {
        self.hasData = hasData
        self.stale = stale
        self.vocabDue = vocabDue
        self.conjugationDue = conjugationDue
        self.streakDays = streakDays
        self.zh = zh
    }

    /// Everything the learner owes today, across BOTH SRS stores — the same number the app
    /// icon badge shows since v1.14 §B.
    public var totalDue: Int { vocabDue + conjugationDue }

    /// Whether the widget may say "all caught up".
    ///
    /// This is one property rather than a condition written per layout because the per-layout
    /// version got it wrong twice in a row: the small layout claimed it while conjugations
    /// were due (fixed in v1.13 §B) and then the medium layout claimed it while the column
    /// beside it displayed those conjugations (fixed in v1.14 §D). Five layouts sharing one
    /// definition cannot drift apart a third time.
    public var isAllCaughtUp: Bool { hasData && totalDue == 0 }

    public static let placeholder = ReviewWidgetData(
        hasData: true, stale: false, vocabDue: 12, conjugationDue: 3, streakDays: 5)
    public static let empty = ReviewWidgetData(
        hasData: false, stale: false, vocabDue: 0, conjugationDue: 0, streakDays: 0)
}

public enum ReviewWidgetSize: Sendable {
    case small, medium
    // Lock-screen accessories (v1.13 §C). These are rendered MONOCHROME by the system
    // (it applies its own tint), so their layouts use SF Symbols + text only and never
    // reference WidgetPalette colours — a colour there would just be flattened to the tint.
    case accessoryRectangular, accessoryInline, accessoryCircular
}

/// Widget colours, matched by eye to `Theme` in NihongoRideApp.swift. Public so the
/// widget extension and the headless preview both wrap the content in the same
/// background (the content itself carries none, so the widget can supply it via
/// `.containerBackground(for: .widget)` as iOS 17 requires).
public enum WidgetPalette {
    public static let bg = LinearGradient(
        colors: [Color(red: 0.06, green: 0.09, blue: 0.18),
                 Color(red: 0.10, green: 0.14, blue: 0.26)],
        startPoint: .top, endPoint: .bottom)
    public static let accent = Color(red: 0.98, green: 0.45, blue: 0.45)
    public static let accent2 = Color(red: 0.42, green: 0.78, blue: 0.98)
    public static let gold = Color(red: 0.98, green: 0.80, blue: 0.35)
    public static let dim = Color.white.opacity(0.55)
}

/// The widget's visual content, background-free. `ReviewWidgetSize` is passed in (not
/// read from `@Environment(\.widgetFamily)`) so this renders without a widget context.
public struct ReviewWidgetContent: View {
    public let data: ReviewWidgetData
    public let size: ReviewWidgetSize

    public init(data: ReviewWidgetData, size: ReviewWidgetSize) {
        self.data = data
        self.size = size
    }

    private func t(_ zh: String, _ en: String) -> String { data.zh ? zh : en }

    /// Total items due across both stores — the single number the tiny accessories show.
    private var totalDue: Int { data.totalDue }

    public var body: some View {
        switch size {
        case .accessoryRectangular: accessoryRectangular
        case .accessoryInline:      accessoryInline
        case .accessoryCircular:    accessoryCircular
        case .medium where data.hasData: medium
        case .small where data.hasData:  small
        default: emptyState
        }
    }

    // MARK: Lock-screen accessories (monochrome — no palette colours)

    /// One line above the clock: "🚲 12 due" / "🚲 全部复习完".
    private var accessoryInline: some View {
        Label {
            Text(!data.hasData ? t("にほんご ライド", "Nihongo Ride")
                 : data.isAllCaughtUp ? t("全部复习完", "all caught up")
                                 : t("\(totalDue) 个到期", "\(totalDue) due"))
        } icon: {
            Image(systemName: "bicycle")
        }
    }

    /// A rectangle: due breakdown + streak, all monochrome.
    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(t("にほんご ライド", "Nihongo Ride"), systemImage: "bicycle")
                .font(.caption2).fontWeight(.semibold)
            if !data.hasData {
                Text(t("打开看看要复习什么", "Open to see what's due")).font(.caption)
            } else if data.isAllCaughtUp {
                Text(t("全部复习完啦", "All caught up")).font(.caption)
            } else {
                Text(t("\(data.vocabDue) 词 · \(data.conjugationDue) 变形",
                       "\(data.vocabDue) words · \(data.conjugationDue) forms"))
                    .font(.caption).fontWeight(.medium)
            }
            // The stale hint that the home-screen layouts carry. Of the three accessory
            // layouts this is the only one with a spare line for it, and without it a
            // lock-screen widget whose snapshot has aged past the horizon states a stale
            // count as fact — the same dishonesty v1.12/v1.13 removed from the larger
            // sizes. Streak yields the line when both want it: a wrong number matters
            // more than a right one.
            if data.stale {
                Text(t("打开以刷新", "Open to refresh")).font(.caption2)
            } else if data.streakDays > 0 {
                Text(t("🔥 连续 \(data.streakDays) 天", "🔥 \(data.streakDays)-day streak"))
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A circular gauge: the total due count, centered.
    private var accessoryCircular: some View {
        ZStack {
            // A faint disc instead of WidgetKit's AccessoryWidgetBackground — keeps this
            // module WidgetKit-free so the app can render it headlessly. On the lock
            // screen the system's own vibrancy sits behind it either way.
            Circle().fill(.secondary.opacity(0.25))
            if data.hasData {
                VStack(spacing: -2) {
                    Text("\(totalDue)").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(t("到期", "due")).font(.system(size: 9))
                }
            } else {
                Image(systemName: "bicycle").font(.system(size: 20))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("🚲").font(.system(size: 26))
            Text(t("打开 Nihongo Ride", "Open Nihongo Ride"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(t("看看有什么要复习", "to see what's due"))
                .font(.system(size: 11)).foregroundStyle(WidgetPalette.dim)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var small: some View {
        // The headline number is vocab if any is due, otherwise conjugation. Only when
        // BOTH are zero does it say "all caught up" — the old layout read vocab alone and
        // claimed everything was done while conjugation drills were still due (grounding
        // LOW, v1.13 §B). The label names which count is showing so the number is never
        // ambiguous.
        let showConj = data.vocabDue == 0 && data.conjugationDue > 0
        let count = showConj ? data.conjugationDue : data.vocabDue
        let allDone = data.isAllCaughtUp
        return VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(allDone ? WidgetPalette.dim : .white)
                .contentTransition(.numericText())
            Text(allDone ? t("全部复习完啦", "all caught up")
                         : showConj ? t("个变形到期", "forms due")
                                    : t("个词到期", "words due"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetPalette.dim)
            Spacer(minLength: 0)
            footline
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // The medium's left column is the vocab headline WITHOUT the small layout's streak
    // footline — otherwise vocab and streak would each appear twice (the right column
    // owns the conjugation count and the streak).
    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                Text("\(data.vocabDue)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(data.vocabDue == 0 ? WidgetPalette.dim : .white)
                    .monospacedDigit()
                // "All caught up" only when BOTH counts are zero. v1.13 §B fixed exactly this
                // for the small layout and missed the medium, where the very next column can
                // be showing due conjugations — and since v1.14 §B the app badge counts them,
                // so the widget would have been contradicting the badge on the same screen.
                Text(data.isAllCaughtUp ? t("全部复习完啦", "all caught up")
                                          : t("个词到期", "words due"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.dim)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 6) {
                Spacer(minLength: 0)
                dueRow(count: data.conjugationDue, label: t("个变形", "conjugations"),
                       tint: WidgetPalette.accent2)
                Spacer(minLength: 0)
                if data.stale {
                    Text(t("打开以刷新", "open to refresh"))
                        .font(.system(size: 11)).foregroundStyle(WidgetPalette.dim)
                } else if data.streakDays > 0 {
                    Text(t("🔥 连续 \(data.streakDays) 天", "🔥 \(data.streakDays)-day streak"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dueRow(count: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(count == 0 ? WidgetPalette.dim : .white)
                .monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(WidgetPalette.dim)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("🚲").font(.system(size: 13))
            Text("Nihongo Ride")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder private var footline: some View {
        if data.stale {
            Text(t("打开以刷新", "open to refresh"))
                .font(.system(size: 10)).foregroundStyle(WidgetPalette.dim)
        } else if data.streakDays > 0 {
            Text("🔥 \(data.streakDays)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetPalette.gold)
        }
    }
}
