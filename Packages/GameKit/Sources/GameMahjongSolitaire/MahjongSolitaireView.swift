import SwiftUI
import Core
import MahjongTiles

public struct MahjongSolitaireView: View {
    @State private var model: MahjongSolitaireModel
    private let services: GameServices
    @State private var zoomMode = false
    @State private var showConfirmNewGame = false
    @State private var showShuffleFailed = false
    @Environment(\.dismiss) private var dismiss

    /// 牌の縦横比（実物の牌に近い縦長）。
    private static let tileAspect: CGFloat = 1.40
    /// 1 段上がるごとに右上へずらす量（牌の幅に対する比）。積み上がりを見せるための奥行き。
    private static let layerShift: CGFloat = 0.14
    /// 拡大表示のときの牌の幅。
    private static let zoomedTileWidth: CGFloat = 40

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: MahjongSolitaireModel(services: services))
    }

    public var body: some View {
        // 縦の余白は 8。プレイ中と取り切った後で高さが変わらない `controlArea` を置くぶん、
        // 盤面に回せる高さを間隔から捻出している（#148）。
        VStack(spacing: 8) {
            statusBar
            board
                // 15 枚並ぶ盤面は横幅で大きさが決まるので、左右の余白ぶんまで使って牌を大きくする。
                .padding(.horizontal, -Theme.pad)
                .layoutPriority(1)
            HowToPlayHint(.mahjongSolitaire, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        .reviewRequestPrompt(services.review)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.coral)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("麻雀ソリティア")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.phase == .playing && model.remainingCount < MahjongSolitaireRules.layout.count {
                        showConfirmNewGame = true
                    } else {
                        model.newGame()
                    }
                } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
            }
        }
        .howToPlay(.mahjongSolitaire)
        .confirmationDialog("新規ゲームを始めますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { model.newGame() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると今の盤面が失われます。")
        }
        .alert("この盤面は並べ替えられません", isPresented: $showShuffleFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("残った牌が重なっていて取り切れません。「最初から」で新しい盤面を配ってください。")
        }
        .overlay {
            if model.isDeadlocked { deadlockOverlay }
        }
        .task {
            model.resumeTimerIfNeeded()
        }
    }

    // MARK: - ステータスバー

    private var statusBar: some View {
        HStack(spacing: 0) {
            Group {
                if model.phase == .won {
                    // 取り切った後の表示は行を増やさずここに同居させる（#148）。
                    // 残り枚数は 0 で固定になるため、入れ替えても失われる情報は無い。
                    Label("クリア！", systemImage: "flag.checkered")
                        .themeBody(15)
                        .foregroundStyle(Theme.teal)
                } else {
                    Label("\(model.remainingCount)", systemImage: "square.stack.3d.up.fill")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.coral)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 78, alignment: .leading)

            Spacer()

            Text(stateEmoji).font(.system(size: 28))

            Spacer()

            HStack(spacing: 8) {
                Label(timeText, systemImage: "clock")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.teal)

                Button { zoomMode.toggle() } label: {
                    Image(systemName: zoomMode ? "minus.magnifyingglass" : "plus.magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(zoomMode ? Theme.teal : Theme.surface)
                        )
                        .foregroundStyle(zoomMode ? .white : Theme.inkSub)
                }
            }
            .frame(minWidth: 78, alignment: .trailing)
        }
        // 縦の余白は 8。牌・数字の大きさは変えずに、ここからも盤面の高さを捻出している（#148）。
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var timeText: String {
        let s = min(model.elapsedSeconds, 59 * 60 + 59)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var stateEmoji: String {
        if model.phase == .won { return "🎉" }
        return model.isDeadlocked ? "😵" : "🀄️"
    }

    // MARK: - 盤面

    private var board: some View {
        Group {
            if model.phase == .won {
                // 取り切った直後は盤面が空になるので、代わりにクリアの演出を置く。
                VStack(spacing: 12) {
                    Text("🎉").font(.system(size: 64))
                    Text("全部取り切った！")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("ヒント\(model.hintCount)回 / 並べ替え\(model.shuffleCount)回")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if zoomMode {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    boardCanvas(tileWidth: Self.zoomedTileWidth)
                }
                .frame(maxWidth: .infinity)
            } else {
                GeometryReader { geo in
                    let width = geo.size.width / Self.canvasWidthInTiles
                    let height = geo.size.height / (Self.canvasHeightInTiles * Self.tileAspect)
                    boardCanvas(tileWidth: max(1, min(width, height)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// 牌の幅を 1 として、盤面全体が何枚分の広さになるか。
    private static var canvasWidthInTiles: CGFloat {
        CGFloat(MahjongSolitaireRules.halfWidth) / 2 + CGFloat(MahjongSolitaireRules.topLayer) * layerShift
    }
    private static var canvasHeightInTiles: CGFloat {
        CGFloat(MahjongSolitaireRules.halfHeight) / 2 + CGFloat(MahjongSolitaireRules.topLayer) * layerShift
    }

    private func boardCanvas(tileWidth: CGFloat) -> some View {
        let tileHeight = tileWidth * Self.tileAspect
        return ZStack(alignment: .topLeading) {
            // 下の段から順に描くことで、上に積まれた牌が手前に来る。
            ForEach(MahjongSolitaireRules.layout.indices, id: \.self) { index in
                if let face = model.faces[index] {
                    tileView(index: index, face: face, tileWidth: tileWidth, tileHeight: tileHeight)
                }
            }
        }
        // 牌は `offset` で置くのでレイアウト上の大きさは 1 枚分しかない。
        // 盤面全体の枠を与え、左上を基準に揃えないと中央寄せされてずれる。
        .frame(
            width: tileWidth * Self.canvasWidthInTiles,
            height: tileHeight * Self.canvasHeightInTiles,
            alignment: .topLeading
        )
    }

    private func tileView(index: Int, face: MahjongFace, tileWidth: CGFloat, tileHeight: CGFloat) -> some View {
        let position = MahjongSolitaireRules.layout[index]
        let depth = CGFloat(position.layer)
        let top = CGFloat(MahjongSolitaireRules.topLayer)
        let x = CGFloat(position.hx) / 2 * tileWidth + depth * Self.layerShift * tileWidth
        let y = CGFloat(position.hy) / 2 * tileHeight + (top - depth) * Self.layerShift * tileHeight
        return MahjongTileView(
            face: face,
            width: tileWidth,
            height: tileHeight,
            isBlocked: !model.isFreeByIndex[index],
            isSelected: model.selectedIndex == index,
            isHinted: model.hintPair.contains(index)
        )
        .offset(x: x, y: y)
        .onTapGesture { model.tap(index) }
        // 牌は図形と文字だけで描いているため、絵柄も取れるかどうかも音声では
        // 伝わらない。`onTapGesture` なのでボタン trait も自動では付かない（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MahjongSolitaireAccessibility.tileLabel(
            face: face,
            isBlocked: !model.isFreeByIndex[index],
            isSelected: model.selectedIndex == index,
            isHinted: model.hintPair.contains(index)
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tap(index) }
    }

    // MARK: - 操作

    private var gameControls: some View {
        HStack(spacing: 10) {
            Button { model.showHint() } label: {
                Label("ヒント", systemImage: "lightbulb.fill")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.teal))
            }
            Button {
                if !model.shuffleRemaining() { showShuffleFailed = true }
            } label: {
                Label("並べ替え", systemImage: "shuffle")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.purple))
            }
            Spacer()
            if model.hintCount > 0 || model.shuffleCount > 0 {
                Text("ヒント\(model.hintCount) / 並べ替え\(model.shuffleCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 盤の下の操作エリア

    /// プレイ中（ヒント・並べ替え）と取り切った後（記録 + 次のゲーム + レコメンド）で
    /// 中身が入れ替わるが、**高さは常に後者の最大構成に揃える**（#148）。
    ///
    /// ここが伸び縮みすると盤面（残りの高さいっぱいに牌を敷く）が帳尻合わせに縮む。
    /// レコメンドは出るとは限らず×でも閉じられるため、カードのぶんは常にひな形で高さを確保しておく。
    private var controlArea: some View {
        ZStack(alignment: .top) {
            finishedControls { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if model.phase == .won {
                finishedControls {
                    RecommendationSlot(services: services, isFinished: true)
                }
            } else {
                gameControls
            }
        }
    }

    /// 取り切った後に出すもの。高さの基準（ひな形）と実物で同じ組み方を使う。
    private func finishedControls<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            resultControls
            recommendation()
        }
    }

    /// 記録と「次のゲーム」は 1 段にまとめ、プレイ中の `gameControls` と同じ高さに収める（#148）。
    /// 3 段のままだと盤面の下が伸び、取り切った瞬間に盤面の領域が縮む。クリアの表示と所要時間は
    /// ステータスバーが出しているため、入れ替えても情報は失われない。
    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { model.newGame() } label: {
                Label("次のゲーム", systemImage: "arrow.clockwise")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 手詰まり

    private var deadlockOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("😵").font(.system(size: 52))
                Text("取れる牌がありません")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("残りを並べ替えると、そこから必ず取り切れる配置になります。")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .multilineTextAlignment(.center)

                Button {
                    if !model.shuffleRemaining() { showShuffleFailed = true }
                } label: {
                    Label("並べ替える", systemImage: "shuffle")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.purple, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { model.giveUpAndRestart() } label: {
                    Text("最初から")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 28)
        }
    }
}
