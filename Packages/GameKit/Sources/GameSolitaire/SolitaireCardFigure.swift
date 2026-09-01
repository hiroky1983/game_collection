import Core

/// ルール上のカード（`SolitaireCard`）を、描画・読み上げ用の共通表現（#397 のトランプ54枚基盤）へ写す。
///
/// ルール型と描画型を分けているのは基盤側の設計どおり（ソリティアはジョーカーが中継札という
/// このゲーム固有の意味を持つため、面の表現に混ぜない）。写像はこの 1 か所に閉じる。
public extension SolitaireCard {
    var figure: PlayingCardFigure {
        guard let suit, !isJoker else { return .joker }
        return .pip(suit: suit.playingCardSuit, rank: rank)
    }
}

public extension SolitaireSuit {
    var playingCardSuit: PlayingCardSuit {
        // `rawValue` はどちらも spade=0 / heart=1 / diamond=2 / club=3 で揃えてあるが、
        // 片方の並びが変わったときに黙って別のスートになるので明示的に写す。
        switch self {
        case .spade:   return .spade
        case .heart:   return .heart
        case .diamond: return .diamond
        case .club:    return .club
        }
    }
}
