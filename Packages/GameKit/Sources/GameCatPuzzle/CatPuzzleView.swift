import SwiftUI
import Core
import CoreOjisanPixel

/// おじさんちのねこさがし（#2250）のプレイ画面。家の間取りのマスをタップで ×（いない）を付け外しし、ダブルタップで猫を見つける。
public struct CatPuzzleView: View {
    private let services: GameServices
    @State private var model: CatPuzzleModel
    /// 最後に選んだ盤の大きさ（次に開いたときの開始シートの初期値）。
    @AppStorage("catPuzzleSize") private var preferredSize = CatPuzzleSize.normal.rawValue
    /// 最後に選んだ遊び方（ステージ／自由に遊ぶ・#3048）。開始シートの初期値。
    @AppStorage("catPuzzleMode") private var preferredMode = CatPuzzlePlayMode.stage.rawValue
    /// ステージのクリアのカードを「盤を見る」で閉じたか（新しい局で開け直す）。
    @State private var clearCardClosed = false
    /// 盤を押している指の状態（タップかスライドかの判定。#3116）。
    @State private var boardTouch = BoardTouch()
    /// 開始シート（難易度を選ぶ）。続きの盤が無ければ最初に出す（他のゲームと同じ・会長 QA 2026-10-21・build 43）。
    @State private var showNewGame: Bool
    /// 「＋」で途中の局をやめるかの確認。
    @State private var showConfirmNewGame = false
    /// 「やり直し」（印を全部消す）の確認。
    @State private var showConfirmClear = false
    /// コンティニュー済みの局の負けカードを「盤を見る」で閉じたか（新しい局で開け直す）。
    @State private var failCardClosed = false
    /// ヒントの広告救済（無料 1 回を使い切った後の 1 回。連打ガード・広告・失敗アラート。15パズル・ナンプレと同じ #526）。
    @State private var hintRescue = RewardedRescue()
    /// コンティニュー（3 回目のミスで広告を見て続ける）の広告の段取り（#2780。ヒントとは別の救済として持つ）。
    @State private var continueRescue = RewardedRescue()
    /// 負けたあとの答え合わせで、これまでに盤へ出した「見つけていない猫」の数（1 匹ずつ増やす）。
    @State private var revealedGhosts = 0
    /// ヒントを上限まで使い切ったあとに押したときの一言を出している間（数秒で消える・#3048）。
    @State private var showsHintUsedUp = false
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
    static func holdsClock(showNewGame: Bool, showConfirmNewGame: Bool, showConfirmClear: Bool) -> Bool {
        showNewGame || showConfirmNewGame || showConfirmClear
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            // 盤は残りの高さを Spacer と山分けしない（操作の段が増えた分だけ盤が縮むのを防ぐ）。
            // クリアのダイアログは最後の猫が出る演出を見せてから 1 拍（`CatPuzzleModel.clearCardDelay`）おいて重ねる。
            board
                // ステージの問題を裏で作っている間は盤の上に「用意しています」を重ねる（9×9 は数秒かかることがある）。
                .overlay { if model.isPreparingStage { preparingOverlay } }
                .rewardOffer(continueRescue, for: .continue, isPresented: model.isOfferingContinue,
                             services: services, gameID: CatPuzzleModel.gameID)
                // 広告のロード〜視聴中は盤に触れない（ナンプレと同じ。視聴後のヒントは盤の今の形から読み直す）。
                .disabled(hintRescue.isWatching || continueRescue.isWatching)
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
        .boardGameResultCard(isPresented: Self.showsFailCard(model, closed: failCardClosed)) { failCard }
        // クリアのカードも盤ではなく画面全体に重ねる。盤に重ねるとカードの方が背が高く、SE でスクロールになっていた（#3048）。
        // 最後の猫が出る演出を見せてから 1 拍（`CatPuzzleModel.clearCardDelay`）おいて出す。
        // 「次のステージへ」を押して次の面を作っている間はカードを下げ、盤の「問題を用意しています…」を見せる。
        .boardGameResultCard(isPresented: model.showsClearCard && !clearCardClosed && !model.isPreparingStage) { clearCard }
        .gameChrome(title: tr("おじさんちのねこさがし"), review: services.review,
                    newGame: GameChromeNewGame(.solo, isDisabled: hintRescue.isWatching || continueRescue.isWatching) { requestNewGame() })
        .howToPlay(HowToPlayGuide.catPuzzle.illustrated(CatPuzzleHowToFigures.items).onboarding(CatPuzzleOnboarding.guide))
        .sheet(isPresented: $showNewGame) {
            CatPuzzleNewGameSheet(initialMode: CatPuzzlePlayMode(rawValue: preferredMode) ?? .stage,
                                  initial: model.size, nextStage: model.savedStage) { mode, size in
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
                Text(tr("途中で終了すると、いまの盤面とタイムが失われます。"))
            }
            anchor.confirmationDialog(tr("印を全部消しますか？"), isPresented: $showConfirmClear, titleVisibility: .visible) {
                Button(tr("全部消してやり直す"), role: .destructive) { withGameAnimation { model.reset() } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("同じ問題を最初から解きます。タイムとミスはそのままです。"))
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
                    tr("そこに猫はいない。赤い×を置いた。ミス %1$lld/%2$lld", model.mistakes, CatPuzzleModel.maxMistakes)
                ).post()
            }
        }
        .onChange(of: model.showsClearCard) { _, shows in
            if !shows { clearCardClosed = false }
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
        // 「この局のヒントは使い切りました」は数秒で消す。
        .task(id: showsHintUsedUp) {
            guard showsHintUsedUp else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withGameAnimation { showsHintUsedUp = false }
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
            rescues: [hintRescue, continueRescue],
            isHeld: Self.holdsClock(showNewGame: showNewGame, showConfirmNewGame: showConfirmNewGame,
                                    showConfirmClear: showConfirmClear),
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
        .task {
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
                // ミスの残量。1 回目から色を変える（ナンプレの「ミス 1/3」と同じ形）。
                Text(tr("ミス %1$lld/%2$lld", model.mistakes, CatPuzzleModel.maxMistakes))
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3).monospacedDigit()
                    .foregroundStyle(model.mistakes > 0 ? Theme.coralText : Theme.inkSubText)
                    .accessibilityLabel(tr("ミス %1$lld回、あと%2$lld回で終わり", model.mistakes, model.mistakesRemaining))
                Text(tr("・")).foregroundStyle(Theme.inkSubText).accessibilityHidden(true)
                // ステージは面の番号、自由に遊ぶは難易度。
                Text(model.stage.map { tr("ステージ %lld", $0) } ?? model.size.label)
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(Theme.inkSubText)
                    .accessibilityLabel(model.stage.map { tr("ステージ %lld", $0) } ?? tr("難易度 %@", model.size.label))
                Text(tr("・")).foregroundStyle(Theme.inkSubText).accessibilityHidden(true)
                GameClockLabel(RecordFormat.time(model.elapsedSeconds), elapsedSeconds: model.elapsedSeconds)
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .accessibilityElement(children: .contain)
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
                    puzzle: model.puzzle, marks: model.marks,
                    wrongCrosses: model.wrongCrosses, lastWrongCell: model.lastWrongCell,
                    hintCells: model.hintCells, hintCrosses: model.hintCrosses, lastHint: model.lastHint,
                    shakeToken: model.mistakes, isSolved: model.isSolved,
                    ghostCats: Array(model.unfoundCats.prefix(revealedGhosts)), cellSide: cellSide
                )
                .offset(x: inset, y: inset)
                cells(cellSide: cellSide, inset: inset)
            }
            .frame(width: boardSide, height: boardSide)
            .contentShape(Rectangle())
            .gesture(boardGesture(cellSide: cellSide, inset: inset))
            .frame(maxWidth: .infinity, alignment: .center)
            .gameAnimation(.easeOut(duration: 0.15), value: model.marks)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 盤を押している指の状態。指を置いた位置のマスと、スライドと決まったかを持つ。
    private struct BoardTouch {
        var start: CGPoint?
        var startCell: Int?
        var isSliding = false
    }

