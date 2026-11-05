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
    /// 週間ランキング（#1792）: 結果の演出のあとに挟むページを見終えたか。次の挑戦の開始で戻す。
    @State private var rankingSeen = false
    /// 結果ページの「今週のランキング」から開き直しているか。
    @State private var rankingReopened = false
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
            .gameChrome(title: tr("柵越えおじさん"), review: services.review,
                        hidesBackButton: model.phase == .pitching || model.phase == .ballResult || model.phase == .finale,
                        hidesHowToPlay: model.phase == .pitching || model.phase == .ballResult || model.phase == .finale)
            // 遊び方を読んでいるあいだは投球を止め、閉じたらその球を投げ直す。
            .howToPlay(HowToPlayGuide.homerun.illustrated(HomerunHowToFigures.items).onboarding(HomerunOnboarding.guide), onPresent: { model.hold(.sheet, true, now: Date()) },
                       onDismiss: { model.hold(.sheet, false, now: Date()) }) {
                HomerunRuleSheet()
            }
            // 回数の提示（#780）。使い切ってボタンが出ているあいだを 1 回の提示として数える。
            .rewardOffer(challengeRescue, for: .challenge, isPresented: offersRecovery,
                         services: services, gameID: HomerunModel.gameID)
            .rewardedRescueAlerts(
                challengeRescue,
                notEarned: tr("広告でプレイできませんでした"),
                unavailable: RewardUnavailableAlert(
                    title: tr("広告でプレイできませんでした"),
                    message: tr("広告を見ているあいだに日付が変わったか、今日の広告でのプレイの上限に達したため、挑戦を始められませんでした。")
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
            .onChange(of: model.phase) { _, phase in
                if phase == .pitching || phase == .idle { rankingSeen = false; rankingReopened = false }
            }
            // 場面の効果音（打ち出し・カキーン・歓声・月が割れる等）。鳴らす時刻は演出と同じ式から決める（`HomerunSoundCues`）。
            .modifier(HomerunSoundPlayer(model: model, service: services.homerunSound, haptics: services.haptics))
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
        case .finale:
            // 10 球（または月が割れて）終わったら、結果画面の前に結果の演出を挟む（会長決裁 2026-10-05）。打席の上へ重ねると
            // 透けるうえ、打席のバナーが演出の裏で覆われる（Google の Content obscuring に当たる）ので、結果と同じく
            // 画面ごと差し替える（#1818）。打席が外れるのでバナーも階層から無くなる。
            HomerunFinaleView(model: model)
                .gameNavigationBarBackgroundHidden()
                .transition(.opacity)
        case .finished:
            if (model.weekly.showsAfterFinale && !rankingSeen) || rankingReopened {
                rankingPage
                    .transition(.opacity)
            } else {
                HomerunResultView(model: model, services: services, challengeRescue: challengeRescue,
                                  onOpenRanking: { withGameAnimation { rankingReopened = true } })
                    .transition(.opacity)
            }
        }
    }

    /// 今週のランキング（#1792）。結果の演出のあと（サインイン済みの人だけ）と、結果ページの行から開いたとき。
    /// 演出のあとの最初の 1 回だけ入れ替えアニメを流し、開き直しは静止の表を出す。
    @ViewBuilder private var rankingPage: some View {
        let next = { withGameAnimation { rankingSeen = true; rankingReopened = false } }
        let title = rankingReopened ? tr("結果に戻る") : tr("結果を見る")
        HomerunWeeklyRankingScreen(state: model.weekly, animates: !rankingReopened, nextTitle: title, onNext: next,
                                   ads: services.ads)
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
    /// 結果画面と打席前は、ボタン欄と下の 300×250 を少し近づける（会長指示 2026-10-05・打席前は 2026-10-06 に同じ値へ）。
    static let belowResultActions: CGFloat = 40
}

// MARK: - 打席前

