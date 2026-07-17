import WidgetKit
import SwiftUI
import WidgetSharedKit

// MARK: - Colors (self-contained)

/// The widget extension can't import the app target, so it carries its own copy of the
/// handful of Theme colors it uses. Kept in sync with `Theme` in NihongoRideApp.swift by
/// eye — a widget that drifted a shade off the app is cosmetic, not a bug.
private enum WTheme {
    static let bg = LinearGradient(
        colors: [Color(red: 0.06, green: 0.09, blue: 0.18),
                 Color(red: 0.10, green: 0.14, blue: 0.26)],
        startPoint: .top, endPoint: .bottom)
    static let accent = Color(red: 0.98, green: 0.45, blue: 0.45)   // coral
    static let accent2 = Color(red: 0.42, green: 0.78, blue: 0.98)  // sky
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.35)
    static let dim = Color.white.opacity(0.55)
}

// MARK: - Timeline

/// One resolved moment on the widget's timeline. Sendable value; the provider computes
/// the numbers so the view is pure. `hasData == false` means no snapshot yet (fresh
/// install / App Group not populated) → the view shows a gentle "open the app" prompt.
struct ReviewEntry: TimelineEntry, Sendable {
    let date: Date
    let hasData: Bool
    let stale: Bool
    let vocabDue: Int
    let conjugationDue: Int
    let streakDays: Int

    static let placeholder = ReviewEntry(date: Date(), hasData: true, stale: false,
                                         vocabDue: 12, conjugationDue: 3, streakDays: 5)
    static let empty = ReviewEntry(date: Date(), hasData: false, stale: false,
                                   vocabDue: 0, conjugationDue: 0, streakDays: 0)
}

struct ReviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReviewEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ReviewEntry) -> Void) {
        completion(Self.resolve(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReviewEntry>) -> Void) {
        let cal = Calendar.current
        let now = Date()
        guard let snap = WidgetSnapshotStore.read() else {
            // No snapshot: one empty entry, and try again in an hour (the app may run
            // and populate the group container meanwhile — it also reloads us directly).
            completion(Timeline(entries: [.empty], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        // An entry for now, then one at each local midnight across the horizon, so the
        // count rolls forward without the app running. The app reloads us on every
        // review; .atEnd is only the fallback if it doesn't for two weeks.
        var entries = [Self.entry(from: snap, at: now, cal: cal)]
        let startToday = cal.startOfDay(for: now)
        for k in 1..<WidgetSnapshot.horizon {
            if let midnight = cal.date(byAdding: .day, value: k, to: startToday) {
                entries.append(Self.entry(from: snap, at: midnight, cal: cal))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func resolve(at date: Date) -> ReviewEntry {
        guard let snap = WidgetSnapshotStore.read() else { return .empty }
        return entry(from: snap, at: date, cal: .current)
    }

    private static func entry(from snap: WidgetSnapshot, at date: Date, cal: Calendar) -> ReviewEntry {
        ReviewEntry(date: date, hasData: true,
                    stale: snap.isStale(asOf: date, calendar: cal),
                    vocabDue: snap.vocabDue(asOf: date, calendar: cal),
                    conjugationDue: snap.conjugationDue(asOf: date, calendar: cal),
                    streakDays: snap.streakDays)
    }
}

// MARK: - View

struct ReviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReviewEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { WTheme.bg }
    }

    @ViewBuilder private var content: some View {
        if !entry.hasData {
            emptyState
        } else {
            switch family {
            case .systemMedium: medium
            default:            small
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("🚲").font(.system(size: 26))
            Text("Open Nihongo Ride")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("to see what's due")
                .font(.system(size: 11)).foregroundStyle(WTheme.dim)
        }
        .multilineTextAlignment(.center)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text("\(entry.vocabDue)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(entry.vocabDue == 0 ? WTheme.dim : .white)
                .contentTransition(.numericText())
            Text(entry.vocabDue == 0 ? "all caught up" : "words due")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(WTheme.dim)
            Spacer(minLength: 0)
            footline
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            small
            Divider().overlay(Color.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 8) {
                dueRow(count: entry.conjugationDue, label: "conjugations", tint: WTheme.accent2)
                dueRow(count: entry.vocabDue, label: "vocabulary", tint: WTheme.accent)
                Spacer(minLength: 0)
                if entry.streakDays > 0 {
                    Text("🔥 \(entry.streakDays)-day streak")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WTheme.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dueRow(count: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(count == 0 ? WTheme.dim : .white)
                .monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(WTheme.dim)
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
        if entry.stale {
            Text("open to refresh")
                .font(.system(size: 10)).foregroundStyle(WTheme.dim)
        } else if entry.streakDays > 0 {
            Text("🔥 \(entry.streakDays)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WTheme.gold)
        }
    }
}

// MARK: - Widget + Bundle

struct ReviewDueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NihongoRideReviewDue", provider: ReviewProvider()) { entry in
            ReviewWidgetView(entry: entry)
        }
        .configurationDisplayName("Review Due")
        .description("How many words and conjugations are due to review today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct NihongoRideWidgets: WidgetBundle {
    var body: some Widget {
        ReviewDueWidget()
    }
}
