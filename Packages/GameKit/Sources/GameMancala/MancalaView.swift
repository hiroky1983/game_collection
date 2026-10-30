import SwiftUI
import Core

public struct MancalaView: View {
    @State private var model: MancalaModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showConfirmNewGame = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()
    /// 結果カードを閉じたか（#3059）。新しい対局が始まる（`gameOver` が偽に戻る）とリセットする。
    @State private var resultCardClosed = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: MancalaModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            Spacer(minLength: 0)
            board
                .layoutPriority(1)
                .boardGameResultCard(isPresented: model.gameOver && !resultCardClosed) { resultCard }
            Text(statusMessage)
                .themeBody(14, weight: .semibold)
                .foregroundStyle(Theme.inkSubText)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            controlArea
            HowToPlayHint(.mancala, playLog: services.playLog)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
        .onChange(of: model.gameOver) { _, over in
            if !over { resultCardClosed = false }
        }
        .padding(Theme.pad)
        .gameChrome(title: tr("マンカラ"), review: services.review,
                    newGame: GameChromeNewGame(.match) {
                        if model.hasProgressToLose {
                            showConfirmNewGame = true
                        } else {
                            showNewGame = true
                        }
                    })
        .howToPlay(HowToPlayGuide.mancala.illustrated(MancalaHowToFigures.items)) { MancalaRuleSheet() }
        .sheet(isPresented: $showNewGame) {
            MancalaNewGameSheet(humanFirst: model.humanFirst, aiLevel: model.aiLevel) { first, level in
                model.newGame(humanFirst: first, aiLevel: level)
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
        // CPU の着手（どの穴か・ストア入り・連続手番）を読み上げる（#3062）。
        .cpuMoveAnnouncement(key: model.aiTurnKey, cpuMoveKey: model.lastCPUMoveKey) {
            model.lastMove.map { MancalaAccessibility.cpuMoveAnnouncement(pitSlot: $0.pitSlot, event: model.lastEvent) }
        }
        .task {
            #if DEBUG
            // 撮影・動作確認用: `-mancalaScenario capture|endgame` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-mancalaScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        GameStatusBar {
            if model.gameOver {
                TurnBadge(tr("終局"), kind: .finished)
            } else {
                TurnBadge(isYourTurn: !model.isAITurn)
                if model.isThinking {
                    ProgressView().controlSize(.small)
                }
            }
        } trailing: {
            // ストアの種の数（あなた – CPU）。
            Text(tr("あなた %1$lld – CPU %2$lld", model.humanStore, model.cpuStore))
                .themeBody(15, weight: .black, maxScale: 1.5)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .accessibilityLabel(tr("ストア、あなた%1$lld個、CPU%2$lld個", model.humanStore, model.cpuStore))
        }
    }

    /// 盤の下の案内。直前の手で起きたこと（続けて打つ・取った）を優先して出す。
    private var statusMessage: String {
        if model.gameOver { return " " }
        if let event = model.lastEvent {
            let mine = event.side == model.humanSide
            if event.captured > 0 {
                return mine ? tr("向かいの %lld 個を取った！", event.captured)
                            : tr("CPU が %lld 個取りました", event.captured)
            }
            if event.extraTurn {
                return mine ? tr("ストアに入った！もう一度あなたの番") : tr("CPU がもう一度まきます")
            }
        }
        if model.isAITurn { return tr("CPU が考えています…") }
        return tr("手前の穴をタップして種をまこう")
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let layout = MancalaBoardLayout(width: geo.size.width)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: MancalaBoardStyle.wood), Color(hex: MancalaBoardStyle.woodDeep)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                HStack(spacing: layout.gap) {
                    store(.north, layout: layout)
                    VStack(spacing: layout.gap) {
                        // 奥（CPU）の穴は右から左へまくので、画面の左端が CPU の 6 番目の穴。
                        HStack(spacing: layout.gap) {
                            ForEach(0..<MancalaBoard.pitsPerSide, id: \.self) { column in
                                cpuPit(pit: MancalaBoard.pitsPerSide - 1 - column, column: column, layout: layout)
                            }
                        }
                        HStack(spacing: layout.gap) {
                            ForEach(0..<MancalaBoard.pitsPerSide, id: \.self) { pit in
                                humanPit(pit: pit, layout: layout)
                            }
                        }
                    }
                    store(.south, layout: layout)
                }
                .padding(layout.gap)
            }
            .gameAnimation(.easeOut(duration: 0.2), value: model.turnID)
        }
        .aspectRatio(MancalaBoardLayout.aspectRatio, contentMode: .fit)
    }

    private func humanPit(pit: Int, layout: MancalaBoardLayout) -> some View {
        let slot = MancalaBoard.slotIndex(.south, pit: pit)
        let playable = model.legalPits.contains(pit)
        return Button { model.tap(pit: pit) } label: {
            MancalaPitView(seeds: model.board.slots[slot], diameter: layout.pit,
                           isPlayable: playable, isLastPit: model.lastMove?.pitSlot == slot,
                           isLanding: model.lastMove?.landingSlot == slot, countOnTop: false)
        }
        .buttonStyle(.plain)
        .disabled(model.gameOver || model.isAITurn)
        .accessibilityLabel(MancalaAccessibility.pitLabel(
            side: .south, column: pit, seeds: model.board.slots[slot],
            isPlayable: playable, isLastMove: model.lastMove?.pitSlot == slot))
    }

    private func cpuPit(pit: Int, column: Int, layout: MancalaBoardLayout) -> some View {
        let slot = MancalaBoard.slotIndex(.north, pit: pit)
        return MancalaPitView(seeds: model.board.slots[slot], diameter: layout.pit,
                              isPlayable: false, isLastPit: model.lastMove?.pitSlot == slot,
                              isLanding: model.lastMove?.landingSlot == slot, countOnTop: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MancalaAccessibility.pitLabel(
                side: .north, column: column, seeds: model.board.slots[slot],
                isPlayable: false, isLastMove: model.lastMove?.pitSlot == slot))
    }

    private func store(_ side: MancalaSide, layout: MancalaBoardLayout) -> some View {
        let slot = MancalaBoard.storeIndex(side)
        return MancalaStoreView(seeds: model.board.slots[slot], width: layout.pit,
                                label: side == model.humanSide ? tr("あなた") : "CPU",
                                isLanding: model.lastMove?.landingSlot == slot)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MancalaAccessibility.storeLabel(side: side, seeds: model.board.slots[slot]))
    }

    // MARK: - Controls

    private var gameControls: some View {
        // 待った・「⋯」（投了）の並びは盤ゲームで共通（#1421）。
        BoardGameControlBar(model: model, services: services, rescue: undoRescue,
                            onResign: { model.resign() })
    }

    private var resultVerdict: BoardGameResultCard.Verdict {
        switch model.reviewOutcome {
        case .win:  return .win
        case .loss: return .loss
        case .draw: return .draw
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if model.gameOver {
            BoardGameResultCard(
                verdict: resultVerdict,
                reason: tr("あなた %1$lld – CPU %2$lld", model.humanStore, model.cpuStore),
                record: model.recordResult
            ) { resultCardClosed = true }
        }
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（待った・投了）と終局後（もう一度・レコメンド）で中身が入れ替わるが、
    /// 高さは常に終局後の最大構成に揃える（#148。高さの担保は `GameControlArea`）。
    private var controlArea: some View {
        GameControlArea(isFinished: model.gameOver, services: services, ladder: ladder) {
            GameReplayBar(
                onReplay: { model.newGame(humanFirst: model.humanFirst, aiLevel: model.aiLevel) },
                onChangeSettings: { showNewGame = true }
            )
        } playing: {
            gameControls
        }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.newGame(humanFirst: model.humanFirst, aiLevel: CPUStrength.level(atLadderIndex: index))
        }
    }
}

