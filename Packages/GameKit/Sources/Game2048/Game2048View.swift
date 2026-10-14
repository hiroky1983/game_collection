import SwiftUI
import Core

/// 2048 のプレイ画面。スワイプで操作し、盤面変化をアニメーションする。
public struct Game2048View: View {
    private let services: GameServices
    @State private var model: Game2048Model
    /// コンティニューのリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var continueRescue = RewardedRescue()
    @State private var showConfirmReset = false
    /// 「戻す」の回数補充のリワード広告の段取り（#2023）。
    @State private var undoRescue = RewardedRescue()
    @State private var showUndoRefillPrompt = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: Game2048Model(services: services))
    }

    public var body: some View {
        // 縦の余白は 14。レコメンドのぶんの高さを常に確保するので、盤面に回せる高さを
        // 間隔から捻出している（#148）。
        VStack(spacing: 14) {
            header
            boardView
            gameControls
            // 初回だけ出す 1 行（#118。以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.game2048, playLog: services.playLog)
            recommendationArea
            Spacer()
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: "2048", review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        if model.hasProgressToLose {
                            showConfirmReset = true
                        } else {
                            withGameAnimation { model.newGame() }
                        }
                    })
        .howToPlay(HowToPlayGuide.game2048.illustrated(Game2048HowToFigures.items))
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmReset, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { withGameAnimation { model.newGame() } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの盤面と得点が失われます。"))
            }
            anchor.alert(tr("無料の「戻す」を使い切りました"), isPresented: $showUndoRefillPrompt) {
                Button(tr("広告を見て%lld回補充する", Game2048UndoBudget.refill)) { requestUndoRefill() }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("広告を最後まで視聴すると「戻す」を%lld回ぶん補充します。\n盤面はそのままです。", Game2048UndoBudget.refill))
            }
        }
        .rewardOffer(undoRescue, for: .undo, isPresented: showUndoRefillPrompt,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            undoRescue,
            notEarned: tr("「戻す」を補充できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("「戻す」を補充できませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったため、補充できませんでした。\n新しい局の「戻す」は無料の回数まで戻っています。")
            )
        )
        .onAppear {
            #if DEBUG
            // 撮影・動作確認用: `-simulate2048Move <up|down|left|right>` でその向きへ 1 手動かす（#438）。
            // 勝利演出はスワイプ起点でしか出せず、中断スナップショットの復元だけでは画を作れない
            // （#437 の `-simulateChord` と同型）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-simulate2048Move"), i + 1 < args.count,
               let direction = Self.direction(named: args[i + 1]) {
                withGameAnimation(.easeInOut(duration: 0.12)) { model.move(direction) }
            }
            // 撮影・動作確認用: `-simulate2048GameOver` でゲームオーバーの幕（盤だけに重ねる・#1486）を出す。
            if args.contains("-simulate2048GameOver") {
                model.debugForceGameOver()
            }
            #endif
        }
        .rewardedRescueAlerts(
            continueRescue,
            notEarned: tr("コンティニューできませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("コンティニューできませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったため、コンティニューできませんでした。")
            )
        )
    }

    /// 盤の下の「操作の段」（#1856）。2048 は広告の絡む「戻す」だけを段に出し、「⋯」は持たない。
    private var gameControls: some View {
        GameOverflowBar(actions: [
            GameActionItem(
                id: "undo", title: tr("戻す"), systemImage: "arrow.uturn.backward", role: .undo,
                badge: model.undosRemaining > 0 ? .count(model.undosRemaining) : .ad(gain: RewardedUndoBudget.refill),
                isEnabled: model.canUndo && !undoRescue.isWatching && !continueRescue.isWatching,
                // 専用の読み上げ文を渡すと 2 行目（▶ 広告を見て）は読まれないので、使い切ったら広告が要ることを文に含める。
                accessibilityLabel: model.undosRemaining > 0
                    ? tr("1手戻す（残り%lld回）", model.undosRemaining)
                    : tr("1手戻す（広告を見て補充）"),
                accessibilityHint: model.canUndo
                    ? tr("直前のスワイプの前の盤面と得点に戻します")
                    : tr("戻せる手がありません")
            ) { requestUndo() },
        ])
        .lineLimit(1)
    }

    /// 「戻す」の入口（ナンプレ・フリーセルと同じ契約・#1855）。残りがあればそのまま戻し、
    /// 使い切っていたら**提案を出すだけ**にする（押した瞬間に広告を出さない）。
    private func requestUndo() {
        guard !undoRescue.isWatching else { return }
        if model.needsUndoRefill {
            showUndoRefillPrompt = true
        } else {
            withGameAnimation(.easeInOut(duration: 0.12)) { _ = model.undo() }
        }
    }

    /// リワード広告 → 「戻す」の補充。どの局かを広告を出す前に控え、ロード中に始めた新しい局へは乗せない。
    private func requestUndoRefill() {
        guard !undoRescue.isWatching else { return }
        let game = model.gameSerial
        undoRescue.request(
            services, gameID: model.gameID, purpose: .undo,
            guardedBy: .checkedByGrant
        ) {
            model.grantUndos(forGame: game)
        }
    }

    /// レコメンドカードの枠。高さの担保は `RecommendationArea`（#148）。
    ///
    /// 2048 到達も「決着」なのでレコメンドの対象になる（#438）。ここを `gameOver` だけで
    /// 見ていると、提示カウント（`markShown`）だけ消費してカードが一度も出ない。
    private var recommendationArea: some View {
        RecommendationArea(services: services,
                           isFinished: model.gameOver || model.showWinPrompt)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("スコア"))
                    .themeCaption(12, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .themeBody(30, weight: .heavy, maxScale: 1.5).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        // 縦の余白は 10。スコアの文字の大きさは変えずに、ここからも盤面の高さを捻出している（#148）。
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let n = Game2048Logic.size
            let tileSize = (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0xE7C9A8))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                VStack(spacing: spacing) {
                    ForEach(0..<n, id: \.self) { r in
                        HStack(spacing: spacing) {
                            ForEach(0..<n, id: \.self) { c in
                                TileView(value: model.board[r][c], size: tileSize)
                            }
                        }
                    }
                }
                .padding(spacing)
            }
            // 支援技術にだけ 16 マスを見せる（#712）。勝敗の幕（下の overlay）より手前に付けるので、
            // 幕の「続ける」「もう一度」などのボタンは置き換わらずそのまま読める。
            .accessibilityRepresentation {
                accessibilityGrid(tileSize: tileSize, spacing: spacing)
            }
            .overlay {
                if model.gameOver {
                    gameOverOverlay
                } else if model.showWinPrompt {
                    winOverlay
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // 盤の下に操作の段が増えても、余りを Spacer と山分けして盤が縮まないよう盤を先に確保する（#2023）。
        .layoutPriority(1)
        .gameAnimation(.easeInOut(duration: 0.12), value: model.board)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    /// 2048 初到達の勝利演出（#438）。原典と同じく、ここから同じ盤面のまま続けられる。
    private var winOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text(tr("2048 達成！")).font(.title2.bold()).foregroundStyle(.white)
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                Button {
                    withGameAnimation { model.continueAfterWin() }
                } label: {
                    Label(tr("続ける"), systemImage: "arrow.forward.circle.fill")
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
                Button(tr("もう一度")) { withGameAnimation { model.newGame() } }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
    }

    private var gameOverOverlay: some View {
        RewardedContinueOverlay(
            title: tr("ゲームオーバー"),
            detail: RecordLabel(model.recordResult, textColor: .white.opacity(0.85)),
            rescueLabel: tr("広告を見てコンティニュー"),
            canContinue: !model.continueUsed,
            rescue: continueRescue, services: services, gameID: model.gameID,
            serial: model.gameSerial,
            grant: { game in withGameAnimation { model.continueAfterAd(forGame: game) } },
            secondaryTitle: tr("もう一度"),
            secondaryAction: { withGameAnimation { model.newGame() } }
        )
    }

    #if DEBUG
    /// 起動引数の向きの綴りを `Direction` へ。知らない綴りは nil（何もしない）。
    private static func direction(named name: String) -> Direction? {
        switch name {
        case "up":    return .up
        case "down":  return .down
        case "left":  return .left
        case "right": return .right
        default:      return nil
        }
    }
    #endif

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let direction: Direction = abs(dx) > abs(dy)
                    ? (dx > 0 ? .right : .left)
                    : (dy > 0 ? .down : .up)
                slide(direction)
            }
    }

    /// スワイプと VoiceOver のアクションが共通で通る 1 手。
    private func slide(_ direction: Direction) {
        withGameAnimation(.easeInOut(duration: 0.12)) {
            model.move(direction)
        }
    }

    /// VoiceOver 用のマス目グリッド（#712）。
    ///
    /// 盤はスワイプでしか動かせず、VoiceOver 有効時はスワイプが支援技術に吸われるため、
    /// 各マスに上下左右へ動かすアクションを持たせる（どのマスにフォーカスしていても盤全体が動く）。
    /// `accessibilityRepresentation` は**描画も当たり判定もされず、支援技術に見せる姿としてだけ使われる**
    /// ので、見た目・アニメーション・指でのスワイプは一切変わらない。
    /// 勝敗の幕が出ているあいだは `model.move(_:)` が何もしないので、アクション自体を出さない。
    private func accessibilityGrid(tileSize: CGFloat, spacing: CGFloat) -> some View {
        let n = Game2048Logic.size
        let canMove = !model.gameOver && !model.showWinPrompt
        return VStack(spacing: spacing) {
            ForEach(0..<n, id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(0..<n, id: \.self) { c in
                        Color.clear
                            .frame(width: tileSize, height: tileSize)
                            .accessibilityElement()
                            .accessibilityLabel(Game2048Accessibility.tileLabel(
                                row: r, col: c, value: model.board[r][c]
                            ))
                            .accessibilityActions {
                                if canMove {
                                    ForEach(Direction.allCases, id: \.self) { direction in
                                        Button(Game2048Accessibility.moveActionName(direction)) {
                                            slide(direction)
                                        }
                                    }
                                }
                            }
                    }
                }
            }
        }
        .padding(spacing)
    }
}

