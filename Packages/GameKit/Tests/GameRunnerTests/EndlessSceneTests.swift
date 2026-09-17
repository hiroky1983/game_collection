import Foundation
import SpriteKit
import Testing
@testable import GameRunner

/// エンドレスの描画（#1086 の受け入れ条件 D・F・G）。
///
/// `RunnerScene` を画面に出さずに組み、`rebuildCourse()` / `sync()` を直接呼ぶ。`SKAction` は
/// 画面に出していないので進まない（アニメーションの途中の状態はテストの中で直接作る）。
@Suite("チャリンコおじさん: エンドレスの描画")
@MainActor
struct RunnerEndlessSceneTests {
    private func makeScene(seed: UInt64, suite: String) -> (RunnerModel, RunnerScene) {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-scene-\(suite)"))
        model.newEndlessGame(seed: seed)
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        scene.sync()
        return (model, scene)
    }

    /// 部品のノード（演出の粒 `dustNodeName` と、走り出す地点の手前の地面 `leadIn` を除く）を子孫まで数える。
    private func partNodeCount(_ node: SKNode, excluding leadIn: SKNode? = nil) -> Int {
        node.children.reduce(0) { total, child in
            child.name == RunnerScene.dustNodeName || child === leadIn
                ? total : total + 1 + partNodeCount(child, excluding: leadIn)
        }
    }

    /// 画面上の x（シーンの座標）。
    private func screenX(_ node: SKNode, in scene: RunnerScene) -> Double {
        Double(scene.courseLayer.position.x + node.position.x)
    }

    /// 受け入れ条件 D「描画ノードの数に上限があり、距離に比例して増えない」。
    @Test("部品のノードは最初に作った数から増えず、描く区画は枠の区画と一致する", .timeLimit(.minutes(3)))
    func nodeCountStaysConstant() throws {
        let (model, scene) = makeScene(seed: 21, suite: "nodes")
        let endless = try #require(scene.endless)
        for kind in RunnerScene.EndlessRenderer.PartKind.allCases {
            #expect(endless.partCount(of: kind) == RunnerEndlessTrack.defaultCapacity, "\(kind)")
        }
        let initial = partNodeCount(scene.courseLayer, excluding: endless.leadIn)
        print("エンドレスの部品のノード数: \(initial)")
        // 上限（数えた値を固定する。部品の絵を描き替えて増減したらここを直す）。
        #expect(initial <= 2_000, "部品のノード \(initial)")

        model.press()
        model.release()
        var distance = 0.0
        while distance < 20_000 {
            distance += 13
            model.fastForwardEndlessForDebug(to: distance)
            scene.sync()
            let track = try #require(model.field.track)
            let rendered = endless.rendered.compactMap { $0?.index }.sorted()
            #expect(rendered == Array(track.firstIndex..<track.endIndex), "距離 \(distance): 描く区画 \(rendered)")
            // 画面の左端（走者の `playerX` 後ろ）まで地面の区画を描いている（後ろに残す区画が足りないと左端が欠ける）。
            let leftEdge = distance - RunnerField.Metrics.playerX - RunnerField.Metrics.playerWidth
            if leftEdge > 0, let first = rendered.first {
                #expect(Double(first) * RunnerEndlessSegment.width <= leftEdge, "距離 \(distance): 画面の左端の地面が無い")
            }
            if Int(distance) % 1_000 < 13 {
                #expect(partNodeCount(scene.courseLayer, excluding: endless.leadIn) == initial, "距離 \(distance) でノードが増減した")
            }
        }
        for kind in RunnerScene.EndlessRenderer.PartKind.allCases {
            #expect(endless.partCount(of: kind) == RunnerEndlessTrack.defaultCapacity, "\(kind) を作り足した")
        }
        // 新しい種で作り直しても、部品は作り直さずに使い回す。
        model.newEndlessGame(seed: 22)
        scene.sync()
        #expect(scene.endless === endless)
        #expect(partNodeCount(scene.courseLayer, excluding: endless.leadIn) == initial)
    }

    /// 受け入れ条件 F「取った直後に枠が回っても、描画側と食い違わない」。自動操縦で実際に走って取り、
    /// 毎フレーム「取った区画のアイテムは消し始めている／取っていない区画のアイテムは見えている」を見る。
    @Test("取ったアイテムの描画は、枠を回しても取った印と食い違わない", .timeLimit(.minutes(3)))
    func pickupRenderingFollowsCollection() throws {
        let (model, scene) = makeScene(seed: 1086, suite: "pickups")
        let endless = try #require(scene.endless)
        model.press()
        model.release()
        var frames = 0
        var checkedCollected = 0
        while model.distance < 16_000, model.phase.isRunning, frames < 60 * 600 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
            for rendered in endless.rendered.compactMap({ $0 }) {
                guard let item = rendered.item, item.kind == .speedPickup || item.kind == .takoyaki else { continue }
                let collected = model.field.collectedPickupIndices.contains(rendered.index)
                #expect(rendered.isPickupRemoved == collected, "区画 \(rendered.index): 描画 \(rendered.isPickupRemoved) / 取った印 \(collected)")
                if !collected { #expect(!item.node.isHidden, "取っていないアイテム（区画 \(rendered.index)）が見えない") }
                if collected {
                    // 消す動き（`hidePickupNode`）を掛けたか、すでに隠れている。画面に出していないので動きは進まない。
                    #expect(item.node.hasActions() || item.node.isHidden, "取ったアイテム（区画 \(rendered.index)）を消していない")
                    checkedCollected += 1
                }
            }
        }
        #expect(model.distance >= 16_000, "\(model.distance) で \(model.phase)")
        #expect(checkedCollected > 0, "取ったアイテムを 1 つも確かめていない")
    }

