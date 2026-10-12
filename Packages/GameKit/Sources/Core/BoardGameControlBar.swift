import SwiftUI

/// 「⋯」メニューに入れるヒント（#1421・#1500）。`BoardHintModel` の読む分だけを、ジェネリクスを持ち越さない形に詰める。
public struct BoardControlBarHint {
    let remaining: Int
    var badge: GameActionBadge { .hint(totalRemaining: remaining, needsAd: needsAd) }
    let isEnabled: Bool
    let isThinking: Bool
    /// 無料枠を使い切っていて、次の 1 回に広告が要るか。
    let needsAd: Bool
    /// 広告の救済（失敗アラート・連打ガードに要る。`BoardGameControlBar` が呼び出し側の `@State` から受け取る）。
    let rescue: RewardedRescue
    /// 押したときの処理。読みの Task は画面の世代に載せ、離脱で取り消す（#1903）。
    let request: (GameServices) -> Void
    /// 30 秒以上操作が無いときに出す促し（#1424）。
    let nudge: HintNudge

    /// - Parameter rescue: ヒントの広告救済。呼び出し側の `@State` から受け取る（`BoardUndoButton` と同じ理由。
    ///   ここで新規に持つと、決着で操作行が検討ナビに入れ替わったとき広告のロード中の連打ガードが捨てられる）。
    /// - Parameter game: 局の番号（`gameSerial`）。
    /// - Parameter activity: 操作のたびに値が変わる印（手数・選択など）。変わると促しの待ち時間を数え直す。
    @MainActor
    public init<Model: BoardHintModel>(_ model: Model, rescue: RewardedRescue, game: Int, activity: AnyHashable) {
        remaining = model.hintsRemaining
        needsAd = model.needsAdForHint
        // 広告の視聴中は重ねて押せない（#1500）。
        isEnabled = model.canUseHint && !rescue.isWatching
        isThinking = model.isHintThinking
        self.rescue = rescue
        nudge = HintNudge(isEligible: model.canUseHint, game: game, activity: activity)
        request = { services in
            if model.needsAdForHint {
                // 広告の視聴完了を確かめてから読みに進む（モデルが1本の非同期メソッドで持つ・#526）。
                // 常設の項目で確認を挟まずに広告へ進む契約はナンプレのヒントと同じ（`reward_offer` は数えない）。
                rescue.requestHandledByModel(withOutcome: { await model.requestAdHint() })
            } else {
                // 読みは Model の中で `AITurnGuarded` の照合に載せる（押したあとの局面ずれはそこで弾く）。
                // 画面を離れたら取り消す（離脱後に読みが確定すると回数・game_start・中断データが動く・#1903）。
                services.screenGeneration.runUntilLeave { await model.requestHint() }
            }
        }
    }
}

/// 盤の下の「操作の段」と「⋯」の行（盤ゲーム 5 本・#1421・#1468・#1856）。
///
/// 待った・ゲーム固有の操作（囲碁のパス）・ヒント（残り回数つき）は段のカプセルに並べ（会長決裁 2026-10-06 案A）、
/// 投了（押したあと確認ダイアログ）だけ右下の「⋯」メニューに残す。
///
/// **高さは従来の操作行と同じ（46pt。決着で入れ替わる検討ナビ・結果の行との差を広げない）**（`GameOverflowBar` の 44pt + 上下の余白）。決着で中身が検討ナビに
/// 入れ替わっても、対局中の行が伸び縮みして盤が縮むことがないようにする（#139・#148）。
public struct BoardGameControlBar<Model: BoardUndoModel>: View {
    private let model: Model
    private let services: GameServices
    private let undoRescue: RewardedRescue
    private let hint: BoardControlBarHint?
    private let extraItems: [GameControlMenuItem]
    private let onResign: () -> Void
    @State private var showResignConfirm = false
    @State private var showUndoConfirm = false

    /// - Parameter rescue: 救済は呼び出し側の `@State` から受け取る（`BoardUndoButton` と同じ理由）。
    /// - Parameter extraItems: ゲーム固有の項目（囲碁のパス）。「⋯」の中で投了の前に並ぶ。
    public init(
        model: Model,
        services: GameServices,
        rescue: RewardedRescue,
        hint: BoardControlBarHint? = nil,
        extraItems: [GameControlMenuItem] = [],
        onResign: @escaping () -> Void
    ) {
        self.model = model
        self.services = services
        self.undoRescue = rescue
        self.hint = hint
        self.extraItems = extraItems
        self.onResign = onResign
    }

