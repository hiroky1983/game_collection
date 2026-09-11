import Core
import Foundation
import Testing
@testable import GameBlocks

/// パワーアップアイテム（#599）。
///
/// 受け入れ条件の中心は「**アイテムの取得でゲームが詰まない・無限に有利にならない**」なので、
/// 効果が出ることだけでなく **どこで止まるか**（上限・効果時間・落球での消滅・得点に触らないこと）を
/// 固定する。出現条件は乱数を使わないので、同じ崩し方から常に同じ順番で出ることも確かめる。
@Suite("ブロック崩しのパワーアップ")
struct ItemTests {

    private func field(_ rows: [String], speed: Double = 70) -> BlocksField {
        BlocksField(stage: BlocksStage(number: 1, rows: rows, ballSpeed: speed), speed: speed)
    }

    /// ブロックの無い盤（アイテムとパドルだけを見たいとき）。
    private func emptyField(speed: Double = 70) -> BlocksField {
        field([".........", "........."], speed: speed)
    }

    /// 上から順にブロックを `count` 個壊す。
    ///
    /// 球を狙ったブロックの中心へ置いて 1 フレームだけ進めるので、反射の偶然に左右されない。
    private func destroy(_ f: inout BlocksField, count: Int) {
        var broken = 0
        var guardCount = 0
        while broken < count, guardCount < 4_000 {
            guardCount += 1
            guard let target = firstBreakable(f) else { break }
            let rect = BlocksField.blockRect(row: target.row, column: target.column)
            f.placeBall(x: rect.midX, y: rect.midY, vx: 0, vy: 1)
            let before = f.remainingBreakableCount
            _ = f.step(dt: 1.0 / 60)
            if f.remainingBreakableCount < before { broken += 1 }
        }
        #expect(broken == count, "\(count) 個壊せなかった（\(broken) 個で止まった）")
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

    /// 60fps で `frames` フレームぶん進める。
    ///
    /// 秒で回すと浮動小数の端数でフレーム数が 1 つずれ、落ちた距離の検証が揺れる。
    @discardableResult
    private func run(_ f: inout BlocksField, frames: Int) -> [BlocksEvent] {
        var events: [BlocksEvent] = []
        for _ in 0..<frames {
            events.append(contentsOf: f.step(dt: 1.0 / 60))
        }
        return events
    }

    /// アイテムが受け取られる（または床まで落ちて消える）まで進める。
    ///
    /// **落ちきってからさらに進めてはいけない**。増えた球はパドルを外せば普通に落ちるので、
    /// 余分に回すと「増えたこと」ではなく「そのあと落ちたこと」を見てしまう。
    @discardableResult
    private func settleItems(_ f: inout BlocksField, maxFrames: Int = 400) -> [BlocksEvent] {
        var events: [BlocksEvent] = []
        var frames = 0
        while !f.items.isEmpty, frames < maxFrames {
            frames += 1
            events.append(contentsOf: f.step(dt: 1.0 / 60))
        }
        #expect(f.items.isEmpty, "アイテムが \(maxFrames) フレームで落ちきっていない")
        return events
    }

    // MARK: - 出現条件

    @Test("アイテムはブロックを一定数壊すごとに落ちてくる")
    func itemsDropOnInterval() {
        var f = field(["nnnnnnnnn", "nnnnnnnnn", "nnnnnnnnn"])
        let interval = BlocksRules.itemDropInterval

        destroy(&f, count: interval - 1)
        #expect(f.items.isEmpty, "\(interval - 1) 個ではまだ落ちない")

        destroy(&f, count: 1)
        #expect(f.items.count == 1, "\(interval) 個目で落ちる")

        destroy(&f, count: interval)
        #expect(f.items.count == 2, "さらに \(interval) 個でもう 1 個落ちる")
    }

    @Test("出る順番は決まっていて乱数に依らない")
    func dropOrderIsDeterministic() {
        var first = field(["nnnnnnnnn", "nnnnnnnnn", "nnnnnnnnn"])
        var second = field(["nnnnnnnnn", "nnnnnnnnn", "nnnnnnnnn"])
        destroy(&first, count: BlocksRules.itemDropInterval * 2)
        destroy(&second, count: BlocksRules.itemDropInterval * 2)

        #expect(first.items.map(\.kind) == BlocksItemKind.dropOrder)
        #expect(first.items == second.items, "同じ崩し方からは同じアイテムが同じ場所に出る")
    }

    @Test("アイテムは壊したブロックの位置から出て、まっすぐ落ちる")
    func itemsFallStraightDown() throws {
        var f = field(["nnnnnnnnn", "nnnnnnnnn", "nnnnnnnnn"])
        destroy(&f, count: BlocksRules.itemDropInterval)
        let spawned = try #require(f.items.first)

        // 球にもパドルにも邪魔をさせない（球は止め、パドルはアイテムの真下から外す）。
        f.movePaddle(to: 5)
        f.placeBall(x: 50, y: 60, vx: 0, vy: 0)
        run(&f, frames: 60)
        let falling = try #require(f.items.first)
        #expect(falling.x == spawned.x, "横へは動かない")
        #expect(
            abs((spawned.y - falling.y) - BlocksRules.itemFallSpeed) < 0.01,
            "1 秒で \(BlocksRules.itemFallSpeed) 単位ぶん落ちる"
        )
    }

