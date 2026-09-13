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
    ///   - accent: 「自己ベスト更新！」バッジの差し色。`Theme.Fill` 側を渡す（#220）。
    ///   - textColor: 記録本文の色。暗いオーバーレイの上に直接置く画面（2048・神経衰弱）は
    ///     `.white` を渡す。既定は明るい背景向けの補助文字色（オセロのように暗幕の上でも
    ///     明るいカードに乗る画面はこちらでよい）。
    public init(_ result: RecordResult?, accent: Color = Theme.Fill.coral, textColor: Color = Theme.inkSub) {
        self.result = result
        self.accent = accent
        self.textColor = textColor
    }

    public var body: some View {
        if let result, let line = RecordFormat.resultLine(result.record) {
            HStack(spacing: 8) {
                if result.update.isNewBest {
                    RecordBadge("自己ベスト更新！", accent: accent)
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

/// 「自己ベスト更新！」「ベストタイム更新！」の**バッジ**。
///
/// 以前は差し色で塗りつぶしたカプセルだったが、このアプリのボタン（`actionButton` 等）も差し色の
/// 塗りつぶしなので、リザルトで「次のステージへ」の隣に並ぶと押せるものに見えた
/// （会長 QA 2026-09-14「ボタンと一緒だけど押せる？」）。塗らずに**細い枠線と薄い下地、星印**で
/// 「印」として描き、ボタンと見分けが付くようにする。明るいカードでも暗いオーバーレイでも
/// 差し色の文字で読める。
public struct RecordBadge: View {
    private let text: String
    private let accent: Color

    public init(_ text: String, accent: Color = Theme.Fill.coral) {
        self.text = text
        self.accent = accent
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(accent.opacity(0.14)))
        .overlay(Capsule().strokeBorder(accent, lineWidth: 1.2))
        // 押せる物ではないことを読み上げにも反映する（ボタンの特性を付けない）
        .accessibilityElement(children: .combine)
    }
}
