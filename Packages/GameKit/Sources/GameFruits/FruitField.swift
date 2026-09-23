import Foundation

/// 盤の上の果物 1 個。
public struct Fruit: Equatable, Sendable, Codable {
    public let id: Int
    public let kind: FruitKind
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    /// 転がりの見た目（ラジアン）。描画だけが使い、当たり判定には関わらない。
    public var angle: Double
    /// 盤に現れてからの秒数。危険線の判定の猶予（`FruitField.Metrics.overLineGrace`）に使う。
    public var age: Double
    /// 危険線より上に居続けている秒数。線の下に戻ると 0 に戻る。
    public var overLineTime: Double
    /// 落としてから一度でも何かに触れたか（触れた瞬間の手応えを 1 回だけ返すため）。
    public var hasTouched: Bool

    public init(id: Int, kind: FruitKind, x: Double, y: Double, vx: Double = 0, vy: Double = 0,
                angle: Double = 0, age: Double = 0, overLineTime: Double = 0, hasTouched: Bool = false) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.angle = angle
        self.age = age
        self.overLineTime = overLineTime
        self.hasTouched = hasTouched
    }

    public var radius: Double { kind.radius }
    public var mass: Double { kind.mass }
    public var speed: Double { (vx * vx + vy * vy).squareRoot() }
    /// 上端の高さ。危険線の判定に使う。
    public var top: Double { y + radius }
}

/// 1 回の `step(dt:)` で起きたできごと。Model がこれを見て得点・手応え・終局を動かす。
///
/// **Field は状態を進めるだけで、得点も終局後の扱いも知らない**（アクション枠の基盤規約と同じ分け方）。
public enum FruitEvent: Equatable, Sendable {
    /// 落とした果物が初めて何かに触れた。
    case touched(id: Int)
    /// 同じ種類が触れて 1 つ上の種類になった。`x` / `y` は新しい果物の位置。
    case merged(from: FruitKind, into: FruitKind, x: Double, y: Double, id: Int)
    /// いちばん大きい種類（メロン）が 2 つ触れて消えた。
    case vanished(x: Double, y: Double)
    /// 危険線より上に果物が居続けた（終局）。
    case gameOver
}

/// くっつきフルーツの盤面そのもの（#1319）。
///
/// **SpriteKit にも SwiftUI にも依存しない値型**で、`step(dt:)` を呼ぶと果物が落ちて転がる。
/// 得点・次に落とす果物・中断復元は持たない（それは `FruitsModel` の仕事）。
/// アクション枠の基盤規約（ブロック崩し #463）と同じく `SKPhysicsBody` は使わず、円どうしの
/// 衝突を自前で解く。理由は同じで、合体の条件・積み上がり・終局の判定を `swift test` で固定したい
/// （物理エンジンの解決は内部実装で、同じ入力でも SDK の版で結果が動きうる）。
///
/// 座標系は**左下が原点**（SpriteKit と同じ向き）で、単位は盤固有の抽象単位。
/// 画面 pt への変換は `FruitsScene` が `scaleMode = .aspectFit` で一括して行う。
public struct FruitField: Equatable, Sendable {
    /// 盤の寸法と物理の定数。すべて抽象単位（`width` × `height` の枠に収まる）。
    public enum Metrics {
        public static let width: Double = 100
        /// 盤の高さ。幅に対するこの比が画面上の盤の大きさを決める（ブロック崩し #597 と同じ論点）。
        /// 縦長すぎると iPhone SE で縦が頭打ちになり横幅が余る。1.2 は SE でも幅の 87% を使える値
        /// （`FruitsLayoutTests`）。
        public static let height: Double = 120
        /// 危険線。これより上に果物が `overLineLimit` 秒居続けたら終局。
        public static let deadlineY: Double = 96
        /// 落とす前の果物の中心の高さ。いちばん大きい落とせる果物（みかん・半径 8.8）の頭が天井に触れない。
        public static let spawnY: Double = 108
        /// 重力（単位/秒²）。
        public static let gravity: Double = 320
        /// 反発係数。小さいほど弾まず積み上がる。
        public static let restitution: Double = 0.12
        /// 果物どうしが触れたとき、接線方向の相対速度から 1 回の接触で削る割合。転がり落ちを穏やかにする。
        public static let contactFriction: Double = 0.3
        /// 床に触れているあいだの横方向の減衰（1/秒）。
        public static let floorFriction: Double = 6
        /// 空気抵抗（1/秒）。振動を収めるための弱い減衰。
        public static let airDrag: Double = 0.15
        /// 位置の押し戻しの緩和係数。1 だと 1 回で押し切り、積み上がった塊が跳ねる。
        public static let relaxation: Double = 0.7
        /// 1 サブステップの秒数。最速の落下（約 263 単位/秒）でも 1 サブステップの移動が
        /// いちばん小さい果物の半径（3.4）を超えない。
        public static let substep: Double = 1.0 / 120
        /// 1 サブステップで衝突を解く回数。
        public static let solverIterations = 5
        /// 同じ種類が「触れた」とみなす隙間。ぴったり接するまで待つと、隣で止まったまま合体しない。
        public static let mergeSlack: Double = 0.3
        /// 危険線より上に居続けてよい秒数。超えたら終局。
        public static let overLineLimit: Double = 1.0
        /// 盤に現れてから危険線の判定を始めるまでの猶予（秒）。落としたばかりの果物は線より上から
        /// 落ちてくるので、通り過ぎる時間ぶんは数えない。
        public static let overLineGrace: Double = 0.6
        /// これより遅ければ「止まっている」とみなす（単位/秒）。中断データの書き出しに使う。
        public static let sleepSpeed: Double = 2.0
        /// 広告コンティニューで取り除く小さい種類の数（ブルーベリー〜ライムの 4 種）。
        public static let continueRemovedKinds = 4

