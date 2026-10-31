import Foundation
import SwiftUI
import Core

/// ソリティア（クロンダイク）の画面。
///
/// 中身は 3 つに分けてある（#525）。ここは**器**で、局の状態・シート・アラート・
/// リワード広告の段取りだけを持つ:
///
/// - 盤面 → `SolitaireBoardView`（ドラッグの状態ごと閉じ込めてある・#521）
/// - 救済の面 → `SolitaireRescueOverlay`
/// - 盤の下の操作エリア → `SolitaireControlsView`
public struct SolitaireView: View {
    @State private var model: SolitaireModel
    /// 配り直しの開始シート（#498）。**初回の配札では出さない**（既定で即座に配る）。
    ///
    /// #498 以前は「新しい配札にしますか？」の確認ダイアログを出していたが、
    /// このシートが同じ警告と最終確認（キャンセルできる「配る」）を兼ねるので置き換えた。
    /// ダイアログのあとにさらにシートを出すと、確認を 2 枚重ねることになる。
    @State private var showSetup = false
    /// 開始シートで選んでいる最中のルール。「配る」を押すまで局には効かない（1局=1RuleSet）。
    @State private var draft = SolitaireRuleSet.standard
    /// ジョーカー補充のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var jokerRescue = RewardedRescue()
    /// 無料の「戻す」を使い切った状態でボタンを押したときの提案（#476）。
    /// **自動再生はしない**。ここで「見る」を選んだときだけ広告を出す。
    @State private var showUndoRefillPrompt = false
    /// 「戻す」補充のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()
    /// ヒント（無料 3 回を使い切った後の広告）の段取り（#2025）。読みと広告はモデルが 1 本の非同期メソッドで持つ。
    @State private var hintRescue = RewardedRescue()

    private let services: GameServices

    public init(services: GameServices) {
        self.services = services
        #if DEBUG
        // 確認用（#1755）: クリアカードを遊ばずに出す。記録・中断データ・解析に触れない局で開く
        // （通常の局を先に作ると、それだけで中断データの読み込みと解析の開始が走るので作らない）。
        if ProcessInfo.processInfo.arguments.contains("-solitaireWon") {
            _model = State(initialValue: SolitaireModel.clearPreviewForTesting(remainingMoves: 0))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-solitaireAlmostWon") {
            _model = State(initialValue: SolitaireModel.clearPreviewForTesting(remainingMoves: 1))
            return
        }
        #endif
        _model = State(initialValue: SolitaireModel(services: services))
    }

