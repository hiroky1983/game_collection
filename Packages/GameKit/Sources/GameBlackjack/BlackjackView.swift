import SwiftUI
import Core

public struct BlackjackView: View {
    @State private var model: BlackjackModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @State private var showRewardNotEarned = false
    @State private var isRecoveringChips = false

    // ベット選択肢
    private let betOptions = [50, 100, 200, 500]

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: BlackjackModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 10) {
            chipsBar
            // 配牌前は両者の手札が空で、テーブルを出すと白い空箱が画面の大半を占める。
            // ベットを促す1枚のカードに差し替え、配牌後に本来のテーブルへ切り替える。
            if isBeforeDeal {
                Spacer(minLength: 0)
                preDealTable
                Spacer(minLength: 0)
            } else {
                dealerArea
                Spacer(minLength: 4)
                playerArea
            }
            HowToPlayHint(.blackjack, playLog: services.playLog)
            if model.sessionOver {
                sessionOverView
            } else {
                actionArea
            }
            RecommendationSlot(services: services, isFinished: model.phase == .result || model.sessionOver)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        .reviewRequestPrompt(services.review)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.coral)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("ブラックジャック")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
        .howToPlay(.blackjack)
        .onAppear {
            #if DEBUG
            // 撮影・動作確認用: `-simulateBlackjackAction <double|split|hit|stand>` でその操作を1回行う（#439）。
            // 配りが乱数なので中断スナップショットを注入して手札を決め打ちしたうえで、
            // タップ起点の操作をここから起こす（#437 の `-simulateChord`・#438 の
            // `-simulate2048Move` と同型。撮った画がコードの実行結果であることを担保する）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-simulateBlackjackAction"), i + 1 < args.count {
                switch args[i + 1] {
                case "double": model.doubleDown()
                case "split":  model.split()
                case "hit":    model.hit()
                case "stand":  model.stand()
                default:       break
                }
            }
            #endif
        }
        .alert("チップは回復しませんでした", isPresented: $showRewardNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
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

    /// 手札が両者とも空で、これからベットする局面か
    private var isBeforeDeal: Bool {
        model.phase == .betting && model.dealerHand.isEmpty && model.playerHand.isEmpty
    }

    private var preDealTable: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                BJCardPlaceholder()
                BJCardPlaceholder()
            }
            VStack(spacing: 6) {
                Text("ベットするとカードが配られます")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("21 に近いほうが勝ち。ディーラーは 17 以上で止まります。")
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
                Text("ディーラー")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                Spacer()
                if model.phase == .result || model.phase == .dealerTurn {
                    Text("\(model.dealerValue)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(model.dealerValue > 21 ? Theme.coral : Theme.purple)
                } else if !model.dealerHand.isEmpty {
                    Text("\(model.dealerVisibleValue) + ?")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
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
            // スプリットしたラウンドは手が2つに割れ、それぞれ賭け金も勝敗も別（#439）。
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
                Text("あなた")
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !model.playerHand.isEmpty {
                    Text("\(model.playerValue)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(model.playerValue > 21 ? Theme.coral : Theme.teal)
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
                Text("ハンド\(index + 1)")
                    .themeBody(13)
                    .foregroundStyle(isActive ? Theme.ink : Theme.inkSub)
                Text("\(hand.bet)枚\(hand.isDoubled ? "（ダブル）" : "")")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // 枠の色だけで「今どちらを操作しているか」を示すと色覚に依存するため、文字でも出す。
                if isActive {
                    Text("操作中")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Fill.teal))
                }
                Spacer(minLength: 0)
                Text("\(hand.value)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(hand.isBusted ? Theme.coral : Theme.teal)
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
            .frame(minHeight: 60)
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
            Text("ブラックジャック！")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.yellow))
        case .win:
            Text("勝ち！")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.teal))
        case .push:
            Text("引き分け")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.fillMuted))
        case .lose:
            Text("負け")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
        case .bust:
            Text("バスト")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .betting:
            bettingView
        case .playerTurn:
            playerActionView
        case .result:
            resultView
        case .dealerTurn, .idle:
            EmptyView()
        }
    }

    private var bettingView: some View {
        VStack(spacing: 8) {
            Text("ベット額を選んでください")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            HStack(spacing: 10) {
                ForEach(betOptions, id: \.self) { amount in
                    actionButton(
                        "\(amount)枚",
                        color: Theme.Fill.coral,
                        disabled: model.chips < amount
                    ) {
                        model.placeBet(amount)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var playerActionView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                actionButton("スタンド", color: Theme.fillMuted, foreground: .white) {
                    model.stand()
                }
                actionButton("ヒット", color: Theme.Fill.coral) {
                    model.hit()
                }
            }
            // ダブルダウン・スプリットは最初の2枚のときだけの選択肢（#439）。
            // 手の形が合っているあいだだけ並べ、チップが足りないときは押せなくする。
            if model.isDoubleDownApplicable || model.isSplitApplicable {
                HStack(spacing: 12) {
                    if model.isDoubleDownApplicable {
                        actionButton("ダブルダウン", color: Theme.Fill.yellow,
                                     disabled: !model.canDoubleDown) {
                            model.doubleDown()
                        }
                    }
                    if model.isSplitApplicable {
                        actionButton("スプリット", color: Theme.Fill.purple,
                                     disabled: !model.canSplit) {
                            model.split()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            RecordLabel(model.recordResult)
            actionButton("次のゲーム", color: Theme.Fill.coral) {
                model.nextRound()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Session Over

    private var sessionOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("チップがなくなりました")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.coral)
                    Text("広告を見て500枚回復するか、最初からやり直せます")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                Spacer()
            }

            // チップが尽きた回は resultView ではなくこちらが出るため、記録行もここに置く。
            RecordLabel(model.recordResult)

            Button {
                // 広告のロード〜表示中の連打で2本目が失敗し、誤ってアラートが出るのを防ぐ
                guard !isRecoveringChips else { return }
                isRecoveringChips = true
                Task {
                    if await model.recoverChipsAfterAd() == false { showRewardNotEarned = true }
                    isRecoveringChips = false
                }
            } label: {
                Label("広告を見てチップ回復 (+500枚)", systemImage: "play.rectangle.fill")
                    .themeBody(16).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.yellow)
            .disabled(isRecoveringChips)

            Button { model.restartSession() } label: {
                Text("最初からやり直す (1000枚)").themeBody(16).frame(maxWidth: .infinity)
                .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Helper

    /// - Parameter foreground: 面（`color`）の上に載せる文字色。差し色の面には `Theme.onAccent`、
    ///   `fillMuted` のような濃い面には白を渡す（#220）。
    private func actionButton(_ title: String, color: Color, foreground: Color = Theme.onAccent,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると「200枚」が「20」「0枚」に折り返されて別の額に読めるため、
                // 折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(disabled ? Theme.inkSub : foreground)
        }
        .buttonStyle(.plain)
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

    var body: some View {
        ZStack {
            // 外形・面・裏はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(faceUp: faceUp, cornerRadius: metrics.cornerRadius)

            if faceUp {
                PlayingCardFace(figure: card.figure, metrics: metrics)
            } else {
                PlayingCardBack(metrics: metrics)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

/// 配牌前のカード置き場（`BJCardView` と同じ寸法で、配牌時に高さが動かないようにする）
struct BJCardPlaceholder: View {
    private let metrics = PlayingCardMetrics.standard

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .strokeBorder(Theme.inkSub.opacity(0.3),
                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: metrics.width, height: metrics.height)
    }
}