        /// 盤の縦横比（幅 / 高さ）。View はこの比で枠を作る。
        public static var aspectRatio: Double { width / height }

        /// 半径 `radius` の果物の中心として置ける x に丸める。
        public static func clampedX(_ x: Double, radius: Double) -> Double {
            min(width - radius, max(radius, x))
        }

        /// タップ位置（盤の枠のなかでの x・pt）を盤の x（抽象単位）へ写す。
        public static func fieldX(viewX: Double, viewWidth: Double) -> Double {
            guard viewWidth > 0 else { return width / 2 }
            return min(width, max(0, viewX / viewWidth * width))
        }

        /// 使える枠（pt）に収まる盤の実寸（pt）。`.aspectRatio(_:contentMode: .fit)` の計算そのもの。
        public static func boardSize(availableWidth: Double, availableHeight: Double) -> (width: Double, height: Double) {
            guard availableWidth > 0, availableHeight > 0 else { return (0, 0) }
            let heightLimited = availableHeight * aspectRatio
            if heightLimited <= availableWidth {
                return (heightLimited, availableHeight)
            }
            return (availableWidth, availableWidth / aspectRatio)
        }
    }

    /// 盤の上の果物（古い順）。
    public private(set) var fruits: [Fruit]
    /// 落とす前の果物の中心の x。`moveCursor(to:holding:)` で動かす。
    public private(set) var cursorX: Double
    /// 次に振る果物の ID。
    public private(set) var nextID: Int
    /// 終局したか。以後 `step(dt:)` は何もしない。
    public private(set) var isOver: Bool
    /// 直近の `step(dt:)` で危険線より上（猶予を過ぎたもの）に果物があったか。描画の警告に使う。
    public private(set) var isOverLine: Bool

    public init() {
        fruits = []
        cursorX = Metrics.width / 2
        nextID = 0
        isOver = false
        isOverLine = false
    }

    /// 中断データから作る。危険線の計時は 0 から数え直す（保存した瞬間の続きを再開する形にすると、
    /// 開いた瞬間に終局しうる）。
    public init(fruits: [Fruit], cursorX: Double) {
        self.fruits = fruits.map { fruit in
            var restored = fruit
            restored.overLineTime = 0
            return restored
        }
        self.cursorX = cursorX
        self.nextID = (fruits.map(\.id).max() ?? -1) + 1
        self.isOver = false
        self.isOverLine = false
    }

    public var count: Int { fruits.count }

    /// 果物がすべて止まっているか。
    public var isSettled: Bool { fruits.allSatisfy { $0.speed < Metrics.sleepSpeed } }

    /// いちばん高い果物の上端。何も無ければ 0。
    public var highestTop: Double { fruits.map(\.top).max() ?? 0 }

    // MARK: - 操作

    /// 落とす前の果物を `x` へ動かす。持っている果物の半径ぶん壁から離す。
    public mutating func moveCursor(to x: Double, holding kind: FruitKind) {
        cursorX = Metrics.clampedX(x, radius: kind.radius)
    }

    /// 持っている果物を `cursorX` から落とす。
    @discardableResult
    public mutating func drop(_ kind: FruitKind) -> Fruit {
        let x = Metrics.clampedX(cursorX, radius: kind.radius)
        let fruit = Fruit(id: nextID, kind: kind, x: x, y: Metrics.spawnY)
        nextID += 1
        fruits.append(fruit)
        return fruit
    }

