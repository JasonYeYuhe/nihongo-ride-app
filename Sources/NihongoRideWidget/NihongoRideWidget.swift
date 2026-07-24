import WidgetKit
import SwiftUI
import WidgetSharedKit

// The visual content + colours live in WidgetSharedKit (ReviewWidgetContent), so the
// app can render them headlessly for a visual check. This file is only the WidgetKit
// plumbing: the timeline, the entry, and the @main bundle.

/// One resolved moment on the timeline. Wraps the render-ready `ReviewWidgetData` plus
/// its date; Sendable so it crosses the timeline boundary cleanly.
struct ReviewEntry: TimelineEntry, Sendable {
    let date: Date
    let data: ReviewWidgetData
}

struct ReviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReviewEntry {
        ReviewEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReviewEntry) -> Void) {
        completion(ReviewEntry(date: Date(), data: Self.data(at: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReviewEntry>) -> Void) {
        let cal = Calendar.current
        let now = Date()
        guard let snap = WidgetSnapshotStore.read() else {
            // No snapshot yet: one empty entry; retry in an hour (the app also reloads
            // us directly once it runs and populates the group container).
            completion(Timeline(entries: [ReviewEntry(date: now, data: .empty)],
                                policy: .after(now.addingTimeInterval(3600))))
            return
        }
        // An entry for now, then one at each local midnight across the horizon, so the
        // count rolls forward without the app running. The app reloads us on every
        // review; .atEnd is only the fallback if it doesn't for two weeks.
        var entries = [ReviewEntry(date: now, data: Self.data(from: snap, at: now, cal: cal))]
        let startToday = cal.startOfDay(for: now)
        for k in 1..<WidgetSnapshot.horizon {
            if let midnight = cal.date(byAdding: .day, value: k, to: startToday) {
                entries.append(ReviewEntry(date: midnight, data: Self.data(from: snap, at: midnight, cal: cal)))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func data(at date: Date) -> ReviewWidgetData {
        guard let snap = WidgetSnapshotStore.read() else { return .empty }
        return data(from: snap, at: date, cal: .current)
    }

    private static func data(from snap: WidgetSnapshot, at date: Date, cal: Calendar) -> ReviewWidgetData {
        ReviewWidgetData(
            hasData: true,
            stale: snap.isStale(asOf: date, calendar: cal),
            vocabDue: snap.vocabDue(asOf: date, calendar: cal),
            conjugationDue: snap.conjugationDue(asOf: date, calendar: cal),
            streakDays: snap.streak(asOf: date, calendar: cal),
            zh: snap.languageCode == "zh")
    }
}

/// Maps the widget family to our size and wraps the shared content in the required
/// `.containerBackground`. iOS 17 / macOS 14 both need containerBackground; the shared
/// content carries no background of its own so it also renders standalone.
struct ReviewWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReviewEntry

    var body: some View {
        ReviewWidgetContent(data: entry.data, size: contentSize)
            .padding(padding)
            // Home-screen families get the app's dark background; lock-screen accessories
            // are system-tinted, so they take the widget's default (clear) container.
            .containerBackground(for: .widget) {
                isAccessory ? AnyView(Color.clear) : AnyView(WidgetPalette.bg)
            }
    }

    // The accessory WidgetFamily cases only exist on iOS, so every switch that names them
    // is #if-guarded — referencing them on macOS is a compile error.
    private var isAccessory: Bool {
        #if os(iOS)
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular: return true
        default: return false
        }
        #else
        return false
        #endif
    }

    private var padding: CGFloat {
        switch family {
        case .systemMedium: return 4
        case .systemSmall: return 2
        default: return 0   // accessories manage their own tight layout
        }
    }

    private var contentSize: ReviewWidgetSize {
        #if os(iOS)
        switch family {
        case .accessoryRectangular: return .accessoryRectangular
        case .accessoryInline: return .accessoryInline
        case .accessoryCircular: return .accessoryCircular
        default: break
        }
        #endif
        return family == .systemMedium ? .medium : .small
    }
}

struct ReviewDueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NihongoRideReviewDue", provider: ReviewProvider()) { entry in
            ReviewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Review Due")
        .description("How many words and conjugations are due to review today.")
        // Accessory (lock-screen) families exist only on iOS — they are unavailable in
        // macOS WidgetKit, so listing them there fails to compile. Home-screen families
        // are shared. (v1.13 §C.)
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

@main
struct NihongoRideWidgets: WidgetBundle {
    var body: some Widget {
        ReviewDueWidget()
    }
}
