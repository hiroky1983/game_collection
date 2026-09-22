import SwiftUI

/// `BoardToggleButton` の寸法。各ゲームの `Metrics`（帯の高さの見積りに使う）から参照できるよう、
/// View とは別の**アクター隔離の無い**型に置く。
public enum BoardToggleMetrics {

    /// タップ標的の一辺の下限（Apple HIG）。各ゲームの `Metrics` はこの値を参照する。
    public static let minSide: CGFloat = 44

    /// 面の角丸。帯そのもののカード（`Theme.cornerSmall` = 12）より一段だけ小さくする。
    public static let corner: CGFloat = 10

    /// アイコンの大きさ。44pt の面の中で「押せる物」として目に入る下限。
    public static let iconSize: CGFloat = 15

    /// 文字を添える側の左右の余白。アイコンだけの側は 44pt の正方形に収めるので 0。
    public static let titledHorizontalPadding: CGFloat = 10
}

/// 盤の上の帯（ステータスバー）に並べる ON / OFF トグル。拡大切り替え・旗モードのように
/// 「いまどちらの状態か」を面の色で見せ、押すと入れ替わるボタンの共通形。
///
/// 形は麻雀ソリティアの表示切り替え（#197）で決めたものを正とする。マインスイーパー（#203）は
/// タップ標的 44pt だけを移植して面の作りを揃えておらず、アイコン 13pt・角丸 8・枠線なしと
/// 一回り小さいままだった（#641 の会長QA「マインスイーパーは少し小さい」）。同じ形が 2 ヶ所に
/// 手書きされていたのが原因なので、値を揃えるだけでなくここへ寄せて再発を止める。
///
/// 揃えているのは次の 4 点:
/// - タップ標的 44pt 以上（Apple HIG）。背景の角丸ではなく矩形全体で受け、角も取りこぼさない
/// - 押していない側にも薄い差し色と枠線を敷く。`Theme.surface` のままだとカードと同色になり
///   輪郭がどこにも無く「押せる物」に見えない（#197）
/// - 押している側は差し色の面なので `Theme.onAccent`、薄い面の側は本文色（#197・#220）
/// - `.pop` の押下フィードバック（#195）
public struct BoardToggleButton: View {

    private let isOn: Bool
    private let systemImage: String
    private let title: String?
    private let fill: Color
    private let accent: Color
    private let label: String
    private let action: () -> Void

    /// - Parameters:
    ///   - isOn: 押している側かどうか。true なら差し色の面になる。
    ///   - systemImage: SF Symbols 名。
    ///   - title: アイコンの右に添える短い文字。記号 1 つでは「押すと何が起きるか」が伝わらず
    ///     機能の存在自体が初回プレイで気づかれないため、出せるなら出す（#197）。帯に他の要素が
    ///     多く幅が足りない画面（マインスイーパーは残り機雷・タイマー・旗・拡大が同じ行に並ぶ）は
    ///     nil にしてアイコンだけにする。
    ///   - fill: 押している側の面色。`Theme.Fill` 側を渡す（#220）。
    ///   - accent: 押していない側の薄い面と枠線に使う色。`fill` と対になる `Theme` 側を渡す。
    ///   - label: VoiceOver 用のラベル。状態名ではなく「押すと何が起きるか」を書く。
    public init(
        isOn: Bool,
        systemImage: String,
        title: String? = nil,
        fill: Color,
        accent: Color,
        label: String,
        action: @escaping () -> Void
    ) {
        self.isOn = isOn
        self.systemImage = systemImage
        self.title = title
        self.fill = fill
        self.accent = accent
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: BoardToggleMetrics.iconSize, weight: .bold))
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
            // 文字が付く側だけ左右に余白を足す。アイコンだけなら 44pt の正方形に収める。
            .padding(.horizontal, title == nil ? 0 : BoardToggleMetrics.titledHorizontalPadding)
            .frame(minWidth: BoardToggleMetrics.minSide, minHeight: BoardToggleMetrics.minSide)
            .background(
                RoundedRectangle(cornerRadius: BoardToggleMetrics.corner, style: .continuous)
                    .fill(isOn ? fill : accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BoardToggleMetrics.corner, style: .continuous)
                    .strokeBorder(isOn ? .clear : accent.opacity(0.55), lineWidth: 1.5)
            )
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            // 背景の角丸ではなく矩形全体を受ける（角の 44pt も取りこぼさない）。
            .contentShape(Rectangle())
        }
        // `.plain` は自前で描いた背景を通す代わりに押下フィードバックまで消える。
        // そのために用意された `.pop` を使う（#195・`PopButtonStyle`）。
        .buttonStyle(.pop)
        .accessibilityLabel(label)
    }
}
