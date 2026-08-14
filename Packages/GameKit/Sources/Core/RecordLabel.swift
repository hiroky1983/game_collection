import SwiftUI

/// リザルトに 1 行だけ添える自己ベストの表示（#115）。
///
/// **非モーダル・1 行**。既存のリザルト表示（「もう一度」ボタンや結果カード）の邪魔をしないよう、
/// 見出しではなく添え書きの大きさに留める。記録がまだ無ければ何も描画しない。
public struct RecordLabel: View {
    private let result: RecordResult?
    private let accent: Color
    private let textColor: Color

    /// - Parameters:
    ///   - result: `GameServices.gameDidFinish` の戻り値。nil なら何も出さない。
    ///   - accent: 「自己ベスト更新！」の差し色。
    ///   - textColor: 記録本文の色。暗いオーバーレイの上に置く画面（2048・オセロ・神経衰弱）は
    ///     `.white` を渡す。既定は明るい背景向けの補助文字色。
    public init(_ result: RecordResult?, accent: Color = Theme.coral, textColor: Color = Theme.inkSub) {
        self.result = result
        self.accent = accent
        self.textColor = textColor
    }

    public var body: some View {
        if let result, let line = RecordFormat.resultLine(result.record) {
            HStack(spacing: 8) {
                if result.update.isNewBest {
                    Text("自己ベスト更新！")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(accent))
                }
                Text(line)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(textColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(result.update.isNewBest ? "自己ベスト更新。\(line)" : line)
        }
    }
}
