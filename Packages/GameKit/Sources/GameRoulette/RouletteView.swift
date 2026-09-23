import SwiftUI
import Core

public struct RouletteView: View {
    @State private var model: RouletteModel
    private let services: GameServices
    /// 画面の広さ（#458）。ホイールとマスの高さを同じ倍率で拡大する。
    @Environment(\.adaptiveLayout) private var layout
    /// Reduce Motion。ON ならホイールは回らず止まる位置へ飛ぶので、結果も待たせずに出す。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// チップ切れ復活のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var reviveRescue = RewardedRescue()
    /// ホイールの累積回転角（度）。止まった位置を保ったまま、スピンごとに数周ぶん増える
    /// （巻き戻すと逆回転になるので減らさない）。
    @State private var wheelRotation: Double = 0

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

    public var body: some View {
        // 縦の狭さ（iPhone SE）はこの画面で測る。`AdaptiveLayout` は幅しか持たない（#458）。
        GeometryReader { geometry in
            let sizing = RouletteMetrics.sizing(forHeight: geometry.size.height)
            VStack(spacing: sizing.stackSpacing) {
                tableCard(sizing)
                // チップが尽きたら盤面は畳む（置けないし精算も済んでいる。出目と収支は上のカードに残る）。
                // 復活・やり直しの操作欄は賭け中の操作欄より高く、盤面と同居させると SE で下が切れる。
                if !model.sessionOver {
                    boardCard(sizing)
                }
                HowToPlayHint(.roulette, playLog: services.playLog)
                if model.sessionOver {
                    sessionOverView(sizing)
                } else {
                    actionArea(sizing)
                }
                // 操作欄の高さは局面で変わる（賭け中は 2 段・回転中は 1 段）。余りはここで吸って
                // 盤面を上に固定し、バナーは下に留める（中央寄せだと局面ごとに盤面が上下に動く）。
                Spacer(minLength: 0)
                RecommendationSlot(services: services, isFinished: model.phase == .result || model.sessionOver)
                BannerSlot(ads: services.ads)
            }
            .padding(Theme.pad)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .rewardOffer(reviveRescue, for: .revival, isPresented: model.canReviveAfterBust,
                     services: services, gameID: model.gameID)
        .gameChrome(title: "ルーレット", review: services.review)
        .howToPlay(.roulette) { RouletteRuleSheet() }
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
            notEarned: "チップは回復しませんでした",
            unavailable: RewardUnavailableAlert(
                title: "チップは回復しませんでした",
                message: "広告を見ているあいだにセッションが変わったため、復活は適用していません。復活の回数は減っていません。"
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

    // MARK: - Table (wheel + chips + result)

    private func tableCard(_ sizing: RouletteMetrics.Sizing) -> some View {
        HStack(alignment: .center, spacing: 14) {
            RouletteWheelView(
                rotation: wheelRotation,
                highlighted: model.phase == .result ? model.winningNumber : nil
            )
            .frame(width: layout.scaled(sizing.wheelDiameter),
                   height: layout.scaled(sizing.wheelDiameter))

            VStack(alignment: .leading, spacing: 8) {
                Label("チップ: \(model.chips)枚", systemImage: "circle.hexagongrid.fill")
                    .themeBody(14)
                    .foregroundStyle(Theme.ink)
                Label("ベット: \(model.totalBet)枚", systemImage: "dollarsign.circle.fill")
                    .themeBody(14)
                    .foregroundStyle(model.totalBet > 0 ? Theme.yellow : Theme.inkSub)
                resultLine
                historyStrip
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 出目と収支。ホイールが止まる（= Model が精算する）まで答えを見せない。
    private var resultLine: some View {
        ZStack(alignment: .leading) {
            switch model.phase {
            case .betting:
                Text(model.bets.isEmpty ? "賭ける場所をタップ" : "「スピン」で回します")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
            case .spinning:
                Text("回転中…")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
            case .result:
                if let number = model.winningNumber, let settlement = model.lastSettlement {
                    HStack(spacing: 8) {
                        numberBadge(number, size: 30)
                        Text(netLabel(settlement.net))
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(settlement.net > 0 ? Theme.teal
                                             : (settlement.net < 0 ? Theme.coral : Theme.inkSub))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
        .frame(minHeight: 30)
        // 修飾子は 1 つのビューに 1 つだけ置く（入れ子にすると打ち消し合う・#199）。
        .gameAnimation(RouletteMotion.resultBadge, value: model.phase)
    }

    /// 収支の文言。`Text` 補間の桁区切り（#484）を避けて文字列を先に組む。
    private func netLabel(_ net: Int) -> String {
        if net > 0 { return "+\(net)枚" }
        if net == 0 { return "±0枚" }
        return "\(net)枚"
    }

    /// 直近の出目（新しい順）。
    @ViewBuilder
    private var historyStrip: some View {
        if !model.history.isEmpty {
            HStack(spacing: 4) {
                Text("出目")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                ForEach(Array(model.history.prefix(6).enumerated()), id: \.offset) { _, number in
                    numberBadge(number, size: 20)
                }
            }
        }
    }

    private func numberBadge(_ number: Int, size: CGFloat) -> some View {
        Text(verbatim: "\(number)")
            .font(.system(size: size * 0.5, weight: .black, design: .rounded))
            .foregroundStyle(RouletteWheelView.textColor(for: number))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(Circle().fill(RouletteWheelView.fill(for: number)))
            .accessibilityLabel("\(number)・\(colorName(of: number))")
    }

    private func colorName(of number: Int) -> String {
        switch RouletteWheel.color(of: number) {
        case .red:   return "赤"
        case .black: return "黒"
        case .green: return "緑"
        }
    }

    // MARK: - Board

    /// 盤面。0 の左に 1〜36 を 4 段 × 9 列で並べ、下に 12 個ずつの区分と赤黒などを置く。
    private func boardCard(_ sizing: RouletteMetrics.Sizing) -> some View {
        let spacing = RouletteMetrics.cellSpacing
        return VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                betCell(.straight(0), height: sizing.numberCellHeight * 4 + spacing * 3)
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
        .padding(RouletteMetrics.boardPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 賭けのマス 1 つ。タップで `selectedChip` を 1 口置く。置いた額は右上のバッジに出す。
    private func betCell(_ kind: RouletteBetKind, height: CGFloat) -> some View {
        let staked = model.amount(on: kind)
        let isWinner = model.phase == .result && model.winningNumber.map(kind.covers) == true
        return Button {
            model.placeBet(kind)
        } label: {
            Text(kind.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(cellTextColor(kind))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: layout.scaled(height))
                .background(cellFill(kind), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isWinner ? Theme.yellow : Color.clear, lineWidth: 2.5)
                )
                .overlay(alignment: .topTrailing) {
                    if staked > 0 {
                        chipBadge(staked).offset(x: 3, y: -5)
                    }
                }
        }
        // `.plain` は押下フィードバックも消えるので、押している間だけ沈む `.pop` を使う（#195）。
        .buttonStyle(.pop)
        .disabled(!model.canBet)
        .accessibilityLabel("\(kind.label)に賭ける")
        .accessibilityValue(staked > 0 ? "\(staked)枚" : "なし")
    }

    /// マスに置いた額。白地に固定の濃い文字で、どの面色の上でも読める。
    private func chipBadge(_ amount: Int) -> some View {
        Text(verbatim: "\(amount)")
            .font(.system(size: 9, weight: .black, design: .rounded))
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

    private func bettingView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("チップ")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                ForEach(RouletteModel.chipOptions, id: \.self) { amount in
                    chipButton(amount)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                actionButton("戻す", color: Theme.fillMuted, foreground: .white, disabled: model.bets.isEmpty) {
                    model.undoLastBet()
                }
                actionButton("スピン", color: Theme.Fill.coral, disabled: !model.canSpin) {
                    model.spin()
                }
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
                .font(.system(size: 13, weight: .black, design: .rounded))
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
        .accessibilityLabel("\(amount)枚のチップ")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// ホイールが回っているあいだの操作欄。待ちを飛ばして結果まで進められる。
    private func spinningView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: 8) {
            actionButton("結果まで進める", color: Theme.fillMuted, foreground: .white) {
                skipSpin()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, sizing.cardVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    private func resultView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: 8) {
            RecordLabel(model.recordResult)
            HStack(spacing: 12) {
                actionButton("同じ賭けでもう一度", color: Theme.Fill.yellow) {
                    model.repeatLastBets()
                }
                actionButton("次のゲーム", color: Theme.Fill.coral) {
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
            ? "広告を見て\(RouletteModel.reviveChips)枚で復活するか、最初からやり直せます"
            : "復活はこのセッションで使いました。最初からやり直せます"
    }

    private var reviveButtonTitle: String {
        "広告を見て\(RouletteModel.reviveChips)枚で復活（1セッションに1回）"
    }

    private var restartButtonTitle: String {
        "最初からやり直す (\(RouletteModel.initialChips)枚)"
    }

    private func sessionOverView(_ sizing: RouletteMetrics.Sizing) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("チップが足りなくなりました")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.coral)
                    Text(sessionOverSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
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
        RuleListSheet(title: "ルーレットの配当", rules: [
            ("数字 1 点（0〜36）", "配当 35 倍。当たると元金に加えて 35 倍が戻ります（10 枚なら 360 枚）。"),
            ("1〜12・13〜24・25〜36", "配当 2 倍。12 個の数字のどれかが出れば当たり（10 枚なら 30 枚）。"),
            ("赤・黒・奇数・偶数・1〜18・19〜36", "配当 1 倍。当たると元金と同額が戻ります（10 枚なら 20 枚）。"),
            ("0（緑）", "赤黒・奇数偶数・1〜18・19〜36・12 個の区分はすべて外れ。数字 1 点の 0 だけが当たりです。"),
            ("複数の場所に賭ける", "1 回のスピンで何か所にも置けます。「戻す」で最後に置いた 1 口を外せます。"),
            ("チップが足りなくなったら", "広告を見ると 1 セッションに 1 回だけ \(RouletteModel.reviveChips) 枚で復活できます。最初からやり直すと \(RouletteModel.initialChips) 枚に戻ります。チップはゲーム内だけのもので、現金とは交換できません。"),
        ])
    }
}
