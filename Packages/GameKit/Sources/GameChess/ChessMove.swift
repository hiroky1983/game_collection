import Foundation

/// 指し手。
///
/// **キャスリング・アンパッサンに専用のケースを設けない**。どちらも「移動元・移動先」と
/// そのときの局面から一意に決まるため（キング が横に 2 マス動く / ポーンが斜めに空きマスへ動く）、
/// 状態を二重に持たないほうが取り違えが起きない。UCI の表記もこの形と 1 対 1 に対応する
/// （`e1g1` がキャスリング、`e5d6` がアンパッサン、`e7e8q` がプロモーション）。
public struct ChessMove: Equatable, Hashable, Sendable {
    public let from: Int
    public let to: Int
    /// プロモーション先。プロモーションでなければ nil。
    public let promotion: ChessPieceType?

    public init(from: Int, to: Int, promotion: ChessPieceType? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// UCI 文字列（例 "e2e4" / "e7e8q" / "e1g1"）。
    public var uci: String {
        let base = ChessSquare.name(from) + ChessSquare.name(to)
        guard let promotion else { return base }
        return base + String(promotion.fenLetter).lowercased()
    }

    /// UCI 文字列 → ChessMove。
    public static func fromUCI(_ s: String) -> ChessMove? {
        guard s.count == 4 || s.count == 5 else { return nil }
        guard let from = ChessSquare.fromName(s.prefix(2)),
              let to = ChessSquare.fromName(s.dropFirst(2).prefix(2)) else { return nil }
        guard s.count == 5 else { return ChessMove(from: from, to: to) }
        guard let last = s.last,
              let type = ChessPieceType.from(fenLetter: Character(last.uppercased())),
              type.isPromotionTarget else { return nil }
        return ChessMove(from: from, to: to, promotion: type)
    }
}
