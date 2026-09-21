import Core
import Foundation
import Testing
@testable import GameBlocks
import CoreTestSupport

/// フレンジー増殖（#1202）。
///
/// 既存の `multiBall`（アイテム取得トリガー・上限 `maxBalls`=3・`ItemTests`）とは規模も
/// トリガーも別物（会長決裁 2026-09-21）。ここで固定するのは「ブロックを連続で壊すこと
/// 自体がトリガー」「上限で止まる」「落球でコンボが切れる」という契約そのもの。
@Suite("ブロック崩しのフレンジー増殖")
struct FrenzyTests {

    private func field(_ rows: [String], speed: Double = 70, frenzyThreshold: Int?) -> BlocksField {
        BlocksField(
            stage: BlocksStage(number: 1, rows: rows, ballSpeed: speed, frenzyThreshold: frenzyThreshold),
            speed: speed
        )
    }

    /// 6 行 × 9 列 = 54 個、繰り返し壊しても尽きない盤。
    private func roomyField(speed: Double = 70, frenzyThreshold: Int?) -> BlocksField {
        field(Array(repeating: "nnnnnnnnn", count: 6), speed: speed, frenzyThreshold: frenzyThreshold)
    }

    private func firstBreakable(_ f: BlocksField) -> (row: Int, column: Int)? {
        for row in 0..<f.rowCount {
            for column in 0..<BlocksField.Metrics.columns
            where f.block(row: row, column: column)?.isBreakable == true {
                return (row, column)
            }
        }
        return nil
    }

    private func isFrenzyTriggered(_ event: BlocksEvent) -> Bool {
        if case .frenzyTriggered = event { return true }
        return false
    }

    /// `destroyBlockForTesting`（当たり判定を飛ばす）で上から順に `count` 個壊す。
    ///
    /// **`placeBall` は使わない**: 球を 1 個に差し替えてしまい、フレンジーで増えた球が
    /// 消えてしまう（複数球を保ったまま連続で壊すテストが書けなくなる）。
    @discardableResult
    private func destroyForTesting(_ f: inout BlocksField, count: Int) -> [BlocksEvent] {
        var events: [BlocksEvent] = []
        for _ in 0..<count {
            guard let target = firstBreakable(f) else { break }
            events.append(contentsOf: f.destroyBlockForTesting(row: target.row, column: target.column))
        }
        return events
    }

    /// 上から順にブロックを実際の物理（当たり判定つき）で `count` 個壊す。
    ///
    /// フレンジーが実際の衝突経路（`step` → `resolveBlocks`）から発火することを確かめる
    /// 統合テスト用。`placeBall` で球を狙った位置へ直接置くため、**呼び出し後は球が
    /// 1 個に戻る**（このあいだに増えた球を残したまま続けたいテストでは使わない）。
    @discardableResult
    private func destroyViaPhysics(_ f: inout BlocksField, count: Int) -> [BlocksEvent] {
        var events: [BlocksEvent] = []
        var broken = 0
        var guardCount = 0
        while broken < count, guardCount < 4_000 {
            guardCount += 1
            guard let target = firstBreakable(f) else { break }
            let rect = BlocksField.blockRect(row: target.row, column: target.column)
            f.placeBall(x: rect.midX, y: rect.midY, vx: 0, vy: 1)
            let before = f.remainingBreakableCount
            events.append(contentsOf: f.step(dt: 1.0 / 60))
            if f.remainingBreakableCount < before { broken += 1 }
        }
        #expect(broken == count, "\(count) 個壊せなかった（\(broken) 個で止まった）")
        return events
    }

    // MARK: - コンボ・しきい値（当たり判定を経由しないロジックの単体テスト）

    @Test("しきい値未満の連続破壊では発動しない")
    func doesNotTriggerBelowThreshold() {
        var f = roomyField(frenzyThreshold: 3)
        f.launch()
        let events = destroyForTesting(&f, count: 2)
        #expect(f.balls.count == 1)
        #expect(f.comboCount == 2)
        #expect(!events.contains(where: isFrenzyTriggered))
    }

    @Test("すでに上限に達していれば、しきい値に届いても増えない")
    func staysCappedAfterThreshold() {
        var f = roomyField(frenzyThreshold: 3)
        f.launch()
        destroyForTesting(&f, count: 3)
        #expect(f.balls.count == BlocksRules.frenzyMaxBalls, "最初のフレンジーで上限まで増える")

        let events = destroyForTesting(&f, count: 3)
        #expect(f.balls.count == BlocksRules.frenzyMaxBalls, "上限を超えて増えてはいけない")
        #expect(!events.contains(where: isFrenzyTriggered), "すでに上限なので再発動のイベントは出ない")
    }

