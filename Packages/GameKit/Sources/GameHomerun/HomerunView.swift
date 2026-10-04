import SwiftUI
import Core
import HomerunCore

/// 柵越えおじさん（#1348）の画面。打席・外野は 3D（RealityKit。macOS の `swift test` では 2D の絵に落ちる）。
///
/// 打席前（`36-lobby-3D`）→ 打席（`31-at-bat-3D`）→ 10 球の結果（`34-result-spray`）。
/// バナーは打席前・結果では画面の下、**打席（打球を追うカメラの間も）では画面の上**（#1696・会長指示 2026-10-02。
/// 下 1/3 は押せる帯なので重ねない）。#1348 で打席を無バナーにした方針はここで改めた。
///
/// 時間は Model が「次に起こしてほしい時刻」（`nextWake`）を返し、ここの `.task(id: model.step)` が待つだけ。
/// 輪の大きさは `TimelineView` が時刻から描く（`Timer` は持たない）。
public struct HomerunView: View {
    @State private var model: HomerunModel
    /// 広告を見てプレイ（#1694）の救済。**画面に 1 つだけ**持ち、打席前・結果のボタンへ渡す（ボタンごとに持つと、
    /// 提示の計測（`reward_offer`）と連打ガードが割れ、付与でボタンが消えたときにアラートも一緒に消える）。
    @State private var challengeRescue = RewardedRescue()
    private let services: GameServices
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: HomerunModel(services: services))
    }

    public var body: some View {
        content
            // 打席前 → 打席 → 結果の差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
            .gameAnimation(.easeInOut(duration: 0.2), value: model.phase == .idle)
            // 打席中は左上の戻るを出さない（#1550。誤タップで挑戦が終わらないように。やめるのは一時停止から確認つきで）。
            // 打席中は右上の「?」も出さない（#1617。一時停止の画面に「遊び方」を置き、そこから開く）。
            .gameChrome(title: "柵越えおじさん", review: services.review,
                        hidesBackButton: model.phase == .pitching || model.phase == .ballResult,
                        hidesHowToPlay: model.phase == .pitching || model.phase == .ballResult)
            // 遊び方を読んでいるあいだは投球を止め、閉じたらその球を投げ直す。
            .howToPlay(.homerun, onPresent: { model.hold(.sheet, true, now: Date()) },
                       onDismiss: { model.hold(.sheet, false, now: Date()) }) {
                HomerunRuleSheet()
            }
            // 回数の提示（#780）。使い切ってボタンが出ているあいだを 1 回の提示として数える。
            .rewardOffer(challengeRescue, for: .challenge, isPresented: offersRecovery,
                         services: services, gameID: HomerunModel.gameID)
            .rewardedRescueAlerts(
                challengeRescue,
                notEarned: "広告でプレイできませんでした",
                unavailable: RewardUnavailableAlert(
                    title: "広告でプレイできませんでした",
                    message: "広告を見ているあいだに日付が変わったか、今日の広告でのプレイの上限に達したため、挑戦を始められませんでした。"
                )
            )
            // バックグラウンドでは投球を止め、戻ったらその球をやり直す（台帳は戻さない）。
            // 戻ったときに日付が変わっていれば 0:00 の補充もここで拾う。
            .onChange(of: scenePhase) { _, phase in
                model.hold(.inactive, phase != .active, now: Date())
                if phase == .active { model.refreshDay(now: Date()) }
            }
            // 進行の待ちは Model が決め、ここは待つだけ。進行が変わるたびに `step` が進んで前の待ちが止まる。
            .task(id: model.step) { await runClock() }
            #if os(iOS) && canImport(RealityKit)
            // 打席の 3D は画面の中では使い回し（もう一回で作り直すと前の打席の画のまま止まる・#1594）、離れたら手放す。
            .onDisappear { HomerunAtBatSceneReuse.drop() }
            #endif
    }

    /// 回復のボタンが出ているか（打席前と結果で、残りが 0 のあいだ。上限に達していれば出さない）。
    private var offersRecovery: Bool {
        (model.phase == .idle || model.phase == .finished) && !model.ledger.canStart && model.ledger.canWatchAd
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            HomerunLobbyView(model: model, services: services, challengeRescue: challengeRescue)
                .transition(.opacity)
        case .pitching, .ballResult:
            HomerunAtBatView(model: model, ads: services.ads)
                .transition(.opacity)
        case .finished:
            HomerunResultView(model: model, services: services, challengeRescue: challengeRescue)
                .transition(.opacity)
        }
    }

    /// 同じ `step` のあいだだけ待つ。進行が変わったら新しい `.task` に譲って抜ける。
    private func runClock() async {
        let step = model.step
        while !Task.isCancelled, model.step == step, let wake = model.nextWake {
            let wait = wake.timeIntervalSinceNow
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            guard !Task.isCancelled, model.step == step else { return }
            withGameAnimation(.easeInOut(duration: 0.2)) { model.advance(now: Date()) }
        }
    }
}

