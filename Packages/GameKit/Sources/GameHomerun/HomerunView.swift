import SwiftUI
import Core
import HomerunCore

/// 柵越えおじさん（#1348）の画面。段 3 = 2D の仮絵で一回遊べる形（3D は後続の段）。
///
/// 打席前（`36-lobby-3D`）→ 打席（`31-at-bat-3D`・全画面でバナー無し）→ 10 球の結果（`34-result-spray`）。
/// **バナーはどの画面にも出さない**（打席・外野は無バナーが受け入れ条件。打席前・結果のバナーは広告を
/// 接続する段 4 で足す）。
///
/// 時間は Model が「次に起こしてほしい時刻」（`nextWake`）を返し、ここの `.task(id: model.step)` が待つだけ。
/// 輪の大きさは `TimelineView` が時刻から描く（`Timer` は持たない）。
public struct HomerunView: View {
    @State private var model: HomerunModel
    private let services: GameServices
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: HomerunModel())
    }

    public var body: some View {
        content
            // 打席前 → 打席 → 結果の差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
            .gameAnimation(.easeInOut(duration: 0.2), value: model.phase == .idle)
            .gameChrome(title: "柵越えおじさん", review: services.review)
            // 遊び方を読んでいるあいだは投球を止め、閉じたらその球を投げ直す。
            .howToPlay(.homerun, onPresent: { model.hold(.sheet, true, now: Date()) },
                       onDismiss: { model.hold(.sheet, false, now: Date()) }) {
                HomerunRuleSheet()
            }
            .sheet(isPresented: Bindable(model).showsExhausted) {
                HomerunExhaustedSheet { model.showsExhausted = false }
                    .presentationDetents([.medium])
            }
            // バックグラウンドでは投球を止め、戻ったらその球をやり直す（台帳は戻さない）。
            // 戻ったときに日付が変わっていれば 0:00 の補充もここで拾う。
            .onChange(of: scenePhase) { _, phase in
                model.hold(.inactive, phase != .active, now: Date())
                if phase == .active { model.refreshDay(now: Date()) }
            }
            // 進行の待ちは Model が決め、ここは待つだけ。進行が変わるたびに `step` が進んで前の待ちが止まる。
            .task(id: model.step) { await runClock() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            HomerunLobbyView(model: model, services: services)
                .transition(.opacity)
        case .pitching, .ballResult:
            HomerunAtBatView(model: model)
                .transition(.opacity)
        case .finished:
            HomerunResultView(model: model, services: services)
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

// MARK: - 打席前

struct HomerunLobbyView: View {
    let model: HomerunModel
    let services: GameServices

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                introCard
                todayCard
                recordsCard
                Button {
                    withGameAnimation { model.start(now: Date()) }
                } label: {
                    Label("打席に立つ", systemImage: "figure.baseball")
                        .themeBody(18)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                .accessibilityHint(model.ledger.canStart ? "挑戦回数を1回使って10球の打席を始めます" : "今日の挑戦は使い切りました")
                Text("挑戦回数は打席に立った時点で1つ減ります")
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSub)
                // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
                HowToPlayHint(.homerun, playLog: services.playLog)
            }
            .padding(Theme.pad)
        }
    }

    private var introCard: some View {
        HStack(spacing: 14) {
            OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "1 挑戦 = \(HomerunChallenge.pitchCount) 球")
                    .themeTitle(22)
                    .foregroundStyle(Theme.ink)
                Text("押したまま狙って、離して振る。方向と角度は自分で決める。アウトは無い。")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                Label("体験版", systemImage: "sparkles")
                    .themeCaption(12)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Fill.purple))
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
            HStack(spacing: 8) {
                ForEach(0..<ledger.allowance, id: \.self) { i in
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(i < ledger.remaining ? Theme.coral : Theme.inkSub.opacity(0.35))
                }
            }
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

// MARK: - 10 球の結果

struct HomerunResultView: View {
    let model: HomerunModel
    let services: GameServices

    private var balls: [HomerunBattedBall] { model.challenge?.results ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                sprayCard
                breakdownCard
                actions
                // ほかのゲームへのレコメンド（#52）。全ゲームの終局画面に置く約束（GameChromeTests）。
                RecommendationSlot(services: services, isFinished: true)
            }
            .padding(Theme.pad)
        }
    }

    private var summaryCard: some View {
        let total = model.challenge?.totalDistance ?? 0
        let homers = model.challenge?.homerCount ?? 0
        return HStack(spacing: 14) {
            OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(HomerunChallenge.pitchCount) 球の結果").themeCaption(13).foregroundStyle(Theme.inkSub)
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
                Text(verbatim: "最長 \(HomerunText.meters(longest.element.distance))（\(longest.offset + 1) 球目・\(HomerunText.place(longest.element))・\(HomerunText.timing(longest.element.timing))）")
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .padding(14)
        .popCard()
    }

    private var actions: some View {
        let remaining = model.ledger.remaining
        return HStack(spacing: 10) {
            Button {
                withGameAnimation { model.start(now: Date()) }
            } label: {
                Label(remaining > 0 ? "もう一回（残り \(remaining)）" : "今日はおしまい",
                      systemImage: "arrow.counterclockwise")
                    .themeBody(16)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
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
            Text(verbatim: ball.distance > 0 ? HomerunText.meters(ball.distance) : HomerunText.kind(ball.kind))
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
        switch ball.kind {
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

// MARK: - 使い切りシート

/// 残り 0 で打席に立とうとしたときのシート。広告・アンケートでの回復は段 4 で接続する（いまはボタンを出さない）。
struct HomerunExhaustedSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.purple)
                .accessibilityHidden(true)
            Text("今日の挑戦は使い切りました").themeBody(19, weight: .heavy).foregroundStyle(Theme.ink)
            Text("明日また挑戦できます（0:00 に \(HomerunLedger.freePerDay) 回に戻ります）。")
                .themeBody(14)
                .foregroundStyle(Theme.inkSub)
                .multilineTextAlignment(.center)
            Button(action: onClose) {
                Text("閉じる").themeBody(16).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(Theme.coral)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
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
        ("回数", "挑戦は1日3回。打席に立った時点で1回減り、途中でやめても戻りません。0:00 に3回に戻ります"),
    ]

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
