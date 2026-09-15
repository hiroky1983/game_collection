import Core
import Foundation
import SpriteKit

extension RunnerScene {
    // MARK: - 反映

    private func sync() {
        if renderedGeneration != model.runGeneration { rebuildCourse() }
        let field = model.field
        // 雲はコースより遅く流す（視差）。`cloudLayer` 自体は動かさず、
        // 雲1つ1つを「全雲の帯の幅」でラップする座標に置き直す（無限スクロール）。
        // 折り返しは `RunnerParallax`（#921: 左端に周期的な空白が出ないよう 2 間隔ぶん左へずらす）。
        for (i, cloud) in clouds.enumerated() {
            cloud.position.x = RunnerParallax.wrappedX(
                base: cloudBaseX[i], distance: field.distance, parallax: Self.cloudParallax,
                spacing: Self.cloudSpacing, count: clouds.count)
        }
        // 丘は雲より近く（速く）、コースより遠く（遅く）流す。仕組みは雲と同じ無限スクロール。
        for (i, tile) in hillTiles.enumerated() {
            tile.position.x = RunnerParallax.wrappedX(
                base: hillBaseX[i], distance: field.distance, parallax: Self.hillParallax,
                spacing: Self.hillSpacing, count: hillTiles.count)
        }
        // 走者の画面上の x は動かさず、コースのほうを左へ流す。
        courseLayer.position = CGPoint(x: Metrics.playerX - field.distance, y: 0)
        if model.phase == .falling {
            // ミスした瞬間に `field` は凍る（`RunnerModel.tick` が `field.step` を呼ばなくなる）ので
            // 値は変わらない。最初のフレームだけ、ミスした瞬間の位置・向きへきっちり合わせてから
            // 演出を始める（以後 `player.position` / `.zRotation` はここでは触らず、演出の
            // `SKAction` に専有させる。毎フレーム上書きすると動きが打ち消される）。
            if lastSyncedPhase != .falling {
                player.position = CGPoint(x: Metrics.playerX, y: field.footY)
                player.zRotation = field.isGrounded ? 0 : CGFloat(max(-0.3, min(0.3, field.vy / 300)))
                // 無敵のまま穴に落ちた（#797）場合、点滅の途中の薄さで落下演出に入らないよう
                // 先に戻す（`playFallAnimation` の `removeAllActions` で点滅そのものは止まる）。
                stopInvincibleBlink()
                playFallAnimation()
            }
        } else {
            player.position = CGPoint(x: Metrics.playerX, y: field.footY)
            advancePedaling(field)
            // 空中では前のめりにする。跳んでいることが動きだけで分かるようにするため
            // （コマは `jump` の 1 枚だが、傾きで勢いが出る）。
            player.zRotation = field.isGrounded ? 0 : CGFloat(max(-0.3, min(0.3, field.vy / 300)))
            syncPickups(field)
            syncJustLanding(field)
            syncMovingHazards(field)
            // 無敵の点滅（#797）は走者ノードの alpha だけを触る。動く障害（#796）の同期は
            // 障害側のノードしか動かさないので、順序に依存も干渉もしない。
            syncInvincibility(field)
            // ゴールに着いた最初のフレームだけ紙吹雪を散らす（#703「着いた感」）。
            // `.falling` の落下演出と同じ「前回反映した phase」との比較で 1 回に絞る。
            if model.phase == .cleared || model.phase == .allCleared,
               lastSyncedPhase != .cleared, lastSyncedPhase != .allCleared {
                spawnGoalConfetti()
            }
        }
        // コマは局面・接地・位相の純関数（`RunnerRider.frame`）。`.falling` に入った最初の
        // フレームで `tumble`、演出明けの `.failed` で `dizzy`、空中は `jump`、接地は漕ぐ 2 枚。
        // 撮影の凍結（`isFrozenForCapture`）中は状態が動かないので、コマもそのまま止まる。
        applyRiderFrame(RunnerRider.frame(
            phase: model.phase, isGrounded: field.isGrounded, pedalPhase: pedalPhase
        ))
        lastSyncedPhase = model.phase
    }

