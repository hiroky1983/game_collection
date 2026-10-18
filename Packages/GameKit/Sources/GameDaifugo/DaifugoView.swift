import SwiftUI
import Core

public struct DaifugoView: View {
    @State private var model: DaifugoModel
    private let services: GameServices
    @State private var showResignConfirm = false
    /// 大貧民の献上を広告で免除する救済（#1048）。
    @State private var waiveRescue = RewardedRescue()
    /// ボタンから起こす CPU の手番。画面を離れたら止める（#1380。`.task` と違いボタンの Task は自動で止まらない）。
    @State private var cpuTask: Task<Void, Never>?
    /// 画面の広さ（#458）。場の空き枠を札と同じ倍率で拡大するために読む。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: DaifugoModel(services: services))
    }

    public var body: some View {
        // 縦の狭い画面(iPhone SE)で固定 pt の中身が溢れないよう、使える高さで寸法を選ぶ(#2455)。
        GeometryReader { geometry in
            let metrics = DaifugoVerticalMetrics.metrics(forHeight: geometry.size.height)
            VStack(spacing: metrics.spacing) {
                statusBar
                cpuRow(metrics)
                // 決着後は場も手札も空になるので、代わりに階級のリザルトを出す。
                //
                // 縦の余りは `Spacer` ではなく**場 / リザルトのカード自身**に吸わせる（#193）。
                // `Spacer` に吸わせると、その分がまるごと背景色の空白として残る（iPhone 17 Pro 実測で
                // 場と手札の間に 131pt、リザルトの下に 174pt）。カード側を伸ばせば同じ余りが「広い場」
                // 「大きなリザルト」になり、背景の空白は 0pt になる。
                if model.phase == .result {
                    resultCard
                        .transition(.opacity)
                } else {
                    fieldArea(metrics)
                        .transition(.opacity)
                    handArea(metrics)
                        .transition(.opacity)
                }
                HowToPlayHint(.daifugo, playLog: services.playLog)
                actionArea
                RecommendationSlot(services: services, isFinished: model.phase == .result)
                BannerSlot(ads: services.ads)
            }
            // 局面 → リザルトの差し替えは、上の `transition` を効かせるために**入れ替わる側ではなく
            // 残り続ける親**へ置く（枝の中に置くと消える側と一緒に修飾子も消えて効かない）（#195）。
            .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
            .padding(metrics.pad)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .gameChrome(title: daifugoGameName(), review: services.review)
        // 革命・8切り・階級まで含む細かいルールは3行に収まらないので「くわしいルール」へ送る（#118）。
        .howToPlay(HowToPlayGuide.daifugo.illustrated(DaifugoHowToFigures.items)) { DaifugoRuleSheet() }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("投了しますか？"), isPresented: $showResignConfirm, titleVisibility: .visible) {
                Button(tr("投了する"), role: .destructive) { model.resign() }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("今のゲームを打ち切ります。あなたは大貧民になり、負けとして記録されます。"))
            }
        }
        // 献上免除の提示（#780 × #1048）。大貧民のリザルトでボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(waiveRescue, for: .revival, isPresented: model.canWaiveExchange,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            waiveRescue,
            notEarned: tr("カード交換を免除できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("カード交換を免除できませんでした"),
                message: tr("広告を見ているあいだに次のゲームが始まったため、免除できませんでした。")
            )
        )
        .task {
            // 開幕の全画面モーダルは廃止したので、盤を見せたまま既定値で配り始める（#192）。
            // 中断から戻ったときは init が `.playing` まで復元しているので配り直さない。
            if model.phase == .idle { model.startGame() }
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
        .onDisappear { cpuTask?.cancel() }
    }

    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        GameStatusBar {
            Label(tr("%lldゲーム目", max(model.gameNumber, 1)), systemImage: "number")
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
            if model.isRevolution {
                Text(tr("革命中"))
                    .scaledFont(12, weight: .black, design: .rounded)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        } trailing: {
            TurnBadge(turnLabel, kind: turnKind)
        }
    }

    private var turnKind: TurnBadge.Kind {
        switch model.phase {
        case .idle, .result: return .finished
        case .playing: return model.isPlayerTurn ? .you : .cpu
        }
    }

    private var turnLabel: String {
        switch model.phase {
        case .idle:    return tr("開始待ち")
        case .result:  return tr("決着")
        case .playing: return model.isPlayerTurn ? tr("あなたの番") : tr("%@の番", model.playerName(model.currentPlayer))
        }
    }

    // MARK: - CPU

    private func cpuRow(_ metrics: DaifugoVerticalMetrics) -> some View {
        HStack(spacing: 8) {
            ForEach(1..<DaifugoModel.playerCount, id: \.self) { index in
                cpuCard(index, metrics)
            }
        }
    }

    /// CPU の席・場のラベルが文字サイズ設定で拡大する上限倍率（#1782）。3 人を横に並べる密な帯なので、
    /// 際限なく拡大すると席が押し合う。上限を超える分は `minimumScaleFactor` で縮めて 1 行に収める。
    private static let seatTextMaxScale: CGFloat = 1.6

    private func cpuCard(_ index: Int, _ metrics: DaifugoVerticalMetrics) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .themeCaption(12, maxScale: Self.seatTextMaxScale)
                    .foregroundStyle(model.currentPlayer == index && model.phase == .playing ? Theme.coralText : Theme.inkSub)
                Text(model.playerName(index))
                    .themeCaption(12, maxScale: Self.seatTextMaxScale)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(tr("残り%lld枚", model.hands[index].count))
                .themeCaption(11, weight: .semibold, maxScale: Self.seatTextMaxScale)
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(model.lastActions[index].isEmpty ? " " : model.actionLabel(index))
                .themeCaption(10, maxScale: Self.seatTextMaxScale)
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(model.lastActions[index].isEmpty ? Color.clear : Theme.Fill.purple))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.seatVerticalPadding).padding(.horizontal, 6)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 場

    private func fieldArea(_ metrics: DaifugoVerticalMetrics) -> some View {
        VStack(spacing: 6) {
            fieldHeader
            HStack(spacing: 6) {
                if model.field.isEmpty {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.inkSub.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        // 場の札（`.large` = 56×78）と同じ枠。札が広い画面で拡大するので
                        // ここも一緒に拡大しないと、札が出た瞬間に場の高さが跳ねる（#458）。
                        .frame(width: layout.scaled(56), height: layout.scaled(78))
                        .transition(.opacity)
                } else {
                    ForEach(model.field) { card in
                        DaifugoCardView(card: card, size: .large)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        // 縦の余りをここで吸い、場と手札の間に背景の空白を残さない（#193）。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, metrics.fieldVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
        // 誰が出しても場は同じ経路（`field` の差し替え）で更新されるので、CPU の手も人間の手も
        // ここ1箇所で演出できる。見出しの「場は流れています」も同じ変化で切り替わる（#195）。
        .gameAnimation(.easeInOut(duration: 0.18), value: model.field)
        // 場は「何が出ているか」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DaifugoAccessibility.fieldLabel(model.field, ownerName: fieldOwnerName))
    }

    /// 場の出し手（`fieldOwner`）の名前。場が空 / 出し手が不明なら nil。
    private var fieldOwnerName: String? {
        guard !model.field.isEmpty, let owner = model.fieldOwner else { return nil }
        return model.playerName(owner)
    }

    /// 場の見出し。組が出ているときは**誰が出したか**をバッジで添える（#193）。
    /// 出し手が分からないと、パスして流れたときに親が誰になるか・自分が越えるべき相手が誰かを読めない。
    @ViewBuilder
    private var fieldHeader: some View {
        if let ownerName = fieldOwnerName {
            let isHuman = model.fieldOwner == DaifugoModel.humanIndex
            HStack(spacing: 4) {
                Image(systemName: isHuman ? "person.fill" : "cpu")
                    .themeCaption(10, maxScale: Self.seatTextMaxScale)
                Text(isHuman ? tr("あなたが出した") : tr("%@が出した", ownerName))
                    .themeCaption(11, maxScale: Self.seatTextMaxScale)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(isHuman ? Theme.Fill.teal : Theme.Fill.purple))
        } else {
            Text(model.field.isEmpty ? tr("場は流れています（好きな組を出せます）") : tr("場"))
                .themeCaption(11, weight: .semibold, maxScale: Self.seatTextMaxScale)
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    // MARK: - 手札

    private func handArea(_ metrics: DaifugoVerticalMetrics) -> some View {
        // 1枚ごとに引くと合法手の探索が手札の枚数ぶん走るので、ここで1回だけ求める（#190）。
        let handHint = model.handHint
        return VStack(spacing: 6) {
            HStack {
                Text(tr("あなた（残り%lld枚）", model.playerHand.count))
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !model.lastActions[DaifugoModel.humanIndex].isEmpty {
                    Text(model.actionLabel(DaifugoModel.humanIndex))
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.tealText)
                }
            }
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: DaifugoHandLayout.columnSpacing),
                    count: DaifugoHandLayout.columns
                ),
                spacing: DaifugoHandLayout.rowSpacing
            ) {
                ForEach(model.playerHand) { card in
                    let isSelected = model.selected.contains(card.id)
                    let hint = handHint?.state(for: card.id) ?? .none
                    DaifugoCardView(card: card, size: .small, selected: isSelected, hint: hint)
                        .offset(y: isSelected ? -6 : 0)
                        .gameAnimation(.spring(response: 0.2), value: isSelected)
                        // 見えるカードは 42pt のまま、タップ判定だけを列いっぱいに広げて
                        // 44pt 以上にする（#195）。`offset` は判定の位置に影響しない。
                        .frame(maxWidth: .infinity, minHeight: DaifugoHandLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggleSelection(card) }
                        .transition(.scale.combined(with: .opacity))
                        // カードは `onTapGesture` で組んでいるため、Button と違って
                        // ボタン trait も読み上げ文も自動では付かない（#188）。
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            DaifugoAccessibility.handCardLabel(card, isSelected: isSelected, hint: hint)
                        )
                        .accessibilityHint(tr("ダブルタップで選択を切り替えます"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.toggleSelection(card) }
                        // CPU の手番では `toggleSelection` が何もしないので、
                        // 操作可能として案内しない（描画は素の図形なので見た目は変わらない）。
                        .disabled(!model.isPlayerTurn)
                }
            }
            // 出した札が手札から消える／交換で増える変化を演出する（#195）。
            .gameAnimation(.easeInOut(duration: 0.18), value: model.playerHand)
            hintLine(handHint)
        }
        .padding(.horizontal, DaifugoHandLayout.horizontalPadding).padding(.vertical, metrics.handVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 手札の下に出す1行の案内（#190）。
    /// 出せない組を選んでいればその理由を、選んでいなければ「1枚も出せない」ときだけ助言を出す。
    @ViewBuilder
    private func hintLine(_ handHint: DaifugoHandHint?) -> some View {
        let message = model.selectionIssue
            ?? (handHint?.playable.isEmpty == true ? tr("出せる組がありません。パスしてください") : nil)
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .scaledFont(11, weight: .bold)
                Text(message)
                    // 受け入れ条件どおり1行に収める。文字を拡大しても高さが跳ねないよう縮めて入れる（#189）。
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.coralText)
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
        case .playing where model.isPlayerFinished:
            // 自分が上がった後は操作が無くなるので、無効なパス／出すではなく早送りを出す（#191）。
            actionButton(tr("結果まで進める"), role: .primary, disabled: model.isSkippingToResult) {
                model.skipToResult()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .playing:
            HStack(spacing: 12) {
                actionButton(tr("パス"), role: .skip, disabled: !model.canPass) {
                    model.pass()
                    runCPU()
                }
                actionButton(playButtonTitle, role: .primary, disabled: !model.canPlaySelection) {
                    model.playSelected()
                    runCPU()
                }
                // 投了は盤下の「⋯」メニューに入れる（#1418・会長決裁 #1011 D1）。ヘッダー右は
                // 役・？・新規の並びに固定するため文字の「投了」は置けない。中断すると次回は必ず
                // 「続きから」に戻るので、局面を降りる導線としてここに残す（#194）。
                Menu {
                    Button(tr("投了"), role: .destructive) { showResignConfirm = true }
                        .disabled(!model.canResign)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .scaledFont(17, weight: .semibold)
                        .frame(width: 44)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("その他の操作"))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            VStack(spacing: 8) {
                if model.canWaiveExchange {
                    waiveExchangeButton
                }
                // 視聴中に次のゲームを始めると、見終えた広告が局ガードで弾かれて見損になる（#911 と同型）。
                actionButton(tr("次のゲーム"), role: .primary, disabled: waiveRescue.isWatching) {
                    model.startGame()
                    runCPU()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    /// 大貧民のリザルトにだけ出す「広告を見て献上を免除」（#1048）。
    private var waiveExchangeButton: some View {
        Button {
            // 視聴完了（報酬獲得）したときだけ免除する。どのゲームの決着に対するものかを広告の前に控え、
            // 視聴中に次のゲームが始まっていたら乗せない（#729）。
            let game = model.gameNumber
            waiveRescue.request(
                services, gameID: model.gameID, purpose: .revival,
                guardedBy: .checkedByGrant
            ) {
                model.waiveExchangeAfterAd(forGame: game)
            }
        } label: {
            Label(tr("広告を見て次のカード交換を免除"), systemImage: "play.rectangle.fill")
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(waiveRescue.isWatching)
    }

    private var playButtonTitle: String {
        model.selected.isEmpty ? tr("カードを選ぶ") : tr("%lld枚出す", model.selected.count)
    }

    // MARK: - リザルト

    /// リザルト見出しに添える但し書き。投了は反則上がりより下の扱いなので先に見る（#194）。
    private var humanResultNote: String? {
        if model.resigned.contains(DaifugoModel.humanIndex) { return tr("投了") }
        if model.fouls.contains(DaifugoModel.humanIndex) { return tr("反則上がり") }
        return nil
    }

    /// 順位表の各行に添える但し書き（見出しより短く詰める）。
    private func rankRowNote(_ player: Int) -> String? {
        if model.resigned.contains(player) { return tr("投了") }
        if model.fouls.contains(player) { return tr("反則") }
        return nil
    }

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.playerPlace == 0 ? "crown.fill" : "flag.checkered")
                    .scaledFont(20)
                    .foregroundStyle(model.playerPlace == 0 ? Theme.yellowText : Theme.inkSub)
                Text(tr("あなたは %@", model.playerTitle))
                    .scaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle(model.playerPlace == 0 ? Theme.tealText : Theme.ink)
                if let note = humanResultNote {
                    Text(note)
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                Spacer()
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.element) { place, player in
                    HStack(spacing: 8) {
                        Text(DaifugoRules.title(forPlace: place))
                            .scaledFont(12, weight: .black, design: .rounded)
                            // 1位だけ差し色の面。他は濃いグレーの面なので文字色を分ける（#220）。
                            .foregroundStyle(place == 0 ? Theme.onAccent : .white)
                            // 幅が固定の札なので、英語の階級名（Tycoon など）が長くても 1 行に縮めて収める（#2166）。
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 58)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(place == 0 ? Theme.Fill.yellow : Theme.fillMuted))
                        Text(model.playerName(player))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .foregroundStyle(player == DaifugoModel.humanIndex ? Theme.coralText : Theme.ink)
                        if let note = rankRowNote(player) {
                            Text(note)
                                .scaledFont(10, weight: .bold, design: .rounded)
                                .foregroundStyle(Theme.coralText)
                        }
                        Spacer()
                    }
                }
            }
            // 「今回の結果」（見出し・順位表）を上、「この先」（通算成績・次ゲームの案内）を下に置き、
            // 伸びた分の余りは2つの塊の**間**に集める（#193）。カード全体を中央寄せにすると
            // 見出しが画面の真ん中まで降りてきてしまうので、間に寄せる。
            Spacer(minLength: 8)
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(exchangeNote)
                .scaledFont(11, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.inkSub)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 縦の余りをここで吸い、リザルトの下に背景の空白を残さない（#193）。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 次のゲームのカード交換の案内。広告で献上を免除したら、免除したことを伝える（#1048）。
    private var exchangeNote: String {
        model.isExchangeWaived
            ? tr("次のゲームは大富豪⇔大貧民のカード交換を免除します（富豪⇔貧民は1枚ずつ交換します）")
            : tr("次のゲームは階級に応じてカードを交換します（大富豪⇔大貧民 2枚 / 富豪⇔貧民 1枚）")
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
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .disabled(disabled)
    }
}

// MARK: - 手札グリッドの寸法

/// 手札グリッドの寸法（#195）。
///
/// 見た目のカード幅は 42pt（`DaifugoCardView.Size.small`）のままで、**タップ判定だけ**を
/// 列いっぱいに広げて 44pt 以上にする。列は `GridItem(.flexible())` なので実効幅は画面幅で決まり、
/// 列間隔 4pt のままでは最小構成の端末で 44pt を割っていた。間隔を 0 にして幅を列へ回し、
/// 見た目の隙間は「列幅 − カード幅」で従来とほぼ同じに保つ。
///
/// 実効幅の計算をここに置いてビュー側からも参照するのは、寸法を変えたときに
/// `DaifugoHandLayoutTests` の検証と実装がずれないようにするため。
enum DaifugoHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 6
    /// 手札カード（`popCard`）の内側の左右余白。
    static let horizontalPadding: CGFloat = 12
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 画面幅 `screenWidth` のときの、手札1枚あたりのタップ判定の幅。
    /// 画面外周の `Theme.pad` と手札カードの内側余白を引いた残りを列数で割る。
    static func tapWidth(screenWidth: CGFloat) -> CGFloat {
        let available = screenWidth - Theme.pad * 2 - horizontalPadding * 2
        return (available - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }
}

// MARK: - Card View

struct DaifugoCardView: View {
    enum Size {
        case small, large
        /// 寸法はトランプ共通基盤（#397）の定義を使う。small = 42×60、large = 56×78。
        var metrics: PlayingCardMetrics { self == .small ? .compact : .medium }

        // 手札レイアウト（#190 のタップ判定）が参照する寸法。共通基盤の値をそのまま返す。
        var width: CGFloat { metrics.width }
        var height: CGFloat { metrics.height }
    }

    let card: DaifugoCard
    var size: Size = .small
    var selected: Bool = false
    /// 出せる / 出せないの区別（#190）。`.none` なら素の見た目のまま。
    var hint: DaifugoCardHint = .none
    /// 画面の広さ（#458）。手札の**列幅**は `.flexible()` なので iPad で勝手に広がるのに、
    /// 札の絵柄だけ 42pt 固定で取り残され、列のあいだの隙間だけが開いていた。
    @Environment(\.adaptiveLayout) private var layout

    /// 出せない札は色に頼らず**明度**でも落として区別する（色覚特性の影響を受けないため）。
    private var isDimmed: Bool { hint == .unplayable && !selected }

    private var borderColor: Color {
        if selected { return Theme.coral }
        if hint == .playable { return Theme.teal }
        return Color.gray.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        if selected { return 2 }
        return hint == .playable ? 1.5 : 0.5
    }

    /// 広い画面向けに相似拡大した寸法（#458）。狭い画面では `size.metrics` と同じ値になる。
    private var metrics: PlayingCardMetrics { size.metrics.scaled(by: layout.elementScale) }

    var body: some View {
        ZStack {
            // 外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。大富豪は常に表向き。
            PlayingCardSurface(
                cornerRadius: metrics.cornerRadius,
                border: borderColor,
                borderWidth: borderWidth,
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )

            // ジョーカーの図案は共通基盤の道化帽（#397 で新調。従来は star.fill だった）。
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
        .opacity(isDimmed ? 0.4 : 1)
    }
}

// MARK: - Rule Sheet

struct DaifugoRuleSheet: View {
    /// 表示用なので、その時点の言語で引く（#2166）。
    private var rules: [(String, String)] {
        [
            // 廃止した開幕モーダル（#192）が持っていた「誰と何人で戦うのか」をここへ移した。
            // 残りの3項目（出し方・パス・カード交換）は下の項目と `HowToPlayGuide.daifugo` に既にある。
            (tr("ゲームの流れ"), tr("CPU3人と対戦します。手札を早く出し切るほど上の階級になり、決着すると階級に応じてカードを交換して次のゲームへ進みます")),
            (tr("カードの強さ"), tr("弱い ← 3 4 5 6 7 8 9 10 J Q K A 2 → 強い。ジョーカーが最強で、どのカードの代わりにもなります")),
            (tr("出し方"), tr("場が空なら好きな組（1枚・ペア・3枚…）を出せます。場に組があるときは同じ枚数で、より強い組だけ出せます")),
            (tr("革命"), tr("同じ数字を4枚以上まとめて出すと革命。カードの強さが上下逆になります（もう一度出すと元に戻ります）")),
            (tr("8切り"), tr("8 を含む組を出すと場が流れ、そのまま続けて出せます")),
            (tr("反則上がり"), tr("最後の1手が 2・8・ジョーカーだと反則。上がっても大貧民に落ちます")),
            (tr("階級とカード交換"), tr("上がった順に 大富豪・富豪・貧民・大貧民。次のゲームは 大貧民→大富豪 に強い2枚、大富豪→大貧民 に弱い2枚（富豪と貧民は1枚ずつ）を渡します")),
        ]
    }

    var body: some View {
        RuleListSheet(rules: rules)
    }
}

/// 画面の中身に使える高さで変える縦の寸法（#2455）。`AdaptiveLayout`（#458）は幅しか持たないので、
/// 縦の狭さはこの画面で持つ。iPhone SE（第 3 世代・使える高さ約 593pt）では固定 pt の中身が
/// 初回ミニガイド・手札下の案内込みで約 670pt になり、溢れた分が上下に出てヘッダー下の帯がナビバーに潜る。
enum DaifugoVerticalMetrics: Equatable {
    case regular
    case compact

    /// 「縦が狭い」と見なす境目（pt）。通常寸法が要る高さ（ミニガイド・案内込みで約 670pt）より上に置く。
    /// iPhone SE は約 593pt・13 mini は約 687pt で詰める側、iPhone 17 は約 724pt で通常の側。
    static let compactHeightThreshold: CGFloat = 690

    static func metrics(forHeight height: CGFloat) -> DaifugoVerticalMetrics {
        height < compactHeightThreshold ? .compact : .regular
    }

    /// 要素どうしの縦の間隔。
    var spacing: CGFloat { self == .regular ? 8 : 4 }
    /// 画面の外周の余白。
    var pad: CGFloat { self == .regular ? Theme.pad : 8 }
    /// CPU の席の上下の余白。
    var seatVerticalPadding: CGFloat { self == .regular ? 10 : 6 }
    /// 場の上下の余白。
    var fieldVerticalPadding: CGFloat { self == .regular ? 22 : 10 }
    /// 手札の上下の余白。
    var handVerticalPadding: CGFloat { self == .regular ? 12 : 8 }

    /// 固定部分の高さの見積もり（ヘッダー下の帯 44 + 席 + 場の最小 + 手札 2 段 + 操作 60 + バナー 50 + ミニガイド 22 + 案内 14）。
    /// 場の最小は見出し 14 + 札 78 + 上下の余白、席は 56 + 上下の余白、手札は 2 段 172 - 24 + 上下の余白。
    /// 間隔は要素 8 つの 7 箇所。`DaifugoVerticalMetricsTests` が境目との整合を固定する。
    var estimatedMinimumHeight: CGFloat {
        let seat = 56 + seatVerticalPadding * 2
        let field = 14 + 6 + 78 + fieldVerticalPadding * 2
        let hand = 148 + handVerticalPadding * 2
        return 44 + seat + field + hand + 60 + 50 + 22 + 14 + spacing * 7 + pad * 2
    }
}