/// 1 タイル。値に応じて配色する。
struct TileView: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if value > 0 {
                    Text("\(value)")
                        .font(.system(size: fontSize, weight: .bold, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(Color(hex: Self.textHex))
                        .padding(2)
                }
            }
            .id(value) // 値変化時に出現アニメを効かせる
            .transition(.scale.combined(with: .opacity))
    }

    private var fontSize: CGFloat { value >= 1024 ? size * 0.28 : size * 0.38 }

    private var color: Color { Color(hex: Self.faceHex(for: value)) }

    /// 文字色（`0xRRGGBB`）。全タイルで濃い茶を使う。明るい橙・黄の面に白文字だと 1.5〜2.6:1 しか出なかった（#2233）。
    static let textHex: UInt32 = 0x33241A

    /// 面色（`0xRRGGBB`）。文字色とのコントラスト比 4.5:1 以上をテストで固定している。
    static func faceHex(for value: Int) -> UInt32 {
        switch value {
        case 0:     return 0xD8C3A2
        case 2:     return 0xEDE3D9
        case 4:     return 0xEDE0C7
        case 8:     return 0xF2B078
        case 16:    return 0xF59463
        case 32:    return 0xF57D5E
        case 64:    return 0xF55E3B
        case 128:   return 0xEDCF73
        case 256:   return 0xEDCC61
        case 512:   return 0xEDC74F
        case 1024:  return 0xEDC440
        default:    return 0xEDC22E
        }
    }
}
