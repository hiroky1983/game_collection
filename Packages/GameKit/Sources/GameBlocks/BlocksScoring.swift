import Foundation

/// 得点の決め方（#463）。
///
/// **すべて純関数**にしてある。「あとから配点を調整したい」が必ず来る領域なので、
/// 値と式を 1 か所に集めてテストで固定しておく。
public enum BlocksScoring {
    /// 硬いブロックに当てた（まだ壊れていない）ときの得点。
    public static let hitPoints = 5
    /// 通常ブロックを壊したときの得点。
    public static let normalDestroyedPoints = 10
    /// 硬いブロックを壊したときの得点（上の `hitPoints` とは別に入る）。
    public static let hardDestroyedPoints = 30
    /// ステージクリアの基礎点。ステージ番号を掛ける。
    public static let stageClearBase = 100
    /// クリア時に残っていた 1 機あたりの加点。
    public static let lifeBonus = 50

    /// ステージが進むほど 1 個あたりの価値を上げる倍率。
    ///
    /// ステージ番号をそのまま掛けると最終面が序盤の 12 倍になり、序盤の腕前が結果に出なくなる。
    /// 3 ステージごとに 1 段上げる形にして、最終面でも 4 倍に留める。
    public static func stageMultiplier(stage: Int) -> Int {
        max(1, 1 + (max(1, stage) - 1) / 3)
    }

    /// ブロック 1 個ぶんの得点。壊れないブロック（`solid`）は常に 0。
    public static func blockPoints(kind: BlockKind, destroyed: Bool, stage: Int) -> Int {
        let base: Int
        switch (kind, destroyed) {
        case (.solid, _):        base = 0
        case (.normal, true):    base = normalDestroyedPoints
        case (.normal, false):   base = 0      // 通常ブロックは 1 発で壊れるのでこの組み合わせは来ない
        case (.hard, true):      base = hardDestroyedPoints
        case (.hard, false):     base = hitPoints
        }
        return base * stageMultiplier(stage: stage)
    }

    /// ステージクリアのボーナス。残機が多いほど高い。
    public static func stageClearBonus(stage: Int, remainingLives: Int) -> Int {
        stageClearBase * max(1, stage) + lifeBonus * max(0, remainingLives)
    }
}