    /// 広告コンティニュー。小さい種類（`Metrics.continueRemovedKinds`）と、危険線より上の果物を取り除いて
    /// 終局を取り消す。取り除いた数を返す。
    @discardableResult
    public mutating func clearForContinue() -> Int {
        let before = fruits.count
        fruits.removeAll { $0.kind.rawValue < Metrics.continueRemovedKinds || $0.top > Metrics.deadlineY }
        for index in fruits.indices {
            fruits[index].overLineTime = 0
        }
        isOver = false
        isOverLine = false
        return before - fruits.count
    }

    // MARK: - 進行

    /// `dt` 秒ぶん進める。呼び出し側（Model）が `dt` に上限を掛ける。
    public mutating func step(dt: Double) -> [FruitEvent] {
        guard !isOver, dt > 0 else { return [] }
        var events: [FruitEvent] = []
        var remaining = dt
        while remaining > 1e-9 {
            let h = min(Metrics.substep, remaining)
            remaining -= h
            integrate(h)
            var touched = [Bool](repeating: false, count: fruits.count)
            var merges: [(Int, Int)] = []
            var merging = Set<Int>()
            for _ in 0..<Metrics.solverIterations {
                resolveContacts(touched: &touched, merges: &merges, merging: &merging)
                resolveWalls(touched: &touched)
            }
            for index in fruits.indices {
                fruits[index].age += h
                guard touched[index] else { continue }
                // 転がりの見た目。右へ動けば時計回り（SpriteKit の zRotation は反時計回りが正）。
                fruits[index].angle -= fruits[index].vx / fruits[index].radius * h
                if !fruits[index].hasTouched {
                    fruits[index].hasTouched = true
                    events.append(.touched(id: fruits[index].id))
                }
            }
            if !merges.isEmpty {
                events += applyMerges(merges)
            }
        }
        events += updateOverLine(dt: dt)
        return events
    }

    private mutating func integrate(_ h: Double) {
        let drag = max(0, 1 - Metrics.airDrag * h)
        let floorDrag = max(0, 1 - Metrics.floorFriction * h)
        for index in fruits.indices {
            fruits[index].vy -= Metrics.gravity * h
            fruits[index].vx *= drag
            fruits[index].vy *= drag
            if fruits[index].y - fruits[index].radius <= 0.05 {
                fruits[index].vx *= floorDrag
            }
            fruits[index].x += fruits[index].vx * h
            fruits[index].y += fruits[index].vy * h
        }
    }

    /// 果物どうしの重なりを解く。x でソートして、重なりうる相手だけを見る（sweep and prune）。
    private mutating func resolveContacts(touched: inout [Bool], merges: inout [(Int, Int)], merging: inout Set<Int>) {
        let order = fruits.indices.sorted { fruits[$0].x - fruits[$0].radius < fruits[$1].x - fruits[$1].radius }
        for (position, i) in order.enumerated() {
            let rightEdge = fruits[i].x + fruits[i].radius
            for j in order[(position + 1)...] {
                if fruits[j].x - fruits[j].radius > rightEdge + Metrics.mergeSlack { break }
                resolvePair(i, j, touched: &touched, merges: &merges, merging: &merging)
            }
        }
    }

    private mutating func resolvePair(_ i: Int, _ j: Int, touched: inout [Bool], merges: inout [(Int, Int)], merging: inout Set<Int>) {
        let a = fruits[i]
        let b = fruits[j]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let distanceSquared = dx * dx + dy * dy
        let minDistance = a.radius + b.radius
        // 同じ種類は隙間ぶん手前で合体させる。
        if a.kind == b.kind, !merging.contains(i), !merging.contains(j),
           distanceSquared <= (minDistance + Metrics.mergeSlack) * (minDistance + Metrics.mergeSlack) {
            merges.append((i, j))
            merging.insert(i)
            merging.insert(j)
        }
        guard distanceSquared < minDistance * minDistance else { return }
        touched[i] = true
        touched[j] = true

        let distance = distanceSquared.squareRoot()
        // 中心が重なっていたら上下に分ける（合体で同じ点に生まれた直後など）。
        let nx = distance > 1e-9 ? dx / distance : 0
        let ny = distance > 1e-9 ? dy / distance : 1
        let penetration = minDistance - distance
        let inverseMassA = 1 / a.mass
        let inverseMassB = 1 / b.mass
        let inverseMassSum = inverseMassA + inverseMassB

        // 位置の押し戻し（質量で按分）。
        let correction = penetration * Metrics.relaxation / inverseMassSum
        fruits[i].x -= nx * correction * inverseMassA
        fruits[i].y -= ny * correction * inverseMassA
        fruits[j].x += nx * correction * inverseMassB
        fruits[j].y += ny * correction * inverseMassB

        // 近づいているときだけ速度を解く（離れつつある 2 個には触らない）。
        let relativeVX = b.vx - a.vx
        let relativeVY = b.vy - a.vy
        let normalSpeed = relativeVX * nx + relativeVY * ny
        guard normalSpeed < 0 else { return }
        let normalImpulse = -(1 + Metrics.restitution) * normalSpeed / inverseMassSum
        fruits[i].vx -= nx * normalImpulse * inverseMassA
        fruits[i].vy -= ny * normalImpulse * inverseMassA
        fruits[j].vx += nx * normalImpulse * inverseMassB
        fruits[j].vy += ny * normalImpulse * inverseMassB

        // 接線方向の摩擦。転がり落ちを穏やかにして塊を落ち着かせる。
        let tx = -ny
        let ty = nx
        let tangentSpeed = relativeVX * tx + relativeVY * ty
        let tangentImpulse = -tangentSpeed * Metrics.contactFriction / inverseMassSum
        fruits[i].vx -= tx * tangentImpulse * inverseMassA
        fruits[i].vy -= ty * tangentImpulse * inverseMassA
        fruits[j].vx += tx * tangentImpulse * inverseMassB
        fruits[j].vy += ty * tangentImpulse * inverseMassB
    }

