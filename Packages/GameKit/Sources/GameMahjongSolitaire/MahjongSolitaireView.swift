import Foundation
import SwiftUI
import Core
import MahjongTiles

/// ヒント（リワード広告制・#336）の確認ダイアログ。
///
/// `body` へ直接ぶら下げる修飾子が積み上がると
/// 「The compiler is unable to type-check this expression in reasonable time」でビルドが
/// 通らなくなる（実測）。1 つの修飾子にまとめて型チェックの段数を減らしている。
/// 視聴できなかった・出せなかったときのアラートは共通の
/// `rewardedRescueAlerts(_:notEarned:unavailable:)` が持つ（#526）。
private struct HintAlerts: ViewModifier {
    @Binding var showConfirm: Bool
    let onWatchAd: () -> Void

    func body(content: Content) -> some View {
        content
            // 押した直後に広告を出さず、広告が出ることを予告してから視聴へ進める
            // （並べ替え・将棋の「待った」と同じ契約）。
            .alert("ヒント確認", isPresented: $showConfirm) {
                Button("広告を見てヒントを見る") { onWatchAd() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("広告を視聴すると、いま取れる組を1組だけ光らせます。")
            }
    }
}

/// 「戻す」の補充まわり（#1855）を 1 つの修飾子にまとめる。`HintAlerts` と同じ理由
/// （`body` に直接ぶら下げると型チェックが破綻する）で、確認・広告の予告・失敗アラートを持つ。
private struct UndoRefillAlerts: ViewModifier {
    @Binding var showPrompt: Bool
    let rescue: RewardedRescue
    let services: GameServices
    let gameID: String
    let onWatchAd: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("無料の「戻す」を使い切りました", isPresented: $showPrompt) {
                Button("広告を見て\(MahjongSolitaireUndoBudget.refill)回補充する") { onWatchAd() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("広告を最後まで視聴すると「戻す」を\(MahjongSolitaireUndoBudget.refill)回ぶん補充します。\n盤面はそのままです。")
            }
            .rewardOffer(rescue, for: .undo, isPresented: showPrompt, services: services, gameID: gameID)
            .rewardedRescueAlerts(
                rescue,
                notEarned: "「戻す」を補充できませんでした",
                unavailable: RewardUnavailableAlert(
                    title: "「戻す」を補充できませんでした",
                    message: "広告を見ているあいだに配り直されたか、局が終わったため、補充できませんでした。\n新しい盤面の「戻す」は無料の回数まで戻っています。"
                )
            )
    }
}

public struct MahjongSolitaireView: View {
    @State private var model: MahjongSolitaireModel
    @Environment(\.scenePhase) private var scenePhase
    private let services: GameServices
    /// 盤面全体を 1 画面に収める表示にしているか。
    ///
    /// **既定は true（= 全体見渡し）**（会長指示 2026-09-02）。開幕はまず盤全体を見渡して
    /// 形を把握し、取りに行くときに「拡大」で 44pt の触れる大きさへ切り替える流れにする。
    /// （#196 当初は「触れる大きさ」既定だったが、初手から局所しか見えないほうが不便という判断）
    @State private var showsWholeBoard = MahjongSolitaireView.initialShowsWholeBoard
    /// 盤面のかたちを選ぶ開始シート（会長 QA 2026-09-28）。ほかのゲームの難易度選びと同じく、
    /// **中断データが無い初回はシートから始め**、ナビバーの「新規ゲーム」でも開く。中断データがあれば出さず続きから。
    @State private var showSetup: Bool
    /// 開始シートで選んでいる最中のかたち。「スタート」を押すまで局には効かない（1局=1RuleSet）。
    @State private var draftLayout: MahjongSolitaireLayout = .turtle
    @State private var showShuffleConfirm = false
    /// 並べ替えのリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var shuffleRescue = RewardedRescue()
    // ヒントも並べ替えと同じリワード広告制（#336）。状態の持ち方・アラートの文言まで揃える。
    @State private var showHintConfirm = false
    /// ヒントのリワード広告の段取り（同上）。
    @State private var hintRescue = RewardedRescue()
    /// 「戻す」を使い切ったときの補充の提案と、そのリワード広告の段取り（#1855）。
    @State private var showUndoRefillPrompt = false
    @State private var undoRescue = RewardedRescue()
    /// ヒントと並べ替えは**同じリワード広告の枠**を奪い合う。`RewardedRescue` の連打ガードは
    /// インスタンスごとなので、片方の広告をロードしている最中にもう片方を押せてしまい、
    /// 2 本目のロードが失敗して「見ていないのに失敗アラート」が出る（PR #577 の CodeRabbit 指摘）。
    /// 手詰まりでない盤面ではヒントも並べ替えも押せるので、この経路は実際に踏める。
    private var isWatchingRewardAd: Bool { hintRescue.isWatching || shuffleRescue.isWatching || undoRescue.isWatching }
    /// 盤面の場所にクリアの表示を出しているか（#199）。
    ///
    /// `model.phase` を直に見ると、最後の 2 枚は `faces` が nil になるのと**同じ更新**で
    /// `phase` が `.won` になるため、盤面ごとクリア表示に差し替わって消失アニメーションが
    /// 出ないまま終わる。牌が消えきる時間だけ切り替えを遅らせて、最後の 1 組も同じ演出で消す。
    /// 遅らせるのは**盤面の表示だけ**で、勝敗・記録・計時（`model`）は従来どおり即座に確定する。
    @State private var showsClearDisplay = false

