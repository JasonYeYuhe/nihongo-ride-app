import SwiftUI
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zh ? "骑行日志" : "Ride Log")
                    .scaledSystemFont(isPhoneIdiom ? 28 : 32, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                Text(zh ? "你的打字旅程,一页一页记着" : "Every ride, remembered")
                    .scaledSystemFont(13)
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button(action: model.backToMenu) {
                Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                    .scaledSystemFont(14, weight: .semibold)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("journalBackButton")
        }
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
        let ridden = Set(model.journal.records.map { calendar.startOfDay(for: $0.date) })
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

    private func odoRow(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .scaledSystemFont(24, weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(unit)
                .scaledSystemFont(12, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.dim)
        }
    }

    // MARK: SRS forecast

    private var forecastCard: some View {
        let forecast = model.reviewStore.dueForecast()
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

    private func forecastRow(_ label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(count > 0 ? tint : Color.white.opacity(0.12))
                .frame(width: 7, height: 7)
            Text(label)
                .scaledSystemFont(13, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.dim)
            Spacer()
            Text("\(count)")
                .scaledSystemFont(18, weight: .bold, design: .rounded)
                .foregroundStyle(count > 0 ? .white : Theme.dim)
                .monospacedDigit()
        }
    }

    // MARK: WPM trend

    private var trendCard: some View {
        let series = model.journal.wpmSeries(last: 20)
        let trendSpoken: String = {
            guard series.count >= 2 else {
                return zh ? "数据不足" : "Not enough rides yet"
            }
            let best = Int(model.journal.bestWPM ?? 0)
            return zh ? "最佳 \(best) WPM,最近 \(series.count) 程"
                      : "Best \(best) WPM across your last \(series.count) rides"
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                cardTitle(zh ? "速度趋势" : "Speed trend", icon: "gauge.with.needle", tint: Theme.done)
                Spacer()
                if let best = model.journal.bestWPM {
                    Text((zh ? "最佳 " : "BEST ") + "\(Int(best)) WPM")
                        .scaledSystemFont(11, weight: .heavy, design: .rounded)
                        .tracking(1)
                        .foregroundStyle(Theme.gold)
                }
            }
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

    private func rideRow(_ record: RideRecord) -> some View {
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
                .frame(width: isPhoneIdiom ? 52 : 64, alignment: .leading)
            Text(levelLabel(record.level))
                .scaledSystemFont(10, weight: .heavy, design: .rounded)
                .foregroundStyle(Theme.accent2)
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
        .padding(.vertical, 8)
        // Combine the date / mode / level / score / wpm / accuracy fragments into
        // one spoken row instead of six disjoint VoiceOver stops.
        .accessibilityElement()
        .accessibilityLabel(rideRowLabel(record))
    }

    private func rideRowLabel(_ record: RideRecord) -> String {
        let mode: String
        switch record.mode {
        case "timeAttack": mode = zh ? "限时" : "Time Attack"
        case "practice":   mode = zh ? "练习" : "Practice"
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
            }
            Text(value)
                .scaledSystemFont(13, weight: .semibold, design: .rounded)
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
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
        default: ("bicycle", Theme.accent2)
        }
    }

    private func levelLabel(_ level: String) -> String {
        switch level {
        case "easy": zh ? "短" : "S"
        case "med": zh ? "中" : "M"
        case "hard": zh ? "长" : "L"
        case "all": zh ? "混合" : "MIX"
        default: level   // N5…N1
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
                    Text("🚲")
                        .scaledSystemFont(16)
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
