import Foundation

public let gomokuBoardSize = 15

public enum GomokuStone: Int, Codable, Equatable, Sendable {
    case black = 0, white = 1
    public var opponent: GomokuStone { self == .black ? .white : .black }
}

public struct GomokuBoard: Equatable, Sendable {
    public private(set) var cells: [GomokuStone?]

    public init() {
        cells = Array(repeating: nil, count: gomokuBoardSize * gomokuBoardSize)
    }

    public init(cells: [GomokuStone?]) {
        self.cells = cells
    }

    public subscript(row: Int, col: Int) -> GomokuStone? {
        get { cells[row * gomokuBoardSize + col] }
        set { cells[row * gomokuBoardSize + col] = newValue }
    }

    public func checkWin(row: Int, col: Int) -> Bool {
        guard let stone = self[row, col] else { return false }
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in dirs {
            var count = 1
            for sign in [-1, 1] {
                var r = row + dr * sign, c = col + dc * sign
                while r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize && self[r, c] == stone {
                    count += 1; r += dr * sign; c += dc * sign
                }
            }
            if count >= 5 { return true }
        }
        return false
    }

    public var isFull: Bool { !cells.contains(nil) }
    public var moveCount: Int { cells.compactMap { $0 }.count }
}

// MARK: - 連珠の禁じ手（#441）

/// 黒（先手）に適用する禁じ手の種類。
///
/// 既定の五目並べ（自由五目）では使わない。設定で「禁じ手（連珠ルール）」を
/// オンにしたときだけ、黒の着手を `GomokuBoard.renjuForbidden(row:col:)` で判定する。
public enum GomokuForbidden: Equatable, Sendable {
    /// 三三: 一手で「活三」を 2 つ以上作る。
    case doubleThree
    /// 四四: 一手で「四」を 2 つ以上作る。
    case doubleFour
    /// 長連: 6 つ以上の連。連珠では五にならない。
    case overline

    /// 画面に出す短い名前。
    public var label: String {
        switch self {
        case .doubleThree: "三三"
        case .doubleFour:  "四四"
        case .overline:    "長連"
        }
    }
}

