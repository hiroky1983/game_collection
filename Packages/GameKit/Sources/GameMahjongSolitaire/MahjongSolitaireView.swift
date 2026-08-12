import SwiftUI
import Core

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
        VStack(spacing: 10) {
            statusBar
            board
                // 15 枚並ぶ盤面は横幅で大きさが決まるので、左右の余白ぶんまで使って牌を大きくする。
                .padding(.horizontal, -Theme.pad)
                .layoutPriority(1)
            if model.phase == .won {
                resultControls
            } else {
                gameControls
            }
            RecommendationSlot(services: services, isFinished: model.phase == .won)
            Spacer(minLength: 8)
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
            Label("\(model.remainingCount)", systemImage: "square.stack.3d.up.fill")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.coral)
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
        .padding(.horizontal, 12).padding(.vertical, 10)
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
            if zoomMode {
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
        .font(Theme.body(14))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered").foregroundStyle(Theme.teal)
                Text("クリア！").font(Theme.body(15)).foregroundStyle(Theme.teal)
                Spacer()
                Label(timeText, systemImage: "clock.fill")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)

            Button { model.newGame() } label: {
                Text("次のゲーム").font(Theme.body(16)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
        }
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

// MARK: - 牌

/// 1 枚の牌。絵柄は画像アセットを持たず、文字と図形だけで描く。
struct MahjongTileView: View {
    let face: MahjongFace
    let width: CGFloat
    let height: CGFloat
    /// いま取れない牌（上に載っている・両隣が塞がっている）。暗く落として見分けられるようにする。
    let isBlocked: Bool
    let isSelected: Bool
    let isHinted: Bool

    private static let circleColor = Color(hex: 0x2E6FD8)
    private static let bambooColor = Color(hex: 0x2E9E5B)
    private static let kanjiNumerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
    private static let winds = ["東", "南", "西", "北"]
    private static let dragons = ["中", "發", "白"]
    private static let flowers = ["梅", "蘭", "菊", "竹"]
    private static let seasons = ["春", "夏", "秋", "冬"]

    var body: some View {
        let corner = width * 0.18
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(hex: 0xFFFCF2))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected || isHinted ? width * 0.1 : max(0.5, width * 0.03))
            content
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
        .frame(width: width, height: height)
        .overlay {
            if isBlocked {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(hex: 0x4A3B33, alpha: 0.22))
            }
        }
        .shadow(color: .black.opacity(0.18), radius: width * 0.06, x: width * 0.03, y: width * 0.05)
    }

    private var borderColor: Color {
        if isSelected { return Theme.coral }
        if isHinted { return Theme.teal }
        return Color(hex: 0xD9CDB8)
    }

    @ViewBuilder
    private var content: some View {
        switch face {
        case .characters(let n):
            VStack(spacing: -width * 0.08) {
                Text(Self.kanjiNumerals[max(0, min(8, n - 1))])
                    .font(.system(size: width * 0.5, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("萬")
                    .font(.system(size: width * 0.36, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.coral)
            }
        case .circles(let n):
            ZStack {
                Circle()
                    .strokeBorder(Self.circleColor, lineWidth: width * 0.08)
                    .frame(width: width * 0.68, height: width * 0.68)
                Text("\(n)")
                    .font(.system(size: width * 0.4, weight: .black, design: .rounded))
                    .foregroundStyle(Self.circleColor)
            }
        case .bamboos(let n):
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                    .strokeBorder(Self.bambooColor, lineWidth: width * 0.08)
                    .frame(width: width * 0.62, height: width * 0.72)
                Text("\(n)")
                    .font(.system(size: width * 0.4, weight: .black, design: .rounded))
                    .foregroundStyle(Self.bambooColor)
            }
        case .wind(let n):
            glyph(Self.winds[max(0, min(3, n))], color: Theme.ink)
        case .dragon(let n):
            glyph(Self.dragons[max(0, min(2, n))], color: dragonColor(n))
        case .flower(let n):
            glyph(Self.flowers[max(0, min(3, n))], color: Theme.purple)
        case .season(let n):
            glyph(Self.seasons[max(0, min(3, n))], color: Theme.pink)
        }
    }

    private func glyph(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: width * 0.62, weight: .bold, design: .serif))
            .foregroundStyle(color)
    }

    private func dragonColor(_ n: Int) -> Color {
        switch n {
        case 0:  return Theme.coral        // 中
        case 1:  return Self.bambooColor   // 發
        default: return Self.circleColor   // 白
        }
    }
}
