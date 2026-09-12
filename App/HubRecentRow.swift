import SwiftUI
import Core

/// ハブ最上部の「つづき・最近」の横1行（#660）。
///
/// 回遊・復帰の既存導線（レコメンドカード・久しぶり枠）はどれもリザルト画面にしか出ず、しかも
/// 通算20終局以上が発火条件（`RecommendationPolicy`）なので、**戻ってきた人がハブを開いた瞬間には
/// 何も出ない**。中断データを持つ人は「戻る理由が既にある人」なので、その導線だけを最上部に置く。
///
/// 何を何番目に出すかは `RecentGames`（Core の純粋関数）が決める。この型は描くだけ。
///
/// 置き場所はグリッドを載せる `ScrollView` の**外**。中に入れると、iPad で縦を使い切るための
/// カード高さ（`AdaptiveLayout.hubCardMinHeight`）がスクロール領域の高さを行数で割り付けるため、
/// この行のぶんだけ中身が溢れて最終行が見切れる（#485）。外に置けば測る対象がそのぶん縮むので、
/// 割り付けの計算を一切触らずに整合する。
struct HubRecentRow: View {
    /// 出す順に並んだ候補（`RecentGames.candidates` の戻り値）。**空なら呼び出し側が描かない**。
    let candidates: [RecentGames.Candidate]
    let registry: GameRegistry
    /// 差し色を引くための、`visibleModules` 内の位置。グリッドのカードと同じ色にするため、
    /// 行の並び順ではなく**ハブの並び順**で引く（同じゲームが2か所で違う色になると別物に見える）。
    let paletteIndexByGame: [String: Int]

    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.scaled(6)) {
            Text("つづき・最近")
                .themeCaption(layout.scaled(12))
                .foregroundStyle(Theme.inkSub)
                .padding(.horizontal, Theme.pad)
                // アイコンの並びだけでは何の行か分からないため、見出しとして読ませる。
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HubRecentCard.spacing) {
                    ForEach(candidates, id: \.gameID) { candidate in
                        if let module = registry.module(id: candidate.gameID) {
                            // グリッドのカードと**同じ** `NavigationLink(value:)`。遷移を自前で
                            // 組むと `gameDidLeave`（#158）の発火点が増え、1プレイの数え方が狂う。
                            NavigationLink(value: candidate.gameID) {
                                HubRecentCard(
                                    module: module,
                                    accent: accent(for: candidate.gameID),
                                    accentFill: accentFill(for: candidate.gameID),
                                    hasResume: candidate.hasResume
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 4)
            }
            // 影（`popCard` は下へ 16pt 伸びる）が横スクロールの下端で直線に切れるため、
            // 切り抜きを外す。余白で逃がすと行がそのぶん高くなりグリッドが下がる。
            .scrollClipDisabled()
        }
        .padding(.top, Theme.pad)
    }

    private func accent(for gameID: String) -> Color {
        Theme.palette[(paletteIndexByGame[gameID] ?? 0) % Theme.palette.count]
    }

    private func accentFill(for gameID: String) -> Color {
        Theme.Fill.palette[(paletteIndexByGame[gameID] ?? 0) % Theme.Fill.palette.count]
    }
}

/// 「つづき・最近」の1枚。グリッドのカードを横倒しにして縮めた形。
private struct HubRecentCard: View {
    /// カード間の間隔。行の `HStack` と幅の計算で同じ値を使う。
    static let spacing: CGFloat = 12

    let module: GameModule
    /// 「つづきから」の**文字色**。明るい地の上に置くので差し色そのままを使う。
    let accent: Color
    /// アイコンチップの**面色**。上に載せる文字は `Theme.onAccent`（#220）。
    let accentFill: Color
    let hasResume: Bool

    @Environment(\.adaptiveLayout) private var layout

    /// カード1枚の幅。固定にするのは、SE 相当の 320pt でも**2枚目が半分見える**状態を作って
    /// 「横に続いている」ことを分からせるため（中身に任せるとゲーム名の長さで見え方が変わる）。
    private static let width: CGFloat = 150

    var body: some View {
        HStack(spacing: layout.scaled(8)) {
            RoundedRectangle(cornerRadius: layout.scaled(Theme.cornerSmall), style: .continuous)
                .fill(accentFill.gradient)
                .frame(width: layout.scaled(32), height: layout.scaled(32))
                .overlay {
                    module.icon
                        .font(.system(size: layout.scaled(16), weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .themeBody(layout.scaled(14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(hasResume ? "つづきから" : "また あそぶ")
                    .themeCaption(layout.scaled(10))
                    .foregroundStyle(hasResume ? accent : Theme.inkSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.scaled(10))
        .padding(.vertical, layout.scaled(8))
        .frame(width: layout.scaled(Self.width), alignment: .leading)
        .popCard(corner: Theme.cornerSmall)
        // 2段の文字をばらばらに読ませず、カードを1要素にまとめる（グリッドのカードと同じ作法）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(module.title)、\(hasResume ? "つづきから" : "また あそぶ")")
    }
}
