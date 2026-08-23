import SwiftUI
import Core

public struct MinesweeperView: View {
    @State private var model: MinesweeperModel
    private let services: GameServices
    @State private var showNewGame = true
    @State private var flagMode = false
    @State private var zoomMode = false
    @State private var showContinue = false
    @State private var showConfirmNewGame = false
    @State private var showGiveUpConfirm = false
    @State private var showRewardNotEarned = false
    @State private var isContinuing = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: MinesweeperModel(services: services))
        _showNewGame = State(initialValue: !services.snapshots.exists(for: "minesweeper"))
    }

    public var body: some View {
        // 縦の余白は 8。プレイ中と終局後で高さが変わらない `controlArea` を置くぶん、
        // 盤に回せる高さを間隔から捻出している（#148）。
        VStack(spacing: 8) {
            statusBar
            board
                .layoutPriority(1)
            HowToPlayHint(.minesweeper, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .animation(.none, value: model.gameOver)
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
                Text("マインスイーパー")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.gameState == .playing {
                        showConfirmNewGame = true
                    } else {
                        showNewGame = true
                    }
                } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
            }
        }
        .howToPlay(.minesweeper)
        .sheet(isPresented: $showNewGame) {
            MinesweeperNewGameSheet { rows, cols, mines in
                model.newGame(rows: rows, cols: cols, mines: mines)
                flagMode = false
                zoomMode = false
                showContinue = false
                showNewGame = false
            } onCancel: {
                showNewGame = false
            }
        }
        .confirmationDialog("新規ゲームを始めますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { showNewGame = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると対局データが失われます。")
        }
        .confirmationDialog("諦めますか？", isPresented: $showGiveUpConfirm, titleVisibility: .visible) {
            Button("諦める", role: .destructive) { model.giveUp() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("全ての地雷が公開されゲームオーバーになります。")
        }
        .overlay {
            if showContinue { continueOverlay }
        }
        .alert("コンティニューできませんでした", isPresented: $showRewardNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影・動作確認用（DEBUG 限定）: タップ無しで終局後のレイアウトにする（`-simulateGiveUp`）。
            // この画面の終局状態はタップ起点でしか作れず、中断スナップショットからの復元は
            // 常にプレイ中に戻る（`MinesweeperModel.init` が `.playing` 固定）ため、
            // 非対話のシミュレータ確認ではこの経路が要る（#148）。
            if ProcessInfo.processInfo.arguments.contains("-simulateGiveUp") {
                // 中断スナップショットが無い初回起動では新規ゲームシートが前面に出たままに
                // なるため、先に畳んでから終局させる（PR #153 指摘）。
                showNewGame = false
                model.giveUp()
            }
            #endif
        }
        .onChange(of: model.gameState) { _, state in
            if state == .lost && model.hitMine != nil { showContinue = true }
        }
    }

    // MARK: - Game Controls

    private var gameControls: some View {
        HStack {
            Button { showGiveUpConfirm = true } label: {
                Label("諦める", systemImage: "flag.fill")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.coral))
            }
            Spacer()
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Continue Overlay

    private var continueOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("💥")
                    .font(.system(size: 52))
                Text("地雷を踏んだ！")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)

                Button {
                    // 広告のロード〜表示中の連打で2本目が失敗し、誤ってアラートが出るのを防ぐ
                    guard !isContinuing else { return }
                    isContinuing = true
                    Task {
                        // 視聴完了（報酬獲得）したときだけコンティニューを許可する
                        if await services.ads.showRewardedAd() {
                            model.continueAfterAd()
                            showContinue = false
                        } else {
                            showRewardNotEarned = true
                        }
                        isContinuing = false
                    }
                } label: {
                    Label("広告を見てコンティニュー", systemImage: "play.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.coral, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isContinuing)

                Button { showContinue = false } label: {
                    Text("あきらめる")
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

    // MARK: - 盤の下の操作エリア

    /// プレイ中（諦める）・コンティニュー中（何も出さない）・終局後（記録 + 次のゲーム + レコメンド）で
    /// 中身が入れ替わるが、**高さは常に終局後の最大構成に揃える**（#148）。
    ///
    /// ここが伸び縮みすると `board`（`aspectRatio(1, .fit)` + `layoutPriority(1)`）が
    /// 帳尻合わせに縮み、決着した瞬間に盤が一段小さくなって見える。レコメンドは出るとは
    /// 限らず×でも閉じられるため、カードのぶんは常にひな形で高さを確保しておく。
    private var controlArea: some View {
        ZStack(alignment: .top) {
            finishedControls { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if model.gameOver && !showContinue {
                finishedControls {
                    RecommendationSlot(services: services, isFinished: true)
                }
            } else if model.gameState == .playing {
                gameControls
            }
        }
    }

    /// 終局後に出すもの。高さの基準（ひな形）と実物で同じ組み方を使う。
    private func finishedControls<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            resultControls
            recommendation()
        }
    }

    // MARK: - Result Controls

    /// 記録と「次のゲーム」は 1 段にまとめ、プレイ中の `gameControls` と同じ高さに収める（#148）。
    /// 3 段のままだと盤の下が伸び、決着の瞬間に盤が縮む。結果（クリア / ゲームオーバー）と
    /// 所要時間はステータスバーが出しているため、入れ替えても情報は失われない。
    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { showNewGame = true } label: {
                Label("次のゲーム", systemImage: "arrow.clockwise")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Status Bar

    /// 幅は固定値で決め打ちせず、各グループの内容幅（`fixedSize`）で決める。
    /// 左右を `maxWidth: .infinity` の等分フレームに載せることで絵文字が常に中央に来る。
    private var statusBar: some View {
        HStack(spacing: 8) {
            Group {
                if model.gameOver {
                    // 終局後の結果は行を増やさずここに同居させる（#148）。残り地雷数は
                    // 決着後には意味を持たないため、入れ替えても失われる情報は無い。
                    let won = model.gameState == .won
                    Label(won ? "クリア！" : "ゲームオーバー",
                          systemImage: won ? "flag.checkered" : "xmark.octagon.fill")
                        .themeBody(15)
                        // 文字を拡大すると「ゲームオーバー」が理想幅を要求して
                        // 右のタイマー・旗・ズームを押し出すため、ここだけは縮めて収める（#189）。
                        // 残り地雷数（下の分岐）は等幅で幅を固定したいので `fixedSize` を残す。
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(won ? Theme.teal : Theme.coral)
                } else {
                    Label(String(format: "%02d", max(0, model.remainingMines)),
                          systemImage: "flag.fill")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(Theme.coral)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(stateEmoji)
                .font(.system(size: 28))
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 8) {
                Label(String(format: "%03d", min(model.elapsedSeconds, 999)),
                      systemImage: "clock")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.teal)

                Button { flagMode.toggle() } label: {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(flagMode ? Theme.coral : Theme.surface)
                        )
                        .foregroundStyle(flagMode ? .white : Theme.inkSub)
                }
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
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // 縦の余白は 8。数字・ボタンの大きさは変えずに、ここからも盤の高さを捻出している（#148）。
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var stateEmoji: String {
        switch model.gameState {
        case .won:  return "😎"
        case .lost: return "😵"
        default:    return "🙂"
        }
    }

    // MARK: - Board

    private var board: some View {
        Group {
            if zoomMode {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    boardGrid(cellSize: 44)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            } else {
                GeometryReader { geo in
                    boardGrid(cellSize: geo.size.width / CGFloat(model.cols))
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            }
        }
    }

    private func boardGrid(cellSize: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x777777)
            VStack(spacing: 0) {
                ForEach(0..<model.rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<model.cols, id: \.self) { c in
                            cellView(row: r, col: c, size: cellSize)
                        }
                    }
                }
            }
        }
        .frame(
            width: cellSize * CGFloat(model.cols),
            height: cellSize * CGFloat(model.rows)
        )
    }

    private func cellView(row: Int, col: Int, size: CGFloat) -> some View {
        let cell  = model.cells[row][col]
        let isHit = model.hitMine.map { $0.row == row && $0.col == col } ?? false

        return ZStack {
            Rectangle()
                .fill(cellBg(cell: cell, isHit: isHit))
                .padding(0.7)
            cellContent(cell: cell, isHit: isHit, size: size)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            if flagMode {
                model.toggleFlag(row: row, col: col)
            } else {
                model.tap(row: row, col: col)
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            model.toggleFlag(row: row, col: col)
        }
        // マスの状態は色とアイコンだけで表しているため、読み上げ文を明示する（#188）。
        // `children: .ignore` にしないと数字だけが読まれ、旗や未開放が伝わらない。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MinesweeperAccessibility.cellLabel(
            row: row, col: col, cell: cell, isHit: isHit, gameOver: model.gameOver
        ))
        .accessibilityHint(MinesweeperAccessibility.cellHint(
            flagMode: flagMode,
            canReveal: model.canReveal(row: row, col: col),
            canToggleFlag: model.canToggleFlag(row: row, col: col)
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if flagMode {
                model.toggleFlag(row: row, col: col)
            } else {
                model.tap(row: row, col: col)
            }
        }
        // 旗モードでないときの近道。実際に旗を置けるマスにだけ出す
        // （出しても何も起きない操作を VoiceOver に読み上げさせない）。
        .accessibilityActions {
            if !flagMode, model.canToggleFlag(row: row, col: col) {
                Button("旗を切り替える") { model.toggleFlag(row: row, col: col) }
            }
        }
    }

    private func cellBg(cell: MinesweeperCell, isHit: Bool) -> Color {
        if cell.isRevealed {
            return isHit ? Theme.coral : Color(hex: 0xD8D8D8)
        }
        if cell.isContinuedMine {
            // コンティニューで確定した爆弾: 濃いオレンジ背景
            return Color(hex: 0x7A3800)
        }
        if model.gameOver && cell.isFlagged {
            // ゲームオーバー後のみ: 正しい旗=teal、誤旗=coral
            return cell.isMine ? Theme.teal.opacity(0.28) : Theme.coral.opacity(0.28)
        }
        return Color(hex: 0xBDBDBD)
    }

    @ViewBuilder
    private func cellContent(cell: MinesweeperCell, isHit: Bool, size: CGFloat) -> some View {
        let iconSize   = size * 0.52
        let gameIsOver = model.gameOver

        if !cell.isRevealed && cell.isContinuedMine {
            // コンティニューで確定した爆弾マス: 炎アイコン
            Image(systemName: "flame.fill")
                .resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.orange)
        } else if !cell.isRevealed && cell.isFlagged {
            if gameIsOver && !cell.isMine {
                // 誤フラグ: バツ印（ゲームオーバー後のみ）
                Image(systemName: "xmark.circle.fill")
                    .resizable().scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(Theme.coral)
            } else {
                // 正しい旗（プレイ中は通常の赤、ゲームオーバー後は緑）
                Image(systemName: "flag.fill")
                    .resizable().scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(gameIsOver && cell.isMine ? Theme.teal : Theme.coral)
            }
        } else if cell.isRevealed && cell.isMine {
            Image(systemName: isHit ? "burst.fill" : "circle.fill")
                .resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(isHit ? .white : Color(hex: 0x2A2A2A))
        } else if cell.isRevealed && cell.adjacentMines > 0 {
            Text("\(cell.adjacentMines)")
                .font(.system(size: size * 0.56, weight: .black, design: .rounded))
                .foregroundStyle(numberColor(cell.adjacentMines))
        }
    }

    private func numberColor(_ n: Int) -> Color {
        switch n {
        case 1: return Color(hex: 0x1565C0)
        case 2: return Color(hex: 0x2E7D32)
        case 3: return Theme.coral
        case 4: return Color(hex: 0x0D47A1)
        case 5: return Color(hex: 0xB71C1C)
        case 6: return Color(hex: 0x006064)
        case 7: return Theme.Fixed.ink
        default: return Color(hex: 0x616161)
        }
    }
}

