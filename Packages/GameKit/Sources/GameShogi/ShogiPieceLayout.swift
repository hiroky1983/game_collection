import Foundation

/// 盤上の駒に「移動しても変わらない ID」を与える対応付け（#200）。
///
/// `Position.squares` はマスの配列でしかないため、そのままマスごとに駒を描くと
/// 駒の同一性がマスに紐づく。移動は「移動元のビューが消えて移動先のビューが生まれる」
/// 扱いになり、SwiftUI が座標を補間できない（= 瞬間移動になる）。
/// 直前の配置と新しい局面を突き合わせ、**動いた駒には同じ ID を渡す**ことで補間できるようにする。
///
/// 局面の差分だけを見るので、着手・成り・駒取り・打ち駒に加えて、
/// 検討ナビの前後移動・待った・新規対局のような**任意の局面の入れ替え**にも同じ規則で使える
/// （対応づかない駒は素直に消え、対応づかないマスには新しい駒が現れる）。
struct ShogiPieceLayout: Equatable, Sendable {

    /// 盤上の 1 駒の表示単位。`id` はその駒が盤上に居る間ずっと変わらない。
    struct Placement: Identifiable, Equatable, Sendable {
        let id: Int
        let piece: Piece
        let square: Int
    }

    /// **ID 昇順**で持つ。`ForEach` の並びはそのまま重なり順になるため、マス順にすると
    /// 駒が動くたびに重なり順が入れ替わり、移動中の駒が他の駒の裏に潜る。
    private(set) var placements: [Placement] = []

    /// 次に発行する ID。盤から消えた駒の ID は再利用しない。
    private var nextID = 0

    init() {}

    init(_ position: Position) {
        update(to: position)
    }

    /// 新しい局面へ対応付けを進める。
    mutating func update(to position: Position) {
        // 1. 同じマスに同じ駒が残っているものは、そのまま据え置く。
        var carried: [Int: Placement] = [:]
        var vacated: [Placement] = []
        for placement in placements {
            if position.squares[placement.square] == placement.piece {
                carried[placement.square] = placement
            } else {
                vacated.append(placement)
            }
        }

        // 2. 据え置き以外で駒が居るマス = 「新しく現れたマス」。
        //    マス番号順に処理して、同じ局面からは常に同じ対応付けが出るようにする。
        var next = Array(carried.values)
        for square in 0..<Sq.count {
            guard let piece = position.squares[square], carried[square] == nil else { continue }
            if let reused = takeMatch(for: piece, at: square, from: &vacated) {
                next.append(Placement(id: reused, piece: piece, square: square))
            } else {
                next.append(Placement(id: nextID, piece: piece, square: square))
                nextID += 1
            }
        }

        placements = next.sorted { $0.id < $1.id }
    }

    /// 現れたマスの駒に、居なくなった駒の ID を引き継がせる。
    ///
    /// 成りで `promoted` が変わるため、対応の条件は **同じ手番・同じ駒種**まで。
    /// 候補が複数ある局面（検討ナビの飛び移りなど）では
    /// 「成り状態まで一致するもの」→「近いもの」→「マス番号が小さいもの」の順に選ぶ。
    private func takeMatch(for piece: Piece, at square: Int, from vacated: inout [Placement]) -> Int? {
        var best: (index: Int, key: (Int, Int, Int))?
        for (index, candidate) in vacated.enumerated() {
            guard candidate.piece.color == piece.color, candidate.piece.type == piece.type else { continue }
            let key = (
                candidate.piece == piece ? 0 : 1,
                Self.distance(candidate.square, square),
                candidate.square
            )
            if best == nil || key < best!.key { best = (index, key) }
        }
        guard let best else { return nil }
        return vacated.remove(at: best.index).id
    }

    /// 盤上の 2 マスの隔たり（筋の差 + 段の差）。近い駒を優先して対応づけるためだけに使う。
    private static func distance(_ a: Int, _ b: Int) -> Int {
        abs(Sq.file(a) - Sq.file(b)) + abs(Sq.rank(a) - Sq.rank(b))
    }
}
