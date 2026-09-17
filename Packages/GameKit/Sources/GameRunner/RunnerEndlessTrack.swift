import Foundation

/// エンドレスのコースの 1 区画（#1086）。
///
/// ステージ制の `RunnerStage` が区画記号の文字列を一括で `hazards` / `pickups` / `platforms` /
/// `boostFloors` の配列へ展開するのに対し、エンドレスは**区画ごとに**同じ中身を持つ。座標の
/// 作り方（区画の中央に障害・アイテム、台座・床は区画まるごと）は `RunnerStage` の展開と同じ式。
///
/// `index` は**区画の通し番号**（コース先頭が 0）で、枠（`RunnerEndlessTrack`）のどこに
/// 入っているかとは無関係。取ったアイテムもこの番号で覚える（`RunnerField.collectedPickupIndices`）。
public struct RunnerEndlessSegment: Equatable, Sendable {
    /// 1 区画の長さ（ワールド単位）。
    public static let width = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth

    /// 区画の通し番号。
    public let index: Int
    /// 区画記号（`RunnerStage` の表と同じ）。
    public let symbol: Character
    /// この区画の障害（区画に高々 1 つ）。イノシシの止まる岩（`stopAt`）は次の区画で決まるので、
    /// 生成器が次の区画を作ってから書き足す（`RunnerEndlessGenerator.next()`）。
    public internal(set) var hazard: RunnerHazard?
    /// この区画のアイテム（スピードアップ・たこ焼き）。
    public let pickup: RunnerPickup?
    /// 台座。**連続する `P` の先頭の区画にだけ**、連続ぶんの長さの 1 基を持つ（`RunnerStage.makePlatforms`
    /// と同じく、隣り合う区画を別の台座にしない）。続きの区画は `symbol` が `P` で `platform` は nil。
    public let platform: RunnerPlatform?
    /// スピードアップ床。台座と同じく連続の先頭の区画にだけ持つ。
    public let boostFloor: RunnerBoostFloor?

    /// 区画の左端の x。
    public var start: Double { Double(index) * Self.width }
    /// 区画の右端の x。
    public var end: Double { start + Self.width }

    /// - Parameter runLength: 台座・床の連続の長さ（区画数）。**先頭の区画だけ 1 以上**、
    ///   続きの区画は 0。台座・床以外では使わない。
    init(index: Int, symbol: Character, runLength: Int) {
        self.index = index
        self.symbol = symbol
        let start = Double(index) * Self.width
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        hazard = RunnerStage.segmentSpec(symbol).map {
            RunnerHazard(kind: $0.kind, start: start + offset, length: Double($0.tiles) * RunnerRules.tileWidth)
        }
        switch symbol {
        case RunnerStage.pickupSymbol:   pickup = RunnerPickup(kind: .speed, start: start + offset)
        case RunnerStage.takoyakiSymbol: pickup = RunnerPickup(kind: .invincible, start: start + offset)
        default:                         pickup = nil
        }
        let runWidth = Double(runLength) * Self.width
        platform = symbol == RunnerStage.platformSymbol && runLength > 0
            ? RunnerPlatform(start: start, length: runWidth) : nil
        boostFloor = symbol == RunnerStage.boostFloorSymbol && runLength > 0
            ? RunnerBoostFloor(start: start, length: runWidth) : nil
    }
}