    /// クリアが続いたら一段上のめくり方（3 枚めくり）を勧める（#2599）。始め直しは開始シートの「配る」と同じ経路。
    private var ladder: DifficultyLadderPrompt? {
        let modes = SolitaireDrawMode.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: modes.firstIndex(of: model.rules.drawMode),
                                      levelLabels: modes.map(\.label)) { level in
            model.newGame(rules: SolitaireRuleSet(drawMode: modes[level]))
        }
    }

    public var body: some View {
        // 左右の余白は部品ごとに付ける。盤だけは `boardSideInset`（4pt）まで詰めて札の幅に回し、
        // 帯・ボタンは全画面の枠の左右の余白（8pt）。フリーセルと同じ。
        VStack(spacing: 8) {
            statusBar
                .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
            // レイアウトパターン A（全画面・#2531）: 卓のフェルトは全画面の枠が画面全体に敷くので、盤に `.cardTable()`
            // （木枠付きの卓）は付けない。札の大きさは盤の幅から決まるので、木枠の分だけ大きくなる。
            // 札が帯に張り付いて見えないよう、卓の中の上の余白（`cardTopInset`・ソリティア系で共通）は残す。
            SolitaireBoardView(model: model, services: services)
                .padding(.top, CardTableStyle.cardTopInset)
                // クリアは盤に重ねる共通のカードで示す（#1755）。
                .gameClearCard(isPresented: model.phase == .won,
                               details: [tr("%1$lld手 / タイム %2$@", model.moveCount, RecordFormat.time(model.elapsedSeconds))])
                .padding(.horizontal, CardStackLayout.boardSideInset)
                .layoutPriority(1)
            SolitaireControlsView(
                model: model,
                services: services,
                isWatchingUndoAd: undoRescue.isWatching,
                onUndo: requestUndo,
                isWatchingHintAd: hintRescue.isWatching,
                onHint: requestHint,
                ladder: ladder
            )
            .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
            HowToPlayHint(.solitaire, playLog: services.playLog)
                .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
            // 余りの高さは「⋯」の行とバナーの帯のあいだに置く（盤→「⋯」→余白→広告・#1485）。
            Spacer(minLength: 0)
        }
        // 上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
        .padding(.vertical, 4)
        // レイアウトパターン A（全画面・会長決裁 2026-10-19・#2429 → #2531）: フェルトを画面全体に敷き、ヘッダーは 1 行
        // （戻る・ソリティア・？・＋）、バナーは画面最下部。手数と時計はモックの A 案どおりヘッダーの下に
        // 低い 1 行の札で残す。
        .gameChrome(title: tr("ソリティア"), review: services.review, fullScreen: .felt, ads: services.ads,
                    newGame: GameChromeNewGame(.solo) {
                        openSetup()
                    })
        .howToPlay(HowToPlayGuide.solitaire.illustrated(SolitaireHowToFigures.items).onboarding(SolitaireOnboarding.guide)) { SolitaireRuleSheet() }
        // めくり方を選んでから配る（#498）。局に焼き込むのは「配る」を押した瞬間だけ。
        .sheet(isPresented: $showSetup) {
            SolitaireSetupSheet(draft: $draft, discardsProgress: model.canUndo) {
                showSetup = false
                model.newGame(rules: draft)
            } onCancel: {
                showSetup = false
            }
        }
        .rewardedRescueAlerts(
            jokerRescue,
            notEarned: tr("ジョーカーをもらえませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("ジョーカーを受け取れませんでした"),
                message: tr("広告を見ているあいだに局面が変わったため、ジョーカーを追加できませんでした。\n手持ちのジョーカーはそのまま残っています。")
            )
        )
        .dialogs { anchor in
            anchor.alert(tr("この盤からは勝てません"), isPresented: hopelessBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(tr("「戻す」で戻れます。ヒントの回数は減っていません。"))
            }
            .alert(tr("無料の「戻す」を使い切りました"), isPresented: $showUndoRefillPrompt) {
                Button(tr("広告を見て%lld回補充する", SolitaireUndoBudget.refill)) { requestUndoRefill() }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("広告を最後まで視聴すると「戻す」を%lld回ぶん補充します。\n盤面はそのままです。", SolitaireUndoBudget.refill))
            }
        }
        .rewardOffer(undoRescue, for: .undo, isPresented: showUndoRefillPrompt,
                     services: services, gameID: model.gameID)
        // 手持ちのジョーカーがあるうちの幕は、広告ではなく「使う」を出している（#780）。
        .rewardOffer(jokerRescue, for: .joker, isPresented: model.showsRescuePrompt && !model.hasJoker,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            undoRescue,
            notEarned: tr("「戻す」を補充できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("「戻す」を補充できませんでした"),
                message: tr("広告を見ているあいだに配り直されたか、局が終わったため、補充できませんでした。\n新しい配札の「戻す」は無料の回数まで戻っています。")
            )
        )
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: tr("ヒントを表示できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("ヒントを出せませんでした"),
                message: tr("広告を見ているあいだに盤が変わったか、画面を離れたため、ヒントを出せませんでした。")
            )
        )
        // 示した手を VoiceOver にも一言で伝える（印は目で見る手がかりなので）。
        .onChange(of: model.hintMove) { _, move in
            guard let move else { return }
            AccessibilityNotification.Announcement(
                SolitaireAccessibility.hintLabel(move: move, board: model.board)
            ).post()
        }
        .overlay {
            if model.showsRescuePrompt {
                SolitaireRescueOverlay(
                    model: model,
                    isWatchingJokerAd: jokerRescue.isWatching,
                    isWatchingUndoAd: undoRescue.isWatching,
                    onUndo: requestUndo,
                    onRequestJoker: requestJoker
                )
            }
        }
        // 「自動で上がる」は 1 手ずつ順に送る（#2706）。画面を離れて止められたら残りを一気に片付けて、
        // 「入力が止まったまま」の盤を残さない。
        .task(id: model.autoFinishRun) {
            let run = model.autoFinishRun
            while let wait = model.advanceAutoFinish(for: run) {
                do { try await Task.sleep(for: wait) } catch {
                    model.finishAutoFinishNow(for: run)
                    return
                }
            }
        }
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影用（#397）: 遊んでいる最中の盤面を機械的に作る。シミュレータは自動タップが
            // できないため、初期配置以外を撮る手段がこれしかない（囲碁の `-goMidgame` と同じ理由）。
            if ProcessInfo.processInfo.arguments.contains("-solitaireMidgame") {
                model.applyPreviewProgressForTesting()
            }
            // ヒントの印（#2025）。シミュレータは自動タップができないため、起動引数から無料の 1 回を押した状態にする。
            if ProcessInfo.processInfo.arguments.contains("-solitaireHint") {
                await model.requestHint()
            }
            // 救済の面（#406）は自然に到達させられないので、撮影用に直接その状態を作る。
            if ProcessInfo.processInfo.arguments.contains("-solitaireRescue") {
                model.applyPreviewProgressForTesting()
                model.applyRescuePreviewForTesting(spendJoker: false)
            }
            if ProcessInfo.processInfo.arguments.contains("-solitaireRescueAd") {
                model.applyPreviewProgressForTesting()
                model.applyRescuePreviewForTesting(spendJoker: true)
            }
            if ProcessInfo.processInfo.arguments.contains("-solitaireJokerPlacing") {
                model.applyPreviewProgressForTesting()
                model.applyPlacingJokerPreviewForTesting()
            }
            // 3 枚めくり（#498）は開始シートで選ぶので、自動タップのできないシミュレータでは
            // この 2 つの口からしか撮れない。
            if ProcessInfo.processInfo.arguments.contains("-solitaireDraw3") {
                model.applyDrawThreePreviewForTesting()
            }
            if ProcessInfo.processInfo.arguments.contains("-solitaireSetup") {
                openSetup()
            }
            #endif
        }
        // 画面を離れたら・背面に回ったら・広告の視聴中は計時を止め、戻ったら再開する
        // （#375・#1734・#1382。止め方・動かし方は `GameStopwatch` / `gameTimerLifecycle` に共通化・#1857）。
        .gameTimerLifecycle(
            rescues: [jokerRescue, undoRescue, hintRescue],
            isHeld: showSetup || showUndoRefillPrompt,
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
    }

    /// 開始シートを開く。**いま遊んでいるルールを初期選択にする**（#498）。
    /// 前に開いたときの選択が残っていると、続けて配り直したときに勝手にルールが変わる。
    private func openSetup() {
        draft = model.rules
        showSetup = true
    }

    // MARK: - ステータスバー

    /// 全画面（A・#2531）ではモックどおり 44pt の帯より低い 1 行の札にする（`GameStatusBarStyle.compactMinHeight`）。
    private var statusBar: some View {
        GameStatusBar(verticalPadding: GameStatusBarStyle.compactVerticalPadding,
                      minHeight: GameStatusBarStyle.compactMinHeight) {
            HStack(spacing: 8) {
                Group {
                    if model.phase == .won {
                        Label(tr("クリア！"), systemImage: "flag.checkered")
                            .themeBody(15)
                            .foregroundStyle(Theme.tealText)
                    } else {
                        Label(tr("%lld手", model.moveCount), systemImage: "hand.tap.fill")
                            .scaledFont(15, weight: .bold, design: .monospaced)
                            .foregroundStyle(Theme.coralText)
                    }
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                // 標準以外のルールで遊んでいるときだけルール名を出す（#498）。既定の 1 枚めくりは「標準」そのものなので出さない。
                // 以前は「⋯」の行の左端にあったが、盤の下は操作の段になった（#1856）ので帯（表示だけの場所）へ移した。
                if model.rules.drawMode != .one {
                    Text(model.rules.drawMode.label)
                        .themeCaption(11, maxScale: 1.3)
                        .foregroundStyle(Theme.inkSubText)
                        .lineLimit(1)
                }
            }
        } trailing: {
            GameClockLabel(RecordFormat.time(model.elapsedSeconds), elapsedSeconds: model.elapsedSeconds)
        }
        // 3 つの数字が別々に読まれると意味が取りにくいので 1 要素にまとめる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SolitaireAccessibility.statusLabel(
            phase: model.phase,
            elapsedSeconds: model.elapsedSeconds,
            moveCount: model.moveCount,
            isDeadEnd: model.isDeadEnd,
            isLost: model.isLost,
            ruleLabel: model.rules.drawMode != .one ? model.rules.drawMode.label : nil
        ))
    }

    // MARK: - リワード広告の段取り

    /// リワード広告 → ジョーカー補充 → 置き先の選択、までを 1 本に繋ぐ。
    ///
    /// 「広告を見たのに何も起きない」経路を作らないのが要（既存の広告契約・ナンプレのヒントと同型）。
    /// 視聴しなかったときと、視聴したのに補充できなかったとき（待っている間に自力で局面が
    /// 変わって所持に戻った等）を読み分けて必ず知らせる。
    private func requestJoker() {
        // どの局に対する補充かを、広告を出す前に控える（`requestUndoRefill` と同型。#511）。
        let deal = model.dealSerial
        jokerRescue.request(
            services, gameID: model.gameID, purpose: .joker,
            guardedBy: .checkedByGrant
        ) {
            guard model.grantJoker(forDeal: deal) else { return false }
            model.beginPlacingJoker()
            return true
        }
    }

    private var hopelessBinding: Binding<Bool> {
        Binding(get: { model.showsHintHopeless }, set: { if !$0 { model.dismissHintHopeless() } })
    }

    /// ヒントの入口。無料の残りがあればそのまま読み、使い切っていたら読んでから広告を出す（#2025）。
    /// 読みは画面を離れたら取り消す（離脱後に確定すると回数・解析・中断データが動く・#1903）。
    private func requestHint() {
        guard !hintRescue.isWatching, model.canUseHint else { return }
        if model.needsAdForHint {
            hintRescue.requestHandledByModel(withOutcome: { readDidFinish in await model.requestAdHint(readDidFinish: readDidFinish) }, until: services.screenGeneration)
        } else {
            services.screenGeneration.runUntilLeave { await model.requestHint() }
        }
    }

    /// 「戻す」の入口を 1 本にまとめる（#476）。
    ///
    /// 残り回数があればそのまま戻し、使い切っていたら**提案を出すだけ**にする。
    /// ここで広告を直接出さないのが要で、押した瞬間に再生が始まると
    /// 「戻すつもりが広告を見せられた」になる（決裁の「自動再生禁止」）。
    private func requestUndo() {
        if model.needsUndoRefill {
            showUndoRefillPrompt = true
        } else {
            model.undo()
        }
    }

    /// リワード広告 → 「戻す」の補充。視聴しなかったときと補充できなかったときを読み分けて必ず知らせる。
    private func requestUndoRefill() {
        // どの局に対する補充かを、広告を出す前に控える。ボタンの `disabled` だけでは
        // ツールバーの「新規ゲーム」からの配り直しを止められない（PR #480 の敵対的検証）。
        let deal = model.dealSerial
        undoRescue.request(
            services, gameID: model.gameID, purpose: .undo,
            guardedBy: .checkedByGrant
        ) {
            model.grantUndos(forDeal: deal)
        }
    }
}

