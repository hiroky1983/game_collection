import Foundation

/// 指し手。盤上の移動（成り選択つき）または持ち駒打ち。
public enum Move: Equatable, Sendable {
    case board(from: Int, to: Int, promote: Bool)
    case drop(type: PieceType, to: Int)

    /// USI 文字列（例 "7g7f" / "8h2b+" / "P*5e"）。
    public var usi: String {
        switch self {
        case let .board(from, to, promote):
            return Sq.toUSI(from) + Sq.toUSI(to) + (promote ? "+" : "")
        case let .drop(type, to):
            return "\(type.usiLetter)*\(Sq.toUSI(to))"
        }
    }

    /// USI 文字列 → Move。
    public static func fromUSI(_ s: String) -> Move? {
        if s.contains("*") {
            let parts = s.split(separator: "*")
            guard parts.count == 2, parts[0].count == 1,
                  let type = PieceType.from(usiLetter: parts[0].first!),
                  let to = Sq.fromUSI(parts[1]) else { return nil }
            return .drop(type: type, to: to)
        }
        let promote = s.hasSuffix("+")
        let body = promote ? String(s.dropLast()) : s
        guard body.count == 4,
              let from = Sq.fromUSI(body.prefix(2)),
              let to = Sq.fromUSI(body.suffix(2)) else { return nil }
        return .board(from: from, to: to, promote: promote)
    }
}