    @Test("アイテムの出現はステージごとに数え直す")
    func destroyedCountIsPerStage() {
        var f = field(["nnnnnnnnn", "nnnnnnnnn", "nnnnnnnnn"])
        destroy(&f, count: BlocksRules.itemDropInterval)
        #expect(f.destroyedCount == BlocksRules.itemDropInterval)

        let next = field(["nnnnnnnnn"])
        #expect(next.destroyedCount == 0)
        #expect(next.items.isEmpty)
    }

    // MARK: - バーが伸びる

    @Test("受け取るとパドルが伸び、効果時間が過ぎると戻る")
    func widePaddleExpires() {
        var f = emptyField()
        let normal = BlocksField.Metrics.paddleHalfWidth
        f.movePaddle(to: 50)
        #expect(f.paddleHalfWidth == normal)

        f.dropItemForTesting(kind: .widePaddle, x: 50, y: 60)
        let events = settleItems(&f)
        #expect(events.contains(.itemCaught(kind: .widePaddle)))
        #expect(f.items.isEmpty, "受け取ったアイテムは消える")
        #expect(f.isPaddleWide)
        #expect(abs(f.paddleHalfWidth - normal * BlocksRules.widePaddleFactor) < 1e-9)

        run(&f, frames: Int(BlocksRules.widePaddleDuration * 60) + 1)
        #expect(!f.isPaddleWide, "効果時間が過ぎたら戻る")
        #expect(f.paddleHalfWidth == normal)
    }

