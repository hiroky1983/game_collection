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
    /// `CPUStrength` に無い、1 ゲームだけの段（将棋の「達人」#2698）。共通の段の後ろに並べる。
    public struct ExtraLevel {
        public let level: Int
        public let label: String
        public let accent: Color
        public let detail: String

        public init(level: Int, label: String, accent: Color, detail: String) {
            self.level = level
            self.label = label
            self.accent = accent
            self.detail = detail
        }
    }

    /// 段ごとの説明。**やさしい順**に `CPUStrength.allCases` と同じ並び。
    private let details: [String]
    private let extras: [ExtraLevel]
    @Binding private var level: Int

    /// 寸法は他ゲームの難易度タイルと同じ（`DifficultyTile`・#1417）。
    private static let baseMetrics = DifficultyTile.metrics

    /// 追加の段で 5 列になると「むずかしい」が 2 行に折れるので、そのときだけ 1 行で縮めて収める。
    private var metrics: GameSetupChooser.Metrics {
        var m = Self.baseMetrics
        if !extras.isEmpty {
            m.titleLineLimit = 1
            m.titleMinimumScale = 0.6
        }
        return m
    }

    public init(level: Binding<Int>, details: [String], extras: [ExtraLevel] = []) {
        _level = level
        self.details = details
        self.extras = extras
    }

    /// 段に対応する説明。段の数と説明の数が食い違っても落ちないようにしておく。
    private func detail(_ strength: CPUStrength) -> String {
        details.indices.contains(strength.ladderIndex) ? details[strength.ladderIndex] : ""
    }

    /// 選んでいる段の説明（追加の段を含む）。
    private var selectedDetail: String {
        if let extra = extras.first(where: { $0.level == level }) { return extra.detail }
        return detail(CPUStrength.strength(for: level))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(CPUStrength.allCases, id: \.rawValue) { strength in
                    GameSetupChooser(
                        title: strength.label, subtitle: "",
                        selected: level == strength.rawValue,
                        accent: strength.accent, metrics: metrics
                    ) { level = strength.rawValue }
                        // 読み上げでは説明もタイルに添える（画面では選んだ段のぶんしか出ないため）。
                        .accessibilityLabel(strength.label + tr("、") + detail(strength))
                }
                ForEach(extras, id: \.level) { extra in
                    GameSetupChooser(
                        title: extra.label, subtitle: "",
                        selected: level == extra.level,
                        accent: extra.accent, metrics: metrics
                    ) { level = extra.level }
                        .accessibilityLabel(extra.label + tr("、") + extra.detail)
                }
            }
            // 段を選び直しても高さが変わらないよう 1 行に固定する（シートが伸び縮みしない）。
            Text(selectedDetail)
                .themeBody(13)
                .foregroundStyle(Theme.inkSubText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        }
    }
}
