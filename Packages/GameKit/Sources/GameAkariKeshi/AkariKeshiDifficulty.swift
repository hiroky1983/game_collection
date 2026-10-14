import Core

/// 難易度（#1883）。逆生成で押す数＝最短の手数で段階を分ける。盤は 5×5 のまま変えない。
public enum AkariKeshiDifficulty: String, CaseIterable, Codable, Sendable {
    case easy
    case normal
    case hard

    /// 逆生成で押すマスの数（= この盤の最短の手数）。
    public var presses: Int {
        switch self {
        case .easy:   return 4
        case .normal: return 7
        case .hard:   return AkariKeshiLogic.maxPresses
        }
    }

    /// 画面に出す名前（いまの表示言語）。
    public var label: String { label(language: nil) }

    func label(language: AppLanguage?) -> String {
        switch self {
        case .easy:   return tr("かんたん", language: language)
        case .normal: return tr("ふつう", language: language)
        case .hard:   return tr("むずかしい", language: language)
        }
    }

    /// 記録に保存する区分名（日本語のまま・#2199）。表示は `RecordVariantLabels` が引き直す。
    var recordVariantLabel: String {
        RecordVariantLabels.stored(gameID: "akarikeshi", variant: rawValue)
    }

    /// `game_start` の `level` に載せる段階（#500）。
    var analyticsLevel: AnalyticsLevel {
        switch self {
        case .easy:   return .beginner
        case .normal: return .normal
        case .hard:   return .hard
        }
    }
}