    @Test("重ねて取ってもパドルは太り続けない（延びるのは残り時間だけ）")
    func widePaddleDoesNotStack() {
        var f = emptyField()
        f.movePaddle(to: 50)
        f.dropItemForTesting(kind: .widePaddle, x: 50, y: 60)
        settleItems(&f)
        let widened = f.paddleHalfWidth
        #expect(f.isPaddleWide)

        // 効果が切れる前にもう 1 個取る。
        f.dropItemForTesting(kind: .widePaddle, x: 50, y: 60)
        settleItems(&f)
        #expect(f.paddleHalfWidth == widened, "2 個目でさらに広がってはいけない")
        #expect(
            abs(f.widePaddleRemaining - BlocksRules.widePaddleDuration) < 0.05,
            "残り時間は上書きされる"
        )
    }

    @Test("伸びたパドルも盤からはみ出さない")
    func widePaddleStaysInsideTheBoard() {
        var f = emptyField()
        // 右端に寄せてから伸ばす（伸びたぶんだけ内側へ戻るはず）。
        f.movePaddle(to: 999)
        f.dropItemForTesting(kind: .widePaddle, x: f.paddleX, y: 60)
        settleItems(&f)
        #expect(f.isPaddleWide)
        #expect(f.paddleX + f.paddleHalfWidth <= BlocksField.Metrics.width + 1e-9)

        f.movePaddle(to: -999)
        #expect(f.paddleX - f.paddleHalfWidth >= -1e-9)
    }

    @Test("伸びていても当てた位置と跳ね返る向きの対応は変わらない")
    func widePaddleKeepsTheBounceMapping() {
        var f = emptyField()
        f.movePaddle(to: 50)
        f.dropItemForTesting(kind: .widePaddle, x: 50, y: 60)
        settleItems(&f)
        #expect(f.isPaddleWide)

        // 素の半幅より外（= 伸びていなければ外れる位置）で受けられ、右で当てれば右へ返る。
        let edge = 50 + BlocksField.Metrics.paddleHalfWidth + 2
        f.placeBall(x: edge, y: BlocksField.Metrics.paddleTop + 2.2, vx: 0, vy: -70)
        #expect(f.step(dt: 0.02).contains(.paddleBounce), "素の幅なら外れる位置でも受けられる")
        #expect(f.ball.vx > 0)
        #expect(f.ball.vy > 0)
    }

    @Test("取り逃したアイテムは床で消える（効果は出ない）")
    func missedItemsDisappear() {
        var f = emptyField()
        f.movePaddle(to: 10)
        f.dropItemForTesting(kind: .widePaddle, x: 90, y: 60)
        let events = settleItems(&f)
        #expect(f.items.isEmpty)
        #expect(!f.isPaddleWide)
        #expect(!events.contains(.itemCaught(kind: .widePaddle)))
    }

    // MARK: - 球が増える

    @Test("球が増えるが上限を超えない")
    func multiBallIsCapped() {
        var f = emptyField()
        f.movePaddle(to: 50)
        f.launch()
        #expect(f.balls.count == 1)

        // **パドルのすぐ上に落とす**。高い位置から落とすと受け取るまでの数秒で球が散らばり、
        // 2 個目を取る時点で盤上に 1 個しか残らない。それだと「1 個 + 2 個 = 3 個」に
        // なるだけで、**上限で止まったことを見ていない**（上限の判定を丸ごと外しても緑のままになる）。
        f.dropItemForTesting(kind: .multiBall, x: 50, y: 20)
        settleItems(&f)
        #expect(f.balls.count == BlocksRules.maxBalls)

        // 上限に達したまま、もう 1 個取る。
        f.dropItemForTesting(kind: .multiBall, x: 50, y: 20)
        settleItems(&f)
        #expect(f.balls.count == BlocksRules.maxBalls, "取るたびに増え続けてはいけない")
    }

    @Test("増えた球は向きだけ散らし、速さは元の球のまま")
    func splitBallsKeepTheirSpeed() {
        var f = emptyField(speed: 70)
        f.movePaddle(to: 50)
        f.launch()
        // 散らばる前に受け取らせる（`multiBallIsCapped` と同じ理由）。
        f.dropItemForTesting(kind: .multiBall, x: 50, y: 20)
        settleItems(&f)

        #expect(f.balls.count == BlocksRules.maxBalls)
        for ball in f.balls {
            #expect(abs(ball.speed - 70) < 1e-9, "速さは変わらない")
        }
        let directions = Set(f.balls.map { (($0.vx / $0.speed) * 1_000).rounded() })
        #expect(directions.count == f.balls.count, "同じ向きのまま重なって飛んではいけない")
    }

    @Test("球が 1 個落ちても残機は減らない。全部落ちたときだけ落球になる")
    func lifeIsLostOnlyWhenEveryBallIsGone() {
        var f = emptyField()
        f.movePaddle(to: 50)
        f.launch()
        f.dropItemForTesting(kind: .multiBall, x: 50, y: 20)
        settleItems(&f)
        #expect(f.balls.count == BlocksRules.maxBalls)

        // パドルを端へ寄せ、球が全部落ちるまで待つ。
        f.movePaddle(to: BlocksField.Metrics.paddleHalfWidth)
        var events: [BlocksEvent] = []
        var sawPartialLoss = false
        var frames = 0
        while frames < 60 * 120, !events.contains(.ballLost) {
            frames += 1
            events.append(contentsOf: f.step(dt: 1.0 / 60))
            if f.balls.count < BlocksRules.maxBalls, !f.balls.isEmpty, !events.contains(.ballLost) {
                sawPartialLoss = true
            }
        }
        #expect(sawPartialLoss, "1 個だけ落ちた状態を通っていない（テストの前提が崩れている）")
        #expect(events.filter { $0 == .ballLost }.count == 1, "落球は最後の 1 個のときだけ")
        #expect(f.balls.isEmpty)
    }

    @Test("落球で増えた球・効果・落下中のアイテムはすべて消える")
    func losingTheBallClearsEveryEffect() {
        var f = emptyField()
        f.movePaddle(to: 50)
        f.launch()
        f.dropItemForTesting(kind: .widePaddle, x: 50, y: 60)
        f.dropItemForTesting(kind: .multiBall, x: 50, y: 55)
        settleItems(&f)
        #expect(f.isPaddleWide)
        #expect(f.balls.count == BlocksRules.maxBalls)

        f.dropItemForTesting(kind: .widePaddle, x: 90, y: 80)
        f.resetBall()
        #expect(f.balls.count == 1, "球は 1 個に戻る")
        #expect(!f.balls[0].isMoving, "パドルの上で待機する")
        #expect(!f.isPaddleWide, "効果は持ち越さない")
        #expect(f.items.isEmpty, "落下中のアイテムも消える")
        #expect(f.paddleHalfWidth == BlocksField.Metrics.paddleHalfWidth)
    }

    // MARK: - 詰まない・無限に有利にならない

    @Test("アイテムは得点も残機も 1 つも動かさない")
    @MainActor
    func itemsDoNotScore() {
        let name = "asobiba.blocks.items.score"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let model = BlocksModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
            startingAt: 1,
            preference: FeedbackPreference(key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false)
        )
        model.launch()
        model.movePaddle(to: 50)
        let before = model.score
        model.dropItemForTesting(kind: .widePaddle, x: 50, y: 60)
        model.dropItemForTesting(kind: .multiBall, x: 50, y: 55)
        // ブロックに当たらない高さで球を止めておく（当たれば当然スコアが動く）。
        for _ in 0..<300 {
            model.placeBallForTesting(x: 50, y: 30, vx: 0, vy: 20)
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.field.isPaddleWide, "受け取れている")
        #expect(model.isPaddleWide, "画面へ出す鏡も追従する")
        #expect(model.score == before, "アイテムでは 1 点も入らない")
        #expect(model.lives == BlocksRules.initialLives, "残機も増えない")
    }

    @Test("アイテムは有利にするものだけで、出ない種類も無い")
    func everyItemIsBeneficial() {
        // 「取ると損をする」種類（パドルが縮む・球が速くなる等）を足すと、受けるか避けるかの
        // 判断が増えて素の難度が上がる。ゆっくりモードでは補えないので置かない。
        #expect(Set(BlocksItemKind.allCases) == Set([.widePaddle, .multiBall]))
        #expect(Set(BlocksItemKind.dropOrder) == Set(BlocksItemKind.allCases), "出ない種類があってはいけない")
        #expect(BlocksRules.widePaddleFactor > 1, "パドルは伸びるだけ")
        #expect(BlocksRules.maxBalls > 1)
        #expect(BlocksItemKind.widePaddle.duration == BlocksRules.widePaddleDuration)
        #expect(BlocksItemKind.multiBall.duration == nil, "その場で終わる効果に時間は無い")
    }

    @Test("アイテムは球より遅く落ちる（球を追いながらでも取りに行ける）")
    func itemsFallSlowerThanTheBall() {
        #expect(BlocksRules.itemFallSpeed < BlocksStage.baseSpeed)
    }
}

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}
