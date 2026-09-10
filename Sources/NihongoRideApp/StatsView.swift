import SwiftUI
import Charts
import DiagnosticsKit

/// "Stats" (v1.9 §B) — a data screen that goes deeper than the Ride Log: words-per-day
/// bars, accuracy + WPM trends from the ride history, plus a conjugation section that
/// surfaces the verb-conjugation SRS forecast/leech data v1.8 built but never showed.
///
/// Non-game-screen contract (same as JournalView): keyboard suppressed, Esc/Back returns,
/// ScrollView at runtime but a plain stack under ImageRenderer (the capture path can't lay
/// out ScrollView children), all type via `.scaledSystemFont`, charts carry a synthesized
/// VoiceOver label+value so they aren't a wall of per-point stops.
struct StatsView: View {
    /// Chart heights scale with Dynamic Type. A chart is not text, but its axis labels are:
    /// at the accessibility sizes the day and percentage marks grow into the plot area and
    /// overlap the bars, so the picture stops being readable exactly for the reader who
    /// enlarged it. (v1.16 §D.)
    @ScaledMetric(relativeTo: .body) private var tallChartHeight: CGFloat = 160
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 130

    @Environment(AppModel.self) private var model
    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: isPhoneIdiom ? 14 : 18) {
            header
            tiles
            if model.statsHasRides {
                wordsPerDayCard
                adaptiveRow { accuracyCard; wpmCard }
            } else {
                emptyState
            }
            conjugationCard
            stumbleCard
        }
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .padding(isPhoneIdiom ? 18 : 36)

        return Group {
            if Screenshotter.isCapturing { content } else { ScrollView(showsIndicators: false) { content } }
        }
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .escape || command == .returnKey { model.backToMenu() }
                    },
                    suppressSoftwareKeyboard: true)
            }
        }
    }

    @ViewBuilder private func adaptiveRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if isPhoneIdiom { VStack(spacing: isPhoneIdiom ? 14 : 18) { content() } }
        else { HStack(alignment: .top, spacing: 18) { content() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zh ? "统计" : "Stats")
                    .scaledSystemFont(isPhoneIdiom ? 28 : 32, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                Text(zh ? "你的练习,一图看懂" : "Your practice, at a glance")
                    .scaledSystemFont(13).foregroundStyle(Theme.dim)
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
            .accessibilityIdentifier("statsBackButton")
        }
    }

    // MARK: Lifetime tiles

    private var tiles: some View {
        let streak = model.journal.streakDays()
        return MenuFlow(spacing: 12, rowSpacing: 12) {
            tile(zh ? "累计词数" : "Words", "\(model.lifetimeWords)", "textformat.abc", Theme.accent2)
            tile(zh ? "总骑行" : "Runs", "\(model.lifetimeRuns)", "bicycle", Theme.accent)
            tile(zh ? "连续天数" : "Streak", "\(streak)", "flame.fill", streak > 0 ? Theme.accent : Theme.dim)
            // "—" is a drawing, not a word: VoiceOver announces the glyph, so the tile told a
            // blind user "Best WPM, em dash" where it means "you have not ridden yet".
            tile(zh ? "最佳 WPM" : "Best WPM",
                 model.statsBestWPM.map { String(Int($0.rounded())) } ?? "—", "speedometer", Theme.gold,
                 spoken: model.statsBestWPM == nil ? (zh ? "还没有记录" : "No rides yet") : nil)
        }
    }

    private func tile(_ label: String, _ value: String, _ icon: String, _ tint: Color,
                      spoken: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).scaledSystemFont(15, weight: .semibold).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value).scaledSystemFont(30, weight: .black, design: .rounded, relativeTo: .title)
                .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).scaledSystemFont(11, weight: .medium).tracking(0.5).foregroundStyle(Theme.dim)
        }
        .frame(minWidth: 120, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spoken ?? value)
    }

    // MARK: Charts

    private var wordsPerDayCard: some View {
        let series = model.statsDailyWords
        let total = series.reduce(0) { $0 + $1.words }
        return card(zh ? "每日词数(近两周)" : "Words per day (2 weeks)", icon: "calendar",
                    a11y: zh ? "近两周共 \(total) 词" : "\(total) words over the last two weeks") {
            Chart(series, id: \.day) { point in
                BarMark(x: .value(zh ? "日" : "Day", point.day, unit: .day),
                        y: .value(zh ? "词数" : "Words", point.words))
                    .foregroundStyle(Theme.accent2.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { v in
                AxisValueLabel(format: .dateTime.day(), centered: true)
            } }
            .chartYAxis { AxisMarks(position: .trailing) }
            .frame(height: tallChartHeight)
        }
    }

    private var accuracyCard: some View {
        let series = model.statsAccuracySeries.enumerated().map { ($0.offset, $0.element.accuracy) }
        let avg = series.isEmpty ? 0 : series.reduce(0) { $0 + $1.1 } / Double(series.count)
        return card(zh ? "正确率趋势" : "Accuracy trend", icon: "target",
                    a11y: zh ? "近期平均 \(Int(avg * 100))%" : "recent average \(Int(avg * 100)) percent") {
            Chart(series, id: \.0) { point in
                LineMark(x: .value(zh ? "局" : "Run", point.0), y: .value(zh ? "正确率" : "Accuracy", point.1))
                    .foregroundStyle(Theme.accent.gradient).interpolationMethod(.catmullRom)
                AreaMark(x: .value(zh ? "局" : "Run", point.0), y: .value(zh ? "正确率" : "Accuracy", point.1))
                    .foregroundStyle(Theme.accent.opacity(0.12).gradient).interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(position: .trailing, values: [0, 0.5, 1]) { v in
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d * 100))%") } }
            } }
            .chartXAxis(.hidden)
            .frame(height: chartHeight)
        }
    }

    private var wpmCard: some View {
        let series = model.statsWPMSeries.enumerated().map { ($0.offset, $0.element) }
        return card("WPM", icon: "speedometer",
                    a11y: model.statsBestWPM.map { zh ? "最佳 \(Int($0)) WPM" : "best \(Int($0)) WPM" } ?? "WPM") {
            Chart(series, id: \.0) { point in
                LineMark(x: .value(zh ? "局" : "Run", point.0), y: .value("WPM", point.1))
                    .foregroundStyle(Theme.gold.gradient).interpolationMethod(.catmullRom)
                PointMark(x: .value(zh ? "局" : "Run", point.0), y: .value("WPM", point.1))
                    .foregroundStyle(Theme.gold).symbolSize(14)
            }
            .chartYAxis { AxisMarks(position: .trailing) }
            .chartXAxis(.hidden)
            .frame(height: chartHeight)
        }
    }

    // MARK: Conjugation section (surfaces the v1.8 conjugation SRS)

    private var conjugationCard: some View {
        let f = model.conjugationDueForecast
        let reviewed = model.conjugationReviewedCount
        let leeches = model.conjugationLeechCount
        return card(zh ? "动词变形复习" : "Conjugation Review", icon: "arrow.triangle.2.circlepath",
                    a11y: zh ? "今日到期 \(f.today),已复习 \(reviewed) 个变形"
                             : "\(f.today) due today, \(reviewed) forms reviewed") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    dueChip(zh ? "今天" : "Today", f.today, Theme.accent)
                    dueChip(zh ? "明天" : "Tomorrow", f.tomorrow, Theme.accent2)
                    dueChip(zh ? "本周" : "This week", f.thisWeek, Theme.dim)
                }
                HStack(spacing: 18) {
                    miniStat(zh ? "已练变形" : "Forms practiced", "\(reviewed)")
                    if leeches > 0 { miniStat(zh ? "顽固变形" : "Tough forms", "\(leeches)") }
                }
                if reviewed == 0 {
                    Text(zh ? "在「变形」模式里练动词,这里会记录你的进度。"
                            : "Drill verbs in Conjugation mode to build your review here.")
                        .scaledSystemFont(12).foregroundStyle(Theme.dim.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: What you keep missing (v1.32 §F2)

    /// The first thing this app has ever been able to say about a learner's typing ACROSS rides.
    ///
    /// Every run has produced this data since v1.18 and thrown it away every time, so the app
    /// could tell you what you missed in one run and never what you keep missing — the one thing
    /// a person cannot see about themselves and software can.
    ///
    /// **It renders nothing until there is something to say.** A card reading "0 habits" on a
    /// fresh install is a worse experience than no card, and worse than that it would teach the
    /// learner to ignore this corner of the screen before it ever had a finding.
    @ViewBuilder private var stumbleCard: some View {
        let habits = model.stumbleHabits
        if !habits.isEmpty {
            card(zh ? "你反复卡住的假名" : "What you keep missing",
                 icon: "scope",
                 a11y: stumbleAccessibilityLabel(habits)) {
                VStack(alignment: .leading, spacing: 12) {
                    // `FlowLayout`, not an HStack, for the reason `GameView:719` already gives:
                    // an HStack cannot wrap. Six kana at AX5 on a phone will not sit on one line
                    // and this screen has no horizontal scroll — v1.31 found FOUR separate defects
                    // that were all a Text in a row with no room, and `ImageRenderer` cannot see
                    // any of them, which is why reusing the layout that already solved it beats
                    // deciding this one fits.
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(habits.prefix(6), id: \.kana) { habit in
                            stumbleChip(habit)
                        }
                    }
                    // The number the finding rests on, and the DENOMINATOR is named exactly.
                    //
                    // It said "of your N rides" and that was false: `runsRecorded` counts rides in
                    // which the learner was refused at least once — a clean run folds nothing, by
                    // design. Somebody who rode fifty times and slipped in twenty-one would read
                    // "21 rides", check the Ride Log, and find fifty. A number labelled as
                    // something it is not is this repo's signature defect, and this was a fresh
                    // instance of it. **Found by looking at the screen**, which is also how v1.31
                    // found four; no test in this repo can see a caption that is true of a
                    // different population than the one it names.
                    if let worst = habits.first {
                        Text(zh
                             ? "在你出错的 \(model.stumbleLedger.runsRecorded) 次骑行里,「\(worst.kana)」出现了 \(worst.runs) 次。"
                             : "\(worst.kana) turned up in \(worst.runs) of the \(model.stumbleLedger.runsRecorded) rides where you slipped.")
                            .scaledSystemFont(12).foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let advice = stumbleAdvice(habits) {
                        Text(advice)
                            .scaledSystemFont(12).foregroundStyle(Theme.dim.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func stumbleChip(_ habit: StumbleLedger.Entry) -> some View {
        HStack(spacing: 6) {
            Text(habit.kana)
                .scaledSystemFont(18, weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("\(habit.runs)")
                .scaledSystemFont(12, weight: .semibold, design: .rounded).monospacedDigit()
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.card, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(zh ? "\(habit.kana),\(habit.runs) 次骑行"
                               : "\(habit.kana), \(habit.runs) rides")
    }

    /// One sentence naming the RULE behind the worst habit, when the diagnosis has one.
    ///
    /// Reads `CoachContent`, the same source the coach screen uses, so the two cannot explain the
    /// same pattern differently. `.unknown` yields nothing rather than a filler sentence: the
    /// diagnosis honestly says it does not know, and inventing advice there is how a learner is
    /// told they were wrong about something nobody diagnosed.
    private func stumbleAdvice(_ habits: [StumbleLedger.Entry]) -> String? {
        guard let worst = habits.first, worst.pattern != .unknown,
              let advice = CoachContent.advice(for: worst.pattern, zh: zh)
        else { return nil }
        return advice.rule
    }

    /// Spoken as one sentence. VoiceOver reading six capsules as six fragments is how v1.26's
    /// weak-words button came to SAY a different number than it rode — audible only to VoiceOver,
    /// which is why every headless render walked past it.
    private func stumbleAccessibilityLabel(_ habits: [StumbleLedger.Entry]) -> String {
        let named = habits.prefix(6).map { "\($0.kana) \($0.runs)" }.joined(separator: ", ")
        return zh ? "你反复卡住的假名:\(named)" : "What you keep missing: \(named)"
    }

    /// ⚠️ `lineLimit(1)` + a shrink allowance on the LABEL, because at AX5 on a phone "Tomorrow"
    /// breaks mid-word into "Tomorr / ow". Pre-existing — seen while looking at this screen for
    /// v1.32 §F2 — and the same family as the four defects v1.31 found by running the app: a
    /// `Text` whose content can grow, in a row with no `lineLimit` and no shrink allowance.
    /// `ImageRenderer` cannot see any of them (`ScaledFont.swift` has said so since v1.7).
    private func dueChip(_ label: String, _ n: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").scaledSystemFont(22, weight: .heavy, design: .rounded).monospacedDigit()
                .foregroundStyle(n > 0 ? tint : Theme.dim)
            Text(label).scaledSystemFont(10, weight: .medium).foregroundStyle(Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement().accessibilityLabel(label).accessibilityValue("\(n)")
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value).scaledSystemFont(16, weight: .bold, design: .rounded).monospacedDigit().foregroundStyle(.white)
            Text(label).scaledSystemFont(12).foregroundStyle(Theme.dim)
        }
        .accessibilityElement().accessibilityLabel(label).accessibilityValue(value)
    }

    // MARK: Empty state + card chrome

    private var emptyState: some View {
        card(zh ? "还没有骑行记录" : "No rides yet", icon: "bicycle",
             a11y: zh ? "还没有骑行记录" : "No rides yet") {
            Text(zh ? "先在任意模式里骑一程,这里就会画出你的每日词数、正确率和速度趋势。"
                    : "Ride in any mode and your daily words, accuracy, and speed trends will appear here.")
                .scaledSystemFont(13).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func card<C: View>(_ title: String, icon: String, a11y: String,
                               @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).scaledSystemFont(13, weight: .semibold).foregroundStyle(Theme.accent2)
                    .accessibilityHidden(true)
                Text(title).scaledSystemFont(13, weight: .semibold, design: .rounded).foregroundStyle(Theme.dim)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(a11y)
    }
}
