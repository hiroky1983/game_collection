import Core
import Foundation
import SpriteKit

extension RunnerScene {
    /// エンドレスの描画（#1086）。**部品のノードを使い回す**（オブジェクトプール）。
    ///
    /// ステージ制は走り出す前にコース全体のノードを作る（`buildStageCourse`）が、終わりの無いコースで
    /// それをやると距離に比例してノードが増える。ここでは部品の種類ごとに、枠の数
    /// （`RunnerEndlessTrack.defaultCapacity`）だけノードを**最初に 1 度だけ**作っておき、
    /// 枠に区画が入ったら空いている部品を置き、枠から区画が出たら部品を片付けて次に回す。
    /// 1 つの区画が使う部品は種類ごとに高々 1 つなので、種類ごとに枠の数だけあれば足りない
    /// ことは無い（足りなければその場で作り足す。`nodeCount` のテストで起きないことを固定）。
    @MainActor
    final class EndlessRenderer {
        /// 部品の種類。見た目が違うもの（穴の幅・台座と床の長さ）は別の種類にする。
        enum PartKind: Hashable, CaseIterable {
            /// 区画 1 つぶんの地面。`pitTiles` が 0 なら穴なし、2〜4 ならその幅の穴が中央にある。
            case ground(pitTiles: Int)
            case lowRock, tallRock
            case bird, dog, boar
            /// 連続の長さ（区画数）ごと。台座は 2〜3、床は 1〜2（`RunnerEndlessGenerator.place`）。
            case platform(segments: Int)
            case boostFloor(segments: Int)
            case speedPickup, takoyaki

            /// 作って並べる順。**ステージ制がコース層に足す順（地面 → 床 → 障害 → 台座 → アイテム）と
            /// 同じにする**——同じ z のノードは足した順に描かれるので、使い回しても重なり方が変わらない。
            static let allCases: [PartKind] = [
                .ground(pitTiles: 0), .ground(pitTiles: 2), .ground(pitTiles: 3), .ground(pitTiles: 4),
                .boostFloor(segments: 1), .boostFloor(segments: 2),
                .lowRock, .tallRock, .bird, .dog, .boar,
                .platform(segments: 2), .platform(segments: 3),
                .speedPickup, .takoyaki,
            ]
        }

        /// 使い回す部品 1 つ。作った直後の姿勢（位置・回転・拡大・透明度・表示・一時停止）と、
        /// 掛けてあった繰り返しの動き（`RunnerScene.loopActionKey`）を子孫ぶん覚えておき、
        /// 片付けるときに戻す——**前の区画の見た目（向き・影・アニメーションの途中）を持ち越さない**。
        @MainActor
        final class Part {
            struct Pose: Equatable {
                var position: CGPoint
                var zRotation: CGFloat
                var xScale: CGFloat
                var yScale: CGFloat
                var alpha: CGFloat
                var isHidden: Bool
                var isPaused: Bool
                var speed: CGFloat

                @MainActor init(_ node: SKNode) {
                    position = node.position
                    zRotation = node.zRotation
                    xScale = node.xScale
                    yScale = node.yScale
                    alpha = node.alpha
                    isHidden = node.isHidden
                    isPaused = node.isPaused
                    speed = node.speed
                }

                @MainActor func apply(to node: SKNode) {
                    node.position = position
                    node.zRotation = zRotation
                    node.xScale = xScale
                    node.yScale = yScale
                    node.alpha = alpha
                    node.isHidden = isHidden
                    node.isPaused = isPaused
                    node.speed = speed
                }
            }

            let kind: PartKind
            let node: SKNode
            /// 動く障害の写し（鳥・犬・イノシシ）。それ以外は nil。
            let view: MovingHazardView?
            /// 子孫（自分を含む）と、作った直後の姿勢。
            private let poses: [(node: SKNode, pose: Pose)]
            /// 繰り返しの動きを掛けてあったノードと、その動き。
            private let loops: [(node: SKNode, action: SKAction)]
            /// いま区画に置いているか。
            private(set) var isInUse = false

            init(kind: PartKind, node: SKNode, view: MovingHazardView? = nil) {
                self.kind = kind
                self.node = node
                self.view = view
                var poses: [(SKNode, Pose)] = []
                var loops: [(SKNode, SKAction)] = []
                func visit(_ current: SKNode) {
                    poses.append((current, Pose(current)))
                    if let loop = current.action(forKey: RunnerScene.loopActionKey) { loops.append((current, loop)) }
                    for child in current.children { visit(child) }
                }
                visit(node)
                self.poses = poses
                self.loops = loops
                park()
            }

            /// 片付ける。動きを止め、作った直後の姿勢へ戻して隠す。
            func park() {
                for (node, pose) in poses {
                    node.removeAllActions()
                    pose.apply(to: node)
                }
                view?.resetForReuse()
                node.isHidden = true
                isInUse = false
            }

