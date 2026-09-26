import SwiftUI

/// 「⋯」メニューに入れるヒント（#1421）。`BoardHintModel` の読む分だけを、ジェネリクスを持ち越さない形に詰める。
public struct BoardControlBarHint {
    let remaining: Int
    let isEnabled: Bool
    let isThinking: Bool
    let request: () -> Void
    /// 30 秒以上操作が無いときに出す促し（#1424）。
    let nudge: HintNudge

    /// - Parameter game: 局の番号（`gameSerial`）。
    /// - Parameter activity: 操作のたびに値が変わる印（手数・選択など）。変わると促しの待ち時間を数え直す。
    @MainActor
    public init<Model: BoardHintModel>(_ model: Model, game: Int, activity: AnyHashable) {
        remaining = model.hintsRemaining
        isEnabled = model.canUseHint
        isThinking = model.isHintThinking
        nudge = HintNudge(isEligible: model.canUseHint, game: game, activity: activity)
        // 読みは Model の中で `AITurnGuarded` の照合に載せる（押したあとの局面ずれはそこで弾く）。
        request = { Task { await model.requestHint() } }
    }
}

/// 盤の下の「⋯」の行（盤ゲーム 5 本・#1421・#1468）。
///
/// 待った・ゲーム固有の操作（囲碁のパス）・ヒント（残り回数つき）・投了（押したあと確認ダイアログ）を
/// **すべて右下の「⋯」メニューに入れる**（会長決裁 2026-09-26 QA）。投了は末尾・赤（`GameControlMenu.ordered`）。
///
/// **高さは従来の操作行と同じ**（`GameOverflowBar` の 44pt + 上下の余白）。決着で中身が検討ナビに
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
    /// - Parameter extraItems: ゲーム固有の項目（囲碁のパス）。待ったのあと・ヒントの前に並ぶ。
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
        GameOverflowBar(
            menuItems: menuItems,
            // 投了・待ったの確認が開いている間は促しの待ちを止める（閉じた直後に吹き出しが出るのを防ぐ）。
            nudge: hint.map {
                HintNudge(isEligible: $0.nudge.isEligible && !showResignConfirm && !showUndoConfirm,
                          game: $0.nudge.game, activity: $0.nudge.activity)
            }
        )
        .boardUndoFlow(model: model, services: services, rescue: undoRescue, isPresented: $showUndoConfirm)
        .boardResignConfirmation(isPresented: $showResignConfirm, onResign: onResign)
    }

    private var menuItems: [GameControlMenuItem] {
        var items = [
            GameControlMenuItem(
                id: "undo",
                title: model.undoUsed ? "待った（広告を見て）" : "待った（無料）",
                systemImage: "arrow.uturn.backward",
                isEnabled: model.canUndo,
                accessibilityLabel: "待った",
                accessibilityHint: model.canUndo ? "あなたの直前の1手を、CPU の応手ごと取り消します" : "いまは使えません"
            ) { showUndoConfirm = true }
        ]
        items += extraItems
        if let hint {
            items.append(GameControlMenuItem(
                id: "hint",
                title: hint.isThinking ? "ヒント（読み中…）" : "ヒント（残り\(hint.remaining)回）",
                systemImage: "lightbulb.fill",
                isEnabled: hint.isEnabled,
                accessibilityHint: hint.isEnabled ? "最善手を1手だけ盤の上に示します。使った対局は順位表に送りません"
                                                  : "いまは使えません（あなたの手番ではないか、使い切りました）",
                action: hint.request
            ))
        }
        items.append(GameControlMenuItem(id: "resign", title: "投了", systemImage: "flag.fill", isDestructive: true) {
            showResignConfirm = true
        })
        return items
    }
}
