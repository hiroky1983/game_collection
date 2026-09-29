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
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var gameControls: some View {
        // 戻す・ジョーカー・自動で上がるは右下の「⋯」にまとめる（#1422・#1468）。
        // 標準以外のルールで遊んでいるときだけ、ルール名を左端に表示だけ出す（#498）。
        // 既定の1枚めくりは「標準」そのものなので出さない。
        GameOverflowBar(
            menuItems: menuItems,
            caption: model.rules.drawMode != .one
                ? GameOverflowCaption(model.rules.drawMode.label,
                                      accessibilityLabel: "このゲームのルールは\(model.rules.drawMode.label)")
                : nil
        )
        .overlay(alignment: .top) {
            if model.isPlacingJoker { jokerPlacingBanner }
        }
    }

    private var menuItems: [GameControlMenuItem] {
        [
            // 残り回数を文言に含める（#476 仕様3）。押せない間も項目は残す（#198）。
            GameControlMenuItem(
                id: "undo", title: "戻す（残り\(model.undosRemaining)）", systemImage: "arrow.uturn.backward",
                isEnabled: model.canUndo && !isWatchingUndoAd,
                accessibilityLabel: SolitaireAccessibility.undoButtonLabel(remaining: model.undosRemaining),
                accessibilityHint: SolitaireAccessibility.undoButtonHint(
                    canUndo: model.canUndo,
                    remaining: model.undosRemaining
                )
            ) { onUndo() },
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
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.onAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.Fill.purple))
            .padding(.horizontal, 8)
            .offset(y: -34)
            .allowsHitTesting(false)
    }
}
