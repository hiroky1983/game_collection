import SwiftUI
import Core

/// スピード（#1323）のプレイ画面。
///
/// レイアウトパターン A（全画面・会長 QA 2026-10-23・#2531）: フェルトを画面全体に敷き、ヘッダーは 1 行
/// （戻る・スピード・？・新規）、バナーは画面最下部。上から 速さと記録の帯 → CPU の手札と山札 → 台札 2 山 →
/// あなたの手札と山札 → 操作 → 遊び方の 1 行 → レコメンド。台札とあなたの手札は近めに置き、払う距離を短くする。
///
/// 操作はスワイプ前提（会長 QA 2026-10-23）: 手札の札を出したい台札のほうへ払うと、その台札に出す（判定は `SpeedSwipe`）。
/// ドラッグ中は札が指についてきて、台札の上で離しても出せる。手札は 4 枚の位置が動かない（出した位置に補充し、山札が尽きても空けたまま）。
///
/// 通常の操作では、タップで札を出せない（会長 QA 2026-10-24・build 52「タップで押せると『はやい』でも勝てる」）。
/// 手札のタップは札を少し持ち上げて戻し、1 局に 1 回だけ「台札のほうへ払って出します」と出す。台札のタップも何もしない。
/// VoiceOver・スイッチコントロールを使っているときだけ、今までのタップ・アクションの操作（置ける台札が 1 つならそこへ、
/// 2 つなら選んで台札のタップを待つ）を残す。
///
/// CPU の待ちは Model が返す時間を `.task(id: model.cpuRun)` で待つだけ。場が動くたびに `cpuRun` が進んで
/// 前の待ちが止まり、画面を離れれば `.task` ごと止まる（`Timer` は持たない）。
public struct SpeedView: View {
    @State private var model: SpeedModel
    private let services: GameServices
    /// 負けそうなときに CPU を休ませる救済（広告 1 本で 1 ゲーム 1 回）。
    @State private var timeoutRescue = RewardedRescue()
    @State private var showSetup: Bool
    /// 進行中に右上の新規を押したときの確認（#2370）。
    @State private var showConfirmNewGame = false
    /// 手札 4 枠の並び（札の ID。空いた枠は nil）。出した札の枠を動かさないために View が持つ。
    @State private var slots: [Int?] = Array(repeating: nil, count: SpeedRules.handSize)
    /// `slots` を並べたゲームの通し番号。
    @State private var slotsGame = 0
    /// 札・台札の枠（卓の座標空間）。払った向きと台札の上かの判定に使う。
    @State private var frames: [SpeedSlot: CGRect] = [:]
    /// 指についてくる札。指の位置は `dragLocation` が持つ（卓の本体が指の動きを購読しないように・#521）。
    @State private var lifted: SpeedLift?
    /// 指が触れているあいだだけ true。ジェスチャが取り消された（`onEnded` が来ない）ときも OS が false に戻すので、
    /// 指についた札が残らないよう、これが false になったら持ち上げを解く。
    @GestureState private var isTouching = false
    @State private var dragLocation = CardDragLocation()
    /// 台札へ飛ぶ / 元の位置へ跳ね返る途中の札。
    @State private var flights: [SpeedFlight] = []
    /// 指でタップされて少し持ち上がっている札（すぐ戻る）。タップでは札を出さない代わりの小さな反応。
    @State private var nudgedID: Int?
    /// 支援機能（VoiceOver・スイッチコントロール）を使っているか。使っているときだけタップで札を出せる。
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    /// 画面の広さ（#458）。札と同じ倍率で拡大するために読む。
    @Environment(\.adaptiveLayout) private var layout
    /// バックグラウンドへ移ったら CPU を止める（アクション枠の基盤規約「即一時停止」。ブロック崩し・チャリンコおじさんと同じ）。
    @Environment(\.scenePhase) private var scenePhase

    /// 札・台札の枠と、持ち上げた札・飛ぶ札を同じ座標で扱う空間。
    private static let tableSpace = "speedTable"

