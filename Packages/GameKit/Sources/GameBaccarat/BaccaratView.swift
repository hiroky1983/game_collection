import SwiftUI
import Core

public struct BaccaratView: View {
    @State private var model: BaccaratModel
    private let services: GameServices
    /// チップ切れ復活のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var reviveRescue = RewardedRescue()

    // ベット選択肢。先頭は破産判定の境目（`BaccaratModel.minimumBet`）と必ず同じ額にする
    // ——ここだけ動かすと「全ボタンが無効なのに破産にならない」残高が生まれる（#656）。
    private let betOptions = [BaccaratModel.minimumBet, 100, 200, 500]

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: BaccaratModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 10) {
            chipsBar
            // 配牌前は両者の手札が空で、テーブルを出すと白い空箱が画面の大半を占める。
            // 賭け方を示す 1 枚のカードに差し替え、配牌後に本来のテーブルへ切り替える。
            if isBeforeDeal {
                Spacer(minLength: 0)
                preDealTable
                Spacer(minLength: 0)
            } else {
                handArea(.player)
                Spacer(minLength: 4)
                handArea(.banker)
            }
            HowToPlayHint(.baccarat, playLog: services.playLog)
            if model.sessionOver {
                sessionOverView
            } else {
                actionArea
            }
            RecommendationSlot(services: services, isFinished: model.phase == .result || model.sessionOver)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .gameChrome(title: "バカラ", review: services.review)
        .howToPlay(.baccarat)
        .rewardedRescueAlerts(
            reviveRescue,
            notEarned: "チップは回復しませんでした",
            unavailable: RewardUnavailableAlert(
                title: "チップは回復しませんでした",
                message: "広告を見ているあいだにセッションが変わったため、復活は適用していません。復活の回数は減っていません。"
            )
        )
    }

    // MARK: - Chips Bar

    private var chipsBar: some View {
        HStack {
            Label("チップ: \(model.chips)枚", systemImage: "circle.hexagongrid.fill")
                .themeBody(14)
                .foregroundStyle(Theme.ink)
            Spacer()
            if model.bet > 0 {
                Label("ベット: \(model.bet)枚", systemImage: "dollarsign.circle.fill")
                    .themeBody(14)
                    .foregroundStyle(Theme.yellow)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Pre-deal Table

    /// 手札が両者とも空で、これから賭ける局面か
    private var isBeforeDeal: Bool {
        model.phase == .betting && model.playerHand.isEmpty && model.bankerHand.isEmpty
    }

    private var preDealTable: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                BaccaratCardPlaceholder()
                BaccaratCardPlaceholder()
            }
            VStack(spacing: 6) {
                Text("賭け先とベット額を選ぶとカードが配られます")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("合計の下 1 桁が 9 に近いほうが勝ち。引き足しは自動です。")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 18)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Hands

    /// プレイヤー／バンカーの手 1 つぶん。`side` に `.tie` は渡さない。
    private func handArea(_ side: BaccaratBet) -> some View {
        let isBanker = side == .banker
        let hand = isBanker ? model.bankerHand : model.playerHand
        let total = isBanker ? model.bankerTotal : model.playerTotal
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(side.label)
                    .themeBody(13)
                    .foregroundStyle(model.selectedBet == side ? Theme.ink : Theme.inkSub)
                // 賭けている先は枠の色だけでなく文字でも示す（色覚に依存させない）。
                // 賭ける前・決着後のどちらでも読める語にする（「賭けた」だと賭け待ちで過去形になる）。
                if model.selectedBet == side {
                    Text("ベット先")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Fill.teal))
                }
                Spacer(minLength: 0)
                if !hand.isEmpty {
                    Text("\(total)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(isBanker ? Theme.purple : Theme.teal)
                        .accessibilityLabel(BaccaratAccessibility.totalLabel(side: side, total: total))
                }
                // 勝敗バッジはフェードで出す（#209）。`.gameAnimation` はこの ZStack にだけ置く
                // （合計の入れ替えまで animate されると決着の瞬間に行が伸び縮みする）。
                ZStack {
                    if let outcome = model.outcome, outcomeBadgeText(outcome, for: side) != nil {
                        outcomeBadge(outcome, for: side)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .gameAnimation(BaccaratMotion.outcomeBadge, value: model.outcome)
            }

            HStack(spacing: 8) {
                if hand.isEmpty {
                    // 配牌前に中身が空だと「白い空箱」に見えるため、カードが配られる位置を示す
                    BaccaratCardPlaceholder()
                    BaccaratCardPlaceholder()
                } else {
                    ForEach(Array(hand.enumerated()), id: \.element.id) { index, card in
                        BaccaratDealtCardView(index: index, isBanker: isBanker) {
                            BaccaratCardView(card: card)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 90)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .popCard(corner: Theme.cornerSmall)
    }

    /// その手に出すバッジの文言。関係の無い側には出さない（nil）。
    private func outcomeBadgeText(_ outcome: BaccaratOutcome, for side: BaccaratBet) -> String? {
        switch outcome {
        case .tie:    return "引き分け"
        case .player: return side == .player ? "勝ち！" : nil
        case .banker: return side == .banker ? "勝ち！" : nil
        }
    }

    @ViewBuilder
    private func outcomeBadge(_ outcome: BaccaratOutcome, for side: BaccaratBet) -> some View {
        if let text = outcomeBadgeText(outcome, for: side) {
            Text(text)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(outcome == .tie ? .white : Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(outcome == .tie ? Theme.fillMuted : Theme.Fill.teal))
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .betting: bettingView
        case .result:  resultView
        }
    }

    private var bettingView: some View {
        VStack(spacing: 8) {
            Text("賭け先を選んでください")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            HStack(spacing: 10) {
                ForEach(BaccaratBet.allCases, id: \.self) { choice in
                    betChoiceButton(choice)
                }
            }
            Text("ベット額を選ぶと配られます")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            HStack(spacing: 10) {
                ForEach(betOptions, id: \.self) { amount in
                    actionButton("\(amount)枚", color: Theme.Fill.coral, disabled: model.chips < amount) {
                        model.placeBet(amount)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 賭け先の 3 択。選んでいる 1 つだけを差し色で塗り、残りは沈めた面にする。
    private func betChoiceButton(_ choice: BaccaratBet) -> some View {
        let isSelected = model.selectedBet == choice
        return Button {
            model.select(choice)
        } label: {
            VStack(spacing: 1) {
                Text(choice.label)
                    .themeBody(14)
                Text(choice.payoutLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            // 文字を拡大しても「プレイヤー」が折り返して別の語に読めないよう、縮めて収める（#189）。
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: BaccaratMetrics.actionButtonMinHeight)
            .background(isSelected ? Theme.Fill.teal : Theme.fillMuted,
                        in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(isSelected ? Theme.onAccent : Color.white)
        }
        .buttonStyle(.pop)
        .accessibilityLabel(BaccaratAccessibility.betChoiceLabel(choice))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            Text(resultSummary)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(model.lastChipDelta > 0 ? Theme.teal
                                 : (model.lastChipDelta < 0 ? Theme.coral : Theme.inkSub))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            RecordLabel(model.recordResult)
            actionButton("次のゲーム", color: Theme.Fill.coral) {
                model.nextRound()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    /// リザルトの 1 行。数値は `Text` 補間の桁区切り（#484）を避けて文字列を先に組む。
    private var resultSummary: String {
        let delta = model.lastChipDelta
        if delta > 0 { return "\(model.selectedBet.label)的中！ +\(delta)枚" }
        if delta < 0 { return "\(model.selectedBet.label)は外れ \(delta)枚" }
        return "引き分け。ベットはそのまま戻ります"
    }

    // MARK: - Session Over

    /// チップ切れの見出し下の説明。復活を使い切ったら選べる手を書き換える（#499）。
    /// 復活できるあいだは、もらえる枚数と**順位表に載らないこと**を並べて書く（#523）。
    private var sessionOverSubtitle: String {
        model.canReviveAfterBust
            ? "\(BaccaratModel.reviveChips)枚で復活すると順位表に載りません"
            : "復活はこのセッションで使いました。最初からやり直せます"
    }

    private var reviveButtonTitle: String {
        "広告を見て\(BaccaratModel.reviveChips)枚で復活（1セッションに1回）"
    }

    private var restartButtonTitle: String {
        "最初からやり直す (\(BaccaratModel.initialChips)枚)"
    }

    private var sessionOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    // 残高が 0 とは限らない（バンカー払いの端数で止まる）ので「足りません」と言う。
                    Text("チップが足りなくなりました")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.coral)
                    Text(sessionOverSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                        // SE では縦が詰まり、2 行の文言が 1 行目の途中で切られる（#523）。
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            // チップが尽きた回は resultView ではなくこちらが出るため、記録行もここに置く。
            RecordLabel(model.recordResult)

            // チップ切れ復活（#499）。ブラックジャック（#523）と同じ形
            // （リザルト内のボタン・視聴完了時のみ効果・失敗は #64 統一アラート）。
            if model.canReviveAfterBust {
                Button {
                    // 連打ガードと失敗アラートは共通側が持つ（#526）。見終えたのに適用できなかった
                    // ときは「視聴しなかった」ではなく適用できない旨を出す（#727）。
                    reviveRescue.requestHandledByModel(withOutcome: { await model.reviveAfterAd() })
                } label: {
                    Label(reviveButtonTitle, systemImage: "play.rectangle.fill")
                        .themeBody(16).frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.yellow)
                .disabled(reviveRescue.isWatching)
            }

            Button { model.restartSession() } label: {
                Text(restartButtonTitle).themeBody(16).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            // 広告のロード〜視聴中にやり直すと、見終えた復活が新しいセッションへ乗りかける（#727）。
            // モデル側でも照合しているが、押せる窓そのものを塞ぐ。
            .disabled(reviveRescue.isWatching)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Helper

    /// - Parameter foreground: 面（`color`）の上に載せる文字色。差し色の面には `Theme.onAccent`（#220）。
    private func actionButton(_ title: String, color: Color, foreground: Color = Theme.onAccent,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると「200枚」が「20」「0枚」に折り返されて別の額に読めるため、
                // 折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // 高さの下限は HIG の 44pt（#709）。
                .frame(maxWidth: .infinity, minHeight: BaccaratMetrics.actionButtonMinHeight)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(disabled ? Theme.inkSub : foreground)
        }
        // `.plain` は押下フィードバックも消えるので、押している間だけ沈む `.pop` を使う（#195）。
        .buttonStyle(.pop)
        .disabled(disabled)
    }
}

// MARK: - Deal Animation

/// 配られてくる 1 枚（#209）。上から落ちてきて実寸に収まる。
///
/// 段差は「置かれた順」で決まりビューの再生成では変わらないので、状態は**このビュー自身が持つ**。
/// `ForEach` の identity はカードの `id` なので、ラウンドが変われば作り直されて演出がやり直される。
struct BaccaratDealtCardView<Content: View>: View {
    let index: Int
    let isBanker: Bool
    let content: () -> Content

    /// 置き終わったか。`false` の間だけ持ち上げて薄くしておく。
    @State private var dealt = false

    init(index: Int, isBanker: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.index = index
        self.isBanker = isBanker
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(dealt ? 1 : BaccaratMotion.dealStartScale)
            .offset(y: dealt ? 0 : BaccaratMotion.dealOffset)
            .opacity(dealt ? 1 : 0)
            .onAppear {
                // Reduce Motion が ON なら `withGameAnimation` が補間を落とすので、
                // 遅れも動きも無く即座に置かれる（状態変更そのものは必ず走る）。
                withGameAnimation(BaccaratMotion.dealAppear(index: index, isBanker: isBanker)) {
                    dealt = true
                }
            }
    }
}

// MARK: - Card View

struct BaccaratCardView: View {
    let card: BaccaratCard
    /// 画面の広さ（#458）。この画面も `GeometryReader` を持たず札が固定 pt なので、
    /// iPad では札だけが取り残される。渡された寸法をそのまま相似に拡大する。
    @Environment(\.adaptiveLayout) private var layout

    private var metrics: PlayingCardMetrics {
        PlayingCardMetrics.standard.scaled(by: layout.elementScale)
    }

    var body: some View {
        ZStack {
            // 外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(faceUp: true, cornerRadius: metrics.cornerRadius)
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
        // 1 枚 1 要素にまとめる（#1044）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BaccaratAccessibility.cardLabel(card: card))
    }
}

/// 配牌前のカード置き場（`BaccaratCardView` と同じ寸法で、配牌時に高さが動かないようにする）
struct BaccaratCardPlaceholder: View {
    @Environment(\.adaptiveLayout) private var layout

    private var metrics: PlayingCardMetrics {
        PlayingCardMetrics.standard.scaled(by: layout.elementScale)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .strokeBorder(Theme.inkSub.opacity(0.3),
                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: metrics.width, height: metrics.height)
    }
}