/// エンドレスのコースを先頭から 1 区画ずつ作る生成器（#1086）。
///
/// #675 の `RunnerEndlessCourse.pattern(using:)` が 1 本のループの中で持ち回していた状態
/// （直前の障害 `lastHazard`・平地の連続数 `flatRun`・`forcePlain`・乱数）を**そのまま値として
/// 持ち越す**。区画を枠（`RunnerEndlessTrack`）から捨てても生成器の状態は捨てないので、
/// 枠の継ぎ目でも成立条件の判定（`RunnerEndlessCourse.canPlace` / `canPlacePlatform`）は
/// 途切れずに効く。
///
/// 区画 N の中身は**種と N だけで決まる**（いつ作ったか・枠がいくつあるかに依らない）。
/// 判定式・部品の解禁距離・速さと密度の上がり方は #675 / #930 のまま変えていないので、
/// 先頭の並びは一括生成だった頃と 1 文字も変わらない（`RunnerEndlessCourseTests` が固定する）。
struct RunnerEndlessGenerator: Sendable {
    let seed: UInt64
    private var random: RunnerSeededGenerator
    /// 次に中身を決める区画の通し番号。
    private var nextIndex = 0
    /// 直前に決めた区画の記号。台座・床の手前が素の平地かを見る。
    private var lastSymbol: Character = "-"
    /// 直前に置いた障害（動く障害は `encounter` で見る。止まったイノシシは `stopAt` 付き）。
    private var lastHazard: RunnerHazard?
    /// 台座・床の直後は素の平地にする（`RunnerStage.patterns` の配置規則 (1)(2)）。
    private var forcePlain = false
    /// いま何区画続けて平地（障害・台座・床が無い区画）か。
    private var flatRun: Int
    /// 台座・床の連続のうち、まだ出していない区画の数と記号。
    private var runRemaining = 0
    private var runSymbol: Character = "-"
    /// 1 つ先に作ってある区画（イノシシの止まる岩が次の区画で決まるため・`next()`）。
    private var pending: RunnerEndlessSegment?

    init(seed: UInt64) {
        self.seed = seed
        random = RunnerSeededGenerator(seed: seed)
        lastHazard = RunnerStage.makeHazards(pattern: RunnerEndlessCourse.intro).last
        flatRun = RunnerEndlessCourse.intro.reversed().prefix { $0 == "-" }.count
    }

    /// 次に `next()` が返す区画の通し番号。
    var nextSegmentIndex: Int { pending?.index ?? nextIndex }

    /// 次の区画を返す。
    ///
    /// イノシシ（#801）の次の区画に岩があると、イノシシはその岩の右側で止まる（`RunnerStage.boarStop`）。
    /// 止まる岩になりうるのは次の区画の岩だけ（出現点 `start + 72` までに右端が来るのは 64 先の岩の
    /// `+ 68` だけで、2 区画先の岩は `+ 132`）なので、**1 区画ぶん先に作っておいて**返す前に書き足す。
    /// こうしておけば、枠に入った区画の中身は後から変わらない。
    mutating func next() -> RunnerEndlessSegment {
        var current = pending ?? makeSegment()
        let following = makeSegment()
        if let boar = current.hazard, boar.kind == .boar,
           let rock = following.hazard, rock.kind.isRock,
           rock.end > boar.start, rock.end <= boar.boarSpawn {
            current.hazard = RunnerHazard(kind: .boar, start: boar.start, length: boar.length, stopAt: rock.end)
        }
        pending = following
        return current
    }

    private mutating func makeSegment() -> RunnerEndlessSegment {
        let index = nextIndex
        nextIndex += 1
        let symbol: Character
        let runLength: Int
        if index < RunnerEndlessCourse.introSymbols.count {
            symbol = RunnerEndlessCourse.introSymbols[index]
            runLength = 1
        } else if runRemaining > 0 {
            symbol = runSymbol
            runRemaining -= 1
            runLength = 0
        } else {
            (symbol, runLength) = decide(at: index)
            if runLength > 1 {
                runSymbol = symbol
                runRemaining = runLength - 1
            }
        }
        lastSymbol = symbol
        return RunnerEndlessSegment(index: index, symbol: symbol, runLength: runLength)
    }

