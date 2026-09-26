import SwiftUI

/// 「⋯」メニューに入れるヒント（#1421）。`BoardHintModel` の読む分だけを、ジェネリクスを持ち越さない形に詰める。
public struct BoardControlBarHint {
    let remaining: Int
    let isEnabled: Bool
    let isThinking: Bool
    let request: () -> Void
    /// 30 秒以上操作が無いときに出す促し（#1424）。
    let nudge: HintNudge

    /// - Parameter activity: 操作のたびに値が変わる印（手数・選択など）。変わると促しの待ち時間を数え直す。
    @MainActor
    public init<Model: BoardHintModel>(_ model: Model, activity: AnyHashable) {
        remaining = model.hintsRemaining
        isEnabled = model.canUseHint
        isThinking = model.isHintThinking
        nudge = HintNudge(isEligible: model.canUseHint, activity: activity)
        // 読みは Model の中で `AITurnGuarded` の照合に載せる（押したあとの局面ずれはそこで弾く）。
        request = { Task { await model.requestHint() } }
    }
}

/// 盤の下の操作行（盤ゲーム 5 本・#1421）。
///
/// 左＝待った（ティールのカプセル）、中央＝ゲーム固有（囲碁のパス）、右端＝「⋯」メニュー。
/// メニューには投了（押したあと確認ダイアログ）とヒント（残り回数つき）を入れる。
///
/// **高さは 44pt 固定**（`BoardGameControlMetrics.minTapTarget` + 上下の余白）。決着で中身が
/// 検討ナビに入れ替わっても、対局中の操作行が伸び縮みして盤が縮むことがないようにする（#139・#148）。
public struct BoardGameControlBar<Model: BoardUndoModel, Center: View>: View {
    private let model: Model
    private let services: GameServices
    private let undoRescue: RewardedRescue
    private let hint: BoardControlBarHint?
    private let onResign: () -> Void
    private let center: Center
    @State private var showResignConfirm = false

    /// - Parameter rescue: 救済は呼び出し側の `@State` から受け取る（`BoardUndoButton` と同じ理由）。
    public init(
        model: Model,
        services: GameServices,
        rescue: RewardedRescue,
        hint: BoardControlBarHint? = nil,
        onResign: @escaping () -> Void,
        @ViewBuilder center: () -> Center
    ) {
        self.model = model
        self.services = services
        self.undoRescue = rescue
        self.hint = hint
        self.onResign = onResign
        self.center = center()
    }

    public var body: some View {
        HStack(spacing: 12) {
            BoardUndoButton(model: model, services: services, rescue: undoRescue, usesTapTargetCapsule: true)
            Spacer(minLength: 0)
            center
            Spacer(minLength: 0)
            moreMenu
        }
        .themeBody(14)
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(height: BoardGameControlMetrics.minTapTarget)
        .padding(.horizontal, 16).padding(.vertical, BoardGameControlMetrics.rowVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
        .boardResignConfirmation(isPresented: $showResignConfirm, onResign: onResign)
        .hintNudge(hint?.nudge)
    }

    private var moreMenu: some View {
        Menu {
            if let hint {
                Button(action: hint.request) {
                    Label(hint.isThinking ? "ヒント（読み中…）" : "ヒント（残り\(hint.remaining)回）",
                          systemImage: "lightbulb.fill")
                }
                .disabled(!hint.isEnabled)
                .accessibilityHint(hint.isEnabled ? "最善手を1手だけ盤の上に示します。使った対局は順位表に送りません"
                                                 : "いまは使えません（あなたの手番ではないか、使い切りました）")
            }
            Button(role: .destructive) { showResignConfirm = true } label: {
                Label("投了", systemImage: "flag.fill")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Color.white)
                // 待ったと同じ手（`BoardGameControlCapsuleStyle`）: カプセルを描いてから 44pt の枠で受ける。
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.fillMuted))
                .frame(minWidth: BoardGameControlMetrics.minTapTarget, minHeight: BoardGameControlMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("その他の操作")
        .accessibilityHint(hint == nil ? "投了できます" : "ヒントと投了を選べます")
    }
}

public extension BoardGameControlBar where Center == EmptyView {
    init(
        model: Model,
        services: GameServices,
        rescue: RewardedRescue,
        hint: BoardControlBarHint? = nil,
        onResign: @escaping () -> Void
    ) {
        self.init(model: model, services: services, rescue: rescue, hint: hint, onResign: onResign) { EmptyView() }
    }
}