// MARK: - New Game Sheet

struct MinesweeperNewGameSheet: View {
    let onStart: (Int, Int, Int) -> Void
    let onCancel: () -> Void
    @State private var level = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                section("難易度") {
                    HStack(spacing: 12) {
                        chooser(title: "初級", subtitle: "9×9  10地雷",
                                selected: level == 0, accent: Theme.teal)   { level = 0 }
                        chooser(title: "中級", subtitle: "12×12  25地雷",
                                selected: level == 1, accent: Theme.yellow) { level = 1 }
                        chooser(title: "上級", subtitle: "15×15  40地雷",
                                selected: level == 2, accent: Theme.coral)  { level = 2 }
                    }
                }
                Spacer()
                Button {
                    switch level {
                    case 1: onStart(12, 12, 25)
                    case 2: onStart(15, 15, 40)
                    default: onStart(9, 9, 10)
                    }
                } label: {
                    Text("スタート").themeBody(18).frame(maxWidth: .infinity)
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
        .gameSheetDetents()
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).themeBody(15).foregroundStyle(Theme.inkSub)
            content()
        }
    }

    private func chooser(title: String, subtitle: String,
                         selected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).themeTitle(22).foregroundStyle(selected ? .white : Theme.ink)
                Text(subtitle).font(.system(size: 11, weight: .semibold, design: .rounded))
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
