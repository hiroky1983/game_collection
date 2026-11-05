import SwiftUI
import Core
import CoreOjisanPixel

/// おじさんちのねこさがし（#2250）のプレイ画面。家の間取りのマスをタップで ×（いない）を付け外しし、ダブルタップで猫を見つける。
public struct CatPuzzleView: View {
    let services: GameServices
    @State var model: CatPuzzleModel
    /// 最後に選んだ盤の大きさ（次に開いたときの開始シートの初期値）。
    @AppStorage("catPuzzleSize") private var preferredSize = CatPuzzleSize.normal.rawValue
    /// 最後に選んだ遊び方（ステージ／自由に遊ぶ・#3048）。開始シートの初期値。
    @AppStorage("catPuzzleMode") private var preferredMode = CatPuzzlePlayMode.stage.rawValue
    /// ステージのクリアのカードを「盤を見る」で閉じたか（新しい局で開け直す）。
    @State var clearCardClosed = false
    /// ステージのクリアの流れ（ライフが pt に → ランキング → モーダル・#3304）。クリアのたびに頭から。
    @State var clearFlow = CatPuzzleClearFlow()
    /// クリアのモーダルに載せる今日の順位（ランキングの段で読めたとき。#3329）。
    @State var clearStanding: (rank: Int, participants: Int)?
    /// 盤を押している指の状態（タップかスライドかの判定。#3116）。
    @State private var boardTouch = BoardTouch()
    /// 盤の拡大と移動（2 本指・#3238）。新しい局・盤の大きさが変わったら等倍に戻す。
    @State private var zoom = CatPuzzleBoardZoom()
    /// 開始シート（難易度を選ぶ）。続きの盤が無ければ最初に出す（他のゲームと同じ・会長 QA 2026-10-21・build 43）。
    @State var showNewGame: Bool
    /// 「＋」で途中の局をやめるかの確認。
    @State private var showConfirmNewGame = false
    /// 「やり直し」（印を全部消す）の確認。
    @State var showConfirmClear = false
    /// コンティニュー済みの局の負けカードを「盤を見る」で閉じたか（新しい局で開け直す）。
    @State var failCardClosed = false
    /// ヒントの広告救済（無料 1 回を使い切った後の 1 回。連打ガード・広告・失敗アラート。15パズル・ナンプレと同じ #526）。
    @State var hintRescue = RewardedRescue()
    /// 「猫を 1 匹教える」の広告の段取り（ステージだけ・#3203。ヒントとは別の残りなので救済も別に持つ）。
    @State var teachRescue = RewardedRescue()
    /// コンティニュー（3 回目のミスで広告を見て続ける）の広告の段取り（#2780。ヒントとは別の救済として持つ）。
    @State private var continueRescue = RewardedRescue()
    /// 負けたあとの答え合わせで、これまでに盤へ出した「見つけていない猫」の数（1 匹ずつ増やす）。
    @State private var revealedGhosts = 0
    /// ヒントを上限まで使い切ったあとに押したときの一言を出している間（数秒で消える・#3048）。
    @State var showsHintUsedUp = false
    /// 鍵の部屋の外を触ったときの案内を出している間（数秒で消える・#3235）。
    @State var showsKeyLockedHint = false
    /// 鍵の猫を見つけた直後の「鍵が開いた」を出している間。
    @State var showsKeyOpened = false
    /// 鍵の面の説明を出しているか。初めて鍵の面に来たとき 1 回だけ（`CatPuzzleKeyIntro`）。
    @State private var showsKeyIntro = false
    @AppStorage(CatPuzzleKeyIntro.seenKey) private var keyIntroSeen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(services: GameServices) {
        self.services = services
        let saved = UserDefaults.standard.string(forKey: "catPuzzleSize").flatMap(CatPuzzleSize.init(rawValue:))
        // 開始シートで始めると `newGame` が数えるので、新規の盤の `game_start` は遅らせる。
        let model = CatPuzzleModel(services: services, size: saved ?? .normal, defersStart: true)
        _model = State(initialValue: model)
        // 続きの盤が無ければ、まず難易度を選んでもらう（ナンプレ・マインスイーパー・明かり消しと同じ）。
        _showNewGame = State(initialValue: Self.startsWithNewGameSheet(model))
    }

