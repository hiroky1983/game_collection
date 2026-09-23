import SwiftUI
import Core

public struct ColorRelayView: View {
    @State private var model: ColorRelayModel
    private let services: GameServices
    /// 引き札を広告で免除する救済（#1320）。
    @State private var waiveRescue = RewardedRescue()
    /// 操作の後に CPU の手番を回すタスク。画面を離れたらキャンセルする（CodeRabbit 指摘・PR #1339）。
    /// `.task` の側は View のライフサイクルで自動的にキャンセルされるが、ボタンから起こした
    /// 非構造化タスクはそのままでは生き残り、画面外で CPU が打ち続けて決着・記録まで進んでしまう。
    @State private var cpuTask: Task<Void, Never>?
    /// 画面の広さ（#458）。札と同じ倍率で場の枠を拡大するために読む。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ColorRelayModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            cpuRow
            // 決着後は場も手札も要らないので、代わりに順位のリザルトを出す。
            // 縦の余りは `Spacer` ではなく手札 / リザルトのカード自身に吸わせる（大富豪 #193 と同じ）。
            if model.phase == .result {
                resultCard
                    .transition(.opacity)
            } else {
                fieldArea
                    .transition(.opacity)
                handArea
                    .transition(.opacity)
            }
            HowToPlayHint(.colorRelay, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result)
            BannerSlot(ads: services.ads)
        }
        // 局面 → リザルトの差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .gameChrome(title: "いろリレー", review: services.review)
        .howToPlay(.colorRelay) { ColorRelayRuleSheet() }
        // 免除の提示（#780）。自分の番で引き札を課され、免除ボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(waiveRescue, for: .revival, isPresented: model.canWaivePenalty,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            waiveRescue,
            notEarned: "引き札を免除できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "引き札を免除できませんでした",
                message: "広告を見ているあいだに番が進んだため、免除できませんでした。"
            )
        )
        .onDisappear { cpuTask?.cancel() }
        .task {
            // 開幕のモーダルは置かず、盤を見せたまま配り始める（#192）。
            // 中断から戻ったときは init が `.playing` まで復元しているので配り直さない。
            if model.phase == .idle { model.startGame() }
            #if DEBUG
            // 撮影・動作確認用: `-colorRelayScenario penalty|wild|result` で局面を差し替える。
            // 中断データから復元した局面も差し替える（前回の撮影が残っていても狙った局面になるように）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-colorRelayScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
    }

    /// 人間の操作の後に CPU の手番を回す。前のタスクは止めてから起こす（走者は `withAITurnRunner` が 1 本に保つ）。
    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            Label("\(max(model.gameNumber, 1))ゲーム目", systemImage: "number")
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
            Image(systemName: model.isClockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.inkSub)
                .accessibilityLabel(model.isClockwise ? "順回り" : "逆回り")
            Spacer()
            Text(turnLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var turnLabel: String {
        switch model.phase {
        case .idle:    return "開始待ち"
        case .result:  return "決着"
        case .playing: return model.isPlayerTurn ? "あなたの番" : "\(model.playerName(model.currentPlayer))の番"
        }
    }

    // MARK: - CPU

    private var cpuRow: some View {
        HStack(spacing: 8) {
            ForEach(1..<ColorRelayModel.playerCount, id: \.self) { index in
                cpuCard(index)
            }
        }
    }

    private func cpuCard(_ index: Int) -> some View {
        let isCurrent = model.currentPlayer == index && model.phase == .playing
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isCurrent ? Theme.coral : Theme.inkSub)
                Text(model.playerName(index))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            Text("残り\(model.hands[index].count)枚")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(model.lastActions[index].isEmpty ? " " : model.lastActions[index])
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(model.lastActions[index].isEmpty ? Color.clear : Theme.Fill.purple))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 場

    private var fieldArea: some View {
        HStack(spacing: 18) {
            drawPileView
            VStack(spacing: 4) {
                if let top = model.topCard {
                    ColorRelayCardView(card: top, size: .large)
                        .id(top.id)
                        .transition(.scale.combined(with: .opacity))
                }
                Text("場")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            activeColorChip
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeInOut(duration: 0.18), value: model.topCard)
        // 場は「何が出ているか」「いまの色」「山の残り」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ColorRelayAccessibility.fieldLabel(
            top: model.topCard, activeColor: model.activeColor, drawPileCount: model.drawPile.count
        ))
    }

    /// 山札。自分の番で引けるときはタップでも引ける（操作欄の「1枚引く」と同じ）。
    private var drawPileView: some View {
        VStack(spacing: 4) {
            Button {
                model.drawCard()
                runCPU()
            } label: {
                ColorRelayCardBack(metrics: PlayingCardMetrics.medium.scaled(by: layout.elementScale))
            }
            .buttonStyle(.pop)
            .disabled(!model.canDraw)
            .accessibilityLabel("山から1枚引く")
            Text("山 \(model.drawPile.count)枚")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
    }

    /// いまの色。いろがえの直後は場の札に色が無いので、ここで示す。
    private var activeColorChip: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(model.activeColor.color)
                .frame(width: layout.scaled(40), height: layout.scaled(40))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 2)
                )
            Text("いまの色")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(model.activeColor.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .gameAnimation(.easeInOut(duration: 0.18), value: model.activeColor)
    }

    // MARK: - 手札

    private var handArea: some View {
        // 1 枚ごとに引くと合法手の探索が手札の枚数ぶん走るので、ここで 1 回だけ求める（#190）。
        let handHint = model.handHint
        let playable = model.playableCardIDs
        return VStack(spacing: 6) {
            HStack {
                Text("あなた（残り\(model.playerHand.count)枚）")
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !model.lastActions[ColorRelayModel.humanIndex].isEmpty {
                    Text(model.lastActions[ColorRelayModel.humanIndex])
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.teal)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            // 手札は引き札で 20 枚を超えることがあり、3 段では収まらない。
            // 縦に伸ばさず、手札の枠の中でスクロールさせる（狭い画面で操作欄が押し出されないため）。
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: ColorRelayHandLayout.columnSpacing),
                        count: ColorRelayHandLayout.columns
                    ),
                    spacing: ColorRelayHandLayout.rowSpacing
                ) {
                    ForEach(model.playerHand) { card in
                        let isSelected = model.selectedID == card.id
                        let hint = handHint?.state(for: card.id) ?? .none
                        ColorRelayCardView(card: card, size: .small, selected: isSelected, hint: hint)
                            .offset(y: isSelected ? -6 : 0)
                            .gameAnimation(.spring(response: 0.2), value: isSelected)
                            // 見える札は 42pt のまま、タップ判定だけを列いっぱいに広げて 44pt 以上にする（#195）。
                            .frame(maxWidth: .infinity, minHeight: ColorRelayHandLayout.minimumTapTarget)
                            .contentShape(Rectangle())
                            .onTapGesture { model.toggleSelection(card) }
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                ColorRelayAccessibility.handCardLabel(card, isSelected: isSelected, hint: hint)
                            )
                            .accessibilityHint("ダブルタップで選択を切り替えます")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.toggleSelection(card) }
                            .disabled(!model.isPlayerTurn || model.isPlayerPenalized)
                    }
                }
                // 縦の ScrollView は中身の理想幅を提案してくるので、幅を枠に固定する。
                .frame(maxWidth: .infinity)
                // 出した札が消える / 引いた札が増える変化を演出する（#195）。
                .gameAnimation(.easeInOut(duration: 0.18), value: model.playerHand)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            hintLine(handHint, playable: playable)
        }
        .padding(.horizontal, ColorRelayHandLayout.horizontalPadding).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 手札の下に出す 1 行の案内（#190）。
    @ViewBuilder
    private func hintLine(_ handHint: RelayHandHint?, playable: Set<Int>) -> some View {
        let message: String? = {
            if model.isPlayerPenalized { return "\(model.pendingDraw)枚引いて、番は飛ばされます" }
            if model.canEndTurn, !playable.isEmpty { return "引いた札は出せます。出さずに次へ回すこともできます" }
            if model.isPlayerTurn, handHint?.playable.isEmpty == true, model.canDraw { return "出せる札がありません。山から1枚引いてください" }
            return nil
        }()
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(message)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .playing where model.isPlayerPenalized:
            VStack(spacing: 8) {
                if model.canWaivePenalty {
                    waivePenaltyButton
                }
                // 視聴中に引くと番が進み、見終えた広告が局ガードで弾かれて見損になる（#911 と同型）。
                actionButton("\(model.pendingDraw)枚引く", color: Theme.Fill.coral, disabled: waiveRescue.isWatching) {
                    model.takePenalty()
                    runCPU()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .playing where model.needsColorChoice:
            VStack(spacing: 6) {
                Text("次の色を選ぶ")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                HStack(spacing: 8) {
                    ForEach(RelayColor.allCases, id: \.self) { color in
                        colorChoiceButton(color)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .playing:
            HStack(spacing: 12) {
                if model.canEndTurn {
                    actionButton("出さずに次へ", color: Theme.fillMuted, foreground: .white) {
                        model.endTurn()
                        runCPU()
                    }
                } else {
                    actionButton("1枚引く", color: Theme.fillMuted, foreground: .white, disabled: !model.canDraw) {
                        model.drawCard()
                        runCPU()
                    }
                }
                actionButton(playButtonTitle, color: Theme.Fill.coral, disabled: !model.canPlaySelection) {
                    model.playSelected()
                    runCPU()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            actionButton("次のゲーム", color: Theme.Fill.coral) {
                model.startGame()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    /// 引き札を課された自分の番にだけ出す「広告を見て免除」（#1320）。1 ゲーム 1 回。
    private var waivePenaltyButton: some View {
        Button {
            // 視聴完了（報酬獲得）したときだけ免除する。どの手番に対するものかを広告の前に控え、
            // 視聴中に番が進んでいたら乗せない（#729）。
            let turn = model.turnSerial
            waiveRescue.request(
                services, gameID: model.gameID, purpose: .revival,
                guardedBy: .checkedByGrant
            ) {
                let applied = model.waivePenaltyAfterAd(forTurn: turn)
                if applied { runCPU() }
                return applied
            }
        } label: {
            Label("広告を見て\(model.pendingDraw)枚の引き札を免除", systemImage: "play.rectangle.fill")
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(waiveRescue.isWatching ? Theme.inkSub.opacity(0.3) : Theme.Fill.teal,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(waiveRescue.isWatching ? Theme.inkSub : Theme.onAccent)
        }
        .buttonStyle(.pop)
        .disabled(waiveRescue.isWatching)
    }

    private func colorChoiceButton(_ color: RelayColor) -> some View {
        Button {
            model.playSelected(color: color)
            runCPU()
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.color)
                    .frame(height: 28)
                Text(color.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: ColorRelayHandLayout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .accessibilityLabel("\(color.name)にして出す")
    }

    private var playButtonTitle: String {
        model.selectedID == nil ? "札を選ぶ" : "出す"
    }

    // MARK: - リザルト

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.playerPlace == 0 ? "crown.fill" : "flag.checkered")
                    .font(.system(size: 20))
                    .foregroundStyle(model.playerPlace == 0 ? Theme.yellow : Theme.inkSub)
                Text(resultHeadline)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(model.playerPlace == 0 ? Theme.teal : Theme.ink)
                Spacer()
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.element) { place, player in
                    HStack(spacing: 8) {
                        Text("\(place + 1)位")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            // 1 位だけ差し色の面。他は濃いグレーの面なので文字色を分ける（#220）。
                            .foregroundStyle(place == 0 ? Theme.onAccent : .white)
                            .frame(width: 44)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(place == 0 ? Theme.Fill.yellow : Theme.fillMuted))
                        Text(model.playerName(player))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(player == ColorRelayModel.humanIndex ? Theme.coral : Theme.ink)
                        Spacer()
                        Text(place == 0 ? "あがり" : "残り\(model.hands[player].count)枚")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }
            }
            // 「今回の結果」を上、「通算」を下に置き、余りは 2 つの塊の**間**に集める（#193）。
            Spacer(minLength: 8)
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultHeadline: String {
        guard let winner = model.ranking.first else { return "決着" }
        return winner == ColorRelayModel.humanIndex ? "あなたの勝ち！" : "\(model.playerName(winner))の勝ち"
    }

    /// - Parameter foreground: 面（`color`）の上に載せる文字色。差し色の面には `Theme.onAccent`、
    ///   `fillMuted` のような濃い面には白を渡す（#220）。
    private func actionButton(_ title: String, color: Color, foreground: Color = Theme.onAccent,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(disabled ? Theme.inkSub : foreground)
        }
        .buttonStyle(.pop)
        .disabled(disabled)
    }
}

// MARK: - 手札グリッドの寸法

/// 手札グリッドの寸法（大富豪 #195 と同じ考え方）。見た目の札は 42pt のまま、タップ判定だけを列いっぱいに広げる。
enum ColorRelayHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 6
    /// 手札カード（`popCard`）の内側の左右余白。
    static let horizontalPadding: CGFloat = 12
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 画面幅 `screenWidth` のときの、手札 1 枚あたりのタップ判定の幅。
    static func tapWidth(screenWidth: CGFloat) -> CGFloat {
        let available = screenWidth - Theme.pad * 2 - horizontalPadding * 2
        return (available - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }
}

// MARK: - 札の面（完全オリジナル）

/// 4 色の印（いろがえの図案・山札の裏）。角丸の四角を 2 × 2 に並べる。
struct FourColorMark: View {
    var size: CGFloat
    var spacing: CGFloat = 2

    var body: some View {
        let side = (size - spacing) / 2
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                square(.red, side)
                square(.green, side)
            }
            HStack(spacing: spacing) {
                square(.yellow, side)
                square(.purple, side)
            }
        }
        .frame(width: size, height: size)
    }

    private func square(_ color: RelayColor, _ side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
            .fill(color.color)
            .frame(width: side, height: side)
    }
}

/// 札 1 枚の面。色の地に**白い角丸の窓**を開け、その中に数字・記号を地の色で描く。
///
/// 窓の形（角丸の長方形）・記号（SF Symbols）・4 色の印（2 × 2 の角丸四角）はすべてこのアプリのために
/// 起こしたもので、既存製品の楕円の窓・書体・裏面の図案は写していない（Issue #1320 の権利面の注意）。
struct ColorRelayCardView: View {
    enum Size {
        case small, large
        /// 寸法はトランプ共通基盤（#397）の値を借りる。small = 42×60、large = 56×78。
        var metrics: PlayingCardMetrics { self == .small ? .compact : .medium }
    }

    let card: RelayCard
    var size: Size = .small
    var selected: Bool = false
    var hint: RelayCardHint = .none
    @Environment(\.adaptiveLayout) private var layout

    /// 出せない札は色に頼らず**明度**でも落として区別する。
    private var isDimmed: Bool { hint == .unplayable && !selected }

    private var metrics: PlayingCardMetrics { size.metrics.scaled(by: layout.elementScale) }

    /// 地の色。万能札は濃い地。
    private var faceColor: Color { card.color?.color ?? Theme.fillStrong }

    private var borderColor: Color {
        if selected { return Theme.ink }
        if hint == .playable { return Color.white }
        return Color.black.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        if selected { return 2.5 }
        return hint == .playable ? 2 : 0.5
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(faceColor)
                .shadow(color: selected ? Theme.ink.opacity(0.5) : .black.opacity(0.15),
                        radius: selected ? 6 : 3, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
            // 窓。上下に地を残し、四隅の小さな印が乗る余白を取る。
            RoundedRectangle(cornerRadius: metrics.cornerRadius * 0.7, style: .continuous)
                .fill(Color.white)
                .padding(.horizontal, metrics.width * 0.14)
                .padding(.vertical, metrics.height * 0.2)
            glyph(font: metrics.rankFont * 1.15)
            cornerMarks
        }
        .frame(width: metrics.width, height: metrics.height)
        .opacity(isDimmed ? 0.4 : 1)
    }

    /// 窓の中の記号。
    @ViewBuilder
    private func glyph(font: CGFloat) -> some View {
        switch card.kind {
        case .number(let n):
            Text("\(n)")
                .font(.system(size: font, weight: .black, design: .rounded))
                .foregroundStyle(faceColor)
        case .skip:
            Image(systemName: "circle.slash")
                .font(.system(size: font * 0.85, weight: .black))
                .foregroundStyle(faceColor)
        case .reverse:
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: font * 0.8, weight: .black))
                .foregroundStyle(faceColor)
        case .drawTwo:
            Text("+2")
                .font(.system(size: font * 0.85, weight: .black, design: .rounded))
                .foregroundStyle(faceColor)
        case .wild:
            FourColorMark(size: font * 1.1)
        case .wildDrawFour:
            VStack(spacing: 1) {
                FourColorMark(size: font * 0.7)
                Text("+4")
                    .font(.system(size: font * 0.5, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.fillStrong)
            }
        }
    }

    /// 四隅の小さな印（左上と、180 度回した右下）。重なった手札でも種類が読めるようにする。
    private var cornerMarks: some View {
        let font = metrics.suitFont * 0.55
        return VStack {
            HStack {
                cornerMark(font: font)
                Spacer()
            }
            Spacer()
            HStack {
                Spacer()
                cornerMark(font: font)
                    .rotationEffect(.degrees(180))
            }
        }
        .padding(metrics.width * 0.06)
    }

    @ViewBuilder
    private func cornerMark(font: CGFloat) -> some View {
        switch card.kind {
        case .number(let n):
            Text("\(n)")
                .font(.system(size: font, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        case .skip:
            Image(systemName: "circle.slash")
                .font(.system(size: font * 0.9, weight: .black))
                .foregroundStyle(.white)
        case .reverse:
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: font * 0.85, weight: .black))
                .foregroundStyle(.white)
        case .drawTwo:
            Text("+2")
                .font(.system(size: font * 0.9, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        case .wild:
            FourColorMark(size: font, spacing: 1)
        case .wildDrawFour:
            Text("+4")
                .font(.system(size: font * 0.9, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// 山札の裏。濃い地に内枠と 4 色の印。トランプの裏（`PlayingCardBack`）とは別の図案にする。
struct ColorRelayCardBack: View {
    let metrics: PlayingCardMetrics

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(Theme.fillStrong)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            RoundedRectangle(cornerRadius: metrics.cornerRadius * 0.6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                .padding(4)
            FourColorMark(size: metrics.backMotifFont)
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

// MARK: - Rule Sheet

struct ColorRelayRuleSheet: View {
    static let rules: [(String, String)] = [
        ("ゲームの流れ", "CPU3人と対戦します。7枚ずつ配り、場の札と同じ色か同じ数字・記号の札を順番に出します。手札を先になくした人が勝ちです"),
        ("引くとき", "出せる札が無いとき（出したくないときも）は山から1枚引きます。引いた札が出せるならそのまま出せます（出さずに次へ回してもかまいません）。出せなければ自動で次の人の番になります"),
        ("とばし", "次の人の番を飛ばします"),
        ("ぎゃく", "番の回る向きが逆になります"),
        ("+2", "次の人は山から2枚引き、番を飛ばされます"),
        ("いろがえ", "どの札の上にも出せて、次の色を自分で選べます"),
        ("いろがえ+4", "いろがえに加えて、次の人は4枚引いて番を飛ばされます"),
        ("引き札の免除", "+2 / いろがえ+4 を受けたとき、広告を見ると1ゲームに1回だけ引かずに済みます（番は飛ばされます）"),
        ("順位", "上がった人が1位。残りは手札の少ない順です。次のゲームは親が1人ずつ回ります"),
    ]

    var body: some View {
        RuleListSheet(title: "ルール", rules: Self.rules)
    }
}