    /// 受け入れ条件 G「距離 10,000,000 単位相当まで進めても、ノードの x 座標の絶対値が一定の範囲に収まる」。
    @Test("10,000,000 単位先でも、コース層とノードの x は 10,000 以内", .timeLimit(.minutes(3)))
    func nodesStayNearOriginFarAway() throws {
        let (model, scene) = makeScene(seed: 5, suite: "far")
        model.press()
        model.release()
        for distance in stride(from: 9_999_000.0, through: 10_000_300, by: 7) {
            model.fastForwardEndlessForDebug(to: distance)
            scene.sync()
        }
        #expect(model.distance >= 10_000_000)
        #expect(abs(scene.renderOrigin - 10_000_000) <= RunnerScene.EndlessRenderer.rebaseSpan)
        #expect(abs(scene.courseLayer.position.x) <= 10_000)
        for child in scene.courseLayer.children {
            #expect(abs(child.position.x) <= 10_000, "\(child) の x \(child.position.x)")
        }
        // 見えている部品は、画面上ではワールド座標どおりの位置にある。
        let endless = try #require(scene.endless)
        for rendered in endless.rendered.compactMap({ $0 }) {
            let expected = RunnerField.Metrics.playerX - model.distance + Double(rendered.index) * RunnerEndlessSegment.width
            #expect(abs(screenX(rendered.ground.node, in: scene) - expected) < 1e-3, "区画 \(rendered.index)")
        }
    }

    /// 受け入れ条件 G「原点を戻す瞬間に、障害物・走者が 1 フレームもずれない」「背景の視差・雲が跳ばない」。
    @Test("原点を戻しても、同じ距離での画面上の位置は変わらない")
    func rebasingDoesNotMoveAnythingOnScreen() throws {
        let (model, scene) = makeScene(seed: 8, suite: "rebase")
        model.press()
        model.release()
        // 原点を戻す直前まで進める。
        var distance = 0.0
        while distance < RunnerScene.EndlessRenderer.rebaseSpan - 3 {
            distance += 11
            model.fastForwardEndlessForDebug(to: min(distance, RunnerScene.EndlessRenderer.rebaseSpan - 3))
            scene.sync()
        }
        #expect(scene.renderOrigin == 0)
        let children = scene.courseLayer.children.filter { !$0.isHidden }
        #expect(children.count > 5)
        let before = children.map { screenX($0, in: scene) }
        let player = scene.player.position
        let clouds = scene.clouds.map(\.position)
        let hills = scene.hillTiles.map(\.position)

        // 同じ距離のまま原点だけ動かす。
        scene.applyRenderOrigin(3_968)
        scene.sync()
        #expect(scene.renderOrigin == 3_968)
        let after = children.map { screenX($0, in: scene) }
        for (index, (x0, x1)) in zip(before, after).enumerated() {
            // `SKNode.position` は単精度で持つので、比べるのは 1/1000 単位まで。
            #expect(abs(x0 - x1) < 1e-3, "\(children[index]) が \(x0) → \(x1)")
        }
        #expect(scene.player.position == player)
        #expect(scene.clouds.map(\.position) == clouds)
        #expect(scene.hillTiles.map(\.position) == hills)

        // 距離を進めて `sync` が自分で原点を戻す瞬間も、止まっている部品は進んだぶんだけ左へ動くだけ。
        let endless = try #require(scene.endless)
        scene.applyRenderOrigin(0)
        scene.sync()
        let grounds = endless.rendered.compactMap { $0 }.map { ($0.index, screenX($0.ground.node, in: scene)) }
        model.fastForwardEndlessForDebug(to: RunnerScene.EndlessRenderer.rebaseSpan + 1)
        scene.sync()
        #expect(scene.renderOrigin == RunnerScene.EndlessRenderer.rebaseSpan, "ここで原点が動く")
        for (index, x) in grounds {
            guard let rendered = endless.rendered.compactMap({ $0 }).first(where: { $0.index == index }) else { continue }
            #expect(abs(screenX(rendered.ground.node, in: scene) - (x - 4)) < 1e-3, "区画 \(index)")
        }
    }

