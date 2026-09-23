import Foundation

/// くっつきフルーツの中断データ（#1319）。
///
/// アクション枠の基盤規約は「フレーム単位で保存しない」と決めている（ブロック崩し #463）。ここも同じで、
/// 書き出すのは**果物を落とした瞬間**と、**塊が止まった直後**の 2 種類の区切りだけ（`FruitsModel.persist`）。
/// ステージの無い 1 枚の盤なので「ステージの頭から」に相当する区切りが無く、盤の中身（果物の位置と速度）を
/// そのまま持つ。止まった塊を復元するので、開いた瞬間に何かが目の前で動いている理不尽さは無い。
struct FruitsSnapshot: Codable {
    var fruits: [Fruit]
    var cursorX: Double
    var score: Int
    /// 持っている果物。落とした直後の間（次が出るまで）に保存すると nil。
    var heldKind: FruitKind?
    var nextKind: FruitKind
    var continueUsed: Bool
    /// 落とす果物の抽選の種と、これまでに引いた回数。復元時に同じ列の続きを引く。
    var seed: UInt64
    var drawCount: Int
    var dropCount: Int
    var hasMadeMelon: Bool
}