struct HomerunLobbyView: View {
    let model: HomerunModel
    let services: GameServices
    let challengeRescue: RewardedRescue
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // 「打席に立つ」（回数 0 なら広告を見てプレイも）の置き方は `HomerunActionLayout.lobby`（会長指示 2026-10-04）。
        // 結果画面と同じく、中身 → ボタン → 300×250 を 1 本のスクロールに並べる（会長決裁 2026-10-06・#1819）。
        HomerunActionScroll(placement: HomerunActionLayout.lobby, bannerGap: HomerunBannerGap.belowResultActions) {
            lobbyContent
        } actions: {
            startActions
        } footer: {
            MediumRectangleSlot(ads: services.ads)
        }
        // Game Center の解除済みを読んで端末の記録と合わせる（連携の有無・通信の有無で一覧は変わらない。読めなければ何もしない）。
        .task { await model.syncGameCenterAchievements() }
        // 今週の順位（#2216）は打席前に出るたび・アプリに戻るたびに読み直す（挑戦のあとの順位・週の切り替わりを拾う）。
        .onAppear { model.refreshLobbyWeekly() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshLobbyWeekly() }
        }
        #if os(iOS) && canImport(RealityKit)
        // 打席の 3D を見えない所で先に作っておく（#1695。「打席に立つ」・広告を見てプレイで待たせない）。
        .onAppear { HomerunAtBatScenePrewarm.schedule() }
        #endif
    }

    private var lobbyContent: some View {
        VStack(spacing: 14) {
            introCard
            // 今週の順位（#2216）。結果のあとと同じランキングページを開く。
            HomerunLobbyRankRow(model: model, ads: services.ads)
                .modifier(HomerunWeekEndRefresh(model: model))
            // 回数 0 の「戻ったら知らせる」はスクロールの中の上の方（SE でも送らずに見える位置）。
            if !model.ledger.canStart, let returnReminder = services.returnReminder {
                HomerunReturnReminderToggle(service: returnReminder)
            }
            // 記録と実績は別ページ（会長指示 2026-10-04）。ここは「記録と実績 ›」の 1 行だけ（きろくのカードも置かない）。
            HomerunRecordsLink(model: model, ads: services.ads)
            Text(tr("挑戦回数は打席に立った時点で1つ減ります"))
                .themeCaption(11)
                .foregroundStyle(Theme.inkSubText)
            Toggle(isOn: Bindable(model).showsDirectionMeter) {
                Text(tr("方向メーターを表示")).themeBody(14).foregroundStyle(Theme.ink)
            }
            .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）
            .accessibilityHint(tr("打席の左上に出る方向メーターの表示を切り替えます。消しても判定は変わりません"))
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.homerun, playLog: services.playLog)
        }
    }

    /// ボタン欄の中身。今日の残り回数はボタンの中のボールで見せる（「今日の挑戦」のカードは廃止・会長指示 2026-10-04）。
    /// 回数 0 では押せない灰色にし、すぐ下に回復までの残りを出す（使い切りのシートは廃止・会長決裁 2026-10-04）。
    @ViewBuilder private var startActions: some View {
        HomerunStartButton(model: model, title: tr("打席に立つ"))
        if !model.ledger.canStart {
            HomerunRecoveryButton(model: model, services: services, challengeRescue: challengeRescue)
        }
    }

    private var introCard: some View {
        HStack(spacing: 14) {
            HomerunOjisanImageView()
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: tr("1 挑戦 = %lld 球", HomerunChallenge.pitchCount))
                    .themeTitle(22)
                    .foregroundStyle(Theme.ink)
                Text(tr("押したまま狙って、離して振る。方向と角度は自分で決める。アウトは無い。"))
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSubText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .popCard()
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
    /// 残りのボールの色と、使ったボールの色（「打席に立つ」の中では白と薄い色）。
    var lit: Color = Theme.coralText
    var unlit: Color = Theme.inkSub.opacity(0.35)

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
                    .scaledFont(20, weight: .heavy, design: .rounded).monospacedDigit()
                    .foregroundStyle(remaining > 0 ? lit : unlit)
                    .lineLimit(1)
            }
        }
    }

    private func ball(lit isLit: Bool) -> some View {
        Image(systemName: "baseball.fill")
            .scaledFont(20)
            .foregroundStyle(isLit ? lit : unlit)
    }
}

