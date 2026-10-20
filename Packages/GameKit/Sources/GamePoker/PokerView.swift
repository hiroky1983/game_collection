import SwiftUI
import Core

public struct PokerView: View {
    @State private var model: PokerModel
    private let services: GameServices
    @State private var showStartSheet = true
    @Environment(\.dismiss) private var dismiss
    @State private var revealCPU = false
    /// 「もう 1 回交換」のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var extraExchangeRescue = RewardedRescue()
    @State private var showPointTable = false
    /// 初回だけ出す遊び方ヒントを出すか（#118）。**この画面では判定を自前で持つ**（#650）。
    /// 下の `body` は `ViewThatFits` で同じ列を2回組み立てるため、init で「見せた」を消費する
    /// `HowToPlayHint(_:playLog:)` を使うと 2 つめが false を受け取り、あとから選ばれた枝で
    /// ヒントが消える。判定はここで 1 回だけ行い、結果を渡す。
    @State private var showsHowToPlayHint: Bool
    /// 画面の広さ（#458）。iPad で縦の余白をどう配るかにだけ使う（#485）。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        // Reduce Motion が ON なら手札は即座に表になるので、勝敗の触覚も待たせない（#667）。
        let restored = PokerModel(
            services: services,
            showdownRevealDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay
        )
        _model = State(initialValue: restored)
        // 中断データがあれば開始シートは出さず、その続きから遊ぶ。
        _showStartSheet = State(initialValue: restored.phase == .idle)
        // 中断した回が決着済み（`.result`）なら、CPU の手札は表のまま戻す。
        _revealCPU = State(initialValue: restored.phase == .result)
        _showsHowToPlayHint = State(
            initialValue: services.playLog?.markGuideShown(for: "poker") ?? false
        )
    }

    public var body: some View {
        // 背の高い局面は縦が足りず、`VStack` 1 枚では溢れたぶんが上下に切り落とされていた（#650）。
        //
        // **収まるあいだは今までの縦並びをそのまま使い、収まらないときだけスクロールに落とす**。
        // `ViewThatFits` は選んだ側しか画面に置かないので、収まる局面の描画は従来と一致し、
        // #485 / #640 で決めた位置が 1pt も動かない。
        //
        // 常にスクロールに載せる形は採らない。`ScrollView` を置くと iOS 26 のナビゲーションバーが
        // 確保する安全域が 49pt → 64pt に広がり（プローブビルドで実測）、収まっている端末まで
        // 15pt 下がるため。
        ViewThatFits(in: .vertical) {
            mainColumn
            GeometryReader { geo in
                ScrollView {
                    // **幅を枠に固定する**。`ScrollView` は中身の理想幅が枠より広いとそちらを
                    // 提案してくるため、指定しないと CPU の札5枚（固定 pt で枠に収まらない）が
                    // 基準になって列全体が広がり、右端が切れて左へ寄る（実測）。
                    mainColumn
                        .frame(width: geo.size.width)
                        // 高さの下限も枠に合わせる。入れないと `Spacer` が最小のまま畳まれ、
                        // 数 pt 溢れただけの局面でも並びが base と食い違う。
                        .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
        .padding(Theme.pad)
        // 点数表は「役を覚える教材」を兼ねるので、対局中に1タップで開ける場所に置く（#496）。
        .gameChrome(title: tr("ポーカー"), review: services.review,
                    reference: GameChromeReference(tr("役の点数表")) { showPointTable = true })
        // 役一覧は3行に収まらないので、遊び方シートの「くわしいルール」へ送る（#118）。
        .howToPlay(PokerHowToFigures.guide) { HandGuideSheet() }
        .sheet(isPresented: $showStartSheet) {
            PokerStartSheet {
                showStartSheet = false
                revealCPU = false
                model.startGame()
            } onCancel: {
                // 「覗いてみたけど今はやめる」の退路（#1371）。勝負は始まっていないので記録・解析の
                // イベントは何も発生しない（それらは `startGame()` だけが送る）。
                showStartSheet = false
                dismiss()
            }
            // スワイプで閉じると「シートだけ消えて空の卓が残る」ため引き続き無効。
            // 閉じる操作はキャンセル（ハブへ戻る）に一本化する。
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showPointTable) {
            NavigationStack {
                PointTableSheet()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("閉じる")) { showPointTable = false }.fontWeight(.semibold)
                        }
                    }
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .result { revealCPU = true }
        }
        .task {
            #if DEBUG
            // 撮影用（#366）: 開始シートを飛ばして1回めを配る。手札5枚 + CPU の裏札が写る。
            if ProcessInfo.processInfo.arguments.contains("-pokerAutoStart") {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
            }
            // 撮影用（#1754）: 開始シートを飛ばし、交換なしで 1 回めの決着の画を出す。
            // 配りは乱数なので勝敗は撮るたびに変わる（実際のモデルの経路を通る）。
            if ProcessInfo.processInfo.arguments.contains("-pokerAutoPlay") {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
                model.confirmExchange()
                if model.phase == .exchanged { model.finishExchange() }
            }
            // 撮影用（#2551）: 1 回めの交換のあと、勝負に進むか広告でもう 1 回交換するかを選ぶ画面を出す。
            if ProcessInfo.processInfo.arguments.contains("-pokerExchangedPreview") {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
                model.confirmExchange()
            }
            // 撮影用（#2551）: 点数表だけを出す。開始シートと同時には出せない
            // （同じビューから2枚のシートは presented にならない）ので排他にする。
            if ProcessInfo.processInfo.arguments.contains("-pokerPointTable") {
                showStartSheet = false
                showPointTable = true
            }
            #endif
        }
        .rewardedRescueAlerts(
            extraExchangeRescue,
            notEarned: tr("交換できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("交換できませんでした"),
                message: tr("広告を見ているあいだに回が進んだため、交換は適用していません。交換の回数は減っていません。")
            )
        )
    }

    /// 画面の縦並び本体。`ViewThatFits` の2つの枝で同じものを使うために切り出しただけで、
    /// 並びは変えていない。
    private var mainColumn: some View {
        VStack(spacing: 10) {
            statusBar
            verticalSlack
            cpuArea
            verticalSlack
            // 1 回の勝敗を卓の中央（CPU とあなたの境目）に大きく出す（#1754）。画面全体の中央に
            // 重ねるとあなたの手札を覆ってしまうので、この帯の位置に重ねる。13pt のバッジ（`resultBadge`）は残す
            // ——バナーは数秒で消えるので、消えたあとも手札の横で勝敗が読める。
            // CPU の 5 枚を返す決着は、返り終わってから出す（先に出すと勝敗の答えを見せてから返すことになる・#667）。
            scoreArea
                .handResultOverlay(
                    model.handResult,
                    appearDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay
                )
                // 後ろに並ぶ手札の枠より手前に描く（兄弟は並び順に重なるため、無いとバナーの下半分が隠れる）。
                .zIndex(1)
            verticalSlack
            playerArea
            verticalSlack
            actionSlack
            // 出すかどうかは `showsHowToPlayHint` が1回だけ決める（上の `body` のコメント）。
            HowToPlayHint(.poker, isVisible: showsHowToPlayHint)
            actionArea
            RecommendationSlot(services: services, isFinished: model.isMatchOver)
            // iPad の余りは上の `verticalSlack` が配るので、ここには可変の余白を置かない。
            // 置くと最後の 1 つぶんが下端に固まって残る（実測 14.2%・#485）。
            if layout.isWide {
                Color.clear.frame(height: 4)
            } else {
                Spacer(minLength: 4)
            }
            BannerSlot(ads: services.ads)
        }
    }

    /// iPad で余った高さを節の間に配るための可変余白（#485）。iPhone では何も置かないので
    /// `VStack` の子の並びが変わらず、見た目は 1pt も動かない。
    @ViewBuilder
    private var verticalSlack: some View {
        if layout.isWide { Spacer(minLength: 0) }
    }

    /// 操作の節（遊び方ヒント + 交換）の上に置く可変余白（#640）。
    ///
    /// iPhone では余りが下端の `Spacer` に全部たまり、操作の列が画面の中ほどに浮いて
    /// 下だけが大きく空いていた。ここに同じ可変余白をもう 1 つ置くと余りが上下で等分され、
    /// 列が半分ぶんだけ下がる（iPhone 17 Pro Max の実測で **+99pt**）。
    /// `playerArea` 側に `.frame(maxHeight: .infinity)` を付ける手も試したが、
    /// 余りを総取りして操作の列が広告に接してしまう（実測 +185pt）ため採らない。
    ///
    /// 余りが無い端末では `Spacer` 自体は 0pt だが、`VStack(spacing: 10)` の隙間が 1 つ増えるぶん
    /// 節全体が 10pt 伸びる（iPhone SE で実測。上に 5pt / 下に 5pt 広がるだけで、広告まで収まる）。
    ///
    /// iPad は `verticalSlack` がすでに余りを節の間に配っているので何も置かない（#485 の配分を崩さない）。
    @ViewBuilder
    private var actionSlack: some View {
        if !layout.isWide { Spacer(minLength: 0) }
    }


    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Label(tr("%1$lld / %2$lld 回目", max(model.round, 1), PokerMatch.roundsPerMatch), systemImage: "suit.spade.fill")
                .themeBody(14)
                .foregroundStyle(Theme.ink)
            Spacer()
            Label(tr("合計 %@点", RecordFormat.number(model.totalPoints)), systemImage: "star.fill")
                .themeBody(14)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: Double(model.totalPoints)))
                .gameAnimation(PokerMotion.potChange, value: model.totalPoints)
                // 点が変わるのと同時に画面全体のレイアウトが動く場面では、この Label だけが古い位置から
                // 滑ってきて枠の外に文字が出る。位置は親と一体で決まるようにして、数字の入れ替えだけを演出に残す。
                .geometryGroup()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// CPU の手札を表向きにしてよいか。`.result` に入った**次の**更新（`onChange`）で真になる。
    ///
    /// **`|| model.phase == .result` を足してはいけない**（#383）。それを足すと `.result` に
    /// 入ったその描画で既に真になり、同じ描画で新規に挿入される役名 `Text` とカードには
    /// 「変化前の値」が無いため `.gameAnimation(_:value:)` が一度も走らない。結果、
    /// 遅延フェードが効かず**カードが返る前に役名が見えて**しまう。`.result` と `.showdown` は
    /// `PokerModel.persist()` の保存対象外なので、この状態で復元されることもない。
    private var cpuRevealed: Bool { revealCPU }

    // MARK: - CPU Area

    private var cpuArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("CPU")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                if !model.cpuAction.isEmpty {
                    Text(model.cpuActionLabel)
                        .themeCaption(12, weight: .bold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Fill.purple))
                }
                Spacer()
                if model.phase == .result {
                    Text(model.cpuHandRank.description)
                        .themeCaption(12, weight: .bold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.purple)
                        // 役名が手札より先に出ると答えを見せてから返すことになるので、
                        // 5 枚が返り終わってから薄く現れる（#206）。
                        .opacity(cpuRevealed ? 1 : 0)
                        .gameAnimation(
                            .easeIn(duration: PokerMotion.potChangeDuration)
                                .delay(PokerMotion.showdownTotalDuration),
                            value: cpuRevealed
                        )
                }
            }

            HStack(spacing: 8) {
                // ショーダウンでは左から順に返す（#206）。index は段差の順番にだけ使う。
                ForEach(Array(model.cpuHand.enumerated()), id: \.element.id) { index, card in
                    FlipRevealCardView(card: card, progress: cpuRevealed ? 1 : 0)
                        .gameAnimation(PokerMotion.showdownFlip(index: index), value: cpuRevealed)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Score Area

    /// 卓の中央の帯。ここにその回の勝敗バナーを重ねる。これまでの勝敗と、その回の点を出す。
    private var scoreArea: some View {
        HStack(spacing: 14) {
            Spacer()
            Text(tr("%1$lld勝 %2$lld敗 %3$lld分", model.playerWins, model.cpuWins, model.draws))
                .themeBody(15, weight: .bold, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ink)
            if model.phase == .result {
                Text(tr("+%lld点", model.lastRoundPoints))
                    .themeBody(20, weight: .black, maxScale: 1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(model.lastRoundPoints > 0 ? Theme.yellowText : Theme.inkSub)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PokerAccessibility.scoreLabel(
            wins: model.playerWins, losses: model.cpuWins, draws: model.draws, points: model.totalPoints))
    }

    // MARK: - Player Area

    private var playerArea: some View {
        VStack(spacing: 6) {
            HStack {
                Text(tr("あなた"))
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if model.phase == .exchange {
                    Text(tr("捨てるカードを選んでください"))
                        .themeCaption(11, weight: .semibold, maxScale: 1.5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.tealText)
                }
                if model.phase == .result {
                    if let w = model.winner {
                        resultBadge(w)
                    }
                }
                if model.phase == .result {
                    Text(model.playerHandRank.description)
                        .themeCaption(12, weight: .bold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.tealText)
                }
            }
            HStack(spacing: 8) {
                ForEach(model.playerHand) { card in
                    let isSelected = model.selectedForExchange.contains(card.id)
                    CardView(card: card, faceUp: true, selected: isSelected)
                        .onTapGesture {
                            if model.phase == .exchange {
                                model.toggleCardSelection(card)
                            }
                        }
                        // カードは `onTapGesture` で組んでいるため、ボタン trait も読み上げ文も
                        // 自動では付かない（#710。大富豪の #188 と同じ形）。
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            PokerAccessibility.handCardLabel(card: card, isSelected: isSelected, phase: model.phase)
                        )
                        .accessibilityHint(PokerAccessibility.handCardHint(phase: model.phase))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.toggleCardSelection(card) }
                        // 交換フェーズ以外では `toggleCardSelection` が何もしないので、
                        // 操作可能として案内しない（描画は素の図形なので見た目は変わらない）。
                        .disabled(!PokerAccessibility.acceptsSelection(phase: model.phase))
                        .offset(y: isSelected ? 10 : 0)
                        .gameAnimation(PokerMotion.handSelection, value: isSelected)
                }
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    @ViewBuilder
    private func resultBadge(_ winner: PokerWinner) -> some View {
        switch winner {
        case .player:
            Text(tr("勝ち！"))
                .themeCaption(13, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.Fill.teal))
        case .cpu:
            Text(tr("負け"))
                .themeCaption(13, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.Fill.coral))
        case .tie:
            Text(tr("引き分け"))
                .themeCaption(13, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.fillMuted))
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .exchange:
            exchangeView
        case .exchanged:
            exchangedView
        case .result:
            resultView
        }
    }

    // カード交換
    private var exchangeView: some View {
        HStack(spacing: 12) {
            let count = model.selectedForExchange.count
            actionButton(count == 0 ? tr("交換しない") : tr("%lld枚を交換", count), role: .primary) {
                model.confirmExchange()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // 1 回めの交換のあと。勝負に進むか、広告を見てもう 1 回交換するか。
    private var exchangedView: some View {
        VStack(spacing: 8) {
            actionButton(tr("勝負！"), role: .primary) {
                model.finishExchange()
            }
            if model.canUseExtraExchange {
                Button {
                    // 連打ガードと失敗アラートは共通側が持つ（#526）。見終えたのに適用できなかったとき（#728）は
                    // 「視聴しなかった」と別のアラートを出す。
                    extraExchangeRescue.requestHandledByModel(withOutcome: { await model.extraExchangeAfterAd() })
                } label: {
                    Label(tr("広告を見てもう1回交換（1勝負に1回）"), systemImage: "play.rectangle.fill")
                        .themeBody(14).frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
                .disabled(extraExchangeRescue.isWatching)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // 1 回ぶんの決着。10 回目なら勝負の結果を出す。
    private var resultView: some View {
        VStack(spacing: 8) {
            if model.isMatchOver { matchSummary }
            actionButton(model.isMatchOver ? tr("もう一度（10回勝負）") : tr("次の回へ"), role: .primary) {
                revealCPU = false
                if model.isMatchOver {
                    model.startGame()
                } else {
                    model.nextRound()
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 10 回が終わったときの勝負の結果。合計点・勝敗・作った一番強い役。
    private var matchSummary: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .scaledFont(24)
                    .foregroundStyle(Theme.yellowText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("合計 %@点", RecordFormat.number(model.totalPoints)))
                        .themeBody(18, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.ink)
                    Text(matchSummaryDetail)
                        .themeCaption(12, weight: .semibold, maxScale: 1.5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.inkSub)
                }
                Spacer()
            }
            RecordLabel(model.recordResult)
        }
    }

    private var matchSummaryDetail: String {
        let record = tr("%1$lld勝 %2$lld敗 %3$lld分", model.playerWins, model.cpuWins, model.draws)
        guard let best = model.bestRank else { return record }
        return tr("%1$@・一番強い役 %2$@", record, best.description)
    }

    /// 役割（`GameButtonRole`）で色を決める横いっぱいのボタン（#1423）。色・角丸・44pt は `GameButtonStyle` が持つ。
    private func actionButton(_ title: String, role: GameButtonRole, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると折り返してボタンの高さが跳ねるため、折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .disabled(disabled)
    }
}

// MARK: - Flip Reveal Card View

/// 裏から表へ返る CPU の手札（#206）。
///
/// `faceUp` の切り替えに `.gameAnimation` を掛けただけでは表裏が瞬時に入れ替わるだけなので、
/// オセロの盤（#204）と同じく**このビュー自身を `Animatable`** にして進捗を補間させ、
/// 進捗の翻訳は `PokerMotion` の純関数に任せる（`PokerMotionTests` で固定できる）。
struct FlipRevealCardView: View, Animatable {
    nonisolated let card: PokerCard
    /// 0 = 裏 / 1 = 表。`.gameAnimation` が掛かっていればこの値が補間される。
    nonisolated var progress: Double

    // `View` への適合でこの型は MainActor 隔離になるが、`Animatable` の要求は nonisolated。
    // 保持しているのは値型（すべて Sendable）だけなので、格納プロパティごと nonisolated にして
    // 適合を成立させる（オセロの `OthelloBoardCanvas` と同じ）。
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showsFace = PokerMotion.showsFace(progress: progress)
        CardView(card: card, faceUp: showsFace)
            // 後半はカードごと 90 度を越えて回っているので、表の中身が鏡像にならないよう
            // ここで 180 度打ち消す（合計 360 度で元の向きに戻る）。
            .rotation3DEffect(.degrees(showsFace ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(
                .degrees(PokerMotion.flipDegrees(progress: progress)),
                axis: (x: 0, y: 1, z: 0)
            )
    }
}
