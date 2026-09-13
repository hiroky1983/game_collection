import Foundation

/// 使うスートの数（#717）。世界標準の 3 難度で、少ないほどやさしい。
///
/// 札は常に 2 組 104 枚。スートを減らした分は同じスートを繰り返して 104 枚に揃える
/// （1 スート = ♠ が 8 組）。`rawValue` はスートの数そのもの。
public enum SpiderSuitCount: Int, CaseIterable, Codable, Sendable, Equatable {
    /// 1 スート（♠ ×8 組）。入門。
    case one = 1
    /// 2 スート（♠♥ ×4 組）。標準。
    case two = 2
    /// 4 スート（♠♥♦♣ ×2 組）。上級。
    case four = 4

    /// 使うスート。
    public var suits: [SpiderSuit] {
        switch self {
        case .one:  return [.spade]
        case .two:  return [.spade, .heart]
        case .four: return SpiderSuit.allCases
        }
    }

    /// 1 スートあたり何組入るか（104 枚 ÷ 13 ÷ スート数）。
    public var copiesPerSuit: Int { 8 / rawValue }

    public var label: String { "\(rawValue)スート" }

    /// 開始シート・ステータスの副題。
    public var subtitle: String {
        switch self {
        case .one:  return "入門。♠だけ"
        case .two:  return "標準。♠と♥"
        case .four: return "上級。4種すべて"
        }
    }

    /// 記録の保存先（`GameScore.variant`）。**3 難度すべてに付ける**（ナンプレと同じ）。
    ///
    /// 新規のゲームなので「既定は nil」の規約 3 が守るべき過去の記録は無く、難度ごとに
    /// タイムの水準がまったく違う（1 スートは数分・4 スートは数十分）ため、最初から
    /// 3 行に分けて自己ベストを持つ。
    public var recordVariant: String { "\(rawValue)suit" }

    /// 自己ベストの行に出す区分名。
    public var recordLabel: String { label }
}

/// 1 局に焼き込むルールの束（#717。`docs/ai-devops.md`「1局=1RuleSet」原則）。
///
/// 局の開始時に `SpiderModel` へ焼き込み、進行中の局はこの値だけを見て動く。
/// スナップショットにも書き、復元時はそちらを使う（設定画面を局中に読みに行かない）。
public struct SpiderRuleSet: Equatable, Sendable, Codable {
    public var suitCount: SpiderSuitCount

    public init(suitCount: SpiderSuitCount = .one) {
        self.suitCount = suitCount
    }

    /// 初回の配札に使う既定（1 スート）。起動したらすぐ遊べるように、初回は開始シートを出さない。
    public static let standard = SpiderRuleSet()
}