// MARK: - 10 球の結果

struct HomerunResultView: View {
    let model: HomerunModel
    let services: GameServices
    let challengeRescue: RewardedRescue
    /// 結果ページの「今週のランキング」の行を押したとき（#1792）。
    let onOpenRanking: () -> Void

    private var balls: [HomerunBattedBall] { model.challenge?.results ?? [] }

    var body: some View {
        // 次の挑戦のボタンの置き方は `HomerunActionLayout.result`（会長指示 2026-10-04）。下に固定はやめ、
        // 中身 → ボタン → 300×250 を 1 本のスクロールに並べる（会長決定 2026-10-05）。
        HomerunActionScroll(placement: HomerunActionLayout.result, bannerGap: HomerunBannerGap.belowResultActions) {
            resultContent
        } actions: {
            actions
        } footer: {
            MediumRectangleSlot(ads: services.ads)
        }
    }

    private var resultContent: some View {
        VStack(spacing: 14) {
            summaryCard
            rankingRow
            HomerunUnlockedCard(items: model.unlockedThisChallenge)
            moonCard
            breakdownCard
            sprayCard
            // ほかのゲームへのレコメンド（#52）。全ゲームの終局画面に置く約束（GameChromeTests）。
            RecommendationSlot(services: services, isFinished: true)
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
                     ? tr("%lld 球で終了（月が割れた）", balls.count)
                     : tr("%lld 球の結果", HomerunChallenge.pitchCount)).themeCaption(13).foregroundStyle(Theme.inkSubText)
                Text(verbatim: HomerunText.meters(total))
                    .scaledFont(44, weight: .black, design: .rounded, maxScale: 1.2).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    chip(tr("柵越え %lld 本", homers), systemImage: "flag.checkered", fill: Theme.Fill.yellow)
                    if model.isNewBest {
                        chip(tr("自己ベスト更新！"), systemImage: nil, fill: Theme.Fill.pink)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .popCard()
        .accessibilityElement(children: .combine)
    }

    /// 今週のランキングの 1 行（#1792）。ランクインしたことと順位だけを知らせ、表は別のページで見せる（会長決定 2026-10-09）。
    /// 未サインインでは「登録すると見られます」の案内ページへ。送り先が未作成、または順位を読めていないときは出さない。
    @ViewBuilder private var rankingRow: some View {
        switch model.weekly {
        case .signedOut:
            rankingButton(detail: tr("Game Center に登録すると見られます"), delta: nil)
        case .ready(let before, let after):
            if let rank = after.myRank {
                let up = HomerunRankingPlan.motion(before: before, after: after).map { $0.from + 1 - ($0.to + 1) }
                rankingButton(detail: tr("%lld位にランクイン", rank), delta: up)
            }
        case .off, .loading, .failed:
            EmptyView()
        }
    }

    private func rankingButton(detail: String, delta: Int?) -> some View {
        Button(action: onOpenRanking) {
            HStack(spacing: 8) {
                Label(tr("今週のランキング"), systemImage: "trophy.fill").themeBody(16).foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                Text(verbatim: detail).themeBody(14, weight: .heavy).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
                if let delta, delta > 0 { ChipText(text: "↑ \(delta)", fill: Theme.Fill.pink) }
                DisclosureChevron()
            }
            .padding(14)
            .frame(minHeight: 44)
            .popCard()
        }
        .buttonStyle(.pop)
    }

    /// 月まで飛んだ（#1680）挑戦だけに出す。距離は 384,400 km と出し（合計・自己ベストには 180m で数えてある）、月が割れたら
    /// 挑戦の終わりとプレイ回数 +1 を知らせる。打球の分布（`sprayCard`）とは別のカード。
    @ViewBuilder private var moonCard: some View {
        if let challenge = model.challenge, challenge.moonCount > 0 {
            HStack(spacing: 12) {
                Image(systemName: challenge.isMoonBroken ? "moon.circle.fill" : "moon.stars.fill")
                    .scaledFont(34, weight: .bold, maxScale: 1.2)
                    .foregroundStyle(Theme.yellowText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.isMoonBroken ? tr("月が割れた！") : tr("月まで飛んだ！"))
                        .themeBody(16, weight: .heavy).foregroundStyle(Theme.ink)
                    Text(verbatim: HomerunText.moonDistance)
                        .scaledFont(26, weight: .black, design: .rounded).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    if challenge.isMoonBroken {
                        Text(tr("挑戦はここで終わり。プレイ回数 +%lld をプレゼント", HomerunLedger.moonBonus))
                            .themeCaption(12).foregroundStyle(Theme.coralText)
                    } else {
                        Text(tr("記録には 180 m として数えます")).themeCaption(11).foregroundStyle(Theme.inkSubText)
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
            Text(tr("どこへ飛んだか")).themeBody(16).foregroundStyle(Theme.ink)
            HomerunSprayChart(balls: balls)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.35, contentMode: .fit)
                .accessibilityElement()
                .accessibilityLabel(tr("打球の分布。%@", HomerunText.spraySummary(balls)))
            Text(verbatim: HomerunText.spraySummary(balls))
                .themeCaption(12)
                .foregroundStyle(Theme.ink)
            Text(tr("★ 柵越え　● 当たり（赤は直撃）　F ファウル　× 空振り"))
                .themeCaption(10)
                .foregroundStyle(Theme.inkSubText)
                .accessibilityHidden(true)
        }
        .padding(14)
        .popCard()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("1 球ずつ")).themeBody(16).foregroundStyle(Theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(Array(balls.enumerated()), id: \.offset) { index, ball in
                    HomerunBallTile(ball: ball)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(HomerunText.spoken(ball, number: index + 1))
                }
            }
            if let longest = balls.enumerated().max(by: { $0.element.distance < $1.element.distance }),
               longest.element.distance > 0 {
                Text(verbatim: tr("最長 %1$@（%2$lld 球目・%3$@・%4$@）", HomerunText.distance(of: longest.element), longest.offset + 1,
                                   HomerunText.place(longest.element), HomerunText.timing(longest.element.timing)))
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .padding(14)
        .popCard()
    }

    /// ボタン欄の中身。主ボタンが上の縦並び（会長指示 2026-10-04）。「もう一回」は打席前の「打席に立つ」と同じ部品
    /// （ボタンの中に残り回数のボール）。回数 0 では「もう一回」を出さず（会長指示 2026-10-05）、広告を見てプレイ
    /// （上限に達しても「今日はここまで」は出さない・会長決定 2026-10-05）とその下に「あと◯時間◯分で無料枠が戻ります」、
    /// いちばん下が打席前へ。
    @ViewBuilder private var actions: some View {
        if model.ledger.canStart {
            HomerunStartButton(model: model, title: tr("もう一回"))
        } else {
            // 自己ベストまであと少しのときだけ、広告を見てプレイの上に差を出す（#2724）。
            if model.ledger.canPlayWithAd, let meters = HomerunRecoveryHint.metersToBest(
                totalTenths: Int(((model.challenge?.totalDistance ?? 0) * 10).rounded()),
                bestTenths: model.records.bestTotalTenths, isNewBest: model.isNewBest) {
                Text(tr("あと %@ で自己ベスト", HomerunText.meters(Double(meters))))
                    .themeBody(15, weight: .heavy)
                    .foregroundStyle(Theme.coralText)
            }
            HomerunRecoveryButton(model: model, services: services, challengeRescue: challengeRescue,
                                  showsLimitNotice: false)
            HomerunResetCountdown(freePlays: true, readsAloud: true)
                // 結果画面には `HomerunStartLabel` の更新が無いので、開いたまま 0:00 を越えたらここで回数を戻す。
                .task(id: model.ledger.dayKey) {
                    model.refreshDay(now: Date())
                    let reset = HomerunReturnPolicy.nextReset(after: Date(), calendar: .current)
                    do { try await Task.sleep(for: .seconds(max(0, reset.timeIntervalSinceNow) + 1)) } catch { return }
                    model.refreshDay(now: Date())
                }
        }
        Button {
            withGameAnimation { model.backToLobby() }
        } label: {
            Text(tr("打席前へ")).themeBody(16).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.large).tint(Theme.coralText)
    }
}

/// 打席前・結果のボタン欄の置き方（会長指示 2026-10-04。画面ごとに `HomerunActionLayout` で選ぶ）。
enum HomerunActionPlacement: Equatable {
    /// 下に固定: バナーの上に固定し、スクロールの中身はその上（送り切ると中身の末尾が欄のすぐ上で止まる）。
    case pinned
    /// 中身のすぐ下: スクロールの中身の最後に続けて置く。
    case inline
    /// 自動: 中身がスクロールするほど長いなら下に固定、画面に収まるなら中身のすぐ下。
    case auto
}

/// 画面ごとのボタン欄の置き方。**会長が画面ごとに決める設定値はここだけ**（会長指示 2026-10-04）。
enum HomerunActionLayout {
    /// 打席前（打席に立つ／回数 0 なら広告を見てプレイ）。結果と同じく 1 本のスクロールに（会長決裁 2026-10-06・#1819）。
    static let lobby: HomerunActionPlacement = .inline
    /// 結果（もう一回／回数 0 なら広告を見てプレイ／打席前へ）。中身・ボタン・広告を 1 本のスクロールに（会長決定 2026-10-05）。
    static let result: HomerunActionPlacement = .inline
}

/// スクロールする中身と、その下のボタン欄。置き方は `placement` で切り替える。ボタンとバナーの間は、どの置き方でも
/// 欄の中で `Theme.pad + HomerunBannerGap.belowContent` 空ける（#1749）。
struct HomerunActionScroll<Content: View, Actions: View, Footer: View>: View {
    let placement: HomerunActionPlacement
    /// ボタン欄の下に足す、広告との間隔。
    let bannerGap: CGFloat
    let content: Content
    let actions: Actions
    /// 中身のすぐ下（`.inline`）のとき、ボタン欄の下に続けて同じスクロールに載せるもの（結果画面の 300×250・会長指示 2026-10-05）。
    let footer: Footer

    init(placement: HomerunActionPlacement, bannerGap: CGFloat = HomerunBannerGap.belowContent,
         @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions, @ViewBuilder footer: () -> Footer) {
        self.placement = placement
        self.bannerGap = bannerGap
        self.content = content()
        self.actions = actions()
        self.footer = footer()
    }

    var body: some View {
        switch placement {
        case .pinned:
            pinned
        case .inline:
            // 画面全体を 1 本のスクロールにする（中身 → ボタン欄 → `footer`）。
            ScrollView {
                VStack(spacing: 0) {
                    inline
                    footer
                }
            }
        case .auto:
            // 中身＋欄がそのまま収まれば中身のすぐ下、収まらなければ下に固定（文字の大きさ・端末の高さで自動で切り替わる）。
            ViewThatFits(in: .vertical) {
                inline
                pinned
            }
            // 収まったときは上に詰める（バナーとの間に空きが出ても、欄は中身のすぐ下）。
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var inline: some View {
        VStack(spacing: 0) {
            content.padding([.horizontal, .top], Theme.pad)
            actionBlock
        }
    }

    private var pinned: some View {
        ScrollView { content.padding(Theme.pad) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBlock
                    .background(Theme.background)
                    // 境目: スクロールする中身が欄の手前でなじむよう、上に短いぼかしを重ねる（押せる範囲は増やさない）。
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 14)
                            .offset(y: -14)
                            .allowsHitTesting(false)
                    }
            }
    }

    private var actionBlock: some View {
        VStack(spacing: 10) { actions }
            .padding(Theme.pad)
            .padding(.bottom, bannerGap)
            .frame(maxWidth: .infinity)
    }
}

extension HomerunActionScroll where Footer == EmptyView {
    init(placement: HomerunActionPlacement, bannerGap: CGFloat = HomerunBannerGap.belowContent,
         @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.init(placement: placement, bannerGap: bannerGap, content: content, actions: actions, footer: { EmptyView() })
    }
}

/// 1 球ずつの内訳の 1 マス。
struct HomerunBallTile: View {
    let ball: HomerunBattedBall

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .scaledFont(14, weight: .bold)
                .foregroundStyle(iconColor)
            Text(verbatim: ball.distance > 0 ? HomerunText.distance(of: ball) : HomerunText.kind(ball.kind))
                .scaledFont(13, weight: .heavy, design: .rounded).monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: HomerunText.place(ball))
                .scaledFont(10, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
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
        case .homer: Theme.yellowText
        case .fenceHit: Theme.coralText
        case .inPlay: Theme.tealText
        case .foul, .miss: Theme.inkSubText
        }
    }
}

