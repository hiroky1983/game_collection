import SwiftUI
import Core

/// ルーレットの画面。
///
/// #2364（会長決裁 2026-10-17）でホイールを主役にした。画面は 2 つで、どちらを出すかは
/// `RouletteScreen.of(phase:sessionOver:)` が局面から決める。
/// - **賭けの画面（案 A）**: ホイールを余った高さいっぱいに取り、賭けの表は「数字」「赤黒・区分」の
///   タブで切り替える。
/// - **ホイールの画面（案 B）**: 「スピン」を押した瞬間にホイールを画面いっぱいに出して回し、止まったら
///   出目と収支をホイールの中心に大きく出す。「同じ賭けでもう一度」「次のゲーム」で賭けの画面へ戻る。
public struct RouletteView: View {
    @State private var model: RouletteModel
    private let services: GameServices
    /// 画面の広さ（#458）。マスの高さを同じ倍率で拡大する。
    @Environment(\.adaptiveLayout) private var layout
    /// Reduce Motion。ON ならホイールは回らず止まる位置へ飛ぶので、結果も待たせずに出す。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// チップ切れ復活のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var reviveRescue = RewardedRescue()
    /// ホイールの累積回転角（度）。止まった位置を保ったまま、スピンごとに数周ぶん増える
    /// （巻き戻すと逆回転になるので減らさない）。
    @State private var wheelRotation: Double = 0
    /// 賭けの表で開いているタブ（#2364）。回して戻ってきても同じタブのまま。
    @State private var betTab: RouletteBetTab = .numbers

    public init(services: GameServices) {
        self.services = services
        var spinInterval = RouletteMotion.spinInterval
        #if DEBUG
        // 撮影用: `-rouletteSpinSeconds <秒>` で回転の長さを変え、回っている途中を止めて撮る。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-rouletteSpinSeconds"), i + 1 < args.count,
           let seconds = Double(args[i + 1]) {
            spinInterval = .milliseconds(Int(seconds * 1000))
        }
        #endif
        _model = State(initialValue: RouletteModel(services: services, spinInterval: spinInterval))
    }

    /// いま出す画面（賭け / ホイール）。
    private var screen: RouletteScreen {
        RouletteScreen.of(phase: model.phase, sessionOver: model.sessionOver)
    }

    public var body: some View {
        // 縦の狭さ（iPhone SE）はこの画面で測る。`AdaptiveLayout` は幅しか持たない（#458）。
        GeometryReader { geometry in
            let sizing = RouletteMetrics.sizing(forHeight: geometry.size.height)
            VStack(spacing: sizing.stackSpacing) {
                // ホイールは余った高さいっぱいに取る（下の部品はどれも高さが決まっている）。
                switch screen {
                case .betting:
                    bettingWheelCard
                    tableCard(sizing)
                case .wheel:
                    wheelScreen
                }
                HowToPlayHint(.roulette, playLog: services.playLog)
                if model.sessionOver {
                    sessionOverView(sizing)
                } else {
                    actionArea(sizing)
                }
                RecommendationSlot(services: services, isFinished: model.phase == .result || model.sessionOver)
                BannerSlot(ads: services.ads)
            }
            .padding(Theme.pad)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            // 「スピン」で賭けの画面からホイールの画面へ、「次のゲーム」で戻る。どちらも溶けるように切り替える。
            .gameAnimation(RouletteMotion.screenSwap, value: screen)
        }
        .rewardOffer(reviveRescue, for: .revival, isPresented: model.canReviveAfterBust,
                     services: services, gameID: model.gameID)
        .gameChrome(title: tr("ルーレット"), review: services.review)
        .howToPlay(HowToPlayGuide.roulette.illustrated(RouletteHowToFigures.items)) { RouletteRuleSheet() }
        .onAppear {
            // 回転中に中断して戻ってきたときも、保存された出目の位置まで回す。
            if model.phase == .spinning { spinWheel() }
            #if DEBUG
            // 撮影・動作確認用: `-simulateRouletteSpin` で赤・1〜12・数字 17 に置いて回す。
            // 出目が乱数なので、回っている途中は `-rouletteSpinSeconds` と組み合わせて止めて撮る。
            if ProcessInfo.processInfo.arguments.contains("-simulateRouletteSpin"), model.canBet, model.bets.isEmpty {
                model.selectedChip = 50
                model.placeBet(.red)
                model.placeBet(.dozen(1))
                model.placeBet(.straight(17))
                model.spin()
            }
            // `-simulateRouletteBust` は全額を 0 に置いて回す（37 回に 36 回はチップ切れの画面になる）。
            if ProcessInfo.processInfo.arguments.contains("-simulateRouletteBust"), model.canBet, model.bets.isEmpty {
                model.selectedChip = 500
                model.placeBet(.straight(0))
                model.placeBet(.straight(0))
                model.spin()
            }
            #endif
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .spinning { spinWheel() }
        }
        .rewardedRescueAlerts(
            reviveRescue,
            notEarned: tr("チップは回復しませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("チップは回復しませんでした"),
                message: tr("広告を見ているあいだにセッションが変わったため、復活は適用していません。復活の回数は減っていません。")
            )
        )
    }