            /// 区画に置く。姿勢は `park()` で戻してあるので、見せて繰り返しの動きを掛け直すだけ。
            func activate() {
                node.isHidden = false
                for (node, action) in loops { node.run(action, withKey: RunnerScene.loopActionKey) }
                isInUse = true
            }

            /// 作った直後の姿勢と一致しているか（テスト用）。
            var isAtRestPose: Bool {
                poses.allSatisfy { node, pose in
                    // 表示はルート（`park()` で隠す）だけ作った直後と違ってよい。
                    var current = Pose(node)
                    if node === self.node { current.isHidden = pose.isHidden }
                    return current == pose
                }
            }
            /// 繰り返しの動きを掛けてあるノードの数（テスト用）。
            var loopCount: Int { loops.count }
        }

        /// いま枠に入っている区画に置いた部品。
        struct RenderedSegment {
            let index: Int
            let ground: Part
            /// 地面の上に置いた部品（岩・動く障害・アイテム・台座・床のどれか 1 つ。平地なら nil）。
            let item: Part?
            /// アイテムを取って消し始めたか。
            var isPickupRemoved = false
        }

        /// 部品を作った世界。世界が変わったら作り直す（色が世界ごとに違うため）。
        let world: RunnerWorld
        /// 種類ごとの、空いている部品。
        private var free: [PartKind: [Part]] = [:]
        /// 作った部品のすべて（作った順）。コース層を空にしたあと、この順に足し直す。
        private(set) var parts: [Part] = []
        /// いま描いている区画。区画の通し番号を枠の数で割った余りの位置に入れる（枠に入る区画は
        /// 通し番号が連続して枠の数以下なので、余りは重ならない）。
        var rendered: [RenderedSegment?]
        /// 走り出す地点より手前（x < 0）の地面。ステージ制と同じく、開始時の画面左を崖に見せない。
        let leadIn: SKNode

        init(scene: RunnerScene, capacity: Int) {
            world = scene.world
            rendered = Array(repeating: nil, count: capacity)
            leadIn = SKNode()
            scene.addGround(from: -Metrics.width, to: 0, into: leadIn)
            for kind in PartKind.allCases {
                for _ in 0..<capacity { makePart(kind, in: scene) }
            }
        }

        /// 部品を 1 つ作ってコース層に足し、空いている部品に加える。
        @discardableResult
        private func makePart(_ kind: PartKind, in scene: RunnerScene) -> Part {
            let segment = RunnerEndlessSegment.width
            let tile = RunnerRules.tileWidth
            let part: Part
            switch kind {
            case .ground(let pitTiles):
                let node = SKNode()
                if pitTiles == 0 {
                    scene.addGround(from: 0, to: segment, bandStart: -Self.groundSeamOverlap, into: node)
                } else {
                    // 穴は区画の中央（`RunnerEndlessSegment` と同じ `hazardTileOffset`）。
                    let pit = RunnerHazard(
                        kind: .pit, start: Double(RunnerRules.hazardTileOffset) * tile, length: Double(pitTiles) * tile
                    )
                    scene.addGround(from: 0, to: pit.start, bandStart: -Self.groundSeamOverlap, into: node)
                    scene.addPitVoid(pit, into: node)
                    scene.addPitEdgeMarkers(pit, into: node)
                    scene.addGround(from: pit.end, to: segment, into: node)
                }
                scene.courseLayer.addChild(node)
                part = Part(kind: kind, node: node)
            case .lowRock, .tallRock:
                let node = scene.makeRock(RunnerHazard(kind: kind == .lowRock ? .lowBlock : .tallBlock, start: 0, length: tile))
                scene.courseLayer.addChild(node)
                part = Part(kind: kind, node: node)
            case .bird:
                let view = scene.addBird(RunnerHazard(kind: .bird, start: 0, length: tile))
                part = Part(kind: kind, node: view.node, view: view)
            case .dog:
                let view = scene.addDog(RunnerHazard(kind: .dog, start: 0, length: tile))
                part = Part(kind: kind, node: view.node, view: view)
            case .boar:
                let view = scene.addBoar(RunnerHazard(kind: .boar, start: 0, length: tile))
                part = Part(kind: kind, node: view.node, view: view)
            case .platform(let segments):
                let node = scene.makePlatform(RunnerPlatform(start: 0, length: Double(segments) * segment))
                scene.courseLayer.addChild(node)
                part = Part(kind: kind, node: node)
            case .boostFloor(let segments):
                let node = scene.makeBoostFloor(RunnerBoostFloor(start: 0, length: Double(segments) * segment))
                // 床は次の区画の地面にもまたがる。地面より手前に出すため、足した順ではなく z で持ち上げる
                // （次の区画の地面は、床より後に置かれることがある）。
                node.zPosition = Self.boostFloorZ
                scene.courseLayer.addChild(node)
                part = Part(kind: kind, node: node)
            case .speedPickup:
                part = Part(kind: kind, node: scene.addPickup(RunnerPickup(kind: .speed, start: 0)))
            case .takoyaki:
                part = Part(kind: kind, node: scene.addTakoyaki(RunnerPickup(kind: .invincible, start: 0)))
            }
            parts.append(part)
            free[kind, default: []].append(part)
            return part
        }