    /// 盤全体のタップとスライド（#3116）。指の動きがマスの一辺の `slideThreshold` 未満のまま離したらタップとして
    /// `tap(cell:)` へ、届いたらスライドとして通ったマスに続けて × を付ける・外す（向きは最初のマスで決まる）。
    private func boardGesture(cellSide: CGFloat, inset: CGFloat) -> some Gesture {
        let side = model.puzzle.side
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                if boardTouch.start != value.startLocation {
                    // 前の指が離れ損ねていたら（システムの割り込み）確定してから新しい指として扱う。
                    if boardTouch.isSliding { model.endCrossDrag() }
                    boardTouch = BoardTouch(
                        start: value.startLocation,
                        startCell: CatPuzzleModel.cell(at: value.startLocation, side: side, cellSide: cellSide, inset: inset))
                }
                guard let startCell = boardTouch.startCell else { return }
                let moved = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                if !boardTouch.isSliding, moved >= cellSide * CatPuzzleModel.slideThreshold {
                    boardTouch.isSliding = true
                    withGameAnimation { model.beginCrossDrag(cell: startCell) }
                }
                if boardTouch.isSliding {
                    let cell = CatPuzzleModel.cell(at: value.location, side: side, cellSide: cellSide, inset: inset)
                    withGameAnimation { model.dragCross(to: cell) }
                }
            }
            .onEnded { _ in
                defer { boardTouch = BoardTouch() }
                if boardTouch.isSliding {
                    model.endCrossDrag()
                } else if let cell = boardTouch.startCell {
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
            Color.clear
                .frame(width: cellSide, height: cellSide)
                .contentShape(Rectangle())
                .offset(x: inset + CGFloat(index % n) * cellSide, y: inset + CGFloat(index / n) * cellSide)
                .accessibilityElement()
                .accessibilityLabel(CatPuzzleAccessibility.cellLabel(
                    row: index / n, col: index % n,
                    roomName: CatPuzzleHouse.room(model.puzzle.rooms[index]).name,
                    mark: model.marks[index],
                    isConflict: model.wrongCrosses.contains(index),
                    isHint: model.hintCells.contains(index) || model.hintCrosses.contains(index),
                    isUnfoundCat: model.isUnfoundCat(cell: index)
                ))
                .accessibilityHint(model.isOver ? "" : model.hintCells.contains(index)
                                   ? tr("ヒントで置いた猫は消せません") : model.hintCrosses.contains(index)
                                   ? tr("ヒントで置いた × は消せません") : model.wrongCrosses.contains(index)
                                   ? tr("ここに猫はいません。赤い × は消せません") : model.marks[index] == .cat
                                   ? "" : tr("押すと × を付け外しします。猫を見つけるときはアクションの「猫を見つける」を選びます"))
                .accessibilityAddTraits(.isButton)
                // VoiceOver では × の付け外しと猫を見つけるを別の操作に分ける（ダブルタップは VoiceOver の「押す」と重なるため）。
                .accessibilityAction { withGameAnimation { _ = model.toggleCross(cell: index) } }
                .accessibilityAction(named: tr("× を付け外し")) { withGameAnimation { _ = model.toggleCross(cell: index) } }
                .accessibilityAction(named: tr("猫を見つける")) { withGameAnimation { model.findCat(cell: index) } }
        }
    }

