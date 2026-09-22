import SwiftUI
import Core

/// 記録がゼロの初回だけハブ最上部に出す「はじめの1本」（#721）。
///
/// 出すか・何を出すかは `FirstPick`（Core の純粋関数）が決める。この型は描くだけで、遷移は
/// 呼び出し側の `NavigationLink(value:)` に任せる（グリッドと同じ遷移にしないと `game_open` /
/// `gameDidLeave` の発火点が増える）。
///
/// 見た目はリザルトのレコメンドカード（`RecommendationCard`）に揃える。ただし×は付けない。
/// 閉じたことを覚えるには新しい保存が要り、初めての終局で自然に消えるので不要なため。
///
/// **アニメーションを一切付けない**（受け入れ条件「Reduce Motion 下で表示位置が変わらない」）。
/// 出る・消えるはハブが描き直されたときに切り替わるだけで、位置が動く演出を持たない。
struct HubFirstPickCard: View {
    let module: GameModule
    /// アイコンチップと「あそぶ」の**面色**。上に載せる文字は `Theme.onAccent`（#220）。
    let accentFill: Color

    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        HStack(spacing: layout.scaled(12)) {
            RoundedRectangle(cornerRadius: layout.scaled(8), style: .continuous)
                .fill(accentFill.gradient)
                .frame(width: layout.scaled(36), height: layout.scaled(36))
                .overlay {
                    module.icon
                        .font(.system(size: layout.scaled(18), weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("はじめてなら、これ")
                    .themeCaption(layout.scaled(11), weight: .semibold)
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                Text(module.title)
                    .themeBody(layout.scaled(16))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Text("あそぶ")
                .themeCaption(layout.scaled(13))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(accentFill))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(corner: Theme.cornerSmall)
        // 3つの文字をばらばらに読ませず、カードを1要素にまとめる（グリッドのカードと同じ作法）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("はじめてなら、これ。\(module.title)")
        .accessibilityHint("\(module.title)を開きます")
    }
}