// MARK: - 盤の寸法・色

/// 盤の寸法。幅を 8 単位（穴 6 + 左右のストア 2）に割る。
///
/// View の `static let` は MainActor に隔離されるので、テストから参照できるよう View の外に置く。
public struct MancalaBoardLayout: Sendable {
    /// 穴の直径に対する隙間の割合。
    public static let gapRatio: CGFloat = 0.12
    /// 穴の数字の帯の高さ（穴の直径に対する割合）。
    public static let countBandRatio: CGFloat = 0.32
    /// 盤の縦横比（横 8 単位 + 隙間 9 つ ÷ 縦 2 単位 + 数字の帯 + 隙間 3 つ）。
    public static let aspectRatio: CGFloat = (8 + gapRatio * 9) / (2 + countBandRatio * 2 + gapRatio * 3)

    public let width: CGFloat

    public init(width: CGFloat) { self.width = width }

    /// 穴の直径（= ストアの幅）。
    public var pit: CGFloat { width / (8 + Self.gapRatio * 9) }
    public var gap: CGFloat { pit * Self.gapRatio }
}

/// 盤の色（木の板）。
enum MancalaBoardStyle {
    static let wood: UInt32 = 0xC99A62
    static let woodDeep: UInt32 = 0xA9773F
    static let hole: UInt32 = 0x7A5128
    static let holeDeep: UInt32 = 0x5C3A1A
}

// MARK: - 穴とストア

/// 穴 1 つ（くぼみ・種・数字）。数字は奥の段は上、手前の段は下に出す。
struct MancalaPitView: View {
    let seeds: Int
    let diameter: CGFloat
    let isPlayable: Bool
    let isLastPit: Bool
    let isLanding: Bool
    let countOnTop: Bool

    var body: some View {
        VStack(spacing: 0) {
            if countOnTop { count }
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: MancalaBoardStyle.holeDeep), Color(hex: MancalaBoardStyle.hole)],
                                         center: .center, startRadius: 0, endRadius: diameter / 2))
                MancalaSeedPile(seeds: seeds, diameter: diameter * 0.86)
                if isPlayable {
                    Circle().strokeBorder(Theme.teal, lineWidth: 3)
                }
                if isLastPit {
                    Circle().strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                if isLanding {
                    Circle().fill(Theme.yellow.opacity(0.28))
                }
            }
            .frame(width: diameter, height: diameter)
            if !countOnTop { count }
        }
        .contentShape(Rectangle())
    }

    private var count: some View {
        Text("\(seeds)")
            .scaledFont(15, weight: .black, design: .rounded, maxScale: 1.3)
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: diameter, height: diameter * MancalaBoardLayout.countBandRatio)
    }
}