    private mutating func resolveWalls(touched: inout [Bool]) {
        let e = Metrics.restitution
        for index in fruits.indices {
            let r = fruits[index].radius
            if fruits[index].x - r < 0 {
                fruits[index].x = r
                if fruits[index].vx < 0 { fruits[index].vx = -fruits[index].vx * e }
                touched[index] = true
            } else if fruits[index].x + r > Metrics.width {
                fruits[index].x = Metrics.width - r
                if fruits[index].vx > 0 { fruits[index].vx = -fruits[index].vx * e }
                touched[index] = true
            }
            if fruits[index].y - r < 0 {
                fruits[index].y = r
                if fruits[index].vy < 0 { fruits[index].vy = -fruits[index].vy * e }
                touched[index] = true
            } else if fruits[index].y + r > Metrics.height {
                fruits[index].y = Metrics.height - r
                if fruits[index].vy > 0 { fruits[index].vy = 0 }
            }
        }
    }

    /// 同じ種類の組を 1 つ上の種類に置き換える。メロンどうしは消す。
    private mutating func applyMerges(_ merges: [(Int, Int)]) -> [FruitEvent] {
        var events: [FruitEvent] = []
        var removed = Set<Int>()
        var spawned: [Fruit] = []
        for (i, j) in merges {
            let a = fruits[i]
            let b = fruits[j]
            removed.insert(a.id)
            removed.insert(b.id)
            let x = (a.x + b.x) / 2
            let y = (a.y + b.y) / 2
            guard let next = a.kind.next else {
                events.append(.vanished(x: x, y: y))
                continue
            }
            let fruit = Fruit(
                id: nextID, kind: next,
                x: Metrics.clampedX(x, radius: next.radius),
                y: max(next.radius, y),
                vx: (a.vx + b.vx) / 2, vy: (a.vy + b.vy) / 2,
                // 積み上がった塊の中で生まれるので、触れた手応えは改めて返さない。
                hasTouched: true
            )
            nextID += 1
            spawned.append(fruit)
            events.append(.merged(from: a.kind, into: next, x: fruit.x, y: fruit.y, id: fruit.id))
        }
        fruits.removeAll { removed.contains($0.id) }
        fruits += spawned
        return events
    }

    /// 危険線の計時。`dt` は `step(dt:)` に渡された全体の時間。
    private mutating func updateOverLine(dt: Double) -> [FruitEvent] {
        var anyOver = false
        var over = false
        for index in fruits.indices {
            let fruit = fruits[index]
            if fruit.top > Metrics.deadlineY, fruit.age > Metrics.overLineGrace {
                anyOver = true
                fruits[index].overLineTime += dt
                if fruits[index].overLineTime >= Metrics.overLineLimit { over = true }
            } else {
                fruits[index].overLineTime = 0
            }
        }
        isOverLine = anyOver
        guard over else { return [] }
        isOver = true
        return [.gameOver]
    }

    #if DEBUG
    /// テスト・撮影用に果物を直接置く。製品コードからは呼ばない（`DebugOnlyPathTests` と同じ扱い）。
    public mutating func placeFruitForTesting(_ kind: FruitKind, x: Double, y: Double, vx: Double = 0, vy: Double = 0) {
        fruits.append(Fruit(id: nextID, kind: kind, x: x, y: y, vx: vx, vy: vy, age: Metrics.overLineGrace + 1, hasTouched: true))
        nextID += 1
    }
    #endif
}