    private typealias Metrics = MahjongSolitaireBoardMetrics

    /// 撮影用に拡大表示の状態で起動する経路（DEBUG 限定）。
    /// シミュレータは自動タップができないため、既定でない方の表示を撮る手段がこれしかない。
    private static var initialShowsWholeBoard: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mahjongSolitaireZoomed") { return false }
        #endif
        return true
    }

    /// 撮影用に特定のかたちで起動する経路（DEBUG 限定・#239）。
    /// シミュレータは自動タップができないため、開始シートから選ぶ操作を再現する手段がこれしかない
    /// （`-mahjongSolitaireZoomed` と同じ理由）。指定したときは開始シートを出さずにそのかたちで配る。
    private static var launchLayout: MahjongSolitaireLayout? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-mahjongLayout"), i + 1 < args.count {
            return .named(args[i + 1])
        }
        #endif
        return nil
    }

    public init(services: GameServices) {
        self.services = services
        let launchLayout = MahjongSolitaireView.launchLayout
        // 中断データの有無はモデルを作る前に見る（モデルは作った時点では保存しないが、順序に頼らない）。
        let hasSnapshot = services.snapshots.exists(for: MahjongSolitaireModel.snapshotID)
        // 中断データがあれば続きから（シートを出さない）。起動引数でかたちを指定したときも出さない。
        let showsInitialSetup = launchLayout == nil && !hasSnapshot
        _model = State(initialValue: MahjongSolitaireModel(
            services: services,
            layout: launchLayout ?? .turtle,
            // シートを出すときは `game_start` をシートを閉じるまで保留する（二重計上の防止・囲碁 #1372 と同じ）。
            defersInitialStart: showsInitialSetup
        ))
        _showSetup = State(initialValue: showsInitialSetup)
    }

    public var body: some View {
        // 縦の余白は 8。プレイ中と取り切った後で高さが変わらない `controlArea` を置くぶん、
        // 盤面に回せる高さを間隔から捻出している（#148）。
        VStack(spacing: 8) {
            statusBar
            // 盤は卓の上に置く（#1501）。牌の大きさは卓の内側の幅から決まるので、山が卓からはみ出さない。
            board
                .cardTable()
                // 15 枚並ぶ盤面は横幅で大きさが決まるので、左右の余白を卓の分（`boardSideInset` 4pt。
                // ソリティア系 3 本と同じ）まで詰めて牌を大きくする。
                .padding(.horizontal, -(Theme.pad - CardStackLayout.boardSideInset))
                .layoutPriority(1)
            controlArea
            HowToPlayHint(.mahjongSolitaire, playLog: services.playLog)
            // 余りの高さは「⋯」の行と広告のあいだに置く（盤→「⋯」→余白→広告・#1485）。
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        // ヒント・並べ替えの広告中は配り直させない（#815。照合は `forDeal:` が持つので、ここは
        // 「広告を見たのに何も起きなかった」を起こさないための緩和）。
        .gameChrome(title: "麻雀ソリティア", review: services.review,
                    newGame: GameChromeNewGame(.solo, isDisabled: isWatchingRewardAd) {
                        openSetup()
                    })
        .howToPlay(.mahjongSolitaire) { MahjongSolitaireRuleSheet() }
        // 初回のシートを閉じたとき（キャンセル・下へのスワイプを含む）は、配ってある盤面（亀甲）で
        // そのまま遊べるよう計時を始め、保留していた `game_start` を数える（シートで配り直したなら
        // `newGame` が数え済みで何もしない）。プレイ中に開いたシートなら計時は止めていないので何も起きない。
        .sheet(isPresented: $showSetup, onDismiss: {
            model.startPlayIfPending()
            model.resumeTimerIfNeeded()
        }) {
            MahjongSolitaireSetupSheet(draft: $draftLayout, discardsProgress: hasProgress) {
                showSetup = false
                startGame(layout: draftLayout)
            } onCancel: {
                showSetup = false
            }
        }
        // 並べ替えはリワード広告制（会長指示 2026-08-30）。将棋の「待った」と同じく、
        // 広告が出ることをダイアログで予告してから視聴に進める（突然の広告を出さない）。
        .alert("並べ替え確認", isPresented: $showShuffleConfirm) {
            Button("広告を見て並べ替える") { requestShuffle() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("広告を視聴すると、残りの牌をそこから必ず取り切れる配置に並べ替えます。")
        }
        .rewardedRescueAlerts(
            shuffleRescue,
            notEarned: "並べ替えできませんでした",
            // 広告のあいだも「最初から」（手詰まりの覆い）や「次のゲーム」で配り直せるので、
            // 取り切れない残り方だけを理由にしない（#815）。
            unavailable: RewardUnavailableAlert(
                title: "並べ替えられませんでした",
                message: "広告を見ているあいだに新しい盤面が配られたか、残った牌が重なっていて取り切れません。取り切れないときは「最初から」で新しい盤面を配ってください。"
            )
        )
        // ヒントもリワード広告制（#336）。確認ダイアログは `HintAlerts` にまとめてある
        // （ここへ直接ぶら下げると body の型チェックが破綻してコンパイルが通らない）。
        .modifier(HintAlerts(showConfirm: $showHintConfirm, onWatchAd: requestHint))
        .modifier(UndoRefillAlerts(
            showPrompt: $showUndoRefillPrompt, rescue: undoRescue,
            services: services, gameID: model.gameID, onWatchAd: requestUndoRefill
        ))
        // 並べ替えは確認アラートと手詰まりの覆い（確認を経ずに広告へ進む）の 2 か所で選ばせている（#780）。
        .rewardOffer(shuffleRescue, for: .shuffle, isPresented: showShuffleConfirm || model.isDeadlocked,
                     services: services, gameID: model.gameID)
        .rewardOffer(hintRescue, for: .hint, isPresented: showHintConfirm,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: "ヒントを表示できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "ヒントを出せませんでした",
                message: "広告を見ているあいだに新しい盤面が配られたか、光らせられる組が無くなりました。組が無いときは「並べ替え」で残りを配置し直してください。"
            )
        )
        .overlay {
            if model.isDeadlocked { deadlockOverlay }
        }
        // 画面を離れたら計時を止める（#1369）。戻れば .task が再開する。
        .onDisappear { model.pauseTimer() }
        // 背面に回っている間は計時を止める（基盤規約「バックグラウンド移行時は即一時停止」・#1734）。
        // 止めないと、考えているあいだの計時が 30 秒刻みの保存を待たずに進み、アプリ終了で
        // 直近の保存値に戻せてしまう（最短タイムを縮められる）。止めるときに経過秒を保存する。
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.pauseTimer()
            } else if !showSetup && !isWatchingRewardAd {
                model.resumeTimerIfNeeded()
            }
        }
        // 広告のロード〜視聴中は計時を止める（全画面広告は onDisappear を発火させない・#1382）。
        .pausesTimerWhileWatching([shuffleRescue, hintRescue, undoRescue], pause: { model.pauseTimer() }, resume: { model.resumeTimerIfNeeded() })
        .task {
            // 初回の開始シートを出しているあいだは計時しない（選び終えてから数え始める）。
            if !showSetup { model.resumeTimerIfNeeded() }
            #if DEBUG
            // 撮影・動作確認用（DEBUG 限定）: タップ無しでヒントの確認ダイアログを出す
            // （`-solitaireHintConfirm`）。この画面はタップ起点でしかダイアログを出せず、
            // シミュレータは自動タップができないため、非対話の確認にはこの経路が要る
            // （`-simulateGiveUp` と同じ理由・#336）。
            if ProcessInfo.processInfo.arguments.contains("-solitaireHintConfirm") {
                showSetup = false
                showHintConfirm = true
            }
            // 手詰まりの画面を確認する経路（`-mahjongSolitaireDeadlock`）。乱択で取り続けて手詰まりまで進める。
            if ProcessInfo.processInfo.arguments.contains("-mahjongSolitaireDeadlock") {
                showSetup = false
                model.debugPlayUntilDeadlock()
            }
            // 中断データがあっても開始シートを開く経路（`-mahjongSolitaireSetup`・撮影用）。
            if ProcessInfo.processInfo.arguments.contains("-mahjongSolitaireSetup") {
                openSetup()
            }
            #endif
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

    // MARK: - 新規ゲーム（盤面のかたちの選択・#239）

    /// 開始シートを開く。**いま遊んでいるかたちを初期選択にする**（ソリティア #498・スパイダーと同じ）。
    private func openSetup() {
        draftLayout = model.layout
        showSetup = true
    }

    /// 途中の盤面（1 組でも取った）があるか。開始シートの確定ボタンを「終了してスタート」にする
    /// （旧・確認ダイアログ「終了して新規ゲーム」の役目をシートが兼ねる。ソリティアと同じ）。
    private var hasProgress: Bool {
        model.phase == .playing && model.remainingCount < model.layout.count
    }

    /// 開始シートの「スタート」。
    ///
    /// 初回のシートでは、画面を開いた時点で亀甲が配ってある（シートのあいだは計時もしていない）。
    /// **同じかたちで、配ったまま何もしていないなら配り直さない**（無駄に配り直さない。
    /// `game_start` はシートを閉じたときの `startPlayIfPending()` が 1 回だけ数える）。
    private func startGame(layout: MahjongSolitaireLayout) {
        if layout == model.layout && model.phase == .playing && model.dealSerial == 0
            && model.remainingCount == model.layout.count && model.elapsedSeconds == 0
            && model.shuffleCount == 0 && model.hintCount == 0 {
            model.resumeTimerIfNeeded()
        } else {
            model.newGame(layout: layout)
        }
    }

    // MARK: - ステータスバー

    /// 帯には表示だけを置く（残り枚数・状態・時計）。全体表示⇄拡大などの操作は右下の「⋯」へ（#1468）。
    private var statusBar: some View {
        GameStatusBar {
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
        } trailing: {
            Label(timeText, systemImage: "clock")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.teal)
        }
    }

    private var timeText: String {
        let s = min(model.elapsedSeconds, 59 * 60 + 59)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - 盤面

    private var board: some View {
        Group {
            if showsClearDisplay {
                // 取り切った直後は盤面が空になるので、代わりに共通のクリアカードを置く（#1755）。
                // 補助の利用実績は **0 回でも省かず全部出す**（クリアしたときの記録の内訳であり、
                // 「使わずに取り切った」ことが読み取れる形にしておく = 記録の公平性・#198）。
                GameClearCard(title: "全部取り切った！", details: [
                    "タイム \(RecordFormat.time(model.elapsedSeconds))",
                    "ヒント\(model.hintCount)回 / 並べ替え\(model.shuffleCount)回 / 戻す\(model.undoCount)回",
                ])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    if showsWholeBoard {
                        boardCanvas(tileWidth: Metrics.fittingTileWidth(in: geo.size, layout: model.layout))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // 44pt の牌だと盤面は画面より広くなるのでスクロールで見て回る。
                        // 左上ではなく中央から始めるのは、どのかたちも山が中央にあるため
                        // （両方向へ同じだけ動かせる）。
                        // スクロールバーは**出す**。盤面のどこを見ているかを知る唯一の手がかりで、
                        // 隠すと「全体のどのあたりか」が分からないまま動かすことになる（#197）。
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            boardCanvas(tileWidth: Metrics.comfortableTileWidth(in: geo.size, layout: model.layout))
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
        let canvas = Metrics.canvasSize(tileWidth: tileWidth, layout: model.layout)
        // 牌の外接矩形。牌ごとに求め直さないよう 1 度だけ計算して渡す。
        let extent = Metrics.extent(layout: model.layout)
        return ZStack(alignment: .topLeading) {
            // 下の段から順に描くことで、上に積まれた牌が手前に来る。
            ForEach(model.faces.indices, id: \.self) { index in
                if let face = model.faces[index] {
                    tileView(index: index, face: face, tileWidth: tileWidth, extent: extent)
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
            layoutID: model.layout.id,
            faces: model.faces,
            selectedIndex: model.selectedIndex,
            hintPair: model.hintPair
        )
    }

    private struct BoardAnimationKey: Equatable {
        /// かたちを変えて配り直したときも演出を掛ける（枚数は同じなので `faces` だけでは
        /// 「たまたま同じ並び」を区別できない）。
        let layoutID: String
        let faces: [MahjongFace?]
        let selectedIndex: Int?
        let hintPair: [Int]
    }

    private func tileView(index: Int, face: MahjongFace, tileWidth: CGFloat, extent: Metrics.Extent) -> some View {
        let frame = Metrics.tileFrame(index: index, tileWidth: tileWidth, layout: model.layout, extent: extent)
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

    /// ヒント・並べ替え（どちらも広告）は盤の下の段のカプセルに出し、戻す・全体表示⇄拡大（広告なし）は右下の「⋯」に残す
    /// （#1468・#1856・会長決裁 2026-10-06「段に出すのは広告が絡む操作だけ」。戻すに上限を入れる件は #1855）。
    private var gameControls: some View {
        GameOverflowBar(menuItems: controlMenuItems, actions: controlActions, nudge: hintNudge)
    }

    /// 段: ヒント → 並べ替え。どちらもリワード広告制で、押した直後に広告を出さず確認ダイアログを挟む。
    /// 2 行目は「▶ 広告を見て」（回数の上限は無い）。互いの広告の視聴中は塞ぐ（`isWatchingRewardAd`・PR #577）。
    private var controlActions: [GameActionItem] {
        [
            GameActionItem(
                id: "hint", title: "ヒント", systemImage: "lightbulb.fill", role: .hint, badge: .ad(),
                isEnabled: model.canHint && !isWatchingRewardAd,
                accessibilityHint: "広告を見ると取れる組が1組光ります"
            ) { showHintConfirm = true },
            // 並べ替えはリワード広告制（会長指示 2026-08-30・PR #324）。確認ダイアログ → 視聴 → 並べ替えの順に進む。
            // ヒントの広告をロードしている最中は押させない（`isWatchingRewardAd` の理由）。
            GameActionItem(
                id: "shuffle", title: "並べ替え", systemImage: "shuffle", role: .primary, badge: .ad(),
                isEnabled: !isWatchingRewardAd
            ) { showShuffleConfirm = true },
        ]
    }

    /// 30 秒以上操作が無いときの促し（#1424）。広告は自動で再生せず、段のヒントを光らせるだけ。
    /// 手詰まり・決着・広告の視聴中は出さない。
    private var hintNudge: HintNudge {
        HintNudge(
            isEligible: model.canHint && !isWatchingRewardAd,
            game: model.dealSerial,
            activity: [model.selectedIndex ?? -1, model.remainingCount, model.hintCount, model.shuffleCount, model.undoCount, showsWholeBoard ? 1 : 0]
        )
    }

    /// 「⋯」に入れる操作（広告の無いもの）。ヒント（#336）は段へ移った。手詰まりで組が無いときはヒントを押せない
    /// （広告だけ見せない）。手詰まりなら操作行は `deadlockOverlay` に覆われるので実際には届かないが、
    /// 覆いに頼らず二重の歯止めにしておく。ヒントの広告をロードしている最中も押させない。
    private var controlMenuItems: [GameControlMenuItem] {
        [
            // 直前に取った 2 枚を戻す（#198）。取った直後だけ押せる。押せない間も項目は残す。
            GameControlMenuItem(
                id: "undo", title: "戻す（残り\(model.undosRemaining)）", systemImage: "arrow.uturn.backward",
                isEnabled: model.canUndo && !isWatchingRewardAd,
                accessibilityLabel: "直前に取った2枚を戻す（残り\(model.undosRemaining)回）",
                accessibilityHint: model.canUndo ? "" : "牌を取った直後だけ使えます"
            ) { requestUndo() },
            // 全体表示 ⇄ 拡大（#197）。ON（チェック）＝拡大中の向きは他のゲームと揃える（会長 QA 2026-09-13）。
            GameControlMenuItem(
                id: "zoom", title: "拡大", systemImage: "plus.magnifyingglass", isChecked: !showsWholeBoard,
                accessibilityLabel: showsWholeBoard ? "牌を大きくする" : "盤面全体を表示"
            ) { showsWholeBoard.toggle() },
        ]
    }

    // MARK: - 盤の下の操作エリア

    /// プレイ中（ヒント・並べ替え）と取り切った後（記録 + 次のゲーム + レコメンド）で
    /// 中身が入れ替わるが、**高さは常に後者の最大構成に揃える**（#148。高さの担保は `GameControlArea`）。
    private var controlArea: some View {
        GameControlArea(isFinished: model.phase == .won, services: services) {
            resultControls
        } playing: {
            gameControls
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
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 手詰まり

    /// リワード広告を最後まで見たときだけ並べ替える（数独のヒントと同じ契約・#64 のアラート統一）。
    /// 視聴中の連打で2本目の広告が失敗して誤アラートが出るのは共通側が塞ぐ（#526）。
    private func requestShuffle() {
        guard !isWatchingRewardAd else { return }
        // どの盤面に対する並べ替えかを広告を出す前に控え、ロード中に配り直された盤面へは乗せない（#815）。
        let deal = model.dealSerial
        shuffleRescue.request(
            services, gameID: model.gameID, purpose: .shuffle,
            guardedBy: .checkedByGrant
        ) {
            // 広告を見たのに並べ替わらない盤面（取り切れない残り方）は黙って終わらせない。
            model.shuffleRemaining(forDeal: deal)
        }
    }

    // MARK: - 戻す

    /// 「戻す」の入口を 1 本にまとめる（ソリティア・フリーセルと同じ契約・#1855）。
    ///
    /// 残り回数があればそのまま戻し、使い切っていたら**提案を出すだけ**にする。
    /// ここで広告を直接出さないのが要で、押した瞬間に再生が始まると
    /// 「戻すつもりが広告を見せられた」になる。
    private func requestUndo() {
        guard !isWatchingRewardAd else { return }
        if model.needsUndoRefill {
            showUndoRefillPrompt = true
        } else {
            model.undoLastTake()
        }
    }

    /// リワード広告 → 「戻す」の補充。どの盤面への補充かを広告を出す前に控え、
    /// ロード中に配り直された盤面へは乗せない（#815 と同じ）。
    private func requestUndoRefill() {
        guard !isWatchingRewardAd else { return }
        let deal = model.dealSerial
        undoRescue.request(
            services, gameID: model.gameID, purpose: .undo,
            guardedBy: .checkedByGrant
        ) {
            model.grantUndos(forDeal: deal)
        }
    }

    // MARK: - ヒント

    /// リワード広告を最後まで見たときだけヒントを出す（並べ替え・ナンプレのヒントと同じ契約・#336）。
    /// `requestShuffle()` と同じく、視聴中の連打のガードは共通側が持つ（#526）。
    private func requestHint() {
        guard !isWatchingRewardAd else { return }
        // 並べ替えと同じく、ロード中に配り直された盤面へは乗せない（#815）。
        let deal = model.dealSerial
        hintRescue.request(
            services, gameID: model.gameID, purpose: .hint,
            guardedBy: .checkedByGrant
        ) {
            // 広告を見たのに光らない（視聴中に手詰まりになった）経路は黙って終わらせない。
            model.showHint(forDeal: deal)
        }
    }

    private var deadlockOverlay: some View {
        GameDeadEndPanel(
            emoji: "😵",
            title: "取れる牌がありません",
            message: "広告を見ると残りが並べ替わり、そこから必ず取り切れる配置になります。"
        ) {
            GameDeadEndActionButton("広告を見て並べ替える", systemImage: "play.rectangle.fill", tint: Theme.Fill.purple) {
                requestShuffle()
            }

            // 手詰まりは直前の 1 手が作ったことが多い。オーバーレイは盤の下の操作を覆って
            // しまうので、ここにも出口を置かないとアンドゥが**必要な場面でだけ押せない**（#198）。
            if model.canUndo {
                GameDeadEndActionButton("直前の1手を戻す（残り\(model.undosRemaining)）", systemImage: "arrow.uturn.backward", tint: Theme.Fill.coral) {
                    requestUndo()
                }
            }

            GameDeadEndDismissButton("最初から") {
                model.giveUpAndRestart()
            }
        }
    }
}

// MARK: - くわしいルール

/// 「遊び方」シートから開く詳細ページ（#238）。組み方は `DaifugoRuleSheet` / `MahjongRuleSheet` と同じ。
///
/// 3 行のミニガイドは「同じ絵柄の牌を 2 枚」としか言えないが、実装では
/// `MahjongFace.matchKey` が花牌どうし・季節牌どうしを同一キーに潰しており、**絵柄が違っても合う**。
/// 初回盤面に必ず出るのに説明がどこにも無く、「同じに見えないのに消える」混乱を生んでいた。
struct MahjongSolitaireRuleSheet: View {
    /// 文言はテストから検証したいので型の外に出しておく（花牌・季節牌の説明が落ちると受け入れ条件を割る）。
    static let rules: [(String, String)] = [
        ("取れる牌", "上に牌が1枚も載っておらず、左どなり・右どなりのどちらかが空いている牌だけを取れます。両どなりがふさがっている牌は、まわりを取り除くまで選べません"),
        ("花牌と季節牌", "花牌（梅・蘭・菊・竹）どうし、季節牌（春・夏・秋・冬）どうしは、絵柄が違っても合わせて取れます。梅と蘭、春と冬のような組み合わせで消えるのはこのためです"),
        ("そのほかの牌", "花牌・季節牌以外は、まったく同じ絵柄の2枚だけが合います。一萬と二萬のように種類が同じでも数が違えば合いません"),
        ("並んでいる牌", "全部で144枚（標準の34種が4枚ずつ + 花牌4枚 + 季節牌4枚）です。配る盤面は取り切れる順番があるように作っているので、必ずクリアできます"),
        ("盤面のかたち", "はじめるときと「新規ゲーム」を押したときに、盤面のかたちを選べます。亀甲・ピラミッド・十字の3種類があり、どれも144枚で必ずクリアできます。最短タイムはかたちごとに別々に記録されます"),
        ("ヒント・並べ替え・戻す", "「ヒント」は取れる2枚を1組光らせます。「並べ替え」は残りをそこから取り切れる配置に組み直します（戻せる1手は無くなります）。「戻す」は直前に取った2枚を盤に返します。1局に\(MahjongSolitaireUndoBudget.free)回まで無料で、使い切ったら広告を見ると\(MahjongSolitaireUndoBudget.refill)回補充できます"),
    ]

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
