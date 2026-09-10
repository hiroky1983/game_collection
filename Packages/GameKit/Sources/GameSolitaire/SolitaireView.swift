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

    private let services: GameServices

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: SolitaireModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            SolitaireBoardView(model: model, services: services).layoutPriority(1)
            HowToPlayHint(.solitaire, playLog: services.playLog)
            SolitaireControlsView(
                model: model,
                services: services,
                isWatchingUndoAd: undoRescue.isWatching,
                onUndo: requestUndo
            )
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .gameChrome(title: "ソリティア", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button { openSetup() } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("新しい配札にする")
            }
        }
        .howToPlay(.solitaire) { SolitaireRuleSheet() }
        // めくり方を選んでから配る（#498）。局に焼き込むのは「配る」を押した瞬間だけ。
        .sheet(isPresented: $showSetup) {
            SolitaireSetupSheet(draft: $draft, discardsProgress: model.canUndo) {
                showSetup = false
                model.newGame(rules: draft)
            }
        }
        .rewardedRescueAlerts(
            jokerRescue,
            notEarned: "ジョーカーをもらえませんでした",
            unavailable: RewardUnavailableAlert(
                title: "ジョーカーを受け取れませんでした",
                message: "広告を見ているあいだに局面が変わったため、ジョーカーを追加できませんでした。\n手持ちのジョーカーはそのまま残っています。"
            )
        )
        .alert("無料の「戻す」を使い切りました", isPresented: $showUndoRefillPrompt) {
            Button("広告を見て\(SolitaireUndoBudget.refill)回補充する") { requestUndoRefill() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴すると「戻す」を\(SolitaireUndoBudget.refill)回ぶん補充します。\n盤面はそのままです。")
        }
        .rewardedRescueAlerts(
            undoRescue,
            notEarned: "「戻す」を補充できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "「戻す」を補充できませんでした",
                message: "広告を見ているあいだに配り直されたか、局が終わったため、補充できませんでした。\n新しい配札の「戻す」は無料の回数まで戻っています。"
            )
        )
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
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影用（#397）: 遊んでいる最中の盤面を機械的に作る。シミュレータは自動タップが
            // できないため、初期配置以外を撮る手段がこれしかない（囲碁の `-goMidgame` と同じ理由）。
            if ProcessInfo.processInfo.arguments.contains("-solitaireMidgame") {
                model.applyPreviewProgressForTesting()
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
        .onDisappear { model.pauseTimer() }
    }

    /// 開始シートを開く。**いま遊んでいるルールを初期選択にする**（#498）。
    /// 前に開いたときの選択が残っていると、続けて配り直したときに勝手にルールが変わる。
    private func openSetup() {
        draft = model.rules
        showSetup = true
    }

    // MARK: - ステータスバー

    private var statusBar: some View {
        HStack(spacing: 0) {
            Group {
                if model.phase == .won {
                    Label("クリア！", systemImage: "flag.checkered")
                        .themeBody(15)
                        .foregroundStyle(Theme.teal)
                } else {
                    Label("\(model.moveCount)手", systemImage: "hand.tap.fill")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.coral)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 78, alignment: .leading)

            Spacer()

            Text(stateEmoji).font(.system(size: 28))

            Spacer()

            Label(RecordFormat.time(model.elapsedSeconds), systemImage: "clock")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.teal)
                .frame(minWidth: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
        // 3 つの数字が別々に読まれると意味が取りにくいので 1 要素にまとめる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SolitaireAccessibility.statusLabel(
            phase: model.phase,
            elapsedSeconds: model.elapsedSeconds,
            moveCount: model.moveCount,
            isDeadEnd: model.isDeadEnd,
            isLost: model.isLost
        ))
    }

    private var stateEmoji: String {
        if model.phase == .won { return "🎉" }
        if model.isDeadEnd { return "😵" }
        // 敗北確定（#406）。告知を閉じたあとも、ここだけは状態を出し続ける。
        return model.isLost ? "🤔" : "♠️"
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
    static let rules: [(String, String)] = [
        ("ゲームの流れ", "配られた52枚を、右上の組札（4か所）に ♠♥♦♣ ごとに A から K まで順に積み上げれば クリアです。クロンダイクと呼ばれる、いちばん標準的なソリティアです"),
        ("場札の並べ方", "場札（下の7列）には、ひとつ上の札より1つ小さくて色ちがいの札だけを置けます（黒の8 の上には 赤の7）。そろっている並びは何枚でもまとめて動かせます"),
        ("空いた列", "札が無くなった列に置けるのは K だけです。K を引くまで空けておくか、思い切って埋めるかがクロンダイクの読みどころです"),
        ("山札", "左上の山札はタップでめくれます。最後までめくったらもう一度タップすると、捨て札が山札に戻ります（何周でもできます）"),
        ("めくり方を選ぶ", "「新規ゲーム」を押すと、山札を1枚ずつめくるか3枚ずつめくるかを選べます。3枚めくりでは使えるのがいちばん上の1枚だけになるぶん歯ごたえがあり、自己ベストは1枚めくりとは別に記録されます（Game Center の順位表に載るのは1枚めくりだけです）。選んだめくり方はその配札のあいだ変わりません"),
        ("操作", "動かしたい札をタップして選び、置きたい列か組札をタップします。もう一度同じ札をタップすると選択を外せます"),
        ("戻す", "「戻す」は1局につき\(SolitaireUndoBudget.free)回まで無料です。残り回数はボタンに出ています。使い切ったあとは、広告を見ると\(SolitaireUndoBudget.refill)回ぶん補充できます"),
        ("ジョーカー", "1局につき1枚持っています。場札の列の上に置くと、その上にはどんな札でも1枚だけ重ねられます（空の列と、すでにジョーカーがある列には置けません）。上の札が全部はけると自動で消えて、下の札がまた使えるようになります"),
        ("ジョーカーの補充", "使い切ったあと、手詰まりになったときや、指せる手はあってもクリアできなくなったときに、広告を見て1枚受け取れます。「戻す」でジョーカーを置いた手を巻き戻せば、手持ちに戻ります。ジョーカーを使ってクリアした記録は、自己ベストには残りますが Game Center の順位表には送りません"),
        ("配られる札", "出題する配札は、すべて事前にコンピュータで解いてクリアできることを確かめてあります。行き止まりは配りのせいではなく、指し方で変わります"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Self.rules, id: \.0) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.0)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                        Text(rule.1)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
                }
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle("ルール")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