/// 下端固定バナーと、スクロールの末尾にある押せる要素との間隔（#1749。AdMob は広告の近くのボタンを誤タップ誘発として扱う）。
/// スクロールし切ったとき、最後の要素の下に `Theme.pad` + これだけの余白が残る（SE でも合計 72pt > バナーの高さ 50pt）。
enum HomerunBannerGap {
    static let belowContent: CGFloat = 56
}

// MARK: - 打席前

struct HomerunLobbyView: View {
    let model: HomerunModel
    let services: GameServices
    let challengeRescue: RewardedRescue

    var body: some View {
        VStack(spacing: 0) {
            lobbyScroll
            BannerSlot(ads: services.ads)
        }
        // Game Center の解除済みを読んで端末の記録と合わせる（連携の有無・通信の有無で一覧は変わらない。読めなければ何もしない）。
        .task { await model.syncGameCenterAchievements() }
        #if os(iOS) && canImport(RealityKit)
        // 打席の 3D を見えない所で先に作っておく（#1695。「打席に立つ」・広告を見てプレイで待たせない）。
        .onAppear { HomerunAtBatScenePrewarm.schedule() }
        #endif
    }

    private var lobbyScroll: some View {
        ScrollView {
            VStack(spacing: 14) {
                introCard
                todayCard
                recordsCard
                HomerunAchievementsCard(model: model)
                Button {
                    withGameAnimation { _ = model.start(now: Date()) }
                } label: {
                    HomerunStartLabel(model: model)
                }
                // 回数 0 では押せない灰色にし、回復までの残りを出す（使い切りのシートは廃止・会長決裁 2026-10-04）。
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(model.ledger.canStart ? Theme.Fill.coral : Theme.inkSub.opacity(0.3))
                .disabled(!model.ledger.canStart)
                .accessibilityHint(model.ledger.canStart ? "挑戦回数を1回使って10球の打席を始めます" : "今日の挑戦は使い切りました")
                if !model.ledger.canStart {
                    HomerunResetCountdown()
                    HomerunRecoveryButton(model: model, services: services, challengeRescue: challengeRescue)
                    if let returnReminder = services.returnReminder {
                        HomerunReturnReminderToggle(service: returnReminder)
                    }
                }
                Text("挑戦回数は打席に立った時点で1つ減ります")
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSub)
                Toggle(isOn: Bindable(model).showsDirectionMeter) {
                    Text("方向メーターを表示").themeBody(14).foregroundStyle(Theme.ink)
                }
                .tint(Theme.coral)
                .accessibilityHint("打席の左上に出る方向メーターの表示を切り替えます。消しても判定は変わりません")
                // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
                HowToPlayHint(.homerun, playLog: services.playLog)
            }
            .padding(Theme.pad)
            .padding(.bottom, HomerunBannerGap.belowContent)
        }
    }

    private var introCard: some View {
        HStack(spacing: 14) {
            HomerunOjisanImageView()
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "1 挑戦 = \(HomerunChallenge.pitchCount) 球")
                    .themeTitle(22)
                    .foregroundStyle(Theme.ink)
                Text("押したまま狙って、離して振る。方向と角度は自分で決める。アウトは無い。")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                HomerunHeroTrialBadge()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .popCard()
    }

    private var todayCard: some View {
        let ledger = model.ledger
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日の挑戦").themeBody(16).foregroundStyle(Theme.ink)
                Spacer()
                Text(verbatim: "残り \(ledger.remaining) / \(ledger.allowance)")
                    .themeBody(16, weight: .heavy)
                    .foregroundStyle(ledger.canStart ? Theme.coral : Theme.inkSub)
            }
            HomerunCountMeter(allowance: ledger.allowance, remaining: ledger.remaining)
                .accessibilityHidden(true)
            Text(ledger.canStart
                 ? "0:00 に \(HomerunLedger.freePerDay) 回に戻ります"
                 : "今日の挑戦は使い切りました。0:00 にまた \(HomerunLedger.freePerDay) 回挑戦できます")
                .themeCaption(12)
                .foregroundStyle(Theme.inkSub)
        }
        .padding(14)
        .popCard()
        .accessibilityElement(children: .combine)
    }

    private var recordsCard: some View {
        let r = model.records
        return VStack(alignment: .leading, spacing: 10) {
            Text("きろく").themeBody(16).foregroundStyle(Theme.ink)
            HStack(alignment: .top) {
                stat("自己ベスト", HomerunText.meters(Double(r.bestTotalTenths) / 10))
                Spacer()
                stat("最長の 1 本", HomerunText.meters(Double(r.longestTenths) / 10))
                Spacer()
                stat("通算 柵越え", "\(r.homers) 本")
            }
            // 実績「月まで飛ばした」（#1680）。出したことがある人にだけ出す（隠し演出なので先に存在を知らせない）。
            if r.moonShots > 0 {
                Label("月まで飛ばした \(r.moonShots) 回", systemImage: "moon.stars.fill")
                    .themeCaption(13)
                    .foregroundStyle(Theme.ink)
                    .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .popCard()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).themeCaption(11).foregroundStyle(Theme.inkSub)
            Text(verbatim: value)
                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 回数の表示

/// 今日の挑戦回数の表示（#1694）。回数ぶんアイコンを並べると、月のご褒美などで回数が増えるたびに固有幅が伸び、
/// 縮められない横並びがカードを押し広げて打席前の全カード（ScrollView の VStack は一番広い子に揃う）が横にはみ出していた。
/// **`maxDots` 個までは点、それを超えたら「×N」の数字**にして、どれだけ増えても幅が一定を超えないようにする。
enum HomerunCountDisplay: Equatable {
    /// 点を `total` 個並べ、先頭の `lit` 個を色付きにする（残り）。
    case dots(total: Int, lit: Int)
    /// アイコン 1 つと「×`remaining`」。
    case number(remaining: Int)

    static let maxDots = 5

    init(allowance: Int, remaining: Int) {
        self = allowance <= Self.maxDots ? .dots(total: max(0, allowance), lit: max(0, remaining))
                                         : .number(remaining: max(0, remaining))
    }
}

struct HomerunCountMeter: View {
    let allowance: Int
    let remaining: Int

    var body: some View {
        switch HomerunCountDisplay(allowance: allowance, remaining: remaining) {
        case .dots(let total, let lit):
            HStack(spacing: 8) {
                ForEach(0..<total, id: \.self) { i in
                    ball(lit: i < lit)
                }
            }
        case .number(let remaining):
            HStack(spacing: 6) {
                ball(lit: remaining > 0)
                Text(verbatim: "×\(remaining)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(remaining > 0 ? Theme.coral : Theme.inkSub)
                    .lineLimit(1)
            }
        }
    }

    private func ball(lit: Bool) -> some View {
        Image(systemName: "baseball.fill")
            .font(.system(size: 20))
            .foregroundStyle(lit ? Theme.coral : Theme.inkSub.opacity(0.35))
    }
}

// MARK: - 10 球の結果

struct HomerunResultView: View {
    let model: HomerunModel
    let services: GameServices
    let challengeRescue: RewardedRescue

    private var balls: [HomerunBattedBall] { model.challenge?.results ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            resultScroll
            BannerSlot(ads: services.ads)
        }
    }

    private var resultScroll: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                HomerunUnlockedCard(items: model.unlockedThisChallenge)
                moonCard
                sprayCard
                breakdownCard
                actions
                if model.ledger.remaining == 0 {
                    HomerunRecoveryButton(model: model, services: services, challengeRescue: challengeRescue)
                }
                // ほかのゲームへのレコメンド（#52）。全ゲームの終局画面に置く約束（GameChromeTests）。
                RecommendationSlot(services: services, isFinished: true)
            }
            .padding(Theme.pad)
            .padding(.bottom, HomerunBannerGap.belowContent)
        }
    }

    private var summaryCard: some View {
        let total = model.challenge?.totalDistance ?? 0
        let homers = model.challenge?.homerCount ?? 0
        return HStack(spacing: 14) {
            HomerunOjisanImageView()
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: model.challenge?.isMoonBroken == true
                     ? "\(balls.count) 球で終了（月が割れた）"
                     : "\(HomerunChallenge.pitchCount) 球の結果").themeCaption(13).foregroundStyle(Theme.inkSub)
                Text(verbatim: HomerunText.meters(total))
                    .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    chip("柵越え \(homers) 本", systemImage: "flag.checkered", fill: Theme.Fill.yellow)
                    if model.isNewBest {
                        chip("ベスト更新！", systemImage: nil, fill: Theme.Fill.pink)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .popCard()
        .accessibilityElement(children: .combine)
    }

    /// 月まで飛んだ（#1680）挑戦だけに出す。距離は 384,400 km と出し（合計・自己ベストには 180m で数えてある）、月が割れたら
    /// 挑戦の終わりとプレイ回数 +2 を知らせる。打球の分布（`sprayCard`）とは別のカード。
    @ViewBuilder private var moonCard: some View {
        if let challenge = model.challenge, challenge.moonCount > 0 {
            HStack(spacing: 12) {
                Image(systemName: challenge.isMoonBroken ? "moon.circle.fill" : "moon.stars.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.isMoonBroken ? "月が割れた！" : "月まで飛んだ！")
                        .themeBody(16, weight: .heavy).foregroundStyle(Theme.ink)
                    Text(verbatim: HomerunText.moonDistance)
                        .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    if challenge.isMoonBroken {
                        Text("挑戦はここで終わり。プレイ回数 +\(HomerunLedger.moonBonus) をプレゼント")
                            .themeCaption(12).foregroundStyle(Theme.coral)
                    } else {
                        Text("記録には 180 m として数えます").themeCaption(11).foregroundStyle(Theme.inkSub)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .popCard()
            .accessibilityElement(children: .combine)
        }
    }

    private func chip(_ text: String, systemImage: String?, fill: Color) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(verbatim: text)
        }
        .themeCaption(12)
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(fill))
    }

    private var sprayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("どこへ飛んだか").themeBody(16).foregroundStyle(Theme.ink)
            HomerunSprayChart(balls: balls)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.35, contentMode: .fit)
                .accessibilityElement()
                .accessibilityLabel("打球の分布。" + HomerunText.spraySummary(balls))
            Text(verbatim: HomerunText.spraySummary(balls))
                .themeCaption(12)
                .foregroundStyle(Theme.ink)
            Text("★ 柵越え　● 当たり（赤は直撃）　F ファウル　× 空振り")
                .themeCaption(10)
                .foregroundStyle(Theme.inkSub)
                .accessibilityHidden(true)
        }
        .padding(14)
        .popCard()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1 球ずつ").themeBody(16).foregroundStyle(Theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(Array(balls.enumerated()), id: \.offset) { index, ball in
                    HomerunBallTile(ball: ball)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(HomerunText.spoken(ball, number: index + 1))
                }
            }
            if let longest = balls.enumerated().max(by: { $0.element.distance < $1.element.distance }),
               longest.element.distance > 0 {
                Text(verbatim: "最長 \(HomerunText.distance(of: longest.element))（\(longest.offset + 1) 球目・\(HomerunText.place(longest.element))・\(HomerunText.timing(longest.element.timing))）")
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .padding(14)
        .popCard()
    }

    private var actions: some View {
        let ledger = model.ledger
        let remaining = ledger.remaining
        return HStack(spacing: 10) {
            // 回数が尽きて広告でプレイできるときは、このボタンは出さず下の「広告を見てプレイ」に任せる（#1694）。
            if !ledger.canPlayWithAd {
                Button {
                    withGameAnimation { _ = model.start(now: Date()) }
                } label: {
                    Label(remaining > 0 ? "もう一回（残り \(remaining)）" : "今日はおしまい",
                          systemImage: "arrow.counterclockwise")
                        .themeBody(16)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                // 「今日はおしまい」は押しても何も起きない（使い切りのシートは廃止・会長決裁 2026-10-04）。
                .disabled(remaining == 0)
            }
            Button {
                withGameAnimation { model.backToLobby() }
            } label: {
                Text("打席前へ").themeBody(16).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(Theme.coral)
        }
    }
}

/// 1 球ずつの内訳の 1 マス。
struct HomerunBallTile: View {
    let ball: HomerunBattedBall

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
            Text(verbatim: ball.distance > 0 ? HomerunText.distance(of: ball) : HomerunText.kind(ball.kind))
                .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: HomerunText.place(ball))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall)
            .fill(ball.kind == .homer ? Theme.Fill.yellow.opacity(0.25) : Theme.fillMuted.opacity(0.12)))
    }

    private var icon: String {
        if ball.isMoon { return "moon.fill" }
        return switch ball.kind {
        case .homer: "star.fill"
        case .miss: "xmark"
        case .foul: "f.cursive"
        case .inPlay, .fenceHit: "baseball.fill"
        }
    }

    private var iconColor: Color {
        switch ball.kind {
        case .homer: Theme.yellow
        case .fenceHit: Theme.coral
        case .inPlay: Theme.teal
        case .foul, .miss: Theme.inkSub
        }
    }
}

