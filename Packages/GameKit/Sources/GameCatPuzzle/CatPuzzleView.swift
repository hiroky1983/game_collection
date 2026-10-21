import SwiftUI
import Core

/// おじさんの飼い猫パズル（#2250）のプレイ画面。家の間取りのマスをタップして ×・猫を置く。
public struct CatPuzzleView: View {
    private let services: GameServices
    @State private var model: CatPuzzleModel
    /// 最後に選んだ盤の大きさ（次に開いたときの初期値）。
    @AppStorage("catPuzzleSize") private var preferredSize = CatPuzzleSize.normal.rawValue
    @State private var showConfirmReset = false
    /// 確認のあとに始める大きさ（nil なら同じ大きさで始め直す）。
    @State private var pendingSize: CatPuzzleSize?
    /// 「やり直し」（印を全部消す）の確認。
    @State private var showConfirmClear = false
    /// 難易度の選択の幕。
    @State private var showSizeDialog = false

    public init(services: GameServices) {
        self.services = services
        let saved = UserDefaults.standard.string(forKey: "catPuzzleSize").flatMap(CatPuzzleSize.init(rawValue:))
        _model = State(initialValue: CatPuzzleModel(services: services, size: saved ?? .normal))
    }

    /// 狙った局面を描くための入口（静止画の確認・テスト用）。
    init(services: GameServices, model: CatPuzzleModel) {
        self.services = services
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            // 盤は残りの高さを Spacer と山分けしない（操作の段が増えた分だけ盤が縮むのを防ぐ）。
            board
                .gameClearCard(isPresented: model.isSolved, title: tr("クリア！"), details: clearDetails)
                .layoutPriority(1)
            messageLine
            actionRow
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.catPuzzle, playLog: services.playLog)
            RecommendationArea(services: services, isFinished: model.isSolved)
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("おじさんの飼い猫パズル"), review: services.review,
                    newGame: GameChromeNewGame(.solo) { requestNewGame(size: nil) })
        .howToPlay(HowToPlayGuide.catPuzzle.illustrated(CatPuzzleHowToFigures.items))
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmReset, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { startNewGame(size: pendingSize) }
                Button(tr("キャンセル"), role: .cancel) { pendingSize = nil }
            } message: {
                Text(tr("途中で終了すると、いまの盤面とタイムが失われます。"))
            }
            anchor.confirmationDialog(tr("難易度"), isPresented: $showSizeDialog, titleVisibility: .visible) {
                ForEach(CatPuzzleSize.allCases, id: \.self) { size in
                    Button(tr("%1$@（%2$@）", size.label, size.sizeLabel)) { requestNewGame(size: size) }
                }
                Button(tr("キャンセル"), role: .cancel) {}
            }
            anchor.confirmationDialog(tr("印を全部消しますか？"), isPresented: $showConfirmClear, titleVisibility: .visible) {
                Button(tr("全部消してやり直す"), role: .destructive) { withGameAnimation { model.reset() } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("同じ問題を最初から解きます。タイムとミスはそのままです。"))
            }
        }
        // 矛盾が出たとき・消えたときに読み上げる。
        .onChange(of: model.violations) { _, violations in
            if let message = CatPuzzleAccessibility.message(for: violations) {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        // 画面を離れたら・背面に回ったら計時を止め、戻ったら再開する（#375・#1734。`gameTimerLifecycle`・#1857）。
        .gameTimerLifecycle(
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
        .task { model.resumeTimerIfNeeded() }
    }

    // MARK: - 上の帯

    /// 左に残りの猫、右にミス・難易度（押すと切り替え）・タイム。
    private var statusBar: some View {
        GameStatusBar {
            Text(model.isSolved ? tr("全員みつけた！") : tr("残り %lld匹", model.remainingCats))
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundStyle(model.isSolved ? Theme.tealText : Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } trailing: {
            // 右側は折り返さない（「0:00」が 2 行に割れないよう固定幅で勝たせる）。
            HStack(spacing: 6) {
                Text(tr("ミス %lld", model.mistakes))
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3).monospacedDigit()
                    .foregroundStyle(model.mistakes > 0 ? Theme.coralText : Theme.inkSub)
                Text(tr("・")).foregroundStyle(Theme.inkSub).accessibilityHidden(true)
                sizeMenu
                Text(tr("・")).foregroundStyle(Theme.inkSub).accessibilityHidden(true)
                GameClockLabel(RecordFormat.time(model.elapsedSeconds))
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .accessibilityElement(children: .contain)
    }

    /// 難易度（盤の大きさ）。押すと選択の幕を出し、選んだ大きさで始め直す（途中なら確認を挟む）。
    private var sizeMenu: some View {
        Button {
            showSizeDialog = true
        } label: {
            HStack(spacing: 2) {
                Text(model.size.label)
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3)
                Image(systemName: "chevron.down")
                    .scaledFont(9, weight: .bold)
            }
            .foregroundStyle(Theme.tealText)
            .frame(minHeight: GameButtonMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("難易度 %@", model.size.label))
        .accessibilityHint(tr("押して難易度を選ぶ"))
    }

    // MARK: - 盤

    private var board: some View {
        GeometryReader { geo in
            let n = model.puzzle.side
            let inset: CGFloat = 8
            let boardSide = min(geo.size.width, geo.size.height)
            let cellSide = max(1, (boardSide - inset * 2) / CGFloat(n))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                CatPuzzleBoardCanvas(
                    puzzle: model.puzzle, marks: model.marks, conflicts: shownConflicts,
                    hintCells: model.hintCells, lastHint: model.lastHint, isSolved: model.isSolved, cellSide: cellSide
                )
                .offset(x: inset, y: inset)
                cells(cellSide: cellSide, inset: inset)
            }
            .frame(width: boardSide, height: boardSide)
            .frame(maxWidth: .infinity, alignment: .center)
            .gameAnimation(.easeOut(duration: 0.15), value: model.marks)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 印を付ける矛盾。ヒントで置いた猫は答えなので印を付けない（違うのは相手の猫）。
    private var shownConflicts: Set<Int> { model.violations.cells.subtracting(model.hintCells) }

    /// タップと VoiceOver 用のマスの並び。見た目は Canvas で描き、操作と読み上げだけをこちらに置く。
    private func cells(cellSide: CGFloat, inset: CGFloat) -> some View {
        let n = model.puzzle.side
        let conflicts = shownConflicts
        return ForEach(0..<model.puzzle.cellCount, id: \.self) { index in
            Color.clear
                .frame(width: cellSide, height: cellSide)
                .contentShape(Rectangle())
                .offset(x: inset + CGFloat(index % n) * cellSide, y: inset + CGFloat(index / n) * cellSide)
                .onTapGesture { withGameAnimation { model.tap(cell: index) } }
                .accessibilityElement()
                .accessibilityLabel(CatPuzzleAccessibility.cellLabel(
                    row: index / n, col: index % n,
                    roomName: CatPuzzleHouse.room(model.puzzle.rooms[index]).name,
                    mark: model.marks[index],
                    isConflict: conflicts.contains(index),
                    isHint: model.hintCells.contains(index)
                ))
                .accessibilityHint(model.isSolved ? "" : model.hintCells.contains(index)
                                   ? tr("ヒントで置いた猫は消せません") : tr("押すと ×、猫、空きの順に変わります"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { withGameAnimation { model.tap(cell: index) } }
        }
    }

    // MARK: - 盤の下

    /// 盤の下の 1 行。ヒント・矛盾の説明・クリアの一言。高さは常に確保して盤が跳ねないようにする。
    private var messageLine: some View {
        ZStack {
            if model.isSolved {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        OjisanPixel.faceImage(.cheer)
                            .frame(width: 48, height: 45)
                        Text(tr("%lld匹ともくつろいでおる", model.size.side))
                            .scaledFont(14, weight: .bold, design: .rounded)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .popCard(corner: Theme.cornerSmall)
                    }
                    RecordLabel(model.recordResult)
                }
            } else if let hint = model.lastHint {
                Label(CatPuzzleAccessibility.message(for: hint, roomName: CatPuzzleHouse.room(hint.room).name), systemImage: "lightbulb.fill")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.yellowText)
                    .multilineTextAlignment(.center)
            } else if let message = CatPuzzleAccessibility.message(for: model.violations) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    // 読み上げは `onChange` の通知で 1 回だけ伝える。
                    .accessibilityHidden(true)
            } else {
                Text(tr("タップで ×、もう一度で猫"))
                    .scaledFont(14, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .frame(minHeight: 36)
    }

    /// 操作の段（#1834）。広告が絡むヒントと「戻す」を段に、やり直しは「⋯」に入れる。
    private var actionRow: some View {
        GameOverflowBar(
            menuItems: [
                GameControlMenuItem(
                    id: "clear", title: tr("やり直し"), systemImage: "arrow.counterclockwise",
                    isDestructive: true, isEnabled: model.hasProgressToLose
                ) { showConfirmClear = true },
            ],
            actions: [
                GameActionItem(
                    id: "undo", title: tr("戻す"), systemImage: "arrow.uturn.backward", role: .undo,
                    isEnabled: model.canUndo
                ) { withGameAnimation { model.undo() } },
                GameActionItem(
                    id: "hint", title: tr("ヒント"), systemImage: "lightbulb.fill", role: .hint,
                    badge: hintBadge,
                    isEnabled: model.canHint,
                    accessibilityLabel: tr("ヒント、あと%lld回", model.hintsRemaining),
                    accessibilityHint: tr("答えの猫を1匹置きます。違う場所の猫があれば先に×にします")
                ) { withGameAnimation { model.useHint() } },
            ],
            verticalPadding: 4
        )
    }

    /// ヒントの 2 行目。無料ぶんを使い切ったら「0回 ▶ 広告を見て +1」の面にする。
    /// **試作では広告の差し込み口だけ**で、`RewardedRescue` は呼ばない（押せない）。本導入時に
    /// ナンプレのヒントの救済（`hintRescue`・目的はヒント）と同じ経路をここへつなぐ。
    private var hintBadge: GameActionBadge {
        model.hintsRemaining > 0 ? .count(model.hintsRemaining) : .ad(gain: 1)
    }

    private var clearDetails: [String] {
        [
            tr("タイム %@", RecordFormat.time(model.elapsedSeconds)),
            tr("%1$@（%2$@）", model.size.label, model.size.sizeLabel),
            tr("ミス %lld", model.mistakes),
        ]
    }

    // MARK: - 新規ゲーム

    /// 途中の盤面があるときだけ確認を挟む。`size` が nil なら同じ大きさで始め直す。
    private func requestNewGame(size: CatPuzzleSize?) {
        if let size, size == model.size { return }
        if model.hasProgressToLose {
            pendingSize = size
            showConfirmReset = true
        } else {
            startNewGame(size: size)
        }
    }

    private func startNewGame(size: CatPuzzleSize?) {
        if let size { preferredSize = size.rawValue }
        pendingSize = nil
        withGameAnimation { model.newGame(size: size) }
    }
}
