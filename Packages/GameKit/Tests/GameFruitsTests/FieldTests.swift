import Testing
import Foundation
@testable import GameFruits

/// 盤面（`FruitField`）の物理。SpriteKit 抜きで 1 プレイ丸ごと再生できる。
@Suite("くっつきフルーツの盤面")
struct FieldTests {
    private typealias M = FruitField.Metrics
    private let frame = 1.0 / 60

    /// `seconds` ぶんフレーム刻みで進め、起きたできごとを全部返す。
    @discardableResult
    private func run(_ field: inout FruitField, seconds: Double) -> [FruitEvent] {
        var events: [FruitEvent] = []
        var elapsed = 0.0
        while elapsed < seconds {
            events += field.step(dt: frame)
            elapsed += frame
        }
        return events
    }

    /// どの 2 個も `tolerance` より深く重なっていないこと。
    private func overlaps(in field: FruitField, tolerance: Double) -> [(Int, Int, Double)] {
        var result: [(Int, Int, Double)] = []
        let fruits = field.fruits
        for i in fruits.indices {
            for j in fruits.indices where j > i {
                let dx = fruits[i].x - fruits[j].x
                let dy = fruits[i].y - fruits[j].y
                let depth = fruits[i].radius + fruits[j].radius - (dx * dx + dy * dy).squareRoot()
                if depth > tolerance { result.append((fruits[i].id, fruits[j].id, depth)) }
            }
        }
        return result
    }

    private func insideWalls(_ field: FruitField, tolerance: Double = 0.05) -> Bool {
        field.fruits.allSatisfy {
            $0.x - $0.radius >= -tolerance && $0.x + $0.radius <= M.width + tolerance
                && $0.y - $0.radius >= -tolerance && $0.y + $0.radius <= M.height + tolerance
        }
    }

    // MARK: - 落とす

    @Test("落とした果物は落とす前の位置の真下、天井近くから落ち始める")
    func dropSpawnsAtCursor() {
        var field = FruitField()
        field.moveCursor(to: 30, holding: .cherry)
        let fruit = field.drop(.cherry)
        #expect(fruit.x == 30)
        #expect(fruit.y == M.spawnY)
        #expect(fruit.kind == .cherry)
        #expect(field.count == 1)
        #expect(field.fruits.first?.id == 0)
        #expect(field.nextID == 1)
    }

    @Test("落とす前の位置は壁から半径ぶん離した範囲に丸める")
    func cursorIsClampedByRadius() {
        var field = FruitField()
        field.moveCursor(to: -20, holding: .mandarin)
        #expect(field.cursorX == FruitKind.mandarin.radius)
        field.moveCursor(to: 500, holding: .lime)
        #expect(field.cursorX == M.width - FruitKind.lime.radius)
        // 持ち替えて大きくなったぶんは落とす瞬間にも丸める。
        field.moveCursor(to: M.width, holding: .blueberry)
        let fruit = field.drop(.mandarin)
        #expect(fruit.x == M.width - FruitKind.mandarin.radius)
    }

    @Test("画面の x を盤の x へ写す")
    func viewToFieldX() {
        #expect(M.fieldX(viewX: 0, viewWidth: 300) == 0)
        #expect(M.fieldX(viewX: 150, viewWidth: 300) == 50)
        #expect(M.fieldX(viewX: 400, viewWidth: 300) == M.width, "枠の外は端に丸める")
        #expect(M.fieldX(viewX: 10, viewWidth: 0) == M.width / 2, "幅が無ければ真ん中")
    }

    // MARK: - 落下と壁

    @Test("落とした果物は床に着いて止まる")
    func fruitFallsAndRests() {
        var field = FruitField()
        field.drop(.lime)
        let events = run(&field, seconds: 2)
        let fruit = field.fruits[0]
        #expect(abs(fruit.y - fruit.radius) < 0.2, "床の上で止まる（y=\(fruit.y)）")
        #expect(abs(fruit.x - M.width / 2) < 0.01, "横には動かない")
        #expect(field.isSettled)
        #expect(events.contains(.touched(id: 0)), "床に触れた手応えが 1 回出る")
        #expect(events.filter { $0 == .touched(id: 0) }.count == 1)
        #expect(!events.contains(.gameOver))
        #expect(field.fruits[0].overLineTime == 0, "通り過ぎただけの果物は危険線に数えない")
    }

    @Test("速く落としても床をすり抜けない")
    func noTunnelingThroughFloor() {
        var field = FruitField()
        field.placeFruitForTesting(.blueberry, x: 50, y: 60, vx: 0, vy: -400)
        run(&field, seconds: 1)
        #expect(insideWalls(field))
        #expect(field.fruits[0].y >= FruitKind.blueberry.radius - 0.05)
    }