    /// 出目のポケットが玉の真下に来るまでホイールを回す。
    ///
    /// Reduce Motion が ON なら `withGameAnimation` が補間を落とし、ホイールは止まる位置へ即座に飛ぶ。
    /// そのまま Model の待ちを残すと、玉の真下に出目が見えているのに「回転中…」が 2.6 秒続くので、
    /// 待ちも飛ばして結果を出す。
    private func spinWheel() {
        guard let number = model.winningNumber else { return }
        let index = RouletteWheel.pocketIndex(of: number)
        withGameAnimation(RouletteMotion.spin) {
            wheelRotation = RouletteMotion.targetRotation(from: wheelRotation, toPocket: index)
        }
        if reduceMotion {
            model.skipSpin()
        }
    }

    /// 「結果まで進める」。走っている回転を止まる位置へ飛ばしてから精算する
    /// （止めないと、結果が出たあともホイールが回り続け、玉の真下と出目が一時的に食い違う）。
    private func skipSpin() {
        withGameAnimation(nil) {
            wheelRotation = RouletteMotion.snapped(wheelRotation)
        }
        model.skipSpin()
    }

    // MARK: - Wheel

    /// ホイール本体。`diameter` は呼び出し側が枠から測って渡す。
    private func wheel(diameter: CGFloat) -> some View {
        RouletteWheelView(
            rotation: wheelRotation,
            highlighted: model.phase == .result ? model.winningNumber : nil
        )
        .frame(width: diameter, height: diameter)
    }

