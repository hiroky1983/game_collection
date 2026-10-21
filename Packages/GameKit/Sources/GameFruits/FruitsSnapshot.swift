import Foundation

/// おじさんの盆栽（#2361。もとは くっつきフルーツ #1319）の中断データ。
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
    var hasMadeKinmatsu: Bool

    /// 保存の鍵は くっつきフルーツ時代のまま（`hasMadeMelon`）。名前を変えると、盆栽化（#2361）より前の
    /// 中断データが読めずに新規開始へ倒れる。
    private enum CodingKeys: String, CodingKey {
        case fruits, cursorX, score, heldKind, nextKind, continueUsed, seed, drawCount, dropCount
        case hasMadeKinmatsu = "hasMadeMelon"
    }
}