// MARK: - 回数 0 の打席前（回復までの残り・戻ったら知らせる）

/// 「打席に立つ」の中身。回数 0 のときは押せない灰色のボタンになり、回復（0:00）までの残りを読み上げにも含める
/// （会長決裁 2026-10-04。以前は押すと使い切りのシートが出ていた）。残りの文字はボタンのすぐ下（`HomerunResetCountdown`）に
/// 出す。ボタンの中にも置いて比べたが、押せない灰色の上の小さな灰色の文字は読みにくかった。
struct HomerunStartLabel: View {
    let model: HomerunModel

    var body: some View {
        if model.ledger.canStart {
            Label("打席に立つ", systemImage: "figure.baseball")
                .themeBody(18)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Theme.onAccent)
        } else {
            // 残りは分単位の表示なので、1 分ごとに描き直す（端末の時刻・タイムゾーンで 0:00 を数える）。
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = HomerunReturnPolicy.remainingText(from: context.date, calendar: .current)
                Label("打席に立つ", systemImage: "figure.baseball")
                    .themeBody(18)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.inkSub)
                // 押せないボタンでも、VoiceOver で残りが分かるように（下の残りの文字は読み上げから外している）。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "打席に立つ。\(remaining)"))
            }
            // 画面を開いたまま 0:00 を越えたら、その場で回数を戻す（ボタンが押せる色に戻る）。
            .task(id: model.ledger.dayKey) {
                let reset = HomerunReturnPolicy.nextReset(after: Date(), calendar: .current)
                do { try await Task.sleep(for: .seconds(max(0, reset.timeIntervalSinceNow) + 1)) } catch { return }
                model.refreshDay(now: Date())
            }
        }
    }
}

