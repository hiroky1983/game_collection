import SwiftUI
import Core

public struct OthelloView: View {
    @State private var model: OthelloModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showPassAlert = false
    @State private var showResignConfirm = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: OthelloModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 10) {
            statusBar
            scoreRow
            board
            if model.gameOver {
                resultControls
            } else {
                gameControls
            }
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
                Text("オセロ")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showNewGame = true } label: {
                    Label("新規対局", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showNewGame) {
            OthelloNewGameSheet(humanSide: model.humanSide, aiLevel: model.aiLevel) { side, level in
                model.newGame(humanSide: side, aiLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .alert("パス", isPresented: $showPassAlert) {
            Button("OK") { model.confirmPass() }
        } message: {
            Text("打てるマスがありません。パスします。")
        }
        .alert("投了しますか？", isPresented: $showResignConfirm) {
            Button("投了する", role: .destructive) { model.resign() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在の対局を終了します。")
        }
        .onChange(of: model.mustPass) { _, newValue in
            if newValue && !model.isAITurn { showPassAlert = true }
        }
        .task(id: model.turnID) {
            await model.performAIMoveIfNeeded()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let w = model.winner {
                Label(w == model.humanSide ? "あなたの勝ち！" : "CPUの勝ち",
                      systemImage: "flag.checkered")
                    .font(Theme.body(16)).foregroundStyle(Theme.coral)
            } else if model.isDraw {
                Label("引き分け", systemImage: "equal.circle")
                    .font(Theme.body(16)).foregroundStyle(Theme.inkSub)
            } else {
                let isMine = !model.isAITurn
                Text(isMine ? "あなたの番" : "CPUの番")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(isMine ? Theme.teal : Theme.coral))
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text("思考中…").font(Theme.body(13)).foregroundStyle(Theme.inkSub)
                }
            }
            Spacer()
            Text("\(model.board.totalPieces)手")
                .font(Theme.body(13)).foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Score Row

    private var scoreRow: some View {
        HStack(spacing: 0) {
            scoreCell(stone: .black, label: "●黒")
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1)
            scoreCell(stone: .white, label: "○白")
        }
        .popCard(corner: Theme.cornerSmall)
    }

    private func scoreCell(stone: OthelloStone, label: String) -> some View {
        let count = stone == .black ? model.blackCount : model.whiteCount
        let isActive = model.currentStone == stone && !model.gameOver
        let isHuman  = model.humanSide == stone
        return HStack(spacing: 10) {
            if stone == .white {
                Text("\(count)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            VStack(alignment: stone == .black ? .leading : .trailing, spacing: 1) {
                Text(isHuman ? "あなた" : "CPU")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isHuman ? Theme.teal : Theme.inkSub)
                Text(label)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            Circle()
                .fill(stone == .black ? Color(hex: 0x1A1A1A) : Color(hex: 0xF0ECD8))
                .overlay(stone == .white ? Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1) : nil)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(stone == .black ? 0.3 : 0.1), radius: 2, y: 1)
            if stone == .black {
                Spacer()
                Text("\(count)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(isActive ? Theme.teal.opacity(0.08) : Color.clear)
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let size = geo.size.width
            let cell = size / CGFloat(othelloBoardSize)
            let validSet = (model.gameOver || model.isAITurn || model.mustPass)
                ? Set<Int>()
                : Set(model.board.validMoves(for: model.currentStone).map { $0.0 * othelloBoardSize + $0.1 })

            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0x1C6B36))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                Canvas { ctx, sz in
                    let c = sz.width / CGFloat(othelloBoardSize)
                    let lineShading = GraphicsContext.Shading.color(Color(hex: 0x145028).opacity(0.9))

                    // グリッド線
                    for i in 0...othelloBoardSize {
                        let p = CGFloat(i) * c
                        var vp = Path(); vp.move(to: CGPoint(x: p, y: 0)); vp.addLine(to: CGPoint(x: p, y: sz.height))
                        ctx.stroke(vp, with: lineShading, lineWidth: 1)
                        var hp = Path(); hp.move(to: CGPoint(x: 0, y: p)); hp.addLine(to: CGPoint(x: sz.width, y: p))
                        ctx.stroke(hp, with: lineShading, lineWidth: 1)
                    }

                    // 合法手ドット
                    for idx in validSet {
                        let row = idx / othelloBoardSize, col = idx % othelloBoardSize
                        let cx = (CGFloat(col) + 0.5) * c, cy = (CGFloat(row) + 0.5) * c
                        let r  = c * 0.18
                        ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                                 with: .color(Color.white.opacity(0.38)))
                    }

                    // 石
                    for row in 0..<othelloBoardSize {
                        for col in 0..<othelloBoardSize {
                            guard let stone = model.board[row, col] else { continue }
                            let cx = (CGFloat(col) + 0.5) * c, cy = (CGFloat(row) + 0.5) * c
                            let r  = c * 0.43
                            let rect = CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)
                            if stone == .black {
                                ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0x1A1A1A)))
                            } else {
                                ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0xF0ECD8)))
                                ctx.stroke(Path(ellipseIn: rect), with: .color(Color.gray.opacity(0.3)), lineWidth: 1)
                            }
                            // 直前手マーカー
                            if let last = model.lastMove, last.row == row, last.col == col {
                                let mr = r * 0.3
                                let mRect = CGRect(x: cx-mr, y: cy-mr, width: mr*2, height: mr*2)
                                ctx.fill(Path(ellipseIn: mRect),
                                         with: .color(stone == .black ? Color.white.opacity(0.5)
                                                                       : Color(hex: 0x1C6B36).opacity(0.5)))
                            }
                        }
                    }
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { val in
                            guard !model.isAITurn, !model.gameOver, !model.mustPass else { return }
                            let col = Int(val.location.x / cell)
                            let row = Int(val.location.y / cell)
                            guard row >= 0, row < othelloBoardSize,
                                  col >= 0, col < othelloBoardSize else { return }
                            model.tap(row: row, col: col)
                        }
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Controls

    private var gameControls: some View {
        HStack {
            Button { showResignConfirm = true } label: {
                Label("投了", systemImage: "flag.fill")
            }
            .foregroundStyle(Theme.coral)
            Spacer()
        }
        .font(Theme.body(14))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultControls: some View {
        Button { showNewGame = true } label: {
            Text("もう一度").font(Theme.body(16)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.coral)
    }
}

// MARK: - New Game Sheet

struct OthelloNewGameSheet: View {
    @State private var side: OthelloStone
    @State private var level: Int
    let onStart: (OthelloStone, Int) -> Void
    let onCancel: () -> Void

    init(humanSide: OthelloStone, aiLevel: Int,
         onStart: @escaping (OthelloStone, Int) -> Void,
         onCancel: @escaping () -> Void) {
        _side  = State(initialValue: humanSide)
        _level = State(initialValue: aiLevel)
        self.onStart  = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                section("あなたの石") {
                    HStack(spacing: 12) {
                        chooser(title: "●黒", subtitle: "先手",
                                selected: side == .black, accent: Theme.ink) { side = .black }
                        chooser(title: "○白", subtitle: "後手",
                                selected: side == .white, accent: Theme.inkSub) { side = .white }
                    }
                }
                section("CPUの強さ") {
                    HStack(spacing: 12) {
                        chooser(title: "弱",   subtitle: "浅い読み",
                                selected: level == 0, accent: Theme.teal)   { level = 0 }
                        chooser(title: "普通", subtitle: "標準",
                                selected: level == 1, accent: Theme.yellow) { level = 1 }
                        chooser(title: "強",   subtitle: "深い読み",
                                selected: level == 2, accent: Theme.coral)  { level = 2 }
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

    private func chooser(title: String, subtitle: String, selected: Bool,
                         accent: Color, action: @escaping () -> Void) -> some View {
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
