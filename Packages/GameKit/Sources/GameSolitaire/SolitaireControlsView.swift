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
        ZStack(alignment: .top) {
            finishedControls { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if model.phase == .won {
                finishedControls {
                    RecommendationSlot(services: services, isFinished: true)
                }
            } else {
                gameControls
            }
        }
    }

    private func finishedControls<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            resultControls
            recommendation()
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
        HStack(spacing: 8) {
            // 残り回数を常時見せる（#476 仕様3）。ナンプレの「ヒント3」と同じ見せ方に揃えてある。
            controlButton(
                "戻す\(model.undosRemaining)",
                systemImage: "arrow.uturn.backward",
                tint: Theme.Fill.coral
            ) {
                onUndo()
            }
            .disabled(!model.canUndo || isWatchingUndoAd)
            // 押せない間も枠は残す（消えると「そんな機能は無い」と読まれる・#198 と同じ扱い）。
            .opacity(model.canUndo ? 1 : 0.4)
            .accessibilityLabel(SolitaireAccessibility.undoButtonLabel(remaining: model.undosRemaining))
            .accessibilityHint(SolitaireAccessibility.undoButtonHint(
                canUndo: model.canUndo,
                remaining: model.undosRemaining
            ))

            // ジョーカーの所持を**常時**見せる（#406 の決裁1）。持っていない間も枠を残すのは
            // 「戻す」と同じ理由で、消すと「そんな機能は無い」と読まれるため（#198）。
            jokerButton

            // 「あとは組札へ積むだけ」になった局面でだけ出す。終盤の 52 回タップを 1 回に畳む。
            if model.canAutoFinish {
                controlButton("自動で上がる", systemImage: "wand.and.stars", tint: Theme.Fill.teal) {
                    model.autoFinish()
                }
                .accessibilityHint("残りの札をまとめて組札へ送ります")
            }

            Spacer(minLength: 0)

            // 標準以外のルールで遊んでいるときだけ出す（#498）。既定の1枚めくりは
            // 「標準」そのものなので札は出さず、操作列の見た目を従来のまま保つ。
            if model.rules.drawMode != .one {
                Text(model.rules.drawMode.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("このゲームのルールは\(model.rules.drawMode.label)")
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
        .overlay(alignment: .top) {
            if model.isPlacingJoker { jokerPlacingBanner }
        }
    }

    /// ジョーカーの所持ボタン。押すと「置く列を選ぶ」モードに入り、もう一度押すと抜ける。
    private var jokerButton: some View {
        controlButton(
            model.isPlacingJoker ? "やめる" : "ジョーカー",
            systemImage: model.isPlacingJoker ? "xmark.circle.fill" : "questionmark.app.fill",
            tint: model.isPlacingJoker ? Theme.Fill.teal : Theme.Fill.purple
        ) {
            if model.isPlacingJoker { model.cancelPlacingJoker() } else { model.beginPlacingJoker() }
        }
        .disabled(!model.hasJoker && !model.isPlacingJoker)
        .opacity(model.hasJoker || model.isPlacingJoker ? 1 : 0.4)
        .accessibilityLabel(SolitaireAccessibility.jokerButtonLabel(
            hasJoker: model.hasJoker,
            isPlacing: model.isPlacingJoker
        ))
        .accessibilityHint(SolitaireAccessibility.jokerButtonHint(
            hasJoker: model.hasJoker,
            isPlacing: model.isPlacingJoker
        ))
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

    private func controlButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12)
                // 高さは 44pt（#199 で全ゲームの操作ボタンに揃えた下限）。
                .frame(minHeight: 44)
                .background(Capsule().fill(tint))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }
}