    /// ゴール到達の紙吹雪。土煙と同じ丸だけの部品（#494）で、旗の色と白を交互に散らす。
    /// 座標は画面固定（走者の頭上）——クリアした瞬間 `field` は止まりコースも流れない。
    /// ノードは演出が終わると自分で消えるので、次の走行（`rebuildCourse`）に後始末は要らない。
    private func spawnGoalConfetti() {
        let origin = CGPoint(x: Metrics.playerX, y: Metrics.groundY + Metrics.playerHeight + 3)
        // 弾ける方向は決め打ち（乱数は使わない。撮影・QAで毎回同じ画になるように）。
        let specs: [(dx: Double, dy: Double, r: Double)] = [
            (-7, 9, 1.0), (-3, 12, 0.8), (2, 13, 1.1), (6, 11, 0.9), (9, 7, 0.8),
            (-9, 4, 0.7), (-1, 8, 0.7), (4, 6, 0.9), (11, 3, 0.7), (-5, 6, 0.8),
        ]
        for (i, spec) in specs.enumerated() {
            spawnDust(
                at: origin, specs: [spec], duration: 0.7,
                color: i.isMultiple(of: 2) ? RunnerPalette.goal : RunnerPalette.cloud
            )
        }
    }

    /// 取得済みのピックアップのノードを消す（`removedPickupIndices` の宣言を参照）。
    private func syncPickups(_ field: RunnerField) {
        guard !field.collectedPickupIndices.isSubset(of: removedPickupIndices) else { return }
        let indices = Self.pickupIndicesToRemove(
            collected: field.collectedPickupIndices,
            removed: removedPickupIndices,
            nodeCount: pickupNodes.count
        )
        for i in indices {
            removePickupNode(pickupNodes[i])
            removedPickupIndices.insert(i)
        }
    }

    /// 取得済みなのにまだ消していないピックアップの添字（昇順）。ノードの範囲外の添字は返さない
    /// ——ノードとステージの取り違えがあっても配列の範囲外を引いて落ちないようにするため（#733）。
    nonisolated static func pickupIndicesToRemove(
        collected: Set<Int>, removed: Set<Int>, nodeCount: Int
    ) -> [Int] {
        collected.subtracting(removed).filter { $0 >= 0 && $0 < nodeCount }.sorted()
    }

    /// ジャスト着地（#673）の土煙を出す。**1 回の着地につき 1 回だけ**——`field` の
    /// 単調増加する回数と、すでに出した回数の差で判断する（`syncPickups` と同じ形）。
    private func syncJustLanding(_ field: RunnerField) {
        guard field.justLandingCount > renderedJustLandingCount else { return }
        renderedJustLandingCount = field.justLandingCount
        spawnJustLandingDust(atWorldX: field.distance)
    }

    /// 無敵（たこ焼き・#797）の点滅を、`field.isInvincible` と食い違ったフレームだけ掛ける／外す。
    ///
    /// 点滅は走者ノード全体の `alpha` を `SKAction` で往復させる。周期は 0.36 秒（約 2.8 Hz）
    /// ——毎秒 3 回を超える明滅は光過敏の目安（WCAG 2.3.1）に掛かるので、その手前に留める。
    /// 位置・回転は `sync` が毎フレーム上書きするが `alpha` には触らないので、action と
    /// ぶつからない。
    private func syncInvincibility(_ field: RunnerField) {
        // ミス後（`.failed`）は `field` が無敵のまま凍るが、倒れた走者を点滅させない。
        // 一時停止中は掛けたままにする（止めるたびに外すと再開の瞬間にちらつく）。
        let shouldBlink = field.isInvincible && (model.phase == .running || model.phase == .paused)
        guard shouldBlink != isBlinkingInvincible else { return }
        if shouldBlink {
            isBlinkingInvincible = true
            let blink = SKAction.sequence([
                .fadeAlpha(to: 0.35, duration: 0.18),
                .fadeAlpha(to: 1.0, duration: 0.18),
            ])
            player.run(.repeatForever(blink), withKey: Self.invincibleBlinkKey)
        } else {
            stopInvincibleBlink()
        }
    }

    /// 無敵の点滅を外し、走者を不透明に戻す。無敵でないときに呼んでも何もしない。
    private func stopInvincibleBlink() {
        guard isBlinkingInvincible else { return }
        isBlinkingInvincible = false
        player.removeAction(forKey: Self.invincibleBlinkKey)
        player.alpha = 1
    }

