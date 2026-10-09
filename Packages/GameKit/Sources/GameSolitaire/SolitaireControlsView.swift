import SwiftUI
import Core

/// 盤の下の操作エリア（戻す・ジョーカー・自動で上がる／クリア後の記録とレコメンド）。
///
/// プレイ中（戻す・自動で上がる）とクリア後（記録 + 次のゲーム + レコメンド）で中身が
/// 入れ替わるが、**高さは常に後者の最大構成に揃える**（#148）。ここが伸び縮みすると
/// 盤面（残りの高さいっぱいに札を敷く）が帳尻合わせに縮む。
struct SolitaireControlsView: View {
    let model: SolitaireModel
    let services: GameServices
    /// 「戻す」の補充広告を出している最中（押させない）。
    let isWatchingUndoAd: Bool
    /// 「戻す」の入口。残り回数の判定と広告の提案は画面本体が持つ（#476）。
    let onUndo: () -> Void

    var body: some View {
        GameControlArea(isFinished: model.phase == .won, services: services) {
            resultControls
        } playing: {
            gameControls
        }
    }

    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { model.newGame() } label: {
                Label("次のゲーム", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.game(.primary))
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var gameControls: some View {
        // 戻す（無料 3 回のあと広告）は盤の下の段のカプセルに出し、ジョーカー・自動で上がる（広告なし）は右下の「⋯」に残す
        // （#1468・#1856・会長決裁 2026-10-06「段に出すのは広告が絡む操作だけ」）。
        // 標準以外のルール（3枚めくり）の表示は状態の帯へ移した（`SolitaireView.statusBar`・#498）。
        GameOverflowBar(menuItems: menuItems, actions: actions)
            .overlay(alignment: .top) {
                if model.isPlacingJoker { jokerPlacingBanner }
            }
    }

    /// 段: 戻す。残り回数は 2 行目に出し（#476 仕様3）、無料枠を使い切ったら「▶ 広告を見て」。押せない間も項目は残す（#198）。
    private var actions: [GameActionItem] {
        [
            GameActionItem(
                id: "undo", title: "戻す", systemImage: "arrow.uturn.backward", role: .undo,
                badge: model.undosRemaining > 0 ? .count(model.undosRemaining) : .ad(gain: RewardedUndoBudget.refill),
                isEnabled: model.canUndo && !isWatchingUndoAd,
                accessibilityLabel: SolitaireAccessibility.undoButtonLabel(remaining: model.undosRemaining),
                accessibilityHint: SolitaireAccessibility.undoButtonHint(
                    canUndo: model.canUndo,
                    remaining: model.undosRemaining
                )
            ) { onUndo() },
        ]
    }

    /// 「⋯」に入れる操作（広告の無いもの）。
    private var menuItems: [GameControlMenuItem] {
        [
            // ジョーカーの所持を**常時**見せる（#406 の決裁1）。押すと「置く列を選ぶ」モードに入り、
            // もう一度押すと抜ける。
            GameControlMenuItem(
                id: "joker",
                title: model.isPlacingJoker ? "ジョーカーをやめる" : "ジョーカー",
                systemImage: model.isPlacingJoker ? "xmark.circle.fill" : "questionmark.app.fill",
                isEnabled: model.hasJoker || model.isPlacingJoker,
                accessibilityLabel: SolitaireAccessibility.jokerButtonLabel(
                    hasJoker: model.hasJoker,
                    isPlacing: model.isPlacingJoker
                ),
                accessibilityHint: SolitaireAccessibility.jokerButtonHint(
                    hasJoker: model.hasJoker,
                    isPlacing: model.isPlacingJoker
                )
            ) {
                if model.isPlacingJoker { model.cancelPlacingJoker() } else { model.beginPlacingJoker() }
            },
            // 「あとは組札へ積むだけ」になった局面でだけ押せる。終盤の 52 回タップを 1 回に畳む。
            GameControlMenuItem(
                id: "autoFinish", title: "自動で上がる", systemImage: "wand.and.stars",
                isEnabled: model.canAutoFinish,
                accessibilityHint: "残りの札をまとめて組札へ送ります"
            ) { model.autoFinish() },
        ]
    }

    /// 置き先を選んでいる最中の案内。盤に被せず操作列の上に出す（列をタップさせる必要があるため）。
    private var jokerPlacingBanner: some View {
        Text("ジョーカーを置く列をタップしてください（空の列と、すでにジョーカーがある列には置けません）")
            .scaledFont(12, weight: .bold, design: .rounded)
            .foregroundStyle(Theme.onAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.Fill.purple))
            .padding(.horizontal, 8)
            .offset(y: -34)
            .allowsHitTesting(false)
    }
}
