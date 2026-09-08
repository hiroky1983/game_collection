import Foundation

/// 盤・ピースが占めるマス 1 つ。ピースの中では左上を (0, 0) とした相対座標で使う。
public struct BlockPuzzleCell: Codable, Equatable, Sendable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

/// 盤に置く 1 個のピース。
///
/// 形は**ジェネリックなポリオミノだけ**を使う（#493 の権利チェック）。落下は入れないので
/// 回転も持たない。回転させたい向きはカタログに別のピースとして並べてある
/// （回転を実装すると「どの向きが配られたか」を中断スナップショットに書く必要が出るうえ、
/// 置き型パズルの定番は回転なしのため）。
public struct BlockPuzzlePiece: Codable, Equatable, Sendable, Identifiable {
    /// カタログ内の番号。中断スナップショットにはこの番号だけを書く。
    public let id: Int
    /// 占めるマス。左上を (0, 0) に正規化してある（最小行・最小列が必ず 0）。
    public let cells: [BlockPuzzleCell]

    public init(id: Int, cells: [BlockPuzzleCell]) {
        self.id = id
        self.cells = cells
    }

    /// 外接矩形の高さ（行数）。
    public var height: Int { (cells.map(\.row).max() ?? 0) + 1 }
    /// 外接矩形の幅（列数）。
    public var width: Int { (cells.map(\.col).max() ?? 0) + 1 }
    /// 占めるマスの数。そのまま配置点になる。
    public var size: Int { cells.count }

    /// 盤の描画に使う色の番号（1...5）。マス数から決まるので、同じ形は必ず同じ色になる。
    /// 0 は「空きマス」に予約してあるので使わない。
    public var colorIndex: Int { (size - 1) % 5 + 1 }
}

public extension BlockPuzzlePiece {
    /// 配られうるピースの全量。
    ///
    /// 並びは**変えてはならない**。`id` は配列の添字そのもので、中断スナップショットに
    /// 保存されているため、順を入れ替えると既存プレイヤーの中断データが別の形に化ける。
    /// 足すときは必ず末尾に足す。
    ///
    /// 外接矩形は最大でも 5×1 / 1×5 / 3×3 に収まる。この上限は
    /// `BlockPuzzleBoard.revive`（コンティニューで空ける領域）が 5×5 であることの前提になっている。
    static let catalog: [BlockPuzzlePiece] = {
        var shapes: [[(Int, Int)]] = []

        // 直線（縦横 1〜5 マス）。1×1 は 1 つだけ（縦横の区別が無い）。
        shapes.append([(0, 0)])
        for length in 2...5 {
            shapes.append((0..<length).map { (0, $0) })   // 横
            shapes.append((0..<length).map { ($0, 0) })   // 縦
        }

        // 正方形。
        shapes.append([(0, 0), (0, 1), (1, 0), (1, 1)])                              // 2×2
        shapes.append((0..<3).flatMap { r in (0..<3).map { c in (r, c) } })           // 3×3

        // L 字（2×2 の角を 1 つ欠いた 3 マス）を 4 向き。
        shapes.append([(0, 0), (1, 0), (1, 1)])
        shapes.append([(0, 0), (0, 1), (1, 1)])
        shapes.append([(0, 1), (1, 0), (1, 1)])
        shapes.append([(0, 0), (0, 1), (1, 0)])

        // 大きい L 字（3×3 の 2 辺だけ = 5 マス）を 4 向き。
        shapes.append([(0, 0), (1, 0), (2, 0), (2, 1), (2, 2)])
        shapes.append([(0, 0), (0, 1), (0, 2), (1, 2), (2, 2)])
        shapes.append([(0, 0), (0, 1), (0, 2), (1, 0), (2, 0)])
        shapes.append([(0, 2), (1, 2), (2, 0), (2, 1), (2, 2)])

        return shapes.enumerated().map { index, shape in
            BlockPuzzlePiece(id: index, cells: shape.map { BlockPuzzleCell(row: $0.0, col: $0.1) })
        }
    }()

    /// カタログ番号から引く。範囲外は nil（壊れた中断データを読んだときに落とさないため）。
    static func catalogPiece(id: Int) -> BlockPuzzlePiece? {
        catalog.indices.contains(id) ? catalog[id] : nil
    }
}
