import SwiftUI

/// ヘッダーの右端に置く「自己ベスト」の小さな表示（#2615）。
///
/// 現在値（スコア・手数）の隣に並べて、プレイ中に自己ベストと見比べられるようにする。
/// 現在値の列より背が低くなる寸法（見出し 12pt・値 20pt）にしてあるので、足してもヘッダーの高さは変わらない
/// （#148 の盤の高さ確保を守る）。2048 と 15 パズルで部品と文字の大きさを揃えるために Core に置く。
public struct HeaderBestStat: View {
    private let title: String
    private let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .themeCaption(12, weight: .bold, maxScale: 1.5)
                .foregroundStyle(Theme.inkSubText)
            Text(value)
                .themeBody(20, weight: .heavy, maxScale: 1.5).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.inkSubText)
                .contentTransition(.numericText())
        }
    }
}