    /// 狙った局面を描くための入口（静止画の確認・テスト用）。
    /// `showsAnswers` は負けたあとの答え合わせ（見つけていない猫）を盤に出し終えた状態。
    init(services: GameServices, model: CatPuzzleModel, showNewGame: Bool = false, showsAnswers: Bool = false) {
        self.services = services
        _model = State(initialValue: model)
        _showNewGame = State(initialValue: showNewGame)
        _revealedGhosts = State(initialValue: showsAnswers ? model.unfoundCats.count : 0)
    }

    /// 開いたときに開始シートを出すか。中断データから再開した盤（印がある）なら出さずに続きを見せる。
    static func startsWithNewGameSheet(_ model: CatPuzzleModel) -> Bool {
        !model.hasProgressToLose
    }

    /// ミス 3 回の結果カードを出すか（#2904）。出すのは提案中（中でコンティニューかあきらめるかを選ぶ）と、
    /// コンティニュー済みの局が提案を挟まずに負けたとき（`closed` まで）だけ。あきらめたあとはもう出さない。
    static func showsFailCard(_ model: CatPuzzleModel, closed: Bool) -> Bool {
        model.isOfferingContinue || (model.isFailed && model.continueUsed && !closed)
    }

    /// 計時を止めておくか（開始シート・確認を出している間。遊び方・広告・背面は `gameTimerLifecycle` が止める）。
    static func holdsClock(showNewGame: Bool, showConfirmNewGame: Bool, showConfirmClear: Bool, showsKeyIntro: Bool = false) -> Bool {
        showNewGame || showConfirmNewGame || showConfirmClear || showsKeyIntro
    }

