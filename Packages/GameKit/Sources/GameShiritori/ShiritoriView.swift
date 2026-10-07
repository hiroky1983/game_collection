import SwiftUI
import Core

public struct ShiritoriView: View {
    @State private var model: ShiritoriModel
    @State private var showSetup = false
    @State private var showConfirmNewGame = false
    @State private var extendRescue = RewardedRescue()
    @State private var resultCardClosed = false
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
            if model.phase == .result {
                resultCard
                    .transition(.opacity)
            } else {
                currentArea
                    .transition(.opacity)
            }
            boardArea
                .boardGameResultCard(isPresented: model.phase == .result && !resultCardClosed) { endCard }
            HowToPlayHint(.shiritori, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result)
            // 札の盤は札の枚数ぶんの高さしか取らないため、余りをここで吸って広告を画面の下端に置く。
            // 吸わないと画面全体が縦に伸びず、背景色が中身の範囲にしか塗られない（ヘッダーまわりと広告の下が白く残る）
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        // 結果から外れる（もう一回・広告で延長）と、次の終局でまたカードが出るよう開け直す。
        .onChange(of: model.phase) { _, phase in
            if phase != .result { resultCardClosed = false }
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gameChrome(title: "カードしりとり", review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        model.pause()
                        if model.hasProgressToLose {
                            showConfirmNewGame = true
                        } else {
                            showSetup = true
                        }
                    })
        .confirmationDialog("新規ゲームを始めますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { showSetup = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると、いまの対局が失われます。")
        }
        // 読んでいる間に時間を取られないよう止める。札をタップすると再開する。
        .howToPlay(.shiritori, onPresent: { model.pause() }) { ShiritoriRuleSheet() }
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
            notEarned: "続けられませんでした",
            unavailable: RewardUnavailableAlert(
                title: "続けられませんでした",
                message: "広告を見ているあいだに対局が終わったため、時間を延長できませんでした。"
            )
        )
        // 保留している負けは、画面を離れても落とさず記録する。
        .onDisappear { model.commitTimeUpLoss() }
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
            #endif
            // 開いた直後は難易度を選ばせる。
            if model.phase == .idle { showSetup = true }
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

    // MARK: - ステータス

    private var statusBar: some View {
        VStack(spacing: 6) {
            GameStatusBar {
                switch model.phase {
                case .idle: EmptyView()
                case .playing: TurnBadge(isYourTurn: model.isPlayerTurn)
                default: TurnBadge("終了", kind: .finished)
                }
                Label("\(max(model.gameNumber, 1))ゲーム目", systemImage: "number")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
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
                .foregroundStyle(urgent ? Theme.coral : Theme.inkSub)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkSub.opacity(0.2))
                    Capsule().fill(urgent ? Theme.coral : Theme.teal)
                        .frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text(model.isPaused ? "一時停止" : "\(seconds)びょう")
                .scaledFont(12, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(urgent ? Theme.coral : Theme.ink)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isPaused ? "一時停止中。札をタップすると再開します" : "のこり\(seconds)秒")
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
            .frame(width: 84, height: 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ShiritoriPresentation.currentLabel(card: model.currentCard, reading: model.currentReading))

            VStack(alignment: .leading, spacing: 6) {
                Text(ShiritoriPresentation.prompt(tail: model.requiredTail, isPlayerTurn: model.isPlayerTurn, phase: model.phase))
                    .scaledFont(15, weight: .black, design: .rounded)
                    .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(model.lastEvent.map(ShiritoriPresentation.eventText) ?? " ")
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(isMiss ? Theme.coral : Theme.inkSub)
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
            Label("あなた \(model.playerCount)", systemImage: "person.fill")
                .foregroundStyle(Theme.teal)
            Label("CPU \(model.cpuCount)", systemImage: "cpu")
                .foregroundStyle(Theme.coral)
            if model.mode == .endless {
                Label("山札 \(model.stockCount)", systemImage: "square.stack.fill")
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .scaledFont(12, weight: .bold, design: .rounded)
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("あなた\(model.playerCount)枚、CPU\(model.cpuCount)枚"
                            + (model.mode == .endless ? "、山札\(model.stockCount)枚" : ""))
    }

    // MARK: - 盤

    private var boardArea: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: ShiritoriBoardLayout.columns),
            spacing: 6
        ) {
            ForEach(Array(model.slots.enumerated()), id: \.element.card.id) { index, slot in
                ShiritoriCardTile(card: slot.card, reading: slot.displayReading,
                                  style: .board(owner: slot.owner, selectable: model.isSelectable(index),
                                                isCPUCursor: model.cpuCursorSlot == index))
                    .contentShape(Rectangle())
                    .onTapGesture { select(index) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ShiritoriPresentation.slotLabel(slot))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { select(index) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
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
            actionButton("ゲームを始める", role: .primary) { showSetup = true }
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
            Label("広告を見て +30 秒で続ける（1 局に 1 回）", systemImage: "play.rectangle.fill")
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
                                                         quota: model.quota, ending: ending, mode: model.mode)],
            record: model.recordResult
        ) { resultCardClosed = true }
    }

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.didPlayerWin ? "crown.fill" : "flag.checkered")
                    .scaledFont(20)
                    .foregroundStyle(model.didPlayerWin ? Theme.yellow : Theme.inkSub)
                Text(ShiritoriPresentation.resultTitle(ending: model.ending ?? .timeUp, didWin: model.didPlayerWin,
                                                              mode: model.mode))
                    .scaledFont(16, weight: .black, design: .rounded)
                    .foregroundStyle(model.didPlayerWin ? Theme.teal : Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text(ShiritoriPresentation.resultDetail(player: model.playerCount, cpu: model.cpuCount, quota: model.quota,
                                                          ending: model.ending ?? .timeUp, mode: model.mode))
                .scaledFont(12, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 結果カードが開いているあいだはカードが持つので出さない（二重になり、SE では高さも溢れる）。
            if resultCardClosed {
                RecordLabel(model.recordResult)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
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
    /// 30 枚が 6 列 × 5 行にぴったり収まる（#1660: 29 枚の頃は右下が歯抜けだった）。iPhone SE でも広告枠を含めて縦に収まる本数。
    static let columns = 6
}

// MARK: - 札

struct ShiritoriCardTile: View {
    enum Style: Equatable {
        case current
        case board(owner: ShiritoriOwner?, selectable: Bool, isCPUCursor: Bool)
    }

    let card: ShiritoriCard
    let reading: String
    let style: Style

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
        VStack(spacing: 2) {
            ObjectCardArt(card.kind)
                .padding(isCurrent ? 6 : 3)
            // 常に描画して高さを確保する（グリッドの行の高さが札ごとにばらつかないように）。
            // 隠すときは不透明度だけ0にする（VoiceOver は `boardArea` 側の `accessibilityLabel` が別に持つ）。
            Text(reading)
                .scaledFont(isCurrent ? 14 : 10, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .opacity(showsReading ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2).padding(.vertical, 3)
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
            onStart: { onStart(quota, mode) }, onCancel: onCancel
        ) {
            GameSetupSection("あそびかた") {
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
                        .foregroundStyle(Theme.inkSub)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // とことんにはノルマが無いので、むずかしさは選ばせない。
            if mode == .quota {
                difficultySection
            }
        }
    }

    private var difficultySection: some View {
        Group {
            GameSetupSection("むずかしさ") {
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
                    Text("ノルマ: " + quota.summary)
                        .themeBody(13)
                        .foregroundStyle(Theme.inkSub)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - ルールシート

struct ShiritoriRuleSheet: View {
    private let rules: [(String, String)] = [
        ("ゲームの流れ", "CPUと交互に札を取ります。場の札の読みの最後の字から始まる読みの札を選べたら、その札を取れます。取った札が新しい場の札になります"),
        ("読みのルール", "「ー」で終わるときはひとつ前の字で受けます。「ぎ」のような濁音は、そのまま「ぎ」でも、濁点を取った「き」でも受けられます。1枚の札が別の読みを持つこともあります（うらよみ）"),
        ("制限時間", "制限時間は60秒。しりとりが成立するたびに+10秒、成立しない札を選ぶ（おてつき）と-5秒。時間はあなたの番のあいだだけ減ります。時間切れで負けたときは、広告を見ると30秒足して続けられます（1局に1回）"),
        ("「ん」で終わると負け", "「ん」で終わる読みの札を選んだ人は、その場で負けです"),
        ("勝ち負け", "CPUが続けられなくなったらあなたの勝ち、あなたが続けられなくなったら負けです"),
        ("ノルマ", "自分が取った札がノルマの枚数に届いた瞬間に勝ちです。かんたん=4枚・ふつう=6枚・むずかしい=9枚。届かないまま時間切れになると負けです"),
        ("とことん", "ノルマは無く、札が尽きるか、どちらかが続けられなくなるまで続きます。札を取ると空いた場所に山札から新しい札が出ます（山札が尽きたら出ません）。盤と山札の札を全部なくすとパーフェクトで勝ち。時間切れは負けです"),
    ]

    var body: some View {
        RuleListSheet(rules: rules)
    }
}
