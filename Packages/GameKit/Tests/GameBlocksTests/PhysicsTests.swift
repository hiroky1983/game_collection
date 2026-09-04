import Foundation
import Testing
@testable import GameBlocks

/// 反射計算（#463）。**この層に SpriteKit は一切出てこない**ので、
/// 角度・すり抜け・詰みの検証をシミュレータ無しで固定できる。
@Suite("ブロック崩しの反射計算")
struct PhysicsTests {

    private let epsilon = 1e-9

    // MARK: - パドルの反射

    @Test("パドルの中央で当てるとまっすぐ上へ返る")
    func paddleCenterGoesStraightUp() {
        let v = BlocksPhysics.paddleBounce(offset: 0, speed: 70)
        #expect(abs(v.vx) < epsilon)
        #expect(abs(v.vy - 70) < 1e-9)
    }

    @Test("端で当てるほど横へ飛ぶ（最大角は 60 度）")
    func paddleEdgeMaxAngle() {
        let right = BlocksPhysics.paddleBounce(offset: 1, speed: 100)
        // 垂直から 60 度 → vx = sin60 * 100 ≒ 86.60 / vy = cos60 * 100 = 50
        #expect(abs(right.vx - 86.6025403784) < 1e-6)
        #expect(abs(right.vy - 50) < 1e-6)

        let left = BlocksPhysics.paddleBounce(offset: -1, speed: 100)
        #expect(abs(left.vx + 86.6025403784) < 1e-6)
        #expect(abs(left.vy - 50) < 1e-6)
    }

    @Test("パドルのどこで当てても速さは変わらない")
    func paddleKeepsSpeed() {
        for offset in stride(from: -1.5, through: 1.5, by: 0.1) {
            let v = BlocksPhysics.paddleBounce(offset: offset, speed: 83)
            #expect(abs(v.speed - 83) < 1e-9, "offset=\(offset) で速さが変わった: \(v.speed)")
        }
    }

    @Test("パドルの外まで offset が伸びても最大角で頭打ちになる")
    func paddleOffsetClamped() {
        let far = BlocksPhysics.paddleBounce(offset: 7, speed: 100)
        let edge = BlocksPhysics.paddleBounce(offset: 1, speed: 100)
        #expect(abs(far.vx - edge.vx) < 1e-12)
        #expect(abs(far.vy - edge.vy) < 1e-12)
    }

    @Test("パドルの反射は必ず上向き（下へ打ち出さない）")
    func paddleAlwaysUpward() {
        for offset in stride(from: -1.0, through: 1.0, by: 0.05) {
            #expect(BlocksPhysics.paddleBounce(offset: offset, speed: 70).vy > 0)
        }
    }

    // MARK: - 真横に近い角度の救済

    @Test("|vy| が下限を割ると押し上げられ、速さは保存される")
    func clampVerticalRaisesShallowAngle() {
        let shallow = BlocksPhysics.Velocity(vx: 99.9, vy: 0.5)
        let clamped = BlocksPhysics.clampVertical(shallow)
        #expect(clamped.vy >= clamped.speed * BlocksField.Metrics.minimumVerticalRatio - 1e-12)
        #expect(abs(clamped.speed - shallow.speed) < 1e-9)
        #expect(clamped.vx > 0, "横向きの符号は変えない")
    }

    @Test("下向きに浅い角度でも下向きのまま押し下げられる（勝手に上へ跳ね返さない）")
    func clampVerticalKeepsDownwardSign() {
        let clamped = BlocksPhysics.clampVertical(BlocksPhysics.Velocity(vx: -80, vy: -0.2))
        #expect(clamped.vy < 0)
        #expect(clamped.vx < 0)
        #expect(abs(clamped.vy) >= clamped.speed * BlocksField.Metrics.minimumVerticalRatio - 1e-12)
    }

    @Test("完全に水平（vy = 0）でも詰まず、上向きへ倒す")
    func clampVerticalRescuesHorizontal() {
        let clamped = BlocksPhysics.clampVertical(BlocksPhysics.Velocity(vx: 70, vy: 0))
        #expect(clamped.vy > 0)
        #expect(abs(clamped.speed - 70) < 1e-9)
    }