// MARK: - 回数 0 の打席前（回復までの残り・戻ったら知らせる）

/// 1 挑戦を始めるボタン。打席前の「打席に立つ」と結果の「もう一回」で**同じ部品**を使い、文言だけ変える（会長指示 2026-10-04）。
/// 回数 0 では押せない灰色にし、すぐ下に回復までの残り（`HomerunResetCountdown`）を出す（使い切りのシートは廃止）。
struct HomerunStartButton: View {
    let model: HomerunModel
    let title: String

    var body: some View {
        let canStart = model.ledger.canStart
        Button {
            withGameAnimation { _ = model.start(now: Date()) }
        } label: {
            HomerunStartLabel(model: model, title: title)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .tint(canStart ? Theme.Fill.coral : Theme.inkSub.opacity(0.3))
        .disabled(!canStart)
        .accessibilityHint(canStart ? tr("挑戦回数を1回使って10球の打席を始めます") : tr("今日の挑戦は使い切りました"))
        if !canStart {
            HomerunResetCountdown()
        }
    }
}

/// 「打席に立つ」「もう一回」の中身。残り回数をボールで並べる。回数 0 のときは押せない灰色のボタンになり、回復（0:00）までの
/// 残りを読み上げにも含める（会長決裁 2026-10-04）。残りの文字はボタンのすぐ下（`HomerunResetCountdown`）に出す。
/// ボタンの中にも置いて比べたが、押せない灰色の上の小さな灰色の文字は読みにくかった。
struct HomerunStartLabel: View {
    let model: HomerunModel
    let title: String