/// ストア（盤の左右の細長いくぼみ）。数字は中央に大きく出す。
struct MancalaStoreView: View {
    let seeds: Int
    let width: CGFloat
    let label: String
    let isLanding: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .scaledFont(11, weight: .black, design: .rounded, maxScale: 1.2)
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: MancalaBoardStyle.holeDeep), Color(hex: MancalaBoardStyle.hole)],
                                         startPoint: .top, endPoint: .bottom))
                if isLanding {
                    Capsule().fill(Theme.yellow.opacity(0.28))
                }
                MancalaSeedPile(seeds: seeds, diameter: width * 0.86)
                    .opacity(0.55)
                Text("\(seeds)")
                    .scaledFont(20, weight: .black, design: .rounded, maxScale: 1.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .frame(width: width)
    }
}

/// 穴の中の種。数が多くても形が崩れないよう、ひまわりの種の並び（黄金角）で中心から置く。
/// 描くのは 20 個まで（それ以上は数字で読む）。
struct MancalaSeedPile: View {
    nonisolated static let maxDrawn = 20
    nonisolated static let palette: [UInt32] = [0xF4D35E, 0x9ED8DB, 0xF28F79, 0xB8E28A, 0xE7C6FF, 0xFFFFFF]

    let seeds: Int
    let diameter: CGFloat

    var body: some View {
        let shown = min(seeds, Self.maxDrawn)
        let seedSize = diameter * 0.2
        ZStack {
            ForEach(0..<shown, id: \.self) { i in
                let p = Self.position(i, count: shown, radius: (diameter - seedSize) / 2)
                Circle()
                    .fill(Color(hex: Self.palette[i % Self.palette.count]))
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: seedSize, height: seedSize)
                    .offset(x: p.x, y: p.y)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    /// i 番目の種の位置（中心からのずれ）。
    nonisolated static func position(_ i: Int, count: Int, radius: CGFloat) -> CGPoint {
        guard count > 1 else { return .zero }
        let r = radius * CGFloat((Double(i) + 0.5) / Double(count)).squareRoot()
        let angle = Double(i) * 2.399963
        return CGPoint(x: r * CGFloat(cos(angle)), y: r * CGFloat(sin(angle)))
    }
}

// MARK: - くわしいルール

struct MancalaRuleSheet: View {
    static var rules: [(String, String)] {
        [
            (tr("盤"), tr("手前の 6 つの穴があなた、奥の 6 つが CPU。右端の大きなくぼみがあなたのストア、左端が CPU のストアです。はじめは各穴に 4 個ずつ、合わせて 48 個の種があります。")),
            (tr("まき方"), tr("自分の穴を 1 つ選ぶと、中の種をすべて取り、反時計回りに 1 個ずつ次の穴へ入れていきます。自分のストアには入れますが、相手のストアは飛ばします。")),
            (tr("もう一度"), tr("最後の 1 個が自分のストアに入ったら、もう一度続けてまけます。")),
            (tr("取り"), tr("最後の 1 個が自分の側の空の穴に入り、向かいの相手の穴に種があれば、その種と最後の 1 個をまとめて自分のストアに入れます。向かいが空なら取れません。")),
            (tr("終わり"), tr("どちらかの側の穴がすべて空になったら終わりです。残った種はそれぞれの側のストアに入り、ストアの種が多いほうの勝ち。同じ数なら引き分けです。")),
        ]
    }

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}

// MARK: - New Game Sheet

struct MancalaNewGameSheet: View {
    @State private var humanFirst: Bool
    @State private var level: Int
    let onStart: (Bool, Int) -> Void
    let onCancel: () -> Void

    init(humanFirst: Bool, aiLevel: Int,
         onStart: @escaping (Bool, Int) -> Void,
         onCancel: @escaping () -> Void) {
        _humanFirst = State(initialValue: humanFirst)
        _level = State(initialValue: aiLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onStart: { onStart(humanFirst, level) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("手番")) {
                HStack(spacing: 12) {
                    GameSetupChooser(title: tr("先手"), subtitle: tr("あなたから"),
                                     selected: humanFirst, accent: Theme.fillStrong,
                                     onAccent: .white) { humanFirst = true }
                    GameSetupChooser(title: tr("後手"), subtitle: tr("CPU から"),
                                     selected: !humanFirst, accent: Theme.fillMuted,
                                     onAccent: .white) { humanFirst = false }
                }
            }
            GameSetupSection(tr("CPUの強さ")) {
                // 説明は `MancalaEngine.bestMove` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    tr("でたらめに選ぶ"), tr("1手先だけ見る"), tr("4手先まで読む"), tr("8手先まで読む"),
                ])
            }
        }
    }
}
