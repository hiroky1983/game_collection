import Foundation
import Core

/// フリーセルで扱う1枚（#492）。
///
/// スートは**トランプ共通基盤の `PlayingCardSuit` をそのまま使う**。ソリティア（クロンダイク）が
/// 独自のスート型を持っているのは、あちらがジョーカーを「中継札」というルール上の意味で扱うため
/// （`SolitaireCard.suit` は `Optional`）。フリーセルはジョーカーを使わず 52 枚だけで完結し、
/// **ルール側がスートに求めるものが「色」と「組札の添字」だけ**なので、写す理由が無い。
public struct FreeCellCard: Identifiable, Codable, Sendable, Equatable, Hashable {
    /// 0〜51。`suit.rawValue * 13 + (rank - 1)`。
    public let id: Int
    public let suit: PlayingCardSuit
    /// 1 = A 〜 13 = K。
    public let rank: Int

    public init(_ suit: PlayingCardSuit, _ rank: Int) {
        self.id = suit.rawValue * 13 + (rank - 1)
        self.suit = suit
        self.rank = rank
    }

    public var isRed: Bool { suit.isRed }

    public var rankLabel: String { figure.rankLabel }

    /// ログ・デバッグ用の短い表記（例: "♠A"）。
    public var label: String { figure.label }

    /// 描画・読み上げ用の共通表現（#397 のトランプ54枚基盤）へ写す。
    public var figure: PlayingCardFigure { .pip(suit: suit, rank: rank) }
}

public extension FreeCellCard {
    /// 52 枚の山札（未シャッフル）。フリーセルはジョーカーを使わない。
    static func makeDeck() -> [FreeCellCard] {
        PlayingCardSuit.allCases.flatMap { suit in (1...13).map { FreeCellCard(suit, $0) } }
    }
}

// MARK: - Codable

extension FreeCellCard {
    /// `PlayingCardSuit` は描画専用のため `Codable` を持たない（Core の設計どおり）。
    /// 保存はゲーム側の責務なので、ここで `id` 1 個だけに落として持つ。
    /// **`id` からスートとランクは一意に復元できる**ので、情報は失われない。
    public init(from decoder: Decoder) throws {
        let id = try decoder.singleValueContainer().decode(Int.self)
        guard (0...51).contains(id), let suit = PlayingCardSuit(rawValue: id / 13) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "フリーセルの札の id が範囲外です: \(id)"))
        }
        self.init(suit, id % 13 + 1)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}
