import SwiftUI
import VocabKit
import JournalKit
import ReviewKit

/// "Ride Log" — the rider's travel diary. Streak, lifetime odometer, WPM
/// trend drawn as the road already ridden, SRS due forecast, recent runs.
///
/// Design (per /frontend-design): night-ride almanac. Same deep-navy night
/// sky as the menu, but laid out like a logbook page: a hero band of three
/// instrument cards, a road-shaped trend line with the bike at its end, and
/// a quiet ledger of recent rides. The 14-day "road stud" strip under the
/// streak flame is the screen's signature.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: isPhoneIdiom ? 14 : 18) {
            header

            if isPhoneIdiom {
                streakCard
                totalsCard
                forecastCard
            } else {
                HStack(alignment: .top, spacing: 18) {
                    streakCard
                    totalsCard
                    forecastCard
                }
            }

            trendCard
            recentCard
        }
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .padding(isPhoneIdiom ? 18 : 36)

        // ScrollView at runtime; plain stack for ImageRenderer (it doesn't
        // lay out ScrollView children) — same pattern as AboutView.
        return Group {
            if Screenshotter.isCapturing {
                content
            } else {
                ScrollView(showsIndicators: false) { content }
            }
        }
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .escape || command == .returnKey { model.backToMenu() }
                    },
                    suppressSoftwareKeyboard: true
                )
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: zh ? "骑行日志" : "Ride Log",
                     subtitle: zh ? "你的打字旅程,一页一页记着" : "Every ride, remembered",
                     backLabel: zh ? "返回" : "Back",
                     backIdentifier: "journalBackButton",
                     isPhoneIdiom: isPhoneIdiom,
                     onBack: model.backToMenu)
    }

    // MARK: Streak

    private var streakCard: some View {
        let streak = model.journal.streakDays()
        return VStack(alignment: .leading, spacing: 12) {
            cardTitle(zh ? "连续骑行" : "Streak", icon: "flame.fill", tint: Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(streak)")
                    .scaledSystemFont(44, weight: .black, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(streak > 0 ? Theme.accent : Theme.dim)
                    .monospacedDigit()
                Text(zh ? "天" : (streak == 1 ? "day" : "days"))
                    .scaledSystemFont(15, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.dim)
            }
            dayStuds
            Text(zh ? "最近两周" : "Last two weeks")
                .scaledSystemFont(10, weight: .medium)
                .tracking(1)
                .foregroundStyle(Theme.dim.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(20)
        // One element — the title, big number, and decorative day-studs strip
        // would otherwise be three disjoint VoiceOver stops.
        .accessibilityElement()
        .accessibilityLabel(zh ? "连续骑行" : "Streak")
        .accessibilityValue(zh ? "\(streak) 天" : "\(streak) \(streak == 1 ? "day" : "days")")
    }

    /// 14 "road studs", one per day, lit on days with a ride; today ringed.
    private var dayStuds: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // The same answer the streak number is computed from — see RideJournal.riddenDays.
        let ridden = model.journal.riddenDays(calendar: calendar)
        let days: [(date: Date, lit: Bool)] = (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, ridden.contains(day))
        }
        return HStack(spacing: 5) {
            ForEach(days, id: \.date) { day in
                Circle()
                    .fill(day.lit ? Theme.accent : Color.white.opacity(0.10))
                    .frame(width: 10, height: 10)
                    .overlay {
                        if day.date == today {
                            Circle().strokeBorder(Theme.gold, lineWidth: 1.5).padding(-2.5)
                        }
                    }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Lifetime odometer

    private var totalsCard: some View {
        // Lifetime totals come from the odometer (sums across synced devices),
        // falling back to the local journal — never showing less than either.
        let km = String(format: "%.1f", model.lifetimeDistanceMeters / 1000)
        let spoken = zh
            ? "\(model.lifetimeWords) 词,\(km) 公里,\(model.lifetimeRuns) 程"
            : "\(model.lifetimeWords) words, \(km) kilometers, \(model.lifetimeRuns) runs"
        return VStack(alignment: .leading, spacing: 12) {
            cardTitle(zh ? "里程表" : "Odometer", icon: "bicycle", tint: Theme.accent2)
            odoRow(value: "\(model.lifetimeWords)", unit: zh ? "词" : "words")
            odoRow(value: km, unit: "km")
            odoRow(value: "\(model.lifetimeRuns)", unit: zh ? "程" : "runs")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(20)
        .accessibilityElement()
        .accessibilityLabel(zh ? "里程表" : "Odometer")
        .accessibilityValue(spoken)
    }

    /// One line and a 0.7 shrink floor — **at the accessibility sizes only**, where the odometer and
    /// forecast rows below need them. Everywhere else these are SwiftUI's own defaults (`nil`, `1`),
    /// so the modifiers change nothing there.
    ///
    /// Not unconditional, and that was measured rather than assumed: with a plain
    /// `.lineLimit(1).minimumScaleFactor(0.7)` the headless `journal.png` render CHANGED at the
    /// default size (2026-09-17, ~450k pixels, en and zh) — `ImageRenderer` drew the odometer
    /// numbers and forecast counts visibly smaller and the two cards shorter, although every one of
    /// them fits. It does not shrink text the way a device does (`ScaledFont.swift`; the same
    /// render already draws the recent-ride dates, which carry a shrink allowance, at two different
    /// sizes). A device may well have been unaffected, but the macOS App Store screenshots come out
    /// of that renderer, and "unchanged at the default size" is only provable where the value is
    /// the default. (v1.33 §B L.)
    private var accessibilityLineLimit: Int? { typeSize.isAccessibilitySize ? 1 : nil }
    private var accessibilityShrinkFloor: CGFloat { typeSize.isAccessibilitySize ? 0.7 : 1 }

    /// ⚠️ One line each, with a shrink floor, on the value AND the unit at the accessibility sizes —
    /// the fix `dueChip` in `StatsView` got in v1.32 for "Tomorr / ow", applied to its twin here. A
    /// lifetime count only grows: measured with CoreText for a 393pt phone at AX5 (2026-09-17, v1.33
    /// scan finding #11/#12), "9999 words" is 305pt in a 313pt card and "12345 words" is 354, so the
    /// learner's ten-thousandth word is the one that would break the number or "words" across two
    /// lines. 354 → 313 is ×0.88, inside the 0.7 floor. Both fit untouched below the accessibility
    /// sizes (160pt at XXXL), which is why the floor is not applied there. (v1.33 §B L.)
    private func odoRow(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .scaledSystemFont(24, weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(accessibilityLineLimit).minimumScaleFactor(accessibilityShrinkFloor)
            Text(unit)
                .scaledSystemFont(12, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.dim)
                .lineLimit(accessibilityLineLimit).minimumScaleFactor(accessibilityShrinkFloor)
        }
    }

    // MARK: SRS forecast

    private var forecastCard: some View {
        let forecast = model.reviewStore.dueForecast(
            resolves: model.vocab.resolvesID)   // the model's OWN store, not the global
        let spoken = zh
            ? "今天 \(forecast.today),明天 \(forecast.tomorrow),本周 \(forecast.thisWeek)"
            : "Today \(forecast.today), tomorrow \(forecast.tomorrow), this week \(forecast.thisWeek)"
        return VStack(alignment: .leading, spacing: 12) {
            cardTitle(zh ? "复习预报" : "Review forecast", icon: "brain.head.profile", tint: Theme.gold)
            forecastRow(zh ? "今天" : "Today", count: forecast.today, tint: Theme.accent)
            forecastRow(zh ? "明天" : "Tomorrow", count: forecast.tomorrow, tint: Theme.gold)
            forecastRow(zh ? "本周" : "This week", count: forecast.thisWeek, tint: Theme.accent2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(20)
        .accessibilityElement()
        .accessibilityLabel(zh ? "复习预报" : "Review forecast")
        .accessibilityValue(spoken)
    }

    /// ⚠️ The Stats "Tomorr / ow" defect's twin (v1.32 fixed it in `StatsView.dueChip`; this row
    /// has the same label and was left out). Measured with CoreText for a 393pt phone at AX5,
    /// 2026-09-17 (v1.33 scan finding #13/#14): "Tomorrow" beside 99 due is 289pt in a 313pt
    /// card and fits; beside 100 it is 325, and beside 1000 it is 362 — so the row broke exactly
    /// when a learner's backlog crossed three digits. One line and a 0.7 floor on the label and
    /// the count at the accessibility sizes: 362 → 313 is ×0.86. At XXXL the widest case is 178pt,
    /// so below the accessibility sizes the floor is not applied (see `accessibilityShrinkFloor`
    /// for why that is measured, not just tidy). (v1.33 §B L.)
    private func forecastRow(_ label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(count > 0 ? tint : Color.white.opacity(0.12))
                .frame(width: 7, height: 7)
            Text(label)
                .scaledSystemFont(13, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.dim)
                .lineLimit(accessibilityLineLimit).minimumScaleFactor(accessibilityShrinkFloor)
            Spacer()
            Text("\(count)")
                .scaledSystemFont(18, weight: .bold, design: .rounded)
                .foregroundStyle(count > 0 ? .white : Theme.dim)
                .monospacedDigit()
                .lineLimit(accessibilityLineLimit).minimumScaleFactor(accessibilityShrinkFloor)
        }
    }

    // MARK: WPM trend

    private var trendCard: some View {
        let series = model.journal.wpmSeries(last: 20)
        // Two things this used to get wrong, both of them VoiceOver saying something the
        // screen does not:
        //  - The BEST badge below draws whenever a best exists, which can be after ONE ride —
        //    but this returned "Not enough rides yet" for the whole card, and the card is an
        //    accessibilityElement, so the badge was on screen and unreachable. The best is now
        //    spoken whenever it is drawn; only the CHART is what needs two rides.
        //  - Int() truncates. StatsView's tile rounds. A best of 57.8 was the same number
        //    read as 57 here and 58 there.
        let bestSpoken: String? = model.journal.bestWPM.map { String(Int($0.rounded())) }
        let trendSpoken: String = {
            let bestPart = bestSpoken.map { zh ? "最佳 \($0) WPM" : "Best \($0) WPM" }
            guard series.count >= 2 else {
                let none = zh ? "还需要一程才能画出趋势" : "One more ride and the trend appears"
                return [bestPart, none].compactMap { $0 }.joined(separator: zh ? "," : ". ")
            }
            let span = zh ? "最近 \(series.count) 程" : "across your last \(series.count) rides"
            return [bestPart, span].compactMap { $0 }.joined(separator: zh ? "," : " ")
        }()
        return VStack(alignment: .leading, spacing: 10) {
            trendHeader(best: bestSpoken)
            if series.count >= 2 {
                RoadSparkline(values: series)
                    .frame(height: isPhoneIdiom ? 90 : 110)
                    .accessibilityHidden(true)   // decorative chart; summarized below
                Text(zh ? "最近 \(series.count) 程的 WPM" : "WPM across your last \(series.count) rides")
                    .scaledSystemFont(11)
                    .foregroundStyle(Theme.dim.opacity(0.7))
            } else {
                emptyHint(zh ? "骑满两程,这里会画出你的路。" : "Ride twice and your road appears here.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(20)
        .accessibilityElement()
        .accessibilityLabel(zh ? "速度趋势" : "Speed trend")
        .accessibilityValue(trendSpoken)
    }

    /// The card title and, once a best exists, the BEST badge.
    ///
    /// ⚠️ **At the accessibility sizes the badge goes UNDER the title**, and no shrink allowance
    /// could stand in for that. Measured with CoreText for a 393pt phone at AX5, 2026-09-17 (v1.33
    /// scan finding #15): "SPEED TREND" with its icon is 310pt and "BEST 157 WPM" is 261, against
    /// a 313pt card — squeezing both onto one line would take ×0.55, and splitting the width
    /// evenly broke "SPEE / D". Under the title the badge has the whole card (261 of 313).
    ///
    /// Below the accessibility sizes the header is exactly what it was: at XXXL the one-line
    /// header is 285pt of 313. (v1.33 §B L.)
    @ViewBuilder
    private func trendHeader(best: String?) -> some View {
        let title = cardTitle(zh ? "速度趋势" : "Speed trend", icon: "gauge.with.needle", tint: Theme.done)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                title
                if let best { bestBadge(best) }
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer()
                if let best { bestBadge(best) }
            }
        }
    }

    private func bestBadge(_ best: String) -> some View {
        Text((zh ? "最佳 " : "BEST ") + "\(best) WPM")
            .scaledSystemFont(11, weight: .heavy, design: .rounded)
            .tracking(1)
            .foregroundStyle(Theme.gold)
    }

    // MARK: Recent rides

    private var recentCard: some View {
        let recent = model.journal.recent(10)
        return VStack(alignment: .leading, spacing: 10) {
            cardTitle(zh ? "最近骑行" : "Recent rides", icon: "list.bullet.rectangle", tint: Theme.accent2)
            if recent.isEmpty {
                emptyHint(zh ? "还没有记录——出发吧!🚲" : "No rides yet — saddle up! 🚲")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                        rideRow(record)
                        if index < recent.count - 1 {
                            Divider().background(Theme.cardStroke.opacity(0.6))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(20)
    }

    /// Grows the date column with Dynamic Type — see the comment at its use site.
    @ScaledMetric(relativeTo: .caption) private var dateColumnPhone: CGFloat = 52
    @ScaledMetric(relativeTo: .caption) private var dateColumnWide: CGFloat = 64
    private var dateColumnWidth: CGFloat { isPhoneIdiom ? dateColumnPhone : dateColumnWide }

    /// One ride.
    ///
    /// ⚠️ **At the accessibility text sizes this row becomes two lines, and that is not a
    /// preference.** Measured on an iPhone 17 Pro at AX5, 2026-09-10: the six-column HStack
    /// squeezed every column to about one glyph of width, and each `Text` — none of which could
    /// wrap horizontally any further — wrapped VERTICALLY instead. "N5" rendered as N over 5,
    /// "MINE" as four stacked letters, "★651" as ★ over 6 over 5 over 1, "WPM 22" as W/P/M beside
    /// 2/2, and "100%" as 1/0/0/% with the % half off the right edge. Every value in the row was
    /// illegible, on a screen whose entire job is showing them.
    ///
    /// `PLAN-ITERATION` recorded this as *"the Ride Log does not survive"* at AX5 and left it
    /// unfixed for two releases, because `ImageRenderer` cannot see it — it does not lay out or
    /// shrink text the way a device does (`ScaledFont.swift`, since v1.7). It was found by
    /// looking, twice.
    ///
    /// The fix is the one `MenuView:128` already uses for the route strip, for the same reason
    /// and with the same argument: a horizontal arrangement that cannot fit stops being a
    /// horizontal arrangement. The identity (icon, date, level) stays on the first line and the
    /// numbers move to a second, where they have the width to be read. The VoiceOver label does
    /// not change — it was already one spoken sentence, and it was already the only version of
    /// this row that worked at these sizes.
    private func rideRow(_ record: RideRecord) -> some View {
        Group {
            if typeSize.isAccessibilitySize { stackedRideRow(record) } else { inlineRideRow(record) }
        }
        .padding(.vertical, 8)
        // Combine the date / mode / level / score / wpm / accuracy fragments into
        // one spoken row instead of six disjoint VoiceOver stops.
        .accessibilityElement()
        .accessibilityLabel(rideRowLabel(record))
    }

    /// The mode icon's tile in the STACKED row, scaled against `.body` — the text style the glyph
    /// inside it scales against (`scaledSystemFont` defaults to `.body`), so tile and glyph grow at
    /// the same rate and keep the default proportions.
    ///
    /// The fixed 26×26 tile did not grow while its glyph did. Measured with CoreText, 2026-09-17:
    /// the bicycle glyph is 23pt wide at the default size and 73pt at AX5, so on the device it
    /// spilled out of its 26pt tile over "Today" / "今天" (simulator pass #13, 402pt iPhone 17 Pro).
    /// Scaled, the tile is 81pt at AX5. Only the stacked row uses it: the inline row is never drawn
    /// at the accessibility sizes, and at the default size this is 26 exactly. (v1.33 §B L.)
    @ScaledMetric(relativeTo: .body) private var stackedIconTile: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var stackedIconCorner: CGFloat = 7

    /// The accessibility-size arrangement: identity on one line, numbers on the next.
    private func stackedRideRow(_ record: RideRecord) -> some View {
        let style = modeStyle(record.mode)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .scaledSystemFont(12, weight: .bold)
                    .foregroundStyle(style.tint)
                    .frame(width: stackedIconTile, height: stackedIconTile)
                    .background(style.tint.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: stackedIconCorner))
                Text(dayLabel(record.date))
                    .scaledSystemFont(12, weight: .medium, design: .rounded)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(levelLabel(record.level))
                    .scaledSystemFont(10, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.accent2)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent2.opacity(0.14), in: Capsule())
                Spacer(minLength: 0)
            }
            // `FlowLayout` rather than an HStack, for the reason `GameView:719` gives: an HStack
            // cannot wrap, and at AX5 three stats do not fit one line either.
            FlowLayout(spacing: 12, lineSpacing: 4) {
                if record.score > 0 { rowStat("★", "\(record.score)", tint: Theme.gold) }
                if record.wpm > 0 { rowStat("WPM", "\(Int(record.wpm))", tint: Theme.done) }
                rowStat("", "\(Int(record.accuracy * 100))%", tint: .white)
            }
        }
    }

    private func inlineRideRow(_ record: RideRecord) -> some View {
        let style = modeStyle(record.mode)
        return HStack(spacing: isPhoneIdiom ? 8 : 12) {
            Image(systemName: style.icon)
                .scaledSystemFont(12, weight: .bold)
                .foregroundStyle(style.tint)
                .frame(width: 26, height: 26)
                .background(style.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            Text(dayLabel(record.date))
                .scaledSystemFont(12, weight: .medium, design: .rounded)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // A fixed date column truncates the date itself at larger text sizes, and a
                // truncated date reads as a different day rather than as a broken layout.
                // Scale the column with the text; shrink the glyphs only as a last resort.
                .frame(width: dateColumnWidth, alignment: .leading)
            Text(levelLabel(record.level))
                .scaledSystemFont(10, weight: .heavy, design: .rounded)
                .foregroundStyle(Theme.accent2)
                // The sizes just BELOW the accessibility range squeeze this the same way, only
                // less — "MINE" is the longest label and the one that showed it first.
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.accent2.opacity(0.14), in: Capsule())
            Spacer(minLength: 4)
            if record.score > 0 {
                rowStat("★", "\(record.score)", tint: Theme.gold)
            }
            if record.wpm > 0 {
                rowStat("WPM", "\(Int(record.wpm))", tint: Theme.done)
            }
            rowStat("", "\(Int(record.accuracy * 100))%", tint: .white)
        }
    }

    private func rideRowLabel(_ record: RideRecord) -> String {
        let mode: String
        switch record.mode {
        case "timeAttack": mode = zh ? "限时" : "Time Attack"
        case "practice":   mode = zh ? "练习" : "Practice"
        case "sentence":   mode = zh ? "例句" : "Sentence"
        case "dictation":  mode = zh ? "听写" : "Dictation"
        default:           mode = zh ? "环游" : "Journey"
        }
        let acc = Int(record.accuracy * 100)
        var parts = [dayLabel(record.date), mode, levelLabel(record.level)]
        if record.score > 0 { parts.append(zh ? "得分 \(record.score)" : "score \(record.score)") }
        if record.wpm > 0 { parts.append("\(Int(record.wpm)) WPM") }
        parts.append(zh ? "正确率 \(acc)%" : "\(acc)% accuracy")
        return parts.joined(separator: zh ? "," : ", ")
    }

    private func rowStat(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            if !label.isEmpty {
                Text(label)
                    .scaledSystemFont(9, weight: .bold, design: .rounded)
                    .foregroundStyle(tint.opacity(0.8))
                    // "WPM" wrapped to W/P/M stacked, which is what a three-letter label does
                    // when its column is one glyph wide.
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(value)
                .scaledSystemFont(13, weight: .semibold, design: .rounded)
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(minWidth: isPhoneIdiom ? 38 : 48, alignment: .trailing)
    }

    // MARK: Small pieces

    private func cardTitle(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            Text(title.uppercased())
                .scaledSystemFont(11, weight: .black, design: .rounded)
                .tracking(2)
                .foregroundStyle(Theme.dim)
        } icon: {
            Image(systemName: icon)
                .scaledSystemFont(12, weight: .bold)
                .foregroundStyle(tint)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .scaledSystemFont(13)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, minHeight: 56)
            .multilineTextAlignment(.center)
    }

    private func modeStyle(_ mode: String) -> (icon: String, tint: Color) {
        switch mode {
        case "timeAttack": ("timer", Theme.gold)
        case "practice": ("text.alignleft", Theme.done)
        case "sentence": ("text.quote", Theme.gold)
        case "dictation": ("ear", Theme.accent2)
        default: ("bicycle", Theme.accent2)
        }
    }

    private func levelLabel(_ level: String) -> String { Self.levelLabel(level, zh: zh) }

    /// The capsule beside a ride's date. **Every label here is short on purpose, and the
    /// `default:` used to pass anything else straight through.**
    ///
    /// That cost a broken screen the day a new level string appeared. v1.31's custom-text runs
    /// log `level: "custom"`, which rendered a six-character capsule in a row laid out for one
    /// — the score, WPM and accuracy columns beside it were squeezed until they wrapped
    /// character by character and the row became unreadable. Found by looking at the Ride Log
    /// on a phone, not by any test.
    ///
    /// So the passthrough is now capped. The cap is the durable half: the next level string
    /// somebody adds gets an ugly label instead of a broken row, which is the right way round.
    static func levelLabel(_ level: String, zh: Bool) -> String {
        switch level {
        case "easy": return zh ? "短" : "S"
        case "med": return zh ? "中" : "M"
        case "hard": return zh ? "长" : "L"
        case "all": return zh ? "混合" : "MIX"
        case "custom": return zh ? "自选" : "MINE"
        default: return String(level.prefix(4))   // N5…N1, and anything unforeseen, bounded
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return zh ? "今天" : "Today" }
        if calendar.isDateInYesterday(date) { return zh ? "昨天" : "Yesterday" }
        let components = calendar.dateComponents([.month, .day], from: date)
        let month = components.month ?? 1, day = components.day ?? 1
        return zh ? "\(month)月\(day)日" : "\(month)/\(day)"
    }
}

// MARK: - Road sparkline

/// The WPM trend drawn as the road already ridden: a gradient path with a
/// soft glow under it, a gold dashed line at the best pace, and the bike
/// resting at the latest point.
private struct RoadSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            let best = values.max() ?? 0
            ZStack(alignment: .topLeading) {
                // Best-pace marker
                if best > 0 {
                    let bestY = yFor(best, in: geo.size)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: bestY))
                        path.addLine(to: CGPoint(x: geo.size.width, y: bestY))
                    }
                    .stroke(Theme.gold.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }

                // Soft area under the road
                area(points, in: geo.size)
                    .fill(LinearGradient(colors: [Theme.accent2.opacity(0.20), .clear],
                                         startPoint: .top, endPoint: .bottom))

                // The road itself
                line(points)
                    .stroke(LinearGradient(colors: [Theme.accent2, Theme.accent],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Waypoints + the rider at the end
                ForEach(points.indices, id: \.self) { index in
                    let isLast = index == points.count - 1
                    Circle()
                        .fill(isLast ? Theme.accent : Color.white.opacity(0.35))
                        .frame(width: isLast ? 7 : 4, height: isLast ? 7 : 4)
                        .position(points[index])
                }
                if let last = points.last {
                    // Decorative, accessibilityHidden, position-anchored to a hand-computed
                    // y-offset — keep it a FIXED size (like the GameView progress-bar emoji)
                    // so it can't drift off its anchor at large Dynamic Type sizes.
                    Text("🚲")
                        .font(.system(size: 16))
                        .position(x: last.x - 2, y: max(10, last.y - 16))
                }
            }
        }
    }

    private func bounds() -> (min: Double, max: Double) {
        let low = values.min() ?? 0, high = values.max() ?? 1
        guard high > low else { return (low - 1, high + 1) }
        let pad = (high - low) * 0.18
        return (low - pad, high + pad)
    }

    private func yFor(_ value: Double, in size: CGSize) -> CGFloat {
        let (low, high) = bounds()
        let t = (value - low) / (high - low)
        let inset: CGFloat = 8
        return inset + (1 - CGFloat(t)) * (size.height - inset * 2)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let inset: CGFloat = 8
        let step = values.count > 1 ? (size.width - inset * 2) / CGFloat(values.count - 1) : 0
        return values.enumerated().map { index, value in
            CGPoint(x: inset + CGFloat(index) * step, y: yFor(value, in: size))
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func area(_ points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