    public var body: some View {
        if let hint {
            overflowBar
                // 広告視聴の失敗（未視聴・局面変化）はここで知らせる（#1500。待った・コンティニューの幕と同じ部品）。
                .rewardedRescueAlerts(
                    hint.rescue,
                    notEarned: "ヒントを表示できませんでした",
                    unavailable: RewardUnavailableAlert(
                        title: "ヒントを出せませんでした",
                        message: "広告を見ているあいだに局面が変わったため、ヒントを出せませんでした。"
                    )
                )
        } else {
            overflowBar
        }
    }

    private var overflowBar: some View {
        GameOverflowBar(
            menuItems: menuItems,
            actions: actions,
            verticalPadding: BoardGameControlMetrics.rowVerticalPadding,
            // 投了・待ったの確認が開いている間は促しの待ちを止める（閉じた直後に吹き出しが出るのを防ぐ）。
            nudge: hint.map {
                HintNudge(isEligible: $0.nudge.isEligible && !showResignConfirm && !showUndoConfirm,
                          game: $0.nudge.game, activity: $0.nudge.activity)
            }
        )
        .boardUndoFlow(model: model, services: services, rescue: undoRescue, isPresented: $showUndoConfirm)
        .boardResignConfirmation(isPresented: $showResignConfirm, onResign: onResign)
    }

    /// 段（#1856・案A）: 待った → ヒント（広告が絡む操作だけ。会長決裁 2026-10-06 追加）。
    /// ゲーム固有の項目（囲碁のパス）と投了は広告が無いので「⋯」に残す。
    /// 待ったは 1 局 1 回無料（「あと1回」）、使ったあとは毎回広告（「▶ 広告を見て」）。
    /// ヒントは無料枠の残りを「あと n 回」で、使い切ったあとは広告ぶんの残りを「▶ あと n 回」で出す（#1500 と同じ数）。
    private var actions: [GameActionItem] {
        // 待った・ヒントは別々の広告救済を持つ（`undoRescue` / `hint.rescue`）。片方の視聴中に
        // もう片方も広告を要求すると、2本目のロードが失敗して見ていないのに失敗アラートが出る
        // （麻雀ソリティアの PR #577 と同型の穴）。同じ段に同居させる以上、互いの視聴中は塞ぐ。
        let hintIsWatching = hint?.rescue.isWatching ?? false
        var items = [
            GameActionItem(
                id: "undo",
                title: "待った",
                systemImage: "arrow.uturn.backward",
                role: .undo,
                badge: model.undoUsed ? .ad() : .count(1),
                isEnabled: model.canUndo && !hintIsWatching,
                accessibilityHint: model.canUndo ? "あなたの直前の1手を、CPU の応手ごと取り消します" : "いまは使えません"
            ) { showUndoConfirm = true }
        ]
        if let hint {
            items.append(GameActionItem(
                id: "hint",
                title: hint.isThinking ? "読み中…" : "ヒント",
                systemImage: "lightbulb.fill",
                role: .hint,
                badge: hint.badge,
                isEnabled: hint.isEnabled && !undoRescue.isWatching,
                accessibilityHint: hint.isEnabled
                    ? (hint.needsAd ? "広告を視聴すると、最善手をもう1手示します。使った対局は順位表に送りません"
                                    : "最善手を1手だけ盤の上に示します。使った対局は順位表に送りません")
                    : "いまは使えません（あなたの手番ではないか、8回とも使い切りました）",
                action: { hint.request(services) }
            ))
        }
        return items
    }

    /// 「⋯」: ゲーム固有の項目（囲碁のパス）→ 投了（末尾・赤は `GameControlMenu.ordered`）。
    private var menuItems: [GameControlMenuItem] {
        extraItems + [
            GameControlMenuItem(id: "resign", title: "投了", systemImage: "flag.fill", isDestructive: true) {
                showResignConfirm = true
            }
        ]
    }
}
