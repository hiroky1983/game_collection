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
        // 鳥は**跳ばずにくぐる**障害（#671）。接地したままなら頭が帯（`bottom` 13）に届かず
        // 素通りできるが、跳ぶと必ず当たる。ここで岩と同じ「越える」判断をすると、
        // 鳥のある 13〜15 面が自動操縦でクリアできなくなる。
        //
        // 前端（`playerMaxX`）からも探し直すのは、**後端がまだ帯の下にいるあいだ**を拾うため。
        // `nextHazard(from: playerMaxX)` は体が抜けきる前に次の障害へ移ってしまうので、
        // そのわずかな窓で次の障害の踏み切り条件が成立すると、鳥の尾の下で踏み切って当たる。
        // いまの 15 ステージは区画の間隔（`RunnerRules.segmentTiles`）のおかげでその窓に
        // 踏み切り点が来ない（`RunnerStageTests.birdsNeverForceAJump` が保証）が、
        // 間隔の設計を変えたときにここだけ穴が残らないよう、判断自体を自己完結させる。
        guard hazard.kind != .bird, field.nextHazard(from: field.playerMinX)?.kind != .bird else {
            return false
        }
        return hazard.start - field.distance <= lead(for: hazard, speed: field.stage.speed)
    }

    /// 踏み切ったジャンプを離すべきか。**着地するまで離さない**——早く離すと `vy` が
    /// 切り詰められて低いホップになってしまう（会長QA「軽いタップなら本当に小ジャンプ」
    /// 2026-09-10）ので、地形の成立条件（`RunnerStageTests`）が前提にしている
    /// 「切り詰め無しの全弾道」を保証するには着地まで押し続ける必要がある。
    /// 接地中に呼んでも（すでに `isHolding == false` のため）安全な no-op。
    public static func shouldRelease(field: RunnerField) -> Bool {
        field.isGrounded
    }

    /// その障害に対して、何ワールド単位手前で踏み切るか。
    ///
    /// - 穴: 縁の少し手前。飛距離が穴の幅を上回ることは `RunnerStageTests` が保証する
    /// - 障害物: 当たり判定が重なり始めるまでに上端を越える高さへ上がりきる必要があるので、
    ///   その高さまでの上昇時間ぶんだけ早く踏み切る
    /// - 鳥: 跳ばないので踏み切り位置は無い（#671）。返すのは**ここまでに前のジャンプの
    ///   着地を終えていなければならない余白**で、間隔の成立条件（`RunnerStageTests`）が
    ///   穴と同じ形のまま使える
    static func lead(for hazard: RunnerHazard, speed: Double) -> Double {
        let base = RunnerField.Metrics.playerHalfWidth + RunnerRules.tileWidth / 2
        switch hazard.kind {
        case .pit, .bird:
            return base
        case .lowBlock, .tallBlock:
            return base + speed * RunnerRules.riseTime(to: hazard.height + clearance)
        }
    }

    /// 障害物の上端をどれだけ余して越えるか。
    static let clearance: Double = 0.5
}
