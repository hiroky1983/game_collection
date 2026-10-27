import SwiftUI
import Core

/// 15 パズルのプレイ画面。タイルをタップして空白へスライドする。
public struct FifteenView: View {
    private let services: GameServices
    @State private var model: FifteenModel
    @State private var showConfirmReset = false
    /// 最後に選んだ盤の大きさ（次に開いたときの初期値・#2869）。
    @AppStorage("fifteenSize") private var preferredSize = FifteenLogic.defaultSize
    /// 大きさの切り替えで、確認のあとに始める大きさ。
    @State private var pendingSize: Int?
    /// ヒントの広告救済（無料3回を使い切った後の1回・#1975）。
    @State private var hintRescue = RewardedRescue()

    public init(services: GameServices) {
        self.services = services
        let saved = UserDefaults.standard.object(forKey: "fifteenSize") as? Int
        _model = State(initialValue: FifteenModel(services: services, size: saved ?? FifteenLogic.defaultSize))
    }

    public var body: some View {
        VStack(spacing: 14) {
            header
            sizePicker
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
                    newGame: GameChromeNewGame(.solo, isDisabled: hintRescue.isWatching) { requestNewGame(size: nil) })
        .howToPlay(HowToPlayGuide.fifteen.illustrated(FifteenHowToFigures.items).onboarding(FifteenOnboarding.guide))
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
                Button(tr("終了して新規ゲーム"), role: .destructive) { startNewGame(size: pendingSize) }
                Button(tr("キャンセル"), role: .cancel) { pendingSize = nil }
            } message: {
                Text(tr("途中で終了すると、いまの盤面と手数が失われます。"))
            }
        }
    }

    /// 盤の大きさ。押すとその大きさで始め直す（途中なら確認を挟む）。記録は大きさごとに分かれる。
    private var sizePicker: some View {
        HStack(spacing: 6) {
            Text(tr("盤の大きさ"))
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
            ForEach(Array(FifteenLogic.sizes), id: \.self) { size in
                let isCurrent = size == model.size
                Button {
                    guard !isCurrent, !hintRescue.isWatching else { return }
                    requestNewGame(size: size)
                } label: {
                    Text(verbatim: "\(size)×\(size)")
                        .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundStyle(isCurrent ? Theme.onAccent : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                                .fill(isCurrent ? Theme.Fill.teal : Theme.fillMuted)
                        )
                }
                .buttonStyle(.pop)
                .accessibilityLabel(tr("盤の大きさ %@", "\(size)×\(size)"))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }

    /// 途中の盤面があるときだけ確認を挟む。`size` が nil なら同じ大きさで始め直す。
    private func requestNewGame(size: Int?) {
        if model.hasProgressToLose {
            pendingSize = size
            showConfirmReset = true
        } else {
            startNewGame(size: size)
        }
    }

    private func startNewGame(size: Int?) {
        if let size { preferredSize = size }
        pendingSize = nil
        withGameAnimation { model.newGame(size: size) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("手数"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                Text("\(model.moves)")
                    .scaledFont(30, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
            if let best = model.savedBestMoves {
                HeaderBestStat(title: tr("自己ベスト"), value: tr("%@手", RecordFormat.number(best)))
            }
        }
        // VoiceOver では「手数 n、自己ベスト n手」の 1 要素で読む（#2615）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.savedBestMoves.map {
            tr("手数 %1$lld、自己ベスト %2$@手", model.moves, RecordFormat.number($0))
        } ?? tr("手数") + " " + RecordFormat.number(model.moves))
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
            let n = model.size
            let side = (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                // タイルは値ごとに 1 枚で、位置だけをオフセットで動かす（スライドの動きが出る）。
                ForEach(1..<(n * n), id: \.self) { value in
                    if let index = model.tiles.firstIndex(of: value) {
                        FifteenTile(value: value, side: side, isHome: index == value - 1, isHint: index == model.hintIndex)
                            .offset(
                                x: spacing + CGFloat(index % n) * (side + spacing),
                                y: spacing + CGFloat(index / n) * (side + spacing)
                            )
                            .onTapGesture { model.tap(at: index) }
                            .accessibilityElement()
                            .accessibilityLabel(FifteenAccessibility.cellLabel(index: index, value: value, isHint: index == model.hintIndex, isHome: index == value - 1, size: n))
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
                // ヒントは 0 回でも省かず出す（#2613・#2801）。
                Text(tr("ヒント %lld回", model.hints.used))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                Button { withGameAnimation { model.newGame() } } label: {
                    Text(tr("もう一回")).foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .announcesResultAppearance([tr("クリア！"), tr("%lld手で揃えました", model.moves), tr("ヒント %lld回", model.hints.used)].joined(separator: tr("。")))
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
            .overlay(alignment: .topTrailing) {
                // 正位置は色だけでなくチェック印でも示す（色覚特性・#2322）。
                if isHome {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.18, weight: .black)) // fixed-size: タイルの寸法に比例させる印
                        .foregroundStyle(Theme.onAccent.opacity(0.8))
                        .padding(side * 0.08)
                        .accessibilityHidden(true)
                }
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