        /// 隣の区画との継ぎ目に細い隙間が見えないよう、区画ごとの地面の帯を左へ重ねる幅。
        /// 重なる左隣の 0.5 は破線の切れ目（区画の終わり 4 は線が無い）なので、どちらが手前に描かれても見た目は同じ。
        nonisolated static let groundSeamOverlap: Double = 0.5
        /// 床の z（地面は 0）。部品の中の相対 z（最大 7）と足しても層の間隔（`LayerZ.partMax`）に収まる。
        nonisolated static let boostFloorZ: CGFloat = 0.5
        /// 原点（`renderOrigin`）を動かす間隔（ワールド単位・64 区画ぶん）。
        ///
        /// ノードの x はおおむね `−200〜rebaseSpan + 200` に収まる。単精度でも 1/1000 単位の刻みが残る大きさで、
        /// 動かす頻度は最高速（毎秒 93）でも 44 秒に 1 回。
        nonisolated static let rebaseSpan: Double = 4_096

        /// 空いている部品を区画に置く。足りなければ作り足す（起きないことを `nodeCount` のテストで固定）。
        func acquire(_ kind: PartKind, in scene: RunnerScene) -> Part {
            if free[kind]?.isEmpty ?? true { makePart(kind, in: scene) }
            let part = free[kind]!.removeLast()
            part.activate()
            return part
        }

        /// 部品を片付けて空きに戻す。
        func release(_ part: Part) {
            part.park()
            free[part.kind, default: []].append(part)
        }

        /// 区画に置いた部品をすべて片付ける。
        func release(_ segment: RenderedSegment) {
            release(segment.ground)
            if let item = segment.item { release(item) }
        }

        /// コース層を空にしたあと（`rebuildCourse`）、部品を作った順に足し直してすべて片付ける。
        func reattach(to layer: SKNode) {
            layer.addChild(leadIn)
            for part in parts {
                layer.addChild(part.node)
                if part.isInUse { part.park() }
            }
            for kind in PartKind.allCases { free[kind] = parts.filter { $0.kind == kind } }
            for slot in rendered.indices { rendered[slot] = nil }
        }

        /// 作った部品の数（種類ごと・テスト用）。
        func partCount(of kind: PartKind) -> Int { parts.filter { $0.kind == kind }.count }
    }

    /// エンドレスの部品の置き場を用意する（`rebuildCourse` から呼ぶ）。世界が変わっていなければ前の部品を使い回す。
    func buildEndlessCourse() {
        let capacity = model.field.track?.capacity ?? RunnerEndlessTrack.defaultCapacity
        if endless?.world != world || endless?.rendered.count != capacity {
            endless = EndlessRenderer(scene: self, capacity: capacity)
            // 作った部品はすでにコース層に足してあるが、並びを揃えるため一度外して足し直す。
            courseLayer.removeAllChildren()
        }
        endless?.leadIn.position = CGPoint(x: 0, y: 0)
        endless?.reattach(to: courseLayer)
    }

    /// 枠（`RunnerField.track`）に入っている区画に部品を置き、出ていった区画の部品を片付ける（#1086）。
    /// 毎フレーム `sync` から呼ぶ。枠は高々 `capacity` 区画なので、1 フレームの仕事は区画の数に比例するだけ。
    func syncEndlessCourse(_ field: RunnerField) {
        guard let track = field.track, let endless else { return }
        applyRenderOrigin(Self.rebasedRenderOrigin(current: renderOrigin, distance: field.distance))
        let capacity = endless.rendered.count

        // 枠から出た区画を片付ける。
        for slot in 0..<capacity {
            guard let rendered = endless.rendered[slot] else { continue }
            if rendered.index < track.firstIndex || rendered.index >= track.endIndex {
                endless.release(rendered)
                endless.rendered[slot] = nil
            }
        }

        // 枠に入った区画に部品を置き、置いてある区画のアイテム・動く障害を反映する。
        for position in 0..<track.count {
            let segment = track[position]
            let slot = segment.index % capacity
            if endless.rendered[slot]?.index != segment.index {
                if let stale = endless.rendered[slot] { endless.release(stale) }
                endless.rendered[slot] = place(segment, with: endless, field: field)
            }
            guard var rendered = endless.rendered[slot], let item = rendered.item else { continue }
            if let view = item.view {
                syncMovingHazard(view, field: field)
            } else if item.kind == .speedPickup || item.kind == .takoyaki, !rendered.isPickupRemoved,
                      field.collectedPickupIndices.contains(segment.index) {
                hidePickupNode(item.node)
                rendered.isPickupRemoved = true
                endless.rendered[slot] = rendered
            }
        }
        // 手前の地面は、画面の左端（走者の 26 後ろ）より十分後ろへ流れたらコース層から外す
        // （次の走行の `rebuildCourse` で足し直す）。残しておくと原点を戻すたびに遠くへずれていく。
        if field.distance > Metrics.width * 2, endless.leadIn.parent != nil { endless.leadIn.removeFromParent() }
    }

