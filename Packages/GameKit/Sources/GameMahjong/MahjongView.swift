import SwiftUI
import Core
import MahjongTiles

public struct MahjongView: View {
    @State private var model: MahjongModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    /// 卓の下の手牌の行を iPad で広げるため（#715。`MahjongHandRowMetrics`）。
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @State private var showStartSheet = true
    /// 誤タップ防止: 1タップ目は選択（浮かせる演出）だけ、同じ牌をもう1回タップしたら実際に切る。
    /// 複数枚ある牌を区別できるよう `stableHandIDs` の合成ID（牌の値＋出現順）で管理する。
    /// ID は `MahjongHandTap.handTileID(index:)` / `.drawnTileID` で作り、卓上の一覧と
    /// 卓下の操作行で共有する（どちらでタップしても選択が同期する・#378）。
    @State private var selectedTileID: String?
    /// 卓上の一覧（`handOverviewOnTable`）から選んだ牌を、卓下の横スクロール側でも
    /// 見える位置まで送るための合図（#378）。下部を直接タップしたときは指の下の行が動くと
    /// 邪魔になるので、一覧経由のときだけ立てる。送り終えたら nil に戻す。
    @State private var overviewScrollTarget: String?
    /// トビ復活（#338）。ポーカー・ブラックジャックの「広告を見てチップ回復」と同じ持ち方。
    /// トビ復活のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var reviveRescue = RewardedRescue()
    /// 役の早見表（#501）。`MahjongModel` には触れないので、開閉しても対局の状態は動かない。
    @State private var showYakuSheet = false
    /// 進行中の対局を捨てて配り直す前の確認（#638）。
    @State private var showConfirmNewGame = false
    /// 飛行中の打牌（#738）。河の本物の牌は着地まで隠す。
    @State private var discardFlight: MahjongDiscardFlight?
    @State private var discardFlightProgress: CGFloat = 0
    /// ドラ見出し（`doraHeader`）の実幅。iPhone の基準幅 361pt に対する縮尺に使う。
    @State private var doraHeaderWidth: CGFloat = 0
    /// 打牌の飛び出し位置（#738）: 直前にタップで切った牌が一覧の何枚目（何枚中）にあったか。
    /// `startDiscardFlight` が 1 回使って捨てる。無ければツモ牌の位置（右端）から飛ぶ。
    @State private var pendingDiscardSlot: (index: Int, count: Int)?
    /// 飛行の通し番号。後片付けは「自分が始めた飛行」だけを消す（内容が同じ別の飛行を誤って消さない）。
    @State private var discardFlightSerial = 0
    /// 開始シートで選んでいる対局の長さ（#639）。ここは「次の対局に使う設定」で、
    /// 進行中の対局が見ているのは `model.gameLength`（開始時に焼き込んだ値）のほう。
    @State private var selectedLength: MahjongGameLength

    public init(services: GameServices) {
        self.services = services
        let m = MahjongModel(services: services)
        _model = State(initialValue: m)
        let hasSnapshot = services.snapshots.exists(for: "mahjong4")
        // デバッグ用（DEBUG 限定）: 会長がシミュレータで毎回手動プレイして確認する手間を省くための
        // 自動進行モード。起動引数（`-mahjongAutoPlay`）でだけ有効になり、通常起動には影響しない。
        // 開始シートのタップも省き、対局が無ければその場で最初の局を配る。
        // Release に残すと起動引数を注入するだけで全自動対局が回り、その戦績が Game Center の
        // 実績（wins10 / wins50 / playAll）に載ってしまうため、下の早見表と同じ形で囲う（#514）。
        #if DEBUG
        let autoPlay = ProcessInfo.processInfo.arguments.contains("-mahjongAutoPlay")
        if autoPlay {
            m.enableAutoPlay()
            if !hasSnapshot { m.startGame() }
        }
        #else
        let autoPlay = false
        #endif
        // 撮影用（DEBUG 限定）: 早見表を出す起動では開始シートを最初から出さない。
        // 同じビューの `.sheet` は 2 つ同時に出せないため、`.task` で開始シートを畳むだけだと
        // 開始シートが一瞬見えたり、早見表が出そこねたりする（CodeRabbit 指摘）。
        #if DEBUG
        let showsYakuOnLaunch = ProcessInfo.processInfo.arguments.contains("-mahjongShowYaku")
        // 撮影用（DEBUG 限定）: 対局中のツールバー（「新規対局」#638）と、その確認ダイアログ。
        // 開始シートを出したままだと卓もツールバーも隠れるので、早見表と同じく init で畳む。
        let skipsStartSheet = ProcessInfo.processInfo.arguments.contains("-mahjongSkipStartSheet")
            || ProcessInfo.processInfo.arguments.contains("-mahjongConfirmNewGame")
        #else
        let showsYakuOnLaunch = false
        let skipsStartSheet = false
        #endif
        _showStartSheet = State(
            initialValue: !hasSnapshot && !autoPlay && !showsYakuOnLaunch && !skipsStartSheet
        )
        // 撮影用（DEBUG 限定）: 開始シートを一局戦を選んだ状態で出す（#639）。ピッカーの選択は
        // タップでしか動かせず、シミュレータは自動タップができないため、この経路でしか撮れない。
        #if DEBUG
        let picksSingleHand = ProcessInfo.processInfo.arguments.contains("-mahjongSingleHand")
        #else
        let picksSingleHand = false
        #endif
        _selectedLength = State(initialValue: picksSingleHand ? .singleHand : .tonpuu)
    }