    /// 区画 `index` に何を置くかを決める。台座・床は連続の長さも返す（続きの区画は `makeSegment` が出す）。
    ///
    /// 区画ごとに「障害を置くか」を密度で決め、置くなら解禁済みの部品から重みで 1 つ選ぶ。
    /// 成立条件（`canPlace`）を満たさない候補は **`redrawLimit` 回まで引き直し**、それでも
    /// 置けなければ平地に倒す（#930。以前は引き直さず即座に平地に倒していたため、条件が厳しい
    /// 並び——障害の直後の台座・床、鳥の直後の高い岩——ほど平地に化けて「何もない時間」が伸びた）。
    ///
    /// **平地（障害も台座も床も無い区画）の連続には上限がある**（`flatRunLimit(atDistance:)`）。
    /// 上限に達した区画は密度の抽選を飛ばして必ず障害を置きにいき、引き直しも尽きたら
    /// 最小の穴（`1`）を試す——隣り合う区画にどの障害が並んでも置ける部品
    /// （`RunnerEndlessCourseTests.maxSpeedKeepsAdjacentHazardsPassable`）。
    private mutating func decide(at index: Int) -> (symbol: Character, runLength: Int) {
        typealias Course = RunnerEndlessCourse
        let distance = Double(index) * RunnerEndlessSegment.width
        if forcePlain {
            forcePlain = false
            flatRun += 1
            return ("-", 1)
        }
        let mustPlace = flatRun >= Course.flatRunLimit(atDistance: distance)
        if !mustPlace {
            let roll = Double.random(in: 0..<1, using: &random)
            if roll >= Course.hazardDensity(atDistance: distance) {
                // 平地。ときどきスピードアップアイテムを置く（障害ではないので条件は問わない）。
                let pickup = Int.random(in: 0..<Course.pickupOdds, using: &random) == 0
                // 中盤（`takoyakiUnlockDistance`）からは、残りの平地にときどきたこ焼き（#797）を置く。
                let takoyaki = !pickup && distance >= Course.takoyakiUnlockDistance
                    && Int.random(in: 0..<Course.takoyakiOdds, using: &random) == 0
                flatRun += 1
                return (pickup ? RunnerStage.pickupSymbol : takoyaki ? RunnerStage.takoyakiSymbol : "-", 1)
            }
        }
        for _ in 0...Course.redrawLimit {
            if let placed = place(Course.pick(atDistance: distance, using: &random), at: distance) {
                flatRun = 0
                return placed
            }
        }
        if mustPlace, let placed = place("1", at: distance) {
            flatRun = 0
            return placed
        }
        flatRun += 1
        return ("-", 1)
    }

    /// `symbol` を左端 `distance` の区画に置けるなら、置く記号と連続の長さを返す。台座・床は連続で 1 基置く。
    private mutating func place(_ symbol: Character, at distance: Double) -> (symbol: Character, runLength: Int)? {
        typealias Course = RunnerEndlessCourse
        switch symbol {
        case RunnerStage.platformSymbol, RunnerStage.boostFloorSymbol:
            // 台座は 2〜3 区画、床は 1〜2 区画の連続で 1 基。台座の手前は素の平地でないと
            // 助走が無い（配置規則 (1)）。床の手前も同じ平地を要求しておく——手前が
            // 障害だと、跳んだ着地が床に入って基準速の踏み切り計算からずれる。
            // 長さの乱数は置けるかの判定より先に引く（#675 の一括生成と同じ引き方）。
            let run = symbol == RunnerStage.platformSymbol
                ? Int.random(in: 2...3, using: &random)
                : Int.random(in: 1...2, using: &random)
            guard lastSymbol == "-",
                  symbol != RunnerStage.platformSymbol
                    || Course.canPlacePlatform(at: distance, after: lastHazard, speed: Course.speed(atDistance: distance))
            else { return nil }
            forcePlain = true
            return (symbol, run)
        default:
            guard let spec = RunnerStage.segmentSpec(symbol) else { return nil }
            let candidate = RunnerHazard(
                kind: spec.kind,
                start: distance + Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth,
                length: Double(spec.tiles) * RunnerRules.tileWidth
            )
            // 越えられるかは区画の手前の（遅い）速さで、間隔は先の（速い）速さで判定する
            // （`RunnerStage.speed(at:)` のドキュメント参照）。先の速さは**障害の右端から
            // 2 区画先**で取る——`RunnerEndlessCourseTests` が検め直すのと同じ地点。区画の
            // 左端から 2 区画先で取ると 0.05 ほど遅い速さで判定することになり、飛び立つ鳥
            // （#796）の直後の高い岩のように余白が 0.01 単位まで削れる並びで、生成は通るのに
            // 検算で落ちる。
            let before = Course.speed(atDistance: distance)
            let after = Course.speed(atDistance: candidate.end + RunnerEndlessSegment.width * 2)
            guard Course.canPlace(candidate, after: lastHazard, speedBefore: before, speedAfter: after) else {
                return nil
            }
            // イノシシの次の区画に岩を置くと、イノシシは岩の右側で止まって岩と一続きになる
            // （#801・`RunnerStage.boarStop`）。次の障害との間隔は**止まったイノシシの右端**から
            // 測らないと、岩から測った 64 のうち 4 が埋まっているぶん足りなくなる。
            if let boar = lastHazard, boar.kind == .boar, candidate.kind.isRock,
               candidate.end <= boar.boarSpawn {
                lastHazard = RunnerHazard(kind: .boar, start: boar.start, length: boar.length, stopAt: candidate.end)
            } else {
                lastHazard = candidate
            }
            return (symbol, 1)
        }
    }
}

