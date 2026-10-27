import SwiftUI
import Core

/// 線つなぎ（#2235）のプレイ画面。点から指でなぞって、同じ数字どうしを線でつなぐ。
public struct TsunagiView: View {
    private let services: GameServices
    @State private var model: TsunagiModel
    @State private var showConfirmReset = false
    /// 大きさを変えようとしたが、途中の盤があるので確認を出している先の大きさ。
    @State private var pendingSize: TsunagiSize?
    /// いまのなぞりが盤の上で始まったか（始点が空きマスなら無視する）。
    @State private var isDragging = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: TsunagiModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 14) {
            header
            // 盤は残りの高さを Spacer と山分けしない（下の段が増えた分だけ盤が縮むのを防ぐ）。
            boardView.layoutPriority(1)
            statusLine
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.tsunagi, playLog: services.playLog)
            RecommendationArea(services: services, isFinished: model.isSolved)
            Spacer()
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("線つなぎ"), review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        if model.hasProgressToLose {
                            pendingSize = nil
                            showConfirmReset = true
                        } else {
                            withGameAnimation { model.newGame() }
                        }
                    })
        .howToPlay(HowToPlayGuide.tsunagi.illustrated(TsunagiHowToFigures.items))
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmReset, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) {
                    let size = pendingSize
                    withGameAnimation { model.newGame(size: size) }
                    pendingSize = nil
                }
                Button(tr("キャンセル"), role: .cancel) { pendingSize = nil }
            } message: {
                Text(tr("途中で終了すると、いまの盤面と手数が失われます。"))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
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
            Picker(tr("盤の大きさ"), selection: Binding(
                get: { model.size },
                set: { choose(size: $0) }
            )) {
                ForEach(TsunagiSize.allCases, id: \.self) { size in
                    Text(verbatim: size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 大きさを変える。途中の盤があれば確認してから。
    private func choose(size: TsunagiSize) {
        guard size != model.size else { return }
        if model.hasProgressToLose {
            pendingSize = size
            showConfirmReset = true
        } else {
            withGameAnimation { model.newGame(size: size) }
        }
    }

    /// 盤の下の 1 行。つながった数と埋まったマスの数。全部つながったのに空きが残っていればそう伝える。
    private var statusLine: some View {
        Text(model.isConnectedButNotFilled
             ? tr("全部つながりました。空いているマスも線で通りましょう")
             : TsunagiAccessibility.progressLabel(
                connected: model.connectedCount, pairs: model.puzzle.pairCount,
                filled: model.filledCount, cells: model.puzzle.cellCount))
            .scaledFont(13, weight: .bold, design: .rounded)
            .foregroundStyle(model.isConnectedButNotFilled ? Theme.coralText : Theme.inkSubText)
            .multilineTextAlignment(.center)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let n = model.puzzle.side
            let inset: CGFloat = 6
            let cellSide = (geo.size.width - inset * 2) / CGFloat(n)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                TsunagiBoardCanvas(
                    puzzle: model.puzzle, paths: model.paths, owners: model.owners,
                    cellSide: cellSide, activeColor: model.activeColor
                )
                .offset(x: inset, y: inset)
                accessibilityCells(cellSide: cellSide, inset: inset)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(cellSide: cellSide, inset: inset))
            .overlay {
                if model.isSolved { solvedOverlay }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 指の位置のマス。盤の外なら nil。
    private func cell(at point: CGPoint, cellSide: CGFloat, inset: CGFloat) -> Int? {
        let n = model.puzzle.side
        let col = Int(((point.x - inset) / cellSide).rounded(.down))
        let row = Int(((point.y - inset) / cellSide).rounded(.down))
        guard (0..<n).contains(col), (0..<n).contains(row) else { return nil }
        return row * n + col
    }

    private func dragGesture(cellSide: CGFloat, inset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !model.isSolved else { return }
                if !isDragging {
                    isDragging = true
                    if let start = cell(at: value.startLocation, cellSide: cellSide, inset: inset) {
                        model.beginStroke(at: start)
                    }
                }
                if let current = cell(at: value.location, cellSide: cellSide, inset: inset) {
                    model.extendStroke(to: current)
                }
            }
            .onEnded { _ in
                isDragging = false
                withGameAnimation { model.endStroke() }
            }
    }

    /// VoiceOver 用のマスの並び。見た目は Canvas で描き、読み上げと操作だけをこちらに置く。
    private func accessibilityCells(cellSide: CGFloat, inset: CGFloat) -> some View {
        let n = model.puzzle.side
        return ForEach(0..<model.puzzle.cellCount, id: \.self) { index in
            let owner = model.owners[index]
            let isEndpoint = model.puzzle.endpointColor(at: index) != nil
            Color.clear
                .frame(width: cellSide, height: cellSide)
                .offset(x: inset + CGFloat(index % n) * cellSide, y: inset + CGFloat(index / n) * cellSide)
                .accessibilityElement()
                .accessibilityLabel(TsunagiAccessibility.cellLabel(
                    cell: index, side: n, number: owner.map { $0 + 1 }, isEndpoint: isEndpoint,
                    isConnected: owner.map { model.isComplete($0) } ?? false,
                    isSelected: owner.map { $0 == model.activeColor && model.paths[$0].last == index } ?? false
                ))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { withGameAnimation { model.activate(cell: index) } }
        }
    }

    private var solvedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text(tr("クリア！")).font(.title2.bold()).foregroundStyle(.white)
                Text(tr("%lld手でつなぎました", model.moves))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                Button { withGameAnimation { model.newGame() } } label: {
                    Text(tr("もう一回")).foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
            }
        }
    }
}

/// 数字ごとの色。色だけに頼らず、点には必ず数字を書く（色覚の多様性・#2235 の受け入れ条件）。
enum TsunagiPalette {
    static func color(_ index: Int) -> Color {
        let hues: [Double] = [0.0, 0.58, 0.13, 0.33, 0.78, 0.07, 0.5, 0.9, 0.22, 0.66, 0.42]
        let hue = hues[index % hues.count]
        let brightness = index >= hues.count ? 0.65 : 0.88
        return Color(hue: hue, saturation: 0.62, brightness: brightness)
    }
}

/// 盤の絵（マス目・線・点）。本番と遊び方の図で同じものを使う。
struct TsunagiBoardCanvas: View {
    let puzzle: TsunagiPuzzle
    let paths: [[Int]]
    let owners: [Int?]
    let cellSide: CGFloat
    var activeColor: Int? = nil

    private func center(_ cell: Int) -> CGPoint {
        CGPoint(x: (CGFloat(cell % puzzle.side) + 0.5) * cellSide,
                y: (CGFloat(cell / puzzle.side) + 0.5) * cellSide)
    }

    var body: some View {
        let n = puzzle.side
        ZStack(alignment: .topLeading) {
            // マス目。線が通ったマスは薄くその色を敷く。
            ForEach(0..<puzzle.cellCount, id: \.self) { index in
                Rectangle()
                    .fill(owners[index].map { TsunagiPalette.color($0).opacity(0.18) } ?? Theme.fillMuted.opacity(0.08))
                    .overlay(Rectangle().stroke(Theme.inkSub.opacity(0.35), lineWidth: 0.8))
                    .frame(width: cellSide, height: cellSide)
                    .offset(x: CGFloat(index % n) * cellSide, y: CGFloat(index / n) * cellSide)
            }
            // 線。
            ForEach(Array(paths.enumerated()), id: \.offset) { color, path in
                if path.count >= 2 {
                    Path { p in
                        p.move(to: center(path[0]))
                        for cell in path.dropFirst() { p.addLine(to: center(cell)) }
                    }
                    .stroke(TsunagiPalette.color(color),
                            style: StrokeStyle(lineWidth: cellSide * (color == activeColor ? 0.36 : 0.3),
                                               lineCap: .round, lineJoin: .round))
                }
            }
            // 点（数字入りの丸）。
            ForEach(Array(puzzle.endpoints.enumerated()), id: \.offset) { color, ends in
                ForEach(ends, id: \.self) { cell in
                    let point = center(cell)
                    Circle()
                        .fill(TsunagiPalette.color(color))
                        .overlay(Circle().strokeBorder(Theme.ink.opacity(0.25), lineWidth: 1))
                        .overlay {
                            Text(verbatim: "\(color + 1)")
                                .font(.system(size: cellSide * 0.42, weight: .heavy, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(Theme.onAccent)
                        }
                        .frame(width: cellSide * 0.72, height: cellSide * 0.72)
                        .position(point)
                }
            }
        }
        .frame(width: cellSide * CGFloat(n), height: cellSide * CGFloat(n), alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