    /// 穴に落ちる/ぶつかった瞬間だけ流す演出（`.falling` に入った最初のフレームで 1 回発火）。
    ///
    /// 走者ノード（`player`）をそのまま沈める・回す・フェードする。コマは `sync` が `.falling` で
    /// `tumble`（自転車が横倒しで前へ投げ出された絵）に差し替えるので、ここで掛ける回転は
    /// **絵の中の転倒に上乗せする勢い**に留める（#701）。当たり判定・進行のタイミングは
    /// `RunnerModel` 側の `RunnerRules.fallDuration` が決めており、ここは見た目だけを作る。
    private func playFallAnimation() {
        player.removeAllActions()
        let duration = RunnerRules.fallDuration

        // 序盤から倒れ始める。`easeIn` は終盤に速度が乗る動きで、演出時間の前半は
        // ほとんど回っておらず「立ったまま」に見えていた（会長QA「穴の横に落ちて
        // 縦になってるように見える」・2026-09-10）。
        //
        // 回転の向きは**負**（時計回り）にする。`player` の原点は前輪（+x）と後輪（-x）の
        // ちょうど中間にあり、正の回転（反時計回り）だと前輪側が先に持ち上がり後輪側から
        // 沈む——「なぜ後輪から落ちる、普通は前輪からやろ」という会長QA（2026-09-10）どおりの
        // 見え方になっていた。負の回転なら前輪側（進行方向）が先に沈み、後輪が後から
        // 持ち上がって前転するように見える。走者は左から近づき、穴・障害物は前方にあるので、
        // 前輪から落ちる/突っ込むほうが物理的に自然。
        //
        // 回転量は図形の頃（-0.85π）から弱めてある。`tumble` のコマ自体がすでに倒れた絵なので、
        // 同じだけ回すと転倒が二重になって穴の中で逆さまに止まる（#701）。前のめりに落ちる
        // 分だけ傾ける。
        let topple = SKAction.rotate(byAngle: -.pi * 0.35, duration: duration)
        topple.timingMode = .easeOut

        if model.field.isPit(at: model.field.distance) {
            // 穴の奈落は `Metrics.groundY` の深さまである（`addPitVoid`）。以前の沈み幅
            // （-3.5）はその1割ほどしかなく、穴の底へ落ちる前に演出が終わって
            // 「穴の横で止まっている」ように見えていた。奈落の深さに合わせて沈める。
            let sink = SKAction.moveBy(x: 0, y: -Metrics.groundY * 0.7, duration: duration)
            sink.timingMode = .easeIn
            let fade = SKAction.sequence([
                .wait(forDuration: duration * 0.25),
                .fadeAlpha(to: 0, duration: duration * 0.75),
            ])
            player.run(.group([sink, topple, fade]))
        } else {
            // 障害物への激突。以前は後退1単位+前傾（`topple` 相当）+フェードだけで、
            // 「その場で薄くなって終わり」にしか見えなかった（会長QA「岩にあたったときは
            // コケるアニメーションを再現してほしい」・2026-09-10）。つまずいて転げる
            // 「コケ」に作り直す:
            // - 回転はちょうど 1 回転（-2π・前転）。`topple`（-0.85π）より派手に転げて
            //   見えるうえ、終端で直立に戻るので、直後の `.failed` で `sync` が
            //   `zRotation = 0` へ戻すときの画の飛びも出ない。
            // - 体は岩に弾き返されて後方へ山なりに飛び、着地で小さくバウンドして止まる。
            // - 激突点には土煙を散らす（丸のみ・#494 の範囲内）。
            // - コマは `tumble`（#701）。絵の中ですでに転んでいるが、1 回転は絵ごと転げる
            //   宙返りとして読めるので回転量は変えない（穴の `topple` とは違い、終端で直立に
            //   戻る前提の値なので弱めると `.failed` で画が飛ぶ）。以前あった終盤のフェード
            //   （0.35 まで）は外した——演出明けの `.failed` は `dizzy`（座り込んで目を回す絵）を
            //   見せる局面で、薄いままだと絵が読めない。
            //
            // moveBy + rotate の合成ではなく custom action で毎フレーム姿勢を計算する。
            // `player` の原点は足元にあり、rotate だけだと足元を軸に回って回転の途中で
            // 頭が地面へ潜る（実機確認で判明）。見た目の重心（原点の上 4.5）を軸に
            // 回って見えるよう、回転量に応じた座標の補正を毎フレーム掛ける。
            let pivotY = 4.5
            let baseX = player.position.x, baseY = player.position.y
            let crash = SKAction.customAction(withDuration: duration) { node, elapsed in
                let p = max(0, min(1, Double(elapsed) / duration))
                // 回転は序盤に大きく（2次の easeOut）。激突の勢いで回り、終端で失速する。
                let eased = 1 - (1 - p) * (1 - p)
                let theta = -2 * Double.pi * eased
                node.zRotation = CGFloat(theta)
                // 後方への山なり（前 64%）+ 着地後の小さなバウンド（後 36%）。
                // どちらも sin の半波なので、終端でちょうど y=0（地面）へ戻る。
                let dy = p < 0.64
                    ? 3.4 * sin(.pi * p / 0.64)
                    : 1.0 * sin(.pi * (p - 0.64) / 0.36)
                // 重心軸の回転に見せる補正: 原点 O を C=(0, pivotY) の周りに θ 回した
                // ときの O の移動量。回転が 1 回転し切ると 0 に戻る。
                let compX = pivotY * sin(theta)
                let compY = pivotY * (1 - cos(theta))
                node.position = CGPoint(
                    x: baseX + CGFloat(-3.2 * p + compX),
                    y: baseY + CGFloat(dy + compY)
                )
            }
            player.run(crash)
            spawnCrashDust()
        }
    }