    /// 区画 `segment` に部品を置く。
    private func place(
        _ segment: RunnerEndlessSegment, with endless: EndlessRenderer, field: RunnerField
    ) -> EndlessRenderer.RenderedSegment {
        typealias Kind = EndlessRenderer.PartKind
        var pitTiles = 0
        if let hazard = segment.hazard, hazard.kind == .pit {
            pitTiles = Int((hazard.length / RunnerRules.tileWidth).rounded())
        }
        let ground = endless.acquire(.ground(pitTiles: pitTiles), in: self)
        ground.node.position.x = segment.start - renderOrigin

        var item: EndlessRenderer.Part?
        if let hazard = segment.hazard {
            switch hazard.kind {
            case .pit:
                break
            case .lowBlock, .tallBlock:
                item = endless.acquire(hazard.kind == .lowBlock ? .lowRock : .tallRock, in: self)
                item?.node.position.x = hazard.start - renderOrigin
            case .bird, .dog, .boar:
                let kind: Kind = hazard.kind == .bird ? .bird : hazard.kind == .dog ? .dog : .boar
                let part = endless.acquire(kind, in: self)
                part.view?.hazard = hazard
                item = part
            }
        } else if let pickup = segment.pickup {
            item = endless.acquire(pickup.kind == .speed ? .speedPickup : .takoyaki, in: self)
            item?.node.position.x = pickup.start - renderOrigin
        } else if let platform = segment.platform {
            item = endless.acquire(.platform(segments: Int((platform.length / RunnerEndlessSegment.width).rounded())), in: self)
            item?.node.position.x = platform.start - renderOrigin
        } else if let floor = segment.boostFloor {
            item = endless.acquire(.boostFloor(segments: Int((floor.length / RunnerEndlessSegment.width).rounded())), in: self)
            item?.node.position.x = floor.start - renderOrigin
        }
        var rendered = EndlessRenderer.RenderedSegment(index: segment.index, ground: ground, item: item)
        // 取ったアイテムの区画を置き直すことは無い（枠は前にしか進まない）が、置いた時点で
        // 取ってあれば最初から見せない。
        if segment.pickup != nil, let item, field.collectedPickupIndices.contains(segment.index) {
            item.node.removeAllActions()
            item.node.isHidden = true
            rendered.isPickupRemoved = true
        }
        return rendered
    }

    /// 取ったアイテムをフェードアウト＋縮小で隠す（エンドレス・#1086）。ステージ制の `removePickupNode` と
    /// 同じ動きで、ノードを外さずに隠すだけ（使い回すため）。
    func hidePickupNode(_ node: SKNode) {
        node.removeAllActions()
        node.run(.sequence([
            .group([.fadeOut(withDuration: 0.25), .scale(to: 0.2, duration: 0.25)]),
            .hide(),
        ]))
    }

    /// 走者が `distance` にいるときのコース層の原点。いまの原点から `rebaseSpan` 以上離れたら、
    /// 走者のいる区画の左端へ動かす（区画の左端に揃えるのは、破線の位相を区画の頭に揃えてあるため）。
    nonisolated static func rebasedRenderOrigin(current: Double, distance: Double) -> Double {
        guard abs(distance - current) >= EndlessRenderer.rebaseSpan else { return current }
        let width = RunnerEndlessSegment.width
        return (distance / width).rounded(.down) * width
    }

    /// コース層の原点を `origin` に動かす。見えているノードを同じだけ動かすので、画面上の位置は変わらない
    /// （`courseLayer.position` は `sync` が同じフレームのうちに `courseLayerX` で合わせ直す）。
    ///
    /// **隠れているノードは動かさない**。片付けた部品（`EndlessRenderer.Part.park()`）は次に置くときに
    /// 位置を決め直すので、動かすと原点を戻すたびに遠くへずれていくだけになる。
    func applyRenderOrigin(_ origin: Double) {
        guard origin != renderOrigin else { return }
        let shift = origin - renderOrigin
        for child in courseLayer.children where !child.isHidden { child.position.x -= shift }
        renderOrigin = origin
    }
}
