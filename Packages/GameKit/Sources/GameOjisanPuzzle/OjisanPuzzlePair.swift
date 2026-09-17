import Foundation

/// 子の荷物が軸から見てどちらに付いているか。
public enum OjisanPuzzleRotation: Int, CaseIterable, Sendable {
    /// 真上。
    case up = 0
    /// 右。
    case right
    /// 真下。
    case down
    /// 左。
    case left

    /// 軸から子への相対位置（行は下が +）。
    public var offset: (row: Int, col: Int) {
        switch self {
        case .up:    (-1, 0)
        case .right: (0, 1)
        case .down:  (1, 0)
        case .left:  (0, -1)
        }
    }

    public var turnedRight: OjisanPuzzleRotation {
        OjisanPuzzleRotation(rawValue: (rawValue + 1) % 4) ?? .up
    }

    public var turnedLeft: OjisanPuzzleRotation {
        OjisanPuzzleRotation(rawValue: (rawValue + 3) % 4) ?? .up
    }
}

/// 落ちてくる 2 個 1 組の荷物。軸（`row` / `col`）と、軸から見た向き（`rotation`）で位置が決まる。
///
/// 盤に固定されると `[[Int]]` の 2 マスになるだけなので、この型は**落下中にしか存在しない**。
public struct OjisanPuzzlePair: Equatable, Sendable {
    /// 軸の荷物の種類（1...4）。
    public var axisKind: Int
    /// 子の荷物の種類（1...4）。
    public var childKind: Int
    /// 軸の行（上が 0）。
    public var row: Int
    /// 軸の列。
    public var col: Int
    public var rotation: OjisanPuzzleRotation

    public init(axisKind: Int, childKind: Int, row: Int, col: Int, rotation: OjisanPuzzleRotation) {
        self.axisKind = axisKind
        self.childKind = childKind
        self.row = row
        self.col = col
        self.rotation = rotation
    }

    public var childRow: Int { row + rotation.offset.row }
    public var childCol: Int { col + rotation.offset.col }

    /// 占める 2 マスと、そこに入る種類。軸が先、子が後。
    public var cells: [(cell: OjisanPuzzleCell, kind: Int)] {
        [
            (OjisanPuzzleCell(row: row, col: col), axisKind),
            (OjisanPuzzleCell(row: childRow, col: childCol), childKind),
        ]
    }
}
