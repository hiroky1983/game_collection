import SwiftUI
import Core

public struct BackgammonView: View {
    @State private var model: BackgammonModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showPassAlert = false
    @State private var showResignConfirm = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: BackgammonModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            Spacer(minLength: 0)
            board
                .padding(.horizontal, -Theme.pad)
                .layoutPriority(1)
                .overlay {
                    // 勝敗はフェードで出す。修飾子は 1 つのビューに 1 つだけ（入れ子にすると打ち消し合う・#199）。
                    ZStack {
                        if model.gameOver {
                            resultOverlay
                                .transition(.opacity)
                        }
                    }
                    .gameAnimation(.easeOut(duration: 0.25), value: model.gameOver)
                }
            Spacer(minLength: 0)
            HowToPlayHint(.backgammon, playLog: services.playLog)
            controlArea
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
        .padding(Theme.pad)
        .gameChrome(title: "バックギャモン", review: services.review,
                    newGame: GameChromeNewGame(.match) {
                        showNewGame = true
                    })
        .howToPlay(.backgammon)
        .sheet(isPresented: $showNewGame) {
            BackgammonNewGameSheet(aiLevel: model.aiLevel) { level in
                model.newGame(aiLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .alert("動かせません", isPresented: $showPassAlert) {
            Button("OK") { model.confirmPass() }
        } message: {
            Text("この目で動かせる駒がありません。CPU の番になります。")
        }
        .boardResignConfirmation(isPresented: $showResignConfirm) { model.resign() }
        // パスの案内は **`mustPass` ではなく手番の鍵（`aiTurnKey`）の変化で出す**。CPU がパスした直後に
        // 自分もパスになると、`confirmPass()` → `beginTurn()` が同期で続いて `mustPass` は true → true のまま
        // 変化せず、`onChange(of: mustPass)` では案内が出ずに操作不能になる（verifier 指摘・PR #1344。
        // 400 局の自動対局で 6 回）。手番の鍵は `beginTurn` のたびに必ず進む。
        // `initial: true` が要る（#414）。案内を閉じる前に中断すると `mustPass = true` のまま保存され、
        // 復元後は値が変化しないので 2 引数版 `onChange` は既定では発火しない。
        .onChange(of: model.aiTurnKey, initial: true) { _, _ in
            if model.mustPass && !model.isAITurn { showPassAlert = true }
        }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        .task {
            #if DEBUG
            // 撮影・動作確認用: `-backgammonScenario hit|bar|bearoff|result` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-backgammonScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if model.gameOver {
                    Text("終局")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.fillMuted))
                } else {
                    let isMine = !model.isAITurn
                    Text(isMine ? "あなたの番" : "CPUの番")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(isMine ? Theme.Fill.teal : Theme.Fill.coral))
                    if model.isThinking {
                        ProgressView().controlSize(.small)
                    }
                }

                Spacer()

                diceRow

                Spacer()