/// 回復までの残り（`HomerunReturnPolicy.remainingText`）。押せない「打席に立つ」のすぐ下に出す。読み上げはボタン側で済ませる。
struct HomerunResetCountdown: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(verbatim: HomerunReturnPolicy.remainingText(from: context.date, calendar: .current))
                .themeBody(15, weight: .heavy)
                .foregroundStyle(Theme.coral)
        }
        .accessibilityHidden(true)
    }
}

/// 「戻ったら知らせる」（#1576）。回数 0 の打席前に出す（以前は使い切りのシートの中）。
/// 既定オフで、オンにした 1 回だけ翌 0:00 過ぎの通知を予約する。予約の有無は OS が持つので、
/// 出るたびに予約済みかを読み直してトグルに反映する。
struct HomerunReturnReminderToggle: View {
    let service: ChallengeReturnReminderService

    @State private var notifiesOnReturn = false
    @State private var reminderNote: String?
    /// ユーザーが触ったか。出た直後の「予約済みか」の読み直しが、先に押された操作を上書きしないための印。
    @State private var touchedReminder = false

    var body: some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(get: { notifiesOnReturn }, set: { setReminder($0, service) })) {
                Text("戻ったら知らせる").themeBody(14).foregroundStyle(Theme.ink)
            }
            .tint(Theme.coral)
            .disabled(!service.isNotificationsEnabled)
            if let note = service.isNotificationsEnabled ? reminderNote : "設定の「通知」をオンにすると使えます。" {
                Text(note).themeCaption(12).foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            let pending = await service.pendingFireDate()
            guard !touchedReminder else { return }
            notifiesOnReturn = HomerunReturnPolicy.isReminderActive(pendingFireDate: pending, now: Date())
        }
    }

    private func setReminder(_ on: Bool, _ service: ChallengeReturnReminderService) {
        reminderNote = nil
        touchedReminder = true
        guard on else {
            notifiesOnReturn = false
            service.cancel()
            return
        }
        notifiesOnReturn = true
        Task {
            let content = HomerunReturnPolicy.notificationContent
            let fireDate = HomerunReturnPolicy.reminderFireDate(after: Date(), calendar: .current)
            switch await service.enable(fireDate: fireDate, title: content.title, body: content.body) {
            case .scheduled:
                break
            case .superseded:
                // トグルをオフにした（または設定で通知をオフにした）操作が先に届いている。表示も合わせる。
                notifiesOnReturn = false
            case .notificationsOff:
                notifiesOnReturn = false
                reminderNote = "設定の「通知」をオンにすると使えます。"
            case .denied:
                notifiesOnReturn = false
                reminderNote = "端末の設定で通知が許可されていません。"
            case .expired:
                notifiesOnReturn = false
                reminderNote = "回数が戻りました。"
            }
        }
    }
}

