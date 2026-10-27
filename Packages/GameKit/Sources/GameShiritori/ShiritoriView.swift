import SwiftUI
import Core
import CoreObjectArt

public struct ShiritoriView: View {
    @State private var model: ShiritoriModel
    @State private var showSetup = false
    @State private var showConfirmNewGame = false
    @State private var extendRescue = RewardedRescue()
    @State private var resultCardClosed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.adaptiveLayout) private var layout
    /// 盤札の読み（10pt・`.caption` 基準）の 1 行の高さ。文字を拡大すると札の絵をそのぶん縮めて 5 行を収める（#2847）。
    @ScaledMetric(relativeTo: .caption) private var readingLineHeight: CGFloat = ShiritoriBoardLayout.baseReadingHeight
    /// 盤の下の操作（ヒント・もう一回／延長・レコメンド）の実測の高さ。盤の絵の大きさはこれを引いた残りから決める。
    @State private var controlsHeight: CGFloat = 0
    private let services: GameServices

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ShiritoriModel(
            // 通過札は boardArea の .gameAnimation（150ms）が完了しきってから次へ進むよう、
            // ステップ間隔をアニメーション時間と揃える（55msだと遷移途中で次へ切り替わり、
            // 各札を明確に示せない。CodeRabbit指摘・PR #1309）
            services: services, cpuCursorDelay: .milliseconds(400), cpuCursorStepDelay: .milliseconds(150)
        ))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            // 終局後は場の札の段ごと畳み、結果は上の帯へ移す（#2863。マインスイーパーの #148 と同じ）。
            if model.phase != .result {
                currentArea
                    .transition(.opacity)
            }
            // 盤とその下の操作（ヒント・もう一回・レコメンド）は残りの高さをまとめて受け取り（`GeometryReader`）、
            // 札の絵を「残りの高さ − 下の操作の高さ」に収まる大きさで描く（#2847）。固定 pt のまま積むと
            // iPhone SE（中身 571pt）で溢れ、最上段のカードがナビバーの裏に入っていた。
            // 余りは操作の下・広告の上に残る（以前の `Spacer` と同じ場所。操作が盤から離れて広告の直上へ沈まない・#1485）。
            boardAndControls
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        // 結果から外れる（もう一回・広告で延長）と、次の終局でまたカードが出るよう開け直す。
        .onChange(of: model.phase) { _, phase in
            if phase != .result { resultCardClosed = false }
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gameChrome(title: tr("カードしりとり"), review: services.review,
                    condition: GameChromeCondition(conditionParts),
                    newGame: GameChromeNewGame(.solo) { requestNewGame() })
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { showSetup = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの対局が失われます。"))
            }
        }
        // 読んでいる間に時間を取られないよう止める。札をタップすると再開する。
        // 「？」は遊んでいる遊び方（ノルマ・とことん）に合わせて出し分ける（#2044）。
        .howToPlay(model.mode.howToPlayGuide.onboarding(ShiritoriOnboarding.guide(mode: model.mode)), onPresent: { model.pause() }) { ShiritoriRuleSheet() }
        .sheet(isPresented: $showSetup) {
            ShiritoriSetupSheet(quota: model.quota, mode: model.mode) { quota, mode in
                model.startGame(quota: quota, mode: mode)
                showSetup = false
            } onCancel: { showSetup = false }
        }
        // 時間切れの結果で「広告を見て続ける」を出しているあいだを 1 回の提示として数える（#780 × #1717）。
        .rewardOffer(extendRescue, for: .continue, isPresented: model.canExtendTime,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            extendRescue,
            notEarned: tr("続けられませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("続けられませんでした"),
                message: tr("広告を見ているあいだに対局が終わったため、時間を延長できませんでした。")
            )
        )
        // 保留している負けは、画面を離れても落とさず記録する。
        .onDisappear { model.commitTimeUpLoss() }
        // 強制終了・OS による終了では onDisappear が走らないので、背景に回った時点でも確定する（#1977）。
        // 広告の視聴中は背景扱いになりうる（広告から App Store へ飛ぶ等）。視聴後の延長を潰さないため確定しない。
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, !extendRescue.isWatching { model.commitTimeUpLoss() }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-shiritoriCPUCursorProbe") {
                model.debugShowCPUCursor()
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-shiritoriEndlessProbe") {
                // 撮影用: とことんモードの対局を開始シートを出さずに始める（シミュレータは自動タップできない・#1502）。
                model.startGame(mode: .endless)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-shiritoriResultProbe") {
                // 撮影用（#2360・#2847）: 時間切れの結果画面（延長ボタン + もう一回の段）を開始シートを出さずに再現する。
                model.startGame(quota: .normal, mode: .quota)
                model.tick(ShiritoriTime.initial + 1)
                return
            }
            #endif
            // 開いた直後は難易度を選ばせる。
            if model.phase == .idle { showSetup = true }
        }
        // CPU の手番の開始と取った札を VoiceOver へ伝える（#2610）。カーソルの途中経過は読まない。
        .onChange(of: model.isPlayerTurn) { _, isPlayerTurn in
            if model.phase == .playing, !isPlayerTurn {
                AccessibilityNotification.Announcement(ShiritoriPresentation.cpuThinkingAnnouncement()).post()
            }
        }
        .onChange(of: model.lastEvent) { _, event in
            if case let .played(by: .cpu, reading, _) = event {
                AccessibilityNotification.Announcement(
                    ShiritoriPresentation.cpuPlayedAnnouncement(reading: reading, continues: model.phase == .playing)
                ).post()
            }
        }
        .task(id: model.isPlayerTurn) {
            // CPU の手番。画面を離れたらこのタスクごと取り消される（非構造化の Task にすると、
            // 離脱後に手が着地して幽霊の対局記録を書く）。
            await model.runCPUTurnIfNeeded()
        }
        .task {
            // 制限時間を進める。減るのはプレイヤーの手番のあいだだけ（モデルが判定する）。
            // 裏に回っていた間の時間をまとめて取られないよう、1 回に進める幅は 0.5 秒までにする。
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let now = ContinuousClock.now
                let parts = last.duration(to: now).components
                last = now
                let elapsed = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
                model.tick(min(elapsed, 0.5))
            }
        }
    }

    /// 新規対局の入口（ヘッダーの「新規」と条件のチップが共通で呼ぶ・#1690）。
    private func requestNewGame() {
        model.pause()
        if model.hasProgressToLose {
            showConfirmNewGame = true
        } else {
            showSetup = true
        }
    }

    /// タイトルの下のチップに出す今の条件。遊び方（ノルマ / とことん）→ ノルマのときだけ難易度。
    private var conditionParts: [String] {
        model.mode == .quota ? [model.mode.label, model.quota.label] : [model.mode.label]
    }

    // MARK: - ステータス

    private var statusBar: some View {
        VStack(spacing: 6) {
            GameStatusBar {
                switch model.phase {
                case .idle: EmptyView()
                case .playing: TurnBadge(isYourTurn: model.isPlayerTurn)
                default: TurnBadge(tr("終了"), kind: .finished)
                }
                if model.phase == .result {
                    // 勝敗の見出しを帯に同居させる。詳細・記録は盤に重ねる結果カードが持つ（#2863）。
                    Label(ShiritoriPresentation.resultTitle(ending: model.ending ?? .timeUp, didWin: model.didPlayerWin,
                                                            mode: model.mode),
                          systemImage: model.didPlayerWin ? "crown.fill" : "flag.checkered")
                        .themeBody(13, weight: .bold)
                        .foregroundStyle(model.didPlayerWin ? Theme.tealText : Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Label(tr("%lldゲーム目", max(model.gameNumber, 1)), systemImage: "number")
                        .themeBody(13)
                        .foregroundStyle(Theme.inkSubText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            } trailing: {
                Text(model.mode == .endless ? model.mode.label : model.quota.label)
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Fill.purple))
            }
            timeBar
                .padding(.horizontal, GameStatusBarStyle.horizontalPadding)
        }
    }

    private var timeBar: some View {
        let seconds = Int(model.timeRemaining.rounded(.up))
        let ratio = min(1, max(0, model.timeRemaining / ShiritoriTime.initial))
        let urgent = model.timeRemaining <= 10 && model.phase == .playing
        return HStack(spacing: 8) {
            Image(systemName: "timer")
                .scaledFont(12, weight: .bold)
                .foregroundStyle(urgent ? Theme.coralText : Theme.inkSubText)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkSub.opacity(0.2))
                    Capsule().fill(urgent ? Theme.coral : Theme.teal)
                        .frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text(model.isPaused ? tr("一時停止") : tr("%lldびょう", seconds))
                .scaledFont(12, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(urgent ? Theme.coralText : Theme.ink)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isPaused ? tr("一時停止中。札をタップすると再開します") : tr("のこり%lld秒", seconds))
    }

    // MARK: - 場の札

    private var currentArea: some View {
        HStack(spacing: 12) {
            Group {
                if let card = model.currentCard {
                    ShiritoriCardTile(card: card, reading: model.currentReading, style: .current)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.inkSub.opacity(0.15))
                }
            }
            .frame(width: layout.scaled(84), height: layout.scaled(96))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ShiritoriPresentation.currentLabel(card: model.currentCard, reading: model.currentReading))

            VStack(alignment: .leading, spacing: 6) {
                Text(ShiritoriPresentation.prompt(tail: model.requiredTail, isPlayerTurn: model.isPlayerTurn, phase: model.phase))
                    .scaledFont(15, weight: .black, design: .rounded)
                    .foregroundStyle(model.isPlayerTurn ? Theme.tealText : Theme.inkSubText)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(model.lastEvent.map(ShiritoriPresentation.eventText) ?? " ")
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(isMiss ? Theme.coralText : Theme.inkSubText)
                    .lineLimit(1).minimumScaleFactor(0.6)
                scoreLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var isMiss: Bool { model.lastEvent == .miss }

    private var scoreLine: some View {
        HStack(spacing: 10) {
            Label(tr("あなた %lld", model.playerCount), systemImage: "person.fill")
                .foregroundStyle(Theme.tealText)
            Label("CPU \(model.cpuCount)", systemImage: "cpu")
                .foregroundStyle(Theme.coralText)
            if model.mode == .endless {
                Label(tr("山札 %lld", model.stockCount), systemImage: "square.stack.fill")
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .scaledFont(12, weight: .bold, design: .rounded)
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("あなた%1$lld枚、CPU%2$lld枚", model.playerCount, model.cpuCount)
                            + (model.mode == .endless ? tr("、山札%lld枚", model.stockCount) : ""))
    }

    // MARK: - 盤

    /// 盤と、その下の操作（初回ガイド・もう一回／延長・レコメンド）。
    ///
    /// 札の絵の一辺は、幅から決まる値と「残りの高さ − 下の操作の高さ」から決まる値の小さい方（`ShiritoriBoardLayout.artSide`）。
    /// iPhone 17 では幅で決まり従来と同じ大きさ、iPhone SE では高さで決まって 5 行が画面に収まる（#2847）。
    /// `LazyVGrid` は提案された高さに札を合わせてくれないので、絵の一辺を先に決めて渡す。下の操作の高さは
    /// `background` の `GeometryReader` で測る（配置に干渉しない。`onGeometryChange` は iOS 18 以降のため使わない）。
    /// 下の操作は盤のすぐ下に付き、余りはその下（広告の上）に残る。全部が収まらないときは下端側へはみ出す。
    private var boardAndControls: some View {
        GeometryReader { geo in
            let artSide = ShiritoriBoardLayout.artSide(
                availableWidth: geo.size.width,
                availableHeight: geo.size.height - controlsHeight - 8,
                count: model.slots.count, readingHeight: readingLineHeight * layout.elementScale
            )
            VStack(spacing: 8) {
                boardCard(artSide: artSide)
                    .boardGameResultCard(isPresented: model.phase == .result && !resultCardClosed) { endCard }
                VStack(spacing: 8) {
                    HowToPlayHint(.shiritori, playLog: services.playLog)
                    actionArea
                    RecommendationSlot(services: services, isFinished: model.phase == .result, ladder: ladder)
                }
                .background {
                    GeometryReader { below in
                        Color.clear.task(id: below.size.height) { controlsHeight = below.size.height }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func boardCard(artSide: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: ShiritoriBoardLayout.tileSpacing),
                           count: ShiritoriBoardLayout.columns),
            spacing: ShiritoriBoardLayout.tileSpacing
        ) {
            ForEach(Array(model.slots.enumerated()), id: \.element.card.id) { index, slot in
                ShiritoriCardTile(card: slot.card, reading: slot.displayReading,
                                  style: .board(owner: slot.owner, selectable: model.isSelectable(index),
                                                isCPUCursor: model.cpuCursorSlot == index),
                                  artSide: artSide)
                    .contentShape(Rectangle())
                    .onTapGesture { select(index) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ShiritoriPresentation.slotLabel(slot))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { select(index) }
            }
        }
        .padding(.horizontal, ShiritoriBoardLayout.cardHorizontalPadding)
        .padding(.vertical, ShiritoriBoardLayout.cardVerticalPadding)
        .frame(maxWidth: .infinity)
        .popCard(corner: Theme.cornerSmall)
        // slots と cpuCursorSlot を1つの Equatable にまとめて modifier を1つだけ掛ける
        // （.gameAnimation の入れ子・多重掛けは内側が外側のトランザクションを打ち消すため禁止）。
        .gameAnimation(.easeInOut(duration: 0.15),
                       value: ShiritoriBoardAnimationState(slots: model.slots, cpuCursorSlot: model.cpuCursorSlot))
    }

    /// 札を取る。CPU の手番は `.task(id: model.isPlayerTurn)` が進める。
    private func select(_ index: Int) {
        model.select(index)
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            actionButton(tr("ゲームを始める"), role: .primary) { showSetup = true }
        case .playing:
            EmptyView()
        case .result:
            VStack(spacing: 8) {
                if model.canExtendTime {
                    extendTimeButton
                }
                // 視聴中に始め直すと、見終えた広告が局ガードで弾かれて見損になる（#911 と同型）。
                GameReplayBar(
                    onReplay: { model.startGame(quota: model.quota, mode: model.mode) },
                    onChangeSettings: { showSetup = true }
                )
                .disabled(extendRescue.isWatching)
            }
        }
    }

    /// 時間切れの負けにだけ出す「広告を見て +30 秒で続ける」（#1717。1 局 1 回）。
    private var extendTimeButton: some View {
        Button {
            // 視聴完了したときだけ延長する。どの局かを広告の前に控え、視聴中に局が入れ替わっていたら乗せない。
            let serial = model.gameNumber
            extendRescue.request(
                services, gameID: model.gameID, purpose: .continue,
                guardedBy: .checkedByGrant,
                // 視聴しなかった・読み込めなかったときは従来どおりの負けとして確定する。
                whenNotEarned: { model.commitTimeUpLoss() }
            ) {
                model.extendTimeAfterAd(forGame: serial)
            }
        } label: {
            Label(tr("広告を見て +30 秒で続ける（1 局に 1 回）"), systemImage: "play.rectangle.fill")
                .themeBody(14, weight: .bold, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(extendRescue.isWatching)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 役割（`GameButtonRole`）で色を決める横いっぱいのボタン（#1423）。色・角丸・44pt は `GameButtonStyle` が持つ。
    private func actionButton(_ title: String, role: GameButtonRole,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると折り返してボタンの高さが跳ねるため、折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// ノルマ戦で勝ちが続いたら一段上のノルマを勧める（#2599）。とことんは段が無いので勧めない。
    private var ladder: DifficultyLadderPrompt? {
        let quotas = ShiritoriQuota.allCases
        return DifficultyLadderPrompt(result: model.recordResult,
                                      currentLevel: model.mode == .quota ? quotas.firstIndex(of: model.quota) : nil,
                                      levelLabels: quotas.map(\.label)) { level in
            model.startGame(quota: quotas[level], mode: .quota)
        }
    }

    // MARK: - リザルト

    /// 終局を盤に重ねて大きく示す結果カード（#1876。盤ゲームと同じ部品）。
    /// 時間切れの「広告を見て続ける」ボタンは盤の下の `actionArea` にあり、カードは盤にしか掛からないので出る順番はぶつからない。
    /// 続けるか決まるまで記録は無いので、自己ベストの行はその間は空になる。
    @ViewBuilder
    private var endCard: some View {
        let ending = model.ending ?? .timeUp
        BoardGameResultCard(
            verdict: model.didPlayerWin ? .win : .loss,
            reason: ShiritoriPresentation.resultReason(ending: ending),
            details: [ShiritoriPresentation.resultDetail(player: model.playerCount, cpu: model.cpuCount,
                                                         quota: model.quota, ending: ending, mode: model.mode,
                                                         clearSeconds: model.quotaClearSeconds)],
            record: model.recordResult
        ) { resultCardClosed = true }
    }
}

// MARK: - 盤のアニメーション対象

/// `boardArea` の `.gameAnimation` に渡す 1 つの値（#1286）。
private struct ShiritoriBoardAnimationState: Equatable {
    let slots: [ShiritoriSlot]
    let cpuCursorSlot: Int?
}

// MARK: - 盤の寸法

enum ShiritoriBoardLayout {
    /// 30 枚が 6 列 × 5 行にぴったり収まる（#1660: 29 枚の頃は右下が歯抜けだった）。
    static let columns = 6
    /// 札のあいだ（列・行とも）。
    static let tileSpacing: CGFloat = 6
    /// 盤のカードの内側の余白。
    static let cardHorizontalPadding: CGFloat = 8
    static let cardVerticalPadding: CGFloat = 10
    /// 札の内側の余白（`ShiritoriCardTile`）。
    static let tileHorizontalPadding: CGFloat = 2
    static let tileVerticalPadding: CGFloat = 3
    /// 盤札の絵のまわりの余白と、絵と読みのあいだ。
    static let artPadding: CGFloat = 3
    static let artSpacing: CGFloat = 2
    /// 絵の一辺の下限。これより小さくすると何の絵か読めないので、ここで止めて溢れるほうを取る。
    static let minArtSide: CGFloat = 16
    /// 読みの 1 行の高さの目安（10pt の太字・標準の文字サイズ）。Dynamic Type の拡大は呼び出し側が `@ScaledMetric` で掛ける。
    static let baseReadingHeight: CGFloat = 13

    static func rows(for count: Int) -> Int { max(1, (count + columns - 1) / columns) }

    /// 盤札の絵の一辺（#2847）。幅から決まる値（6 列が横に収まる）と、残りの高さから決まる値（全行が縦に収まる）の小さい方。
    /// iPhone 17（中身 702pt）では幅で決まり、iPhone SE（中身 571pt）では高さで決まる。
    static func artSide(availableWidth: CGFloat, availableHeight: CGFloat, count: Int, readingHeight: CGFloat) -> CGFloat {
        let rows = CGFloat(rows(for: count))
        let tileWidth = (availableWidth - cardHorizontalPadding * 2 - tileSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byWidth = tileWidth - tileHorizontalPadding * 2 - artPadding * 2
        let tileHeight = (availableHeight - cardVerticalPadding * 2 - tileSpacing * (rows - 1)) / rows
        let byHeight = tileHeight - tileVerticalPadding * 2 - artPadding * 2 - artSpacing - readingHeight
        return max(minArtSide, min(byWidth, byHeight))
    }

    /// 絵の一辺から逆算した札 1 枚の高さ。
    static func tileHeight(artSide: CGFloat, readingHeight: CGFloat) -> CGFloat {
        artSide + artPadding * 2 + artSpacing + readingHeight + tileVerticalPadding * 2
    }

    /// 絵の一辺から逆算した盤のカードの高さ。`artSide(...)` が高さで決めた値を戻すと、余りを除いて `availableHeight` 以下になる。
    static func boardHeight(artSide: CGFloat, count: Int, readingHeight: CGFloat) -> CGFloat {
        let rows = CGFloat(rows(for: count))
        return tileHeight(artSide: artSide, readingHeight: readingHeight) * rows + tileSpacing * (rows - 1) + cardVerticalPadding * 2
    }
}

// MARK: - 札

struct ShiritoriCardTile: View {
    @Environment(\.adaptiveLayout) private var layout

    enum Style: Equatable {
        case current
        case board(owner: ShiritoriOwner?, selectable: Bool, isCPUCursor: Bool)
    }

    let card: ShiritoriCard
    let reading: String
    let style: Style
    /// 絵の一辺。盤札は `ShiritoriBoardLayout.artSide` で決めた値を受け取る（nil なら幅なりに描く・場の札）。
    var artSide: CGFloat? = nil

    private var owner: ShiritoriOwner? {
        if case let .board(owner, _, _) = style { return owner }
        return nil
    }

    /// CPU が次に取ろうとしている札か（#1286: 取る前にカーソルが動く演出）。
    private var isCPUCursor: Bool {
        if case let .board(_, _, isCPUCursor) = style { return isCPUCursor }
        return false
    }

    private var isCurrent: Bool { style == .current }

    /// 読みを文字で見せるか。**取られる前の盤札では隠す**——絵だけを見て読みを考えるのが
    /// しりとりパネルの遊び（ワギャンランド踏襲）で、文字を出すと当てる要素が消える
    /// （会長指摘・2026-09-22「カードに文字書いてたら意味がない」）。場の最後の1枚（`.current`。
    /// 次に続ける相手が読みを知っている必要がある）と、**取られたあとの札**（結果の確認）だけ見せる。
    private var showsReading: Bool { isCurrent || owner != nil }

    var body: some View {
        VStack(spacing: ShiritoriBoardLayout.artSpacing) {
            ObjectCardArt(card.kind)
                .frame(width: artSide, height: artSide)
                .padding(isCurrent ? 6 : ShiritoriBoardLayout.artPadding)
            // 常に描画して高さを確保する（グリッドの行の高さが札ごとにばらつかないように）。
            // 隠すときは不透明度だけ0にする（VoiceOver は `boardArea` 側の `accessibilityLabel` が別に持つ）。
            Text(reading)
                .scaledFont(layout.scaled(isCurrent ? 14 : 10), weight: .bold, design: .rounded)
                .foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .opacity(showsReading ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ShiritoriBoardLayout.tileHorizontalPadding)
        .padding(.vertical, ShiritoriBoardLayout.tileVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CardStyle.faceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor, lineWidth: (isCurrent || isCPUCursor) ? 2.5 : (owner == nil ? 1 : 2))
                )
        )
        .opacity(owner == nil ? 1 : 0.55)
        .overlay(alignment: .topTrailing) { ownerBadge }
    }

    private var borderColor: Color {
        if isCurrent || isCPUCursor { return Theme.yellow }
        switch owner {
        case .player: return Theme.teal
        case .cpu:    return Theme.coral
        case nil:     return Theme.inkSub.opacity(0.3)
        }
    }

    @ViewBuilder
    private var ownerBadge: some View {
        switch owner {
        case .player:
            Image(systemName: "person.fill").scaledFont(9, weight: .bold)
                .foregroundStyle(Theme.onAccent).padding(3)
                .background(Circle().fill(Theme.teal)).offset(x: 3, y: -3)
        case .cpu:
            Image(systemName: "cpu").scaledFont(9, weight: .bold)
                .foregroundStyle(Theme.onAccent).padding(3)
                .background(Circle().fill(Theme.coral)).offset(x: 3, y: -3)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - 開始シート

struct ShiritoriSetupSheet: View {
    @State private var quota: ShiritoriQuota
    @State private var mode: ShiritoriMode
    /// 番の交代・制限時間・勝ち負けの説明を開いているか。遊び方を切り替えても開閉はそのまま。
    @State private var showsDetails = false
    let onStart: (ShiritoriQuota, ShiritoriMode) -> Void
    let onCancel: () -> Void

    init(quota: ShiritoriQuota,
         mode: ShiritoriMode,
         onStart: @escaping (ShiritoriQuota, ShiritoriMode) -> Void,
         onCancel: @escaping () -> Void) {
        _quota = State(initialValue: quota)
        _mode = State(initialValue: mode)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onboarding: ShiritoriOnboarding.guide(mode: mode),
            onStart: { onStart(quota, mode) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("あそびかた")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(Array(ShiritoriMode.allCases.enumerated()), id: \.element) { step, item in
                            GameSetupChooser(
                                title: item.label, subtitle: "",
                                selected: mode == item,
                                accent: DifficultyTile.accent(step: step, of: ShiritoriMode.allCases.count),
                                metrics: DifficultyTile.metrics
                            ) { mode = item }
                        }
                    }
                    Text(mode.summary)
                        .themeBody(13)
                        .foregroundStyle(Theme.inkSubText)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // とことんにはノルマが無いので、むずかしさは選ばせない。
            if mode == .quota {
                difficultySection
            }
            // 選んでいる遊び方のルールの要点を、図つきでそのまま並べる（#2044。荷物運びパズルの開始シート #2132 と
            // 同じ型・会長指示「遷移リンクを貼るだけでは駄目」）。カードは「？」の遊び方シートと同じ部品。
            GameSetupSection(tr("%@のルール", mode.label)) {
                VStack(spacing: 10) {
                    ForEach(Array(mode.setupKeyItems.enumerated()), id: \.offset) { _, item in
                        HowToPlayItemCard(item)
                    }
                    detailsToggle
                    if showsDetails {
                        ForEach(Array(mode.setupDetailItems.enumerated()), id: \.offset) { _, item in
                            HowToPlayItemCard(item)
                        }
                        let notes = mode.howToPlayGuide.notes
                        if !notes.isEmpty { HowToPlayNotesCard(notes) }
                    }
                }
                // 遊び方を切り替えたら、前の遊び方の図を引きずらずに丸ごと描き直す。
                .id(mode)
            }
        }
    }

    /// 番の交代・制限時間・勝ち負けの説明を開閉する行。別画面へは移らず、この場で下に広げる（荷物運びパズルと同じ）。
    private var detailsToggle: some View {
        Button {
            withGameAnimation(.easeInOut(duration: 0.2)) { showsDetails.toggle() }
        } label: {
            HStack {
                Label(tr("制限時間・勝ち負けのくわしい説明"), systemImage: "timer")
                    .themeBody(15)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(Theme.inkSubText)
                    .rotationEffect(.degrees(showsDetails ? 180 : 0))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popCard(corner: Theme.cornerSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .foregroundStyle(Theme.ink)
        .accessibilityValue(showsDetails ? tr("開いている") : tr("閉じている"))
    }

    private var difficultySection: some View {
        Group {
            GameSetupSection(tr("むずかしさ")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(Array(ShiritoriQuota.allCases.enumerated()), id: \.element) { step, level in
                            GameSetupChooser(
                                title: level.label, subtitle: "",
                                selected: quota == level,
                                accent: DifficultyTile.accent(step: step, of: ShiritoriQuota.allCases.count),
                                metrics: DifficultyTile.metrics
                            ) { quota = level }
                        }
                    }
                    Text(tr("ノルマ: %@", quota.summary))
                        .themeBody(13)
                        .foregroundStyle(Theme.inkSubText)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - ルールシート

struct ShiritoriRuleSheet: View {
    /// 表示言語が変わったら引き直せるよう、毎回 `tr` で組む（#2169）。かな（「ー」「ぎ」など）は
    /// しりとりの中身なので英語でも日本語のまま見せ、`%@` で埋め込む。
    private var rules: [(String, String)] {
        let n = ShiritoriPresentation.nKana
        let longMark = "ー"  // i18n-keep: しりとりのかなそのもの（言語を切り替えられない）
        let (voiced, unvoiced) = ("ぎ", "き")  // i18n-keep: しりとりのかなそのもの（言語を切り替えられない）
        return [
            (tr("ゲームの流れ"), tr("CPUと交互に札を取ります。場の札の読みの最後の字から始まる読みの札を選べたら、その札を取れます。取った札が新しい場の札になります")),
            (tr("読みのルール"), tr("「%1$@」で終わるときはひとつ前の字で受けます。「%2$@」のような濁音は、そのまま「%2$@」でも、濁点を取った「%3$@」でも受けられます。1枚の札が別の読みを持つこともあります（うらよみ）", longMark, voiced, unvoiced)),
            (tr("制限時間"), tr("制限時間は60秒。しりとりが成立するたびに+10秒、成立しない札を選ぶ（おてつき）と-5秒。時間はあなたの番のあいだだけ減ります。時間切れで負けたときは、広告を見ると30秒足して続けられます（1局に1回）")),
            (tr("「%@」で終わると負け", n), tr("「%@」で終わる読みの札を選んだ人は、その場で負けです", n)),
            (tr("勝ち負け"), tr("CPUが続けられなくなったらあなたの勝ち、あなたが続けられなくなったら負けです")),
            (tr("ノルマ"), tr("自分が取った札がノルマの枚数に届いた瞬間に勝ちです。かんたん=4枚・ふつう=6枚・むずかしい=9枚。届かないまま時間切れになると負けです")),
            (tr("とことん"), tr("ノルマは無く、札が尽きるか、どちらかが続けられなくなるまで続きます。札を取ると空いた場所に山札から新しい札が出ます（山札が尽きたら出ません）。盤と山札の札を全部なくすとパーフェクトで勝ち。時間切れは負けです")),
        ]
    }

    var body: some View {
        RuleListSheet(rules: rules)
    }
}
