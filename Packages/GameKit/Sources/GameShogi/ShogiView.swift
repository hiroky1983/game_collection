import SwiftUI
import Core

/// 将棋の対局画面（CPU 対戦）。人間の手番側を常に手前に表示する。
public struct ShogiView: View {
    @State private var model: ShogiGameModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showUndoConfirm = false
    @State private var showResignConfirm = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ShogiGameModel(services: services))
    }

    /// 人間が後手なら盤を反転して表示する。
    private var flipped: Bool { model.humanSide == .white }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            if !model.gameOver { gameControls }
            HandAreaView(model: model, color: model.humanSide.opponent)
            board
            HandAreaView(model: model, color: model.humanSide)
            if model.gameOver { reviewControls }
            Spacer(minLength: 8)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
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
                Text("将棋")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showNewGame = true } label: {
                    Label("新規対局", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showNewGame) {
            NewGameSheet(initialSide: model.humanSide, initialLevel: model.aiLevel) { side, level in
                model.newGame(humanSide: side, aiLevel: level)
                showNewGame = false
            } onCancel: {
                showNewGame = false
            }
        }
        .overlay {
            if model.pendingPromotion != nil {
                promotionOverlay
            }
        }
        .task(id: model.moves.count) {
            await model.performAIMoveIfNeeded()
        }
    }

    private var promotionOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("成りますか？")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 16) {
                    Button {
                        model.resolvePromotion(false)
                    } label: {
                        Text("不成")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 80, height: 44)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Theme.ink)
                    }
                    Button {
                        model.resolvePromotion(true)
                    } label: {
                        Text("成る")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 80, height: 44)
                            .background(Theme.coral, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        }
    }

    // MARK: - 盤

    private var board: some View {
        let pos = model.displayedPosition
        return GeometryReader { geo in
            let cell = (geo.size.width - 8) / 9
            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { col in
                            let idx = squareIndex(row: row, col: col)
                            ShogiCell(
                                piece: pos.squares[idx],
                                size: cell,
                                pointsUp: pos.squares[idx]?.color == model.humanSide,
                                isSelected: model.selectedSquare == idx,
                                isTarget: model.legalTargets.contains(idx),
                                isLastMove: model.highlightedSquares.contains(idx)
                            )
                            .onTapGesture { model.tapSquare(idx) }
                        }
                    }
                }
            }
            .background(BoardStyle.line)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(BoardStyle.frame)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 画面 (row,col) → 内部マス。人間が先手なら先手視点、後手なら反転。
    private func squareIndex(row: Int, col: Int) -> Int {
        Sq.boardIndex(row: row, col: col, flipped: flipped)
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let result = model.resultText {
                Label(result, systemImage: "flag.checkered")
                    .font(Theme.body(16)).foregroundStyle(Theme.coral)
            } else {
                Text(model.position.sideToMove == .black ? "先手番" : "後手番")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(model.position.sideToMove == .black ? Theme.ink : Theme.teal))
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text("CPU思考中…").font(Theme.body(13)).foregroundStyle(Theme.inkSub)
                } else if let last = model.highlightedMoveText {
                    Text("直前 \(last)").font(Theme.body(14)).foregroundStyle(Theme.ink)
                }
            }
            Spacer()
            Text("\(model.moves.count)手").font(Theme.body(13)).foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var gameControls: some View {
        HStack(spacing: 12) {
            Button { showResignConfirm = true } label: {
                Label("投了", systemImage: "flag.fill")
            }
            .foregroundStyle(Theme.coral)
            .alert("投了しますか？", isPresented: $showResignConfirm) {
                Button("投了する", role: .destructive) { model.resign() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("現在の対局を終了します。\nCPUの勝ちになります。")
            }

            Spacer()

            Button { showUndoConfirm = true } label: {
                Label("待った", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .alert("待った確認", isPresented: $showUndoConfirm) {
                Button(model.undoUsed ? "広告を見て戻す" : "戻す（無料）") {
                    Task {
                        if model.undoUsed { await services.ads.showInterstitial() }
                        model.undoLastExchange()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(model.undoUsed
                     ? "無料の待ったは使い切りました。\n広告を視聴すると1手戻せます。"
                     : "直前の1手を取り消します。\n無料で使えるのは1回だけです。")
            }
        }
        .font(Theme.body(14))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var reviewControls: some View {
        HStack(spacing: 16) {
            Button { model.reviewStepBack() } label: { Image(systemName: "backward.frame.fill") }
                .disabled(model.reviewPly <= 0)
            Text("検討 \(model.reviewPly)/\(model.moves.count)手")
                .font(Theme.body(15)).monospacedDigit().foregroundStyle(Theme.ink)
            Button { model.reviewStepForward() } label: { Image(systemName: "forward.frame.fill") }
                .disabled(model.reviewPly >= model.moves.count)
            ShareLink(item: KIF.export(model)) {
                Label("KIF", systemImage: "square.and.arrow.up")
            }
            .font(Theme.body(15))
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 新規対局シート

/// 先後・難易度を大きなボタンで選ぶ。
struct NewGameSheet: View {
    @State private var side: Side
    @State private var level: Int
    let onStart: (Side, Int) -> Void
    let onCancel: () -> Void

    init(initialSide: Side, initialLevel: Int,
         onStart: @escaping (Side, Int) -> Void, onCancel: @escaping () -> Void) {
        _side = State(initialValue: initialSide)
        _level = State(initialValue: initialLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                section("あなたの手番") {
                    HStack(spacing: 12) {
                        chooser(title: "先手", subtitle: "▲ 先に指す", selected: side == .black, accent: Theme.ink) { side = .black }
                        chooser(title: "後手", subtitle: "△ 後に指す", selected: side == .white, accent: Theme.teal) { side = .white }
                    }
                }
                section("CPUの強さ") {
                    HStack(spacing: 12) {
                        chooser(title: "弱", subtitle: "駒得だけ", selected: level == 0, accent: Theme.teal) { level = 0 }
                        chooser(title: "普通", subtitle: "囲いを作る", selected: level == 1, accent: Theme.yellow) { level = 1 }
                        chooser(title: "強", subtitle: "定跡＋深読み", selected: level == 2, accent: Theme.coral) { level = 2 }
                    }
                }
                Spacer()
                Button { onStart(side, level) } label: {
                    Text("対局開始").font(Theme.body(18)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("新規対局")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.body(15)).foregroundStyle(Theme.inkSub)
            content()
        }
    }

    private func chooser(title: String, subtitle: String, selected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(Theme.title(22)).foregroundStyle(selected ? .white : Theme.ink)
                Text(subtitle).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white.opacity(0.9) : Theme.inkSub)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? accent : Theme.surface)
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 盤・駒

/// 盤の配色（ポップ・明るい木目調）。
enum BoardStyle {
    static let frame = Color(hex: 0xE7B96A)
    static let cell = Color(hex: 0xFBE6B6)
    static let line = Color(hex: 0xCDA15B)
    static let komaSente = Color(hex: 0xFFF1CF)
    static let komaGote = Color(hex: 0xCFEFF0)
}

/// 1 マス。
struct ShogiCell: View {
    let piece: Piece?
    let size: CGFloat
    let pointsUp: Bool
    let isSelected: Bool
    let isTarget: Bool
    let isLastMove: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(BoardStyle.cell)
            if isLastMove {
                Rectangle().fill(Theme.coral.opacity(0.22)) // 直前手のマス
            }
            if isSelected {
                Rectangle().fill(Theme.yellow.opacity(0.65))
            }
            if let piece {
                KomaView(piece: piece, size: size, pointsUp: pointsUp)
            }
            if isTarget {
                if piece == nil {
                    Circle().fill(Theme.coral.opacity(0.55))
                        .frame(width: size * 0.28, height: size * 0.28)
                } else {
                    RoundedRectangle(cornerRadius: 4).stroke(Theme.coral, lineWidth: 3).padding(2)
                }
            }
        }
        .frame(width: size, height: size)
        .padding(0.5)
    }
}

/// ポップな駒（将棋の駒形＝五角形）。pointsUp=false（相手の駒）は 180 度回転。
struct KomaView: View {
    let piece: Piece
    let size: CGFloat
    let pointsUp: Bool

    var body: some View {
        ZStack {
            KomaShape()
                .fill((piece.color == .black ? BoardStyle.komaSente : BoardStyle.komaGote).gradient)
                .overlay(KomaShape().stroke(Theme.ink.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            Text(Glyph.kanji(for: piece))
                .font(.system(size: size * 0.46, weight: .black, design: .rounded))
                .foregroundStyle(piece.promoted ? Theme.coral : Theme.ink)
        }
        .frame(width: size * 0.86, height: size * 0.86)
        .rotationEffect(.degrees(pointsUp ? 0 : 180))
    }
}

/// 将棋の駒形（五角形）。上が尖り、下が平ら。
struct KomaShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let shoulder = h * 0.32
        var p = Path()
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.02))
        p.addLine(to: CGPoint(x: w * 0.83, y: shoulder))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.17, y: shoulder))
        p.closeSubpath()
        return p
    }
}

// MARK: - 持ち駒エリア（独立 View で再描画スコープを分離）

/// 持ち駒の表示・打ち駒選択。ShogiView.body から切り出すことで、
/// isThinking など持ち駒に無関係なプロパティ変化では再描画されない。
private struct HandAreaView: View {
    let model: ShogiGameModel
    let color: Side

    var body: some View {
        let pos     = model.displayedPosition
        let hand    = pos.hands[color.rawValue]
        let owned   = PieceType.allCases.filter { $0.isDroppable && hand[$0.rawValue] > 0 }
        let isYou   = color == model.humanSide

        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "あなた" : "CPU")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isYou ? Theme.teal : Theme.inkSub)
                Text(color == .black ? "☗" : "☖")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSub)
            }
            .frame(width: 38, alignment: .leading)

            if owned.isEmpty {
                Text("持ち駒なし")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Spacer()
            } else {
                HStack(spacing: 6) {
                    ForEach(owned, id: \.rawValue) { type in
                        let selected = model.selectedHand == type && color == pos.sideToMove
                        let count    = hand[type.rawValue]
                        Button { model.tapHand(type, color: color) } label: {
                            VStack(spacing: 2) {
                                KomaView(piece: Piece(type: type, color: color),
                                         size: 32, pointsUp: isYou)
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selected ? Theme.yellow : BoardStyle.komaSente)
                                    )
                                Text("×\(count)")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(selected ? Theme.coral : Theme.inkSub)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .drawingGroup() // 駒形状・グラデーションを Metal で一括描画
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// 駒の漢字表記。
enum Glyph {
    static func kanji(for p: Piece) -> String {
        if p.promoted {
            switch p.type {
            case .pawn: return "と"
            case .lance: return "杏"
            case .knight: return "圭"
            case .silver: return "全"
            case .bishop: return "馬"
            case .rook: return "龍"
            default: break
            }
        }
        switch p.type {
        case .pawn: return "歩"
        case .lance: return "香"
        case .knight: return "桂"
        case .silver: return "銀"
        case .gold: return "金"
        case .bishop: return "角"
        case .rook: return "飛"
        case .king: return p.color == .black ? "玉" : "王"
        }
    }
}
