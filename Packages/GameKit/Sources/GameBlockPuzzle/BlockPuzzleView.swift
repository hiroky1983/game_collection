import SwiftUI
import Core

/// ブロックならべ（#493）のプレイ画面。
///
/// 手元のピースを盤へドラッグして置く。**指の位置とマスの対応**は `BlockPuzzleDrop` の
/// 純関数に切り出してあり、この View は測った寸法を渡すだけにしている。
public struct BlockPuzzleView: View {
    private let services: GameServices
    @State private var model: BlockPuzzleModel
    @State private var showRewardNotEarned = false
    @State private var isContinuing = false
    /// 盤の内側（マスが並ぶ領域）の原点とマスの一辺。ドラッグ位置の翻訳に使う。
    @State private var boardOrigin: CGPoint = .zero
    @State private var cellSize: CGFloat = 0
    @State private var drag: DragState?
    @Environment(\.dismiss) private var dismiss

    /// 盤と手元を同じ物差しで測るための座標空間。
    private static let space = "blockpuzzle"
    /// 盤の内側の余白。
    private static let boardInset: CGFloat = 6

    private struct DragState: Equatable {
        var index: Int
        /// 指の位置（盤の内側の左上を原点とする座標）。
        var touch: CGPoint
    }

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: BlockPuzzleModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 12) {
            header
            boardView
            handTray
            // 初回だけ出す 1 行（#118。以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.blockPuzzle, playLog: services.playLog)
            recommendationArea
            Spacer()
            BannerSlot(ads: services.ads)
        }
        .padding()
        .coordinateSpace(name: Self.space)
        // ドラッグ中のピースは盤にも手元にも属さないので、画面全体の上に別に描く。
        .overlay(alignment: .topLeading) { dragPreview }
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
                Text("ブロックならべ")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { withGameAnimation { model.newGame() } } label: {
                    Label("リセット", systemImage: "arrow.clockwise")
                }
            }
        }
        .howToPlay(.blockPuzzle)
        .alert("コンティニューできませんでした", isPresented: $showRewardNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
    }

    // MARK: - スコア

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("スコア")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
            // 直前の 1 手の成果。次に置くまで出したままにして、消えた瞬間を見逃しても分かるようにする。
            if model.lastClearedLines > 0 {
                Text(model.combo > 1 ? "\(model.lastClearedLines)本消し \(model.combo)連鎖"
                                     : "\(model.lastClearedLines)本消し")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.coral)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BlockPuzzleAccessibility.statusLabel(score: model.score, combo: model.combo))
    }

    // MARK: - 盤

    private var boardView: some View {
        GeometryReader { geo in
            let cell = (geo.size.width - Self.boardInset * 2) / CGFloat(BlockPuzzleBoard.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted.opacity(0.18))
                cells(cell: cell)
                if let ghost = ghostPlacement(cellSize: cell) {
                    ghostView(ghost, cell: cell)
                }
            }
            .background {
                // 盤の内側の原点を測るだけ。配置には干渉しない（AdaptiveLayout と同じ手）。
                GeometryReader { inner in
                    let frame = inner.frame(in: .named(Self.space))
                    Color.clear
                        .task(id: frame) {
                            boardOrigin = CGPoint(x: frame.minX + Self.boardInset,
                                                  y: frame.minY + Self.boardInset)
                            cellSize = cell
                        }
                }
            }
            .overlay { if model.gameOver { gameOverOverlay } }
        }
        .aspectRatio(1, contentMode: .fit)
        .gameAnimation(.easeInOut(duration: 0.15), value: model.board)
    }

    private func cells(cell: CGFloat) -> some View {
        ForEach(0..<BlockPuzzleBoard.size, id: \.self) { row in
            ForEach(0..<BlockPuzzleBoard.size, id: \.self) { col in
                let value = model.board[row][col]
                RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                    .fill(value == 0 ? Theme.fillMuted.opacity(0.16) : Self.color(value))
                    .frame(width: cell - 2, height: cell - 2)
                    .offset(x: Self.boardInset + CGFloat(col) * cell + 1,
                            y: Self.boardInset + CGFloat(row) * cell + 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(BlockPuzzleAccessibility.cellLabel(row: row, col: col, value: value))
            }
        }
    }

    /// ドラッグ中に「ここに置かれる」を見せる影。置けない位置では赤く出す。
    private func ghostPlacement(cellSize cell: CGFloat) -> (piece: BlockPuzzlePiece, row: Int, col: Int, valid: Bool)? {
        guard let drag, let piece = model.hand[drag.index] else { return nil }
        let center = BlockPuzzleDrop.pieceCenter(touch: drag.touch, cellSize: cell)
        let target = BlockPuzzleDrop.targetCell(center: center, piece: piece, cellSize: cell)
        let valid = BlockPuzzleBoard.canPlace(model.board, piece, row: target.row, col: target.col)
        return (piece, target.row, target.col, valid)
    }

    private func ghostView(
        _ ghost: (piece: BlockPuzzlePiece, row: Int, col: Int, valid: Bool),
        cell: CGFloat
    ) -> some View {
        ForEach(ghost.piece.cells.indices, id: \.self) { i in
            let c = ghost.piece.cells[i]
            let row = ghost.row + c.row
            let col = ghost.col + c.col
            if row >= 0, row < BlockPuzzleBoard.size, col >= 0, col < BlockPuzzleBoard.size {
                RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                    .fill((ghost.valid ? Self.color(ghost.piece.colorIndex) : Theme.coral).opacity(0.4))
                    .frame(width: cell - 2, height: cell - 2)
                    .offset(x: Self.boardInset + CGFloat(col) * cell + 1,
                            y: Self.boardInset + CGFloat(row) * cell + 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 手元

    private var handTray: some View {
        HStack(spacing: 10) {
            ForEach(0..<BlockPuzzleBoard.handSize, id: \.self) { index in
                handSlot(index)
            }
        }
        .frame(height: 78)
    }

    private func handSlot(_ index: Int) -> some View {
        let piece = model.hand[index]
        let placeable = piece.map { BlockPuzzleBoard.canPlaceAnywhere(model.board, $0) } ?? false
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.fillMuted.opacity(0.12))
            if let piece, drag?.index != index {
                PieceShape(piece: piece, cell: 14)
                    .opacity(placeable ? 1 : 0.35)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(index: index))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BlockPuzzleAccessibility.handLabel(index: index, piece: piece, canPlace: placeable))
    }

    private func dragGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !model.gameOver, model.hand.indices.contains(index), model.hand[index] != nil else { return }
                drag = DragState(index: index, touch: boardLocal(value.location))
            }
            .onEnded { value in
                defer { drag = nil }
                guard !model.gameOver, model.hand.indices.contains(index),
                      let piece = model.hand[index], cellSize > 0 else { return }
                let center = BlockPuzzleDrop.pieceCenter(touch: boardLocal(value.location), cellSize: cellSize)
                let target = BlockPuzzleDrop.targetCell(center: center, piece: piece, cellSize: cellSize)
                withGameAnimation(.easeInOut(duration: 0.15)) {
                    model.place(pieceIndex: index, row: target.row, col: target.col)
                }
            }
    }

    /// 座標空間の点を、盤の内側の左上を原点とする点へ移す。
    private func boardLocal(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - boardOrigin.x, y: point.y - boardOrigin.y)
    }

    /// ドラッグ中のピース本体。指の少し上に浮かせて置き先を隠さない。
    @ViewBuilder
    private var dragPreview: some View {
        if let drag, let piece = model.hand[drag.index], cellSize > 0 {
            let center = BlockPuzzleDrop.pieceCenter(touch: drag.touch, cellSize: cellSize)
            PieceShape(piece: piece, cell: cellSize)
                .position(x: boardOrigin.x + center.x, y: boardOrigin.y + center.y)
                .allowsHitTesting(false)
        }
    }

    // MARK: - レコメンド・ゲームオーバー

    /// レコメンドカードの枠。カードの有無で高さが動かないよう、常にひな形で高さを確保する（#148）。
    private var recommendationArea: some View {
        ZStack(alignment: .top) {
            RecommendationCard.heightPlaceholder
            RecommendationSlot(services: services, isFinished: model.gameOver)
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text("ゲームオーバー").font(.title2.bold()).foregroundStyle(.white)
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                if !model.continueUsed {
                    Button {
                        // 広告のロード〜表示中の連打で2本目が失敗し、誤ってアラートが出るのを防ぐ
                        guard !isContinuing else { return }
                        isContinuing = true
                        Task {
                            // 視聴完了（報酬獲得）したときだけコンティニューを許可する
                            if await services.ads.showRewardedAd() {
                                withGameAnimation { model.continueAfterAd() }
                            } else {
                                showRewardNotEarned = true
                            }
                            isContinuing = false
                        }
                    } label: {
                        Label("広告を見て中央を空ける", systemImage: "play.rectangle.fill")
                            .foregroundStyle(Theme.onAccent)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Fill.coral)
                    .disabled(isContinuing)
                }
                Button("もう一度") { withGameAnimation { model.newGame() } }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
    }

    /// 色番号 1...5 を配色へ。0（空きマス）はここに来ない。
    static func color(_ index: Int) -> Color {
        let palette = Theme.Fill.palette
        guard index >= 1, index <= palette.count else { return Theme.fillMuted }
        return palette[index - 1]
    }
}

/// ピース 1 個の絵。手元のスロットとドラッグ中のプレビューで共有する。
struct PieceShape: View {
    let piece: BlockPuzzlePiece
    let cell: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 外接矩形ぶんの透明な下地を敷いて、`ZStack` の大きさをピースの寸法に固定する。
            Color.clear
                .frame(width: CGFloat(piece.width) * cell, height: CGFloat(piece.height) * cell)
            ForEach(piece.cells.indices, id: \.self) { i in
                let c = piece.cells[i]
                RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                    .fill(BlockPuzzleView.color(piece.colorIndex))
                    .frame(width: cell - 2, height: cell - 2)
                    .offset(x: CGFloat(c.col) * cell + 1, y: CGFloat(c.row) * cell + 1)
            }
        }
        .accessibilityHidden(true)
    }
}