// MARK: - 広告を見てプレイ

/// 回数を使い切ったあとの「広告を見てプレイ」（#1694・README §3.4）。1 日の上限は `HomerunLedger.adLimitPerDay`。
/// **見終えたらその場で 1 挑戦を始めて打席へ入る**（回数は増やさない・貯められない）。必ずユーザーのタップで出す（自動再生しない）。
///
/// 打席前と結果に同じものを置く（**広告の呼び出しはここ 1 か所**）。救済（`RewardedRescue`）・提示の計測・失敗の
/// アラートは `HomerunView` が 1 つ持つ。広告を出す前に「今日」の鍵を時計から控え、視聴中に 0:00 をまたいだら
/// 始めない（前の日の広告で今日の挑戦を始めない）。見なかった・読み込めなかったときは始めない（`RewardedRescue` の失敗の知らせ）。
struct HomerunRecoveryButton: View {
    let model: HomerunModel
    let services: GameServices
    let challengeRescue: RewardedRescue
    @State private var showsSurvey = false
    @State private var surveyNotApplied = false
    /// 適用できなかった知らせは、シートが閉じ終わってから出す（閉じる最中に同じ親からアラートを出すと iOS が無視する）。
    @State private var surveyFailedOnSubmit = false
    /// アンケートを開いた時点の「今日」の鍵（時計から作る。回答中に 0:00 をまたいだら適用しない）。
    @State private var surveyDay = 0

