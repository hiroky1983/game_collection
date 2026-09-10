import Foundation

/// 地形を読んで踏み切りの是非だけを返す自動操縦（#494）。
///
/// **検証と撮影のためのもので、遊んでいる人の操作には一切関与しない**。
/// 置き場所を製品コードにしているのは、次の 2 つが**同じ関数**であることを保つため:
///
/// - `RunnerStageTests` が全 15 ステージをゴールまで走らせて「クリア可能」を実証する
/// - `-simulateRunner cleared`（DEBUG）がクリア画面の撮影用にコースを走り切る
///
/// テスト側にだけ自動操縦を置くと、撮影用に別の（都合の良い）操作を書く余地が生まれ、
/// 「テストが通る操作」と「実際に撮れる操作」が食い違っても気付けない。
///
/// 判断は**押して即離す最小のジャンプ**だけを使う。大ジャンプ（押し続け）は余裕を増やす
/// 上振れなので、これでゴールできれば「押さなくても越えられる地形」であることの証明になる。
public enum RunnerAutoPilot {
    /// 踏み切るべきか。接地していないときは常に false。
    public static func shouldJump(field: RunnerField) -> Bool {
        guard field.isGrounded else { return false }
        guard let hazard = field.nextHazard(from: field.playerMaxX) else { return false }
        return hazard.start - field.distance <= lead(for: hazard, speed: field.stage.speed)
    }

    /// その障害に対して、何ワールド単位手前で踏み切るか。
    ///
    /// - 穴: 縁の少し手前。飛距離が穴の幅を上回ることは `RunnerStageTests` が保証する
    /// - 障害物: 当たり判定が重なり始めるまでに上端を越える高さへ上がりきる必要があるので、
    ///   その高さまでの上昇時間ぶんだけ早く踏み切る
    static func lead(for hazard: RunnerHazard, speed: Double) -> Double {
        let base = RunnerField.Metrics.playerHalfWidth + RunnerRules.tileWidth / 2
        switch hazard.kind {
        case .pit:
            return base
        case .lowBlock, .tallBlock, .bird:
            return base + speed * RunnerRules.riseTime(to: hazard.height + clearance)
        }
    }

    /// 障害物の上端をどれだけ余して越えるか。
    static let clearance: Double = 0.5
}