extension RunnerEndlessGenerator: Equatable {
    /// 生成器の状態は**種と、そこまでに作った区画の数**だけで決まる（乱数 `SplitMix64` は比較できない
    /// 型なので、同じ種から同じ数だけ進めた＝同じ状態、として比べる）。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.seed == rhs.seed && lhs.nextIndex == rhs.nextIndex && lhs.pending == rhs.pending
    }
}

/// エンドレスのコースのうち、いま走者のまわりにある区画だけを持つ枠（#1086）。
///
/// **決まった数の枠（`capacity`）を使い回すリングバッファ**。走り出す前に枠を確保し、走行中は
/// 古い区画を捨てた枠に新しい区画を書き込むだけなので、区画データの確保・解放も配列の
/// 再確保も起きない（`RunnerEndlessCourseTests` が配列の先頭番地で固定する）。
///
/// 枠の中の位置（`subscript(position:)`）と区画の通し番号（`RunnerEndlessSegment.index`）は別物。
/// 区画は通し番号の昇順に並び、`firstIndex..<endIndex` が連続して入っている。
public struct RunnerEndlessTrack: Equatable, Sendable {
    /// 枠の数。
    ///
    /// 同時に持つ区画は最大 7 つ——走者のいる区画、その後ろ `retainedSegmentsBehind`（3）、
    /// 前に `aheadDistance`（160）を覆うぶん（最大 3。区画の途中 `f` にいるとき `⌈(f + 160) / 64⌉ ≤ 4` 区画目まで）。
    /// 1 つ余らせて 8。足りなくなると `advance(to:)` が古い区画から押し出す（テストで起きないことを固定）。
    public static let defaultCapacity = 8
    /// 走者のいる区画より後ろに残す区画の数。
    ///
    /// 後ろの区画を見るのは 3 か所: 走者がまだ上にいる台座（最長 3 区画なので 2 区画前に始まりうる）、
    /// ジャスト着地（#673）の「この滞空で越えた障害」（二段ジャンプでも滞空は 1.5 秒・最高速で 90 ≒ 1.4 区画）、
    /// 画面の左端（走者の 26 後ろ）までの地面と、すれ違った動物・鳥の絵。いちばん遠いのは台座の 2 区画で、
    /// 1 つ足して 3。
    public static let retainedSegmentsBehind = 3
    /// 走者の前に、生成済みの区画で覆っておく距離（ワールド単位）。
    ///
    /// 画面に見える先読みは 74（`RunnerField.Metrics.width − playerX`）。それより先で関わる相手が
    /// 2 つある: 犬は区画の中央の 60 手前で画面の右の外に現れ（`dogApproachDistance` + 半身）、
    /// イノシシは 76 手前で突進を始める（`boarChargeDistance` + 半身。この瞬間に止まる岩も要る）。
    /// イノシシの区画の中央が 76 先にあるとき、その区画の右端は 76 − 24 + 64 = 116 先。
    /// それに半区画弱の余裕を足して 160（2.5 区画）。**生成は `RunnerField` の 1 サブステップ
    /// （最大 2）ごとに追いつかせる**ので、どれだけ速くてもこの距離を割らない。
    public static let aheadDistance: Double = 160

