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

    public init(hasData: Bool, stale: Bool, vocabDue: Int, conjugationDue: Int, streakDays: Int) {
        self.hasData = hasData
        self.stale = stale
        self.vocabDue = vocabDue
        self.conjugationDue = conjugationDue
        self.streakDays = streakDays
    }

    public static let placeholder = ReviewWidgetData(
        hasData: true, stale: false, vocabDue: 12, conjugationDue: 3, streakDays: 5)
    public static let empty = ReviewWidgetData(
        hasData: false, stale: false, vocabDue: 0, conjugationDue: 0, streakDays: 0)
}

public enum ReviewWidgetSize: Sendable { case small, medium }

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

    public var body: some View {
        if !data.hasData {
            emptyState
        } else if size == .medium {
            medium
        } else {
            small
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("🚲").font(.system(size: 26))
            Text("Open Nihongo Ride")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("to see what's due")
                .font(.system(size: 11)).foregroundStyle(WidgetPalette.dim)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text("\(data.vocabDue)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(data.vocabDue == 0 ? WidgetPalette.dim : .white)
                .contentTransition(.numericText())
            Text(data.vocabDue == 0 ? "all caught up" : "words due")
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
                Text(data.vocabDue == 0 ? "all caught up" : "words due")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.dim)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 6) {
                Spacer(minLength: 0)
                dueRow(count: data.conjugationDue, label: "conjugations", tint: WidgetPalette.accent2)
                Spacer(minLength: 0)
                if data.stale {
                    Text("open to refresh")
                        .font(.system(size: 11)).foregroundStyle(WidgetPalette.dim)
                } else if data.streakDays > 0 {
                    Text("🔥 \(data.streakDays)-day streak")
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
            Text("open to refresh")
                .font(.system(size: 10)).foregroundStyle(WidgetPalette.dim)
        } else if data.streakDays > 0 {
            Text("🔥 \(data.streakDays)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetPalette.gold)
        }
    }
}
