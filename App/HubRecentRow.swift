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
    /// 連続プレイ日数の 1 行（#1625）。2 日以上のときだけ渡され、見出しの右に控えめに出す。
    let streakText: String?

    @Environment(\.adaptiveLayout) private var layout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 寸法・色はモック 01（docs/design/hub-redesign-1831）の `.label` / `.recent` / `.rc`（#2175）。
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("つづき・最近"))
                    .themeCaption(layout.scaled(12), weight: .heavy)
                    .foregroundStyle(Theme.inkSubText)
                    // アイコンの並びだけでは何の行か分からないため、見出しとして読ませる。
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let streakText {
                    Label(streakText, systemImage: "flame.fill")
                        .themeCaption(layout.scaled(11), weight: .heavy)
                        .foregroundStyle(Theme.inkSubText)
                        // 最大サイズでは切らずに折り返す（#2935）。既定サイズは 1 行のまま。
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Theme.pad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HubRecentCard.spacing) {
                    ForEach(Array(candidates.enumerated()), id: \.element.gameID) { offset, candidate in
                        if let module = registry.module(id: candidate.gameID) {
                            // グリッドのカードと**同じ** `NavigationLink(value:)`。遷移を自前で
                            // 組むと `gameDidLeave`（#158）の発火点が増え、1プレイの数え方が狂う。
                            // 位置は行の中の 1 始まり（#659）。
                            NavigationLink(value: HubRoute(
                                gameID: candidate.gameID, source: .recent,
                                position: offset + 1, resume: candidate.hasResume
                            )) {
                                HubRecentCard(
                                    module: module,
                                    accent: HubTileStyle.textAccent(for: candidate.gameID),
                                    hasResume: candidate.hasResume
                                )
                            }
                            // グリッドのカードと同じ押下フィードバック（#716）。
                            .buttonStyle(.pop)
                        }
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 4)
            }
            // 影（`popCard` は下へ 16pt 伸びる）が横スクロールの下端で直線に切れるため、
            // 切り抜きを外す。余白で逃がすと行がそのぶん高くなりグリッドが下がる。
            .scrollClipDisabled()
        }
        .padding(.top, 12)
    }
}

/// 「つづき・最近」の1枚。モック 01 の `.rc`: 150 × 52pt・角丸 12・左にタイルと同じ絵の小さい版（32pt・角丸 9）。
private struct HubRecentCard: View {
    /// カード間の間隔。行の `HStack` と幅の計算で同じ値を使う。
    static let spacing: CGFloat = 12

    let module: GameModule
    /// 「つづきから」の**文字色**。タイルの下線と同じゲームごとの差し色（`HubTileStyle`）。
    let accent: Color
    let hasResume: Bool

    @Environment(\.adaptiveLayout) private var layout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// カード1枚の幅。固定にするのは、SE 相当の 320pt でも**2枚目が半分見える**状態を作って
    /// 「横に続いている」ことを分からせるため（中身に任せるとゲーム名の長さで見え方が変わる）。
    private static let width: CGFloat = 150

    var body: some View {
        HStack(spacing: layout.scaled(8)) {
            thumbnail
                .frame(width: layout.scaled(32), height: layout.scaled(32))
                .clipShape(RoundedRectangle(cornerRadius: layout.scaled(9), style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .themeBody(layout.scaled(14), weight: .heavy)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.7)
                Text(hasResume ? tr("つづきから") : tr("また あそぶ"))
                    .themeCaption(layout.scaled(10), weight: .heavy)
                    .foregroundStyle(hasResume ? accent : Theme.inkSubText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    // 英語（#2109）は日本語より横に長い。幅が固定のカードなので、切れる前に縮める。
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.scaled(10))
        // 最大サイズでは固定幅をやめ、文字に合わせて広げる（#2935）。既定サイズは固定幅のまま。
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : layout.scaled(Self.width), alignment: .leading)
        .frame(
            minWidth: dynamicTypeSize.isAccessibilitySize ? layout.scaled(Self.width) : nil,
            maxWidth: dynamicTypeSize.isAccessibilitySize ? layout.scaled(Self.width * 2) : nil,
            alignment: .leading
        )
        .frame(minHeight: layout.scaled(52))
        .background(
            RoundedRectangle(cornerRadius: layout.scaled(Theme.cornerSmall), style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.cardShadow, radius: 5, x: 0, y: 6)
        )
        // 2段の文字をばらばらに読ませず、カードを1要素にまとめる（グリッドのカードと同じ作法）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("%1$@、%2$@", module.title, hasResume ? tr("つづきから") : tr("また あそぶ")))
    }

    /// タイルと同じ絵（名前なしの版・`hubthumb-<id>`）。無ければゲームのアイコンを差し色の面に出す。
    @ViewBuilder
    private var thumbnail: some View {
        if UIImage(named: HubTileStyle.thumbName(for: module.id)) != nil {
            Image(HubTileStyle.thumbName(for: module.id))
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(accent.gradient)
                .overlay {
                    module.icon
                        .font(.system(size: layout.scaled(16), weight: .bold)) // fixed-size: アイコンを入れるバッジの枠（layout.scaled）が固定寸法で、枠に合わせて大きさを決める
                        .foregroundStyle(Theme.onAccent)
                }
        }
    }
}