    public let capacity: Int
    let aheadDistance: Double
    private var generator: RunnerEndlessGenerator
    /// 枠。長さは常に `capacity`（使っていない枠には捨てた区画が残っているだけ）。
    private var slots: [RunnerEndlessSegment]
    /// いちばん古い区画が入っている枠。
    private var head = 0
    /// いま持っている区画の数。
    public private(set) var count = 0
    /// いちばん古い区画の通し番号。区画を持っていないときは次に作る区画の通し番号。
    public private(set) var firstIndex = 0

    /// 種からコースを作り、走り出す地点（距離 0）のまわりの区画を用意する。
    public init(seed: UInt64) {
        self.init(seed: seed, capacity: Self.defaultCapacity, aheadDistance: Self.aheadDistance)
    }

    /// 枠の数・先読みの距離を変えて作る（テストで「枠の数に中身が左右されない」ことを確かめる用）。
    init(seed: UInt64, capacity: Int, aheadDistance: Double) {
        self.capacity = capacity
        self.aheadDistance = aheadDistance
        generator = RunnerEndlessGenerator(seed: seed)
        slots = Array(repeating: RunnerEndlessSegment(index: -1, symbol: "-", runLength: 0), count: capacity)
        advance(to: 0)
    }

    /// コースの種。
    public var seed: UInt64 { generator.seed }
    /// いま持っている区画の次の通し番号（ここから先はまだ作っていない）。
    public var endIndex: Int { firstIndex + count }
    /// 生成済みの区画の右端の x。ここより先はまだ作っていない（走者が入っても地面として扱う）。
    public var generatedEnd: Double { Double(endIndex) * RunnerEndlessSegment.width }

    /// 枠の中の `position` 番目（0 がいちばん古い）の区画。
    public subscript(position: Int) -> RunnerEndlessSegment {
        precondition(position >= 0 && position < count, "枠の外（\(position) / \(count)）")
        return slots[(head + position) % capacity]
    }

    /// 通し番号 `index` の区画。枠から捨てた区画・まだ作っていない区画は nil。
    public func segment(withIndex index: Int) -> RunnerEndlessSegment? {
        guard index >= firstIndex, index < endIndex else { return nil }
        return self[index - firstIndex]
    }

    /// 走者が `distance` に来たときの枠にする。後ろの区画を捨て、前の区画を `aheadDistance` ぶん作る。
    ///
    /// 距離が一気に進んだ場合（テスト・撮影で遠くへ置いたとき）も、生成器は区画を**先頭から順に**
    /// 作る——区画の中身が種と通し番号だけで決まることを保つため。途中の区画は作ったそばから捨てる。
    mutating func advance(to distance: Double) {
        let keepFrom = Int((distance / RunnerEndlessSegment.width).rounded(.down)) - Self.retainedSegmentsBehind
        evict(before: keepFrom)
        while generatedEnd < distance + aheadDistance {
            if count == capacity {
                // 枠の数が足りない設定（`defaultCapacity` の根拠を参照）。落とさず古い区画から押し出す。
                assertionFailure("エンドレスの枠（\(capacity)）が足りない")
                evict(before: firstIndex + 1)
            }
            slots[(head + count) % capacity] = generator.next()
            count += 1
            evict(before: keepFrom)
        }
    }

    private mutating func evict(before index: Int) {
        while count > 0, firstIndex < index {
            head = (head + 1) % capacity
            firstIndex += 1
            count -= 1
        }
        if count == 0 { firstIndex = generator.nextSegmentIndex }
    }

    /// 通し番号 `index` の区画が入っている枠の番号（テスト用。継ぎ目をまたいだかを数える）。
    func slot(ofSegmentIndex index: Int) -> Int? {
        guard index >= firstIndex, index < endIndex else { return nil }
        return (head + index - firstIndex) % capacity
    }

    /// 枠の配列の先頭番地（テスト用）。走行中に変わらなければ、配列は再確保されていない。
    var storageAddress: UnsafeRawPointer? {
        slots.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }
}