    @Test("落球するとコンボが切れる")
    func comboResetsOnBallLost() {
        var f = roomyField(frenzyThreshold: 3)
        f.launch()
        destroyForTesting(&f, count: 2)
        #expect(f.comboCount == 2)

        f.resetBall()
        #expect(f.comboCount == 0, "落球でコンボはリセットされる")

        f.launch()
        let events = destroyForTesting(&f, count: 2)
        #expect(f.balls.count == 1, "リセット後は 2 個ぶんではしきい値(3)に届かない")
        #expect(!events.contains(where: isFrenzyTriggered))
    }

    @Test("しきい値が無いステージでは何個壊しても発動しない")
    func neverTriggersWhenThresholdIsNil() {
        var f = roomyField(frenzyThreshold: nil)
        f.launch()
        let events = destroyForTesting(&f, count: 12)
        #expect(f.balls.count == 1)
        #expect(!events.contains(where: isFrenzyTriggered))
    }

    // MARK: - 実際の衝突経路からの発火（統合テスト）

    @Test("しきい値に達すると、実際の当たり判定経由でも球が上限まで一気に増える")
    func triggersAtThresholdViaPhysics() {
        var f = roomyField(frenzyThreshold: 3)
        f.launch()
        let events = destroyViaPhysics(&f, count: 3)
        #expect(f.balls.count == BlocksRules.frenzyMaxBalls)
        #expect(events.contains(.frenzyTriggered(ballCount: BlocksRules.frenzyMaxBalls)))
    }

    @Test("複数球のとき、実際に衝突した球が種になる（配列の先頭の球ではない）")
    func seedIsTheBallThatActuallyCollided() {
        var f = roomyField(speed: 70, frenzyThreshold: 1)
        let target = firstBreakable(f)!
        let rect = BlocksField.blockRect(row: target.row, column: target.column)
        // 配列の先頭（balls[0]）は動いてはいるが、ブロックにも壁にも当たらない場所に置く
        // （`resolveBlocks` を呼んでも何も起きない位置・速さ）。
        let decoy = BlocksBall(x: 5, y: 5, vx: 0, vy: 5)
        // 実際に衝突する球（balls[1]）は先頭とはっきり違う速さでブロックへ向かわせる。
        let hitter = BlocksBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        f.placeBallsForTesting([decoy, hitter])

        let events = f.step(dt: 0.02)
        #expect(events.contains(.frenzyTriggered(ballCount: BlocksRules.frenzyMaxBalls)))

        let addedSpeeds = Set(f.balls.dropFirst(2).map { $0.speed.rounded() })
        #expect(
            addedSpeeds == [70],
            "先頭のおとり球（速さ5）ではなく、実際に衝突した球（速さ70）が種になっているべき: \(addedSpeeds)"
        )
    }

    @Test("増えた球は種と同じ速さで、向きは分散する")
    func addedBallsKeepSpeedAndSpread() {
        var f = roomyField(speed: 90, frenzyThreshold: 3)
        f.launch()
        destroyViaPhysics(&f, count: 2)

        // 3 個目（しきい値ちょうど）は、速さが分かっている実際の飛球で当てる。
        let target = firstBreakable(f)!
        let rect = BlocksField.blockRect(row: target.row, column: target.column)
        f.placeBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        let seedSpeed = f.ball.speed
        let events = f.step(dt: 0.02)

        #expect(events.contains(.frenzyTriggered(ballCount: BlocksRules.frenzyMaxBalls)))
        #expect(f.balls.count == BlocksRules.frenzyMaxBalls)
        for ball in f.balls {
            #expect(abs(ball.speed - seedSpeed) < 1e-9, "速さは種の球のまま")
        }
        let directions = Set(f.balls.map { (($0.vx / $0.speed) * 1_000).rounded() })
        #expect(directions.count > 1, "全部同じ向きに重なって飛んではいけない")
    }

    // MARK: - 得点への影響

    @Test("フレンジー自体は得点を動かさない（壊した分の得点だけが加算される）")
    @MainActor
    func frenzyDoesNotScore() {
        let name = "asobiba.blocks.frenzy.score"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let model = BlocksModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
            startingAt: 1,
            preference: FeedbackPreference(key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false)
        )
        model.launch()
        // ステージ 1 のしきい値（3）ぶん、通常ブロックを壊す。
        let threshold = 3
        var broken = 0
        var guardCount = 0
        while broken < threshold, guardCount < 4_000 {
            guardCount += 1
            guard let target = firstBreakable(model.field) else { break }
            let rect = BlocksField.blockRect(row: target.row, column: target.column)
            model.placeBallForTesting(x: rect.midX, y: rect.midY, vx: 0, vy: 1)
            let before = model.field.remainingBreakableCount
            model.tick(dt: 1.0 / 60)
            if model.field.remainingBreakableCount < before { broken += 1 }
        }
        #expect(broken == threshold)
        #expect(model.field.balls.count > 1, "フレンジーが発動している前提")
        let expected = threshold * BlocksScoring.blockPoints(kind: .normal, destroyed: true, stage: 1)
        #expect(model.score == expected, "フレンジー発動ぶんの追加点が入っていないこと")
    }
}
