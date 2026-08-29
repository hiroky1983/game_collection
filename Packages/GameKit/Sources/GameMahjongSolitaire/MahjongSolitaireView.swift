import Foundation
import SwiftUI
import Core
import MahjongTiles

public struct MahjongSolitaireView: View {
    @State private var model: MahjongSolitaireModel
    private let services: GameServices
    /// 盤面全体を 1 画面に収める表示にしているか。
    ///
    /// **既定は false（= 牌を 44pt 以上にした表示）**。亀型レイアウトは横 15.56 枚ぶんあり、
    /// 44pt の牌で全体を出すには 684.6pt の幅が要る。iPhone では両立しないため、
    /// 「触れる大きさ」を既定にし、全体像はこのトグルで 1 タップ取り戻せるようにしている（#196）。
    @State private var showsWholeBoard = MahjongSolitaireView.initialShowsWholeBoard
    @State private var showConfirmNewGame = false
    @State private var showShuffleFailed = false
    @State private var showShuffleConfirm = false
    @State private var isRequestingShuffle = false
    @State private var showShuffleNotEarned = false
    /// 盤面の場所にクリアの表示を出しているか（#199）。
    ///
    /// `model.phase` を直に見ると、最後の 2 枚は `faces` が nil になるのと**同じ更新**で
    /// `phase` が `.won` になるため、盤面ごとクリア表示に差し替わって消失アニメーションが
    /// 出ないまま終わる。牌が消えきる時間だけ切り替えを遅らせて、最後の 1 組も同じ演出で消す。
    /// 遅らせるのは**盤面の表示だけ**で、勝敗・記録・計時（`model`）は従来どおり即座に確定する。
    @State private var showsClearDisplay = false
    @Environment(\.dismiss) private var dismiss

    private typealias Metrics = MahjongSolitaireBoardMetrics