    /// 余った枠いっぱいのホイール。中心（ハブ）には回転中・結果の表示を重ねる。
    private var flexibleWheel: some View {
        GeometryReader { proxy in
            let diameter = RouletteMetrics.wheelDiameter(fitting: proxy.size)
            ZStack {
                wheel(diameter: diameter)
                hubOverlay(diameter: diameter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// ホイールの中心に出す答え。ホイールが止まる（= Model が精算する）まで出目を見せない。
    private func hubOverlay(diameter: CGFloat) -> some View {
        ZStack {
            switch model.phase {
            case .betting:
                EmptyView()
            case .spinning:
                Text(tr("回転中…"))
                    .font(.system(size: max(12, diameter * 0.055), weight: .bold, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surface.opacity(0.92)))
            case .result:
                if let number = model.winningNumber, let settlement = model.lastSettlement {
                    VStack(spacing: 2) {
                        numberBadge(number, size: diameter * 0.17)
                        Text(netLabel(settlement.net))
                            .font(.system(size: max(12, diameter * 0.065), weight: .black, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                            .foregroundStyle(netColor(settlement.net))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(10)
                    .background(Circle().fill(Theme.surface).shadow(color: Theme.cardShadow, radius: 6, y: 3))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
        .frame(maxWidth: diameter * 0.5)
        // 修飾子は 1 つのビューに 1 つだけ置く（入れ子にすると打ち消し合う・#199）。
        .gameAnimation(RouletteMotion.resultBadge, value: model.phase)
    }

    /// チップの残り・今の賭けの札。どちらの画面でも常に見せる。
    private var chipsPill: some View {
        statPill(tr("チップ: %@枚", model.chips.formatted()), systemImage: "circle.hexagongrid.fill",
                 color: Theme.ink)
    }

    private var betPill: some View {
        statPill(tr("ベット: %@枚", model.totalBet.formatted()), systemImage: "dollarsign.circle.fill",
                 color: model.totalBet > 0 ? Theme.yellowText : Theme.inkSub)
    }

    private func statPill(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .scaledFont(13, weight: .bold, design: .rounded)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.inkSub.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Betting screen (A)

    /// 賭けの画面のホイールのカード。札は上の角に重ね、下の 1 行に出目の履歴と案内を出す。
    private var bettingWheelCard: some View {
        VStack(spacing: RouletteMetrics.wheelCardFooterSpacing) {
            flexibleWheel
                .overlay(alignment: .topLeading) { chipsPill }
                .overlay(alignment: .topTrailing) { betPill }
            HStack(spacing: 8) {
                historyStrip
                Spacer(minLength: 0)
                Text(model.bets.isEmpty ? tr("賭ける場所をタップ") : tr("「スピン」で回します"))
                    .themeBody(12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.inkSub)
            }
            .frame(height: RouletteMetrics.wheelCardFooterHeight)
        }
        .padding(RouletteMetrics.wheelCardPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 賭けの表。「数字」「赤黒・区分」のタブで切り替える。2 つのタブで高さは同じ。
    private func tableCard(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: RouletteMetrics.tableTabSpacing) {
            betTabs
            Group {
                switch betTab {
                case .numbers: numberGrid(sizing)
                case .outside: outsideGrid(sizing)
                }
            }
            .frame(height: layout.scaled(sizing.tableContentHeight))
        }
        .padding(RouletteMetrics.boardPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// タブの見出し。もう片方のタブに置いた額も見出しのバッジで分かるようにする。
    private var betTabs: some View {
        let inset = RouletteMetrics.tabTrackInset
        return HStack(spacing: 4) {
            ForEach(RouletteBetTab.allCases, id: \.self) { tab in
                let selected = betTab == tab
                let staked = model.bets.filter { tab.contains($0.kind) }.reduce(0) { $0 + $1.amount }
                Button {
                    betTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Text(tabTitle(tab))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if staked > 0 {
                            chipBadge(staked)
                        }
                    }
                    .foregroundStyle(selected ? Theme.onAccent : Theme.inkSub)
                    // タップ領域は 44pt 以上（外枠の余白はこの外側に足す）。
                    .frame(maxWidth: .infinity, minHeight: RouletteMetrics.tabButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall - inset, style: .continuous)
                            .fill(selected ? Theme.Fill.yellow : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pop)
                .accessibilityLabel(tabTitle(tab))
                .accessibilityValue(staked > 0 ? tr("%lld枚", staked) : tr("なし"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(inset)
        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.background))
    }

    private func tabTitle(_ tab: RouletteBetTab) -> String {
        switch tab {
        case .numbers: return tr("数字（0〜36）")
        case .outside: return tr("赤黒・奇偶・区分")
        }
    }

    /// 「数字」タブ。0 の右に 1〜36 を 4 段 × 9 列で並べる。
    private func numberGrid(_ sizing: RouletteMetrics.Sizing) -> some View {
        let spacing = RouletteMetrics.cellSpacing
        return HStack(spacing: spacing) {
            betCell(.straight(0), height: sizing.tableContentHeight)
                .frame(width: layout.scaled(sizing.numberCellHeight))
            VStack(spacing: spacing) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(1...9, id: \.self) { column in
                            betCell(.straight(row * 9 + column), height: sizing.numberCellHeight)
                        }
                    }
                }
            }
        }
    }

    /// 「赤黒・区分」タブ。12 個ずつの区分 3 つと、赤黒など 6 つの 2 段。数字の表と同じ高さを分け合うので、
    /// マスは 44pt を超える。
    private func outsideGrid(_ sizing: RouletteMetrics.Sizing) -> some View {
        let spacing = RouletteMetrics.cellSpacing
        return VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(RouletteBetKind.dozens, id: \.self) { kind in
                    betCell(kind, height: sizing.outsideCellHeight)
                }
            }
            HStack(spacing: spacing) {
                ForEach(RouletteBetKind.evenMoney, id: \.self) { kind in
                    betCell(kind, height: sizing.outsideCellHeight)
                }
            }
        }
    }

    /// 賭けのマス 1 つ。タップで `selectedChip` を 1 口置く。置いた額は右上のバッジに出す。
    private func betCell(_ kind: RouletteBetKind, height: CGFloat) -> some View {
        let staked = model.amount(on: kind)
        return Button {
            model.placeBet(kind)
        } label: {
            Text(kind.label)
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(cellTextColor(kind))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: layout.scaled(height))
                .background(cellFill(kind), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if staked > 0 {
                        chipBadge(staked).offset(x: 3, y: -5)
                    }
                }
        }
        // `.plain` は押下フィードバックも消えるので、押している間だけ沈む `.pop` を使う（#195）。
        .buttonStyle(.pop)
        .disabled(!model.canBet)
        .accessibilityLabel(tr("%@に賭ける", kind.label))
        .accessibilityValue(staked > 0 ? tr("%lld枚", staked) : tr("なし"))
    }

    // MARK: - Wheel screen (B)

    /// ホイールが主役の画面（回転中・結果・チップ切れ）。上に札、真ん中にホイール、下に置いた口。
    private var wheelScreen: some View {
        VStack(spacing: 8) {
            HStack {
                chipsPill
                Spacer(minLength: 8)
                betPill
            }
            .frame(height: RouletteMetrics.wheelScreenStatsHeight)
            flexibleWheel
            // チップ切れのときは操作欄が高い（見出し・記録・復活・やり直し）。置いた口は畳んで
            // ホイールの大きさを保つ（出目と収支はホイールの中心に残る）。
            if !model.sessionOver {
                betSummaryCard
            }
        }
    }

    /// 置いた口の一覧。回転中は「あなたの賭け」、結果では当たった口に戻りを出し、外れた口は薄くする。
    private var betSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.phase == .result ? tr("結果") : tr("あなたの賭け"))
                    .scaledFont(13, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Spacer(minLength: 0)
                if model.phase == .result, let settlement = model.lastSettlement {
                    Text(netLabel(settlement.net))
                        .scaledFont(18, weight: .black, design: .rounded)
                        .foregroundStyle(netColor(settlement.net))
                } else {
                    Text(tr("回転中…"))
                        .themeBody(13)
                        .foregroundStyle(Theme.inkSub)
                }
            }
            placedBetsRow
                .frame(height: 26)
            historyStrip
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: RouletteMetrics.betSummaryHeight, alignment: .topLeading)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 置いた口を 1 行に並べる。入りきらなければ後ろを「ほか n 口」にまとめる（横にはみ出さない）。
    private var placedBetsRow: some View {
        let kinds = placedKinds
        return ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: kinds.count, through: 1, by: -1)), id: \.self) { shown in
                HStack(spacing: 8) {
                    ForEach(kinds.prefix(shown), id: \.self) { kind in
                        placedBet(kind)
                    }
                    if shown < kinds.count {
                        Text(tr("ほか%lld口", kinds.count - shown))
                            .scaledFont(12, weight: .bold, design: .rounded)
                            .foregroundStyle(Theme.inkSub)
                            .lineLimit(1)
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 置いた口の種類（置いた順・重複なし）。同じ場所に何口置いても 1 つにまとめて額を足す。
    private var placedKinds: [RouletteBetKind] {
        var seen = Set<RouletteBetKind>()
        return model.bets.map(\.kind).filter { seen.insert($0).inserted }
    }

    private func placedBet(_ kind: RouletteBetKind) -> some View {
        let amount = model.amount(on: kind)
        let settled = model.phase == .result
        let hit = settled && model.winningNumber.map(kind.covers) == true
        return HStack(spacing: 4) {
            Text(kind.label)
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(cellTextColor(kind))
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(cellFill(kind)))
            Text(hit ? tr("+%lld枚", amount * kind.payout) : tr("%lld枚", amount))
                .scaledFont(12, weight: .black, design: .rounded)
                .foregroundStyle(hit ? Theme.tealText : Theme.ink)
                .lineLimit(1)
        }
        .opacity(settled && !hit ? 0.4 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared parts

    /// 収支の文言。`Text` 補間の桁区切り（#484）を避けて文字列を先に組む。
    private func netLabel(_ net: Int) -> String {
        if net > 0 { return tr("+%lld枚", net) }
        if net == 0 { return tr("±0枚") }
        return tr("%lld枚", net)
    }

    private func netColor(_ net: Int) -> Color {
        net > 0 ? Theme.tealText : (net < 0 ? Theme.coralText : Theme.inkSub)
    }

    /// 直近の出目（新しい順）。
    @ViewBuilder
    private var historyStrip: some View {
        if !model.history.isEmpty {
            HStack(spacing: 4) {
                Text(tr("出目"))
                    .scaledFont(11, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                    .fixedSize()
                ForEach(Array(model.history.prefix(6).enumerated()), id: \.offset) { _, number in
                    numberBadge(number, size: 20)
                }
            }
        }
    }

    private func numberBadge(_ number: Int, size: CGFloat) -> some View {
        Text(verbatim: "\(number)")
            .font(.system(size: size * 0.5, weight: .black, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
            .foregroundStyle(RouletteWheelView.textColor(for: number))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(Circle().fill(RouletteWheelView.fill(for: number)))
            .accessibilityLabel(tr("%1$lld・%2$@", number, colorName(of: number)))
    }

    private func colorName(of number: Int) -> String {
        switch RouletteWheel.color(of: number) {
        case .red:   return tr("赤")
        case .black: return tr("黒")
        case .green: return tr("緑")
        }
    }

    /// マスに置いた額。白地に固定の濃い文字で、どの面色の上でも読める。
    private func chipBadge(_ amount: Int) -> some View {
        Text(verbatim: "\(amount)")
            .scaledFont(9, weight: .black, design: .rounded)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().strokeBorder(Theme.onAccent, lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func cellFill(_ kind: RouletteBetKind) -> Color {
        switch kind {
        case .straight(let number): return RouletteWheelView.fill(for: number)
        case .red:                  return Theme.Fill.coral
        case .black:                return Theme.fillStrong
        case .dozen:                return Theme.Fill.purple
        case .odd, .even, .low, .high: return Theme.Fill.yellow
        }
    }

    private func cellTextColor(_ kind: RouletteBetKind) -> Color {
        switch kind {
        case .straight(let number): return RouletteWheelView.textColor(for: number)
        case .black:                return .white
        default:                    return Theme.onAccent
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private func actionArea(_ sizing: RouletteMetrics.Sizing) -> some View {
        switch model.phase {
        case .betting:  bettingView(sizing)
        case .spinning: spinningView(sizing)
        case .result:   resultView(sizing)
        }
    }

    /// 賭け中の操作欄。1 段目にチップ額 4 つ + 戻す、2 段目にスピンを全幅（#2364）。
    private func bettingView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: RouletteMetrics.actionRowSpacing) {
            HStack(spacing: 8) {
                Text(tr("チップ"))
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                    .fixedSize()
                ForEach(RouletteModel.chipOptions, id: \.self) { amount in
                    chipButton(amount)
                }
                actionButton(tr("戻す"), color: Theme.fillMuted, foreground: .white, disabled: model.bets.isEmpty) {
                    model.undoLastBet()
                }
            }
            actionButton(tr("スピン"), color: Theme.Fill.coral, disabled: !model.canSpin) {
                model.spin()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 置くチップの額を選ぶ丸ボタン。残高で買えない額は押せなくする。
    private func chipButton(_ amount: Int) -> some View {
        let selected = model.selectedChip == amount
        let affordable = model.availableChips >= amount
        return Button {
            model.selectedChip = amount
        } label: {
            Text(verbatim: "\(amount)")
                .scaledFont(13, weight: .black, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: RouletteMetrics.chipButtonSize, height: RouletteMetrics.chipButtonSize)
                .background(Circle().fill(selected ? Theme.Fill.yellow : Theme.surface))
                .overlay(
                    Circle().strokeBorder(selected ? Theme.yellow : Theme.inkSub.opacity(0.5),
                                          style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                )
                .foregroundStyle(affordable ? (selected ? Theme.onAccent : Theme.ink) : Theme.inkSub)
        }
        .buttonStyle(.pop)
        .disabled(!affordable)
        .accessibilityLabel(tr("%lld枚のチップ", amount))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// ホイールが回っているあいだの操作欄。待ちを飛ばして結果まで進められる。
    private func spinningView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: 8) {
            actionButton(tr("結果まで進める"), color: Theme.fillMuted, foreground: .white) {
                skipSpin()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 結果の操作欄。どちらを押しても賭けの画面へ戻る（同じ口を置き直すか、空の表から賭けるか）。
    private func resultView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: 8) {
            RecordLabel(model.recordResult)
            HStack(spacing: 12) {
                actionButton(tr("同じ賭けでもう一度"), color: Theme.Fill.yellow) {
                    model.repeatLastBets()
                }
                actionButton(tr("次のゲーム"), color: Theme.Fill.coral) {
                    model.nextRound()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Session Over

    /// チップ切れの見出し下の説明。復活を使い切ったら選べる手を書き換える。
    /// 数値は `Text` 補間の桁区切り（#484）を避けて文字列を先に組む。
    private var sessionOverSubtitle: String {
        model.canReviveAfterBust
            ? tr("広告を見て%lld枚で復活するか、最初からやり直せます", RouletteModel.reviveChips)
            : tr("復活はこのセッションで使いました。最初からやり直せます")
    }

    private var reviveButtonTitle: String {
        tr("広告を見て%lld枚で復活（1セッションに1回）", RouletteModel.reviveChips)
    }

    private var restartButtonTitle: String {
        tr("最初からやり直す (%lld枚)", RouletteModel.initialChips)
    }

    private func sessionOverView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .scaledFont(24)
                    .foregroundStyle(Theme.coralText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("チップが足りなくなりました"))
                        .scaledFont(16, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.coralText)
                    Text(sessionOverSubtitle)
                        .scaledFont(12, weight: .medium, design: .rounded)
                        .foregroundStyle(Theme.inkSub)
                }
                Spacer()
            }

            // チップが尽きた回は resultView ではなくこちらが出るため、記録行もここに置く。
            RecordLabel(model.recordResult)

            // チップ切れ復活。ブラックジャック（#499）と同じ形
            // （リザルト内のボタン・視聴完了時のみ効果・失敗は共通アラート）。使い切ったセッションではボタンごと消す。
            if model.canReviveAfterBust {
                Button {
                    // 連打ガードと失敗アラートは共通側が持つ（#526）。広告と回復は
                    // `reviveAfterAd()` が 1 本で受け持つのでモデル側の形のまま（#727）。
                    reviveRescue.requestHandledByModel(withOutcome: { await model.reviveAfterAd() })
                } label: {
                    Label(reviveButtonTitle, systemImage: "play.rectangle.fill")
                        .themeBody(16).frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.yellow)
                .disabled(reviveRescue.isWatching)
            }

            Button { model.restartSession() } label: {
                Text(restartButtonTitle).themeBody(16).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            // 広告のロード〜視聴中にやり直すと、見終えた復活が新しいセッションへ乗りかける（#727）。
            .disabled(reviveRescue.isWatching)
        }
        .padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // 高さは Apple HIG の 44pt を下限にする（#709 と同じ）。
                .frame(maxWidth: .infinity, minHeight: RouletteMetrics.actionButtonMinHeight)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(disabled ? Theme.inkSub : foreground)
        }
        .buttonStyle(.pop)
        .disabled(disabled)
    }
}

// MARK: - Rule Sheet

/// 「くわしいルール」（配当の一覧）。対局画面の `?` から 1 タップで開ける。
struct RouletteRuleSheet: View {
    var body: some View {
        RuleListSheet(rules: [
            (tr("数字 1 点（0〜36）"), tr("配当 35 倍。当たると元金に加えて 35 倍が戻ります（10 枚なら 360 枚）。")),
            (tr("1〜12・13〜24・25〜36"), tr("配当 2 倍。12 個の数字のどれかが出れば当たり（10 枚なら 30 枚）。")),
            (tr("赤・黒・奇数・偶数・1〜18・19〜36"), tr("配当 1 倍。当たると元金と同額が戻ります（10 枚なら 20 枚）。")),
            (tr("0（緑）"), tr("赤黒・奇数偶数・1〜18・19〜36・12 個の区分はすべて外れ。数字 1 点の 0 だけが当たりです。")),
            (tr("複数の場所に賭ける"), tr("1 回のスピンで何か所にも置けます。「戻す」で最後に置いた 1 口を外せます。")),
            (tr("チップが足りなくなったら"), tr("広告を見ると 1 セッションに 1 回だけ %1$lld 枚で復活できます。最初からやり直すと %2$lld 枚に戻ります。チップはゲーム内だけのもので、現金とは交換できません。", RouletteModel.reviveChips, RouletteModel.initialChips)),
        ])
    }
}