    public var body: some View {
        VStack(spacing: 6) {
            // 局数・残り枚数は卓中央パネル（`MahjongCenterPanel`）が持ち、ドラは卓の上の見出し
            // （`doraHeader`）に出す。以前はここに同じ情報の白いステータスバーを重ねて出していたが、
            // 情報が100%重複しているうえ、画面上部の白い領域が無駄に広く見える一因になっていた
            // （会長指摘）ため撤去した。
            // 卓（対面・上家・下家の河 + 自分の河）は局の決着後もそのまま見えている方が自然なので、
            // 局面/リザルトの分岐の外に置く（実物の卓も清算が終わるまで牌は残ったまま）。
            // layoutPriority(1) は将棋の盤（ShogiView.board）と同じ考え方: 卓を優先して
            // 高さを確保させ、他の要素（手牌・アクション行・バナー）がそのぶん譲る。
            // これが無いと卓が伸び放題になり、画面下のバナー広告が画面外へ押し出されて
            // 見えなくなる／レイヤーが崩れて見える（会長のシミュレータ確認で発覚）。
            doraHeader
            mahjongTable
                .layoutPriority(1)
            // 卓（`mahjongTable`）は縦長の長方形（#927）で、画面の余った縦幅をすべて使い切るとは限らない。
            // 余りは手牌（またはリザルト）の下で吸収し、見出しと卓は画面上部に固定する（上寄せ）。
            // 一度は卓の上で吸収して下寄せにしたが、リザルトへの切り替えで卓とドラの見出しが
            // 上下に動いて見えたので戻した（会長指摘 2026-09-13）。
            if model.phase == .gameResult {
                gameResultCard.transition(.opacity)
                Spacer(minLength: 0)
            } else if model.phase == .handResult {
                handResultCard.transition(.opacity)
                Spacer(minLength: 0)
            } else {
                handOnTable.transition(.opacity)
                Spacer(minLength: 0)
            }
            // 会長指摘: リザルト画面でも「切る牌をタップしよう」が出ていて、打牌できない場面なのに
            // 打牌を促す文言が残っていた。対局中だけ出す。
            if isInPlay {
                HowToPlayHint(.mahjong, playLog: services.playLog)
            }
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .gameResult)
            BannerSlot(ads: services.ads)
        }
        // 局面 → リザルトの差し替えは、入れ替わる枝ではなく残り続ける親に置く（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        // ナビバーの既定の白背景がコンテンツのクリーム背景と食い違い、画面上部だけ白い帯に
        // 見えていた（会長指摘）。背景色を揃えて帯の境目を消す。
        .gameChrome(title: "麻雀", review: services.review, matchesNavigationBarBackground: true) {
            // 役は 30 種以上あり、覚えていないと何をねらうか決められない。遊び方シートの
            // 奥（`?` → くわしいルール）だと 2 タップかかるので、対局中 1 タップで開ける
            // 早見表をここに置く（#501。花札 #495 と同じ置き方）。ツールバーは `Label` を
            // アイコンだけに畳むので、文字を出すために `Text` を直接渡す。
            ToolbarItem(placement: .primaryAction) {
                Button { showYakuSheet = true } label: {
                    Text("役")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .accessibilityLabel("役の早見表")
            }
            // 対局を始めると東風戦を打ち切るかトビるまで抜けられなかった（会長QA・#638）。
            // 他ゲーム（将棋・囲碁・ナンプレ）と同じ位置・同じ絵柄で「新規対局」を置く。
            ToolbarItem(placement: .primaryAction) {
                Button { startNewGame() } label: {
                    Label("新規対局", systemImage: "plus.circle.fill")
                }
            }
        }
        .confirmationDialog(
            "新規対局しますか？",
            isPresented: $showConfirmNewGame,
            titleVisibility: .visible
        ) {
            // 長さもここで選べるようにする（#639）。開始シートは中断データがあると出ないため、
            // ここを「終了して新規対局」の 1 つだけにすると、対局中に一局戦へ切り替える経路が
            // どこにも無くなる（ハブへ戻っても中断データから同じ対局が再開する）。
            ForEach(MahjongGameLength.allCases) { option in
                Button("終了して\(option.title)", role: .destructive) { restartGame(length: option) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると今の持ち点と局の進行が失われます。この対局は成績に記録されません。")
        }
        // 役と点数は 3 行に収まらないので「くわしいルール」へ送る（#118）。
        .howToPlay(.mahjong) { MahjongRuleSheet() }
        .sheet(isPresented: $showYakuSheet) { MahjongYakuSheet() }
        .sheet(isPresented: $showStartSheet) {
            MahjongStartSheet(length: $selectedLength) {
                showStartSheet = false
                model.startGame(length: selectedLength)
                Task { await model.runCPUTurnsIfNeeded() }
            } onCancel: {
                // 「覗いてみたけど今はやめる」の退路（#352）。対局は始まっていないので
                // 記録・解析のイベントは何も発生しない（それらは `startGame()` だけが送る）。
                showStartSheet = false
                dismiss()
            }
            // スワイプで閉じると「シートだけ消えて空の卓が残る」ため引き続き無効。
            // 閉じる操作はキャンセル（ハブへ戻る）に一本化する。
            .interactiveDismissDisabled(true)
        }
        .task {
            #if DEBUG
            // 撮影・動作確認用（DEBUG 限定）: トビ終了のリザルト（復活ボタン）をタップ無しで出す（#338）。
            if ProcessInfo.processInfo.arguments.contains("-mahjongBustResult") {
                showStartSheet = false
                model.simulateBustResultForTesting()
                return
            }
            // 撮影・動作確認用（DEBUG 限定）: 和了リザルトの手牌開示（#351）を非対話で出す。
            if ProcessInfo.processInfo.arguments.contains("-mahjongWinResult") {
                showStartSheet = false
                model.simulateWinResultForTesting()
                return
            }
            // 撮影・動作確認用（DEBUG 限定）: 一局戦の終了リザルト（見出しが「一局戦終了」に
            // 変わることの確認。#639）。最後まで打たないと到達できない画面で、シミュレータは
            // 自動タップができないため、非対話でこの画面を出す経路が要る。
            if ProcessInfo.processInfo.arguments.contains("-mahjongSingleHandResult") {
                showStartSheet = false
                model.simulateFinalResultForTesting(length: .singleHand)
                return
            }
            // 撮影・動作確認用（DEBUG 限定）: 役の早見表（#501）を非対話で開く。
            // シミュレータはタップを自動化できず、中断データの注入では「シートが開いている」
            // 状態を作れないため、早見表はこの経路でしか撮れない。
            if ProcessInfo.processInfo.arguments.contains("-mahjongShowYaku") {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
                showYakuSheet = true
                return
            }
            // 撮影・動作確認用（DEBUG 限定）: 対局中の卓（= ツールバーに「新規対局」が並ぶ状態）と、
            // その確認ダイアログ（#638）。どちらもタップでしか到達できず、麻雀の中断データは
            // 山・手牌・河を丸ごと持つため外から注入するのも現実的でない。
            if ProcessInfo.processInfo.arguments.contains("-mahjongSkipStartSheet")
                || ProcessInfo.processInfo.arguments.contains("-mahjongConfirmNewGame") {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
                if ProcessInfo.processInfo.arguments.contains("-mahjongConfirmNewGame") {
                    startNewGame()
                }
                return
            }
            #endif
            // 中断から戻ったときに手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
        .task(id: model.turnKey) {
            await model.runCPUTurnsIfNeeded()
        }
        .onChange(of: model.playerHand) {
            // 手牌が変わったら選択（誤タップ防止の1タップ目）は必ず解除する。
            selectedTileID = nil
        }
        .onChange(of: model.currentPlayer) {
            selectedTileID = nil
        }
        .rewardedRescueAlerts(
            reviveRescue,
            notEarned: "復活できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "復活できませんでした",
                message: "広告を見ているあいだに対局が変わったため、復活は適用していません。復活の回数は減っていません。"
            )
        )
    }

    // MARK: - 新規対局（#638）

    /// 進行中なら確認を挟んでから配り直す。捨てるものが無い局面（開始前・決着後）は直接始める。
    ///
    /// ブロック崩しの「はじめから」（#515）は確認を出す前に球を止めるが、あれは反射神経を
    /// 使うゲームで、迷っているあいだに落球して状況が悪化するため。麻雀は**裏で CPU の手番が
    /// 進むだけ**で、待たされても打牌を迫られることはないので止めない（キャンセルすれば
    /// そのまま続けられ、確定すればどのみち全部配り直す）。
    private func startNewGame() {
        guard model.hasGameInProgress else {
            restartGame()
            return
        }
        showConfirmNewGame = true
    }

    /// 開始シートは通さない。選ぶ項目は対局の長さ（#639）だけで、それは確認ダイアログの
    /// ボタン側で選べるようにしてある（対局中の人に遊び方の読み物を再度出しても手数が増えるだけ）。
    ///
    /// - Parameter length: 焼き込む長さ。nil（開始前・決着後からの呼び出し）なら直前の対局と同じ。
    private func restartGame(length: MahjongGameLength? = nil) {
        if let length { selectedLength = length }
        model.startGame(length: length)
        Task { await model.runCPUTurnsIfNeeded() }
    }

    // MARK: - 雀卓

    /// 斜め上から見る雀卓（麻雀刷新 #736 / #737）。
    ///
    /// 幾何は `MahjongTableLayout`（純関数・`MahjongTableLayoutTests` で重なりと収まりを検査）、
    /// 描画は `MahjongTableView`。以前の `VStack`/`HStack` の自動フローと名前チップはやめ、
    /// 河・立て牌・副露・立直棒・中央パネル（点数・局・本場・供託）を遠近の写像で置く。
    /// 見た目の基準は `docs/ui-review/mahjong-3d/mock-v12.png`（会長承認 2026-09-13）。
    ///
    /// **自分の手牌一覧（タップ対象）だけはここで重ねる**。写像で位置を決めるが、牌の寸法と
    /// 当たり判定（44pt）は従来の `handOverviewOnTable` のまま（#378・#736 受け入れ条件）。
    /// `GeometryReader` + `aspectRatio(_:contentMode: .fit)` は将棋の盤と同じ手法。卓は縦長
    /// （幅 : 高さ = 1 : `MahjongTableLayout.aspect`。#927 で正方形から変えた）。
    private var mahjongTable: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height / MahjongTableLayout.aspect)
            let height = width * MahjongTableLayout.aspect
            // SwiftUI は最初のレイアウトで大きさ 0 を渡してくる。その 1 回で `MahjongTableLayout` が
            // 0 ÷ 0 の NaN を作り、牌の幅・位置に広がって幅 393pt 以下の端末で落ちていた
            // （v1.1.5 開発版。会長の実機と当番の iPhone SE で再現）。一辺が 0 以下なら何も描かない。
            if width > 0 {
                let layout = MahjongTableLayout(size: CGSize(width: width, height: height))
                ZStack(alignment: .topLeading) {
                    Group {
                        MahjongTableView(scene: tableScene, layout: layout)
                        if isInPlay {
                            let overview = layout.handOverview
                            handOverviewOnTable(width: overview.width, tileWidth: overview.tileWidth)
                                .position(overview.center)
                        }
                    }
                    // 河のアニメーションが止まらないという指摘のため、卓の中身への暗黙アニメーションを
                    // 一切禁止する（実物の牌もアニメーションはしない）。打牌の動き（#738）はこの外側の
                    // 飛行レイヤーだけが持つ。
                    .transaction { $0.animation = nil }
                    if let flight = discardFlight {
                        MahjongDiscardFlightView(flight: flight, progress: discardFlightProgress,
                                                 tileWidth: layout.riverTileWidth)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                .frame(width: geo.size.width, height: geo.size.height)
                .onChange(of: model.discards.map(\.count)) { old, new in
                    startDiscardFlight(old: old, new: new, layout: layout)
                }
            }
        }
        .aspectRatio(1 / MahjongTableLayout.aspect, contentMode: .fit)
    }

    /// ドラ表示の見出し。卓のすぐ上に 1 行の HUD として置く（会長指摘 2026-09-13。以前は卓の
    /// 左上の角に外側から重ねていたが、卓を画面下へ寄せるのに合わせて見出しに独立させた）。
    /// iPad では卓と一緒に大きくなるよう、行の幅（＝卓の幅）から縮尺を取る。
    private var doraHeader: some View {
        HStack {
            doraChip(scale: doraHeaderWidth > 0 ? doraHeaderWidth / 361 : 1)
            Spacer(minLength: 0)
        }
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { doraHeaderWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in doraHeaderWidth = w }
            }
        )
    }

    /// ドラ表示。参考画像と同じく画面左上の HUD。牌が複数（カン）なら並べる。
    private func doraChip(scale s: CGFloat) -> some View {
        HStack(spacing: 5 * s) {
            Text("ドラ")
                .font(.system(size: 11 * s, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Fixed.ink)
            ForEach(Array(model.doraIndicators.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: 20 * s, height: 27 * s)
            }
        }
        .padding(.horizontal, 9 * s).padding(.vertical, 5 * s)
        .background(Capsule().fill(.white).shadow(color: .black.opacity(0.18), radius: 5, y: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ドラ表示牌、" + model.doraIndicators.map { $0.displayName }.joined(separator: "、"))
    }

    /// 河が 1 枚増えた家を見つけて、その 1 枚を出発点から着地点へ飛ばす（#738）。
    /// 同時に複数の家が増えることは無い（打牌は 1 手番に 1 枚）。局の開始で全員 0 に戻るときは何もしない。
    private func startDiscardFlight(old: [Int], new: [Int], layout: MahjongTableLayout) {
        // 河が減った＝局が変わった（または中断から作り直した）。飛行中の 1 枚は捨てて、
        // 新しい局の牌を隠したまま残さない（タイミングに頼らず構造で塞ぐ・verifier 申し送り）。
        if zip(old, new).contains(where: { $1 < $0 }) {
            discardFlight = nil
            return
        }
        guard old.count == new.count,
              let seat = new.indices.first(where: { new[$0] == old[$0] + 1 }),
              let tile = model.discards[seat].last else { return }
        let index = new[seat] - 1
        let slot = layout.riverSlot(seat: seat, index: index)
        // 自分の打牌は、切った牌が一覧にあった場所から飛ぶ（会長指摘 2026-09-13「真ん中ではなく端っこから」）
        let from: CGPoint
        if seat == MahjongModel.humanIndex, let s = pendingDiscardSlot {
            from = layout.handOverviewTileCenter(index: s.index, count: s.count)
        } else {
            from = layout.discardOrigin(seat: seat)
        }
        pendingDiscardSlot = nil
        discardFlight = MahjongDiscardFlight(
            seat: seat, index: index, tile: tile,
            from: from, to: slot.center,
            rotation: slot.rotation, scale: slot.scale
        )
        discardFlightProgress = 0
        withGameAnimation(.easeOut(duration: MahjongDiscardFlight.duration)) {
            discardFlightProgress = 1
        }
        discardFlightSerial += 1
        let serial = discardFlightSerial
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(MahjongDiscardFlight.duration * 1000) + 20))
            // 次の打牌が先に始まっていたら（通し番号が進んでいたら）、そちらが片付ける
            if discardFlightSerial == serial { discardFlight = nil }
        }
    }

    /// 卓に描く値を `MahjongModel` から切り出す。CPU の手牌は枚数だけ（絵柄は伏せる）。
    /// 自分の枚数は手牌一覧（`handOverviewOnTable`）と同じ数え方（ツモ牌は `playerDrawnTile`）にする。
    /// 副露の置き場（一覧の右隣。#960）がこの枚数から決まるので、ずれると副露が手牌に重なる。
    private var tableScene: MahjongTableScene {
        let n = MahjongModel.playerCount
        var counts = [Int](repeating: 0, count: n)
        for i in 0..<n where i != MahjongModel.humanIndex {
            counts[i] = model.hands[i].tiles.count
                + (model.currentPlayer == i && model.drawnTile != nil && model.phase == .playing ? 1 : 0)
        }
        counts[MahjongModel.humanIndex] = model.playerHand.tiles.count + (model.playerDrawnTile != nil ? 1 : 0)
        return MahjongTableScene(
            discards: model.discards,
            melds: model.melds,
            handCounts: counts,
            riichi: model.riichi,
            scores: model.scores,
            names: (0..<n).map { model.playerName($0) },
            seatWinds: (0..<n).map { model.seatWind($0) },
            currentPlayer: model.phase == .playing ? model.currentPlayer : nil,
            roundNumber: model.displayedRoundNumber,
            honba: model.displayedHonba,
            riichiSticks: model.riichiSticks,
            remainingTiles: model.remainingTiles,
            doraIndicators: model.doraIndicators,
            hiddenDiscardSeat: discardFlight?.seat,
            hiddenDiscardIndex: discardFlight?.index
        )
    }

    /// 対局中（決着していない）か。「切る牌をタップしよう」のヒントや手牌一覧など、
    /// 打牌操作に関わる要素はリザルト画面では意味を持たないのでここで隠す。
    ///
    /// 会長指摘（2026-08-25）: 名前・点数は以前リザルト中だけ隠していたが、CPUも含めて
    /// 「常に固定で出ていてほしい」とのことなので、表示・非表示にはもう使わない
    /// （#736 以降は中央パネル `MahjongCenterPanel` が常時 4 家の風・点数を出す）。
    private var isInPlay: Bool {
        model.phase == .playing || model.phase == .ronOffer || model.phase == .callOffer
    }

    // MARK: - 手牌一覧（卓上）

    private static let handOverviewSpacing: CGFloat = MahjongTableLayout.handOverviewSpacing
    /// 一覧の牌は河と同じ大きさ（iPhone で幅 18pt・高さ 25pt ほど）で、そのままでは Apple 推奨の 44pt に届かない。
    /// **レイアウトは変えずに当たり判定だけ**この高さまで縦に広げる（`handOverviewTile`）。
    private static let handOverviewMinHitHeight: CGFloat = 44
    /// 一覧で選択中の牌を持ち上げる量。下部（`tableHandLift` 側の -10pt）と同じ言語だが、
    /// 牌が小さく行の高さも詰まっているので控えめにする。
    private static let handOverviewLift: CGFloat = 3

    /// 卓の上（フェルトの手前の縁）に置く、手牌14枚を河の牌と同じ大きさで一目で見渡せる一覧。
    ///
    /// **この一覧からも打牌できる**（#378・会長発案）。以前はタップを卓下部の `handOnTable`
    /// （大きい牌・横スクロール）に一本化し、こちらは視認専用にしていたが、一覧で切りたい牌を
    /// 見つけても下部までスクロールして探し直さないと切れず二度手間だった。牌の ID を下部と
    /// 共有する（`MahjongHandTap.handTileID(index:)`）ので、**どちらの面でタップしても選択は同じ**で、
    /// 2タップ目の確定もどちらの面からでも成立する。
    ///
    /// 読み上げは従来どおり下部に一本化する（この一覧は `accessibilityHidden`。VoiceOver 利用時は
    /// 同じ操作が下部の `handTile` にラベル・ヒント付きで揃っている）。
    private func handOverviewOnTable(width: CGFloat, tileWidth: CGFloat) -> some View {
        let hand = model.playerHand.tiles
        let drawn = model.playerDrawnTile
        // 切れる牌の判定は手牌の枚数ぶん走るので、1 回だけ求めて配る（`handOnTable` と同じ考え方）。
        let discardable = model.discardableTiles
        let tileCount = hand.count + (drawn != nil ? 1 : 0)
        let totalSpacing = Self.handOverviewSpacing * CGFloat(max(0, tileCount - 1))
        // 牌の幅は河の牌と同じ（`MahjongTableLayout.handOverview`。会長指摘 2026-09-13）。
        // 幅は 14 枚が収まるように決まっているので普段は縮まないが、念のため収まる幅に丸める。
        let rawWidth = tileCount > 0 ? (width - totalSpacing) / CGFloat(tileCount) : tileWidth
        let tileWidth = max(10, min(tileWidth, rawWidth))
        let tileHeight = tileWidth * MahjongTableLayout.tileAspect
        return HStack(spacing: Self.handOverviewSpacing) {
            ForEach(Array(hand.enumerated()), id: \.offset) { index, tile in
                handOverviewTile(
                    tile, id: MahjongHandTap.handTileID(index: index),
                    width: tileWidth, height: tileHeight, isDrawn: false, discardable: discardable
                )
            }
            if let drawn {
                handOverviewTile(
                    drawn, id: MahjongHandTap.drawnTileID,
                    width: tileWidth, height: tileHeight, isDrawn: true, discardable: discardable
                )
            }
        }
        // 左詰め（#960）: 1 枚目の位置がツモの有無で動かず、鳴いて減った右側に副露（`MahjongTableView.inlineMelds`）
        // が入る。牌の中心は `MahjongTableLayout.handOverviewTileCenter` と同じ計算。
        .frame(width: width, alignment: .leading)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }

    /// 一覧の 1 枚。打牌の判定は下部の `handTile` と同じ `MahjongHandTap` を通す。
    private func handOverviewTile(
        _ tile: MahjongTile, id: String, width: CGFloat, height: CGFloat,
        isDrawn: Bool, discardable: Set<MahjongTile>
    ) -> some View {
        let canDiscard = discardable.contains(tile)
        let isSelected = selectedTileID == id
        // 当たり判定だけを縦へ伸ばす: 余白を足してから `contentShape` を取り、同じ量を負の余白で
        // 引き戻す。牌そのものの大きさも行の高さも変わらないまま、指の当たる範囲だけが広がる。
        let hitPadding = max(0, (Self.handOverviewMinHitHeight - height) / 2)
        return MahjongTileView(
            tile: tile, width: width, height: height,
            // 立直中に切れない牌は下部と同じく暗く落とす。ここで見分けが付かないと
            // 「一覧をタップしても反応しない牌がある」という理由の分からない挙動になる。
            isBlocked: model.isPlayerTurn && !canDiscard,
            isSelected: isSelected,
            isHinted: isDrawn
        )
        .offset(y: isSelected ? -Self.handOverviewLift : 0)
        .padding(.vertical, hitPadding)
        .contentShape(Rectangle())
        .padding(.vertical, -hitPadding)
        .onTapGesture {
            handleHandTap(tile, id: id, canDiscard: canDiscard, scrollsBottomHand: true)
        }
        .disabled(!model.isPlayerTurn)
    }

    // MARK: - 手牌

    /// 会長指摘「持ち牌もグリーンの卓の上に一列に並べて見てほしい」「横スクロールは維持して」への対応。
    /// 以前の 7列×2段の白カードをやめ、卓と同じ緑フェルトの帯に単列（横スクロール）で並べる。
    /// 名前・風・点数は卓の中央パネル（`MahjongCenterPanel`・#737）に一本化したので、ここでは持たない。
    ///
    /// **「ルーレット現象」の正体**（Fable・Opus の並行調査で特定）: アニメーションでも
    /// ScrollView でもなく、**CPU のツモ牌が自分の手牌14枚目として表示されるデータバグ**だった。
    /// `model.drawnTile` は全員共有のプロパティ（`draw(for:)` が誰の手番でも同じ変数へ書く）で、
    /// CPU の手番中（1人あたり `cpuDelay` ≒520ms）も値が入れ替わり続ける。ここを手番の判定なしに
    /// 描いていたため、自分が1枚切るたびに右端の枠が CPU1→CPU2→CPU3 のツモ牌へパタパタと
    /// 4回連続で切り替わって見えていた。これは本物のデータ変化なので、`transaction { animation
    /// = nil }` でも identity 安定化でも ScrollView の有無でも止まらなかった
    /// （過去の対策が軒並み効かなかった理由）。`MahjongModel.playerDrawnTile` で自分の手番以外は
    /// nil を返すようにして解消した。
    ///
    /// 牌・間隔・ツモ牌の隙間は `MahjongHandRowMetrics`（iPhone は 34×46pt 固定、iPad は捨て牌より小さくならないよう相似に広げる・#715）。
    private var handRowMetrics: MahjongHandRowMetrics { .make(layout: adaptiveLayout) }
    /// 選択時に牌を -10pt 持ち上げる演出が ScrollView の上端で切れないための余白。
    private static let tableHandLift: CGFloat = 12

    private var handOnTable: some View {
        // 切れる牌の判定は手牌の枚数ぶん走るので、1 回だけ求めて配る（#190 と同じ考え方）。
        let discardable = model.discardableTiles
        let waits = model.playerWaits
        // model.playerHand.tiles を直接使う（常にソート済み）。以前は差分適用のローカル state を
        // 挟んでいたが、末尾に追加するだけだとソート順が崩れて「並び替えが効かない」不具合になった。
        let hand = model.playerHand.tiles
        let drawn = model.playerDrawnTile
        let metrics = handRowMetrics
        return VStack(spacing: 6) {
            // 卓上の一覧（`handOverviewOnTable`）から選んだ牌はこの行の表示範囲外にあることが
            // 多いので、そこまで送れるように `ScrollViewReader` で包む（#378）。
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: metrics.spacing) {
                        // identity は **配列の位置**（`\.offset`）にする。牌の値を identity にすると、
                        // 途中の1枚が抜けて別の牌が別の位置に挿さったとき「生き残った牌が別スロットへ
                        // 移動した」と SwiftUI に解釈され、横滑りを補間できる状態になってしまう
                        // （Opus 指摘）。手牌は毎回ゼロから並べ直す配列なので、位置 identity にすれば
                        // 各スロットは「同じ View の中身が差し替わるだけ」になり、動きようがない。
                        // `.id` に渡す値も同じ位置由来なので、スクロールの宛先を足しても
                        // identity は動かない（値が変われば identity が切れる点に注意）。
                        ForEach(Array(hand.enumerated()), id: \.offset) { index, tile in
                            let id = MahjongHandTap.handTileID(index: index)
                            handTile(tile, id: id, isDrawn: false, discardable: discardable)
                                .id(id)
                        }
                        Spacer().frame(width: metrics.drawnGap)
                        // ツモ牌が無い間も同じ幅の透明プレースホルダーを置き、コンテンツの総幅を
                        // 常に一定に保つ。ツモ牌の出入りで ScrollView の contentSize が変わると
                        // UIScrollView 側がスクロール位置を自前で補正することがあるため、幅そのものを
                        // 固定してその発火条件自体を無くす。
                        ZStack {
                            Color.clear
                            if let drawn {
                                handTile(
                                    drawn, id: MahjongHandTap.drawnTileID,
                                    isDrawn: true, discardable: discardable
                                )
                            }
                        }
                        .frame(width: metrics.tileWidth, height: metrics.tileHeight)
                        // ツモ牌が無い間もこの枠は残るので、スクロールの宛先は常に解決できる。
                        .id(MahjongHandTap.drawnTileID)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, Self.tableHandLift)
                    .padding(.bottom, 6)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .defaultScrollAnchor(.leading)
                .frame(height: metrics.tileHeight + Self.tableHandLift + 6)
                // 並び替え・出し入れは瞬時に反映するだけにする（雀卓側と同じ考え方）。
                // 選択（浮き上がり）演出は handTile 側で個別に `.animation` を付け直しているので、
                // ここで止めても影響しない。
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .onChange(of: overviewScrollTarget) {
                    guard let target = overviewScrollTarget else { return }
                    // アニメーションは付けない。この行は「ルーレット現象」（上のコメント参照）の
                    // 反省で徹底して動きを止めてある場所で、ここだけ横滑りを足すと同じ見え方に
                    // 逆戻りする。瞬時に位置が変わるだけなら Reduce Motion とも整合する。
                    proxy.scrollTo(target, anchor: .center)
                    overviewScrollTarget = nil
                }
            }
            // 副露は「卓の上においてほしい」（会長指摘）ため卓上の手牌一覧の右隣（`MahjongTableView.inlineMelds`。#960）
            // に置く。ここ（操作用のスクロール行）には置かない。
            hintLine(waits: waits)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        // 木の牌台（#738）。卓が木枠付きになったのに合わせる。
        // 影は台自身に付ける（外側に付けると手牌の1枚1枚にまで影が落ちる）。
        .background(MahjongWoodTray().shadow(color: .black.opacity(0.22), radius: 6, y: 3))
    }

    /// 会長指摘「誤タップ防止のため1タップでフォーカス、2タップ目で捨てる」への対応。
    /// 1回目のタップは選択（アウトライン＋浮き上がり）だけ。同じ牌をもう一度タップしたときだけ
    /// 実際に `model.discard` を呼ぶ。別の牌をタップした場合は選択を切り替えるだけで切らない。
    private func handTile(
        _ tile: MahjongTile, id: String, isDrawn: Bool, discardable: Set<MahjongTile>
    ) -> some View {
        let canDiscard = discardable.contains(tile)
        let isSelected = selectedTileID == id
        return MahjongTileView(
            tile: tile,
            width: handRowMetrics.tileWidth,
            height: handRowMetrics.tileHeight,
            isBlocked: model.isPlayerTurn && !canDiscard,
            isHinted: isDrawn
        )
        // 牌の絵柄そのものは、外側の選択アニメーションの影響を受けないようここで打ち切る
        // （無いと、選択解除と絵柄の差し替えが重なったときにクロスフェードして見える）。
        .transaction { $0.animation = nil }
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Theme.coral, lineWidth: isSelected ? 2.5 : 0)
        )
        .shadow(color: isSelected ? .black.opacity(0.3) : .clear, radius: isSelected ? 5 : 0, y: 3)
        .offset(y: isSelected ? -10 : 0)
        .gameAnimation(.spring(response: 0.22, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            // 下部をタップしたときは指の下でこの行が動くと邪魔なのでスクロールは追従させない。
            handleHandTap(tile, id: id, canDiscard: canDiscard, scrollsBottomHand: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MahjongAccessibility.handTileLabel(tile, isDrawn: isDrawn, isDiscardable: canDiscard)
        )
        .accessibilityHint("ダブルタップでこの牌を切ります")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            // VoiceOver の打牌もタップと同じ位置から飛ばす（verifier 指摘）
            pendingDiscardSlot = (index: MahjongHandTap.handIndex(of: id) ?? model.playerHand.tiles.count,
                                  count: model.playerHand.tiles.count + (model.playerDrawnTile != nil ? 1 : 0))
            model.discard(tile)
        }
        .disabled(!model.isPlayerTurn)
    }

    /// 卓上の一覧と卓下の操作行に共通の打牌タップ処理（#378）。判定そのものは `MahjongHandTap`
    /// に置いてあり、どちらの面から来ても同じ2段階（1タップ目=選択・2タップ目=打牌）を通る。
    ///
    /// `scrollsBottomHand` は「選んだ牌が下部の表示範囲外かもしれない」一覧側でだけ true にする。
    private func handleHandTap(
        _ tile: MahjongTile, id: String, canDiscard: Bool, scrollsBottomHand: Bool
    ) {
        switch MahjongHandTap.outcome(
            tappedID: id, selectedID: selectedTileID,
            isPlayerTurn: model.isPlayerTurn, isDiscardable: canDiscard
        ) {
        case .ignored:
            return
        case .select(let selected):
            selectedTileID = selected
            if scrollsBottomHand { overviewScrollTarget = selected }
        case .discard:
            // 選択解除と打牌を同じトランザクションにする。別々のフレームに分かれると
            // 「選択解除」→「手牌の入れ替え」の2段ジャンプに見えることがある（Opus指摘）。
            // 切る前に、この牌が一覧の何枚目にあったかを控える（打牌の飛び出し位置。ツモ牌は末尾）。
            let handCount = model.playerHand.tiles.count
            let overviewCount = handCount + (model.playerDrawnTile != nil ? 1 : 0)
            pendingDiscardSlot = (
                index: MahjongHandTap.handIndex(of: id) ?? handCount,
                count: overviewCount
            )
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTileID = nil
                model.discard(tile)
            }
        }
    }

    /// 手牌の下に出す 1 行の案内（#190 の設定に従う）。
    @ViewBuilder
    private func hintLine(waits: [MahjongTile]) -> some View {
        let message: String? = {
            if model.isDeclaringRiichi { return "立直します。切る牌を選んでください" }
            if model.isPlayerFuriten && !waits.isEmpty { return "フリテンです（ツモでのみ和了できます）" }
            if !waits.isEmpty {
                // ツモ牌を除いた 13 枚の待ちなので、条件つきの言い方にする（`playerWaits` を参照）。
                return "ツモ切りすると " + waits.map(\.displayName).joined(separator: "・") + " 待ち"
            }
            return nil
        }()
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(message)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(model.isPlayerFuriten ? Theme.inkSub : Theme.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - リザルト

    private var handResultCard: some View {
        VStack(spacing: 8) {
            Text(handResultTitle)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Theme.coral)
            if let result = model.handResult, result.kind != .exhaustiveDraw {
                Text("\(result.han)飜 \(result.fu > 0 ? "\(result.fu)符 " : "")\(result.limitName ?? "")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                VStack(spacing: 3) {
                    ForEach(Array(result.yaku.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }
                Text("\(result.gainedPoints)点")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.teal)
                // 和了者の手を開く（#351）。何に振り込んだか・どんな手だったかを学べるようにする。
                if let tiles = result.winningHand, let winTile = result.winningTile {
                    winningHandRow(
                        tiles: tiles, melds: result.winningMelds ?? [], winningTile: winTile
                    )
                }
                if let ura = result.uraDoraIndicators, !ura.isEmpty {
                    uraDoraRow(ura)
                }
            } else if let result = model.handResult {
                Text(
                    result.tenpaiPlayers.isEmpty
                        ? "全員ノーテンです"
                        : "聴牌: " + result.tenpaiPlayers.map { model.playerName($0) }.joined(separator: "・")
                )
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            }
            scoreTable
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 和了者の手（門前 + 副露 + 和了牌）。「なぜ負けたか」を学べるようにリザルトで開く（#351）。
    /// 和了牌は `isHinted` のハイライトで半歩離して並べ、どれで和了ったかをひと目で分かるようにする。
    private func winningHandRow(
        tiles: [MahjongTile], melds: [MahjongCall], winningTile: MahjongTile
    ) -> some View {
        let sorted = tiles.sorted { MahjongTileOrder.index(of: $0) < MahjongTileOrder.index(of: $1) }
        // 門前13枚 + 和了牌でもカード幅（約300pt）に収まる小ささ。副露があるぶん門前は減るので
        // これより横に伸びることはない。
        let tileWidth: CGFloat = 17
        let tileHeight: CGFloat = 23
        return HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, tile in
                    MahjongTileView(tile: tile, width: tileWidth, height: tileHeight)
                }
            }
            if !melds.isEmpty {
                MahjongMeldRow(melds: melds, tileWidth: tileWidth, showsBadge: false)
            }
            MahjongTileView(tile: winningTile, width: tileWidth, height: tileHeight, isHinted: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "和了した手: "
                + sorted.map(\.displayName).joined(separator: "、")
                + "、和了牌は \(winningTile.displayName)"
        )
    }

    /// 立直で和了ったときだけ開示する裏ドラ表示牌（#351）。卓中央のドラ表示と同じ牌サイズ。
    private func uraDoraRow(_ tiles: [MahjongTile]) -> some View {
        HStack(spacing: 4) {
            Text("裏ドラ")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                MahjongTileView(tile: tile, width: 14, height: 19)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("裏ドラ表示牌: " + tiles.map(\.displayName).joined(separator: "、"))
    }

    /// 会長指摘「誰が誰に点を振り込んだかわかるようにしてほしい」への対応。ロンは放銃した人が
    /// 一意に決まるので、タイトルに「{放銃した人} → {和了した人}」を添える。ツモは複数人が
    /// 別々の額を払うため、単一の矢印では表せない。下の `scoreTable` 側で全員の点数の動きを
    /// 一覧できるようにして補う。
    private var handResultTitle: String {
        guard let result = model.handResult else { return "" }
        let winnerName = model.playerName(result.winner ?? 0)
        switch result.kind {
        case .exhaustiveDraw: return "流局"
        case .tsumo:  return "\(winnerName)のツモ"
        case .ron:
            guard let loser = result.loser else { return "\(winnerName)のロン" }
            return "\(model.playerName(loser)) → \(winnerName)のロン"
        }
    }

    /// 終わり方は3種類あり、東2局で突然終わっても理由が読めるよう見出しを分ける（#352）。
    /// 打ち切りの見出しは対局の長さで変える（#639。一局戦で「東風戦終了」と出ると嘘になる）。
    private var gameResultTitle: String {
        switch model.gameEndReason {
        case .busted:    return "トビで終了"
        case .agariYame: return "アガリやめで終了"
        case .completedAllRounds, nil: return "\(model.gameLength.title)終了"
        }
    }

    private var gameResultCard: some View {
        VStack(spacing: 10) {
            Text(gameResultTitle)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.coral)
            if let place = model.playerPlace {
                Text("あなたは \(place + 1)位")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.offset) { place, player in
                    HStack {
                        Text("\(place + 1)位")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                            .frame(width: 36, alignment: .leading)
                        Text(model.playerName(player))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(model.scores[player])点")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }
            }
            RecordLabel(model.recordResult)
            if model.canReviveAfterBust { reviveButton }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .popCard(corner: Theme.cornerSmall)
    }

    /// トビで終わったときだけ出る復活導線（#338）。ポーカー・ブラックジャックの
    /// 「広告を見てチップ回復」と同じ形（リザルト内のボタン・視聴完了時のみ効果・失敗は #64 統一アラート）。
    private var reviveButton: some View {
        Button {
            // 連打ガードと失敗アラートは共通側が持つ（#526）。広告と復活は
            // `reviveAfterAd()` が 1 本で受け持つのでモデル側の形のまま。
            // 見終えたのに対局が入れ替わって適用しなかったときは「視聴しなかった」ではなく
            // `unavailable:` のアラートを出す（#814。ブラックジャック・ポーカーの #727 と同じ形）。
            reviveRescue.requestHandledByModel(withOutcome: {
                await model.reviveAfterAd()
            }, whenGranted: {
                await model.runCPUTurnsIfNeeded()
            })
        } label: {
            // 「1半荘に1回」は VoiceOver のヒントだけでなく見た目にも出す（#352。
            // 書かないと2回目を期待して押す人が出る）。
            Label("広告を見て25,000点で復活（1半荘に1回）", systemImage: "play.rectangle.fill")
                .themeBody(16).frame(maxWidth: .infinity)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.yellow)
        .disabled(reviveRescue.isWatching)
        .accessibilityHint("広告を最後まで見ると25,000点で対局を続けられます。1半荘に1回だけです")
    }

    /// 会長指摘「誰が誰に点を振り込んだかわかるようにしてほしい」への対応。`pointChanges` で
    /// 全員ぶんの増減を出す。ツモのように払う人が複数いるケースも、タイトルの矢印1本では
    /// 表せないのでここで一覧にして補う。
    private var scoreTable: some View {
        VStack(spacing: 4) {
            ForEach(0..<MahjongModel.playerCount, id: \.self) { player in
                HStack {
                    Text(model.playerName(player))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Spacer()
                    if let change = model.handResult?.pointChanges[player], change != 0 {
                        Text(change > 0 ? "+\(change)" : "\(change)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(change > 0 ? Theme.teal : Theme.coral)
                    }
                    Text("\(model.scores[player])点")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(model.scores[player] < 0 ? Theme.coral : Theme.ink)
                        .frame(width: 66, alignment: .trailing)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 操作

    /// 会長指摘: 鳴きの選択肢（`MahjongCallBar`）が出ると、それまでの1行ボタンより背が高いぶん
    /// このセクション自体の高さが変わり、下のバナー広告などが動いて見える。全ケースに共通の
    /// 最小高さを持たせて、差を小さくする（1行の鳴き提示ならほぼ動かなくなる）。
    private static let actionAreaMinHeight: CGFloat = 72

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .ronOffer:
            HStack(spacing: 12) {
                actionButton("見逃す", color: Theme.fillMuted, foreground: .white) {
                    model.declineRon()
                    Task { await model.runCPUTurnsIfNeeded() }
                }
                actionButton("ロン", color: Theme.Fill.coral) { model.declareRon() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        case .callOffer:
            if let offer = model.callOffer {
                MahjongCallBar(
                    offer: offer,
                    onAccept: { call in
                        model.acceptCall(call)
                        Task { await model.runCPUTurnsIfNeeded() }
                    },
                    onDecline: {
                        model.declineCall()
                        Task { await model.runCPUTurnsIfNeeded() }
                    }
                )
                .frame(minHeight: Self.actionAreaMinHeight)
            }
        case .playing:
            HStack(spacing: 12) {
                if model.isDeclaringRiichi {
                    actionButton("やめる", color: Theme.fillMuted, foreground: .white) { model.cancelRiichiDeclaration() }
                } else {
                    actionButton("立直", color: Theme.Fill.purple, disabled: !model.canDeclareRiichi) {
                        model.declareRiichi()
                    }
                }
                // カンは出来るときだけ出す（常設すると押せないボタンが 3 つ並ぶ）。
                if model.canDeclareKan {
                    MahjongKanButton(options: model.availableSelfKans) { call in
                        model.declareKan(call)
                        Task { await model.runCPUTurnsIfNeeded() }
                    }
                }
                actionButton("ツモ", color: Theme.Fill.coral, disabled: !model.canDeclareTsumo) {
                    model.declareTsumo()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        case .handResult:
            // 一局戦（#639）はこの先に局が無いので「次の局へ」は嘘になる。東風戦の最終局・
            // アガリやめ・トビでも同じ状況なので、押した先に合わせて文言を差し替える。
            actionButton(
                model.concludesAfterCurrentResult ? "結果を見る" : "次の局へ",
                color: Theme.Fill.coral
            ) {
                model.advanceToNextHand()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        case .gameResult:
            actionButton("もう一度", color: Theme.Fill.coral) {
                model.startGame()
                Task { await model.runCPUTurnsIfNeeded() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        }
    }

    /// - Parameter foreground: 面（`color`）の上に載せる文字色。差し色の面には `Theme.onAccent`、
    ///   `fillMuted` のような濃い面には白を渡す（#220）。
    private func actionButton(
        _ title: String, color: Color, foreground: Color = Theme.onAccent,
        disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(foreground)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(disabled)
    }

    static let windNames = ["東", "南", "西", "北"]

}

// MARK: - Start Sheet

struct MahjongStartSheet: View {
    /// 選んだ対局の長さ（#639）。ここで選んだものが `startGame(length:)` で焼き込まれる。
    @Binding var length: MahjongGameLength
    let onStart: () -> Void
    /// キャンセル（ハブへ戻る）。12本中この1本だけ「入ったら戻れない」状態だった（#352）。
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("対局の長さ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    Picker("対局の長さ", selection: $length) {
                        ForEach(MahjongGameLength.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(length.summary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                VStack(alignment: .leading, spacing: 8) {
                    Text("ゲームの流れ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    ruleRow("1", flowSummary)
                    ruleRow("2", "1枚ツモって1枚切る。4面子+雀頭で和了")
                    ruleRow("3", "聴牌したら立直できます（1000点を供託）。門前のときだけ")
                    ruleRow("4", "他の人の捨て牌はポン・チー・カンで鳴けます（鳴くと立直はできません）")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                NavigationLink {
                    MahjongRuleSheet()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("ルールと役を見る")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSub)
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
                }

                Spacer()
                Button {
                    onStart()
                } label: {
                    Text("対局開始").themeBody(18).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("麻雀")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// 選んだ長さに合わせた 1 行目。何局打つかは遊ぶ前にいちばん知りたい情報なので、
    /// ピッカーの説明文と流れの 1 行目の両方に出す。
    private var flowSummary: String {
        switch length {
        case .tonpuu:
            return "CPU3人と東風戦（東1局〜東4局）。持ち点は25000点から"
        case .singleHand:
            return "CPU3人と一局戦（東1局のみ）。持ち点は25000点から"
        }
    }

    private func ruleRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.Fill.coral))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

// MARK: - Rule Sheet

struct MahjongRuleSheet: View {
    private let rules: [(String, String)] = [
        ("和了の形", "同じ牌3枚（刻子）か連番3枚（順子）を4組と、同じ牌2枚（雀頭）を1組そろえると和了です。ほかに七対子（対子7組）と国士無双もあります"),
        ("ツモとロン", "自分で引いた牌で和了すればツモ、他の人が切った牌で和了すればロンです"),
        ("役が要ります", "和了の形になっても、役が1つも無いと和了できません。立直・断幺九・役牌などが役です"),
        ("立直", "聴牌したら1000点を供託して宣言できます。以後は引いてきた牌をそのまま切ります（手牌は変えられません）。鳴いた手では宣言できません"),
        ("ポン・チー", "同じ牌が2枚あれば誰の捨て牌でもポン、連番であと2枚そろうときは上家（左の人）の捨て牌をチーできます。鳴くとその牌を含む面子を手牌の外に晒し、そのまま自分の番になって1枚切ります"),
        ("カン", "同じ牌4枚でカンできます。手の内の4枚なら暗槓、他の人の捨て牌でそろえば明槓、ポン済みの牌に4枚目を足せば加槓です。カンすると新しいドラがめくれ、王牌から1枚（嶺上牌）を引きます"),
        ("鳴くと何が変わるか", "立直・門前清自摸和・平和・一盃口・七対子は付かなくなり、三色同順・一気通貫・チャンタ・混一色などは1飜下がります。役牌のように鳴いても付く役をねらいます。暗槓だけは門前のままです"),
        ("フリテン", "自分の待ち牌を自分で捨てているとロンできません（ツモなら和了できます）"),
        ("流局", "山が尽きたら流局。聴牌していた人が3000点を分け合い、ノーテンの人が払います"),
        ("東風戦", "東1局から東4局までの4局。親が和了または聴牌で流局すると連荘して本場が増えます"),
        ("一局戦", "東1局だけを打って順位を決める短い対局です。親が和了っても連荘はせず、その局で終わります。成績は東風戦とは別に数えます"),
        ("この版の範囲", "半荘は次の版で追加します。立直したあとのカン・食い替えの禁止・流し満貫はまだ入っていません"),
    ]

    var body: some View {
        RuleListSheet(title: "ルールと役", rules: rules)
    }
}