                // ピップカウント（あがるまでに要る目の合計）。
                VStack(alignment: .trailing, spacing: 0) {
                    Text("あなた \(model.humanPips)")
                    Text("CPU \(model.cpuPips)")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSub)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("ピップカウント、あなた\(model.humanPips)、CPU\(model.cpuPips)")
            }
            Text(statusMessage)
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 1 行の案内。高さが変わらないよう常に 1 行を出す（無いときは空白 1 文字）。
    private var statusMessage: String {
        if model.gameOver { return " " }
        if model.mustPass { return model.isAITurn ? "CPU は動かせる駒がありません" : "動かせる駒がありません" }
        if model.isAITurn {
            if model.turnID == 1, let o = model.openingRoll { return "先手は CPU（オープニングロール CPU \(o.cpu) – あなた \(o.human)）" }
            return "CPU が考えています…"
        }
        if model.selectedPoint != nil { return "行き先をタップ（同じ駒をもう一度タップで選び直し）" }
        if model.turnID == 1, let o = model.openingRoll { return "先手はあなた（オープニングロール あなた \(o.human) – CPU \(o.cpu)）" }
        return "動かす駒をタップ"
    }

    /// 振った目。使った目は薄くする。
    private var diceRow: some View {
        let used = BackgammonDiceLayout.usedFlags(dice: model.dice, remaining: model.remainingDice)
        return HStack(spacing: 4) {
            ForEach(Array(model.dice.enumerated()), id: \.offset) { i, value in
                BackgammonDieFace(value: value, isUsed: used.indices.contains(i) && used[i])
                    .frame(width: model.dice.count == 4 ? 22 : 28, height: model.dice.count == 4 ? 22 : 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BackgammonAccessibility.diceLabel(dice: model.dice, remaining: model.remainingDice))
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let layout = BackgammonBoardLayout(width: geo.size.width)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: BackgammonBoardStyle.frame), Color(hex: BackgammonBoardStyle.frameDeep)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                BackgammonBoardCanvas(
                    board: model.board,
                    layout: layout,
                    movable: model.isAITurn ? [] : model.movableSources,
                    selected: model.selectedPoint,
                    destinations: Set(model.destinations.map(\.to)),
                    lastMove: model.lastMove
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { val in
                            guard !model.isAITurn, !model.gameOver, !model.mustPass else { return }
                            if let point = layout.point(at: val.location) { model.tap(point) }
                        }
                )
                .accessibilityRepresentation { accessibilityGrid }
            }
        }
        .aspectRatio(BackgammonBoardLayout.aspectRatio, contentMode: .fit)
    }

    /// VoiceOver 用のポイント一覧（#188）。描画も当たり判定もされず、支援技術にだけ見せる。
    private var accessibilityGrid: some View {
        let movable = model.isAITurn ? Set<Int>() : model.movableSources
        let destinations = Set(model.destinations.map(\.to))
        let disabled = model.gameOver || model.isAITurn || model.mustPass
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array((12..<24)), id: \.self) { index in pointButton(index, movable: movable, destinations: destinations, disabled: disabled) }
            }
            HStack(spacing: 0) {
                Button { model.tap(BackgammonBoard.bar) } label: { Color.clear.frame(width: 44, height: 44) }
                    .disabled(disabled)
                    .accessibilityLabel(BackgammonAccessibility.barLabel(
                        humanCount: model.board.bar(for: .white), cpuCount: model.board.bar(for: .black),
                        isMovable: movable.contains(BackgammonBoard.bar), isSelected: model.selectedPoint == BackgammonBoard.bar))
                Button { model.tap(BackgammonBoard.off) } label: { Color.clear.frame(width: 44, height: 44) }
                    .disabled(disabled)
                    .accessibilityLabel(BackgammonAccessibility.offLabel(
                        humanCount: model.board.off(for: .white), cpuCount: model.board.off(for: .black),
                        isDestination: destinations.contains(BackgammonBoard.off)))
            }
            HStack(spacing: 0) {
                ForEach(Array((0..<12).reversed()), id: \.self) { index in pointButton(index, movable: movable, destinations: destinations, disabled: disabled) }
            }
        }
    }

    private func pointButton(_ index: Int, movable: Set<Int>, destinations: Set<Int>, disabled: Bool) -> some View {
        Button { model.tap(index) } label: { Color.clear.frame(width: 28, height: 44) }
            .disabled(disabled)
            .accessibilityLabel(BackgammonAccessibility.pointLabel(
                index: index, owner: model.board.owner(at: index), count: model.board.count(at: index),
                isMovable: movable.contains(index), isSelected: model.selectedPoint == index,
                isDestination: destinations.contains(index)))
    }

    // MARK: - Controls

    private var gameControls: some View {
        HStack(spacing: 8) {
            // 3 つとも 44pt の共通カプセル（#711・#828）。投了の確認ダイアログは画面全体に付けている。
            BoardResignButton(look: .tapTargetCapsule) { showResignConfirm = true }
            Spacer(minLength: 0)
            Button { model.restartTurn() } label: {
                Label("やり直し", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(BoardGameControlCapsuleStyle(fill: Theme.Fill.yellow))
            .disabled(!model.canRestartTurn)
            .accessibilityHint("この手番で動かした駒を、サイコロを振った直後に戻します")
            Spacer(minLength: 0)
            BoardUndoButton(model: model, services: services, rescue: undoRescue, usesTapTargetCapsule: true)
        }
        .themeBody(14)
        .padding(.horizontal, 12).padding(.vertical, BoardGameControlMetrics.rowVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 12) {
                let isWin = model.winner == model.humanSide
                Image(systemName: isWin ? "trophy.fill" : "flag.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(isWin ? Theme.yellow : Theme.coral)
                Text(isWin ? "あなたの勝ち！" : "CPUの勝ち")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(isWin ? Theme.teal : Theme.coral)
                if let kind = model.winKind, kind != .single {
                    Text("\(kind.label)（\(kind.rawValue)点）")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                }
                Text("あがり あなた \(model.board.off(for: .white)) – CPU \(model.board.off(for: .black))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSub)
                RecordLabel(model.recordResult)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }

    /// 対局中（投了・やり直し・待った）と終局後（もう一度・レコメンド）で中身が入れ替わるが、
    /// 高さは常に終局後の最大構成に揃える（#148。高さの担保は `GameControlArea`）。
    private var controlArea: some View {
        GameControlArea(isFinished: model.gameOver, services: services, ladder: ladder) {
            newGameButton
        } playing: {
            gameControls
        }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.newGame(aiLevel: CPUStrength.level(atLadderIndex: index))
        }
    }

    private var newGameButton: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button { showNewGame = true } label: {
                Label("もう一度", systemImage: "arrow.clockwise")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
            Spacer(minLength: 0)
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 盤の寸法

/// 盤の座標系。幅を 13.6 単位（ポイント 12 + バー 0.7 + あがり置き場 0.9）に割り、駒の直径をほぼ 1 単位にする。
///
/// View の `static let` は MainActor に隔離されるので、テストから参照できるよう View の外に置く。
public struct BackgammonBoardLayout: Sendable {
    public static let barWidth: CGFloat = 0.7
    public static let trayWidth: CGFloat = 0.9
    /// 左右端の余白（単位）。盤は角丸で切り抜くので、端の列の駒が角に掛からないぶんを空ける。
    public static let sideInset: CGFloat = 0.4
    /// 上下端の余白（単位）。同じく角丸に駒が掛からないぶん。
    public static let verticalInset: CGFloat = 0.25
    public static let unitsWide: CGFloat = 12 + barWidth + trayWidth + sideInset * 2
    public static let unitsTall: CGFloat = 10.4 + verticalInset * 2
    public static let aspectRatio: CGFloat = unitsWide / unitsTall
    /// 三角の高さ（単位）。上下で 2 本ぶんの間に 1 単位以上の隙間が残る。
    public static let pointHeight: CGFloat = 4.6
    /// 1 列に描く駒の上限。超えたぶんは数字で示す。
    public static let maxDrawn = 5

    public let width: CGFloat
    public var unit: CGFloat { width / Self.unitsWide }
    public var height: CGFloat { unit * Self.unitsTall }
    public var checkerDiameter: CGFloat { unit * 0.92 }

    public init(width: CGFloat) { self.width = width }

    /// 列（0〜11。左から）の左端 x。
    public func columnX(_ column: Int) -> CGFloat {
        let inner = column < 6 ? CGFloat(column) : 6 + Self.barWidth + CGFloat(column - 6)
        return (Self.sideInset + inner) * unit
    }

    /// ポイントの添字 → 列と上下。下段は右から 1〜12、上段は左から 13〜24。
    public func position(of index: Int) -> (column: Int, isTop: Bool) {
        index < 12 ? (11 - index, false) : (index - 12, true)
    }

    /// 列の中心 x。
    public func centerX(of index: Int) -> CGFloat { columnX(position(of: index).column) + unit / 2 }

    public var barMinX: CGFloat { (Self.sideInset + 6) * unit }
    public var barMaxX: CGFloat { (Self.sideInset + 6 + Self.barWidth) * unit }
    public var trayMinX: CGFloat { (Self.sideInset + 12 + Self.barWidth) * unit }
    public var trayMaxX: CGFloat { trayMinX + Self.trayWidth * unit }
    /// 三角の付け根の y（上段は上端の余白の下、下段は下端の余白の上）。
    public var topBaseY: CGFloat { Self.verticalInset * unit }
    public var bottomBaseY: CGFloat { height - Self.verticalInset * unit }

    /// `k` 番目（0 始まり）の駒の中心 y。
    public func checkerCenterY(k: Int, isTop: Bool) -> CGFloat {
        let d = checkerDiameter
        return isTop ? topBaseY + d * (CGFloat(k) + 0.5) : bottomBaseY - d * (CGFloat(k) + 0.5)
    }

    /// タップ位置 → ポイントの添字・バー・あがり。盤の外なら nil。
    public func point(at location: CGPoint) -> Int? {
        guard location.x >= 0, location.x <= width, location.y >= 0, location.y <= height else { return nil }
        if location.x >= trayMinX { return BackgammonBoard.off }
        if location.x >= barMinX && location.x < barMaxX { return BackgammonBoard.bar }
        let isTop = location.y < height / 2
        let column: Int
        if location.x < barMinX {
            column = max(0, min(5, Int((location.x - Self.sideInset * unit) / unit)))
        } else {
            column = 6 + min(5, Int((location.x - barMaxX) / unit))
        }
        return isTop ? 12 + column : 11 - column
    }
}

/// 盤・駒の色。`Color` は成分を取り出せないので数値で持つ（`Theme.Hex` と同じ理由）。
public enum BackgammonBoardStyle {
    public static let frame: UInt32 = 0x8A5A3C
    public static let frameDeep: UInt32 = 0x6E4630
    public static let field: UInt32 = 0xEBD9BC
    public static let pointDark: UInt32 = 0xB07A4E
    public static let pointLight: UInt32 = 0xF4E6CC
    public static let whiteFace: UInt32 = 0xF4EFE2
    public static let whiteSide: UInt32 = 0xC9BFA8
    public static let blackFace: UInt32 = 0x2B2624
    public static let blackSide: UInt32 = 0x0F0D0C
    /// 動かせる駒・行き先の印（オセロの合法手ドットと同じ系統）。
    public static let hint: UInt32 = Theme.Hex.teal
    public static let selected: UInt32 = Theme.Hex.yellow
}

/// サイコロの並びの補助（表示用の純関数）。
public enum BackgammonDiceLayout {
    /// 各目を使ったか。残りは**後ろから**照合するので、ゾロ目では先頭から順に薄くなる。
    public static func usedFlags(dice: [Int], remaining: [Int]) -> [Bool] {
        var rest = remaining
        var flags = Array(repeating: true, count: dice.count)
        for i in dice.indices.reversed() {
            if let j = rest.firstIndex(of: dice[i]) {
                rest.remove(at: j)
                flags[i] = false
            }
        }
        return flags
    }

    /// 目 1〜6 の点の位置（0〜1 の座標）。
    public static func pips(_ value: Int) -> [CGPoint] {
        let l: CGFloat = 0.25, c: CGFloat = 0.5, r: CGFloat = 0.75
        switch value {
        case 1: return [CGPoint(x: c, y: c)]
        case 2: return [CGPoint(x: l, y: l), CGPoint(x: r, y: r)]
        case 3: return [CGPoint(x: l, y: l), CGPoint(x: c, y: c), CGPoint(x: r, y: r)]
        case 4: return [CGPoint(x: l, y: l), CGPoint(x: r, y: l), CGPoint(x: l, y: r), CGPoint(x: r, y: r)]
        case 5: return [CGPoint(x: l, y: l), CGPoint(x: r, y: l), CGPoint(x: c, y: c), CGPoint(x: l, y: r), CGPoint(x: r, y: r)]
        case 6: return [CGPoint(x: l, y: l), CGPoint(x: r, y: l), CGPoint(x: l, y: c), CGPoint(x: r, y: c), CGPoint(x: l, y: r), CGPoint(x: r, y: r)]
        default: return []
        }
    }
}

/// サイコロ 1 個。
struct BackgammonDieFace: View {
    let value: Int
    let isUsed: Bool

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                        .stroke(Color.black.opacity(0.25), lineWidth: 1))
                ForEach(Array(BackgammonDiceLayout.pips(value).enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(Color(hex: 0x2B2624))
                        .frame(width: s * 0.18, height: s * 0.18)
                        .position(x: p.x * s, y: p.y * s)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(isUsed ? 0.3 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Board Canvas

/// 盤（三角・バー・あがり置き場・駒・印）の描画。
private struct BackgammonBoardCanvas: View {
    let board: BackgammonBoard
    let layout: BackgammonBoardLayout
    let movable: Set<Int>
    let selected: Int?
    let destinations: Set<Int>
    let lastMove: BackgammonMove?

    var body: some View {
        Canvas { ctx, _ in
            let u = layout.unit
            let h = layout.height
            let d = layout.checkerDiameter

            // 盤面（三角の下地）。左右の 6 列ずつ。
            let fieldColor = Color(hex: BackgammonBoardStyle.field)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: layout.barMinX, height: h)), with: .color(fieldColor))
            ctx.fill(Path(CGRect(x: layout.barMaxX, y: 0, width: layout.trayMinX - layout.barMaxX, height: h)), with: .color(fieldColor))

            // 三角。上段は 13〜24（左から）、下段は 1〜12（右から）。色は隣り合う列で交互。
            for index in 0..<BackgammonBoard.pointCount {
                let (column, isTop) = layout.position(of: index)
                let x0 = layout.columnX(column)
                var path = Path()
                let baseY = isTop ? layout.topBaseY : layout.bottomBaseY
                let tipY = isTop ? baseY + BackgammonBoardLayout.pointHeight * u : baseY - BackgammonBoardLayout.pointHeight * u
                path.move(to: CGPoint(x: x0 + u * 0.04, y: baseY))
                path.addLine(to: CGPoint(x: x0 + u * 0.96, y: baseY))
                path.addLine(to: CGPoint(x: x0 + u / 2, y: tipY))
                path.closeSubpath()
                let dark = (index % 2 == 0)
                var color = Color(hex: dark ? BackgammonBoardStyle.pointDark : BackgammonBoardStyle.pointLight)
                if destinations.contains(index) { color = Color(hex: BackgammonBoardStyle.hint).opacity(0.55) }
                else if selected == index { color = Color(hex: BackgammonBoardStyle.selected).opacity(0.75) }
                ctx.fill(path, with: .color(color))
            }

            // バーとあがり置き場は枠と同じ濃い木目。
            ctx.fill(Path(CGRect(x: layout.barMinX, y: 0, width: layout.barMaxX - layout.barMinX, height: h)),
                     with: .color(Color(hex: BackgammonBoardStyle.frameDeep).opacity(0.9)))
            let trayRect = CGRect(x: layout.trayMinX, y: 0, width: layout.width - layout.trayMinX, height: h)
            ctx.fill(Path(trayRect), with: .color(Color(hex: BackgammonBoardStyle.frameDeep).opacity(0.9)))
            if destinations.contains(BackgammonBoard.off) {
                ctx.fill(Path(CGRect(x: layout.trayMinX, y: h / 2 + u * 0.1, width: layout.width - layout.trayMinX, height: h / 2 - u * 0.1)),
                         with: .color(Color(hex: BackgammonBoardStyle.hint).opacity(0.5)))
            }
            if selected == BackgammonBoard.bar {
                ctx.fill(Path(CGRect(x: layout.barMinX, y: h / 2, width: layout.barMaxX - layout.barMinX, height: h / 2)),
                         with: .color(Color(hex: BackgammonBoardStyle.selected).opacity(0.6)))
            }

            // 動かせる駒の印（三角の付け根の小さな点）。
            for index in movable where index < BackgammonBoard.pointCount && selected == nil {
                let (_, isTop) = layout.position(of: index)
                let cx = layout.centerX(of: index)
                let cy = isTop ? layout.topBaseY + BackgammonBoardLayout.pointHeight * u + u * 0.3
                               : layout.bottomBaseY - BackgammonBoardLayout.pointHeight * u - u * 0.3
                let r = u * 0.12
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(hex: BackgammonBoardStyle.hint)))
            }
            if movable.contains(BackgammonBoard.bar), selected == nil {
                // バーの駒は中央から下へ積むので、その下に置く（駒の下に隠れないように）。
                let cx = (layout.barMinX + layout.barMaxX) / 2
                let drawn = CGFloat(min(board.bar(for: .white), 3))
                let cy = h / 2 + d * (drawn + 0.6)
                let r = u * 0.12
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(hex: BackgammonBoardStyle.hint)))
            }

            // 駒。
            func drawChecker(center: CGPoint, side: BackgammonSide, label: String?, highlighted: Bool) {
                let r = d / 2
                let rim = r * 0.16
                let face = CGRect(x: center.x - r, y: center.y - r - rim / 2, width: d, height: d)
                let sideRect = face.offsetBy(dx: 0, dy: rim)
                ctx.fill(Path(ellipseIn: sideRect),
                         with: .color(Color(hex: side == .white ? BackgammonBoardStyle.whiteSide : BackgammonBoardStyle.blackSide)))
                ctx.fill(Path(ellipseIn: face),
                         with: .color(Color(hex: side == .white ? BackgammonBoardStyle.whiteFace : BackgammonBoardStyle.blackFace)))
                ctx.stroke(Path(ellipseIn: face), with: .color(.black.opacity(side == .white ? 0.25 : 0.6)), lineWidth: 1)
                if highlighted {
                    ctx.stroke(Path(ellipseIn: face.insetBy(dx: -1.5, dy: -1.5)),
                               with: .color(Color(hex: BackgammonBoardStyle.selected)), lineWidth: 2.5)
                }
                if let label {
                    ctx.draw(Text(label).font(.system(size: d * 0.5, weight: .bold, design: .rounded))
                        .foregroundColor(side == .white ? Color(hex: 0x2B2624) : .white),
                             at: CGPoint(x: face.midX, y: face.midY))
                }
            }

            for index in 0..<BackgammonBoard.pointCount {
                guard let owner = board.owner(at: index) else { continue }
                let count = board.count(at: index)
                let (_, isTop) = layout.position(of: index)
                let cx = layout.centerX(of: index)
                let drawn = min(count, BackgammonBoardLayout.maxDrawn)
                for k in 0..<drawn {
                    let isLast = k == drawn - 1
                    drawChecker(center: CGPoint(x: cx, y: layout.checkerCenterY(k: k, isTop: isTop)), side: owner,
                                label: isLast && count > drawn ? "\(count)" : nil,
                                highlighted: isLast && (selected == index || lastMove?.to == index))
                }
            }
            // バーの駒（白は下半分・黒は上半分に、中央から外へ積む）。
            let barX = (layout.barMinX + layout.barMaxX) / 2
            for side in BackgammonSide.allCases {
                let count = board.bar(for: side)
                guard count > 0 else { continue }
                let drawn = min(count, 3)
                for k in 0..<drawn {
                    let y = side == .white ? h / 2 + d * (CGFloat(k) + 0.6) : h / 2 - d * (CGFloat(k) + 0.6)
                    drawChecker(center: CGPoint(x: barX, y: y), side: side,
                                label: k == drawn - 1 && count > drawn ? "\(count)" : nil,
                                highlighted: k == drawn - 1 && side == .white && selected == BackgammonBoard.bar)
                }
            }
            // あがった駒（薄い板を積む）。白は下から、黒は上から。
            let trayInset = u * 0.12
            let plank = d * 0.28
            for side in BackgammonSide.allCases {
                let count = board.off(for: side)
                for k in 0..<count {
                    let y = side == .white ? h - trayInset - plank * CGFloat(k + 1) : trayInset + plank * CGFloat(k)
                    let rect = CGRect(x: layout.trayMinX + trayInset, y: y,
                                      width: layout.width - layout.trayMinX - 2 * trayInset, height: plank - 1)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(Color(hex: side == .white ? BackgammonBoardStyle.whiteFace : BackgammonBoardStyle.blackFace)))
                }
            }
        }
    }
}

// MARK: - New Game Sheet

struct BackgammonNewGameSheet: View {
    @State private var level: Int
    let onStart: (Int) -> Void
    let onCancel: () -> Void

    init(aiLevel: Int, onStart: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        _level = State(initialValue: aiLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onStart: { onStart(level) }, onCancel: onCancel
        ) {
            GameSetupSection("CPUの強さ") {
                // 説明は `BackgammonEngine.bestSequence` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    "でたらめに動かす", "ピップ差と叩きだけ", "ブロットの危険まで見る", "相手の目まで読む",
                ])
            }
        }
    }
}
