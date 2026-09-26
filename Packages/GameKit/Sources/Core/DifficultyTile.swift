import SwiftUI

/// 難易度・CPU の強さのタイルの寸法と色を 1 か所で持つ（#1417）。
///
/// 将棋・チェス・五目並べ・オセロ・囲碁の `CPUStrengthPicker` も、花札・ナンプレ・スパイダー・
/// マインスイーパー・神経衰弱・カードしりとりの段選択も、**大きさと色の並びをここに揃える**。
/// 色は `CPUStrength.accent` と同じ並び（入門=ピンク・かんたん=ティール・ふつう=黄・むずかしい=コーラル）で、
/// 3 段階は末尾の 3 色（ティール／黄／コーラル）を使う。
public enum DifficultyTile {
    /// タイルの寸法。最長の「むずかしい」は狭い端末（iPhone SE）で縮めて 1 行に収める。
    public static let metrics = GameSetupChooser.Metrics(
        title: .body(15), subtitleSize: 11, verticalPadding: 14,
        titleMinimumScale: 0.7, subtitleMinimumScale: 0.7
    )

    /// やさしい順に並べた面色（`CPUStrength.allCases` と同じ並び）。
    private static let ladder: [Color] = CPUStrength.allCases.map(\.accent)

    /// `count` 段階のうち、やさしい方から `step` 番目（0 始まり）の面色。
    /// 段が少ないときは難しい側の色に寄せる（3 段階なら ティール／黄／コーラル）。
    public static func accent(step: Int, of count: Int) -> Color {
        let colors = ladder.suffix(max(1, count))
        let index = min(max(step, 0), colors.count - 1)
        return colors[colors.startIndex + index]
    }
}
