import Testing
@testable import ConjugationKit

/// Gate-0 layer-(i) golden (PLAN-V1.6 §2 轨B): 68 curated N5–N3 core verbs, one
/// row per real vocab entry, asserting the engine's output for every supported form
/// against INDEPENDENTLY-derived ground truth. The expected kana were produced by a
/// 3-pass independent grammar derivation with a unanimous majority vote (NOT by running
/// this engine), so a match is a genuine cross-check rather than a tautology. This is the
/// correctness gate that decides Workstream B enters v1.6; it does NOT depend on the B1
/// data writeback (that path has its own layer-(ii) golden).
@Suite("ConjugationKit — N5–N3 core-set golden (Gate-0)")
struct ConjugatorCoreSetGoldenTests {

    private struct Row {
        let kana: String, surface: String, cls: VerbClass
        let polite, te, past, negative, pastNegative, potential, volitional: String
    }

    // Verified ground truth — 3 independent grammar passes, 0 conflicts (unanimous).
    private static let rows: [Row] = [
        Row(kana: "みる", surface: "見る", cls: .ichidan, polite: "みます", te: "みて", past: "みた", negative: "みない", pastNegative: "みなかった", potential: "みられる", volitional: "みよう"),
        Row(kana: "たべる", surface: "食べる", cls: .ichidan, polite: "たべます", te: "たべて", past: "たべた", negative: "たべない", pastNegative: "たべなかった", potential: "たべられる", volitional: "たべよう"),
        Row(kana: "おきる", surface: "起きる", cls: .ichidan, polite: "おきます", te: "おきて", past: "おきた", negative: "おきない", pastNegative: "おきなかった", potential: "おきられる", volitional: "おきよう"),
        Row(kana: "ねる", surface: "寝る", cls: .ichidan, polite: "ねます", te: "ねて", past: "ねた", negative: "ねない", pastNegative: "ねなかった", potential: "ねられる", volitional: "ねよう"),
        Row(kana: "おしえる", surface: "教える", cls: .ichidan, polite: "おしえます", te: "おしえて", past: "おしえた", negative: "おしえない", pastNegative: "おしえなかった", potential: "おしえられる", volitional: "おしえよう"),
        Row(kana: "おぼえる", surface: "覚える", cls: .ichidan, polite: "おぼえます", te: "おぼえて", past: "おぼえた", negative: "おぼえない", pastNegative: "おぼえなかった", potential: "おぼえられる", volitional: "おぼえよう"),
        Row(kana: "でる", surface: "出る", cls: .ichidan, polite: "でます", te: "でて", past: "でた", negative: "でない", pastNegative: "でなかった", potential: "でられる", volitional: "でよう"),
        Row(kana: "かりる", surface: "借りる", cls: .ichidan, polite: "かります", te: "かりて", past: "かりた", negative: "かりない", pastNegative: "かりなかった", potential: "かりられる", volitional: "かりよう"),
        Row(kana: "おりる", surface: "降りる", cls: .ichidan, polite: "おります", te: "おりて", past: "おりた", negative: "おりない", pastNegative: "おりなかった", potential: "おりられる", volitional: "おりよう"),
        Row(kana: "つづける", surface: "続ける", cls: .ichidan, polite: "つづけます", te: "つづけて", past: "つづけた", negative: "つづけない", pastNegative: "つづけなかった", potential: "つづけられる", volitional: "つづけよう"),
        Row(kana: "あつめる", surface: "集める", cls: .ichidan, polite: "あつめます", te: "あつめて", past: "あつめた", negative: "あつめない", pastNegative: "あつめなかった", potential: "あつめられる", volitional: "あつめよう"),
        Row(kana: "かう", surface: "買う", cls: .godanU, polite: "かいます", te: "かって", past: "かった", negative: "かわない", pastNegative: "かわなかった", potential: "かえる", volitional: "かおう"),
        Row(kana: "あう", surface: "会う", cls: .godanU, polite: "あいます", te: "あって", past: "あった", negative: "あわない", pastNegative: "あわなかった", potential: "あえる", volitional: "あおう"),
        Row(kana: "つかう", surface: "使う", cls: .godanU, polite: "つかいます", te: "つかって", past: "つかった", negative: "つかわない", pastNegative: "つかわなかった", potential: "つかえる", volitional: "つかおう"),
        Row(kana: "うたう", surface: "歌う", cls: .godanU, polite: "うたいます", te: "うたって", past: "うたった", negative: "うたわない", pastNegative: "うたわなかった", potential: "うたえる", volitional: "うたおう"),
        Row(kana: "ならう", surface: "習う", cls: .godanU, polite: "ならいます", te: "ならって", past: "ならった", negative: "ならわない", pastNegative: "ならわなかった", potential: "ならえる", volitional: "ならおう"),
        Row(kana: "あらう", surface: "洗う", cls: .godanU, polite: "あらいます", te: "あらって", past: "あらった", negative: "あらわない", pastNegative: "あらわなかった", potential: "あらえる", volitional: "あらおう"),
        Row(kana: "てつだう", surface: "手伝う", cls: .godanU, polite: "てつだいます", te: "てつだって", past: "てつだった", negative: "てつだわない", pastNegative: "てつだわなかった", potential: "てつだえる", volitional: "てつだおう"),
        Row(kana: "かく", surface: "書く", cls: .godanK, polite: "かきます", te: "かいて", past: "かいた", negative: "かかない", pastNegative: "かかなかった", potential: "かける", volitional: "かこう"),
        Row(kana: "きく", surface: "聞く", cls: .godanK, polite: "ききます", te: "きいて", past: "きいた", negative: "きかない", pastNegative: "きかなかった", potential: "きける", volitional: "きこう"),
        Row(kana: "あるく", surface: "歩く", cls: .godanK, polite: "あるきます", te: "あるいて", past: "あるいた", negative: "あるかない", pastNegative: "あるかなかった", potential: "あるける", volitional: "あるこう"),
        Row(kana: "はたらく", surface: "働く", cls: .godanK, polite: "はたらきます", te: "はたらいて", past: "はたらいた", negative: "はたらかない", pastNegative: "はたらかなかった", potential: "はたらける", volitional: "はたらこう"),
        Row(kana: "なく", surface: "泣く", cls: .godanK, polite: "なきます", te: "ないて", past: "ないた", negative: "なかない", pastNegative: "なかなかった", potential: "なける", volitional: "なこう"),
        Row(kana: "とどく", surface: "届く", cls: .godanK, polite: "とどきます", te: "とどいて", past: "とどいた", negative: "とどかない", pastNegative: "とどかなかった", potential: "とどける", volitional: "とどこう"),
        Row(kana: "およぐ", surface: "泳ぐ", cls: .godanG, polite: "およぎます", te: "およいで", past: "およいだ", negative: "およがない", pastNegative: "およがなかった", potential: "およげる", volitional: "およごう"),
        Row(kana: "いそぐ", surface: "急ぐ", cls: .godanG, polite: "いそぎます", te: "いそいで", past: "いそいだ", negative: "いそがない", pastNegative: "いそがなかった", potential: "いそげる", volitional: "いそごう"),
        Row(kana: "ぬぐ", surface: "脱ぐ", cls: .godanG, polite: "ぬぎます", te: "ぬいで", past: "ぬいだ", negative: "ぬがない", pastNegative: "ぬがなかった", potential: "ぬげる", volitional: "ぬごう"),
        Row(kana: "はなす", surface: "話す", cls: .godanS, polite: "はなします", te: "はなして", past: "はなした", negative: "はなさない", pastNegative: "はなさなかった", potential: "はなせる", volitional: "はなそう"),
        Row(kana: "かえす", surface: "返す", cls: .godanS, polite: "かえします", te: "かえして", past: "かえした", negative: "かえさない", pastNegative: "かえさなかった", potential: "かえせる", volitional: "かえそう"),
        Row(kana: "かす", surface: "貸す", cls: .godanS, polite: "かします", te: "かして", past: "かした", negative: "かさない", pastNegative: "かさなかった", potential: "かせる", volitional: "かそう"),
        Row(kana: "おす", surface: "押す", cls: .godanS, polite: "おします", te: "おして", past: "おした", negative: "おさない", pastNegative: "おさなかった", potential: "おせる", volitional: "おそう"),
        Row(kana: "けす", surface: "消す", cls: .godanS, polite: "けします", te: "けして", past: "けした", negative: "けさない", pastNegative: "けさなかった", potential: "けせる", volitional: "けそう"),
        Row(kana: "だす", surface: "出す", cls: .godanS, polite: "だします", te: "だして", past: "だした", negative: "ださない", pastNegative: "ださなかった", potential: "だせる", volitional: "だそう"),
        Row(kana: "わたす", surface: "渡す", cls: .godanS, polite: "わたします", te: "わたして", past: "わたした", negative: "わたさない", pastNegative: "わたさなかった", potential: "わたせる", volitional: "わたそう"),
        Row(kana: "まつ", surface: "待つ", cls: .godanT, polite: "まちます", te: "まって", past: "まった", negative: "またない", pastNegative: "またなかった", potential: "まてる", volitional: "まとう"),
        Row(kana: "もつ", surface: "持つ", cls: .godanT, polite: "もちます", te: "もって", past: "もった", negative: "もたない", pastNegative: "もたなかった", potential: "もてる", volitional: "もとう"),
        Row(kana: "たつ", surface: "立つ", cls: .godanT, polite: "たちます", te: "たって", past: "たった", negative: "たたない", pastNegative: "たたなかった", potential: "たてる", volitional: "たとう"),
        Row(kana: "かつ", surface: "勝つ", cls: .godanT, polite: "かちます", te: "かって", past: "かった", negative: "かたない", pastNegative: "かたなかった", potential: "かてる", volitional: "かとう"),
        Row(kana: "しぬ", surface: "死ぬ", cls: .godanN, polite: "しにます", te: "しんで", past: "しんだ", negative: "しなない", pastNegative: "しななかった", potential: "しねる", volitional: "しのう"),
        Row(kana: "あそぶ", surface: "遊ぶ", cls: .godanB, polite: "あそびます", te: "あそんで", past: "あそんだ", negative: "あそばない", pastNegative: "あそばなかった", potential: "あそべる", volitional: "あそぼう"),
        Row(kana: "よぶ", surface: "呼ぶ", cls: .godanB, polite: "よびます", te: "よんで", past: "よんだ", negative: "よばない", pastNegative: "よばなかった", potential: "よべる", volitional: "よぼう"),
        Row(kana: "とぶ", surface: "飛ぶ", cls: .godanB, polite: "とびます", te: "とんで", past: "とんだ", negative: "とばない", pastNegative: "とばなかった", potential: "とべる", volitional: "とぼう"),
        Row(kana: "はこぶ", surface: "運ぶ", cls: .godanB, polite: "はこびます", te: "はこんで", past: "はこんだ", negative: "はこばない", pastNegative: "はこばなかった", potential: "はこべる", volitional: "はこぼう"),
        Row(kana: "えらぶ", surface: "選ぶ", cls: .godanB, polite: "えらびます", te: "えらんで", past: "えらんだ", negative: "えらばない", pastNegative: "えらばなかった", potential: "えらべる", volitional: "えらぼう"),
        Row(kana: "のむ", surface: "飲む", cls: .godanM, polite: "のみます", te: "のんで", past: "のんだ", negative: "のまない", pastNegative: "のまなかった", potential: "のめる", volitional: "のもう"),
        Row(kana: "よむ", surface: "読む", cls: .godanM, polite: "よみます", te: "よんで", past: "よんだ", negative: "よまない", pastNegative: "よまなかった", potential: "よめる", volitional: "よもう"),
        Row(kana: "やすむ", surface: "休む", cls: .godanM, polite: "やすみます", te: "やすんで", past: "やすんだ", negative: "やすまない", pastNegative: "やすまなかった", potential: "やすめる", volitional: "やすもう"),
        Row(kana: "たのむ", surface: "頼む", cls: .godanM, polite: "たのみます", te: "たのんで", past: "たのんだ", negative: "たのまない", pastNegative: "たのまなかった", potential: "たのめる", volitional: "たのもう"),
        Row(kana: "かむ", surface: "噛む", cls: .godanM, polite: "かみます", te: "かんで", past: "かんだ", negative: "かまない", pastNegative: "かまなかった", potential: "かめる", volitional: "かもう"),
        Row(kana: "こむ", surface: "込む", cls: .godanM, polite: "こみます", te: "こんで", past: "こんだ", negative: "こまない", pastNegative: "こまなかった", potential: "こめる", volitional: "こもう"),
        Row(kana: "かえる", surface: "帰る", cls: .godanR, polite: "かえります", te: "かえって", past: "かえった", negative: "かえらない", pastNegative: "かえらなかった", potential: "かえれる", volitional: "かえろう"),
        Row(kana: "つくる", surface: "作る", cls: .godanR, polite: "つくります", te: "つくって", past: "つくった", negative: "つくらない", pastNegative: "つくらなかった", potential: "つくれる", volitional: "つくろう"),
        Row(kana: "とる", surface: "取る", cls: .godanR, polite: "とります", te: "とって", past: "とった", negative: "とらない", pastNegative: "とらなかった", potential: "とれる", volitional: "とろう"),
        Row(kana: "うる", surface: "売る", cls: .godanR, polite: "うります", te: "うって", past: "うった", negative: "うらない", pastNegative: "うらなかった", potential: "うれる", volitional: "うろう"),
        Row(kana: "はいる", surface: "入る", cls: .godanR, polite: "はいります", te: "はいって", past: "はいった", negative: "はいらない", pastNegative: "はいらなかった", potential: "はいれる", volitional: "はいろう"),
        Row(kana: "しる", surface: "知る", cls: .godanR, polite: "しります", te: "しって", past: "しった", negative: "しらない", pastNegative: "しらなかった", potential: "しれる", volitional: "しろう"),
        Row(kana: "はしる", surface: "走る", cls: .godanR, polite: "はしります", te: "はしって", past: "はしった", negative: "はしらない", pastNegative: "はしらなかった", potential: "はしれる", volitional: "はしろう"),
        Row(kana: "すわる", surface: "座る", cls: .godanR, polite: "すわります", te: "すわって", past: "すわった", negative: "すわらない", pastNegative: "すわらなかった", potential: "すわれる", volitional: "すわろう"),
        Row(kana: "きる", surface: "切る", cls: .godanR, polite: "きります", te: "きって", past: "きった", negative: "きらない", pastNegative: "きらなかった", potential: "きれる", volitional: "きろう"),
        Row(kana: "べんきょうする", surface: "勉強", cls: .suru, polite: "べんきょうします", te: "べんきょうして", past: "べんきょうした", negative: "べんきょうしない", pastNegative: "べんきょうしなかった", potential: "べんきょうできる", volitional: "べんきょうしよう"),
        Row(kana: "そうじする", surface: "掃除", cls: .suru, polite: "そうじします", te: "そうじして", past: "そうじした", negative: "そうじしない", pastNegative: "そうじしなかった", potential: "そうじできる", volitional: "そうじしよう"),
        Row(kana: "さんぽする", surface: "散歩", cls: .suru, polite: "さんぽします", te: "さんぽして", past: "さんぽした", negative: "さんぽしない", pastNegative: "さんぽしなかった", potential: "さんぽできる", volitional: "さんぽしよう"),
        Row(kana: "れんしゅうする", surface: "練習", cls: .suru, polite: "れんしゅうします", te: "れんしゅうして", past: "れんしゅうした", negative: "れんしゅうしない", pastNegative: "れんしゅうしなかった", potential: "れんしゅうできる", volitional: "れんしゅうしよう"),
        Row(kana: "りょうり", surface: "料理", cls: .suru, polite: "りょうりします", te: "りょうりして", past: "りょうりした", negative: "りょうりしない", pastNegative: "りょうりしなかった", potential: "りょうりできる", volitional: "りょうりしよう"),
        Row(kana: "けっこん", surface: "結婚", cls: .suru, polite: "けっこんします", te: "けっこんして", past: "けっこんした", negative: "けっこんしない", pastNegative: "けっこんしなかった", potential: "けっこんできる", volitional: "けっこんしよう"),
        Row(kana: "りょこう", surface: "旅行", cls: .suru, polite: "りょこうします", te: "りょこうして", past: "りょこうした", negative: "りょこうしない", pastNegative: "りょこうしなかった", potential: "りょこうできる", volitional: "りょこうしよう"),
        Row(kana: "うんどう", surface: "運動", cls: .suru, polite: "うんどうします", te: "うんどうして", past: "うんどうした", negative: "うんどうしない", pastNegative: "うんどうしなかった", potential: "うんどうできる", volitional: "うんどうしよう"),
        Row(kana: "くる", surface: "来る", cls: .kuru, polite: "きます", te: "きて", past: "きた", negative: "こない", pastNegative: "こなかった", potential: "こられる", volitional: "こよう"),
    ]

    @Test("every core verb conjugates exactly to verified ground truth")
    func coreSet() {
        for r in Self.rows {
            let expect: [ConjugationForm: String] = [
                .polite: r.polite, .te: r.te, .past: r.past, .negative: r.negative,
                .pastNegative: r.pastNegative, .potential: r.potential, .volitional: r.volitional,
            ]
            for (form, want) in expect {
                let got = Conjugator.conjugate(kana: r.kana, verbClass: r.cls, form: form)
                #expect(got == want, "\(r.surface)(\(r.kana)) \(form.rawValue): got \(got ?? "nil"), want \(want)")
            }
        }
    }

    @Test("core-set spans every VerbClass and is sized as the gate expects")
    func coverage() {
        let classes = Set(Self.rows.map { $0.cls })
        #expect(classes.count == VerbClass.allCases.count)   // all 12 classes represented
        #expect(Self.rows.count >= 60)                        // ~68 curated core verbs
    }
}