    var body: some View {
        let ledger = model.ledger
        VStack(spacing: 6) {
            if ledger.canPlayWithAd {
                Button {
                    let day = model.dayKey(at: Date())
                    challengeRescue.request(
                        services, gameID: HomerunModel.gameID, purpose: .challenge,
                        guardedBy: .checkedByGrant
                    ) {
                        // 見終えたら確認を挟まずに打席へ（会長指示 2026-10-02）。
                        withGameAnimation(.easeInOut(duration: 0.2)) { model.startWithAd(forDay: day, now: Date()) }
                    }
                } label: {
                    Label("広告を見てプレイ", systemImage: "play.rectangle.fill")
                        .themeBody(16)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(challengeRescue.isWatching ? Theme.inkSub : Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(challengeRescue.isWatching ? Theme.inkSub.opacity(0.3) : Theme.Fill.teal)
                .disabled(challengeRescue.isWatching)
            } else if !ledger.canWatchAd {
                // 上限の本数は画面に出さない（会長決裁 2026-10-02）。達したときだけ知らせる。
                Text("今日はここまで。0:00 に \(HomerunLedger.freePerDay) 回に戻ります")
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSub)
            }
            if HomerunSurvey.isOffered && ledger.canDoSurvey { surveyButton }
        }
        .sheet(isPresented: $showsSurvey, onDismiss: {
            if surveyFailedOnSubmit { surveyFailedOnSubmit = false; surveyNotApplied = true }
        }) {
            HomerunSurveySheet { answers in
                let applied = model.submitSurvey(answers, forDay: surveyDay, now: Date())
                showsSurvey = false
                surveyFailedOnSubmit = !applied
            }
        }
        .alert("挑戦回数を増やせませんでした", isPresented: $surveyNotApplied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("回答しているあいだに日付が変わったため、回数を増やせませんでした。")
        }
    }

    private var surveyButton: some View {
        VStack(spacing: 6) {
            Button {
                surveyDay = model.dayKey(at: Date())
                showsSurvey = true
            } label: {
                Label("アンケートに答えて挑戦 +1 回", systemImage: "list.bullet.clipboard")
                    .themeBody(16)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(Theme.Fill.teal)
            Text(verbatim: "3 問・選ぶだけ・1 日 1 回")
                .themeCaption(11)
                .foregroundStyle(Theme.inkSub)
        }
    }
}

// MARK: - アンケートで挑戦回数 +1

/// 3 問を選ぶだけのアンケート（README §3.4）。全問に答えると送信でき、閉じるだけでは回数は増えない。
/// 回答は `onSubmit` が Model へ渡すだけで、この画面には残さない。
struct HomerunSurveySheet: View {
    let onSubmit: ([Int]) -> Void
    @State private var answers: [Int?] = Array(repeating: nil, count: HomerunSurvey.questions.count)
    @Environment(\.dismiss) private var dismiss

    private var complete: [Int]? {
        let picked = answers.compactMap { $0 }
        return picked.count == answers.count ? picked : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("答えると今日の挑戦が 1 回増えます。回答は選んだ番号だけを送り、あなたを特定する情報は含みません。")
                        .themeCaption(12)
                        .foregroundStyle(Theme.inkSub)
                    ForEach(Array(HomerunSurvey.questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: "Q\(index + 1). \(question.prompt)")
                                .themeBody(16, weight: .heavy)
                                .foregroundStyle(Theme.ink)
                            ForEach(Array(question.choices.enumerated()), id: \.offset) { choice, label in
                                let selected = answers[index] == choice + 1
                                Button { answers[index] = choice + 1 } label: {
                                    HStack {
                                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                        Text(label).themeBody(15)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .foregroundStyle(selected ? Theme.coral : Theme.ink)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                    Button {
                        if let picked = complete { onSubmit(picked) }
                    } label: {
                        Text("送信して挑戦 +1 回").themeBody(17).frame(maxWidth: .infinity)
                            .foregroundStyle(complete == nil ? Theme.inkSub : Theme.onAccent)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                    .disabled(complete == nil)
                }
                .padding(Theme.pad)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("アンケート")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }
}

// MARK: - くわしいルール

struct HomerunRuleSheet: View {
    static let rules: [(String, String)] = [
        ("流れ", "1回の挑戦は10球。アウトは無く、10球を必ず投げ切ります。空振り・ファウルは距離0として残ります"),
        ("押す", "画面の下のほう（打席の下 1/3）を押します。押しただけでは振りません。投球の前から押していてもかまいません"),
        ("ずらす", "押したままずらすと、水色のミートカーソルが指の動いたぶんだけ動きます。カーソルは球ごとにゾーンの真ん中へ戻ります"),
        ("離す", "縮む輪が白い的に重なった瞬間に離すとスイング。ぴったりほど遠くへ飛びます（ジャスト・ナイス・当たり）"),
        ("角度", "カーソルがボールより上だとゴロ、真ん中だとライナー、少し下だと柵越えの出やすいフライ、下すぎるとポップフライ"),
        ("方向", "カーソルを左に置くと左へ、右に置くと右へ。早く振ると左、遅く振ると右にも寄ります。寄せすぎるとファウル"),
        ("柵", "両翼 100 m・中堅 122 m。左右へ引っ張ると柵は近いけれどファウルになりやすく、センターは遠いけれどファウルが無い"),
        ("回数", "挑戦は1日3回。打席に立った時点で1回減り、途中でやめても戻りません。0:00 に3回に戻ります。使い切ったあとは、広告を見るとその場で1回挑戦できます"),
    ]

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