    @Test("十分に立った角度は素通し（余計に曲げない）")
    func clampVerticalLeavesSteepAngleAlone() {
        let steep = BlocksPhysics.Velocity(vx: 30, vy: 60)
        let clamped = BlocksPhysics.clampVertical(steep)
        #expect(clamped == steep)
    }

    // MARK: - ブロックとの当たり

    private let rect = BlocksPhysics.Rect(minX: 20, maxX: 31.1, minY: 100, maxY: 105)

    @Test("重なっていなければ衝突しない")
    func noCollisionWhenApart() {
        #expect(BlocksPhysics.blockCollision(ballX: 25, ballY: 90, radius: 2, rect: rect) == nil)
        #expect(BlocksPhysics.blockCollision(ballX: 10, ballY: 102, radius: 2, rect: rect) == nil)
    }

    @Test("下の面に当たったら上下反転（vertical）で、球は面の外へ押し出される")
    func hitsBottomFace() {
        let hit = BlocksPhysics.blockCollision(ballX: 25, ballY: 98.5, radius: 2, rect: rect)
        #expect(hit?.axis == .vertical)
        #expect(hit.map { abs($0.y - 98) < 1e-12 } == true, "minY - radius = 98 へ押し出す")
        #expect(hit?.x == 25, "反転しない軸の座標は動かさない")
    }

    @Test("上の面に当たったら上下反転で、上側へ押し出される")
    func hitsTopFace() {
        let hit = BlocksPhysics.blockCollision(ballX: 25, ballY: 106.5, radius: 2, rect: rect)
        #expect(hit?.axis == .vertical)
        #expect(hit.map { abs($0.y - 107) < 1e-12 } == true, "maxY + radius = 107")
    }

    @Test("横の面に当たったら左右反転（horizontal）")
    func hitsSideFace() {
        let left = BlocksPhysics.blockCollision(ballX: 18.5, ballY: 102, radius: 2, rect: rect)
        #expect(left?.axis == .horizontal)
        #expect(left.map { abs($0.x - 18) < 1e-12 } == true, "minX - radius = 18")

        let right = BlocksPhysics.blockCollision(ballX: 32.5, ballY: 102, radius: 2, rect: rect)
        #expect(right?.axis == .horizontal)
        #expect(right.map { abs($0.x - 33.1) < 1e-12 } == true, "maxX + radius = 33.1")
    }

    @Test("角に当たったときは中心と最近点を結ぶ向きが長いほうの軸で反転する")
    func hitsCorner() {
        // 左下の角 (20, 100) の少し左下。dx = -1.2 / dy = -1.0 なので横のほうが長い。
        let horizontal = BlocksPhysics.blockCollision(ballX: 18.8, ballY: 99.0, radius: 2, rect: rect)
        #expect(horizontal?.axis == .horizontal)

        // 同じ角の、より真下寄り。dx = -0.6 / dy = -1.5 で縦のほうが長い。
        let vertical = BlocksPhysics.blockCollision(ballX: 19.4, ballY: 98.5, radius: 2, rect: rect)
        #expect(vertical?.axis == .vertical)
    }

    @Test("完全にめり込んだときは、押し出し量がいちばん小さい面から出る")
    func resolvesDeepOverlap() {
        // 下寄りに沈み込んでいる（下面まで 0.5・左面まで 3）。
        let deep = BlocksPhysics.blockCollision(ballX: 23, ballY: 100.5, radius: 2, rect: rect)
        #expect(deep?.axis == .vertical)
        #expect(deep.map { abs($0.y - 98) < 1e-12 } == true)

        // 左寄りに沈み込んでいる（左面まで 0.4・上下はどちらも 2 以上）。
        let side = BlocksPhysics.blockCollision(ballX: 20.4, ballY: 102.5, radius: 2, rect: rect)
        #expect(side?.axis == .horizontal)
        #expect(side.map { abs($0.x - 18) < 1e-12 } == true)
    }
}