// MARK: - くわしいルール

/// 「遊び方」シートから開く詳細ページ。組み方は `MahjongSolitaireRuleSheet` と同じ。
struct SolitaireRuleSheet: View {
    /// 文言はテストから検証したいので型の外に出しておく。
    static var rules: [(String, String)] { [
        (tr("ゲームの流れ"), tr("配られた52枚を、右上の組札（4か所）に ♠♥♦♣ ごとに A から K まで順に積み上げれば クリアです。クロンダイクと呼ばれる、いちばん標準的なソリティアです")),
        (tr("場札の並べ方"), tr("場札（下の7列）には、ひとつ上の札より1つ小さくて色ちがいの札だけを置けます（黒の8 の上には 赤の7）。そろっている並びは何枚でもまとめて動かせます")),
        (tr("空いた列"), tr("札が無くなった列に置けるのは K だけです。K を引くまで空けておくか、思い切って埋めるかがクロンダイクの読みどころです")),
        (tr("山札"), tr("左上の山札はタップでめくれます。最後までめくったらもう一度タップすると、捨て札が山札に戻ります（何周でもできます）")),
        (tr("めくり方を選ぶ"), tr("「新規ゲーム」を押すと、山札を1枚ずつめくるか3枚ずつめくるかを選べます。3枚めくりでは使えるのがいちばん上の1枚だけになるぶん歯ごたえがあり、自己ベストは1枚めくりとは別に記録されます（Game Center の順位表に載るのは1枚めくりだけです）。選んだめくり方はその配札のあいだ変わりません")),
        (tr("操作"), tr("動かしたい札をタップして選び、置きたい列か組札をタップします。ドラッグでも動かせます。もう一度同じ札をタップすると選択を外せます。同じ札をすばやく2回タップすると組札へ送れます。あとは積むだけになったら、右下の「⋯」の「自動で上がる」で残りをまとめて組札へ送れます")),
        (tr("戻す"), tr("「戻す」は1局につき%1$lld回まで無料です。残り回数はボタンに出ています。使い切ったあとは、広告を見ると%2$lld回ぶん補充できます", SolitaireUndoBudget.free, SolitaireUndoBudget.refill)),
        (tr("ジョーカー"), tr("1局につき1枚持っています。場札の列の上に置くと、その上にはどんな札でも1枚だけ重ねられます（空の列と、すでにジョーカーがある列には置けません）。上の札が全部はけると自動で消えて、下の札がまた使えるようになります")),
        (tr("ジョーカーの補充"), tr("使い切ったあと、手詰まりになったときや、指せる手はあってもクリアできなくなったときに、広告を見て1枚受け取れます。「戻す」でジョーカーを置いた手を巻き戻せば、手持ちに戻ります。ジョーカーを使ってクリアした記録は、自己ベストには残りますが Game Center の順位表には送りません")),
        (tr("配られる札"), tr("出題する配札は、すべて事前にコンピュータで解いてクリアできることを確かめてあります。行き止まりは配りのせいではなく、指し方で変わります")),
    ] }

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
