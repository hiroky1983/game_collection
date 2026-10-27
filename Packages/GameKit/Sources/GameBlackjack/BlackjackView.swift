import SwiftUI
import Core

public struct BlackjackView: View {
    @State private var model: BlackjackModel
    private let services: GameServices
    /// 画面の広さ（#458）。スプリット行の高さを札（`.compact` = 42×60）と同じ倍率で拡大する。
    @Environment(\.adaptiveLayout) private var layout
    /// 負けた回のやり直し（#2552）のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var retryRescue = RewardedRescue()
    /// ナビバーの「点数のルール」シート（#2596。ポーカーの「役の点数表」と同じ位置）。
    @State private var showScoringRules = false
    /// 結果の演出（めくり・勝敗バッジ）が終わるまで「次へ」を押せなくする（#2701）。
    @State private var nextLocked = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // 縦の狭い画面(iPhone SE)のスプリット中だけ固定 pt の中身が溢れるので、使える高さで寸法を選ぶ(#2498)。
        GeometryReader { geometry in
            let metrics = BlackjackVerticalMetrics.metrics(forHeight: geometry.size.height,
                                                           isSplit: model.hands.count > 1)
            content(metrics)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .rewardOffer(retryRescue, for: .undo, isPresented: model.canRetryRound,
                     services: services, gameID: model.gameID)
        // レイアウトパターン A（全画面・会長決裁 2026-10-19・#2426 → #2531）: フェルトを画面全体に敷き、ヘッダーは 1 行
        // （戻る・ブラックジャック・？）、バナーは画面最下部。ディーラー・あなたの白い札と操作欄の白い札はやめて
        // フェルトに直に置く。勝負の帯（何回目・勝ち点・連勝）はモックの A 案どおりヘッダーの下に 1 行の札で残す。
        .gameChrome(title: tr("ブラックジャック"), review: services.review, fullScreen: .felt, ads: services.ads,
                    reference: GameChromeReference(tr("点数のルール")) { showScoringRules = true })
        .sheet(isPresented: $showScoringRules) {
            NavigationStack {
                BlackjackScoringRulesSheet()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("閉じる")) { showScoringRules = false }.fontWeight(.semibold)
                        }
                    }
            }
        }
        .howToPlay(HowToPlayGuide.blackjack.illustrated(BlackjackHowToFigures.items).onboarding(BlackjackOnboarding.guide))
        // ディーラーが 1 枚引くたびに合計を読む（#2595）。文字の更新は VoiceOver が自動では読まない。
        .onChange(of: model.dealerHand.count) { old, new in
            if let text = BlackjackAccessibility.dealerDrawAnnouncement(oldCount: old, newCount: new,
                                                                        value: model.dealerValue) {
                AccessibilityNotification.Announcement(text).post()
            }
        }
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
            notEarned: tr("この回はやり直せませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("この回はやり直せませんでした"),
                message: tr("広告を見ているあいだに次の回へ進んだため、やり直しは使っていません。")
            )
        )
    }

    private func content(_ metrics: BlackjackVerticalMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            matchBar(metrics)
            // 卓・ミニガイド・操作欄を 1 つのまとまりにして、帯の下の残りの真ん中に置く（会長 QA 2026-10-22・#2531）。
            // 全画面にして縦が伸びた分を卓の中（ディーラーとあなたの間）で吸うと、真ん中が大きく空いていた。
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: metrics.spacing) {
                    // 配牌前は両者の手札が空で、テーブルを出すと白い空箱が画面の大半を占める。
                    // 勝負の説明を出す1枚のカードに差し替え、配牌後に本来のテーブルへ切り替える。
                    if isBeforeDeal {
                        preDealTable
                    } else {
                        // ディーラーとあなたの境目（= 卓の中央）に勝敗を重ねる（#1754）。画面全体の中央に
                        // 重ねるとあなたの手札を覆ってしまうので、この 2 つだけを囲んで中央を取る。
                        // 手ごとのバッジ（`outcomeBadge`）は残す——スプリットでは手ごとの勝敗が行に要るし、
                        // バナーが消えたあとも結果が読める。勝敗の読み上げ（#1574）もこの重ねが担う
                        // （出る瞬間に、理由と増減まで添えて読む）。
                        // 卓の高さはスプリット中の高さまで（`estimatedSplitTableHeight`）。1 手 ⇄ スプリットで
                        // 卓の背が変わらないので、ディーラーの札は動かない（中身が上限を超えたら中身の高さになる）。
                        VStack(spacing: metrics.tableSpacing) {
                            dealerArea(metrics)
                            Spacer(minLength: 4)
                            playerArea(metrics)
                        }
                        .frame(maxHeight: layout.scaled(metrics.estimatedSplitTableHeight))
                        .handResultOverlay(model.handResult, appearDelay: .milliseconds(200))
                    }
                    HowToPlayHint(.blackjack, playLog: services.playLog)
                    if model.matchOver {
                        matchOverView
                    } else {
                        // ボタン 2 段ぶんを取っておき上詰め（スプリット・やり直しのボタンの出入りでまとまりが動かない）。
                        actionArea
                            .frame(minHeight: metrics.actionAreaMinHeight, alignment: .top)
                    }
                }
                Spacer(minLength: 0)
            }
            // おすすめは 10 回の勝負を終えたときだけ出す（1 回ごとの結果は勝負の途中）。
            RecommendationSlot(services: services, isFinished: model.matchOver)
        }
        // 左右は全画面の枠の値（8pt）。上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
        .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
        .padding(.vertical, metrics.pad)
    }

    // MARK: - Match Bar (#2552)

    /// 上の帯。「n 回目 / 10」「勝ち n 点」「連勝 n」を並べる。
    private func matchBar(_ metrics: BlackjackVerticalMetrics) -> some View {
        HStack(spacing: 12) {
            Text(model.format == .single
                    ? tr("単発戦")
                    : tr("%1$lld回目 / %2$lld", model.currentRound, BlackjackModel.roundsPerMatch))
                .themeBody(14)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if model.showsFinalRoundMark { FinalRoundBadge() }
            Spacer(minLength: 0)
            Label(tr("勝ち %lld点", model.points), systemImage: "star.fill")
                .themeBody(14)
                .foregroundStyle(Theme.tealText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Label(tr("連勝 %lld", model.streak), systemImage: "flame.fill")
                .themeBody(14)
                .foregroundStyle(Theme.coralText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, metrics.chipsVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
        .finalRoundBar(model.showsFinalRoundMark)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pre-deal Table

    /// 手札が両者とも空で、これから 1 回目を配る局面か
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
                Text(tr("ディーラーと勝負"))
                    .themeBody(15, weight: .bold, maxScale: 1.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.ink)
                Text(tr("21 に近いほうが勝ち。勝てば 1 点、ブラックジャックで勝てば 2 点。ディーラーは 17 以上で止まります。"))
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSubText)
                    .multilineTextAlignment(.center)
                Text(tr("引き分け・バストは 0 点。引き分けでも連勝は途切れます。"))
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSubText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 18)
        .popCard(corner: Theme.cornerSmall)
        // 白い札の上なので、空き枠の破線はフェルト用（白）ではなく地の上の色で描く。
        .environment(\.cardTableInk, .plain)
    }

    // MARK: - Dealer Area

    private func dealerArea(_ metrics: BlackjackVerticalMetrics) -> some View {
        VStack(spacing: metrics.tableSpacing) {
            // フェルトの上の見出し・合計は卓の上の文字色（白系）。バストだけ赤い札にして目立たせる（色以外に札の形でも分かる）。
            CardTableInkReader { ink in
                HStack {
                    Text(tr("ディーラー"))
                        .themeBody(13)
                        .foregroundStyle(ink.labelSub)
                        .accessibilityHidden(model.phase == .result || model.phase == .dealerTurn)
                    Spacer()
                    if model.phase == .result || model.phase == .dealerTurn {
                        totalText(model.dealerValue, ink: ink)
                            .accessibilityLabel(BlackjackAccessibility.totalLabel(
                                owner: tr("ディーラー"), value: model.dealerValue
                            ))
                    } else if !model.dealerHand.isEmpty {
                        Text("\(model.dealerVisibleValue) + ?")
                            .themeBody(14, weight: .black, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(ink.labelSub)
                            .accessibilityLabel(BlackjackAccessibility.dealerPartialValueLabel(
                                visibleValue: model.dealerVisibleValue
                            ))
                    }
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
            .shrinkToFitWidth(naturalWidth: PlayingCardMetrics.standard.scaled(by: layout.elementScale)
                .rowWidth(count: max(model.dealerHand.count, 2), spacing: 8))
        }
        .padding(.horizontal, 6).padding(.vertical, metrics.areaVerticalPadding)
    }

    // MARK: - Player Area

    private func playerArea(_ metrics: BlackjackVerticalMetrics) -> some View {
        VStack(spacing: metrics.tableSpacing) {
            // スプリットした回は手が2つに割れ、それぞれ勝敗も勝ち点も別（#439）。
            if model.hands.count > 1 {
                ForEach(Array(model.hands.enumerated()), id: \.element.id) { idx, hand in
                    splitHandRow(index: idx, hand: hand)
                }
            } else {
                singleHandArea
            }
        }
        .padding(.horizontal, 6).padding(.vertical, metrics.areaVerticalPadding)
    }

    /// 合計の数字。フェルトの上なので白系で、バスト（22 以上）だけ赤い札に白い数字で出す。
    private func totalText(_ value: Int, ink: CardTableInk) -> some View {
        let busted = value > 21
        return Text("\(value)")
            .themeBody(14, weight: .black, maxScale: 1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(busted ? Theme.onAccent : ink.label)
            .padding(.horizontal, busted ? 8 : 0).padding(.vertical, busted ? 1 : 0)
            .background(Capsule().fill(busted ? Theme.Fill.coral : Color.clear))
    }

    private var singleHandArea: some View {
        VStack(spacing: 10) {
            CardTableInkReader { ink in
                HStack {
                    Text(tr("あなた"))
                        .themeBody(13)
                        .foregroundStyle(ink.label)
                        .accessibilityHidden(!model.playerHand.isEmpty)
                    Spacer()
                    if !model.playerHand.isEmpty {
                        totalText(model.playerValue, ink: ink)
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
            .shrinkToFitWidth(naturalWidth: PlayingCardMetrics.standard.scaled(by: layout.elementScale)
                .rowWidth(count: max(model.playerHand.count, 2), spacing: 8))
        }
    }

    // MARK: - Split Hands (#439)

    /// スプリットで分かれた手 1 つぶん。2 手ぶんを縦に積むため札は `compact` で描く。
    private func splitHandRow(index: Int, hand: BlackjackHand) -> some View {
        let isActive = model.phase == .playerTurn && index == model.activeHandIndex
        return VStack(spacing: 6) {
            CardTableInkReader { ink in
                HStack(spacing: 6) {
                    Text(tr("ハンド%lld", index + 1))
                        .themeBody(13)
                        .foregroundStyle(isActive ? ink.label : ink.labelSub)
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
                    totalText(hand.value, ink: ink)
                        .accessibilityLabel(BlackjackAccessibility.totalLabel(
                            owner: tr("ハンド%lld", index + 1), value: hand.value
                        ))
                    if let outcome = hand.outcome {
                        outcomeBadge(outcome)
                    }
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
                .strokeBorder(isActive ? Theme.Fill.yellow : Color.clear, lineWidth: 2)
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
            readyView
        case .playerTurn:
            playerActionView
                .disabled(model.isRevealingNatural) // 21 の回は伏せ札を見せるあいだ操作を受けない（#2700）
        case .result:
            resultView
        case .dealerTurn:
            dealerTurnView
        }
    }

    /// ディーラーが1枚ずつ引いているあいだの操作欄（#667）。待ちを飛ばして結果まで進められる。
    private var dealerTurnView: some View {
        VStack(spacing: 8) {
            actionButton(tr("結果まで進める"), role: .skip) {
                model.skipDealerDraws()
            }
        }
    }

    /// 1 回目を配る前（#2552）。勝負の形（10 回勝負か単発戦・#2860）を選ぶと、すぐ配られる。
    private var readyView: some View {
        VStack(spacing: 8) {
            actionButton(tr("10回勝負で配る"), role: .primary) {
                model.deal(format: .tenRounds)
            }
            actionButton(tr("単発戦で配る"), role: .skip) {
                model.deal(format: .single)
            }
            .accessibilityHint(tr("1回だけ勝負して終わります。10回勝負とは別の記録に残ります"))
        }
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
            // スプリットは最初の2枚が同じ点数のときだけの選択肢（#439）。手の形が合っているあいだだけ並べる。
            if model.canSplit {
                actionButton(tr("スプリット"), role: .declaration) {
                    model.split()
                }
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            // 負けた回のやり直し（#2552）。1 回の勝負につき 1 回、負けた回の結果にだけ出す。
            // 連打ガードと失敗アラートは共通側が持つ（#526）。広告とやり直しは `retryRoundAfterAd()` が 1 本で受け持つ。
            if model.canRetryRound {
                Button {
                    retryRescue.requestHandledByModel(withOutcome: { await model.retryRoundAfterAd() })
                } label: {
                    Label(tr("広告を見てこの回をやり直す（1回まで）"), systemImage: "play.rectangle.fill")
                        .themeBody(15).frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
                .accessibilityHint(model.format == .single
                    ? tr("1回だけ、広告を見るとこの回をやり直せます")
                    : tr("10回の勝負につき1回だけ、広告を見るとこの回をやり直せます"))
                .disabled(retryRescue.isWatching)
            }
            actionButton(model.isFinalRoundResult ? tr("結果を見る") : tr("次の回へ"), role: .primary,
                         disabled: retryRescue.isWatching || nextLocked) {
                model.nextRound()
            }
        }
        .modifier(NextUnlock(locked: $nextLocked, duration: BlackjackMotion.nextButtonLockDuration,
                             reduceMotion: reduceMotion))
    }

    // MARK: - Match Over (#2552)

    /// 10 回勝負を終えたときのまとめ。勝ち点の合計・この勝負の最高連勝・自己ベストを並べる。
    private var matchOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                let outcome = model.matchOutcome
                let icon = outcome == .win ? "trophy.fill" : outcome == .loss ? "xmark.octagon.fill" : "equal.circle.fill"
                let iconColor = outcome == .win ? Theme.yellowText : outcome == .loss ? Theme.coralText : Theme.tealText
                let title: String = switch (model.format, outcome) {
                case (.single, .win):  tr("単発戦は勝ち！")
                case (.single, .loss): tr("単発戦は負け")
                case (.single, _):     tr("単発戦は引き分け")
                case (_, .win):        tr("10回勝負は勝ち越し！")
                case (_, .loss):       tr("10回勝負は負け越し")
                default:               tr("10回勝負は引き分け")
                }
                let titleColor = outcome == .loss ? Theme.coralText : Theme.tealText
                Image(systemName: icon)
                    .scaledFont(24)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .themeBody(16, weight: .bold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(titleColor)
                    if model.format == .single {
                        Text(tr("単発戦の結果：勝ち %@", tr("%lld点", model.points)))
                            .themeCaption(12, weight: .medium, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.inkSubText)
                    } else {
                        Text(tr("%1$lld回勝負の結果：勝ち %2$@", BlackjackModel.roundsPerMatch, tr("%lld点", model.points)))
                            .themeCaption(12, weight: .medium, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.inkSubText)
                        Text(tr("勝ち %lld回", model.handsWon))
                            .themeCaption(12, weight: .medium, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.inkSubText)
                        Text(tr("この勝負の最高連勝 %lld", model.bestStreak))
                            .themeCaption(12, weight: .medium, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.inkSubText)
                    }
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            RecordLabel(model.recordResult)

            HStack(spacing: 12) {
                // 「遊び方を選ぶ」は配る前に戻る（10 回勝負と単発戦を切り替えられる・#2860）。
                actionButton(tr("遊び方を選ぶ"), role: .skip, disabled: nextLocked) {
                    model.restartMatch()
                }
                actionButton(model.format == .single ? tr("もう一度 単発戦") : tr("もう一度%lld回勝負", BlackjackModel.roundsPerMatch),
                             role: .primary, disabled: nextLocked) {
                    let format = model.format
                    model.restartMatch()
                    model.deal(format: format)
                }
            }
        }
        .modifier(NextUnlock(locked: $nextLocked, duration: BlackjackMotion.nextButtonLockDuration,
                             reduceMotion: reduceMotion))
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
    /// 破線の色。フェルトの上は白系、白い札の上（配牌前の説明）は地の上の色（#2531）。
    @Environment(\.cardTableInk) private var ink

    private var metrics: PlayingCardMetrics {
        PlayingCardMetrics.standard.scaled(by: layout.elementScale)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .strokeBorder(ink.slotStroke,
                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: metrics.width, height: metrics.height)
    }
}

// MARK: - Scoring Rules Sheet

/// 対局中にナビバーから開く点数のルール（#2596）。配る前の説明と同じ文言を再利用する。
struct BlackjackScoringRulesSheet: View {
    var body: some View {
        YakuTableSheet(title: tr("点数のルール")) {
            YakuTableSection {
                Text(tr("21 に近いほうが勝ち。勝てば 1 点、ブラックジャックで勝てば 2 点。ディーラーは 17 以上で止まります。"))
                    .themeBody(13, weight: .medium)
                    .foregroundStyle(Theme.ink)
                Text(tr("引き分け・バストは 0 点。引き分けでも連勝は途切れます。"))
                    .themeBody(13, weight: .medium)
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

/// 現れてから `duration` 秒のあいだ `locked` を真にし、過ぎたら偽にする（#2701）。Reduce Motion では演出が無いので待たない。
private struct NextUnlock: ViewModifier {
    @Binding var locked: Bool
    let duration: TimeInterval
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .task {
                locked = !reduceMotion
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled { locked = false }
            }
            .onDisappear { locked = true }
    }
}
