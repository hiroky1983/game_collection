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
            // 「戻す」は盤から離す（#2253）。広げたぶんは「戻す」の段の下側の余白から詰めて
            // 縦の合計を据え置く（SE では盤の大きさが縦で決まるため、合計が増えると盤が縮む）。
            gameControls
                .padding(.bottom, -Self.undoGapExtra)
            // 初回だけ出す 1 行（#118。以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.game2048, playLog: services.playLog)
            recommendationArea
            Spacer()
            BannerSlot(ads: services.ads)
        }
        .padding()
        .operationResultAnnouncement(model.lastResult)
        .gameChrome(title: "2048", review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        if model.hasProgressToLose {
                            showConfirmReset = true
                        } else {
                            withGameAnimation { model.newGame() }
                        }
                    })
        .howToPlay(HowToPlayGuide.game2048.illustrated(Game2048HowToFigures.items).onboarding(Game2048Onboarding.guide))
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
                withGameAnimation(Self.slideAnimation) { model.move(direction) }
            }
            // 動作確認用: `-simulate2048Moves left,up,undo,new,...` を `-simulate2048MoveInterval`（秒・既定 0.6）おきに
            // 指す（#2253 のスライドの画面収録用。シミュレータではスワイプを打てないため）。
            if let i = args.firstIndex(of: "-simulate2048Moves"), i + 1 < args.count {
                let steps = args[i + 1].split(separator: ",").map(String.init)
                let interval = args.firstIndex(of: "-simulate2048MoveInterval")
                    .flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 0.6
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    for step in steps {
                        switch step {
                        case "undo": requestUndo()
                        case "new": withGameAnimation { model.newGame() }
                        default: if let direction = Self.direction(named: step) { slide(direction) }
                        }
                        try? await Task.sleep(for: .seconds(interval))
                    }
                }
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
            withGameAnimation(Self.slideAnimation) { _ = model.undo() }
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
                    .foregroundStyle(Theme.inkSubText)
                Text("\(model.score)")
                    .themeBody(30, weight: .heavy, maxScale: 1.5).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(alignment: .top, spacing: 16) {
                // 今回の最高タイル（#2812）。
                HeaderBestStat(title: tr("最高"), value: "\(model.highestTile)")
                if let best = model.liveBestScore {
                    HeaderBestStat(title: tr("ベスト"), value: RecordFormat.number(best))
                }
            }
        }
        // VoiceOver では「スコア n、最高タイル n、ベスト n」の 1 要素で読む（#2615・#2812）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
        // 縦の余白は 10。スコアの文字の大きさは変えずに、ここからも盤面の高さを捻出している（#148）。
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var headerAccessibilityLabel: String {
        let score = RecordFormat.number(model.score)
        let tile = "\(model.highestTile)"
        guard let best = model.liveBestScore else { return tr("スコア %1$@、最高タイル %2$@", score, tile) }
        return tr("スコア %1$@、最高タイル %2$@、ベスト %3$@", score, tile, RecordFormat.number(best))
    }

    private var boardView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let n = Game2048Logic.size
            // GeometryReader は最初に大きさ 0 を渡すことがあるので、負の寸法にしない。
            let tileSize = max(0, (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0xE7C9A8))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                // 空きマスの下地。タイルはこの上に座標で置いて滑らせる。
                VStack(spacing: spacing) {
                    ForEach(0..<n, id: \.self) { _ in
                        HStack(spacing: spacing) {
                            ForEach(0..<n, id: \.self) { _ in
                                TileView(value: 0, size: tileSize)
                            }
                        }
                    }
                }
                .padding(spacing)
                // タイルは ID ごとに 1 つのビューを保ち、行・列の変化を座標のアニメーションにする（#2253）。
                // 合体元の 2 枚（`vanishing`）も同じ ForEach に入れる。別の ForEach に移すと別のビュー扱いになり、
                // 滑らずにその場で消えてしまう。
                ForEach(drawnTiles, id: \.tile.id) { item in
                    Game2048TileView(tile: item.tile, size: tileSize, appearDelay: Self.slideDuration)
                        .offset(x: spacing + CGFloat(item.tile.col) * (tileSize + spacing),
                                y: spacing + CGFloat(item.tile.row) * (tileSize + spacing))
                        .zIndex(item.isVanishing ? 0 : 1)
                }
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
        // 盤の直下の余白もスワイプの範囲にする（#2253）。盤の下端ぎりぎりから始めたスワイプを「戻す」が拾わないよう、
        // 盤 → スワイプの余白 → 何も反応しない余白 → 「戻す」の順に並べる。
        .padding(.bottom, Self.undoGapExtra)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
        // 盤の下に操作の段が増えても、余りを Spacer と山分けして盤が縮まないよう盤を先に確保する（#2023）。
        .layoutPriority(1)
        // 合体元の 2 枚は滑り終えたら片付ける。次の手が先に来たら、その手の中で入れ替わる。
        // 待ち始めたときの ID を控えて渡し、キャンセルが間に合わなくても次の手の合体元は消さない。
        .task(id: model.vanishing.map(\.id)) {
            let ids = model.vanishing.map(\.id)
            guard !ids.isEmpty else { return }
            try? await Task.sleep(for: .seconds(Self.slideDuration + 0.1))
            guard !Task.isCancelled else { return }
            model.settleVanishing(ids: ids)
        }
    }

    /// 「戻す」の段を盤から追加で離す量（#2253）。盤の下端 → 「戻す」のすき間は 22pt → 34pt。
    static let undoGapExtra: CGFloat = 12

    /// タイルが滑る時間（#2253）。合体の弾み・新しいタイルはこの後に出る。
    static let slideDuration: Double = 0.12
    static let slideAnimation: Animation = .easeInOut(duration: slideDuration)

    /// 描く順（合体元の 2 枚 → 盤のタイル）。ID は両者で重ならない。
    private var drawnTiles: [(tile: Game2048Tile, isVanishing: Bool)] {
        model.vanishing.map { ($0, true) } + model.tiles.map { ($0, false) }
    }

    /// 2048 初到達の勝利演出（#438）。原典と同じく、ここから同じ盤面のまま続けられる。
    private var winOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text(tr("2048 達成！")).font(.title2.bold()).foregroundStyle(.white)
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                GameDeadEndActionButton(
                    tr("続ける"), systemImage: "arrow.forward.circle.fill", tint: Theme.Fill.coral
                ) {
                    withGameAnimation { model.continueAfterWin() }
                }
                GameDeadEndDismissButton(tr("もう一回")) { withGameAnimation { model.newGame() } }
            }
            .padding(RewardedPanelLayout.contentPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .announcesResultAppearance(tr("2048 達成！"))
    }

    private var gameOverOverlay: some View {
        RewardedContinueOverlay(
            title: tr("ゲームオーバー"),
            cornerRadius: Theme.corner,
            detail: RecordLabel(model.recordResult, textColor: .white.opacity(0.85)),
            rescueLabel: tr("広告を見てコンティニュー"),
            canContinue: !model.continueUsed,
            rescue: continueRescue, services: services, gameID: model.gameID,
            serial: model.gameSerial,
            grant: { game in withGameAnimation { model.continueAfterAd(forGame: game) } },
            secondaryTitle: tr("もう一回"),
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
        withGameAnimation(Self.slideAnimation) {
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

/// 盤の上で動く 1 枚（#2253）。位置は親が `offset` で決め、ここは出方だけを持つ。
/// - 合体してできたタイル: 滑り終える（`appearDelay`）まで隠し、出たら軽く弾む。その間は合体元の 2 枚が滑って見える。
/// - 新しいタイル: 滑り終えてから小さい所から出る。
/// - それ以外（滑ってきた・作り直した）: そのまま見せる。
/// Reduce Motion のときは待たずにそのまま出す。
struct Game2048TileView: View {
    let tile: Game2048Tile
    let size: CGFloat
    let appearDelay: Double

    @State private var isShown: Bool
    @State private var scale: CGFloat

    init(tile: Game2048Tile, size: CGFloat, appearDelay: Double) {
        self.tile = tile
        self.size = size
        self.appearDelay = appearDelay
        let waits = tile.arrival == .merged || tile.arrival == .spawned
        _isShown = State(initialValue: !waits)
        _scale = State(initialValue: tile.arrival == .spawned ? 0.3 : 1)
    }

    var body: some View {
        TileView(value: tile.value, size: size)
            .scaleEffect(scale)
            .opacity(isShown ? 1 : 0)
            // 合体・出現の入り方は下の task が受け持つ。挿入・削除の既定のフェードは、戻す・新しいゲームの作り直しにだけ効かせる。
            .transition(tile.arrival == .placed ? .opacity : .asymmetric(insertion: .identity, removal: .opacity))
            .task { await appear() }
    }

    private func appear() async {
        guard !isShown else { return }
        if Motion.isReduceMotionEnabled {
            isShown = true
            scale = 1
            return
        }
        try? await Task.sleep(for: .seconds(appearDelay))
        guard !Task.isCancelled else { return }
        switch tile.arrival {
        case .merged:
            isShown = true
            withGameAnimation(.easeOut(duration: 0.07)) { scale = 1.12 }
            try? await Task.sleep(for: .seconds(0.07))
            withGameAnimation(.easeIn(duration: 0.08)) { scale = 1 }
        default:
            withGameAnimation(.easeOut(duration: 0.12)) {
                isShown = true
                scale = 1
            }
        }
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