    var body: some View {
        let ledger = model.ledger
        if ledger.canStart {
            HStack(spacing: 12) {
                Label(title, systemImage: "figure.baseball")
                    .themeBody(18)
                    .foregroundStyle(Theme.onAccent)
                // 今日の残り回数（残りだけ白いボール）。「今日の挑戦」のカードの代わり（会長指示 2026-10-04）。
                HomerunCountMeter(allowance: ledger.allowance, remaining: ledger.remaining,
                                  lit: .white, unlit: Theme.onAccent.opacity(0.25))
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: tr("%@。今日の残り %lld 回", title, ledger.remaining)))
        } else {
            // 残りは分単位の表示なので、1 分ごとに描き直す（端末の時刻・タイムゾーンで 0:00 を数える）。
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = HomerunReturnPolicy.remainingText(from: context.date, calendar: .current)
                HStack(spacing: 12) {
                    Label(title, systemImage: "figure.baseball")
                        .themeBody(18)
                    HomerunCountMeter(allowance: ledger.allowance, remaining: 0,
                                      lit: Theme.inkSub, unlit: Theme.inkSub.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Theme.inkSubText)
                // 押せないボタンでも、VoiceOver で残りが分かるように（下の残りの文字は読み上げから外している）。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: tr("%1$@。%2$@", title, remaining)))
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
/// 結果画面では「広告を見てプレイ」の下に「あと◯時間◯分で無料枠が戻ります」で出す（`freePlays`・会長指示 2026-10-05）。
/// 結果画面には読み上げを済ませるボタンが無いので、ここで読み上げる（`readsAloud`）。
struct HomerunResetCountdown: View {
    var freePlays = false
    var readsAloud = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(verbatim: HomerunReturnPolicy.remainingText(from: context.date, calendar: .current,
                                                             freePlays: freePlays))
                .themeBody(15, weight: .heavy)
                .foregroundStyle(Theme.coralText)
        }
        .accessibilityHidden(!readsAloud)
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
                Text(tr("戻ったら知らせる")).themeBody(14).foregroundStyle(Theme.ink)
            }
            .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）
            .disabled(!service.isNotificationsEnabled)
            if let note = service.isNotificationsEnabled ? reminderNote : tr("設定の「通知」をオンにすると使えます。") {
                Text(note).themeCaption(12).foregroundStyle(Theme.inkSubText)
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
                reminderNote = tr("設定の「通知」をオンにすると使えます。")
            case .denied:
                notifiesOnReturn = false
                reminderNote = tr("端末の設定で通知が許可されていません。")
            case .expired:
                notifiesOnReturn = false
                reminderNote = tr("回数が戻りました。")
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
    /// 広告でのプレイの上限に達したとき「今日はここまで…」を出すか。結果画面は下に「あと◯時間◯分で無料枠が戻ります」が
    /// あるので出さない（会長決定 2026-10-05）。
    var showsLimitNotice = true

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
                    Label(tr("広告を見てプレイ"), systemImage: "play.rectangle.fill")
                        .themeBody(16)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(challengeRescue.isWatching ? Theme.inkSubText : Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(challengeRescue.isWatching ? Theme.inkSub.opacity(0.3) : Theme.Fill.teal)
                .disabled(challengeRescue.isWatching)
            } else if !ledger.canWatchAd && showsLimitNotice {
                // 上限の本数は画面に出さない（会長決裁 2026-10-02）。達したときだけ知らせる。
                Text(tr("今日はここまで。0:00 に %lld 回に戻ります", HomerunLedger.freePerDay))
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
    }
}

// MARK: - くわしいルール

struct HomerunRuleSheet: View {
    static var rules: [(String, String)] { [
        (tr("流れ"), tr("1回の挑戦は10球。アウトは無く、10球を必ず投げ切ります。空振り・ファウルは距離0として残ります")),
        (tr("押す"), tr("画面の下のほう（打席の下 1/3）を押します。押しただけでは振りません。投球の前から押していてもかまいません")),
        (tr("ずらす"), tr("押したままずらすと、水色のミートカーソルが指の動いたぶんだけ動きます。カーソルは球ごとにゾーンの真ん中へ戻ります")),
        (tr("離す"), tr("縮む輪が白い的に重なった瞬間に離すとスイング。ぴったりほど遠くへ飛びます（ジャスト・ナイス・当たり）")),
        (tr("角度"), tr("カーソルがボールより上だとゴロ、真ん中だとライナー、少し下だと柵越えの出やすいフライ、下すぎるとポップフライ")),
        (tr("方向"), tr("カーソルを左に置くと左へ、右に置くと右へ。早く振ると左、遅く振ると右にも寄ります。寄せすぎるとファウル")),
        (tr("柵"), tr("両翼 100 m・中堅 122 m。左右へ引っ張ると柵は近いけれどファウルになりやすく、センターは遠いけれどファウルが無い")),
        (tr("回数"), tr("挑戦は1日3回。打席に立った時点で1回減り、途中でやめても戻りません。0:00 に3回に戻ります。使い切ったあとは、広告を見るとその場で1回挑戦できます")),
    ] }

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
