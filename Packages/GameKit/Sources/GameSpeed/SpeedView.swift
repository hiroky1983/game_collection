import SwiftUI
import Core

/// スピード（#1323）のプレイ画面。
///
/// 上から: 速さと記録の見出し → CPU の手札と山札 → 台札 2 山 → あなたの手札と山札 → 操作
/// → 遊び方の 1 行 → レコメンド → バナー。手札は 4 枚固定の並びで、出した位置に補充されるので
/// 札の位置が動かない（狙った札を追いかけずに済む）。
///
/// CPU の待ちは Model が返す時間を `.task(id: model.cpuRun)` で待つだけ。場が動くたびに `cpuRun` が進んで
/// 前の待ちが止まり、画面を離れれば `.task` ごと止まる（`Timer` は持たない）。
public struct SpeedView: View {
    @State private var model: SpeedModel
    private let services: GameServices
    /// 負けそうなときに CPU を休ませる救済（広告 1 本で 1 ゲーム 1 回）。
    @State private var timeoutRescue = RewardedRescue()
    @State private var showSetup: Bool
    /// 画面の広さ（#458）。札と同じ倍率で拡大するために読む。
    @Environment(\.adaptiveLayout) private var layout
    /// バックグラウンドへ移ったら CPU を止める（アクション枠の基盤規約「即一時停止」。ブロック崩し・チャリンコおじさんと同じ）。
    @Environment(\.scenePhase) private var scenePhase

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
        // まだ 1 ゲームも始めていなければ速さのシートから入る。撮影で局面を差し替えたときは畳んだまま
        // （`.task` で開くとシートの提示と競合する）。
        _showSetup = State(initialValue: model.phase == .idle)
    }

    public var body: some View {
        VStack(spacing: 10) {
            header
            if model.phase == .result {
                resultCard
                    .transition(.opacity)
            } else {
                cpuArea
                    .transition(.opacity)
                tableArea
                    .transition(.opacity)
                handArea
                    .transition(.opacity)
            }
            actionArea
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.speed, playLog: services.playLog)
            RecommendationSlot(services: services, isFinished: model.phase == .result)
            BannerSlot(ads: services.ads)
        }
        // 局面 → リザルトの差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .gameChrome(title: "スピード", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button { showSetup = true } label: {
                    Label("速さ", systemImage: "slider.horizontal.3")
                }
                // 広告の視聴中は塞ぐ（速さを変えるとゲームが入れ替わり、見終えた広告のタイムが乗らない）。
                .disabled(timeoutRescue.isWatching)
            }
        }
        // シートを開いているあいだも CPU は止める（背面で出し切ると、読んでいる間に敗北が記録される。#1358）。
        .howToPlay(.speed, onPresent: { model.holdCPU(.sheet, true) }, onDismiss: { model.holdCPU(.sheet, false) }) {
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
            notEarned: "タイムを取れませんでした",
            unavailable: RewardUnavailableAlert(
                title: "タイムを取れませんでした",
                message: "広告を見ているあいだにゲームが終わったか、負けそうな局面ではなくなったため、タイムを取れませんでした。"
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
        // 「速さ」のシートも同じ（開いたまま置くと背面で CPU が出し続ける）。閉じたら再開する。
        .onChange(of: showSetup) { _, open in
            model.holdCPU(.sheet, open)
        }
        // CPU の待ちは Model が決め、ここは待つだけ。場が動くたびに `cpuRun` が進んで前のループが止まり、
        // 画面を離れれば `.task` ごと止まる。
        .task(id: model.cpuRun) { await runCPU() }
    }

    /// 同じ `cpuRun` のあいだだけ CPU を回す。場が動いて番号が変わったら、新しい `.task` に譲って抜ける
    /// （SwiftUI のキャンセルが届く前に同じループが 2 度動かないよう、番号でも見張る）。
    private func runCPU() async {
        let run = model.cpuRun
        while !Task.isCancelled, model.cpuRun == run, let wait = model.nextCPUWait() {
            do { try await Task.sleep(for: wait) } catch { return }
            guard !Task.isCancelled, model.cpuRun == run else { return }
            withGameAnimation { model.performCPUAction() }
        }
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CPU の速さ").themeCaption(11).foregroundStyle(Theme.inkSub)
                Text(model.settings.variantLabel)
                    .themeBody(15)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            stat("連勝", value: "\(model.streak)")
            if let best = model.bestSeconds {
                stat("最速", value: "\(best)秒")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).themeCaption(11).foregroundStyle(Theme.inkSub)
            Text(verbatim: value)
                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - CPU

    private var cpuMetrics: PlayingCardMetrics { PlayingCardMetrics.compact.scaled(by: layout.elementScale) }
    private var tableMetrics: PlayingCardMetrics { PlayingCardMetrics.standard.scaled(by: layout.elementScale) }

    private var cpuArea: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.isTimeoutActive ? Theme.inkSub : Theme.coral)
                Text(model.isTimeoutActive ? "タイム中" : "CPU")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: layout.scaled(56), alignment: .leading)
            HStack(spacing: 6) {
                ForEach(model.cpuHand) { card in
                    SpeedCardView(card: card, metrics: cpuMetrics)
                        .id(card.id)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .gameAnimation(.easeInOut(duration: 0.18), value: model.cpuHand)
            Spacer(minLength: 4)
            SpeedStockView(metrics: cpuMetrics, count: model.cpuStock.count)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
        // CPU 側は「何を持っていて山があと何枚か」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpeedAccessibility.cpuHandLabel(model.cpuHand, stockCount: model.cpuStock.count))
    }

    // MARK: - 台札

    private var tableArea: some View {
        HStack(spacing: 28) {
            ForEach(0..<SpeedRules.pileCount, id: \.self) { index in
                pileView(index)
            }
        }
        // 縦の余りはこの枠が吸う（`Spacer` を置くと中身が上下に散る。いろリレーの手札と同じ考え方）。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .overlay(alignment: .top) {
            if model.isStuck {
                Text("どちらも出せない！")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Fill.yellow))
                    .offset(y: -8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .gameAnimation(.easeInOut(duration: 0.18), value: model.isStuck)
    }

    private func pileView(_ index: Int) -> some View {
        let top = model.tops[index]
        let selected = model.selectedCard
        let accepts = selected.map { SpeedRules.canPlay($0, onto: top) } ?? false
        return Button { withGameAnimation { model.tapPile(index) } } label: {
            ZStack {
                if let top {
                    SpeedCardView(card: top, metrics: tableMetrics, highlighted: accepts)
                        .id(top.id)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    CardSlot(metrics: tableMetrics, systemImage: "arrow.down.to.line")
                }
            }
            .frame(width: tableMetrics.width, height: tableMetrics.height)
            // 見える札はそのまま、タップ判定だけを上下左右に広げて 44pt 以上を確保する。
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gameAnimation(.easeOut(duration: 0.15), value: top)
        .accessibilityLabel(SpeedAccessibility.pileLabel(index: index, top: top))
        .accessibilityHint(selected == nil ? "この台札に置ける手札が1枚だけならダブルタップで出します" : "ダブルタップで選択中の札を置きます")
    }

    // MARK: - 手札

    private var handArea: some View {
        let playable = model.humanPlayableIDs
        let showsHints = model.showsHints
        return HStack(spacing: SpeedHandLayout.spacing) {
            ForEach(model.humanHand) { card in
                let isSelected = model.selectedID == card.id
                let isPlayable = playable.contains(card.id)
                Button { withGameAnimation { model.tapHandCard(card) } } label: {
                    SpeedCardView(
                        card: card, metrics: tableMetrics, selected: isSelected,
                        highlighted: showsHints && isPlayable && !isSelected,
                        dimmed: showsHints && !isPlayable && !isSelected && model.phase == .playing
                    )
                    .offset(y: isSelected ? -8 : 0)
                    .gameAnimation(.spring(response: 0.2), value: isSelected)
                    .id(card.id)
                    .transition(.scale.combined(with: .opacity))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SpeedAccessibility.handCardLabel(card, isSelected: isSelected, isPlayable: isPlayable))
                .accessibilityHint("ダブルタップで台札に出します")
            }
            Spacer(minLength: 0)
            SpeedStockView(metrics: tableMetrics, count: model.humanStock.count)
                .accessibilityLabel(SpeedAccessibility.stockLabel(of: .human, count: model.humanStock.count))
        }
        .frame(maxWidth: .infinity)
        // 出した札が消える / 補充される変化を演出する。
        .gameAnimation(.easeInOut(duration: 0.18), value: model.humanHand)
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            Button { showSetup = true } label: {
                Text("はじめる").themeBody(18).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            .padding(.horizontal, 24)
        case .playing:
            VStack(spacing: 8) {
                if model.canUseTimeout {
                    timeoutButton
                }
                if model.canFlip {
                    actionButton("めくる（両方の山札から1枚ずつ）", color: Theme.Fill.coral) {
                        model.flipStocks()
                    }
                } else {
                    Text(statusText)
                        .themeBody(14)
                        .foregroundStyle(Theme.inkSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
            }
            .gameAnimation(.easeInOut(duration: 0.18), value: model.canFlip)
            .accessibilityElement(children: .contain)
        case .result:
            VStack(spacing: 10) {
                Button { withGameAnimation { model.restart() } } label: {
                    Label("もう一度", systemImage: "arrow.counterclockwise.circle.fill")
                        .themeBody(17).frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                Button { showSetup = true } label: {
                    Text("速さを変える").themeBody(15).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).tint(Theme.coral)
            }
            .padding(.horizontal, 24)
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
            Label("広告を見てタイム（CPU が8秒休む）", systemImage: "play.rectangle.fill")
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(timeoutRescue.isWatching ? Theme.inkSub.opacity(0.3) : Theme.Fill.teal,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(timeoutRescue.isWatching ? Theme.inkSub : Theme.onAccent)
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
                    .font(.system(size: 20))
                    .foregroundStyle(model.winner == .human ? Theme.yellow : Theme.inkSub)
                Text(statusText)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(model.winner == .human ? Theme.teal : Theme.ink)
                Spacer()
            }
            VStack(spacing: 4) {
                resultRow("あなた", remaining: model.remaining(of: .human), isWinner: model.winner == .human)
                resultRow("CPU", remaining: model.remaining(of: .cpu), isWinner: model.winner == .cpu)
            }
            if let seconds = model.winSeconds {
                // 記録の 1 行（`RecordLabel`）は勝敗の指標なので秒数を出さない。最速を更新した回は
                // 「自己ベスト更新！」の中身がここで分かるように添える。
                Text(verbatim: model.recordResult?.update.seconds == true ? "所要 \(seconds)秒（最速！）" : "所要 \(seconds)秒")
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private func resultRow(_ name: String, remaining: Int, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isWinner ? "勝ち" : "　")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44)
                .padding(.vertical, 3)
                .background(Capsule().fill(isWinner ? Theme.Fill.yellow : Color.clear))
            Text(name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(name == "あなた" ? Theme.coral : Theme.ink)
            Spacer()
            Text(remaining == 0 ? "出し切り" : "残り\(remaining)枚")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 手札の寸法

/// 手札の並びの寸法。札 4 枚 + 山札 1 枚を横 1 列に置くので、iPhone SE の幅（375pt）に収まる間隔にする。
enum SpeedHandLayout {
    static let spacing: CGFloat = 8

    /// 画面幅 `screenWidth` のときに、標準の札 5 枚（手札 4 + 山札）が収まるか。
    static func fits(screenWidth: CGFloat) -> Bool {
        let available = screenWidth - Theme.pad * 2
        let needed = PlayingCardMetrics.standard.width * 5 + spacing * 4
        return needed <= available
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
                    .font(.system(size: metrics.rankFont * 0.7, weight: .black, design: .rounded).monospacedDigit())
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
            title: "CPU の速さをえらぶ", startTitle: "スタート",
            onStart: { onStart(settings) }, onCancel: onCancel
        ) {
            GameSetupSection("速さ") {
                HStack(spacing: 12) {
                    ForEach(SpeedLevel.allCases, id: \.self) { level in
                        GameSetupChooser(title: level.label, subtitle: level.subtitle,
                                         selected: settings.level == level,
                                         accent: Theme.Fill.coral, metrics: Self.metrics) {
                            settings.level = level
                        }
                    }
                }
                Text("あなたに制限時間はありません。設定の「ゆっくりモード」をオンにすると、CPU はさらにゆっくりになります。")
                    .themeCaption(11)
                    .foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Rule Sheet

struct SpeedRuleSheet: View {
    static let rules: [(String, String)] = [
        ("ゲームの流れ", "トランプを赤（♥♦）と黒（♠♣）の26枚ずつに分け、あなたが赤、CPU が黒を使います。手札は4枚。真ん中の台札2山に、手札から札を重ねていきます"),
        ("出せる札", "台札の数字と1つ違いの札（台札が7なら6か8）。A と K もつながります。マークは関係ありません"),
        ("順番はない", "出せる札があればいつでも出せます。CPU も同時に出してくるので、早い者勝ちです。あなたの側に制限時間はありません"),
        ("補充", "札を出すと、自分の山札から手札に1枚補充されます（手札はいつも4枚まで）"),
        ("つまったら", "どちらも出せる札が無くなったら「めくる」。両方の山札から1枚ずつ台札に置きます。山札が無いときは、自分側の台札を切り直して山札にします"),
        ("勝ち", "手札と山札を先に出し切ったほうの勝ち。めくるだけが続いて場が動かないときは引き分けです"),
        ("タイム", "負けそうなとき（CPU の残りが8枚以下で、あなたより少ないとき）、広告を見ると1ゲームに1回だけ CPU が8秒休みます"),
        ("速さ", "CPU の反応は「ゆっくり / ふつう / はやい」から選べます。設定の「ゆっくりモード」をオンにすると、さらにゆっくりになります"),
    ]

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