    @Test("横に飛んだ果物は壁の内側で止まる")
    func wallsKeepFruitInside() {
        var field = FruitField()
        field.placeFruitForTesting(.kiwi, x: 50, y: 30, vx: 500, vy: 0)
        run(&field, seconds: 2)
        #expect(insideWalls(field))
        #expect(field.isSettled)
        #expect(field.fruits[0].x + FruitKind.kiwi.radius <= M.width + 0.05)
    }

    @Test("大きい果物の上に小さい果物が乗る（重ならず、下に落ちない）")
    func smallFruitRestsOnLargeOne() {
        var field = FruitField()
        field.drop(.mandarin)
        run(&field, seconds: 2)
        field.drop(.cherry)
        run(&field, seconds: 3)
        let mandarin = field.fruits.first { $0.kind == .mandarin }!
        let cherry = field.fruits.first { $0.kind == .cherry }!
        #expect(cherry.y > mandarin.y + FruitKind.mandarin.radius, "さくらんぼはみかんの上（y=\(cherry.y)）")
        #expect(overlaps(in: field, tolerance: 0.3).isEmpty)
        #expect(field.isSettled)
    }

    @Test("いろいろな果物を積んでも塊は落ち着く（重ならず、壁の中で、止まる）")
    func pileSettles() {
        var field = FruitField()
        let kinds: [FruitKind] = [.mandarin, .lime, .kiwi, .strawberry, .peach, .blueberry, .lime, .cherry, .mandarin, .kiwi]
        for (index, kind) in kinds.enumerated() {
            field.moveCursor(to: 30 + Double(index % 4) * 13, holding: kind)
            field.drop(kind)
            run(&field, seconds: 0.6)
        }
        run(&field, seconds: 4)
        #expect(field.isSettled, "速度が残っている: \(field.fruits.map { ($0.kind.name, $0.speed) })")
        #expect(insideWalls(field))
        let deep = overlaps(in: field, tolerance: 0.5)
        #expect(deep.isEmpty, "深く重なっている: \(deep)")
        #expect(!field.isOver)
    }

    // MARK: - 合体

    @Test("同じ種類が触れると 1 つ上の種類になり、位置は 2 個の間")
    func sameKindMerges() {
        var field = FruitField()
        field.moveCursor(to: 40, holding: .cherry)
        field.drop(.cherry)
        run(&field, seconds: 1.5)
        field.moveCursor(to: 44, holding: .cherry)
        field.drop(.cherry)
        let events = run(&field, seconds: 2)
        #expect(field.count == 1)
        #expect(field.fruits.first?.kind == .strawberry)
        let merged = events.compactMap { event -> (FruitKind, FruitKind, Int)? in
            if case let .merged(from, into, _, _, id) = event { return (from, into, id) }
            return nil
        }
        #expect(merged.count == 1)
        #expect(merged.first?.0 == .cherry)
        #expect(merged.first?.1 == .strawberry)
        #expect(merged.first?.2 == 2, "新しい果物は新しい ID を持つ")
        #expect(field.fruits.first?.id == 2)
        #expect(insideWalls(field))
    }

    @Test("合体は連鎖する（いちご + いちご → ライムができた先でライムと合体）")
    func mergesChain() {
        var field = FruitField()
        // ライムを左の壁際に置き、その右隣にいちごを 2 個縦に重ねる。上のいちごが下のいちごに触れて
        // ライムになり、そのライムが壁際のライムに触れてみかんになる。
        field.moveCursor(to: 0, holding: .lime)
        field.drop(.lime)
        run(&field, seconds: 1.5)
        let strawberryX = FruitKind.lime.radius * 2 + FruitKind.strawberry.radius
        field.moveCursor(to: strawberryX, holding: .strawberry)
        field.drop(.strawberry)
        run(&field, seconds: 1.5)
        field.drop(.strawberry)
        let events = run(&field, seconds: 3)
        let intos = events.compactMap { event -> FruitKind? in
            if case let .merged(_, into, _, _, _) = event { return into }
            return nil
        }
        #expect(intos == [.lime, .mandarin], "いちご→ライム、ライム→みかんの順（実際: \(intos)）")
        #expect(field.count == 1)
        #expect(field.fruits.first?.kind == .mandarin)
    }