    // MARK: - コンティニュー・答え合わせ

    /// 結果カードの「広告を見てコンティニュー」。押したときだけ広告を出し、見終えたらミスを 1 回ぶん戻す（自動再生しない）。
    /// どの局に対する広告かを出す前に控え、ロード中に入れ替わった局へは乗せない（#729）。
    private func requestContinue() {
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

    // MARK: - 盤の下

    /// 盤の下の 1 行。ヒント・赤い × の説明・終局のおじさんの一言。高さは常に確保して盤が跳ねないようにする。
    private var messageLine: some View {
        ZStack {
            if model.isSolved {
                // おじさんの一言は横いっぱいの吹き出しにして、文字が窮屈にならないようにする（会長 QA 2026-10-21・build 42）。
                ojisanLine(face: .cheer, text: tr("みんなでくつろいでおる"))
            } else if model.isFailed {
                ojisanLine(face: .frown, text: tr("猫はどこへ行ったんじゃ…"))
            } else if model.lastWrongCell != nil, model.mistakesRemaining == 1 {
                // 残りミス 1 回は一段強く（アイコン付き・太字）。次の 1 回で終わることを見逃さないようにする。
                Label(tr("あと1回で終わり！ そこに猫はいない"), systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(15, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            } else if model.lastWrongCell != nil {
                Text(tr("そこに猫はいない！ 赤い×はミス（あと%lld回で終わり）", model.mistakesRemaining))
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    // 読み上げは `onChange` の通知で伝える。
                    .accessibilityHidden(true)
            } else if showsHintUsedUp {
                Label(tr("この局のヒントは使い切りました"), systemImage: "lightbulb.slash")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                    .multilineTextAlignment(.center)
            } else if let hint = model.lastHint {
                Label(CatPuzzleAccessibility.message(for: hint, puzzle: model.puzzle, roomName: { CatPuzzleHouse.room($0).name }),
                      systemImage: "lightbulb.fill")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.yellowText)
                    .multilineTextAlignment(.center)
            } else {
                Text(tr("タップで ×、ダブルタップで猫"))
                    .scaledFont(14, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .frame(minHeight: 36)
    }

    /// 終局のおじさんの一言（顔＋横いっぱいの吹き出し）。
    private func ojisanLine(face: OjisanPixel.Face, text: String) -> some View {
        HStack(spacing: 10) {
            OjisanPixel.faceImage(face)
                .frame(width: 40, height: 37.5)
            Text(text)
                .scaledFont(16, weight: .bold, design: .rounded, maxScale: 1.4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .popCard(corner: Theme.cornerSmall)
        }
        .frame(maxWidth: .infinity)
    }

    /// 盤の下の操作（#148・#1689）。遊んでいる間はヒント・戻す・⋯、終局（クリア・ミス 3 回の負け）したら他のゲームと同じ
    /// 「同じ条件でもう一回」「設定を変える」（`GameReplayBar`）とレコメンドに替える（会長 QA 2026-10-21・build 42）。
    ///
    /// 遊んでいる間は操作の段の高さだけを取り、決着後の段（もう一回＋レコメンド）の高さは確保しない（#3048）。
    /// 確保すると SE で盤が 216pt まで縮み、段の下に画面の 1/4 ほどの空きが残っていた。入れ替えは結果カードを
    /// 画面全体に出している間（クリアのカード・ミス 3 回のカード）に行い、盤の大きさが変わる瞬間を見せない
    /// （`showsFinishedControls`）。
    @ViewBuilder private var controlArea: some View {
        if Self.showsFinishedControls(model) {
            GameControlArea(isFinished: true, services: services, ladder: model.stage == nil ? ladder : nil) {
                if let stage = model.stage, model.isSolved {
                    CatPuzzleNextStageBar(next: stage + 1,
                                          onNext: { startStage(stage + 1) },
                                          onChangeSettings: { showNewGame = true })
                } else {
                    GameReplayBar(
                        onReplay: { replay() },
                        onChangeSettings: { showNewGame = true }
                    ) {
                        RecordLabel(model.recordResult)
                    }
                }
            } playing: {
                EmptyView()
            }
        } else {
            let controls = Self.playControls(
                for: model,
                isWatchingAd: hintRescue.isWatching,
                onClear: { showConfirmClear = true },
                onUndo: { withGameAnimation { model.undo() } },
                onHint: { requestHint() }
            )
            if !controls.menu.isEmpty || !controls.actions.isEmpty {
                GameOverflowBar(menuItems: controls.menu, actions: controls.actions, verticalPadding: 4)
            }
        }
    }

    /// 決着後の段に替えるか。クリアはカードが出た時点（最後の猫から 1 拍後）、ミス 3 回は提案のカードが出た時点で替える
    /// （どちらもカードが画面全体を覆っている間に盤の大きさが変わる）。コンティニューで戻ったら遊ぶ段に戻る。
    static func showsFinishedControls(_ model: CatPuzzleModel) -> Bool {
        model.showsClearCard || model.isFailed || model.isOfferingContinue
    }

    /// 遊んでいる間の操作の段（#1834）。広告が絡むヒントと「戻す」を段に、やり直しは「⋯」に入れる。
    /// 終局した後は何も返さない（終局後は `GameReplayBar` に替わる）。
    static func playControls(
        for model: CatPuzzleModel,
        isWatchingAd: Bool = false,
        onClear: @escaping () -> Void = {}, onUndo: @escaping () -> Void = {}, onHint: @escaping () -> Void = {}
    ) -> (menu: [GameControlMenuItem], actions: [GameActionItem]) {
        guard !model.isOver else { return ([], []) }
        let menu = [
            GameControlMenuItem(
                id: "clear", title: tr("やり直し"), systemImage: "arrow.counterclockwise",
                isDestructive: true, isEnabled: model.hasProgressToLose && !model.isOfferingContinue && !isWatchingAd, action: onClear
            ),
        ]
        let actions = [
            GameActionItem(
                id: "undo", title: tr("戻す"), systemImage: "arrow.uturn.backward", role: .undo,
                isEnabled: model.canUndo && !isWatchingAd, action: onUndo
            ),
            GameActionItem(
                id: "hint", title: tr("ヒント"), systemImage: "lightbulb.fill", role: .hint,
                badge: hintBadge(for: model),
                // 上限まで使い切ったら押せない見た目にするが、押すと「使い切りました」と知らせる（広告は出さない・#3048）。
                isEnabled: (model.canHint || isHintUsedUp(model)) && !isWatchingAd,
                looksDisabled: isHintUsedUp(model),
                accessibilityLabel: CatPuzzleAccessibility.hintLabel(remaining: model.hintsRemaining, needsAd: model.needsAdForHint),
                accessibilityHint: isHintUsedUp(model)
                    ? tr("この局のヒントは使い切りました")
                    : tr("推理の1歩を示します。確実に猫のいないマスに×を置き、確定するときだけ猫を置きます"),
                action: onHint
            ),
        ]
        return (menu, actions)
    }

    /// ヒントの 2 行目。「あと n 回」は無料ぶんだけで、使い切ったら「0回 ▶ 広告を見て +1」の面にする
    /// （15パズル・将棋などと同じ `GameActionBadge.hint`。広告の追加まで使い切ったら 0 のまま・#1897）。
    /// 広告で足せる上限は盤ゲームの 5 回ではなく 3 回なので、それを渡す（#3048）。
    static func hintBadge(for model: CatPuzzleModel) -> GameActionBadge {
        .hint(totalRemaining: model.hints.remaining, needsAd: model.needsAdForHint, adLimit: model.hints.adLimit)
    }

    /// 無料と広告の追加を合わせて、この局のヒントを上限まで使い切ったか（遊んでいる間だけ）。
    static func isHintUsedUp(_ model: CatPuzzleModel) -> Bool {
        model.hints.isExhausted && !model.isOver && !model.isOfferingContinue
    }

    /// 無料が残っていればそのまま示し、使い切っていれば広告を見たあとに示す（広告は押下起点・自動再生しない）。
    /// 上限まで使い切っていたら広告は出さず、盤の下に「この局のヒントは使い切りました」を数秒出す。
    private func requestHint() {
        if Self.isHintUsedUp(model) {
            showsHintUsedUp = true
            AccessibilityNotification.Announcement(tr("この局のヒントは使い切りました")).post()
            return
        }
        Self.requestHint(model: model, hintRescue: hintRescue, services: services)
    }

    /// `requestHint()` の中身（テストからモックの services で広告の成功・失敗を確かめるため static にしている）。
    /// どの局に対する広告かを出す前に控え、ロード中に始めた新しい局へは乗せない（15パズル・ナンプレのヒントと同じ #815）。
    static func requestHint(model: CatPuzzleModel, hintRescue: RewardedRescue, services: GameServices) {
        guard !hintRescue.isWatching, model.canHint else { return }
        guard model.needsAdForHint else {
            withGameAnimation { model.useHint() }
            return
        }
        let game = model.gameSerial
        hintRescue.request(
            services, gameID: CatPuzzleModel.gameID, purpose: .hint,
            guardedBy: .checkedByGrant
        ) {
            // 広告を見たのに入らなかったら黙って終わらせない（`grantAdHint` が false → 「出せませんでした」）。
            withGameAnimation { model.grantAdHint(forGame: game) }
        }
    }

    /// 盤の大きさの呼び名。ステージは「ステージ 3（6×6）」、自由に遊ぶは「ふつう（7×7）」。
    private var boardLabel: String {
        if let stage = model.stage {
            return tr("ステージ %1$lld（%2$@）", stage, model.size.sizeLabel)
        }
        return tr("%1$@（%2$@）", model.size.label, model.size.sizeLabel)
    }

    /// クリアのカードの行。SE の画面に収まるよう 2〜3 行に詰める（#3048。以前は 5 行で盤からはみ出しスクロールになっていた）。
    /// ヒントは 0 回でも省かず出す（#2613・#2801）。
    var clearDetails: [String] {
        var lines = [
            tr("タイム %1$@・ミス %2$lld・ヒント %3$lld回",
               RecordFormat.time(model.elapsedSeconds), model.mistakes, model.hintsUsed),
            tr("%1$@・手数 %2$lld", boardLabel, model.moves),
        ]
        if model.mistakes == 0 { lines.append(tr("ミスなしのパーフェクト！")) }
        return lines
    }

    /// クリアのカード（画面全体に重ねる）。ステージは見出しを「ステージ n クリア！」にし、「次のステージへ」を置く。
    private var clearCard: some View {
        let title = model.stage.map { tr("ステージ %lld クリア！", $0) } ?? tr("クリア！")
        return ZStack {
            Color.black.opacity(0.45)
            GameClearCard(
                title: title, details: clearDetails,
                primaryAction: model.stage.map { stage in
                    GameClearCard.PrimaryAction(
                        title: tr("次のステージへ"),
                        hint: tr("ステージ %lld を始めます", stage + 1)
                    ) { startStage(stage + 1) }
                }
            ) {
                clearCardClosed = true
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// 3 回目のミスで出す、ただ 1 枚のダイアログ（他のゲームの負けと同じ `BoardGameResultCard`・#2904）。
    /// 提案中は「広告を見てコンティニュー」でミスが 1 回ぶん戻り、「あきらめて正解を見る」で負けを確定して盤に正解を出す
    /// （負けはあきらめた時点で確定するので、記録の行はこのカードには出ない）。
    /// コンティニュー済みの局は負けが確定した状態で出し、「盤を見る」で閉じる（正解はカードの後ろで盤に出る）。
    /// 補足は 1 行に詰める（#3048。SE で画面の高さぎりぎりだった）。「広告を見ると、ミスが1回ぶん戻ります」は
    /// コンティニューのボタンの読み上げのヒントに残す。
    private var failCard: some View {
        let offering = model.isOfferingContinue
        return BoardGameResultCard(
            verdict: .loss,
            reason: tr("%lld回まちがえた…", CatPuzzleModel.maxMistakes),
            details: [tr("%1$@・タイム %2$@", boardLabel, RecordFormat.time(model.elapsedSeconds))],
            record: offering ? nil : model.recordResult,
            secondaryAction: offering
                ? BoardGameResultCard.SecondaryAction(
                    title: tr("広告を見てコンティニュー"),
                    hint: tr("広告を見ると、ミスが1回ぶん戻ります")
                ) { requestContinue() }
                : nil,
            closeTitle: offering ? tr("あきらめて正解を見る") : nil,
            closeHint: offering ? tr("負けを確定して、猫のいる場所を盤に表示します") : nil
        ) {
            if offering {
                withGameAnimation { model.declineContinue() }
            } else {
                failCardClosed = true
            }
        }
    }

    /// ステージの問題を作っている間に盤へ重ねる表示。
    private var preparingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface.opacity(0.85))
            VStack(spacing: 10) {
                ProgressView()
                Text(tr("問題を用意しています…"))
                    .scaledFont(15, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .accessibilityElement(children: .combine)
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
    private var ladder: DifficultyLadderPrompt? {
        let sizes = CatPuzzleSize.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: sizes.firstIndex(of: model.size),
                                      levelLabels: sizes.map(\.label)) { index in
            startNewGame(size: sizes[index])
        }
    }

    /// 「同じ条件でもう一回」。ステージで負けたら同じ面（同じ問題）にもう一度挑む。自由に遊ぶは同じ大きさの新しい問題。
    private func replay() {
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
    private func startStage(_ number: Int?) {
        withGameAnimation { model.startStage(number) }
    }
}

// MARK: - 遊び方の選択

/// 入口で選ぶ遊び方（#3048）。`rawValue` は最後に選んだ遊び方の保存に使う。
enum CatPuzzlePlayMode: String, CaseIterable {
    /// 1 面ずつ難しくなる連番のステージ。クリアしたら次の面へ進むだけで、前の面には戻らない。
    case stage
    /// 盤の大きさを選び、毎回新しい問題（これまでの遊び方）。
    case free

    var label: String {
        switch self {
        case .stage: tr("ステージ")
        case .free: tr("自由に遊ぶ")
        }
    }
}

/// ステージのクリア後に盤の下へ出す段。「次のステージへ」と「設定を変える」（`GameReplayBar` と同じ形・寸法）。
struct CatPuzzleNextStageBar: View {
    let next: Int
    let onNext: () -> Void
    let onChangeSettings: () -> Void

    var body: some View {
        HStack(spacing: GameReplayBarMetrics.buttonSpacing) {
            Button(action: onNext) {
                capsule(tr("次のステージへ"), fill: Theme.Fill.coral, foreground: Theme.onAccent)
            }
            .accessibilityHint(tr("ステージ %lld を始めます", next))
            Button(action: onChangeSettings) {
                capsule(GameReplayBarText.changeSettings, fill: Theme.fillMuted, foreground: .white)
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, GameReplayBarMetrics.verticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    private func capsule(_ title: String, fill: Color, foreground: Color) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: GameReplayBarMetrics.buttonHeight)
            .background(Capsule().fill(fill))
            .contentShape(Rectangle())
    }
}

// MARK: - 開始シート

/// 遊び方（ステージ／自由に遊ぶ）と、自由に遊ぶときの難易度（盤の大きさ）を選んで始めるシート。
/// 他のゲームと同じ共通の枠（`GameSetupSheet`）。
struct CatPuzzleNewGameSheet: View {
    let nextStage: Int
    let onStart: (CatPuzzlePlayMode, CatPuzzleSize) -> Void
    let onCancel: () -> Void
    @State private var mode: CatPuzzlePlayMode
    @State private var size: CatPuzzleSize

    init(initialMode: CatPuzzlePlayMode, initial: CatPuzzleSize, nextStage: Int,
         onStart: @escaping (CatPuzzlePlayMode, CatPuzzleSize) -> Void,
         onCancel: @escaping () -> Void) {
        self.nextStage = nextStage
        self.onStart = onStart
        self.onCancel = onCancel
        _mode = State(initialValue: initialMode)
        _size = State(initialValue: initial)
    }

    var body: some View {
        GameSetupSheet(
            kind: .solo,
            onboarding: CatPuzzleOnboarding.guide,
            onStart: { onStart(mode, size) }, onCancel: onCancel
        ) {
            Self.modeSection(selection: $mode, nextStage: nextStage)
            if mode == .free {
                Self.sizeSection(selection: $size)
            }
        }
    }

    /// 遊び方の節。ステージは次に遊ぶ面の番号を添える。
    static func modeSection(selection: Binding<CatPuzzlePlayMode>, nextStage: Int) -> some View {
        GameSetupSection(tr("遊び方")) {
            HStack(spacing: 6) {
                let modes = CatPuzzlePlayMode.allCases
                ForEach(Array(modes.enumerated()), id: \.element) { step, value in
                    GameSetupChooser(title: value.label,
                                     subtitle: value == .stage ? tr("ステージ %lld から", nextStage) : tr("盤の大きさを選ぶ"),
                                     selected: selection.wrappedValue == value,
                                     accent: DifficultyTile.accent(step: step, of: modes.count),
                                     metrics: DifficultyTile.metrics) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }

    /// 難易度の節（静止画の確認でも中身だけ描けるよう切り出している）。
    static func sizeSection(selection: Binding<CatPuzzleSize>) -> some View {
        GameSetupSection(tr("難易度")) {
            HStack(spacing: 6) {
                let levels = CatPuzzleSize.allCases
                ForEach(Array(levels.enumerated()), id: \.element) { step, value in
                    GameSetupChooser(title: value.label, subtitle: value.sizeLabel,
                                     selected: selection.wrappedValue == value,
                                     accent: DifficultyTile.accent(step: step, of: levels.count),
                                     metrics: DifficultyTile.metrics) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }
}
