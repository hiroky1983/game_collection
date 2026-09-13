import Core

/// 純ロジック側の型を、描画・読み上げ・解析の共通基盤（Core）へ写す口。
///
/// `SpiderCard` / `SpiderSuit` / `SpiderSuitCount` 自体は Core を知らない（`SpiderCard.swift` の注記）。
/// Core に触れる変換はこのファイルだけに集め、盤・配札・ソルバーを `swiftc -O` 単体で回せるようにしておく。
extension SpiderSuit {
    /// 描画用の共通スート。`rawValue` を揃えてあるので写すだけ。
    public var playingCardSuit: PlayingCardSuit {
        PlayingCardSuit(rawValue: rawValue) ?? .spade
    }
}

extension SpiderCard {
    /// 描画・読み上げ用の共通表現（#397 のトランプ基盤）へ写す。
    public var figure: PlayingCardFigure { .pip(suit: suit.playingCardSuit, rank: rank) }
}

extension SpiderSuitCount {
    /// `game_start` の `level`（#500 の語彙）。1 / 2 / 4 スートを入門 / 標準 / 上級に写す。
    public var analyticsLevel: AnalyticsLevel {
        switch self {
        case .one:  return .beginner
        case .two:  return .normal
        case .four: return .hard
        }
    }
}
