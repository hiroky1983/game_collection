import SwiftUI

public extension CPUStrength {
    /// タイルの面色。上に載る文字は `Theme.onAccent`（#220）。
    /// 既存 3 段階の色（teal / yellow / coral）は動かさず、下に pink を足している。
    /// 「ガチ」（purple）は v1.1.6 で一旦見送り（`CPUStrength.swift` 参照）。
    var accent: Color {
        switch self {
        case .novice: return Theme.Fill.pink
        case .easy:   return Theme.Fill.teal
        case .normal: return Theme.Fill.yellow
        case .hard:   return Theme.Fill.coral
        }
    }
}

/// 開始シートで「CPUの強さ」を選ぶ段階の並び（#1174）。
///
/// 「ガチ」を含む5段階だったときにタイルの中に副題（探索の中身）まで入れると iPhone SE では
/// 読めない大きさになった経緯があり、そこで**タイルは呼び名だけ**にし、選んでいる段の説明を
/// 下の1行に出す形にした。「表示している文言と探索の中身を一致させる」約束（#416）はこの
/// 1行が引き継ぐので、`details` には各ゲームのエンジンが実際にやっていることを書くこと。
///
/// 「ガチ」を見送って4段階になったので、3列×2段（5個目だけ余る不格好な形）をやめ、
/// **1行4列**に戻した（会長指摘・2026-09-22「4つにしたなら横一列にできないか」）。
///
/// 4 ゲーム（将棋・チェス・五目並べ・オセロ）が同じ部品を使い、寸法も色も揃える。
/// 呼び出し側は節の見出しごと `GameSetupSection("CPUの強さ")` で包む。
public struct CPUStrengthPicker: View {
    /// 段ごとの説明。**やさしい順**に `CPUStrength.allCases` と同じ並び。
    private let details: [String]
    @Binding private var level: Int

    /// 寸法は他ゲームの難易度タイルと同じ（`DifficultyTile`・#1417）。
    private static let metrics = DifficultyTile.metrics

    public init(level: Binding<Int>, details: [String]) {
        _level = level
        self.details = details
    }

    /// 段に対応する説明。段の数と説明の数が食い違っても落ちないようにしておく。
    private func detail(_ strength: CPUStrength) -> String {
        details.indices.contains(strength.ladderIndex) ? details[strength.ladderIndex] : ""
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(CPUStrength.allCases, id: \.rawValue) { strength in
                    GameSetupChooser(
                        title: strength.label, subtitle: "",
                        selected: level == strength.rawValue,
                        accent: strength.accent, metrics: Self.metrics
                    ) { level = strength.rawValue }
                        // 読み上げでは説明もタイルに添える（画面では選んだ段のぶんしか出ないため）。
                        .accessibilityLabel("\(strength.label)、\(detail(strength))")
                }
            }
            // 段を選び直しても高さが変わらないよう 1 行に固定する（シートが伸び縮みしない）。
            Text(detail(CPUStrength.strength(for: level)))
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        }
    }
}
