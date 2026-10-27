import SwiftUI
import Core

public struct YonmokuView: View {
    @State private var model: YonmokuModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()
    /// 結果カードを閉じたか（#1753）。新しい対局が始まる（`gameOver` が偽に戻る）とリセットする。
    @State private var resultCardClosed = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: YonmokuModel(services: services))
        // 続きが無ければ開始シート（先手・後手と強さ）から始める（五目並べ・オセロと同じ）。
        _showNewGame = State(initialValue: !services.snapshots.exists(for: YonmokuModel.gameID))
    }

    public var body: some View {
        VStack(spacing: 6) {
            statusBar
            Spacer(minLength: 0)
            board
                .padding(.horizontal, -Theme.pad / 2)
                .layoutPriority(1)
                .boardGameResultCard(isPresented: model.gameOver && !resultCardClosed) { resultCard }
            Spacer(minLength: 0)
            playersRow
            controlArea
            HowToPlayHint(.yonmoku, playLog: services.playLog)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
        .onChange(of: model.gameOver) { _, over in
            if !over { resultCardClosed = false }
        }
        .padding(Theme.pad)
        .gameChrome(title: tr("四目並べ"), review: services.review,
                    newGame: GameChromeNewGame(.match) {
                        if model.hasProgressToLose {
                            showConfirmNewGame = true
                        } else {
                            showNewGame = true
                        }
                    })
        .howToPlay(HowToPlayGuide.yonmoku.illustrated(YonmokuHowToFigures.items)) { YonmokuRuleSheet() }
        .sheet(isPresented: $showNewGame, onDismiss: { model.startPlayIfPending() }) {
            YonmokuNewGameSheet(humanSide: model.humanSide, aiLevel: model.aiLevel) { side, level in
                model.newGame(humanSide: side, aiLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規対局しますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規対局"), role: .destructive) { showNewGame = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると対局データが失われます。"))
            }
        }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        // CPU の着手を読み上げる（#2280）。
        .cpuMoveAnnouncement(key: model.aiTurnKey, cpuMoveKey: model.lastCPUMoveKey) {
            model.lastMove.map { YonmokuAccessibility.cpuMoveAnnouncement(col: $0.col, row: $0.row) }
        }
        .task {
            #if DEBUG
            // 撮影・動作確認用: `-yonmokuScenario midgame|threat` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-yonmokuScenario"), i + 1 < args.count {
                showNewGame = false
                model.applyDebugScenario(args[i + 1])
            }
            #endif
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        GameStatusBar {
            if let w = model.winner {
                Label(w == model.humanSide ? tr("あなたの勝ち！") : tr("CPUの勝ち"),
                      systemImage: "flag.checkered")
                    .themeBody(16).foregroundStyle(Theme.coralText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if model.isDraw {
                Label(tr("引き分け"), systemImage: "equal.circle")
                    .themeBody(16).foregroundStyle(Theme.inkSubText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                TurnBadge(isYourTurn: !model.isAITurn)
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text(tr("思考中…")).themeBody(13).foregroundStyle(Theme.inkSubText)
                }
            }
        } trailing: {
            if model.gameOver {
                RecordLabel(model.recordResult)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(tr("%lld手", model.moveCount)).themeBody(13).foregroundStyle(Theme.inkSubText)
        }
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let layout = YonmokuBoardLayout(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: YonmokuBoardStyle.frame))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

                // 穴
                ForEach(0..<YonmokuBoard.columns, id: \.self) { col in
                    ForEach(0..<YonmokuBoard.rows, id: \.self) { row in
                        Circle()
                            .fill(RadialGradient(colors: [Color(hex: YonmokuBoardStyle.holeDeep), Color(hex: YonmokuBoardStyle.hole)],
                                                 center: .center, startRadius: 0, endRadius: layout.cell / 2))
                            .frame(width: layout.disc, height: layout.disc)
                            .position(layout.center(col: col, row: row))
                    }
                }

                // 石（直前の手は上から落ちてくる）
                ForEach(discPoints, id: \.self) { point in
                    if let disc = model.board[point.col, point.row] {
                        YonmokuDiscView(disc: disc, size: layout.disc,
                                        isLast: model.lastMove == point)
                            .position(layout.center(col: point.col, row: point.row))
                            .transition(.asymmetric(
                                insertion: .offset(y: -layout.dropDistance(row: point.row)),
                                removal: .opacity))
                    }
                }
                .gameAnimation(.easeIn(duration: YonmokuMotion.dropDuration), value: model.moveCount)

                // 決着した 4 つを光らせる（五目並べ #665 と同じ印）。
                if let line = model.winningLine, let first = line.first, let last = line.last {
                    ZStack {
                        Path { path in
                            path.move(to: layout.center(col: first.col, row: first.row))
                            path.addLine(to: layout.center(col: last.col, row: last.row))
                        }
                        .stroke(Theme.coral.opacity(0.75), style: StrokeStyle(lineWidth: layout.cell * 0.16, lineCap: .round))
                        ForEach(line, id: \.self) { point in
                            Circle()
                                .stroke(Theme.coral, lineWidth: 3)
                                .frame(width: layout.disc + 6, height: layout.disc + 6)
                                .position(layout.center(col: point.col, row: point.row))
                        }
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                // 列ごとのタップ領域（幅 = 1 列ぶん・高さ = 盤全体。44pt 以上）。
                HStack(spacing: 0) {
                    ForEach(0..<YonmokuBoard.columns, id: \.self) { col in
                        Button { model.tap(column: col) } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: layout.cell, height: geo.size.height)
                        .disabled(model.gameOver)
                        .accessibilityLabel(columnLabel(col))
                        .accessibilityHint(model.playableColumns.contains(col) ? tr("ダブルタップで石を入れます") : "")
                    }
                }
                .padding(.horizontal, layout.inset)
            }
            .gameAnimation(.easeOut(duration: 0.25), value: model.winningLine)
            .modifier(YonmokuShake(animatableData: CGFloat(model.rejectedTapCount)))
            .gameAnimation(.linear(duration: 0.32), value: model.rejectedTapCount)
        }
        .aspectRatio(YonmokuBoardLayout.aspectRatio, contentMode: .fit)
    }

    /// 石のあるマス（ForEach の id に使う）。
    private var discPoints: [YonmokuPoint] {
        var points: [YonmokuPoint] = []
        for col in 0..<YonmokuBoard.columns {
            for row in 0..<model.board.height(of: col) { points.append(YonmokuPoint(col: col, row: row)) }
        }
        return points
    }

    private func columnLabel(_ col: Int) -> String {
        let discs = (0..<model.board.height(of: col)).compactMap { model.board[col, $0] }
        return YonmokuAccessibility.columnLabel(col: col, discs: discs, isLastMove: model.lastMove?.col == col)
    }

    // MARK: - Players Row

    /// 「あなた／CPU」の石の色を 1 行で示す（五目並べ #1663 と同じ作り）。
    private var playersRow: some View {
        HStack(spacing: 8) {
            playerChip(disc: model.humanSide, isYou: true)
            Spacer(minLength: 0)
            playerChip(disc: model.humanSide.opponent, isYou: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 30)
        .padding(.horizontal, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    private func playerChip(disc: YonmokuDisc, isYou: Bool) -> some View {
        HStack(spacing: 6) {
            YonmokuDiscView(disc: disc, size: 18, isLast: false)
            Text(isYou ? tr("あなた") : "CPU")
                .themeCaption(13, weight: .bold, maxScale: 1.5)
                .foregroundStyle(isYou ? Theme.tealText : Theme.inkSubText)
            Text(disc == .black ? tr("黒・先手") : tr("白・後手"))
                .themeCaption(13, weight: .regular, maxScale: 1.5)
                .foregroundStyle(Theme.inkSubText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: - 結果

    /// 終局の結果カード（盤ゲーム共通・#1753）。
    @ViewBuilder
    private var resultCard: some View {
        if model.gameOver {
            let verdict: BoardGameResultCard.Verdict = model.isDraw ? .draw
                : (model.winner == model.humanSide ? .win : .loss)
            BoardGameResultCard(
                verdict: verdict,
                reason: model.isDraw ? tr("盤が埋まった") : (model.winningLine != nil ? tr("4 つ並んだ") : tr("投了")),
                record: model.recordResult
            ) { resultCardClosed = true }
        }
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（待った・投了）と終局後（もう一回・レコメンド）で中身が入れ替わるが、
    /// 高さは常に終局後の最大構成に揃える（#148。高さの担保は `GameControlArea`）。
    private var controlArea: some View {
        GameControlArea(isFinished: model.gameOver, services: services, ladder: ladder) {
            GameReplayBar(
                onReplay: { model.newGame(humanSide: model.humanSide, aiLevel: model.aiLevel) },
                onChangeSettings: { showNewGame = true }
            )
        } playing: {
            // 待った・「⋯」（投了）の並びは盤ゲームで共通（#1421）。
            BoardGameControlBar(model: model, services: services, rescue: undoRescue,
                                onResign: { model.resign() })
        }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.newGame(humanSide: model.humanSide, aiLevel: CPUStrength.level(atLadderIndex: index))
        }
    }
}

// MARK: - 盤の寸法・色・演出

/// 盤の寸法。幅を「7 列 + 左右の縁」で割る。
///
/// View の `static let` は MainActor に隔離されるので、テストから参照できるよう View の外に置く。
public struct YonmokuBoardLayout: Sendable {
    /// 縁の幅（1 マスに対する割合）。
    public static let insetRatio: CGFloat = 0.3
    /// 石の直径（1 マスに対する割合）。
    public static let discRatio: CGFloat = 0.84
    /// 盤の縦横比（横 7 マス + 縁 ÷ 縦 6 マス + 縁）。
    public static let aspectRatio: CGFloat =
        (CGFloat(YonmokuBoard.columns) + insetRatio * 2) / (CGFloat(YonmokuBoard.rows) + insetRatio * 2)

    public let width: CGFloat

    public init(width: CGFloat) { self.width = width }

    /// 1 マス（= 列のタップ領域の幅）。GeometryReader の最初の 0 幅でも割り算は落ちない。
    public var cell: CGFloat { max(width, 0) / (CGFloat(YonmokuBoard.columns) + Self.insetRatio * 2) }
    public var inset: CGFloat { cell * Self.insetRatio }
    public var disc: CGFloat { cell * Self.discRatio }

    /// マスの中心。`row` は下から数える。
    public func center(col: Int, row: Int) -> CGPoint {
        CGPoint(x: inset + (CGFloat(col) + 0.5) * cell,
                y: inset + (CGFloat(YonmokuBoard.rows - 1 - row) + 0.5) * cell)
    }

    /// 盤の上端の外から、その段まで落ちる距離。
    public func dropDistance(row: Int) -> CGFloat {
        center(col: 0, row: row).y + cell
    }
}

/// 盤の色。木地は五目並べの盤と同じ。
enum YonmokuBoardStyle {
    static let frame: UInt32 = 0xDEB568
    static let hole: UInt32 = 0xB08436
    static let holeDeep: UInt32 = 0x7A5810
}

enum YonmokuMotion {
    /// 石が上から落ちきるまでの時間。
    static let dropDuration: TimeInterval = 0.28
}

/// 盤の石（五目並べの碁石と同じ、左上に照りのあるドーム）。直前の手には同じ印（輪と中央の点）を付ける。
struct YonmokuDiscView: View {
    let disc: YonmokuDisc
    let size: CGFloat
    let isLast: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: disc == .black ? [Color(hex: 0x55504A), Color(hex: 0x0F0C08)]
                                           : [Color(hex: 0xFFFCF0), Color(hex: 0xD9D2B8)],
                    center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.85))
                .overlay(Circle().stroke(Color.gray.opacity(disc == .white ? 0.4 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: size * 0.04, y: size * 0.035)
            if isLast {
                Circle().stroke(Theme.coral, lineWidth: 2.4).padding(-2)
                Circle()
                    .fill(disc == .black ? Color.white.opacity(0.9) : Color(hex: 0x2A1600).opacity(0.75))
                    .frame(width: size * 0.3, height: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 入らない列・CPU の番のタップを伝える盤の横揺れ（五目並べ #202 と同じ）。
/// Reduce Motion が ON のときは `.gameAnimation` が補間を落とすので揺れない（触覚は Model から鳴る）。
private struct YonmokuShake: GeometryEffect {
    var amount: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * 2 * shakes), y: 0)
        )
    }
}

// MARK: - くわしいルール

struct YonmokuRuleSheet: View {
    static var rules: [(String, String)] {
        [
            (tr("盤"), tr("横 7 列 × 縦 6 段の立てた盤を使います。黒が先手、白が後手です。")),
            (tr("打ち方"), tr("列を 1 つ選ぶと、石が上から落ちて、その列の一番下の空いた段に入ります。いっぱいの列には入れられません。")),
            (tr("勝ち"), tr("たて・よこ・ななめのどれかで、自分の石を先に 4 つ並べたほうの勝ちです。")),
            (tr("引き分け"), tr("どちらも 4 つ並べないまま 42 マスがすべて埋まったら引き分けです。")),
        ]
    }

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}

// MARK: - New Game Sheet

struct YonmokuNewGameSheet: View {
    @State private var side: YonmokuDisc
    @State private var level: Int
    let onStart: (YonmokuDisc, Int) -> Void
    let onCancel: () -> Void

    init(humanSide: YonmokuDisc, aiLevel: Int,
         onStart: @escaping (YonmokuDisc, Int) -> Void,
         onCancel: @escaping () -> Void) {
        _side = State(initialValue: humanSide)
        _level = State(initialValue: aiLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onStart: { onStart(side, level) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("あなたの石")) {
                HStack(spacing: 12) {
                    GameSetupChooser(title: tr("●黒"), subtitle: tr("先手"),
                                     selected: side == .black, accent: Theme.fillStrong,
                                     onAccent: .white) { side = .black }
                    GameSetupChooser(title: tr("○白"), subtitle: tr("後手"),
                                     selected: side == .white, accent: Theme.fillMuted,
                                     onAccent: .white) { side = .white }
                }
            }
            GameSetupSection(tr("CPUの強さ")) {
                // 説明は `YonmokuEngine` の段階表と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    tr("見のがしが多い"), tr("1手先だけ見る"), tr("3手先まで読む"), tr("最後まで深く読む"),
                ])
            }
            // 遊び方の要点を図つきで並べる（五目並べと同じ・#2044・#2268）。
            GameSetupSection(tr("ルールの要点")) {
                let guide = HowToPlayGuide.yonmoku.illustrated(YonmokuHowToFigures.items)
                VStack(spacing: 10) {
                    ForEach(Array(guide.items.enumerated()), id: \.offset) { _, item in
                        HowToPlayItemCard(item)
                    }
                    if !guide.notes.isEmpty { HowToPlayNotesCard(guide.notes) }
                }
            }
        }
    }
}
