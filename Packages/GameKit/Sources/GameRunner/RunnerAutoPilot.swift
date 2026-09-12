import Foundation

/// 地形を読んで踏み切りの是非だけを返す自動操縦（#494）。
///
/// **検証と撮影のためのもので、遊んでいる人の操作には一切関与しない**。
/// 置き場所を製品コードにしているのは、次の 2 つが**同じ関数**であることを保つため:
///
/// - `RunnerStageTests` が全ステージをゴールまで走らせて「クリア可能」を実証する
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
        guard let target = nextTarget(field: field) else { return false }
        return target.start - field.distance <= target.lead
    }

    /// 次に踏み切りの対象になるもの——前方の障害、または台座の左端（#674）——の
    /// 左端の x と、そこから何ワールド単位手前で踏み切るか。
    ///
    /// **台座は「越える」のではなく「上面に乗る」**。踏み切りの計算そのものは岩と同じで、
    /// 正面の当たり判定に入るまでに上面を越える高さへ上がりきれていればよい
    /// （`RunnerField.isHittingPlatformFace`）。上りきったあとは中心が台座の範囲に入った
    /// 時点で上面に接地するので、越え切る必要はない——だから台座の**長さ**は踏み切りに関係ない。
    ///
    /// 降りるほうは何もしない。端から出れば自然に落ちて地面（または台座）へ着地し、
    /// 落ちているあいだは `field.isGrounded` が false なので `shouldJump` も黙る。
    ///
    /// 障害と台座が両方前方にあるときは**左端が手前のほう**を選ぶ。ステージ側は台座の前後を
    /// 必ず平地にしてあるので（`RunnerStage.patterns`）、この 2 つの踏み切りが重なることはない。
    public static func nextTarget(field: RunnerField) -> (start: Double, lead: Double)? {
        let speed = field.stage.speed
        var target: (start: Double, lead: Double)?
        if let hazard = field.nextHazard(from: field.playerMaxX) {
            target = (hazard.start, lead(for: hazard, speed: speed))
        }
        if let platform = field.nextPlatform(from: field.playerMaxX) {
            // いま立っている面からの登り幅で見る（台座から台座へ乗り継ぐ場合は差分だけ上がればよい）。
            let rise = RunnerRules.riseTime(to: max(0, platform.top - field.altitude) + clearance)
            let candidate = (start: platform.start, lead: baseLead + speed * rise)
            if target == nil || candidate.start < target!.start { target = candidate }
        }
        return target
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
    static func lead(for hazard: RunnerHazard, speed: Double) -> Double {
        switch hazard.kind {
        case .pit:
            return baseLead
        case .lowBlock, .tallBlock, .bird:
            return baseLead + speed * RunnerRules.riseTime(to: hazard.height + clearance)
        }
    }

    /// 踏み切りの基礎の余裕（当たり判定に入る前に爪先ぶん＋半タイル手前で踏み切る）。
    static var baseLead: Double { RunnerField.Metrics.playerHalfWidth + RunnerRules.tileWidth / 2 }

    /// 障害物の上端をどれだけ余して越えるか。
    static let clearance: Double = 0.5
}
