import SwiftUI
import SceneryKit
import EntitlementKit

/// The road, both journeys of it, and the one place the purchase is offered.
///
/// ## Why the two roads are drawn as two journeys and not one progress bar
///
/// Structurally the paid road is appended to the free one, and a test proves an unentitled rider's
/// experience is identical to v1.29's at 1,167 points. That covers everything a byte can cover and
/// it does not cover the thing most likely to actually hurt.
///
/// Before this release the Tōkaidō was **the** road and 京都 was where it ended. Somebody who rode
/// 48 to 72 rides to get there finished something. Draw the same data as one sixteen-stretch bar
/// and their completed journey silently becomes a half-finished one — nothing removed, and a real
/// loss. There is no telemetry in this app and there will not be, so if that happened nobody would
/// find out; it would arrive, if at all, as the one-star review this product cannot absorb.
///
/// So: 東海道 gets its own section, its own ending, and the word 到達 when it is done. The road
/// west is a **second departure from the same city**, not the back half of the first journey.
/// **This is a judgement, not a measurement.** Nobody has watched a rider react to either layout.
///
/// ## Why the offer lives behind a screen rather than on the row itself
///
/// The placement discipline is Codex's and it is adopted whole: one row, in Settings, no modal, no
/// badge, no post-ride solicitation, and deliberately far from the rating prompt that v1.27
/// already fires after a completed ride. A screen reached BY TAPPING that row is not a second
/// solicitation — it is the product page for the thing the row names, and it is what lets the
/// offer be honest to a rider who is still 20 km short of it being any use to them.
struct RoadView: View {
    @Environment(AppModel.self) private var model
    private var zh: Bool { model.languageCode == "zh" }