    /// 激突点の土煙。丸だけで組む（#494）。ノードは演出が終わると自分で消えるので、
    /// `rebuildCourse` 側での後始末は要らない。座標は画面固定（走者の前輪の先）——
    /// ミスの瞬間 `field` は凍っていてコースも流れないため、シーン直下に置いてよい。
    private func spawnCrashDust() {
        // 弾ける方向は決め打ち（乱数は使わない。撮影・QAで毎回同じ画になるように）。
        spawnDust(
            at: CGPoint(x: Metrics.playerX + 5.0, y: Metrics.groundY + 2.0),
            specs: [
                (-1.5, 2.5, 1.1), (0.8, 3.2, 0.9), (2.0, 1.8, 1.2),
                (-3.0, 1.2, 0.8), (0.2, 0.8, 1.3), (-4.5, 2.0, 0.7),
            ]
        )
    }

    /// ジャスト着地の土煙（#673）。激突の土煙と同じ作りで、**後輪の足元から後ろへ小さく**
    /// 散らす（越えた障害の真裏に降りた、という画にする）。ミスの演出と紛れないよう、
    /// 粒は少なく・小さく・短くしてある。
    ///
    /// **こちらはコース側（`courseLayer`）に置く**——走行中はコースが流れ続けるので、
    /// 画面固定にすると土煙が走者と一緒に前へ動いて見える。降りた地点に残して後ろへ流す。
    private func spawnJustLandingDust(atWorldX worldX: Double) {
        spawnDust(
            at: CGPoint(x: worldX - 2.6, y: Metrics.groundY + 0.8),
            specs: [(-2.2, 1.4, 0.8), (-4.0, 0.9, 0.6), (-0.6, 1.9, 0.7)],
            duration: 0.3,
            in: courseLayer
        )
    }

    /// 丸だけの土煙を 1 か所から散らす。ノードは演出が終わると自分で消える。
    private func spawnDust(
        at origin: CGPoint,
        specs: [(dx: Double, dy: Double, r: Double)],
        duration: TimeInterval = 0.4,
        in parent: SKNode? = nil,
        color: UInt32 = RunnerPalette.cloud
    ) {
        for spec in specs {
            let puff = SKShapeNode(circleOfRadius: spec.r)
            puff.fillColor = RunnerPalette.color(color)
            puff.strokeColor = .clear
            puff.alpha = 0.8
            puff.zPosition = 6
            puff.position = origin
            (parent ?? self).addChild(puff)
            let drift = SKAction.moveBy(x: spec.dx, y: spec.dy, duration: duration)
            drift.timingMode = .easeOut
            puff.run(.sequence([
                .group([
                    drift,
                    .scale(to: 1.8, duration: duration),
                    .fadeOut(withDuration: duration),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    /// 漕ぐ位相を進める（#569 → #701 でコマの切り替えに流用）。
    ///
    /// 位相は**接地して進んだ距離**から出す。時計で回すと、ゆっくりモードや一時停止のあいだも
    /// 脚だけが動いてしまう。速く走れば漕ぐのも速くなる（`pedalBoost` が距離に乗るため、
    /// ケイデンスはここで何もしなくても乗りに追従する）。コマへの反映は `sync` の末尾
    /// （`RunnerRider.frame`）。
    private func advancePedaling(_ field: RunnerField) {
        // 初回は 0 から数える。`field.distance` を初期値にすると、シーンが出るより前に
        // 進んでいた場合（撮影用の `-simulateRunner`）にその区間だけ漕いでいない扱いになる
        // （`RunnerRider.phase(forGroundedDistance:)` はこの前提で撮影の画を狙う）。
        let delta = field.distance - (lastRenderedDistance ?? 0)
        lastRenderedDistance = field.distance
        pedalPhase = RunnerRider.advance(
            phase: pedalPhase, by: delta, isPedaling: field.isGrounded
        )
    }
}
