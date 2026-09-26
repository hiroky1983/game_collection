import SwiftUI
import Core
import MahjongTiles

public struct MahjongView: View {
    @State var model: MahjongModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    /// 卓の下の手牌の行を iPad で広げるため（#715。`MahjongHandRowMetrics`）。
    @Environment(\.adaptiveLayout) var adaptiveLayout
    @State private var showStartSheet = true
    /// 誤タップ防止: 1タップ目は選択（浮かせる演出）だけ、同じ牌をもう1回タップしたら実際に切る。
    /// 複数枚ある牌を区別できるよう `stableHandIDs` の合成ID（牌の値＋出現順）で管理する。
    /// ID は `MahjongHandTap.handTileID(index:)` / `.drawnTileID` で作り、卓上の一覧と
    /// 卓下の操作行で共有する（どちらでタップしても選択が同期する・#378）。
    @State var selectedTileID: String?
    /// 卓上の一覧（`handOverviewOnTable`）から選んだ牌を、卓下の横スクロール側でも
    /// 見える位置まで送るための合図（#378）。下部を直接タップしたときは指の下の行が動くと
    /// 邪魔になるので、一覧経由のときだけ立てる。送り終えたら nil に戻す。
    @State var overviewScrollTarget: String?
    /// トビ復活（#338）。ポーカー・ブラックジャックの「広告を見てチップ回復」と同じ持ち方。
    /// トビ復活のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var reviveRescue = RewardedRescue()
    @State private var extendRescue = RewardedRescue()
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
    @State var pendingDiscardSlot: (index: Int, count: Int)?
    /// 飛行の通し番号。後片付けは「自分が始めた飛行」だけを消す（内容が同じ別の飛行を誤って消さない）。
    @State private var discardFlightSerial = 0
    /// 開始シートで選んでいる対局の長さ（#639）。ここは「次の対局に使う設定」で、
    /// 進行中の対局が見ているのは `model.gameLength`（開始時に焼き込んだ値）のほう。
    @State private var selectedLength: MahjongGameLength
    /// ボタンから起こす CPU の手番。画面を離れたら止める（#1380。`.task` と違いボタンの Task は自動で止まらない）。
    @State private var cpuTask: Task<Void, Never>?

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
        // 復活ボタンは終局のリザルトにだけ出る（#780）。
        .rewardOffer(reviveRescue, for: .revival, isPresented: model.phase == .gameResult && model.canReviveAfterBust,
                     services: services, gameID: model.gameID)
        .rewardOffer(extendRescue, for: .continue, isPresented: model.phase == .gameResult && model.canExtendAfterLastPlace,
                     services: services, gameID: model.gameID)
        // 役は 30 種以上あり、覚えていないと何をねらうか決められない。遊び方シートの
        // 奥（`?` → くわしいルール）だと 2 タップかかるので、対局中 1 タップで開ける
        // 早見表を置く（#501。花札 #495 と同じ置き方）。
        // 対局を始めると東風戦を打ち切るかトビるまで抜けられなかった（会長QA・#638）ので新規対局も置く。
        .gameChrome(title: "麻雀", review: services.review,
                    reference: GameChromeReference { showYakuSheet = true },
                    newGame: GameChromeNewGame(.match, isDisabled: isWatchingRescueAd) {
                        startNewGame()
                    })
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
                runCPU()
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
        .onDisappear { cpuTask?.cancel() }
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
        .rewardedRescueAlerts(
            extendRescue,
            notEarned: "延長できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "延長できませんでした",
                message: "広告を見ているあいだに対局が変わったため、延長は適用していません。延長の回数は減っていません。"
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

    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    /// 開始シートは通さない。選ぶ項目は対局の長さ（#639）だけで、それは確認ダイアログの
    /// ボタン側で選べるようにしてある（対局中の人に遊び方の読み物を再度出しても手数が増えるだけ）。
    ///
    /// - Parameter length: 焼き込む長さ。nil（開始前・決着後からの呼び出し）なら直前の対局と同じ。
    private func restartGame(length: MahjongGameLength? = nil) {
        if let length { selectedLength = length }
        model.startGame(length: length)
        runCPU()
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

    // MARK: - 復活導線
    // 失敗アラート（`body`）と同じファイルに置く。`AdsTests` がファイル単位で宣言とアラートの数を突き合わせる。

    /// トビで終わったときだけ出る復活導線（#338）。ポーカー・ブラックジャックの
    /// 「広告を見てチップ回復」と同じ形（リザルト内のボタン・視聴完了時のみ効果・失敗は #64 統一アラート）。
    var reviveButton: some View {
        Button {
            // 連打ガードと失敗アラートは共通側が持つ（#526）。広告と復活は
            // `reviveAfterAd()` が 1 本で受け持つのでモデル側の形のまま。
            // 見終えたのに対局が入れ替わって適用しなかったときは「視聴しなかった」ではなく
            // `unavailable:` のアラートを出す（#814。ブラックジャック・ポーカーの #727 と同じ形）。
            reviveRescue.requestHandledByModel(withOutcome: {
                await model.reviveAfterAd()
            }, whenGranted: {
                runCPU()
            })
        } label: {
            // 「1対局に1回」は VoiceOver のヒントだけでなく見た目にも出す（#352。
            // 書かないと2回目を期待して押す人が出る）。
            Label("広告を見て25,000点で復活（1対局に1回）", systemImage: "play.rectangle.fill")
                .themeBody(16)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(reviveRescue.isWatching)
        .accessibilityHint("広告を最後まで見ると25,000点で対局を続けられます。1対局に1回だけです")
    }

    /// 東 4 局を終えて最下位だったときだけ出る延長導線（#1201）。トビ復活と同じ形で、
    /// 視聴完了のときだけ東 5 局を 1 局足す。得点は動かさない（1 対局 1 回まで）。
    var extendButton: some View {
        Button {
            extendRescue.requestHandledByModel(withOutcome: {
                await model.extendAfterAd()
            }, whenGranted: {
                runCPU()
            })
        } label: {
            Label("広告を見て東5局を追加（1対局に1回）", systemImage: "play.rectangle.fill")
                .themeBody(16)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(extendRescue.isWatching)
        .accessibilityHint("広告を最後まで見ると、東5局をもう1局だけ打てます。最下位のときに1対局に1回だけです")
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
                actionButton("見逃す", role: .skip) {
                    model.declineRon()
                    runCPU()
                }
                actionButton("ロン", role: .primary) { model.declareRon() }
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
                        runCPU()
                    },
                    onDecline: {
                        model.declineCall()
                        runCPU()
                    }
                )
                .frame(minHeight: Self.actionAreaMinHeight)
            }
        case .playing:
            // 立直・カン・ツモは出来るときだけ出す（会長指摘: 押せないボタンが常に並んでいた）。
            // 何も出せない間も同じ高さの空きを残し、ボタンの出入りで卓や広告が上下に動かないようにする。
            let actions = MahjongTurnActions(model: model)
            if actions.isEmpty {
                Color.clear.frame(height: Self.actionAreaMinHeight)
            } else {
                HStack(spacing: 12) {
                    if actions.showsCancelRiichi {
                        actionButton("やめる", role: .skip) { model.cancelRiichiDeclaration() }
                    }
                    if actions.showsRiichi {
                        actionButton("立直", role: .declaration) { model.declareRiichi() }
                    }
                    if actions.showsKan {
                        MahjongKanButton(options: model.availableSelfKans) { call in
                            model.declareKan(call)
                            runCPU()
                        }
                    }
                    if actions.showsTsumo {
                        actionButton("ツモ", role: .primary) { model.declareTsumo() }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .popCard(corner: Theme.cornerSmall)
                .frame(minHeight: Self.actionAreaMinHeight)
            }
        case .handResult:
            // 一局戦（#639）はこの先に局が無いので「次の局へ」は嘘になる。東風戦の最終局・
            // アガリやめ・トビでも同じ状況なので、押した先に合わせて文言を差し替える。
            actionButton(
                model.concludesAfterCurrentResult ? "結果を見る" : "次の局へ",
                role: .primary
            ) {
                model.advanceToNextHand()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        case .gameResult:
            // 復活・延長の広告を読み込んでいる間は局を捨てさせない（#1381）。
            actionButton("もう一度", role: .primary, disabled: isWatchingRescueAd) {
                model.startGame()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
            .frame(minHeight: Self.actionAreaMinHeight)
        }
    }

    /// 役割（`GameButtonRole`）で色を決める横いっぱいのボタン（#1423）。色・角丸・44pt は `GameButtonStyle` が持つ。
    private func actionButton(_ title: String, role: GameButtonRole, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .disabled(disabled)
    }

    private var isWatchingRescueAd: Bool { reviveRescue.isWatching || extendRescue.isWatching }

    static let windNames = ["東", "南", "西", "北"]

}

/// 対局中（`.playing`）の操作行に出すボタン。判定はモデルの `canDeclare…` をそのまま使い、ここではルールを持たない。
struct MahjongTurnActions: Equatable {
    /// 立直の宣言牌を選んでいる途中の取り消し。
    var showsCancelRiichi: Bool
    var showsRiichi: Bool
    var showsKan: Bool
    var showsTsumo: Bool

    var isEmpty: Bool { !(showsCancelRiichi || showsRiichi || showsKan || showsTsumo) }

    @MainActor
    init(model: MahjongModel) {
        showsCancelRiichi = model.isDeclaringRiichi
        showsRiichi = !model.isDeclaringRiichi && model.canDeclareRiichi
        showsKan = model.canDeclareKan
        showsTsumo = model.canDeclareTsumo
    }
}