    /// 鍵の面の説明を出すか（鍵の面で、まだ見ていなくて、開始シート・問題の用意中でないとき）。
    static func wantsKeyIntro(_ model: CatPuzzleModel, seen: Bool, showNewGame: Bool) -> Bool {
        model.keyCat != nil && !seen && !showNewGame && !model.isPreparingStage
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            // 盤は残りの高さを Spacer と山分けしない（操作の段が増えた分だけ盤が縮むのを防ぐ）。
            // クリアのダイアログは最後の猫が出る演出を見せてから 1 拍（`CatPuzzleModel.clearCardDelay`）おいて重ねる。
            board
                // ステージの問題を裏で作っている間は盤の上に「用意しています」を重ねる（9×9 は数秒かかることがある）。
                .overlay { if model.isPreparingStage { preparingOverlay } }
                // 盤が切り替わる面に入ったら 1 回だけ短く出す（Reduce Motion では動かさずに出して消す）。
                .overlay {
                    if let size = model.boardAdvance {
                        CatPuzzleBoardAdvanceBanner(size: size)
                            .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                            .task(id: model.gameSerial) {
                                // VoiceOver には表示と同時に読み上げる（静的テキストは出ただけでは読まれない）。
                                AccessibilityNotification.Announcement(CatPuzzleStageProgressText.advanced(to: size)).post()
                                try? await Task.sleep(for: .seconds(1.6))
                                withGameAnimation { model.clearBoardAdvance() }
                            }
                    }
                }
                // ボーナスステージ（141 面目以降の 1 の位が 5）は始まったときに色を替えて 1 回出す。
                .overlay {
                    if let size = model.bonusIntro {
                        CatPuzzleBoardAdvanceBanner(bonusSize: size)
                            .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                            .task(id: model.gameSerial) {
                                AccessibilityNotification.Announcement(tr("ボーナスステージ（%@）", size.sizeLabel)).post()
                                try? await Task.sleep(for: .seconds(1.6))
                                guard !Task.isCancelled else { return }
                                withGameAnimation { model.clearBonusIntro() }
                            }
                    }
                }
                .rewardOffer(continueRescue, for: .continue, isPresented: model.isOfferingContinue,
                             services: services, gameID: CatPuzzleModel.gameID)
                // 広告のロード〜視聴中は盤に触れない（ナンプレと同じ。視聴後のヒントは盤の今の形から読み直す）。
                .disabled(hintRescue.isWatching || teachRescue.isWatching || continueRescue.isWatching)
                .layoutPriority(1)
            messageLine
            controlArea
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.catPuzzle, playLog: services.playLog)
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
        // 3 回目のミスで出すダイアログはこの結果カード 1 枚だけ。中に「広告を見てコンティニュー」と
        // 「あきらめて正解を見る」を並べ、あきらめたら盤に正解を出して終わる（もう 1 枚は重ねない・#2904）。
        // 盤（正方形）ではなく画面全体に重ねる。盤の高さだけでは SE でボタンまで見えないため（#2931）。
        .boardGameResultCardAboveBanner(isPresented: Self.showsFailCard(model, closed: failCardClosed)) { failCard }
        // クリアのカードも盤ではなく画面全体に重ねる。盤に重ねるとカードの方が背が高く、SE でスクロールになっていた（#3048）。
        // 最後の猫が出る演出を見せてから 1 拍（`CatPuzzleModel.clearCardDelay`）おいて出す。
        // 「次のステージへ」を押して次の面を作っている間はカードを下げ、盤の「問題を用意しています…」を見せる。
        .boardGameResultCardAboveBanner(isPresented: model.showsClearCard && !clearCardClosed && !model.isPreparingStage) { clearCard }
        .gameChrome(title: tr("おじさんちのねこさがし"), review: services.review,
                    newGame: GameChromeNewGame(.solo, isDisabled: hintRescue.isWatching || teachRescue.isWatching || continueRescue.isWatching) { requestNewGame() })
        .howToPlay(HowToPlayGuide.catPuzzle.illustrated(CatPuzzleHowToFigures.items).onboarding(CatPuzzleOnboarding.guide))
        .onChange(of: Self.wantsKeyIntro(model, seen: keyIntroSeen, showNewGame: showNewGame), initial: true) { _, wants in
            if wants { showsKeyIntro = true }
        }
        .sheet(isPresented: $showsKeyIntro, onDismiss: { keyIntroSeen = true }) {
            CatPuzzleKeyIntro { showsKeyIntro = false }
        }
        .sheet(isPresented: $showNewGame) {
            CatPuzzleNewGameSheet(initialMode: CatPuzzlePlayMode(rawValue: preferredMode) ?? .stage,
                                  initial: model.size, nextStage: model.savedStage,
                                  noMissBest: model.noMissBest,
                                  eventTotal: model.todayEventTotal,
                                  onOpenRanking: services.openGameCenter,
                                  makeRanking: { CatPuzzleRankingModel(reporter: services.gameCenter) }) { mode, size in
                showNewGame = false
                start(mode: mode, size: size)
            } onCancel: {
                showNewGame = false
                // 閉じて今の盤で遊ぶ。遅らせていた開始をここで数える。
                model.startPlayIfPending()
            }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { showNewGame = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                // ステージは秒数を持たないので、タイムには触れない（#3210）。
                Text(Self.showsClock(model) ? tr("途中で終了すると、いまの盤面とタイムが失われます。")
                                            : tr("途中で終了すると、いまの盤面が失われます。"))
            }
            anchor.confirmationDialog(tr("印を全部消しますか？"), isPresented: $showConfirmClear, titleVisibility: .visible) {
                Button(tr("全部消してやり直す"), role: .destructive) { withGameAnimation { model.reset() } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(Self.showsClock(model) ? tr("同じ問題を最初から解きます。タイムとミスはそのままです。")
                                            : tr("同じ問題を最初から解きます。ミスはそのままです。"))
            }
            // 前日のランキング 1〜3 位の特典を渡した直後の知らせ（#3256）。
            anchor.alert(tr("昨日のランキング %lld位！", model.dailyRewardCard?.rank ?? 0),
                         isPresented: Binding(get: { model.dailyRewardCard != nil },
                                              set: { if !$0 { model.dismissDailyRewardCard() } })) {
                Button(tr("OK")) { model.dismissDailyRewardCard() }
            } message: {
                Text(model.dailyRewardCard?.itemsText ?? "")
            }
        }
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: tr("ヒントを使えませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("ヒントを出せませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったか、盤面が変わったため、ヒントを出せませんでした。\nヒントの残り回数は減っていません。")
            )
        )
        .rewardedRescueAlerts(
            teachRescue,
            notEarned: tr("餌をあげられませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("餌をあげられませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったか、盤面が変わったため、猫をおびき出せませんでした。\n残り回数は減っていません。")
            )
        )
        .rewardedRescueAlerts(
            continueRescue,
            notEarned: tr("コンティニューできませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("コンティニューできませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったため、コンティニューできませんでした。")
            )
        )
        // 答えでないマスに赤い × が付いたら読み上げる（3 回目は結果カードが読み上げる）。
        .onChange(of: model.mistakes) { old, new in
            // 増えたときだけ（コンティニューでミスが戻ったときは読み上げない）。
            if new > old, model.lastWrongCell != nil, !model.isFailed, !model.isOfferingContinue {
                AccessibilityNotification.Announcement(
                    tr("そこに猫はいない。赤い×を置いた。ライフ %1$lld/%2$lld", model.mistakesRemaining, CatPuzzleModel.maxMistakes)
                ).post()
            }
        }
        .onChange(of: model.showsClearCard) { _, shows in
            if !shows {
                clearCardClosed = false
                clearFlow = CatPuzzleClearFlow()
                clearStanding = nil
            }
        }
        // 新しい局が始まったら、答え合わせで出した猫を片付ける。
        .onChange(of: model.isFailed) { _, failed in
            if !failed {
                revealedGhosts = 0
                failCardClosed = false
            }
        }
        // 負けたら、見つけていない猫を正解の場所に 1 匹ずつ出す（結果カードはあきらめる前に出し終えている）。
        .task(id: model.isFailed) {
            guard model.isFailed else { return }
            await revealUnfoundCats()
        }
        // 餌の皿は猫が出てから少しだけ見せて片付ける（#3304）。
        .task(id: model.lureToken) {
            guard model.lureCell != nil else { return }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withGameAnimation { model.clearLure() }
        }
        // 「この局のヒントは使い切りました」は数秒で消す。
        .task(id: showsHintUsedUp) {
            guard showsHintUsedUp else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withGameAnimation { showsHintUsedUp = false }
        }
        // 新しい局では前の局の鍵の案内を消す。
        .onChange(of: model.gameSerial) {
            showsKeyLockedHint = false
            showsKeyOpened = false
            zoom.reset()
        }
        // 鍵の部屋の外を触ったら、先に鍵の猫を見つけるよう数秒だけ案内する（盤の揺れは盤の側）。
        .task(id: model.lockedTouches) {
            guard model.lockedTouches > 0 else { return }
            withGameAnimation { showsKeyLockedHint = true }
            AccessibilityNotification.Announcement(tr("先に鍵の猫を見つけよう")).post()
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withGameAnimation { showsKeyLockedHint = false }
        }
        // 鍵の猫を見つけたら、鍵が開いたことを数秒だけ知らせる。
        .task(id: model.keyOpenings) {
            guard model.keyOpenings > 0 else { return }
            withGameAnimation { showsKeyLockedHint = false; showsKeyOpened = true }
            AccessibilityNotification.Announcement(tr("鍵が開いた！ ほかの部屋にも印を付けられる")).post()
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withGameAnimation { showsKeyOpened = false }
        }
        // 最後の猫を置いたら 1 拍おいてクリアのダイアログを出す。
        .task(id: model.isSolved) {
            guard let wait = model.clearCardWait else { return }
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled else { return }
            withGameAnimation { model.revealClearCardIfDue() }
        }
        // 計時は盤が出た時点から（会長 QA 2026-10-21・build 43）。開始シート・確認・遊び方・広告・背面の間は止め、
        // 画面を離れたら止め、戻ったら再開する（#375・#1734・#1857・#2406）。
        .gameTimerLifecycle(
            rescues: [hintRescue, teachRescue, continueRescue],
            isHeld: Self.holdsClock(showNewGame: showNewGame, showConfirmNewGame: showConfirmNewGame,
                                    showConfirmClear: showConfirmClear, showsKeyIntro: showsKeyIntro),
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
        // 前日のランキング 1〜3 位の特典（#3256）。順位の読み込みを待たせないよう、盤の準備とは別の task にする。
        .task {
            await model.claimDailyReward {
                await CatPuzzleDailyReward.lookup(reporter: services.gameCenter, now: model.eventNow())
            }
        }
        .task {
            // 未ログインで貯めたイベントの pt を、ログイン後に開いたときに送る（#3204）。
            model.submitEventTotalIfNeeded()
            #if DEBUG
            // 撮影・動作確認用: `-catpuzzleScenario <名前>` で開始シートを閉じ、狙った盤を作る（#3048）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-catpuzzleScenario"), i + 1 < args.count {
                showNewGame = false
                model.startPlayIfPending()
                await model.applyDebugScenario(args[i + 1])
            }
            #endif
            // 開始シートを出している間は動かさない（シートを閉じた時点で `gameTimerLifecycle` が動かす）。
            if !showNewGame { model.resumeTimerIfNeeded() }
        }
    }

    // MARK: - 上の帯

    /// ライフの表記（残り ♥・減ったぶん ♡。例: 1 回ミスして `♥♥♡`）。
    static func livesText(_ model: CatPuzzleModel) -> String {
        String(repeating: "♥", count: model.mistakesRemaining) + String(repeating: "♡", count: CatPuzzleModel.maxMistakes - model.mistakesRemaining)
    }

    /// 左に残りの猫（終局後は結果）、右にミス（「ミス 1/3」）・難易度・タイム。
    private var statusBar: some View {
        GameStatusBar {
            Text(model.isSolved ? tr("全員みつけた！")
                 : model.isFailed ? tr("%lld回まちがえた…", CatPuzzleModel.maxMistakes)
                 : tr("残り %lld匹", model.remainingCats))
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundStyle(model.isSolved ? Theme.tealText : model.isFailed ? Theme.coralText : Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } trailing: {
            // 右側は折り返さない（「0:00」が 2 行に割れないよう固定幅で勝たせる）。
            HStack(spacing: 6) {
                // ライフ（♥♥♡）。ミスのたびに 1 つ減り、0 で終わり（#3304）。1 つ減ったら色を変える。
                Text(Self.livesText(model))
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(model.mistakes > 0 ? Theme.coralText : Theme.inkSubText)
                    .accessibilityLabel(tr("ライフ %1$lld、あと%2$lld回のミスで終わり", model.mistakesRemaining, model.mistakesRemaining))
                Text(tr("・")).foregroundStyle(Theme.inkSubText).accessibilityHidden(true)
                // ステージは面の番号、自由に遊ぶは難易度。
                Text(model.stage.map { tr("ステージ %lld", $0) } ?? model.size.label)
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(Theme.inkSubText)
                    .accessibilityLabel(model.stage.map { tr("ステージ %lld", $0) } ?? tr("難易度 %@", model.size.label))
                // ステージは秒数を出さない（#3210）。自由に遊ぶだけ時計を置く。
                if Self.showsClock(model) {
                    Text(tr("・")).foregroundStyle(Theme.inkSubText).accessibilityHidden(true)
                    GameClockLabel(RecordFormat.time(model.elapsedSeconds), elapsedSeconds: model.elapsedSeconds)
                }
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 盤

    /// 盤の枠の内側の余白。
    static let boardInset: CGFloat = 8

    /// 1 マスの一辺。12×12 でも iPhone SE（幅 375pt・左右の余白 16pt ずつ）で 26pt 以上になる（#3201）。
    static func cellSide(boardSide: CGFloat, side n: Int) -> CGFloat {
        max(1, (boardSide - boardInset * 2) / CGFloat(n))
    }

    private var board: some View {
        GeometryReader { geo in
            let n = model.puzzle.side
            let inset = Self.boardInset
            let boardSide = min(geo.size.width, geo.size.height)
            let cellSide = Self.cellSide(boardSide: boardSide, side: n)
            // 拡大中は盤の絵とマスを大きく描き直して（ベクターのまま）、枠の中で動かす。タップの判定は等倍の座標へ戻して行う。
            let drawnCell = cellSide * zoom.scale
            let drawnInset = inset * zoom.scale
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                ZStack(alignment: .topLeading) {
                    CatPuzzleBoardCanvas(
                        puzzle: model.puzzle, marks: model.marks,
                        wrongCrosses: model.wrongCrosses, lastWrongCell: model.lastWrongCell,
                        hintCells: model.hintCells, hintCrosses: model.hintCrosses, lastHint: model.lastHint,
                        shakeToken: model.mistakes, isSolved: model.isSolved,
                        ghostCats: Array(model.unfoundCats.prefix(revealedGhosts)),
                        lureCell: model.lureCell,
                        keyRoom: model.keyRoom, keyLocked: model.isKeyLocked, cellSide: drawnCell
                    )
                    // 鍵の部屋の外を触ったら盤が短く揺れる（Reduce Motion では揺らさない）。
                    .phaseAnimator(CatPuzzleMotion.shakePhases, trigger: model.lockedTouches) { content, phase in
                        content.offset(x: reduceMotion ? 0 : phase * drawnCell * 0.12)
                    } animation: { _ in
                        reduceMotion ? nil : CatPuzzleMotion.shakeStep
                    }
                    .offset(x: drawnInset, y: drawnInset)
                    cells(cellSide: drawnCell, inset: drawnInset)
                }
                .offset(x: zoom.offset.x, y: zoom.offset.y)
                .frame(width: boardSide, height: boardSide, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            }
            .frame(width: boardSide, height: boardSide)
            .contentShape(Rectangle())
            .gesture(boardGesture(cellSide: cellSide, inset: inset))
            .overlay {
                CatPuzzleZoomGestureHost(
                    onBegan: { cancelBoardTouch() },
                    onPinch: { factor, center in zoom.zoom(by: factor, anchor: center, boardSide: boardSide) },
                    onPan: { delta in zoom.pan(by: delta, boardSide: boardSide) }
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if zoom.isZoomed {
                    zoomResetButton
                }
            }
            .onChange(of: boardSide) { zoom.reset() }
            .frame(maxWidth: .infinity, alignment: .center)
            .gameAnimation(.easeOut(duration: 0.15), value: model.marks)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 拡大中だけ盤の隅に出す「等倍に戻す」。押せる範囲 44pt は枠の中に収める。
    private var zoomResetButton: some View {
        Button {
            withGameAnimation { zoom.reset() }
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 14, weight: .bold)) // fixed-size: 32pt の丸に収める記号（図形のジオメトリに従う）
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.6)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .accessibilityLabel(tr("等倍に戻す"))
    }

    /// 2 本指の操作が始まったら、進行中の 1 本指の操作（スライド・タップ）を取りやめる。
    private func cancelBoardTouch() {
        guard boardTouch.start != nil else { return }
        if boardTouch.isSliding { model.endCrossDrag() }
        boardTouch.isSliding = false
        boardTouch.isCancelled = true
    }

    /// 盤を押している指の状態。指を置いた位置のマスと、スライドと決まったかを持つ。
    /// 参照型にして中身の書き換えでは View を再評価させない（`@State` の値型だと、指が動くたびに盤・マス n² 個を含む
    /// 画面全体の body が作り直されて、× の表示が遅れる・#3202）。
    private final class BoardTouch {
        var start: CGPoint?
        var startCell: Int?
        var isSliding = false
        /// 2 本指の操作に切り替わったので、この指が離れるまで 1 本指の操作として扱わない。
        var isCancelled = false

        func begin(at start: CGPoint, cell: Int?) {
            self.start = start
            startCell = cell
            isSliding = false
            isCancelled = false
        }

        func reset() {
            start = nil
            startCell = nil
            isSliding = false
            isCancelled = false
        }
    }

    /// 盤全体のタップとスライド（#3116）。指の動きがマスの一辺の `slideThreshold` 未満のまま離したらタップとして
    /// `tap(cell:)` へ、届いたらスライドとして通ったマスに続けて × を付ける・外す（向きは最初のマスで決まる）。
    private func boardGesture(cellSide: CGFloat, inset: CGFloat) -> some Gesture {
        let side = model.puzzle.side
        let zoom = zoom
        let slide = CatPuzzleModel.slideDistance(cellSide: cellSide * zoom.scale)
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                if boardTouch.start != value.startLocation {
                    // 前の指が離れ損ねていたら（システムの割り込み）確定してから新しい指として扱う。
                    if boardTouch.isSliding { model.endCrossDrag() }
                    boardTouch.begin(
                        at: value.startLocation,
                        cell: CatPuzzleModel.cell(at: zoom.unzoomed(value.startLocation), side: side, cellSide: cellSide, inset: inset))
                }
                guard !boardTouch.isCancelled, let startCell = boardTouch.startCell else { return }
                let moved = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                if !boardTouch.isSliding, moved >= slide {
                    boardTouch.isSliding = true
                    withGameAnimation { model.beginCrossDrag(cell: startCell) }
                }
                if boardTouch.isSliding {
                    let cell = CatPuzzleModel.cell(at: zoom.unzoomed(value.location), side: side, cellSide: cellSide, inset: inset)
                    withGameAnimation { model.dragCross(to: cell) }
                }
            }
            .onEnded { value in
                defer { boardTouch.reset() }
                if boardTouch.isCancelled { return }
                if boardTouch.isSliding {
                    model.endCrossDrag()
                } else if let cell = boardTouch.startCell,
                          cell == CatPuzzleModel.cell(at: zoom.unzoomed(value.location), side: side, cellSide: cellSide, inset: inset) {
                    // 開始マスの上で離したときだけタップ（マスの端から余白へ出て離したら何もしない。旧 onTapGesture と同じ）。
                    withGameAnimation { model.tap(cell: cell) }
                }
            }
    }

    /// タップと VoiceOver 用のマスの並び。見た目は Canvas で描き、操作と読み上げだけをこちらに置く。
    /// タップは盤全体のジェスチャ（`boardGesture`）が 1 回ごとに `CatPuzzleModel.tap(cell:)` へ渡し、ダブルタップの判定はモデルが時刻と同じマスかで行う
    /// （`.onTapGesture(count: 2)` と排他にすると単タップが約 0.3 秒遅れるため・会長 QA 2026-10-22・build 45）。
    private func cells(cellSide: CGFloat, inset: CGFloat) -> some View {
        let n = model.puzzle.side
        return ForEach(0..<model.puzzle.cellCount, id: \.self) { index in
            // 盤が縮む新規の差分更新で旧盤面の添字が残っても範囲外を引かない（#3141）。
            if let state = model.cellState(at: index) {
                cellElement(index: index, n: n, room: state.room, mark: state.mark, cellSide: cellSide, inset: inset)
            } else {
                Color.clear.frame(width: cellSide, height: cellSide)
            }
        }
    }

    private func cellElement(index: Int, n: Int, room: Int, mark: CatPuzzleModel.Mark, cellSide: CGFloat, inset: CGFloat) -> some View {
        Color.clear
            .frame(width: cellSide, height: cellSide)
            .contentShape(Rectangle())
            .offset(x: inset + CGFloat(index % n) * cellSide, y: inset + CGFloat(index / n) * cellSide)
            .accessibilityElement()
            .accessibilityLabel(CatPuzzleAccessibility.cellLabel(
                row: index / n, col: index % n,
                roomName: room == model.keyRoom ? tr("%@（鍵の部屋）", CatPuzzleHouse.room(room).name) : CatPuzzleHouse.room(room).name,
                mark: mark,
                isConflict: model.wrongCrosses.contains(index),
                isHint: model.hintCells.contains(index) || model.hintCrosses.contains(index),
                isUnfoundCat: model.isUnfoundCat(cell: index)
            ))
            .accessibilityHint(model.isOver ? "" : model.isLockedOut(cell: index)
                               ? tr("鍵の猫を見つけるまで、この部屋には印を付けられません") : model.hintCells.contains(index)
                               ? tr("ヒントで置いた猫は消せません") : model.hintCrosses.contains(index)
                               ? tr("ヒントで置いた × は消せません") : model.wrongCrosses.contains(index)
                               ? tr("ここに猫はいません。赤い × は消せません") : mark == .cat
                               ? "" : tr("押すと × を付け外しします。猫を見つけるときはアクションの「猫を見つける」を選びます"))
            .accessibilityAddTraits(.isButton)
            // VoiceOver では × の付け外しと猫を見つけるを別の操作に分ける（ダブルタップは VoiceOver の「押す」と重なるため）。
            .accessibilityAction { withGameAnimation { _ = model.toggleCross(cell: index) } }
            .accessibilityAction(named: tr("× を付け外し")) { withGameAnimation { _ = model.toggleCross(cell: index) } }
            .accessibilityAction(named: tr("猫を見つける")) { withGameAnimation { model.findCat(cell: index) } }
    }

    // MARK: - コンティニュー・答え合わせ

    /// 結果カードの「広告を見てコンティニュー」。押したときだけ広告を出し、見終えたらミスを 1 回ぶん戻す（自動再生しない）。
    /// どの局に対する広告かを出す前に控え、ロード中に入れ替わった局へは乗せない（#729）。
    func requestContinue() {
        guard !continueRescue.isWatching, model.isOfferingContinue else { return }
        let game = model.gameSerial
        continueRescue.request(
            services, gameID: CatPuzzleModel.gameID, purpose: .continue,
            guardedBy: .checkedByGrant
        ) {
            withGameAnimation { model.continueAfterAd(forGame: game) }
        }
    }

    /// 負けたあとの答え合わせ。見つけていない猫を 1 匹ずつ「ぽん」と出す。
    /// 全体で約 1 秒に収まるよう、匹数が多いときは間隔を詰める。Reduce Motion のときは待たずに全部出す。
    private func revealUnfoundCats() async {
        let total = model.unfoundCats.count
        if !reduceMotion, total > 0 {
            let step = min(CatPuzzleMotion.revealStep, CatPuzzleMotion.revealTotal / total)
            for _ in 0..<total {
                try? await Task.sleep(for: step)
                guard !Task.isCancelled else { return }
                withGameAnimation { revealedGhosts += 1 }
            }
            try? await Task.sleep(for: CatPuzzleMotion.revealSettle)
            guard !Task.isCancelled else { return }
        } else {
            withGameAnimation { revealedGhosts = total }
        }
        if total > 0 {
            AccessibilityNotification.Announcement(tr("見つけられなかった猫の場所を%lld匹ぶん表示しました", total)).post()
        }
    }

    // MARK: - 新規ゲーム

    /// 「＋」。途中の盤面があるときは確認を挟んでから開始シートを出す（他のゲームと同じ）。
    /// やめた局は、開始シートで始めた時点で途中離脱（quit）として数える（`CatPuzzleModel.newGame` → `gameDidRestart`）。
    private func requestNewGame() {
        if model.hasProgressToLose {
            showConfirmNewGame = true
        } else {
            showNewGame = true
        }
    }

    /// 勝ちが続いたら一段上の大きさを勧める（#722・#2806）。並びは開始シートの大きさと同じ。自由に遊ぶときだけ。
    var ladder: DifficultyLadderPrompt? {
        let sizes = CatPuzzleSize.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: sizes.firstIndex(of: model.size),
                                      levelLabels: sizes.map(\.label)) { index in
            startNewGame(size: sizes[index])
        }
    }

    /// 「同じ条件でもう一回」。ステージで負けたら同じ面（同じ問題）にもう一度挑む。自由に遊ぶは同じ大きさの新しい問題。
    func replay() {
        if let stage = model.stage {
            startStage(stage)
        } else {
            startNewGame(size: nil)
        }
    }

    /// 開始シートの「スタート」。
    private func start(mode: CatPuzzlePlayMode, size: CatPuzzleSize) {
        preferredMode = mode.rawValue
        switch mode {
        case .stage: startStage(nil)
        case .free: startNewGame(size: size)
        }
    }

    /// 自由に遊ぶ。`size` が nil なら同じ大きさで始め直す（「同じ条件でもう一回」）。
    private func startNewGame(size: CatPuzzleSize?) {
        if let size { preferredSize = size.rawValue }
        withGameAnimation { model.newGame(size: size) }
    }

    /// ステージの面を始める。`number` が nil なら次に遊ぶ面。
    func startStage(_ number: Int?) {
        withGameAnimation { model.startStage(number) }
    }
}