    public init(services: GameServices) {
        self.services = services
        let model = SpeedModel(services: services)
        #if DEBUG
        // 撮影・動作確認用: `-speedScenario playing|both|stuck|timeout|win|lose` で局面を差し替える。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-speedScenario"), i + 1 < args.count {
            model.applyDebugScenario(args[i + 1])
        }
        #endif
        _model = State(initialValue: model)
        _slots = State(initialValue: SpeedHandLayout.arrange(previous: [], hand: model.humanHand.map(\.id)))
        _slotsGame = State(initialValue: model.gameSerial)
        // まだ 1 ゲームも始めていなければ速さのシートから入る。撮影で局面を差し替えたときは畳んだまま
        // （`.task` で開くとシートの提示と競合する）。
        _showSetup = State(initialValue: model.phase == .idle)
    }

    public var body: some View {
        GeometryReader { geometry in
            let metrics = SpeedTableLayout.metrics(contentSize: geometry.size, elementScale: layout.elementScale)
            VStack(spacing: SpeedTableLayout.spacing) {
                statsBar
                if model.phase == .result {
                    // 結果の札は中身の高さで止め、余りは札の下に空ける（いろリレー #2393 と同じ）。
                    VStack(spacing: 0) {
                        resultCard
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                } else {
                    table(metrics)
                        .transition(.opacity)
                }
                // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
                HowToPlayHint(.speed, playLog: services.playLog)
                // ボタン 2 段ぶん（めくる・タイム）を取っておき上詰め（ボタンの出入りで手札が動かない）。
                actionArea
                    .frame(minHeight: SpeedTableLayout.actionMinHeight, alignment: .top)
                RecommendationSlot(services: services, isFinished: model.phase == .result, ladder: ladder)
            }
            // 局面 → リザルトの差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
            .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
            // 左右は全画面の枠の値（8pt）。上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
            .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
            .padding(.vertical, SpeedTableLayout.verticalInset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        // 右上の新規（#2370）。途中なら確認を挟んで、速さのシート（共通の開始シート・初期選択は前回の速さ）から始める
        // （会長 QA 2026-10-23「＋ともう一個ボタンあるけど、これ同じじゃね？」で以前の「速さ」ボタンを統合）。
        // 広告の視聴中は塞ぐ（始め直すと見終えた広告のタイムが局ガードで弾かれて見損になる）。
        .gameChrome(title: tr("スピード"), review: services.review, fullScreen: .felt, ads: services.ads,
                    newGame: GameChromeNewGame(.match, isDisabled: timeoutRescue.isWatching) {
                        if model.hasProgressToLose {
                            showConfirmNewGame = true
                        } else {
                            showSetup = true
                        }
                    })
        // シートを開いているあいだも CPU は止める（背面で出し切ると、読んでいる間に敗北が記録される。#1358）。
        .howToPlay(HowToPlayGuide.speed.illustrated(SpeedHowToFigures.items).onboarding(SpeedOnboarding.guide), onPresent: { model.holdCPU(.sheet, true) }, onDismiss: { model.holdCPU(.sheet, false) }) {
            SpeedRuleSheet()
        }
        .sheet(isPresented: $showSetup) {
            SpeedSetupSheet(initial: model.settings) { settings in
                showSetup = false
                withGameAnimation { model.start(settings) }
            } onCancel: {
                showSetup = false
            }
        }
        // タイムの提示（#780）。負けそうでボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(timeoutRescue, for: .revival, isPresented: model.canUseTimeout,
                     services: services, gameID: SpeedModel.gameID)
        .rewardedRescueAlerts(
            timeoutRescue,
            notEarned: tr("タイムを取れませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("タイムを取れませんでした"),
                message: tr("広告を見ているあいだにゲームが終わったか、負けそうな局面ではなくなったため、タイムを取れませんでした。")
            )
        )
        // 広告の視聴中とバックグラウンドでは CPU を止める。あなたが触れないあいだに CPU だけが出し切ると、
        // 見終えた広告のタイムが局ガードで弾かれて見損になる（verifier 指摘・PR #1345）。
        .onChange(of: timeoutRescue.isWatching) { _, watching in
            model.holdCPU(.ad, watching)
        }
        .onChange(of: scenePhase) { _, phase in
            model.holdCPU(.inactive, phase != .active)
        }
        // 速さのシートも同じ（開いたまま置くと背面で CPU が出し続ける）。閉じたら再開する。
        .onChange(of: showSetup) { _, open in
            model.holdCPU(.sheet, open)
        }
        // 出した札の枠に補充の札を入れ、山札が尽きたら枠を空けたままにする（4 枚の位置を動かさない）。
        // 新しいゲームでは前の並びを引き継がず、配った順に並べ直す。
        .onChange(of: model.humanHand) { _, hand in
            let fresh = slotsGame != model.gameSerial
            slotsGame = model.gameSerial
            slots = SpeedHandLayout.arrange(previous: fresh ? [] : slots, hand: hand.map(\.id))
            if let lifted, !hand.contains(lifted.card) { self.lifted = nil }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規対局しますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規対局"), role: .destructive) { showSetup = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると対局データが失われます。"))
            }
        }
        // 払いが取り消された（`onEnded` が来ない）ときも、指についた札を残さない。
        .onChange(of: isTouching) { _, touching in
            if !touching { lifted = nil }
        }
        // 確認を出しているあいだも CPU は止める（迷っているうちに出し切られて負けが記録される、を防ぐ）。
        .onChange(of: showConfirmNewGame) { _, open in
            model.holdCPU(.sheet, open)
        }
        // CPU の待ちは Model が決め、ここは待つだけ。場が動くたびに `cpuRun` が進んで前のループが止まり、
        // 画面を離れれば `.task` ごと止まる。
        .task(id: model.cpuRun) { await runCPU() }
        // 出せる札の案内（5 秒）。あなたの操作・場が動く・CPU を止める / 解くたびに番号が進み、数え直す。
        .task(id: model.navigationEpoch) { await runPlayableNavigation() }
        // 「台札のほうへ払って出します」の一言は少し出して消す。
        .task(id: model.isShowingSwipeTip) {
            guard model.isShowingSwipeTip else { return }
            do { try await Task.sleep(for: SpeedTableLayout.swipeTipDuration) } catch { return }
            withGameAnimation(.easeInOut(duration: 0.2)) { model.dismissSwipeTip() }
        }
    }

    /// 支援機能を使っているか。使っていれば指のタップも今までどおり札を出す操作として扱う。
    private var assistive: Bool { voiceOverEnabled || switchControlEnabled }

    /// 案内を出すまで待つ。番号が変わったら新しい `.task` に譲って抜ける。
    private func runPlayableNavigation() async {
        let epoch = model.navigationEpoch
        while !Task.isCancelled, model.navigationEpoch == epoch, let wait = model.playableNavigationWait() {
            do { try await Task.sleep(for: wait) } catch { return }
            guard !Task.isCancelled, model.navigationEpoch == epoch else { return }
            withGameAnimation(.easeInOut(duration: 0.25)) { model.updatePlayableNavigation() }
        }
    }

    /// 同じ `cpuRun` のあいだだけ CPU を回す。場が動いて番号が変わったら、新しい `.task` に譲って抜ける
    /// （SwiftUI のキャンセルが届く前に同じループが 2 度動かないよう、番号でも見張る）。
    private func runCPU() async {
        let run = model.cpuRun
        while !Task.isCancelled, model.cpuRun == run, let wait = model.nextCPUWait() {
            do { try await Task.sleep(for: wait) } catch { return }
            guard !Task.isCancelled, model.cpuRun == run else { return }
            let hand = model.cpuHand
            let tops = model.tops
            withGameAnimation { model.performCPUAction() }
            flyCPUPlay(hand: hand, tops: tops)
            flyCPURefill(before: hand)
        }
    }

    // MARK: - 速さと記録の帯

    private var statsBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("CPU の速さ")).themeCaption(11).foregroundStyle(Theme.inkSubText)
                Text(model.settings.level.label)
                    .themeBody(15)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            stat(tr("連勝"), value: "\(model.streak)")
            if let best = model.bestSeconds {
                stat(tr("最速"), value: tr("%lld秒", best))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .popCard(corner: Theme.cornerSmall)
    }

    private func stat(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title).themeCaption(11).foregroundStyle(Theme.inkSubText)
            Text(verbatim: value)
                .scaledFont(20, weight: .heavy, design: .rounded).monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 卓（CPU・台札・あなた）

    /// CPU の段・台札・あなたの手札を 1 つのまとまりにして、帯と操作のあいだに置く。
    /// 縦の余りは CPU の段の上と、CPU と台札のあいだに配る。台札とあなたの手札は近いまま（払う距離を短く）、
    /// 手札は操作の段のすぐ上（親指の届く下寄り）に置く。
    private func table(_ metrics: SpeedTableLayout.Metrics) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            cpuArea(metrics)
            Spacer(minLength: SpeedTableLayout.cpuGap)
            pilesArea(metrics)
            handArea(metrics)
                .padding(.top, SpeedTableLayout.handGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 指の位置・台札の枠・飛ぶ札をすべて同じ座標で扱う。
        .coordinateSpace(name: Self.tableSpace)
        .onPreferenceChange(CardDropFramesKey<SpeedSlot>.self) { frames = $0 }
        .overlay(alignment: .topLeading) { motionLayer(metrics) }
    }

    // MARK: - CPU

    private func cpuArea(_ metrics: SpeedTableLayout.Metrics) -> some View {
        let cpuMetrics = metrics.cpuCard
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .scaledFont(12, weight: .bold)
                    .foregroundStyle(model.isTimeoutActive ? Theme.inkSubText : Theme.coralText)
                Text(model.isTimeoutActive ? tr("タイム中") : "CPU")
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(width: layout.scaled(SpeedTableLayout.cpuChipWidth))
            .background(Capsule().fill(Theme.surface))
            .shadow(color: Theme.cardShadow, radius: 3, y: 1)
            HStack(spacing: SpeedTableLayout.cpuCardSpacing) {
                ForEach(model.cpuHand) { card in
                    SpeedCardView(card: card, metrics: cpuMetrics)
                        // 山札から滑ってくる途中の補充の札は、着くまで見せない。
                        .opacity(isDealing(card) ? 0 : 1)
                        // 出した札を台札へ飛ばす起点（中心だけ使う。出入りの拡大縮小でも中心は動かない）。
                        .cardDropTarget(SpeedSlot.cpu(card.id), in: Self.tableSpace)
                        .id(card.id)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .gameAnimation(.easeInOut(duration: 0.18), value: model.cpuHand)
            .cardDropTarget(SpeedSlot.cpuRow, in: Self.tableSpace)
            Spacer(minLength: 0)
            SpeedStockView(metrics: cpuMetrics, count: model.cpuStock.count)
                .cardDropTarget(SpeedSlot.cpuStock, in: Self.tableSpace)
        }
        // CPU 側は「何を持っていて山があと何枚か」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpeedAccessibility.cpuHandLabel(model.cpuHand, stockCount: model.cpuStock.count))
    }

    // MARK: - 台札

    private func pilesArea(_ metrics: SpeedTableLayout.Metrics) -> some View {
        HStack(spacing: metrics.pileSpacing) {
            ForEach(0..<SpeedRules.pileCount, id: \.self) { index in
                pileView(index, metrics: metrics.pileCard)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpeedTableLayout.pileVerticalPadding)
        .overlay(alignment: .top) {
            if model.isStuck {
                Text(tr("どちらも出せない！"))
                    .scaledFont(11, weight: .black, design: .rounded)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Fill.yellow))
                    .offset(y: -8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .gameAnimation(.easeInOut(duration: 0.18), value: model.isStuck)
        // 手札をタップしたときの一言（1 局に 1 回）。支援機能では出ない（タップで出せるため）。
        .overlay(alignment: .bottom) {
            if model.isShowingSwipeTip {
                Label(tr("台札のほうへ払って出します"), systemImage: "hand.draw.fill")
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.surface))
                    .shadow(color: Theme.cardShadow, radius: 3, y: 1)
                    .offset(y: 6)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.isShowingSwipeTip)
    }

    private func pileView(_ index: Int, metrics: PlayingCardMetrics) -> some View {
        let top = model.tops[index]
        let selected = model.selectedCard
        // 選んだ札を置ける台札・持ち上げた札を置ける台札（ヒントがオンのとき）を縁で示す。
        let accepts: Bool = {
            if let selected { return SpeedRules.canPlay(selected, onto: top) }
            if let lifted, model.showsHints { return SpeedRules.canPlay(lifted.card, onto: top) }
            return false
        }()
        return Button { fingerTapPile(index) } label: {
            ZStack {
                CardSlot(metrics: metrics, systemImage: "arrow.down.to.line")
                // 上の数枚を重ねて置く。飛んでくる札が着くまでのあいだも下の札が見えたままになり、
                // 台札が空いて見えたり急に差し替わったりしない（会長 QA 2026-10-23）。
                ForEach(model.piles[index].suffix(3)) { card in
                    // 台札へ飛んでいる途中の札は、着くまで台札の側では見せない（同じ札が 2 枚見えないように）。
                    let arriving = flights.contains { $0.card.id == card.id && $0.isToPile }
                    SpeedCardView(card: card, metrics: metrics, highlighted: card == top && accepts)
                        .opacity(arriving ? 0 : 1)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(width: metrics.width, height: metrics.height)
            // 出せる札の案内（5 秒何もしなかったとき）。この台札に置ける手札があれば光らせる。
            .overlay {
                if model.playableNavigationPiles.contains(index) {
                    SpeedNavigationRing(cornerRadius: metrics.cornerRadius)
                }
            }
            .cardDropTarget(SpeedSlot.pile(index), in: Self.tableSpace)
            // 見える札はそのまま、タップ判定だけを左右に広げる。
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gameAnimation(.easeOut(duration: 0.15), value: top)
        .accessibilityIdentifier("speed.pile.\(index)")
        .accessibilityLabel(SpeedAccessibility.pileLabel(index: index, top: top))
        .accessibilityHint(selected == nil ? tr("この台札に置ける手札が1枚だけならダブルタップで出します") : tr("ダブルタップで選択中の札を置きます"))
    }

    // MARK: - 手札

    private func handArea(_ metrics: SpeedTableLayout.Metrics) -> some View {
        let playable = model.humanPlayableIDs
        let showsHints = model.showsHints
        let handMetrics = metrics.handCard
        return HStack(spacing: SpeedHandLayout.spacing) {
            ForEach(Array(slots.enumerated()), id: \.offset) { position, id in
                ZStack {
                    if let id, let card = model.humanHand.first(where: { $0.id == id }) {
                        handCard(card, position: position, metrics: handMetrics,
                                 isPlayable: playable.contains(card.id), showsHints: showsHints)
                    } else {
                        // 山札が尽きて空いた枠。ほかの札を寄せない（狙った札の位置が動かない）。
                        CardSlot(metrics: handMetrics)
                            .frame(width: handMetrics.width, height: handMetrics.height)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: handMetrics.width, height: handMetrics.height)
                .cardDropTarget(SpeedSlot.handSlot(position), in: Self.tableSpace)
                // 札の枠は、補充の札の `.transition(.scale)` の外（動かない枠）で測る。札の側で測ると、出てきた瞬間の
                // ほぼ 0 倍に縮んだ枠（幅 0.0007pt）が残り、台札へ飛ぶ札の倍率が 14 万倍になって画面全体が白く光った
                // （会長 QA 2026-10-23「スピードの画面がチカチカフラッシュする」）。
                .background {
                    // 選択中の札は 8pt 浮かせて見せているので、測る枠もそろえる（払いのつかみ位置・飛び始めの位置）。
                    if let id {
                        Color.clear
                            .offset(y: model.selectedID == id ? SpeedHandLayout.selectedLift : 0)
                            .cardDropTarget(SpeedSlot.hand(id), in: Self.tableSpace)
                    }
                }
            }
            SpeedStockView(metrics: handMetrics, count: model.humanStock.count)
                .cardDropTarget(SpeedSlot.humanStock, in: Self.tableSpace)
                .accessibilityLabel(SpeedAccessibility.stockLabel(of: .human, count: model.humanStock.count))
        }
        .frame(maxWidth: .infinity)
        // 出した札が消える / 補充される変化を演出する。
        .gameAnimation(.easeInOut(duration: 0.18), value: model.humanHand)
    }

    private func handCard(_ card: SpeedCard, position: Int, metrics: PlayingCardMetrics,
                          isPlayable: Bool, showsHints: Bool) -> some View {
        let isSelected = model.selectedID == card.id
        let isAway = lifted?.card.id == card.id || flights.contains { $0.card.id == card.id && !$0.isToPile }
        return SpeedCardView(
            card: card, metrics: metrics, selected: isSelected,
            highlighted: showsHints && isPlayable && !isSelected,
            dimmed: showsHints && !isPlayable && !isSelected && model.phase == .playing
        )
        // 出せる札の案内（5 秒何もしなかったとき）。
        .overlay {
            if model.playableNavigationCardIDs.contains(card.id) {
                SpeedNavigationRing(cornerRadius: metrics.cornerRadius)
            }
        }
        .offset(y: isSelected ? SpeedHandLayout.selectedLift : (nudgedID == card.id ? SpeedHandLayout.nudgeLift : 0))
        .gameAnimation(.spring(response: 0.2), value: isSelected)
        // 持ち上げている間・跳ね返って戻る途中は、元の位置を空けておく（札は指 / 飛ぶ札の側で見せる）。
        .opacity(isAway ? 0 : 1)
        .contentShape(Rectangle())
        .gesture(swipeGesture(card))
        .id(card.id)
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("speed.hand.\(position)")
        .accessibilityLabel(SpeedAccessibility.handCardLabel(card, isSelected: isSelected, isPlayable: isPlayable))
        .accessibilityHint(tr("ダブルタップで台札に出します"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tapHandCard(card) }
    }

    // MARK: - スワイプ

    /// 手札 1 枚の払い。指が `SpeedSwipe.tapSlop` 動いたら持ち上げて指につけ、離した瞬間の動いた量と速さで判定する。
    /// 時刻は使わない（速さは OS の `velocity` を読む。柵越えおじさんの `DragGesture` の時刻の事故の再発防止）。
    private func swipeGesture(_ card: SpeedCard) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.tableSpace))
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                guard model.phase == .playing else { return }
                // 2 本目の指: ほかの札を持ち上げているあいだは、この札のジェスチャは何もしない
                // （指の位置を書き換えて持ち上げた札を奪わない。CodeRabbit 指摘・PR #2720）。
                if let lifted, lifted.card.id != card.id { return }
                if lifted == nil {
                    let moved = hypot(value.translation.width, value.translation.height)
                    guard moved >= SpeedSwipe.tapSlop, let frame = frames[.hand(card.id)] else { return }
                    model.clearSelection()
                    // 払い始めた = 操作した。出ている案内を消して 5 秒を数え直す。
                    model.noteHumanActivity()
                    // 位置を先に入れる。持ち上げた最初の 1 フレームから正しい場所に出す。
                    dragLocation.point = value.location
                    lifted = SpeedLift(card: card, grab: CGSize(width: value.startLocation.x - frame.minX,
                                                                height: value.startLocation.y - frame.minY))
                } else {
                    // 卓の本体の `@State` は触らない（#521）。読むのは指につく札だけ。
                    dragLocation.point = value.location
                }
            }
            .onEnded { value in
                // ほかの札を持ち上げているあいだに離した 2 本目の指は無視する（持ち上げた札の操作を横取りしない）。
                if let lifted, lifted.card.id != card.id { return }
                lifted = nil
                guard model.phase == .playing, let frame = frames[.hand(card.id)] else { return }
                let outcome = SpeedSwipe.resolve(
                    cardCenter: CGPoint(x: frame.midX, y: frame.midY),
                    translation: value.translation,
                    velocity: value.velocity,
                    pileFrames: pileFrames,
                    playable: Set(model.playableTargets(for: card))
                )
                let release = CGPoint(x: frame.midX + value.translation.width, y: frame.midY + value.translation.height)
                apply(outcome, card: card, release: release, home: frame)
            }
    }

    private var pileFrames: [Int: CGRect] {
        var result: [Int: CGRect] = [:]
        for case (.pile(let index), let frame) in frames { result[index] = frame }
        return result
    }

    private func apply(_ outcome: SpeedSwipe.Outcome, card: SpeedCard, release: CGPoint, home: CGRect) {
        switch outcome {
        case .tap:
            fingerTapHandCard(card)
        case .play(let pile):
            if model.swipeCard(card, onto: pile) {
                fly(card, from: release, toPile: pile)
                flyHumanRefill()
            } else {
                bounce(card, from: release, home: home)
            }
        case .miss(let pile):
            // 出せない台札を狙った: 警告（ペナルティは無い）を鳴らして元の位置へ跳ね返す。
            model.swipeCard(card, onto: pile)
            bounce(card, from: release, home: home)
        case .cancel:
            bounce(card, from: release, home: home)
        }
    }

    /// 手札の指のタップ。通常の操作では札を出さず、持ち上げて戻す反応と 1 局に 1 回の一言だけ。
    /// 支援機能を使っているときは `tapHandCard`（今までのタップの操作）に渡す。
    private func fingerTapHandCard(_ card: SpeedCard) {
        if assistive {
            tapHandCard(card)
            return
        }
        guard case .nudged = model.fingerTapHandCard(card, assistive: false) else { return }
        nudge(card)
    }

    /// 札を少し持ち上げて戻す（タップで出せないことを、何も起きない故障に見せない）。
    private func nudge(_ card: SpeedCard) {
        withGameAnimation(.spring(response: 0.12, dampingFraction: 0.7)) { nudgedID = card.id }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard nudgedID == card.id else { return }
            withGameAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { nudgedID = nil }
        }
    }

    /// 手札のタップ（支援機能の操作・アクション）。置ける台札が 1 つならそこへ飛ばし、2 つなら選んで台札のタップを待つ。
    private func tapHandCard(_ card: SpeedCard) {
        let targets = model.playableTargets(for: card)
        let home = frames[.hand(card.id)]
        model.tapHandCard(card)
        if targets.count == 1, let home, model.tops[targets[0]] == card {
            fly(card, from: CGPoint(x: home.midX, y: home.midY), toPile: targets[0])
            flyHumanRefill()
        }
    }

    /// 台札のタップ。通常の操作では何もしない。支援機能を使っているとき（か、支援機能で札を選んであるとき）は、
    /// 選んだ札（無ければ、その台札に置けるただ 1 枚）を置く。
    private func fingerTapPile(_ index: Int) {
        let card = model.selectedCard ?? {
            let candidates = model.humanHand.filter { SpeedRules.canPlay($0, onto: model.tops[index]) }
            return candidates.count == 1 ? candidates[0] : nil
        }()
        let home = card.flatMap { frames[.hand($0.id)] }
        var handled = false
        withGameAnimation { handled = model.fingerTapPile(index, assistive: assistive) }
        if handled, let card, let home, model.tops[index] == card {
            fly(card, from: CGPoint(x: home.midX, y: home.midY), toPile: index)
            flyHumanRefill()
        }
    }

    /// 札を台札 `pile` へ飛ばす。`fromScale` は飛び始めの大きさ（手札の札に対する倍率。CPU の札は小さい）。
    private func fly(_ card: SpeedCard, from: CGPoint, toPile pile: Int, fromScale: CGFloat = 1) {
        guard let target = pileFrames[pile] else { return }
        // 台札の札は手札の札より大きいので、着くまでに台札の大きさへそろえる（倍率は飛ぶ札の側で寸法から決める）。
        flights.append(SpeedFlight(card: card, from: from, to: CGPoint(x: target.midX, y: target.midY),
                                   fromScale: fromScale, toWidth: target.width, isToPile: true))
    }

    /// CPU が出した札を、CPU の手札の位置から台札へ飛ばす（会長 QA 2026-10-23「相手が出したアニメーションが無く、
    /// 急に札が入れ替わったように感じる」）。自分が払ったときと同じ飛び方・速さ。音は鳴らさない（CPU の着手は無音の決まり）。
    /// 出す前の CPU の手札 `hand` と台札 `tops` を比べ、台札に増えた札が CPU の手札にあったものなら飛ばす。
    private func flyCPUPlay(hand: [SpeedCard], tops: [SpeedCard?]) {
        for (index, top) in model.tops.enumerated() where index < tops.count && top != tops[index] {
            guard let top, hand.contains(top), let frame = frames[.cpu(top.id)] else { continue }
            fly(top, from: CGPoint(x: frame.midX, y: frame.midY), toPile: index, fromScale: SpeedTableLayout.cpuCardRatio)
        }
    }

    /// 補充の札を飛ばしている途中か（着くまで手札・CPU の札の側では見せない）。
    private func isDealing(_ card: SpeedCard) -> Bool {
        flights.contains { $0.card.id == card.id && $0.isDeal }
    }

    /// 自分が札を出した直後、手札に補充された札を山札から空いた枠へ滑らせる（#2955）。
    /// `slots` はまだ補充前の並びなので、`arrange` で補充後の枠を先に求める。Reduce Motion では滑らせない。
    private func flyHumanRefill() {
        guard !Motion.isReduceMotionEnabled, let stock = frames[.humanStock] else { return }
        let ids = model.humanHand.map(\.id)
        let next = SpeedHandLayout.arrange(previous: slots, hand: ids)
        for card in model.humanHand where !slots.contains(card.id) {
            guard let position = next.firstIndex(of: card.id), let slot = frames[.handSlot(position)] else { continue }
            flights.append(SpeedFlight(card: card, from: CGPoint(x: stock.midX, y: stock.midY),
                                       to: CGPoint(x: slot.midX, y: slot.midY), isToPile: false,
                                       isDeal: true, toScale: 1))
        }
    }

    /// CPU が札を出した直後、CPU の手札に補充された札を CPU の山札から並びの端へ滑らせる（#2955）。
    /// 着く先は、並びの左端（枚数が変わっても動かない）から札の幅と間隔で数えた位置。
    private func flyCPURefill(before hand: [SpeedCard]) {
        guard !Motion.isReduceMotionEnabled, let stock = frames[.cpuStock], let row = frames[.cpuRow] else { return }
        let before = Set(hand.map(\.id))
        let width = stock.width
        for (index, card) in model.cpuHand.enumerated() where !before.contains(card.id) {
            let x = row.minX + (width + SpeedTableLayout.cpuCardSpacing) * CGFloat(index) + width / 2
            flights.append(SpeedFlight(card: card, from: CGPoint(x: stock.midX, y: stock.midY),
                                       to: CGPoint(x: x, y: stock.midY), fromScale: SpeedTableLayout.cpuCardRatio,
                                       isToPile: false, isDeal: true, toScale: SpeedTableLayout.cpuCardRatio))
        }
    }

    private func bounce(_ card: SpeedCard, from: CGPoint, home: CGRect) {
        let to = CGPoint(x: home.midX, y: home.midY)
        // ほとんど動いていなければ跳ね返しの演出は要らない。
        guard hypot(from.x - to.x, from.y - to.y) > 1 else { return }
        flights.append(SpeedFlight(card: card, from: from, to: to, isToPile: false))
    }

    /// 指につく札と、飛ぶ / 跳ね返る札。当たり判定は持たない。
    @ViewBuilder
    private func motionLayer(_ metrics: SpeedTableLayout.Metrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(flights) { flight in
                SpeedFlightView(flight: flight, metrics: metrics.handCard)
                    .task(id: flight.id) {
                        try? await Task.sleep(for: flight.lifetime)
                        flights.removeAll { $0.id == flight.id }
                    }
            }
            if let lifted {
                CardDragLayer(cards: [lifted.card], grab: lifted.grab, location: dragLocation, step: 0) { _, card in
                    SpeedCardView(card: card, metrics: metrics.handCard, highlighted: true)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 操作

    /// 勝ちが続いたら一段速い CPU を勧める（#722・#2806）。並びは開始シートの速さと同じ。
    private var ladder: DifficultyLadderPrompt? {
        let levels = SpeedLevel.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: levels.firstIndex(of: model.settings.level),
                                      levelLabels: levels.map(\.label)) { index in
            withGameAnimation { model.start(SpeedSettings(level: levels[index])) }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            Button { showSetup = true } label: {
                Text(tr("はじめる")).themeBody(18).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            .padding(.horizontal, 24)
        case .playing:
            VStack(spacing: 8) {
                if model.canFlip {
                    actionButton(flipTitle, color: Theme.Fill.coral) {
                        model.flipStocks()
                    }
                } else {
                    // フェルトの上なので卓の上の文字色（白系）で出す。
                    CardTableInkReader { ink in
                        Text(statusText)
                            .themeBody(14)
                            .foregroundStyle(ink.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
                if model.canUseTimeout {
                    timeoutButton
                }
            }
            .gameAnimation(.easeInOut(duration: 0.18), value: model.canFlip)
            .accessibilityElement(children: .contain)
        case .result:
            VStack(spacing: 10) {
                Button { withGameAnimation { model.restart() } } label: {
                    Label(tr("もう一回"), systemImage: "arrow.counterclockwise.circle.fill")
                        .themeBody(17).frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                Button { showSetup = true } label: {
                    Text(tr("速さを変える")).themeBody(15).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).tint(Theme.coralText)
                .background(Theme.surface, in: Capsule())
            }
            .padding(.horizontal, 24)
        }
    }

    /// 「めくる」の文言。山札が尽きた人はめくらないので、残っている山札に合わせて言い分ける。
    private var flipTitle: String {
        switch (model.humanStock.isEmpty, model.cpuStock.isEmpty) {
        case (false, false): return tr("めくる（両方の山札から1枚ずつ）")
        case (true, true):   return tr("めくる（台札を切り直す）")
        default:             return tr("めくる（山札が残っている側だけ）")
        }
    }

    private var statusText: String {
        SpeedAccessibility.statusLabel(
            phase: model.phase, isStuck: model.isStuck, hasSelection: model.selectedID != nil,
            winner: model.winner, isDraw: model.isDraw
        )
    }

    /// 負けそうなときだけ出す「広告を見てタイム」（#1323）。1 ゲーム 1 回。
    private var timeoutButton: some View {
        Button {
            // 視聴完了（報酬獲得）したときだけ休ませる。どのゲームに対するものかを広告の前に控え、
            // 視聴中にゲームが変わっていたら乗せない（#729）。
            let serial = model.gameSerial
            timeoutRescue.request(
                services, gameID: SpeedModel.gameID, purpose: .revival,
                guardedBy: .checkedByGrant
            ) {
                model.grantTimeoutAfterAd(forGame: serial)
            }
        } label: {
            Label(tr("広告を見てタイム（CPU が8秒休む）"), systemImage: "play.rectangle.fill")
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(timeoutRescue.isWatching ? Theme.inkSub.opacity(0.3) : Theme.Fill.teal,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(timeoutRescue.isWatching ? Theme.inkSubText : Theme.onAccent)
        }
        .buttonStyle(.pop)
        .disabled(timeoutRescue.isWatching)
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.pop)
    }

    // MARK: - リザルト

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.winner == .human ? "crown.fill" : "flag.checkered")
                    .scaledFont(20)
                    .foregroundStyle(model.winner == .human ? Theme.yellowText : Theme.inkSubText)
                Text(statusText)
                    .scaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle(model.winner == .human ? Theme.tealText : Theme.ink)
                Spacer()
            }
            VStack(spacing: 4) {
                resultRow(tr("あなた"), remaining: model.remaining(of: .human), isWinner: model.winner == .human)
                resultRow("CPU", remaining: model.remaining(of: .cpu), isWinner: model.winner == .cpu)
            }
            if let seconds = model.winSeconds {
                // 記録の 1 行（`RecordLabel`）は勝敗の指標なので秒数を出さない。最速を更新した回は
                // 「自己ベスト更新！」の中身がここで分かるように添える。
                Text(verbatim: model.recordResult?.update.seconds == true ? tr("所要 %lld秒（最速！）", seconds) : tr("所要 %lld秒", seconds))
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSubText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 「今回の結果」を上、「通算」を下に置く。
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    private func resultRow(_ name: String, remaining: Int, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isWinner ? tr("勝ち") : "　")  // i18n-keep: 行の高さをそろえる全角空白（文字としては読まれない）
                .scaledFont(12, weight: .black, design: .rounded)
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44)
                .padding(.vertical, 3)
                .background(Capsule().fill(isWinner ? Theme.Fill.yellow : Color.clear))
            Text(name)
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(name == tr("あなた") ? Theme.coralText : Theme.ink)
            Spacer()
            Text(remaining == 0 ? tr("出し切り") : tr("残り%lld枚", remaining))
                .scaledFont(12, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 卓の部品の状態

/// 卓の座標空間で枠を測る対象。
enum SpeedSlot: Hashable {
    /// 台札（0 = 左、1 = 右）。
    case pile(Int)
    /// 手札の札（札の ID）。
    case hand(Int)
    /// CPU の手札の札（札の ID）。出した札を飛ばす起点。
    case cpu(Int)
    /// 自分の山札・CPU の山札。補充の札が滑り出す起点。
    case humanStock
    case cpuStock
    /// 手札の枠（左から数えた位置。札の出入りで動かない）。補充の札が着く先。
    case handSlot(Int)
    /// CPU の札の並び全体。左端は札の枚数が変わっても動かないので、補充の札が着く先の計算に使う。
    case cpuRow
}

/// 指についている札と、つかんだ位置（札の左上からのずれ）。
struct SpeedLift: Equatable {
    let card: SpeedCard
    let grab: CGSize
}

/// 台札へ飛ぶ / 元の位置へ跳ね返る札（中心の位置で動かす）。
struct SpeedFlight: Identifiable, Equatable {
    let id = UUID()
    let card: SpeedCard
    let from: CGPoint
    let to: CGPoint
    /// 飛び始めの大きさ（手札の札に対する倍率。CPU の札は手札より小さい）。
    var fromScale: CGFloat = 1
    /// 着く先の札の幅（台札）。nil なら手札の大きさのまま（跳ね返り）。
    var toWidth: CGFloat?
    let isToPile: Bool
    /// 山札から手札へ滑る補充の札か（#2955）。着くまで手札の側では見せない。
    var isDeal = false
    /// 着いたときの倍率。nil なら `toWidth` から決める。
    var toScale: CGFloat?

    /// 台札へ・補充で滑る札か（すっと速く動く）。跳ね返りだけが別の動き。
    private var isSlide: Bool { isToPile || isDeal }

    /// 動きの長さ。台札へ・補充はすっと速く、跳ね返りはばねで少し揺らす（ミスの手応え）。
    var animation: Animation {
        isSlide ? .easeOut(duration: 0.14) : .spring(response: 0.26, dampingFraction: 0.55)
    }

    /// 動き終えて消すまでの時間（動きの長さに少し足す）。
    var lifetime: Duration { isSlide ? .milliseconds(170) : .milliseconds(380) }

    /// 台札へ飛ぶ札の着いたときの倍率（台札の枠の幅 ÷ 手札の札の寸法の幅）。以前は手札の札の**測った枠**で割っていて、
    /// 出てくる途中の札（`.transition(.scale)` でほぼ 0 倍）の枠だと 14 万倍になり、札の面が画面全体を覆って白く光った
    /// （会長 QA 2026-10-23「チカチカフラッシュする」）。寸法の幅で割り、台札の大きさの上限 `maxPileRatio` 倍までに抑える。
    static func pileScale(handWidth: CGFloat?, pileWidth: CGFloat?) -> CGFloat {
        guard let handWidth, let pileWidth, handWidth > 0, pileWidth > 0 else { return 1 }
        return min(max(pileWidth / handWidth, 1), SpeedTableLayout.maxPileRatio)
    }
}

/// 飛ぶ札 1 枚。出た瞬間に `from` から `to` へ動き出す（Reduce Motion ではすぐ着く）。
private struct SpeedFlightView: View {
    let flight: SpeedFlight
    let metrics: PlayingCardMetrics
    @State private var arrived = false

    var body: some View {
        SpeedCardView(card: flight.card, metrics: metrics)
            .scaleEffect(arrived ? (flight.toScale ?? SpeedFlight.pileScale(handWidth: metrics.width, pileWidth: flight.toWidth)) : flight.fromScale)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
            .position(arrived ? flight.to : flight.from)
            .onAppear {
                withGameAnimation(flight.animation) { arrived = true }
            }
    }
}

// MARK: - 寸法

/// 手札の並びの寸法。札 4 枚 + 山札 1 枚を横 1 列に置き、画面の幅いっぱいまで札を大きくする（払いやすく）。
enum SpeedHandLayout {
    static let spacing: CGFloat = 8
    /// 選択中の札を浮かせる量。
    static let selectedLift: CGFloat = -8
    /// 指でタップした札を持ち上げる量（すぐ戻す）。
    static let nudgeLift: CGFloat = -6
    /// 手札の札の幅の上限（iPhone の幅）。広い画面は `elementScale` 倍。
    static let maxCardWidth: CGFloat = 72
    /// 札の幅の下限（タップ標的の 44pt）。
    static let minCardWidth: CGFloat = 44

    /// 幅 `contentWidth`（画面の左右の余白の内側）に札 5 枚（手札 4 + 山札）を並べるときの札の幅。
    static func cardWidth(contentWidth: CGFloat, elementScale: CGFloat = 1) -> CGFloat {
        let fit = (max(0, contentWidth) - spacing * 4) / 5
        return max(minCardWidth, min(maxCardWidth * elementScale, fit.rounded(.down)))
    }

    /// 画面幅 `screenWidth` のときに、札 5 枚（手札 4 + 山札）が余白の内側に収まるか。
    static func fits(screenWidth: CGFloat) -> Bool {
        let available = screenWidth - FullScreenGameLayoutMetrics.sideInset * 2
        return cardWidth(contentWidth: available) * 5 + spacing * 4 <= available
    }

    /// 手札 4 枠の並び。残っている札は前と同じ枠に置き、新しい札（補充）は空いた枠に前から入れる。
    /// 山札が尽きて補充が無ければ枠は空いたまま（ほかの札を寄せない）。
    static func arrange(previous: [Int?], hand: [Int]) -> [Int?] {
        var slots = Array(previous.prefix(SpeedRules.handSize))
        slots += Array(repeating: nil, count: SpeedRules.handSize - slots.count)
        let present = Set(hand)
        slots = slots.map { id in id.flatMap { present.contains($0) ? $0 : nil } }
        let placed = Set(slots.compactMap { $0 })
        var incoming = hand.filter { !placed.contains($0) }[...]
        for index in slots.indices where slots[index] == nil {
            guard let next = incoming.popFirst() else { break }
            slots[index] = next
        }
        return slots
    }
}

/// 卓の縦の寸法。札の大きさを画面の高さから決める（View を組まずにテストできるよう純関数）。
enum SpeedTableLayout {
    /// 帯・卓・操作の段のあいだの間隔。
    static let spacing: CGFloat = 8
    /// 上下の余白（ヘッダーの余白 4 とバナーの帯の余白 8 に足す分）。
    static let verticalInset: CGFloat = 4
    /// 手札をタップしたときの一言（「台札のほうへ払って出します」）を出しておく時間。
    static let swipeTipDuration: Duration = .milliseconds(2500)
    /// 速さと記録の帯の高さの見積もり。
    static let statsHeight: CGFloat = 44
    /// 操作の段に取っておく高さ（ボタン 2 段: めくる・タイム）。
    static let actionMinHeight: CGFloat = 96
    /// CPU の段と台札のあいだの最小の間隔（余りはここと卓の上下に配る）。
    static let cpuGap: CGFloat = 16
    /// 台札とあなたの手札のあいだ（払う距離を短くするため詰める）。
    static let handGap: CGFloat = 6
    /// 台札の上下の余白（「どちらも出せない！」の札を重ねる分）。
    static let pileVerticalPadding: CGFloat = 10
    /// CPU の札（手札の札に対する比）。
    static let cpuCardRatio: CGFloat = 0.75
    static let cpuCardSpacing: CGFloat = 6
    static let cpuChipWidth: CGFloat = 64
    /// 台札の札の大きさの上限（手札の札に対する比）。台札は狙う的なので手札より大きく見せる。
    static let maxPileRatio: CGFloat = 1.4
    /// 縦の余りのうち台札を大きくするのに回す割合。
    static let pileShareOfRoom: CGFloat = 0.75
    /// 台札 2 山のあいだ。
    static let pileSpacing: CGFloat = 32
    struct Metrics {
        let handCard: PlayingCardMetrics
        let cpuCard: PlayingCardMetrics
        let pileCard: PlayingCardMetrics
        let pileSpacing: CGFloat
    }

    /// 札の縦横比（共通の札 62×90）。
    static var cardAspect: CGFloat { PlayingCardMetrics.standard.height / PlayingCardMetrics.standard.width }

    /// 盤に使える大きさ `contentSize`（全画面の枠のヘッダーとバナーの帯の内側）のときの寸法。
    /// GeometryReader は最初に大きさ 0 を渡すことがあるので、0 でも負にならない値を返す。
    static func metrics(contentSize: CGSize, elementScale: CGFloat = 1) -> Metrics {
        let contentWidth = max(0, contentSize.width - FullScreenGameLayoutMetrics.sideInset * 2)
        let handWidth = SpeedHandLayout.cardWidth(contentWidth: contentWidth, elementScale: elementScale)
        let pileWidth = pileCardWidth(contentHeight: contentSize.height, contentWidth: contentWidth, handWidth: handWidth)
        let standard = PlayingCardMetrics.standard
        return Metrics(
            handCard: standard.scaled(by: handWidth / standard.width),
            cpuCard: standard.scaled(by: handWidth * cpuCardRatio / standard.width),
            pileCard: standard.scaled(by: pileWidth / standard.width),
            pileSpacing: pileSpacing
        )
    }

    /// 台札の札の幅。縦の余り（帯・CPU・手札・操作の段と間隔を引いた残り）の `pileShareOfRoom` まで大きくし、
    /// 手札の札より小さくはしない・`maxPileRatio` 倍を超えない・2 山が横に収まる。
    static func pileCardWidth(contentHeight: CGFloat, contentWidth: CGFloat, handWidth: CGFloat) -> CGFloat {
        let handHeight = handWidth * cardAspect
        let cpuHeight = handWidth * cpuCardRatio * cardAspect
        let fixed = verticalInset * 2 + statsHeight + spacing * 2 + actionMinHeight
            + cpuHeight + cpuGap + pileVerticalPadding * 2 + handGap + handHeight
        let room = max(0, contentHeight - fixed)
        let byHeight = room * pileShareOfRoom / cardAspect
        let byWidth = (contentWidth - pileSpacing - 20 * 2) / 2
        return max(handWidth, min(handWidth * maxPileRatio, byHeight, byWidth))
    }
}

// MARK: - 札

/// 札 1 枚。外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。
struct SpeedCardView: View {
    let card: SpeedCard
    let metrics: PlayingCardMetrics
    var selected: Bool = false
    /// 出せる札・置ける台札の強調。
    var highlighted: Bool = false
    /// 出せない札は色に頼らず**明度**でも落として区別する。
    var dimmed: Bool = false

    private var border: Color {
        if selected { return Theme.coral }
        if highlighted { return Theme.teal }
        return Color.gray.opacity(0.2)
    }

    var body: some View {
        ZStack {
            PlayingCardSurface(
                faceUp: true,
                cornerRadius: metrics.cornerRadius,
                border: border,
                borderWidth: selected ? 2.5 : (highlighted ? 2 : 0.5),
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
        .opacity(dimmed ? 0.45 : 1)
    }
}

/// 出せる札の案内の枠（会長 QA 2026-10-24）。ほかのゲームのヒントの印と同じ色（`BoardGameHintColor`）で、
/// ゆっくり脈打たせる。Reduce Motion では脈打たせず、濃い枠のまま止める。当たり判定・読み上げは持たない。
struct SpeedNavigationRing: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 1 回の明暗の長さ（ゆっくり。ヒントの促し `HintNudge` の光り方と同じ）。
    static let pulseDuration = 0.8

    var body: some View {
        Group {
            if reduceMotion {
                ring(bright: true)
            } else {
                // 2 つの位相を行き来して脈打たせる（`phaseAnimator` は trigger を渡さなければ繰り返す）。
                ring(bright: false).phaseAnimator([false, true]) { _, bright in
                    ring(bright: bright)
                } animation: { _ in
                    .easeInOut(duration: Self.pulseDuration)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// フェルトにも札の白にも沈まないよう、白い縁を挟んだ二重枠にする（神経衰弱のヒントと同じ形）。
    private func ring(bright: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return shape.strokeBorder(.white, lineWidth: 5)
            .overlay(shape.strokeBorder(BoardGameHintColor.color, lineWidth: 3))
            .shadow(color: BoardGameHintColor.color.opacity(bright ? 0.85 : 0.3), radius: bright ? 9 : 3)
            .opacity(bright ? 1 : 0.5)
            .padding(-3)
    }
}

/// 山札（裏向き + 残り枚数）。空なら破線の枠。
struct SpeedStockView: View {
    let metrics: PlayingCardMetrics
    let count: Int

    var body: some View {
        ZStack {
            if count > 0 {
                PlayingCardSurface(faceUp: false, cornerRadius: metrics.cornerRadius)
                PlayingCardBack(metrics: metrics)
                Text(verbatim: "\(count)")
                    .font(.system(size: metrics.rankFont * 0.7, weight: .black, design: .rounded).monospacedDigit()) // fixed-size: カード・セットアップ部品の寸法（metrics）に比例させる文字
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .contentTransition(.numericText())
            } else {
                CardSlot(metrics: metrics, systemImage: "tray")
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .accessibilityElement(children: .ignore)
    }
}

// MARK: - 速さのシート

/// CPU の速さを選ぶ（#1323 の受け入れ条件）。
struct SpeedSetupSheet: View {
    let onStart: (SpeedSettings) -> Void
    let onCancel: () -> Void
    @State private var settings: SpeedSettings

    init(initial: SpeedSettings, onStart: @escaping (SpeedSettings) -> Void, onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        _settings = State(initialValue: initial)
    }

    /// 3 つ横に並ぶので、見出しと副題を標準より少し小さくする。
    private static let metrics = GameSetupChooser.Metrics(title: .title(20), subtitleSize: 11)

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onboarding: SpeedOnboarding.guide,
            onStart: { onStart(settings) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("速さ")) {
                HStack(spacing: 12) {
                    ForEach(SpeedLevel.allCases, id: \.self) { level in
                        GameSetupChooser(title: level.label, subtitle: level.subtitle,
                                         selected: settings.level == level,
                                         accent: Theme.Fill.coral, metrics: Self.metrics) {
                            settings.level = level
                        }
                    }
                }
                Text(tr("あなたに制限時間はありません。設定の「ゆっくりモード」をオンにすると、CPU はさらにゆっくりになります。"))
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSubText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Rule Sheet

struct SpeedRuleSheet: View {
    static var rules: [(String, String)] { [
        (tr("ゲームの流れ"), tr("トランプを赤（♥♦）と黒（♠♣）の26枚ずつに分け、あなたが赤、CPU が黒を使います。手札は4枚。真ん中の台札2山に、手札から札を重ねていきます")),
        (tr("出し方"), tr("手札の札を、出したい台札のほうへ払うと出せます。台札の上まで動かして離しても出せます。出せない札は手札に戻ります（ペナルティはありません）")),
        (tr("出せる札"), tr("台札の数字と1つ違いの札（台札が7なら6か8）。A と K もつながります。マークは関係ありません")),
        (tr("順番はない"), tr("出せる札があればいつでも出せます。CPU も同時に出してくるので、早い者勝ちです。あなたの側に制限時間はありません")),
        (tr("補充"), tr("札を出すと、自分の山札から手札に1枚補充されます（手札はいつも4枚まで）")),
        (tr("つまったら"), tr("どちらも出せる札が無くなったら「めくる」。山札が残っている側が、山札から1枚ずつ台札に置きます。山札が無くなったら、めくらずに手札を出し切れば勝ちです。両方とも山札が無いときは、台札を切り直して一番上の札を入れ替えます")),
        (tr("勝ち"), tr("手札と山札を先に出し切ったほうの勝ち。めくるだけが続いて場が動かないときは引き分けです")),
        (tr("タイム"), tr("負けそうなとき（CPU の残りが8枚以下で、あなたより少ないとき）、広告を見ると1ゲームに1回だけ CPU が8秒休みます")),
        (tr("速さ"), tr("CPU の反応は「ゆっくり / ふつう / はやい」から選べます。設定の「ゆっくりモード」をオンにすると、さらにゆっくりになります")),
    ] }

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
