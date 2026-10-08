import SpriteKit

extension RunnerScene {
    /// 湯けむり（`RunnerStage.steamBanks`・#1938 温泉街）の演出。
    ///
    /// 画面に固定した層（コースと一緒には流さない）に、白い湯気の塊を**走者の前端から
    /// `RunnerRules.steamNearClearGap` より先**にだけ並べる。濃さは `RunnerStage.steamIntensity(atRunnerDistance:)`
    /// （距離だけで決まる）に `RunnerRules.steamMaxAlpha` を掛けたもの——走者が区間に入るころから遠くが
    /// かすみ、抜けると晴れる。踏み切りの地点（手前）は決して隠さず、遠くの障害や泡立ちの合図も
    /// 縁取りが薄く透けて読める濃さに抑えてある。
    ///
    /// 見た目だけで当たり判定・成立条件には一切関与しない。揺れは視差を減らす設定（`reducesMotion`）では止める。
    func buildSteam(_ stage: RunnerStage) {
        steamLayer.removeAllChildren()
        steamLayer.alpha = 0
        steamLayer.isHidden = true
        guard !stage.steamBanks.isEmpty else { return }
        let left = Metrics.playerX + Metrics.playerHalfWidth + RunnerRules.steamNearClearGap
        let color = RunnerPalette.color(RunnerWorld.SceneryPalette.steam)
        // 塊の位置・大きさは固定の表（乱数を使わない＝撮影が毎回同じ）。x は `left` からの相対、y は地面からの高さ。
        let puffs: [(dx: Double, dy: Double, r: Double)] = [
            (4, 6, 10), (14, 16, 12), (24, 4, 9), (30, 22, 11), (10, 30, 10),
            (22, 36, 9), (32, 10, 12), (36, 30, 10), (16, 44, 8), (40, 18, 11),
        ]
        for (index, puff) in puffs.enumerated() {
            let node = SKShapeNode(circleOfRadius: puff.r)
            node.fillColor = color
            node.strokeColor = .clear
            node.alpha = index.isMultiple(of: 2) ? 1.0 : 0.8
            node.position = CGPoint(x: left + puff.dx, y: Metrics.groundY + puff.dy)
            if !reducesMotion {
                let drift = SKAction.moveBy(x: 0, y: 1.6, duration: 1.1 + 0.15 * Double(index % 3))
                drift.timingMode = .easeInEaseOut
                node.run(.repeatForever(.sequence([drift, drift.reversed()])), withKey: Self.loopActionKey)
            }
            steamLayer.addChild(node)
        }
    }

    /// 走者の距離から湯けむりの濃さを写す。区間の無い面（と エンドレス）では何もしない。
    func syncSteam(_ field: RunnerField) {
        guard field.track == nil, !field.stage.steamBanks.isEmpty else { return }
        let intensity = field.stage.steamIntensity(atRunnerDistance: field.distance)
        steamLayer.isHidden = intensity <= 0
        steamLayer.alpha = CGFloat(intensity * RunnerRules.steamMaxAlpha)
    }
}