    @Test("メロンどうしが触れると 2 個とも消える")
    func melonsVanish() {
        var field = FruitField()
        let r = FruitKind.melon.radius
        field.placeFruitForTesting(.melon, x: r + 1, y: r)
        field.placeFruitForTesting(.melon, x: M.width - r - 1, y: r + 30, vx: -60)
        let events = run(&field, seconds: 3)
        #expect(field.count == 0)
        #expect(events.contains { if case .vanished = $0 { return true } else { return false } })
    }

    @Test("同じ種類が 3 個触れても合体するのは 1 組だけで、1 個は残る")
    func threeOfAKindMergeOnlyOnePair() {
        var field = FruitField()
        // 3 個が横一列で隣どうし触れている状態から始める（間隔 17 < 直径 17.6）。
        let r = FruitKind.kiwi.radius
        for x in [30.0, 47, 64] {
            field.placeFruitForTesting(.kiwi, x: x, y: r)
        }
        run(&field, seconds: 3)
        // 左の 2 個がももになり、残りの 1 個はキウイのまま。ももとキウイは合体しない。
        let kinds = field.fruits.map(\.kind).sorted()
        #expect(kinds == [.kiwi, .peach], "実際: \(kinds.map(\.name))")
        #expect(field.isSettled)
    }

    // MARK: - 危険線と終局

    @Test("積み上がって危険線を越えたままなら終局し、以後は進まない")
    func overflowEndsTheGame() {
        var field = FruitField()
        var events: [FruitEvent] = []
        var drops = 0
        // 合体しにくいよう大きい種類を巡回して落とす。盤の面積は 100 × 96 で、ぶどう（半径 17.2）は
        // 10 個ほどで埋まる。
        let kinds: [FruitKind] = [.grape, .pineapple, .apple, .peach]
        while !field.isOver, drops < 40 {
            field.moveCursor(to: 30 + Double(drops % 3) * 20, holding: kinds[drops % kinds.count])
            field.drop(kinds[drops % kinds.count])
            events += run(&field, seconds: 0.8)
            drops += 1
        }
        #expect(field.isOver, "\(drops) 個落としても終局しない")
        #expect(events.filter { $0 == .gameOver }.count == 1, "終局は 1 回だけ伝える")
        #expect(field.isOverLine)

        let frozen = field
        #expect(field.step(dt: 1).isEmpty)
        #expect(field == frozen, "終局後は動かない")
    }

    @Test("危険線の上を通り過ぎるだけでは終局しない（猶予）")
    func passingThroughTheLineDoesNotCount() {
        var field = FruitField()
        // 床にみかんを 1 個。落とした果物はその上に乗るが、上端は危険線より下。
        field.drop(.mandarin)
        run(&field, seconds: 2)
        field.drop(.lime)
        let events = run(&field, seconds: 3)
        #expect(!events.contains(.gameOver))
        #expect(!field.isOver)
        #expect(!field.isOverLine)
        #expect(field.fruits.allSatisfy { $0.overLineTime == 0 })
    }

    @Test("危険線より上で止まった果物は猶予 + 1 秒で終局する")
    func restingAboveTheLineEndsAfterOneSecond() {
        var field = FruitField()
        // 左の壁に沿って大きい果物を柱にし、その上の果物の頭を危険線より上に出す。
        let melon = FruitKind.melon.radius
        let pineapple = FruitKind.pineapple.radius
        let grape = FruitKind.grape.radius
        field.placeFruitForTesting(.melon, x: melon, y: melon)
        field.placeFruitForTesting(.pineapple, x: pineapple, y: melon * 2 + pineapple)
        field.placeFruitForTesting(.grape, x: grape, y: melon * 2 + pineapple * 2 + grape)
        #expect(field.fruits[2].top > M.deadlineY, "柱の頭が危険線より上（\(field.fruits[2].top)）")
        // 置いた直後は猶予を過ぎている（`placeFruitForTesting` は age を進めて置く）。
        var elapsed = 0.0
        var over = false
        while elapsed < 3, !over {
            over = field.step(dt: frame).contains(.gameOver)
            elapsed += frame
        }
        #expect(over)
        #expect(elapsed > M.overLineLimit - 0.05, "1 秒未満で終局した（\(elapsed)）")
        #expect(elapsed < M.overLineLimit + 0.5, "1 秒を大きく超えて終局した（\(elapsed)）")
    }

    @Test("危険線の下へ戻れば計時は 0 に戻る")
    func timerResetsBelowTheLine() {
        var field = FruitField()
        field.placeFruitForTesting(.cherry, x: 50, y: M.deadlineY + 10)
        // 落ちている途中の数フレームは線より上（猶予は過ぎている）。
        var timers: [Double] = []
        for _ in 0..<60 {
            field.step(dt: frame)
            timers.append(field.fruits[0].overLineTime)
        }
        #expect(timers.first! > 0, "線より上にいるあいだは数える")
        #expect(timers.last! == 0, "床に着いたら 0")
        #expect(!field.isOver)
    }

