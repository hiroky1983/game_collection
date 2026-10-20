import SwiftUI
import Core

public struct BlackjackView: View {
    @State private var model: BlackjackModel
    private let services: GameServices
    /// 画面の広さ（#458）。スプリット行の高さを札（`.compact` = 42×60）と同じ倍率で拡大する。
    @Environment(\.adaptiveLayout) private var layout
    /// 負けた 1 回をやり直すリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var retryRescue = RewardedRescue()

    public init(services: GameServices) {
        self.services = services
        var dealerDrawInterval = BlackjackMotion.dealerDrawInterval
        #if DEBUG
        // 撮影用（#667）: `-blackjackDealerDrawSeconds <秒>` でディーラーの間を延ばし、引いている途中を止めて撮る。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-blackjackDealerDrawSeconds"), i + 1 < args.count,
           let seconds = Double(args[i + 1]) {
            dealerDrawInterval = .milliseconds(Int(seconds * 1000))
        }
        #endif
        _model = State(initialValue: BlackjackModel(services: services, dealerDrawInterval: dealerDrawInterval))
    }

    public var body: some View {
        VStack(spacing: 10) {
            statusBar
            // 配牌前は両者の手札が空で、テーブルを出すと白い空箱が画面の大半を占める。
            // 配るのを促す1枚のカードに差し替え、配牌後に本来のテーブルへ切り替える。
            if isBeforeDeal {
                Spacer(minLength: 0)
                preDealTable
                Spacer(minLength: 0)
            } else {
                // ディーラーとあなたの境目（= 卓の中央）に勝敗を重ねる（#1754）。画面全体の中央に
                // 重ねるとあなたの手札を覆ってしまうので、この 2 つだけを囲んで中央を取る。
                // 手ごとのバッジ（`outcomeBadge`）は残す——スプリットでは手ごとの勝敗が行に要るし、
                // バナーが消えたあとも結果が読める。勝敗の読み上げ（#1574）もこの重ねが担う
                // （出る瞬間に、理由と増減まで添えて読む）。
                VStack(spacing: 10) {
                    dealerArea
                    Spacer(minLength: 4)
                    playerArea
                }
                .handResultOverlay(model.handResult, appearDelay: .milliseconds(200))
            }
            HowToPlayHint(.blackjack, playLog: services.playLog)
            if model.isMatchClosed {
                matchOverView
            } else {
                actionArea
            }
            RecommendationSlot(services: services, isFinished: model.isMatchClosed)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .rewardOffer(retryRescue, for: .undo, isPresented: model.canRetryLoss,
                     services: services, gameID: model.gameID)
        .gameChrome(title: tr("ブラックジャック"), review: services.review)
        .howToPlay(HowToPlayGuide.blackjack.illustrated(BlackjackHowToFigures.items))
        .onAppear {
            #if DEBUG
            // 撮影・動作確認用: `-simulateBlackjackAction <split|hit|stand>` でその操作を1回行う（#439）。
            // 配りが乱数なので中断スナップショットを注入して手札を決め打ちしたうえで、
            // タップ起点の操作をここから起こす（#437 の `-simulateChord`・#438 の
            // `-simulate2048Move` と同型。撮った画がコードの実行結果であることを担保する）。
            let args = ProcessInfo.processInfo.arguments
            // 撮影用（#1754）: 配って、そのままスタンドして決着の画を出す。配りは乱数なので
            // 勝敗は撮るたびに変わる（実際のモデルの経路を通る）。
            if args.contains("-blackjackAutoPlay"), model.phase == .ready {
                model.deal()
                if model.phase == .playerTurn { model.stand() }
            }
            if let i = args.firstIndex(of: "-simulateBlackjackAction"), i + 1 < args.count {
                switch args[i + 1] {
                case "split":  model.split()
                case "hit":    model.hit()
                case "stand":  model.stand()
                default:       break
                }
            }
            #endif
        }
        .rewardedRescueAlerts(
            retryRescue,
            notEarned: tr("やり直せませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("やり直せませんでした"),
                message: tr("広告を見ているあいだに勝負が変わったため、やり直しは適用していません。やり直しの権利は使っていません。")
            )
        )
    }

    // MARK: - Status Bar

    /// 何回目か・合計点・連勝。10 回勝負の進み具合を常に見せる。
    private var statusBar: some View {
        HStack {
            Label(tr("第%1$lld回 / %2$lld回", model.roundNumber, BlackjackModel.roundsPerMatch),
                  systemImage: "flag.checkered")
                .themeBody(14)
                .foregroundStyle(Theme.ink)
            Spacer()
            if model.streak >= 2 {
                Text(tr("%lld連勝", model.streak))
                    .themeCaption(12, weight: .black, maxScale: 1.5)
                    .foregroundStyle(Theme.yellowText)
                    .padding(.trailing, 8)
            }
            Label(tr("%lld点", model.score), systemImage: "star.fill")
                .themeBody(14)
                .foregroundStyle(Theme.yellowText)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BlackjackAccessibility.statusLabel(
            round: model.roundNumber, rounds: BlackjackModel.roundsPerMatch,
            score: model.score, streak: model.streak
        ))
    }

    // MARK: - Pre-deal Table

    /// 手札が両者とも空で、これから配る局面か
    private var isBeforeDeal: Bool {
        model.phase == .ready && model.dealerHand.isEmpty && model.playerHand.isEmpty
    }

    private var preDealTable: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                BJCardPlaceholder()
                BJCardPlaceholder()
            }
            VStack(spacing: 6) {
                Text(tr("カードを配って勝負しましょう"))
                    .themeBody(15, weight: .bold, maxScale: 1.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.ink)
                Text(tr("21 に近いほうが勝ち。ディーラーは 17 以上で止まります。"))
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 18)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Dealer Area

