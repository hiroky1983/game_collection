import Foundation

/// 石の色。黒が先手、白が後手（五目並べと同じ）。
public enum YonmokuDisc: Int, Codable, Sendable, CaseIterable {
    case black = 0
    case white = 1

    public var opponent: YonmokuDisc { self == .black ? .white : .black }
}

/// 盤の 1 マス。`row` は**下から**数える（0 = 一番下の段）。
public struct YonmokuPoint: Hashable, Sendable, Codable {
    public let col: Int
    public let row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}

/// 立てた盤（横 7 列 × 縦 6 段）。値型なので探索・テストはコピーで済む。
///
/// 石は列の一番下の空き段に入る（上から落とす）。宙に浮いた石は作れない。
public struct YonmokuBoard: Equatable, Hashable, Sendable {
    public static let columns = 7
    public static let rows = 6
    public static let cellCount = columns * rows
    /// 4 つ並べたら勝ち。
    public static let lineLength = 4

    /// `row * columns + col`（row は下から）。
    public private(set) var cells: [YonmokuDisc?]

    public init() {
        cells = Array(repeating: nil, count: Self.cellCount)
    }

    public subscript(col: Int, row: Int) -> YonmokuDisc? {
        get { cells[row * Self.columns + col] }
        set { cells[row * Self.columns + col] = newValue }
    }

    /// その列に入っている石の数（= 次に入る段）。
    public func height(of col: Int) -> Int {
        var h = 0
        while h < Self.rows, self[col, h] != nil { h += 1 }
        return h
    }

    /// その列にまだ入れられるか（範囲外の列は false）。
    public func canDrop(in col: Int) -> Bool {
        (0..<Self.columns).contains(col) && height(of: col) < Self.rows
    }

    /// 入れられる列（左から）。
    public var playableColumns: [Int] { (0..<Self.columns).filter { canDrop(in: $0) } }

    public var discCount: Int { cells.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }

    public var isFull: Bool { discCount == Self.cellCount }

    /// `col` に `disc` を落とし、入ったマスを返す。満杯・範囲外なら nil で盤は変わらない。
    @discardableResult
    public mutating func drop(_ disc: YonmokuDisc, in col: Int) -> YonmokuPoint? {
        guard canDrop(in: col) else { return nil }
        let row = height(of: col)
        self[col, row] = disc
        return YonmokuPoint(col: col, row: row)
    }

    /// `point` の石を含んで 4 つ以上並んだ線（並んだ全マス・端から端の順）。無ければ nil。
    ///
    /// 縦・横・斜め 2 方向を見る。5 つ以上並んだときは並んだ全部を返す（勝ちは変わらない）。
    public func winningLine(through point: YonmokuPoint) -> [YonmokuPoint]? {
        guard let disc = self[point.col, point.row] else { return nil }
        for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
            var line = [point]
            var c = point.col - dc, r = point.row - dr
            while Self.contains(col: c, row: r), self[c, r] == disc {
                line.insert(YonmokuPoint(col: c, row: r), at: 0)
                c -= dc; r -= dr
            }
            c = point.col + dc; r = point.row + dr
            while Self.contains(col: c, row: r), self[c, r] == disc {
                line.append(YonmokuPoint(col: c, row: r))
                c += dc; r += dr
            }
            if line.count >= Self.lineLength { return line }
        }
        return nil
    }

    public static func contains(col: Int, row: Int) -> Bool {
        (0..<columns).contains(col) && (0..<rows).contains(row)
    }

    /// 列の手順（先手から交互）から盤を作る。途中で入らない列・決着後の手があれば nil。
    ///
    /// 中断データの復元で使う。手順の最後の手で決着しているのは許す（決着した局も読めるように）。
    public static func replay(_ moves: [Int]) -> YonmokuBoard? {
        var board = YonmokuBoard()
        var disc = YonmokuDisc.black
        for (index, col) in moves.enumerated() {
            guard let point = board.drop(disc, in: col) else { return nil }
            if index < moves.count - 1, board.winningLine(through: point) != nil { return nil }
            disc = disc.opponent
        }
        return board
    }
}