    // MARK: - コンティニュー

    @Test("コンティニューは小さい 4 種と危険線より上の果物を取り除き、終局を取り消す")
    func clearForContinueRemovesSmallAndOverflowing() {
        var field = FruitField()
        field.placeFruitForTesting(.blueberry, x: 10, y: 5)
        field.placeFruitForTesting(.lime, x: 30, y: 8)
        field.placeFruitForTesting(.mandarin, x: 50, y: 9)
        field.placeFruitForTesting(.apple, x: 75, y: 15)
        field.placeFruitForTesting(.peach, x: 50, y: M.deadlineY + 5)
        let removed = field.clearForContinue()
        #expect(removed == 3)
        #expect(field.fruits.map(\.kind).sorted() == [.mandarin, .apple])
        #expect(!field.isOver)
        #expect(!field.isOverLine)
        #expect(field.fruits.allSatisfy { $0.overLineTime == 0 })
    }

    @Test("終局した盤もコンティニューで再び進む")
    func continueResumesAfterGameOver() {
        var field = FruitField()
        let melon = FruitKind.melon.radius
        let pineapple = FruitKind.pineapple.radius
        let grape = FruitKind.grape.radius
        field.placeFruitForTesting(.melon, x: melon, y: melon)
        field.placeFruitForTesting(.pineapple, x: pineapple, y: melon * 2 + pineapple)
        field.placeFruitForTesting(.grape, x: grape, y: melon * 2 + pineapple * 2 + grape)
        run(&field, seconds: 3)
        #expect(field.isOver)
        field.clearForContinue()
        #expect(field.count == 2, "線より上のぶどうだけ消える")
        field.drop(.cherry)
        let events = run(&field, seconds: 2)
        #expect(events.contains(.touched(id: 3)))
        #expect(!field.isOver)
    }

    // MARK: - 決定性・復元

    @Test("同じ操作からは常に同じ盤になる")
    func deterministic() {
        func play() -> FruitField {
            var field = FruitField()
            let kinds: [FruitKind] = [.cherry, .lime, .cherry, .mandarin, .strawberry, .lime, .blueberry]
            for (index, kind) in kinds.enumerated() {
                field.moveCursor(to: 25 + Double(index) * 8, holding: kind)
                field.drop(kind)
                run(&field, seconds: 0.5)
            }
            run(&field, seconds: 2)
            return field
        }
        #expect(play() == play())
    }

    @Test("中断データから作ると危険線の計時は 0 に戻り、ID は続きから振る")
    func restoreResetsTimersAndContinuesIDs() {
        var original = FruitField()
        original.placeFruitForTesting(.lime, x: 20, y: 8)
        original.placeFruitForTesting(.kiwi, x: 60, y: 11)
        var saved = original.fruits
        saved[0].overLineTime = 0.7
        let restored = FruitField(fruits: saved, cursorX: 42)
        #expect(restored.fruits.map(\.overLineTime) == [0, 0])
        #expect(restored.fruits.map(\.id) == [0, 1])
        #expect(restored.nextID == 2)
        #expect(restored.cursorX == 42)
        #expect(!restored.isOver)
    }

    @Test("Fruit は JSON に往復できる")
    func fruitRoundTripsThroughJSON() throws {
        let fruit = Fruit(id: 7, kind: .grape, x: 12.5, y: 30, vx: -1, vy: 2, angle: 0.3, age: 4, overLineTime: 0.1, hasTouched: true)
        let data = try JSONEncoder().encode(fruit)
        let decoded = try JSONDecoder().decode(Fruit.self, from: data)
        #expect(decoded == fruit)
    }

    // MARK: - 画面への載せ方

    @Test("iPhone SE の枠でも盤は幅の 85% 以上を使う")
    func boardUsesMostOfTheWidthOnSE() {
        // SE（第 3 世代）の中身の幅 343pt・ヘッダーとバナーを除いた高さの目安 357pt。
        let size = M.boardSize(availableWidth: 343, availableHeight: 357)
        #expect(size.width >= 343 * 0.85, "幅 \(size.width)pt")
        #expect(size.height <= 357)
        // iPhone 17 では幅を使い切る。
        let large = M.boardSize(availableWidth: 361, availableHeight: 470)
        #expect(large.width == 361)
        #expect(abs(large.height - 361 / M.aspectRatio) < 0.01)
        #expect(M.boardSize(availableWidth: 0, availableHeight: 100) == (0, 0))
    }
}