private let gomokuRenjuDirections: [(dr: Int, dc: Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]

public extension GomokuBoard {
    /// **黒が** (row, col) に打ったとき、連珠の禁じ手に当たるならその種類を返す。
    ///
    /// 白（後手）には禁じ手が無いので、呼び出し側で「禁じ手ルールが有効かつ手番が黒」で
    /// あることを確かめてから使う（この関数は常に黒として判定する）。
    ///
    /// 判定の順序は連珠の規定どおり **五が最優先**で、ちょうど 5 つ並ぶ手は
    /// 同時に三三・四四になっていても打てる（勝ちになる）。
    ///
    /// 本家の連珠にある**再帰的な禁じ手判定**（「三」を作る点それ自体が禁じ手なら
    /// その三は三として数えない）は実装していない。カジュアル向けの補助ルールとして、
    /// 直接の形だけで判定する。
    func renjuForbidden(row: Int, col: Int) -> GomokuForbidden? {
        guard GomokuBoard.inBounds(row, col), self[row, col] == nil else { return nil }
        var probe = self
        probe[row, col] = .black
        return probe.renjuVerdict(row: row, col: col)
    }

    internal static func inBounds(_ row: Int, _ col: Int) -> Bool {
        row >= 0 && row < gomokuBoardSize && col >= 0 && col < gomokuBoardSize
    }
}

private extension GomokuBoard {
    /// (row, col) に黒を置き終えた盤面で、その手が禁じ手かを判定する。
    ///
    /// `mutating` なのは、四・活三の判定で「もう 1 手足したらどうなるか」を見るため。
    /// 盤の複製は `renjuForbidden` の 1 回だけにして、以降は同じ複製を置いては戻す
    /// （複製し直すと 1 手の判定で 70 回以上 225 要素の配列をコピーすることになる）。
    mutating func renjuVerdict(row: Int, col: Int) -> GomokuForbidden? {
        var fours = 0
        var openThrees = 0
        var hasOverline = false

        for dir in gomokuRenjuDirections {
            let extent = runExtent(row: row, col: col, dir: dir)
            switch extent.back + extent.forward + 1 {
            case 5:
                return nil          // 五は禁じ手より優先する（勝ち）
            case 6...:
                hasOverline = true  // 他の方向に五がある可能性が残るので打ち切らない
                continue
            default:
                break
            }
            let foursInDirection = fourCount(row: row, col: col, dir: dir)
            fours += foursInDirection
            // 四になっている方向は三として数えない（四のほうが強い形）。
            if foursInDirection == 0, makesOpenThree(row: row, col: col, dir: dir) {
                openThrees += 1
            }
        }

        if hasOverline    { return .overline }
        if fours >= 2     { return .doubleFour }
        if openThrees >= 2 { return .doubleThree }
        return nil
    }

    /// (row, col) の石を含む連が、`dir` 方向へ前後それぞれ何個伸びているか。
    func runExtent(row: Int, col: Int, dir: (dr: Int, dc: Int)) -> (back: Int, forward: Int) {
        guard let stone = self[row, col] else { return (0, 0) }
        var back = 0
        var r = row - dir.dr, c = col - dir.dc
        while GomokuBoard.inBounds(r, c), self[r, c] == stone {
            back += 1; r -= dir.dr; c -= dir.dc
        }
        var forward = 0
        r = row + dir.dr; c = col + dir.dc
        while GomokuBoard.inBounds(r, c), self[r, c] == stone {
            forward += 1; r += dir.dr; c += dir.dc
        }
        return (back, forward)
    }

    /// (row, col) の石を含む連を、`dir` 方向の並び順で符号化して返す。
    func runStones(row: Int, col: Int, dir: (dr: Int, dc: Int)) -> [Int] {
        let extent = runExtent(row: row, col: col, dir: dir)
        return (-extent.back...extent.forward).map { step in
            (row + step * dir.dr) * gomokuBoardSize + (col + step * dir.dc)
        }
    }

    /// (row, col) を含む「四」が `dir` 方向にいくつあるか。
    ///
    /// 「四」= あと 1 手で**ちょうど 5** になる形。空点に黒を足して五になるかで数え、
    /// **できあがる五から足した石を除いた 4 つの組**で重複を除く。両端が空いた四（達四）は
    /// 足せる点が 2 つあるが、どちらも同じ 4 つの石なので **1 つの四**として数える。
    /// `BBBB.B` のように足すと 6 になる形は五にならないので四に数えない。
    mutating func fourCount(row: Int, col: Int, dir: (dr: Int, dc: Int)) -> Int {
        let origin = row * gomokuBoardSize + col
        var shapes = Set<[Int]>()
        for step in -4...4 where step != 0 {
            let r = row + step * dir.dr, c = col + step * dir.dc
            guard GomokuBoard.inBounds(r, c), self[r, c] == nil else { continue }
            let added = r * gomokuBoardSize + c
            self[r, c] = .black
            let stones = runStones(row: r, col: c, dir: dir)
            self[r, c] = nil
            guard stones.count == 5, stones.contains(origin) else { continue }
            shapes.insert(stones.filter { $0 != added })
        }
        return shapes.count
    }

    /// (row, col) を含む「活三」が `dir` 方向にあるか。
    ///
    /// 活三 = あと 1 手で**達四**（ちょうど 4 連かつ両端が空 = 止められない四）にできる形。
    mutating func makesOpenThree(row: Int, col: Int, dir: (dr: Int, dc: Int)) -> Bool {
        for step in -4...4 where step != 0 {
            let r = row + step * dir.dr, c = col + step * dir.dc
            guard GomokuBoard.inBounds(r, c), self[r, c] == nil else { continue }
            self[r, c] = .black
            let extent = runExtent(row: r, col: c, dir: dir)
            let isStraightFour = extent.back + extent.forward + 1 == 4
            // 足した点から見て (row, col) は -step の位置にある。連の中に入っているか。
            let containsOrigin = step > 0 ? step <= extent.back : -step <= extent.forward
            let headR = r - (extent.back + 1) * dir.dr, headC = c - (extent.back + 1) * dir.dc
            let tailR = r + (extent.forward + 1) * dir.dr, tailC = c + (extent.forward + 1) * dir.dc
            let openBothEnds = GomokuBoard.inBounds(headR, headC) && self[headR, headC] == nil
                && GomokuBoard.inBounds(tailR, tailC) && self[tailR, tailC] == nil
            self[r, c] = nil
            if isStraightFour, containsOrigin, openBothEnds { return true }
        }
        return false
    }
}
