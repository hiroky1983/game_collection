import Testing
import SpriteKit
import GameKitTestSupport
@testable import GameRunner

/// 常時ループの装飾が「視差効果を減らす」に従うこと（#1973）。
@Suite("装飾ループと視差効果を減らす")
struct RunnerAmbientLoopTests {
    /// `loopActionKey` の動きが掛かっているノードの数（部品の子孫まで見る）。
    @MainActor
    private func loopingNodeCount(reduceMotion: Bool, stages: ClosedRange<Int>) -> Int {
        var count = 0
        for number in stages {
            let model = RunnerModel(startingAt: number, preference: makePreference("ambient-\(reduceMotion)-\(number)"))
            let scene = RunnerScene(model: model)
            scene.reduceMotionOverride = reduceMotion
            scene.rebuildCourse()
            var queue: [SKNode] = [scene.courseLayer]
            while let node = queue.popLast() {
                if node.action(forKey: RunnerScene.loopActionKey) != nil { count += 1 }
                queue.append(contentsOf: node.children)
            }
        }
        return count
    }

    @Test("視差効果を減らすがオンなら、コースの装飾に繰り返しの動きが掛からない")
    @MainActor
    func noLoopsWhenReducingMotion() {
        #expect(loopingNodeCount(reduceMotion: true, stages: 1...RunnerRules.stageCount) == 0)
    }

    @Test("オフなら今までどおり装飾が動く（空振り防止の対照）")
    @MainActor
    func loopsWhenNotReducingMotion() {
        #expect(loopingNodeCount(reduceMotion: false, stages: 1...RunnerRules.stageCount) > 0)
    }

    /// 装飾の `repeatForever` を `runAmbientLoop` を通さず直に足すと、この数が合わなくなる。
    /// 直書きが残るのは、いずれも別に `reducesMotion` / ゲーム進行の都合で扱っているもの:
    /// ヘルパー本体・宝くじの揺れ（`applyGoalTicketSway`）・宝くじの煌めき・無敵中の点滅。
    @Test("repeatForever の直書きは、ヘルパーと既に配慮済みの3箇所だけ")
    func repeatForeverGoesThroughHelper() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        #expect(SourceScan.matchCount(of: #"\.repeatForever\("#, in: source) == 4)
    }
}
