import SwiftUI
import Core

public struct SevensView: View {
    @State private var model: SevensModel
    private let services: GameServices

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: SevensModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            cpuRow
            if model.phase == .result {
                resultCard
                    .transition(.opacity)
            } else {
                boardArea
                    .transition(.opacity)
                handArea
                    .transition(.opacity)
            }
            HowToPlayHint(.sevens, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .gameChrome(title: "七並べ", review: services.review)
        .howToPlay(.sevens) { SevensRuleSheet() }
        .task {
            // 中断から戻ったときは init が `.playing` まで復元しているので配り直さない。
            if model.phase == .idle { model.startGame() }
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            Label("\(max(model.gameNumber, 1))ゲーム目", systemImage: "number")
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
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
            ForEach(1..<SevensModel.playerCount, id: \.self) { index in
                cpuCard(index)
            }
        }
    }

    private func cpuCard(_ index: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.currentPlayer == index && model.phase == .playing ? Theme.coral : Theme.inkSub)
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
    }

    // MARK: - 場

    private var boardArea: some View {
        VStack(spacing: 4) {
            ForEach(SevensSuit.allCases, id: \.self) { suit in
                boardRow(suit)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeInOut(duration: 0.15), value: model.board)
    }

    private func boardRow(_ suit: SevensSuit) -> some View {
        let range = model.board[suit.rawValue]
        return HStack(spacing: 2) {
            Text(suit.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PlayingCardInk.color(for: suit.playing))
                .frame(width: 16)
            ForEach(1...13, id: \.self) { rank in
                boardCell(suit: suit, rank: rank, isPlaced: range.placedRanks.contains(rank))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SevensAccessibility.suitRowLabel(suit, range: range))
    }

    private func boardCell(suit: SevensSuit, rank: Int, isPlaced: Bool) -> some View {
        let ink = PlayingCardInk.color(for: suit.playing)
        return ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isPlaced ? ink.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(isPlaced ? ink.opacity(0.55) : Theme.inkSub.opacity(0.25), lineWidth: 1)
                )
            if isPlaced {
                Text(Self.rankLabel(rank))
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }

    private static func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    // MARK: - 手札

    private var handArea: some View {
        VStack(spacing: 6) {
            HStack {
                Text("あなた（残り\(model.playerHand.count)枚）")
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !model.lastActions[SevensModel.humanIndex].isEmpty {
                    Text(model.lastActions[SevensModel.humanIndex])
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.teal)
                }
            }
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: SevensHandLayout.columnSpacing),
                    count: SevensHandLayout.columns
                ),
                spacing: SevensHandLayout.rowSpacing
            ) {
                ForEach(model.playerHand) { card in
                    let playable = model.canPlay(card)
                    SevensCardView(card: card, playable: playable)
                        // 見えるカードは 42pt のまま、タップ判定だけを列いっぱいに広げて
                        // 44pt 以上にする（大富豪 #195 と同じ考え方）。
                        .frame(maxWidth: .infinity, minHeight: SevensHandLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                        .onTapGesture { play(card) }
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SevensAccessibility.handCardLabel(card, canPlay: playable))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { play(card) }
                        .disabled(!model.isPlayerTurn)
                }
            }
            .gameAnimation(.easeInOut(duration: 0.18), value: model.playerHand)
            if model.mustPass {
                hintLine("出せる札がありません。パスしてください")
            }
        }
        .padding(.horizontal, SevensHandLayout.horizontalPadding).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 人間がカードを出す。パス・次のゲーム開始と同様、出した直後に CPU の手番を進める
    /// （出さないと次に人間の手番が回ってくるまで盤面が止まったままになる）。
    private func play(_ card: SevensCard) {
        model.play(card)
        Task { await model.runCPUTurnsIfNeeded() }
    }

    private func hintLine(_ message: String) -> some View {
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

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .playing:
            actionButton("パス", color: Theme.fillMuted, foreground: .white, disabled: !model.mustPass) {
                model.pass()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            actionButton("次のゲーム", color: Theme.Fill.coral) {
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    // MARK: - リザルト

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.didPlayerWin ? "crown.fill" : "flag.checkered")
                    .font(.system(size: 20))
                    .foregroundStyle(model.didPlayerWin ? Theme.yellow : Theme.inkSub)
                Text(model.didPlayerWin ? "あなたの勝ち！" : "\(model.playerName(model.winner ?? 0))の勝ち")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(model.didPlayerWin ? Theme.teal : Theme.ink)
                Spacer()
            }
            Spacer(minLength: 8)
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

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

enum SevensHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 12
    static let minimumTapTarget: CGFloat = 44
}

// MARK: - Card View

struct SevensCardView: View {
    let card: SevensCard
    var playable: Bool = true

    private var borderColor: Color {
        playable ? Theme.teal : Color.gray.opacity(0.2)
    }

    private var borderWidth: CGFloat { playable ? 1.5 : 0.5 }

    var body: some View {
        ZStack {
            PlayingCardSurface(
                cornerRadius: PlayingCardMetrics.compact.cornerRadius,
                border: borderColor,
                borderWidth: borderWidth
            )
            PlayingCardFace(figure: card.figure, metrics: .compact)
        }
        .frame(width: PlayingCardMetrics.compact.width, height: PlayingCardMetrics.compact.height)
        .opacity(playable ? 1 : 0.4)
    }
}

// MARK: - Rule Sheet

struct SevensRuleSheet: View {
    private let rules: [(String, String)] = [
        ("ゲームの流れ", "CPU3人と対戦します。トランプ52枚を13枚ずつ配り、手札を早く出し切った人の勝ちです"),
        ("出し方", "4つのスート（♠♥♦♣）ごとに、7から始めて隣り合う数字だけ出せます。まだ7が出ていないスートは7しか出せません"),
        ("パス", "出せる札が無いときだけパスできます。出せる札があるのに出さないことはできません"),
        ("勝敗", "手札を最初になくした人の勝ちです"),
    ]

    var body: some View {
        RuleListSheet(title: "ルール", rules: rules)
    }
}