    private var dealerArea: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("ディーラー"))
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .accessibilityHidden(model.phase == .result || model.phase == .dealerTurn)
                Spacer()
                if model.phase == .result || model.phase == .dealerTurn {
                    Text("\(model.dealerValue)")
                        .themeBody(14, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(model.dealerValue > 21 ? Theme.coralText : Theme.purple)
                        .accessibilityLabel(BlackjackAccessibility.totalLabel(
                            owner: tr("ディーラー"), value: model.dealerValue
                        ))
                } else if !model.dealerHand.isEmpty {
                    Text("\(model.dealerVisibleValue) + ?")
                        .themeBody(14, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.inkSub)
                        .accessibilityLabel(BlackjackAccessibility.dealerPartialValueLabel(
                            visibleValue: model.dealerVisibleValue
                        ))
                }
            }

            HStack(spacing: 8) {
                if model.dealerHand.isEmpty {
                    // 配牌前に中身が空だと「白い空箱」に見えるため、カードが配られる位置を示す
                    BJCardPlaceholder()
                    BJCardPlaceholder()
                } else {
                    ForEach(Array(model.dealerHand.enumerated()), id: \.element.id) { idx, card in
                        let hidden = idx == 1 && model.phase == .playerTurn
                        // 伏せカードの公開はこのゲーム唯一の山場なので、表裏を差し替えるのではなく
                        // 進捗を補間して実際に返す（#209）。
                        BJDealtCardView(index: idx, isDealer: true) {
                            BJFlipCardView(card: card, progress: hidden ? 0 : 1)
                                .gameAnimation(BlackjackMotion.holeCardFlip, value: hidden)
                        }
                    }
                }
            }
            .frame(minHeight: 90)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Player Area

    private var playerArea: some View {
        VStack(spacing: 10) {
            // スプリットしたラウンドは手が2つに割れ、勝敗がそれぞれ別（#439）。
            if model.hands.count > 1 {
                ForEach(Array(model.hands.enumerated()), id: \.element.id) { idx, hand in
                    splitHandRow(index: idx, hand: hand)
                }
            } else {
                singleHandArea
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .popCard(corner: Theme.cornerSmall)
    }

    private var singleHandArea: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("あなた"))
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(!model.playerHand.isEmpty)
                Spacer()
                if !model.playerHand.isEmpty {
                    Text("\(model.playerValue)")
                        .themeBody(14, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(model.playerValue > 21 ? Theme.coralText : Theme.tealText)
                        .accessibilityLabel(BlackjackAccessibility.totalLabel(
                            owner: tr("あなた"), value: model.playerValue
                        ))
                }
                // 勝敗バッジはフェードで出す（#209）。`.gameAnimation` はこの ZStack にだけ置く
                // （手札の値の入れ替えまで animate されると決着の瞬間に行が伸び縮みする）。
                // 修飾子は1つのビューに1つだけ置くこと（入れ子にすると打ち消し合う・#199）。
                ZStack {
                    if let outcome = model.outcome {
                        outcomeBadge(outcome)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .gameAnimation(BlackjackMotion.outcomeBadge, value: model.outcome)
            }

            HStack(spacing: 8) {
                if model.playerHand.isEmpty {
                    BJCardPlaceholder()
                    BJCardPlaceholder()
                } else {
                    ForEach(Array(model.playerHand.enumerated()), id: \.element.id) { idx, card in
                        BJDealtCardView(index: idx, isDealer: false) {
                            BJCardView(card: card, faceUp: true)
                        }
                    }
                }
            }
            .frame(minHeight: 90)
        }
    }

    // MARK: - Split Hands (#439)

    /// スプリットで分かれた手 1 つぶん。2 手ぶんを縦に積むため札は `compact` で描く。
    private func splitHandRow(index: Int, hand: BlackjackHand) -> some View {
        let isActive = model.phase == .playerTurn && index == model.activeHandIndex
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("ハンド%lld", index + 1))
                    .themeBody(13)
                    .foregroundStyle(isActive ? Theme.ink : Theme.inkSub)
                    .accessibilityHidden(true)
                // 枠の色だけで「今どちらを操作しているか」を示すと色覚に依存するため、文字でも出す。
                if isActive {
                    Text(tr("操作中"))
                        .themeCaption(10, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Fill.teal))
                }
                Spacer(minLength: 0)
                Text("\(hand.value)")
                    .themeBody(14, weight: .black, maxScale: 1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(hand.isBusted ? Theme.coralText : Theme.tealText)
                    .accessibilityLabel(BlackjackAccessibility.totalLabel(
                        owner: tr("ハンド%lld", index + 1), value: hand.value
                    ))
                if let outcome = hand.outcome {
                    outcomeBadge(outcome)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(hand.cards.enumerated()), id: \.element.id) { idx, card in
                    BJDealtCardView(index: idx, isDealer: false) {
                        BJCardView(card: card, faceUp: true, metrics: .compact)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: layout.scaled(60))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? Theme.teal : Color.clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private func outcomeBadge(_ outcome: BlackjackOutcome) -> some View {
        switch outcome {
        case .playerBlackjack:
            Text(tr("ブラックジャック！"))
                .themeCaption(12, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.yellow))
        case .win:
            Text(tr("勝ち！"))
                .themeCaption(12, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.teal))
        case .push:
            Text(tr("引き分け"))
                .themeCaption(12, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.fillMuted))
        case .lose:
            Text(tr("負け"))
                .themeCaption(12, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
        case .bust:
            Text(tr("バスト"))
                .themeCaption(12, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .ready:
            dealView
        case .playerTurn:
            playerActionView
        case .result:
            resultView
        case .dealerTurn:
            dealerTurnView
        case .idle:
            EmptyView()
        }
    }

    /// ディーラーが1枚ずつ引いているあいだの操作欄（#667）。待ちを飛ばして結果まで進められる。
    private var dealerTurnView: some View {
        VStack(spacing: 8) {
            actionButton(tr("結果まで進める"), role: .skip) {
                model.skipDealerDraws()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var dealView: some View {
        VStack(spacing: 8) {
            actionButton(tr("カードを配る"), role: .primary) {
                model.deal()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var playerActionView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                actionButton(tr("スタンド"), role: .skip) {
                    model.stand()
                }
                actionButton(tr("ヒット"), role: .primary) {
                    model.hit()
                }
            }
            // スプリットは最初の2枚が同じ点数のときだけの選択肢（#439）。
            if model.isSplitApplicable {
                actionButton(tr("スプリット"), role: .declaration) {
                    model.split()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            RecordLabel(model.recordResult)
            if model.canRetryLoss { retryButton }
            if model.isMatchOver {
                // 10 回目のあと。締めるまで記録は出ない（負けた回のやり直しを選べるように）。
                actionButton(tr("結果を見る"), role: .primary) {
                    model.finishMatch()
                }
            } else {
                // 次の回はそのまま配る（押す回数を増やさない）。
                actionButton(tr("次の回へ"), role: .primary) {
                    model.nextRound()
                    model.deal()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Match Over

    /// 負けた 1 回をやり直す広告導線。1 回の勝負につき 1 回まで（残っているあいだだけ出す）。
    private var retryButton: some View {
        Button {
            // 連打ガードと失敗アラートは共通側が持つ（#526）。広告とやり直しは
            // `retryLossAfterAd()` が 1 本で受け持つ。見終えたのに適用できなかったときは
            // 「視聴しなかった」ではなく適用できない旨を出す（#727）。
            retryRescue.requestHandledByModel(withOutcome: { await model.retryLossAfterAd() })
        } label: {
            Label(tr("広告を見て負けた1回をやり直す"), systemImage: "play.rectangle.fill")
                .themeBody(16).frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(retryRescue.isWatching)
    }

    /// 勝負を締めた画。決着の画（卓）は残したまま、操作欄を合計点と「もう一度」に差し替える。
    private var matchOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .scaledFont(24)
                    .foregroundStyle(Theme.yellowText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("%lld回勝負が終わりました", BlackjackModel.roundsPerMatch))
                        .themeBody(16, weight: .bold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.ink)
                    Text(tr("合計%1$lld点・最高%2$lld連勝", model.score, model.bestStreakInMatch))
                        .themeCaption(12, weight: .medium, maxScale: 1.5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            // 締めたあとは resultView ではなくこちらが出るため、記録行もここに置く。
            RecordLabel(model.recordResult)

            Button { model.restartSession() } label: {
                Text(tr("もう一度%lld回勝負", BlackjackModel.roundsPerMatch)).themeBody(16)
            }
            .buttonStyle(GameButtonStyle(role: .primary, shape: .block))
            // 広告のロード〜視聴中にやり直すと、見終えたやり直しが新しい勝負へ乗りかける（#727）。
            // モデル側でも照合しているが、押せる窓そのものを塞ぐ。
            .disabled(retryRescue.isWatching)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Helper

    /// 役割（`GameButtonRole`）で色を決める横いっぱいのボタン（#1423）。色・角丸・44pt は `GameButtonStyle` が持つ。
    private func actionButton(_ title: String, role: GameButtonRole, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると折り返してボタンの高さが跳ねるため、折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .disabled(disabled)
    }
}

// MARK: - Deal Animation

/// 配られてくる 1 枚（#209）。上から落ちてきて実寸に収まる。
///
/// 段差は「置かれた順」で決まりビューの再生成では変わらないので、状態は**このビュー自身が持つ**。
/// `ForEach` の identity はカードの `id` なので、ラウンドが変わって手札が入れ替われば
/// ビューごと作り直され、`onAppear` から演出がやり直される。
struct BJDealtCardView<Content: View>: View {
    let index: Int
    let isDealer: Bool
    let content: () -> Content

    /// 置き終わったか。`false` の間だけ持ち上げて薄くしておく。
    @State private var dealt = false

    init(index: Int, isDealer: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.index = index
        self.isDealer = isDealer
        self.content = content
    }

    var body: some View {
        content()
            // `.transition` と違い `.offset` より前に置く必要はないが、拡大・移動は
            // 不透明度より先に掛けて「遠くから来て濃くなる」順にする。
            .scaleEffect(dealt ? 1 : BlackjackMotion.dealStartScale)
            .offset(y: dealt ? 0 : BlackjackMotion.dealOffset)
            .opacity(dealt ? 1 : 0)
            .onAppear {
                // Reduce Motion が ON なら `withGameAnimation` が補間を落とすので、
                // 遅れも動きも無く即座に置かれる（状態変更そのものは必ず走る）。
                withGameAnimation(BlackjackMotion.dealAppear(index: index, isDealer: isDealer)) {
                    dealt = true
                }
            }
    }
}

// MARK: - Flip Reveal Card View

/// 裏から表へ返るディーラーの伏せカード（#209）。
///
/// `faceUp` の切り替えに `.gameAnimation` を掛けただけでは表裏が瞬時に入れ替わるだけなので、
/// ポーカーの `FlipRevealCardView`（#206）と同じく**このビュー自身を `Animatable`** にして
/// 進捗を補間させ、進捗の翻訳は `BlackjackMotion` の純関数に任せる。
struct BJFlipCardView: View, Animatable {
    nonisolated let card: BlackjackCard
    /// 0 = 裏 / 1 = 表。`.gameAnimation` が掛かっていればこの値が補間される。
    nonisolated var progress: Double

    // `View` への適合でこの型は MainActor 隔離になるが、`Animatable` の要求は nonisolated。
    // 保持しているのは値型（すべて Sendable）だけなので、格納プロパティごと nonisolated にする。
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showsFace = BlackjackMotion.showsFace(progress: progress)
        BJCardView(card: card, faceUp: showsFace)
            // 後半はカードごと 90 度を越えて回っているので、表の中身が鏡像にならないよう
            // ここで 180 度打ち消す（合計 360 度で元の向きに戻る）。
            .rotation3DEffect(.degrees(showsFace ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(
                .degrees(BlackjackMotion.flipDegrees(progress: progress)),
                axis: (x: 0, y: 1, z: 0)
            )
    }
}

// MARK: - Card View

struct BJCardView: View {
    let card: BlackjackCard
    var faceUp: Bool = true
    /// 札の寸法。スプリットで2手を縦に積むときだけ `compact` を渡す（#439）。
    var metrics: PlayingCardMetrics = .standard
    /// 画面の広さ（#458）。この画面も `GeometryReader` を持たず札が固定 pt なので、
    /// iPad では札だけが取り残される。渡された寸法をそのまま相似に拡大する
    /// （`.standard` も `.compact` も同じ倍率で大きくなるので、スプリット時の比率は保たれる）。
    @Environment(\.adaptiveLayout) private var layout

    private var scaled: PlayingCardMetrics { metrics.scaled(by: layout.elementScale) }

    var body: some View {
        ZStack {
            // 外形・面・裏はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(faceUp: faceUp, cornerRadius: scaled.cornerRadius)

            if faceUp {
                PlayingCardFace(figure: card.figure, metrics: scaled)
            } else {
                PlayingCardBack(metrics: scaled)
            }
        }
        .frame(width: scaled.width, height: scaled.height)
        // 表裏とも 1 枚 1 要素にまとめる（#1044）。裏のスート印を読ませず、伏せ札は中身を漏らさない。
        // ディーラー・プレイヤー・スプリットの各手はすべてこの View を通る。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BlackjackAccessibility.cardLabel(card: card, faceUp: faceUp))
    }
}

/// 配牌前のカード置き場（`BJCardView` と同じ寸法で、配牌時に高さが動かないようにする）
struct BJCardPlaceholder: View {
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