    /// 受け入れ条件 G「背景の視差（`RunnerParallax.wrappedX`）・雲が原点の戻しで跳ばない」。雲・丘は
    /// 原点ではなく走行距離で流しているので、遠くでも小さく進めたぶんだけ滑らかに動く。
    @Test("10,000,000 単位先でも、雲・丘は進んだぶんだけ視差の倍率で滑らかに動く")
    func parallaxStaysSmoothFarAway() {
        let spacing = RunnerScene.cloudSpacing
        let count = 8
        let total = spacing * Double(count)
        for base in stride(from: 0.0, to: total, by: spacing) {
            for distance in [0.0, 25_600, 10_000_000, 10_000_000.5] {
                let x0 = RunnerParallax.wrappedX(base: base, distance: distance, parallax: RunnerScene.cloudParallax, spacing: spacing, count: count)
                let x1 = RunnerParallax.wrappedX(base: base, distance: distance + 1, parallax: RunnerScene.cloudParallax, spacing: spacing, count: count)
                var moved = x1 - x0
                if moved > total / 2 { moved -= total }  // 折り返し（画面の外で右端へ回る）
                if moved < -total / 2 { moved += total }
                #expect(abs(moved + RunnerScene.cloudParallax) < 1e-6, "距離 \(distance) で \(moved)")
            }
        }
    }

    /// 受け入れ条件 G「枠を回して使い回したノードに、前の区画の見た目（種類・向き・影・アニメーションの途中状態）が残らない」。
    @Test("片付けた部品は作った直後の姿勢に戻り、繰り返しの動きを掛け直してから次の区画に出る")
    func recycledPartsForgetPreviousSegment() throws {
        let (_, scene) = makeScene(seed: 2, suite: "recycle")
        let endless = try #require(scene.endless)
        for kind in RunnerScene.EndlessRenderer.PartKind.allCases {
            let part = endless.acquire(kind, in: scene)
            #expect(!part.node.isHidden)
            // 前の区画で進んだ状態を作る（向き・位置・透明度・一時停止・子の表示）。
            part.node.position = CGPoint(x: 1234, y: 56)
            part.node.xScale *= -1
            part.node.alpha = 0.2
            part.node.removeAllActions()
            for child in part.node.children {
                child.zRotation = 1.2
                child.isPaused = true
                child.isHidden.toggle()
                child.position.y += 3
                child.removeAllActions()
            }
            if let view = part.view {
                view.apply(.stopped)
                view.hazard = RunnerHazard(kind: view.hazard.kind, start: 9_999, length: RunnerRules.tileWidth)
                view.applyWalkFrame(travel: 1.3)
            }
            if kind == .speedPickup || kind == .takoyaki { scene.hidePickupNode(part.node) }
            #expect(!part.isAtRestPose, "\(kind): 対照（崩した状態は作った直後と違う）")

            endless.release(part)
            #expect(part.isAtRestPose, "\(kind): 片付けても姿勢が戻っていない")
            #expect(part.node.isHidden, "\(kind): 片付けた部品は隠す")
            #expect(!part.node.hasActions(), "\(kind): 動きが残っている")
            if let view = part.view {
                #expect(view.state == nil, "\(kind): 状態が残っている")
                #expect(view.walkSprite?.texture === view.walkTextures.first, "\(kind): 歩きのコマが残っている")
            }

            let reused = endless.acquire(kind, in: scene)
            #expect(reused === part, "\(kind): 片付けた部品が次に使われる")
            var loops = 0
            func count(_ node: SKNode) {
                if node.action(forKey: RunnerScene.loopActionKey) != nil { loops += 1 }
                node.children.forEach(count)
            }
            count(reused.node)
            #expect(loops == reused.loopCount, "\(kind): 繰り返しの動き \(loops) / \(reused.loopCount)")
            endless.release(reused)
        }
        // 動くものは実際に繰り返しの動きを持っている（キーを付け忘れると 0 になる）。
        for kind: RunnerScene.EndlessRenderer.PartKind in [.bird, .boar, .speedPickup, .takoyaki, .boostFloor(segments: 1)] {
            let part = endless.acquire(kind, in: scene)
            #expect(part.loopCount > 0, "\(kind) に繰り返しの動きが無い")
            endless.release(part)
        }
    }

    /// ステージ制は原点を動かさない（従来どおりワールド座標のまま・受け入れ条件 J）。
    @Test("ステージ制は原点 0 のまま、コース層の x は走者の位置 − 距離")
    func stagesKeepWorldCoordinates() {
        let model = RunnerModel(startingAt: 18, preference: makePreference("endless-scene-stages"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        model.press()
        model.release()
        for _ in 0..<600 {
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
        }
        #expect(scene.endless == nil)
        #expect(scene.renderOrigin == 0)
        // `SKNode.position` は単精度で持つ（この丸めがエンドレスで原点を動かす理由）。
        #expect(abs(Double(scene.courseLayer.position.x) - (RunnerField.Metrics.playerX - model.distance)) < 1e-3)
        #expect(RunnerScene.courseLayerX(distance: 1_234.5, origin: 0) == RunnerField.Metrics.playerX - 1_234.5)
    }
}