    /// 撮影用に全体表示の状態で起動する経路（DEBUG 限定）。
    /// シミュレータは自動タップができないため、既定でない方の表示を撮る手段がこれしかない。
    private static var initialShowsWholeBoard: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-mahjongWholeBoard")
        #else
        return false
        #endif
    }

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: MahjongSolitaireModel(services: services))
    }

    public var body: some View {
        // 縦の余白は 8。プレイ中と取り切った後で高さが変わらない `controlArea` を置くぶん、
        // 盤面に回せる高さを間隔から捻出している（#148）。
        VStack(spacing: 8) {
            statusBar
            board
                // 15 枚並ぶ盤面は横幅で大きさが決まるので、左右の余白ぶんまで使って牌を大きくする。
                .padding(.horizontal, -Theme.pad)
                .layoutPriority(1)
            HowToPlayHint(.mahjongSolitaire, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
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
                Text("麻雀ソリティア")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.phase == .playing && model.remainingCount < MahjongSolitaireRules.layout.count {
                        showConfirmNewGame = true
                    } else {
                        model.newGame()
                    }
                } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
            }
        }
        .howToPlay(.mahjongSolitaire)
        .confirmationDialog("新規ゲームを始めますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { model.newGame() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると今の盤面が失われます。")
        }
        .alert("この盤面は並べ替えられません", isPresented: $showShuffleFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("残った牌が重なっていて取り切れません。「最初から」で新しい盤面を配ってください。")
        }
        // 並べ替えはリワード広告制（会長指示 2026-08-30）。将棋の「待った」と同じく、
        // 広告が出ることをダイアログで予告してから視聴に進める（突然の広告を出さない）。
        .alert("並べ替え確認", isPresented: $showShuffleConfirm) {
            Button("広告を見て並べ替える") { requestShuffle() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("広告を視聴すると、残りの牌をそこから必ず取り切れる配置に並べ替えます。")
        }
        .alert("並べ替えできませんでした", isPresented: $showShuffleNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
        .overlay {
            if model.isDeadlocked { deadlockOverlay }
        }
        .task {
            model.resumeTimerIfNeeded()
        }
        // 取り切ったら、最後の 1 組が消えきってから盤面をクリア表示に差し替える（#199）。
        // Reduce Motion のときは演出そのものが無いので待たない。
        .task(id: model.phase) {
            guard model.phase == .won else {
                showsClearDisplay = false
                return
            }
            if !Motion.isReduceMotionEnabled {
                try? await Task.sleep(nanoseconds: UInt64(Metrics.boardAnimationDuration * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            showsClearDisplay = true
        }
    }

    // MARK: - ステータスバー

    private var statusBar: some View {
        HStack(spacing: 0) {
            Group {
                if model.phase == .won {
                    // 取り切った後の表示は行を増やさずここに同居させる（#148）。
                    // 残り枚数は 0 で固定になるため、入れ替えても失われる情報は無い。
                    Label("クリア！", systemImage: "flag.checkered")
                        .themeBody(15)
                        .foregroundStyle(Theme.teal)
                } else {
                    Label("\(model.remainingCount)", systemImage: "square.stack.3d.up.fill")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.coral)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 78, alignment: .leading)

            Spacer()

            Text(stateEmoji).font(.system(size: 28))

            Spacer()

            HStack(spacing: 8) {
                Label(timeText, systemImage: "clock")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.teal)

                displayToggle
            }
            .frame(minWidth: 78, alignment: .trailing)
        }
        // 縦の余白は 4。切り替えボタンが 44pt になって帯の高さを決めるようになったぶんここを詰め、
        // #148 で捻出した盤面の高さを食わないようにしている（#197）。
        .padding(.horizontal, 12).padding(.vertical, Metrics.statusBarVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 全体表示 ⇄ 拡大の切り替え（#197）。
    ///
    /// 全体像を取り戻す唯一の入口なので、次の2点を満たす形にしてある:
    /// - **タップ標的 44pt 以上**（従来は実測 29×23pt で Apple HIG を下回っていた）
    /// - **記号だけにしない**。虫めがねアイコン 1 つでは「押すと何が起きるか」が伝わらず、
    ///   拡大・全体表示という機能の存在自体が初回プレイで気づかれない。常時出す短い文字で補う
    ///   （一度きりのヒントと違い、初回でも 2 回目以降でも同じように読める）。
    private var displayToggle: some View {
        Button { showsWholeBoard.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: showsWholeBoard ? "plus.magnifyingglass" : "minus.magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                Text(showsWholeBoard ? "拡大" : "全体")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .frame(
                minWidth: Metrics.toggleButtonMinSide,
                minHeight: Metrics.toggleButtonMinSide
            )
            // 押していない側の面は `Theme.surface`（＝カードと同じ白）だったため、
            // ボタンの輪郭がどこにも無く「押せる物」に見えなかった。薄い差し色と枠線を敷く（#197）。
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(showsWholeBoard ? Theme.teal : Theme.teal.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(showsWholeBoard ? .clear : Theme.teal.opacity(0.55), lineWidth: 1.5)
            )
            // 薄い面の上は白文字だと読めないので本文色を使う（差し色の面 + 白文字は押している側だけ）。
            .foregroundStyle(showsWholeBoard ? .white : Theme.ink)
            // 背景の角丸ではなく矩形全体を受ける（角の 44pt も取りこぼさない）。
            .contentShape(Rectangle())
        }
        // `.plain` は自前で描いた背景を通す代わりに押下フィードバックまで消える。
        // そのために用意された `.pop` を使う（#195・`PopButtonStyle`）。
        .buttonStyle(.pop)
        .accessibilityLabel(showsWholeBoard ? "牌を大きくする" : "盤面全体を表示")
    }

    private var timeText: String {
        let s = min(model.elapsedSeconds, 59 * 60 + 59)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var stateEmoji: String {
        if model.phase == .won { return "🎉" }
        return model.isDeadlocked ? "😵" : "🀄️"
    }

    // MARK: - 盤面

    private var board: some View {
        Group {
            if showsClearDisplay {
                // 取り切った直後は盤面が空になるので、代わりにクリアの演出を置く。
                VStack(spacing: 12) {
                    Text("🎉").font(.system(size: 64))
                    Text("全部取り切った！")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("ヒント\(model.hintCount)回 / 並べ替え\(model.shuffleCount)回")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    if showsWholeBoard {
                        boardCanvas(tileWidth: Metrics.fittingTileWidth(in: geo.size))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // 44pt の牌だと盤面は画面より広くなるのでスクロールで見て回る。
                        // 左上ではなく中央から始めるのは、亀型の山が中央にあるため（両方向へ同じだけ動かせる）。
                        // スクロールバーは**出す**。盤面のどこを見ているかを知る唯一の手がかりで、
                        // 隠すと「全体のどのあたりか」が分からないまま動かすことになる（#197）。
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            boardCanvas(tileWidth: Metrics.comfortableTileWidth(in: geo.size))
                                // 画面の方が広い辺（iPad 等）では全体表示と同じく中央に置く。
                                .frame(
                                    minWidth: geo.size.width,
                                    minHeight: geo.size.height,
                                    alignment: .center
                                )
                        }
                        .defaultScrollAnchor(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func boardCanvas(tileWidth: CGFloat) -> some View {
        let canvas = Metrics.canvasSize(tileWidth: tileWidth)
        return ZStack(alignment: .topLeading) {
            // 下の段から順に描くことで、上に積まれた牌が手前に来る。
            ForEach(MahjongSolitaireRules.layout.indices, id: \.self) { index in
                if let face = model.faces[index] {
                    tileView(index: index, face: face, tileWidth: tileWidth)
                }
            }
        }
        // 牌は `offset` で置くのでレイアウト上の大きさは 1 枚分しかない。
        // 盤面全体の枠を与え、左上を基準に揃えないと中央寄せされてずれる。
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .gameAnimation(.easeOut(duration: Metrics.boardAnimationDuration), value: boardAnimationKey)
    }

    /// 盤面のアニメーションを起こす値（#199）。
    ///
    /// 牌の増減（取得・並べ替え・配り直し）と枠色（選択・ヒント）を**ひとつにまとめて**、
    /// `.gameAnimation` を盤面に 1 つだけ掛ける。`.animation(_:value:)` は入れ子にすると
    /// 内側が外側のトランザクションを打ち消すため、2 つに分けると牌の消失アニメーションだけが
    /// 効かなくなる。Reduce Motion のときは `gameAnimation` が nil に落ち、
    /// 下の `.transition` ごと即時反映になる（状態変更そのものは必ず走る・#210）。
    private var boardAnimationKey: BoardAnimationKey {
        BoardAnimationKey(
            faces: model.faces,
            selectedIndex: model.selectedIndex,
            hintPair: model.hintPair
        )
    }

    private struct BoardAnimationKey: Equatable {
        let faces: [MahjongFace?]
        let selectedIndex: Int?
        let hintPair: [Int]
    }

    private func tileView(index: Int, face: MahjongFace, tileWidth: CGFloat) -> some View {
        let frame = Metrics.tileFrame(index: index, tileWidth: tileWidth)
        return MahjongTileView(
            face: face,
            width: frame.width,
            height: frame.height,
            isBlocked: !model.isFreeByIndex[index],
            isSelected: model.selectedIndex == index,
            isHinted: model.hintPair.contains(index)
        )
        // 取った牌は縮みながら消える。**`.offset` より前に置くこと**（#199）。
        // 後ろに置くと `offset` は牌のレイアウト上の位置（盤面の左上）を動かさないため、
        // 縮小の基準が牌の中心ではなく盤面の左上になり、消える牌が左上へ吸い込まれる。
        .transition(.scale(scale: 0.7).combined(with: .opacity))
        .offset(x: frame.minX, y: frame.minY)
        .onTapGesture { model.tap(index) }
        // 牌は図形と文字だけで描いているため、絵柄も取れるかどうかも音声では
        // 伝わらない。`onTapGesture` なのでボタン trait も自動では付かない（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MahjongSolitaireAccessibility.tileLabel(
            face: face,
            isBlocked: !model.isFreeByIndex[index],
            isSelected: model.selectedIndex == index,
            isHinted: model.hintPair.contains(index)
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tap(index) }
    }

    // MARK: - 操作

    private var gameControls: some View {
        HStack(spacing: 10) {
            Button { model.showHint() } label: {
                Label("ヒント", systemImage: "lightbulb.fill")
                    // 横幅は変えない。足りていなかったのは**高さ**（実測 約29pt）だけで、
                    // 広げると右の回数表示に押されて文字が 2 行に折り返す（#199）。
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: Metrics.controlButtonMinHeight)
                    .background(Capsule().fill(Theme.teal))
                    // カプセルの角の外側まで受ける（44pt の矩形を取りこぼさない・#197 と同じ）。
                    .contentShape(Rectangle())
            }
            Button {
                showShuffleConfirm = true
            } label: {
                Label("並べ替え", systemImage: "shuffle")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: Metrics.controlButtonMinHeight)
                    .background(Capsule().fill(Theme.purple))
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 8)
            if model.hintCount > 0 || model.shuffleCount > 0 {
                Text("ヒント\(model.hintCount) / 並べ替え\(model.shuffleCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    // 幅が足りないときに縮むのはボタンではなくこちら（#199）。
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 盤の下の操作エリア

    /// プレイ中（ヒント・並べ替え）と取り切った後（記録 + 次のゲーム + レコメンド）で
    /// 中身が入れ替わるが、**高さは常に後者の最大構成に揃える**（#148）。
    ///
    /// ここが伸び縮みすると盤面（残りの高さいっぱいに牌を敷く）が帳尻合わせに縮む。
    /// レコメンドは出るとは限らず×でも閉じられるため、カードのぶんは常にひな形で高さを確保しておく。
    private var controlArea: some View {
        ZStack(alignment: .top) {
            finishedControls { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if model.phase == .won {
                finishedControls {
                    RecommendationSlot(services: services, isFinished: true)
                }
            } else {
                gameControls
            }
        }
    }

    /// 取り切った後に出すもの。高さの基準（ひな形）と実物で同じ組み方を使う。
    private func finishedControls<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            resultControls
            recommendation()
        }
    }

    /// 記録と「次のゲーム」は 1 段にまとめ、プレイ中の `gameControls` と同じ高さに収める（#148）。
    /// 3 段のままだと盤面の下が伸び、取り切った瞬間に盤面の領域が縮む。クリアの表示と所要時間は
    /// ステータスバーが出しているため、入れ替えても情報は失われない。
    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { model.newGame() } label: {
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

    // MARK: - 手詰まり

    /// リワード広告を最後まで見たときだけ並べ替える（数独のヒントと同じ契約・#64 のアラート統一）。
    /// 視聴中の連打で2本目の広告が失敗して誤アラートが出ないよう `isRequestingShuffle` で塞ぐ。
    private func requestShuffle() {
        guard !isRequestingShuffle else { return }
        isRequestingShuffle = true
        Task {
            if await services.ads.showRewardedAd() {
                // 広告を見たのに並べ替わらない盤面（取り切れない残り方）は黙って終わらせない。
                if !model.shuffleRemaining() { showShuffleFailed = true }
            } else {
                showShuffleNotEarned = true
            }
            isRequestingShuffle = false
        }
    }

    private var deadlockOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("😵").font(.system(size: 52))
                Text("取れる牌がありません")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("広告を見ると残りが並べ替わり、そこから必ず取り切れる配置になります。")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .multilineTextAlignment(.center)

                Button {
                    requestShuffle()
                } label: {
                    Label("広告を見て並べ替える", systemImage: "play.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.purple, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { model.giveUpAndRestart() } label: {
                    Text("最初から")
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
}
