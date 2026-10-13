import SwiftUI
import Core

/// 15 パズルのプレイ画面。タイルをタップして空白へスライドする。
public struct FifteenView: View {
    private let services: GameServices
    @State private var model: FifteenModel
    @State private var showConfirmReset = false
    /// ヒントの広告救済（無料3回を使い切った後の1回・#1975）。
    @State private var hintRescue = RewardedRescue()

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: FifteenModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 14) {
            header
            // 盤は残りの高さを Spacer と山分けしない（操作の段が増えた分だけ盤が縮むのを防ぐ）。
            boardView.layoutPriority(1)
            hintBar
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.fifteen, playLog: services.playLog)
            RecommendationArea(services: services, isFinished: model.isSolved)
            Spacer()
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("15パズル"), review: services.review,
                    newGame: GameChromeNewGame(.solo, isDisabled: hintRescue.isWatching) {
                        if model.hasProgressToLose {
                            showConfirmReset = true
                        } else {
                            withGameAnimation { model.newGame() }
                        }
                    })
        .howToPlay(HowToPlayGuide.fifteen.illustrated(FifteenHowToFigures.items))
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: tr("ヒントを使えませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("ヒントを出せませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったため、ヒントを出せませんでした。\nヒントの残り回数は減っていません。")
            )
        )
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmReset, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { withGameAnimation { model.newGame() } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの盤面と手数が失われます。"))
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("手数"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.moves)")
                    .scaledFont(30, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 盤の下の操作の段。ヒントだけ（無料3回、使い切ったら広告1本で+1回）。決着後は押せないだけで消さない（高さを変えない）。
    private var hintBar: some View {
        GameOverflowBar(
            actions: [
                GameActionItem(
                    id: "hint", title: tr("ヒント"), systemImage: "lightbulb.fill", role: .hint,
                    badge: .hint(totalRemaining: model.hintsRemaining, needsAd: model.needsAdForHint),
                    isEnabled: model.canUseHint && !hintRescue.isWatching,
                    accessibilityLabel: FifteenAccessibility.hintLabel(
                        remaining: model.hints.freeRemaining, needsAd: model.needsAdForHint),
                    accessibilityHint: tr("次に動かすタイルを光らせます")
                ) { requestHint() },
            ],
            verticalPadding: 4,
            nudge: HintNudge(
                isEligible: model.canUseHint && !hintRescue.isWatching,
                game: model.gameSerial,
                activity: [model.moves, model.hints.used]
            )
        )
    }

    /// 無料が残っていればそのまま示し、使い切っていれば広告を見たあとに示す（広告は押下起点・自動再生しない）。
    private func requestHint() {
        guard !hintRescue.isWatching, model.canUseHint else { return }
        guard model.needsAdForHint else {
            model.requestHint()
            return
        }
        // どの局に対する広告かを出す前に控え、ロード中に始めた新しい局へは乗せない（ナンプレのヒントと同じ）。
        let game = model.gameSerial
        hintRescue.request(
            services, gameID: model.gameID, purpose: .hint,
            guardedBy: .checkedByGrant
        ) {
            model.grantAdHint(forGame: game)
        }
    }

    private var boardView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let n = FifteenLogic.size
            let side = (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                // タイルは値ごとに 1 枚で、位置だけをオフセットで動かす（スライドの動きが出る）。
                ForEach(1..<FifteenLogic.cellCount, id: \.self) { value in
                    if let index = model.tiles.firstIndex(of: value) {
                        FifteenTile(value: value, side: side, isHome: index == value - 1, isHint: index == model.hintIndex)
                            .offset(
                                x: spacing + CGFloat(index % n) * (side + spacing),
                                y: spacing + CGFloat(index / n) * (side + spacing)
                            )
                            .onTapGesture { model.tap(at: index) }
                            .accessibilityElement()
                            .accessibilityLabel(FifteenAccessibility.cellLabel(index: index, value: value, isHint: index == model.hintIndex))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { withGameAnimation { model.tap(at: index) } }
                    }
                }
            }
            .gameAnimation(.easeInOut(duration: 0.12), value: model.tiles)
            .overlay {
                if model.isSolved { solvedOverlay }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var solvedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text(tr("クリア！")).font(.title2.bold()).foregroundStyle(.white)
                Text(tr("%lld手で揃えました", model.moves))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                Button(tr("もう一度")) { withGameAnimation { model.newGame() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Fill.coral)
            }
        }
    }
}

/// 1 タイル。正しい位置にあるタイルは色を変えて、揃っていく手応えを出す。
struct FifteenTile: View {
    let value: Int
    let side: CGFloat
    let isHome: Bool
    /// ヒントが「次に動かす」と示しているタイル（紫の枠。色は盤ゲームのヒントと共通）。
    var isHint = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(isHome ? Theme.Fill.teal : Theme.Fill.yellow)
            .frame(width: side, height: side)
            .overlay {
                Text(verbatim: "\(value)")
                    .font(.system(size: side * 0.42, weight: .heavy, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.onAccent)
            }
            .overlay {
                if isHint {
                    shape
                        .strokeBorder(BoardGameHintColor.color, lineWidth: 4)
                }
            }
            .contentShape(Rectangle())
    }
}