    private var entitled: Bool { model.entitlements.isEntitled }
    private var metres: Double { model.lifetimeDistanceMeters }
    private var arrived: Bool { RideRoute.hasArrivedAtKyoto(lifetimeMetres: metres) }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 22) {
            header
            tokaido
            west
            if entitled { owned } else { offer }
            restore
            boundary
            Spacer(minLength: 12)
        }
        .padding(isPhoneIdiom ? 22 : 40)
        .frame(maxWidth: 620, alignment: .leading)

        return Group {
            if Screenshotter.isCapturing { content } else { ScrollView { content } }
        }
        .frame(maxWidth: .infinity)
        // Recorded here, not at the Settings row: this is the moment somebody is actually looking
        // at the offer, and the moment the product either has a price or does not.
        .onAppear { model.recordOfferAppeared() }
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .escape || command == .returnKey { model.showSettings() }
                    },
                    suppressSoftwareKeyboard: true
                )
            }
        }
    }

    // MARK: The two journeys

    private var tokaido: some View {
        card(title: zh ? "東海道 · 日本橋 → 京都" : "The Tōkaidō · Nihonbashi → Kyōto") {
            ForEach(RideRoute.tokaidoStages) { stage in
                stretchRow(stage, reached: metres >= stage.startMetres, locked: false)
            }
            // The free road's own ending, stated as an ending. Never "8 / 16".
            if arrived {
                Text(zh ? "已抵达京都。这条路走完了。" : "Arrived at Kyōto. This road is complete.")
                    .scaledSystemFont(13, weight: .semibold)
                    .foregroundStyle(Theme.accent2)
                    .padding(.top, 2)
            } else {
                Text(remainingToKyoto)
                    .scaledSystemFont(12).foregroundStyle(Theme.dim)
                    .padding(.top, 2)
            }
        }
    }

    private var west: some View {
        card(title: zh ? "西の道 · 京都 → 長崎" : "The Road West · Kyōto → Nagasaki") {
            if !entitled {
                Text(zh ? "京都之后,路继续往西。" : "Past Kyōto, the road goes on west.")
                    .scaledSystemFont(13).foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 2)
            }
            ForEach(RideRoute.westStages) { stage in
                stretchRow(stage, reached: entitled && metres >= stage.startMetres, locked: !entitled)
            }
        }
    }

    /// How far Kyōto still is, in kilometres a rider can check against the Ride Log.
    ///
    /// Distance to the END of the free road, not to the next stretch. The question somebody
    /// reading this screen is asking is *how far away does the thing on offer become useful*, and
    /// answering with the next stretch instead would be a true number to a different question.
    private var remainingToKyoto: String {
        let km = String(format: "%.1f", metresToKyoto / 1000)
        return zh ? "距离京都还有 \(km) 公里。" : "\(km) km still to Kyōto."
    }

    /// A stretch's threshold, in kilometres a rider can compare against the Ride Log.
    ///
    /// One decimal below 10 km, because `Int(400 / 1000)` is 0 and the first render of this screen
    /// showed 川崎 — which begins at 400 m and is the second stretch every rider reaches — labelled
    /// **"0 km"**, directly under 日本橋's "0 km". Two different stretches claiming the same
    /// distance, on the screen whose entire job is to say how far away things are.
    static func distanceLabel(_ metres: Double) -> String {
        let km = metres / 1000
        return km < 10 ? String(format: "%.1f km", km) : "\(Int(km)) km"
    }

    private var metresToKyoto: Double {
        max(0, (RideRoute.tokaidoStages.last?.startMetres ?? 0) - metres)
    }

    private func stretchRow(_ stage: RideStage, reached: Bool, locked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: reached ? "checkmark.circle.fill" : (locked ? "lock" : "circle"))
                .foregroundStyle(reached ? Theme.accent2 : Theme.dim.opacity(locked ? 0.5 : 0.8))
                .scaledSystemFont(13)
            Text(stage.name)
                .scaledSystemFont(15, weight: reached ? .semibold : .regular)
                .foregroundStyle(.white.opacity(reached ? 0.95 : 0.6))
            Text(stage.romaji)
                .scaledSystemFont(12).foregroundStyle(Theme.dim)
            Spacer()
            Text(Self.distanceLabel(stage.startMetres))
                .scaledSystemFont(12, weight: .medium, design: .monospaced)
                .foregroundStyle(Theme.dim)
        }
        // `.accessibilityElement()` defaults to `children: .ignore`, so the trailing distance —
        // the one number this screen exists to state — was dropped from VoiceOver entirely. It
        // goes into the value alongside the state, because a stretch's name without its distance
        // is the half of the row that does not answer anything.
        .accessibilityElement()
        .accessibilityLabel("\(stage.name), \(stage.romaji)")
        .accessibilityValue({
            let state = reached ? (zh ? "已抵达" : "reached")
                : locked ? (zh ? "未解锁" : "locked")
                         : (zh ? "还未抵达" : "not yet reached")
            return "\(Self.distanceLabel(stage.startMetres)), \(state)"
        }())
    }

    // MARK: The offer

    @ViewBuilder private var offer: some View {
        let store = model.entitlements
        card(title: zh ? "开启西の道" : "Open the Road West") {
            // Honest to a rider who has not arrived. Somebody at 3 km can buy this and see nothing
            // change for forty rides; saying so here is the difference between a purchase and a
            // refund, and the plan's whole placement argument assumes the offer explains itself.
            Text(offerBlurb)
                .scaledSystemFont(13).foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            if let product = store.product {
                Button {
                    Task { await model.buyTheRoadWest() }
                } label: {
                    HStack {
                        Text(zh ? "一次性购买" : "One-time purchase")
                            .scaledSystemFont(15, weight: .semibold)
                        Spacer()
                        Text(product.displayPrice)
                            .scaledSystemFont(15, weight: .bold, design: .rounded)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.accent2.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent2.opacity(0.5)))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(store.isPurchasing)
                .accessibilityIdentifier("buyRoadWest")
            } else if store.hasLoaded {
                // The App Store answered and had nothing, or the request failed. Two different
                // stories, and neither is "you already decided" — the counter records this as
                // `offerUnavailable` rather than as an offer nobody took.
                Text(store.loadError == nil
                     ? (zh ? "暂时无法读取价格。稍后再试。" : "Prices are unavailable right now. Try again later.")
                     : (zh ? "连接 App Store 失败。" : "Could not reach the App Store."))
                    .scaledSystemFont(12).foregroundStyle(Theme.accent)
                Button(zh ? "重试" : "Retry") { Task { await store.load() } }
                    .buttonStyle(.plain)
                    .scaledSystemFont(13, weight: .semibold)
                    .foregroundStyle(Theme.accent2)
            } else {
                Text(zh ? "正在读取价格…" : "Loading price…")
                    .scaledSystemFont(12).foregroundStyle(Theme.dim)
            }

            if let notice = store.notice { noticeText(notice) }
        }
    }

    /// What an owner sees where the offer used to be. **Not nothing** — see `restore` below.
    private var owned: some View {
        card(title: zh ? "已开启" : "Opened") {
            // Says only what was sold. The earlier version promised "every route and backdrop
            // added later" here too — see `boundary` for why that came out.
            Text(zh
                 ? "西の道已经开启。谢谢 —— 这条路会一直在。"
                 : "The road west is open. Thank you — it stays open.")
                .scaledSystemFont(13).foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **Always present, owned or not, and that is the whole point.**
    ///
    /// The first version of this screen put Restore inside the offer card, which only rendered
    /// `if !entitled` — so the app had NO restore control at all on a device that owned the SKU.
    /// That is precisely backwards: the person who needs Restore is a buyer on a second device,
    /// or after a reinstall, whose entitlement has not resolved yet. App Review guideline 3.1.1
    /// requires a restore mechanism for non-consumables, and this app's would have been reachable
    /// only by people who had nothing to restore.
    ///
    /// `PaidRouteRowTests.testAnOwnedDeviceStillSeesTheRowAndStillHasRestore` asserts exactly
    /// this — and it was written before the bug and never run, which is how the bug survived.
    /// A test that is never executed is a comment.
    private var restore: some View {
        card(title: zh ? "已经买过?" : "Already bought it?") {
            // "Or a different Apple Account" was here, and it was FALSE: a non-consumable belongs
            // to the Apple Account that bought it, and Restore on another account recovers nothing
            // (Family Sharing aside, which this SKU does not enable). Purchase copy promising
            // something StoreKit cannot do is how a refund and the one negative review §K names as
            // its only stop-and-fix guardrail get manufactured. Says the true thing instead, and
            // names the account requirement rather than leaving somebody to discover it.
            Text(zh
                 ? "换了设备、重装,或者在你的另一台设备上 —— 用这里把它找回来,不会重复扣款。请用当初购买的那个 Apple 账号登录。"
                 : "New device, reinstall, or another of your devices — bring it back here and you will not be charged again. Sign in with the Apple Account that bought it.")
                .scaledSystemFont(12).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button(zh ? "恢复购买" : "Restore Purchases") {
                Task { await model.restorePurchases() }
            }
            .buttonStyle(.plain)
            .scaledSystemFont(14, weight: .semibold)
            .foregroundStyle(Theme.accent2)
            .accessibilityIdentifier("restorePurchases")
        }
    }

    private var offerBlurb: String {
        if arrived {
            return zh
                ? "你已经骑到京都了。这次购买把路接下去 —— 大阪、神户、姬路、冈山、广岛、下关、博多,一直到长崎。"
                : "You have already reached Kyōto. This continues the road — Ōsaka, Kōbe, Himeji, Okayama, Hiroshima, Shimonoseki, Hakata, and on to Nagasaki."
        }
        let km = String(format: "%.1f", max(0, (RideRoute.tokaidoStages.last?.startMetres ?? 0) - metres) / 1000)
        return zh
            ? "西の道从京都开始,你还有 \(km) 公里要骑。买了不会改变东海道 —— 那条路免费,而且是完整的。"
            : "The road west begins at Kyōto, and you are \(km) km from there. Buying it changes nothing about the Tōkaidō — that road is free, and it is complete."
    }

    @ViewBuilder private func noticeText(_ notice: RouteStore.Notice) -> some View {
        let text: String = {
            switch notice {
            case .pending:
                return zh ? "购买待批准。批准后会自动开启。" : "Awaiting approval. The road opens by itself once it is approved."
            case .unverified:
                return zh ? "App Store 无法验证这笔购买,什么都没有开启。如已扣款,请用「恢复购买」。"
                          : "The App Store could not verify that purchase, so nothing was opened. If you were charged, use Restore Purchases."
            case .productMissing:
                return zh ? "价格还没读到。" : "The price had not loaded yet."
            case .failed(let message):
                return message
            }
        }()
        Text(text)
            .scaledSystemFont(12).foregroundStyle(Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// §C required the capability set to be NAMED before the SKU existed. This is where a buyer
    /// reads it, in one sentence, before paying rather than after asking.
    /// **What this says, and why it is narrower than the first draft's.**
    ///
    /// v1.30's first draft sold "scenery and routes — all of them, now and in future", with one
    /// exclusion named to the buyer. Two problems, both found while the SKU still had **zero
    /// customers**, which is the only window in which either could be fixed: widening a promise is
    /// always possible afterwards and narrowing one never is.
    ///
    /// 1. It named two categories of goods where the code has one. `SceneryKit` is two files, a
    ///    palette is a field of a `RideStage`, and the entitlement gates a `[RideStage]` — there is
    ///    no scenery in this app that is not attached to a route. So "scenery", standing alone, was
    ///    an undefined second category that a buyer could reasonably read onto weather, a night
    ///    mode, or a seasonal repaint of stages they already have.
    /// 2. "Now and in future" sells unfinished goods, which §D's own finished-goods rule forbids.
    ///    The two rules could not both be literally true.
    ///
    /// So this names the finished thing: the whole road west, end to end, and that route's scenery.
    /// **"Permanent" now describes the duration of ownership, not an unbounded future catalogue.**
    /// More routes can still be given to these buyers later, and probably will be — a gift keeps
    /// its option value, a promise does not.
    private var boundary: some View {
        Text(zh
             ? "这次购买永久开启完整的西行之路 —— 京都到长崎 —— 以及这条路线的风景。不包含:需要联网的功能(这个 app 完全离线,以后如果做联网玩法,那是另外的东西)、导入你自己的日语材料、以及内容包。"
             : "This purchase permanently opens the complete road west — Kyōto to Nagasaki — and the scenery of that route. It does not cover anything needing a server (this app works fully offline, and a connected mode would be a separate thing), importing your own Japanese, or content packs.")
            .scaledSystemFont(11).foregroundStyle(Theme.dim.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Text(zh ? "路" : "The Road")
                .scaledSystemFont(32, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white)
            Spacer()
            Button(action: model.showSettings) {
                Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                    .scaledSystemFont(14, weight: .semibold)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("roadBackButton")
        }
    }

    private func card(title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .scaledSystemFont(11, weight: .black).tracking(2)
                .foregroundStyle(Theme.accent)
            content()
        }
        .panel()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
