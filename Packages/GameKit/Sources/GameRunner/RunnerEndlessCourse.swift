import Foundation

/// エンドレスモードのコース生成（#675・会長決裁 2026-09-12）。
///
/// ステージ制のコースは手で書いた区画記号の文字列（`RunnerStage.patterns`）だが、ここは
/// **同じ記号を乱数で並べる**。冒頭の数区画だけ毎回同じ（ステージ 1 と同じ「間合いを覚える」
/// 導入）で、そこから先が毎回違う。
///
/// **ランダムでも詰まないことは生成時に保証する。** 置く前に、ステージ制の成立条件
/// （`RunnerStageTests` が 18 ステージについて確かめている「押さないジャンプで越えられる」
/// 「隣接障害の間に着地して踏み切り直す余白がある」「鳥の前後に跳ばざるを得ない配置が無い」
/// 「台座の前後・床の直後は素の平地」）を `canPlace` で判定し、通らない候補は平地に倒す。
/// 判定式はテストと同じ物差し（`RunnerRules` の弾道と `RunnerAutoPilot.lead`）で書いてあり、
/// テスト側は生成したコースを**独立に**同じ条件で検め直す（`RunnerEndlessCourseTests`）。
///
/// 乱数は**種を注入できる生成器**（`RandomNumberGenerator`）を引数に取る。同じ種なら同じ
/// コースになるので、テストは決定論的に再現でき、不具合報告も種 1 つで再現できる。
/// 実プレイの種は `RunnerModel` が `SystemRandomNumberGenerator` から毎回引く。
public enum RunnerEndlessCourse {
    /// 冒頭の固定区画。**ステージ 1 の出だし 4 区画**（走り出しの余白 2 つと 1 タイルの穴 1 つ）。
    ///
    /// 「最初の数区画は毎回同じ」（会長決裁）の実体。#930 まではステージ 1 のパターン全部
    /// （`--1-1--1-1--`・12 区画 ≒ 20 秒）だったが、会長 QA「何もない時間が長過ぎる」を受けて
    /// 最初の穴までに切り詰めた。ステージ 1 の出だしと同じであることは `RunnerEndlessCourseTests`
    /// が固定する——別の導入を書きたくなったらそこを直す。
    public static let intro = "--1-"
    /// 末尾の平地の区画数。ステージ制の「末尾は必ず 2 区画ぶん平地」に合わせる。
    static let trailingSegments = 2

    /// 種からコースを作る。`number` は 0（本番のステージではないことを型で示す。
    /// `RunnerStage.debugShowcase` と同じ扱い）。
    public static func makeStage(seed: UInt64) -> RunnerStage {
        RunnerStage(
            number: 0,
            pattern: pattern(seed: seed),
            speed: RunnerRules.baseSpeed,
            speedGain: speedGain,
            speedCap: RunnerRules.endlessMaxSpeed
        )
    }

    /// 種から区画記号の並びを作る。
    public static func pattern(seed: UInt64) -> String {
        var generator = RunnerSeededGenerator(seed: seed)
        return pattern(using: &generator)
    }

    // MARK: - 難易度カーブ

    /// 距離あたりの加速。ステージ制の「1 ステージごとに `speedStep`」を
    /// 「`endlessSpeedStepDistance` 進むごとに `speedStep`」へ写したもの。
    static var speedGain: Double { RunnerRules.speedStep / RunnerRules.endlessSpeedStepDistance }

    /// その距離での基準速。`RunnerRules.baseSpeed` から上がり、`RunnerRules.endlessMaxSpeed` で頭打ち。
    ///
    /// `makeStage` が作る `RunnerStage.speed(at:)` と同じ式。生成の途中（まだ `RunnerStage` が
    /// 無い時点）で成立条件を判定するために、静的関数としても持つ。
    public static func speed(atDistance distance: Double) -> Double {
        min(RunnerRules.endlessMaxSpeed, RunnerRules.baseSpeed + speedGain * max(0, distance))
    }

    /// その距離で 1 区画に障害（台座・床を含む）を置く確率。
    ///
    /// 冒頭は疎（0.3 = ステージ 1〜2 の割合）、`densityRampDistance` で 0.8（ステージ 15 の
    /// 19/26 ≒ 0.73 より少し密）まで直線で上げてそこで頭打ち。上限を 1 にしないのは、
    /// 平地がタイムに操作を反映させる余白そのものだから（`RunnerStage.patterns` の
    /// 「障害を足すときは平地を潰さない」と同じ理由。走行距離を競うモードでも、
    /// 休む区画が無いと乗りを立て直す場所が無くなる）。
    ///
    /// これは区画ごとの**抽選の確率**で、実際の密度はこれより高い——平地の連続に上限
    /// （`flatRunLimit(atDistance:)`・#930）があるので、冒頭でも 1,000 種の平均で 0.39
    /// （ステージ 4 の 6/15 と同じ水準）、終盤は 0.8 のまま。
    public static func hazardDensity(atDistance distance: Double) -> Double {
        let ratio = min(1, max(0, distance) / densityRampDistance)
        return minDensity + (maxDensity - minDensity) * ratio
    }

    static let minDensity = 0.3
    static let maxDensity = 0.8
    /// 密度が上限に達する距離（320 区画）。
    static let densityRampDistance: Double = 20_480
    /// 平地の連続の上限を 3 区画から 2 区画へ詰める距離（#930 の「中盤」）。
    static let flatRunTightenDistance: Double = 4_000

    // MARK: - 部品

    /// 生成に使う部品と、その重み・解禁距離。
    ///
    /// **解禁距離はステージ制の初出の順序に合わせてある**（穴 2 タイルは 3 面、高い障害物・犬は
    /// 4 面、次に鳥、台座と床、いちばん後ろがイノシシ）。初めて遊ぶ人が導入で一通り見てから
    /// 難しい部品に会う、という順序をランダムでも保つため。距離そのものは #930（会長 QA
    /// 「何もない時間が長過ぎる」）で前倒しした——鳥 8,192 → 4,096、台座・床 10,240 → 4,096、
    /// イノシシ 12,288 → 8,192。犬（2,048）とたこ焼き（`takoyakiUnlockDistance`）は据え置き。
    ///
    /// 3 タイルの穴（`3`）だけは距離ではなく**速さ**で解禁する。跳べる幅は `speed × jumpAirTime`
    /// で、速さ 34 の走り出しでは足りない（必要 26 に対して 25.5）。ステージ制でも 6 面（速さ 38.0。
    /// #968 までは 40）が初出で、そこでは瞬間タップ（`jumpCutGraceTime`）の飛距離 22.85（40 なら 24.04）で
    /// 越えるのに要る 22 をぎりぎり渡る。ここでは速さ 41.2（= 6,144 進んだ地点）以上に置き、タップでも
    /// 余裕を残す（`RunnerEndlessCourseTests.instantTapClearsPitsAndLowBlocks`）。
    private static let parts: [(symbol: Character, weight: Int, unlockDistance: Double)] = [
        ("1", 3, 0),
        ("n", 3, 0),
        ("2", 2, 1_024),
        ("t", 2, 2_048),
        ("d", 2, 2_048),
        ("3", 2, 6_144),
        ("b", 2, 4_096),
        (RunnerStage.platformSymbol, 1, 4_096),
        (RunnerStage.boostFloorSymbol, 1, 4_096),
        ("i", 2, 8_192),
    ]

    /// 平地の区画にスピードアップアイテムを置く割合（1/6）。
    private static let pickupOdds = 6
    /// たこ焼き（#797）を置き始める距離。**全 400 区画のちょうど半分（200 区画）**で、
    /// Issue の「エンドレスでは中盤から」の実体。いちばん後ろのイノシシ（128 区画）より後ろに
    /// してあるので、部品が出揃ってから無敵のご褒美が混ざる順序になる。
    ///
    /// この距離より手前では乱数を 1 つも余分に引かない（下の `pattern(using:)`）。
    static let takoyakiUnlockDistance: Double = 12_800
    /// 解禁後、スピードアップアイテムを置かなかった平地の区画にたこ焼きを置く割合（1/16）。
    /// 後半 200 区画の平地は 60〜70 区画ほどなので 1 本あたり 4 個前後——3 秒の無敵
    /// （最高速で約 4 区画ぶん）が後半の 1 割弱を占める程度に留める。
    private static let takoyakiOdds = 16

    // MARK: - 生成

    /// 区画記号の並びを作る。長さは常に `RunnerRules.endlessSegments`。
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
    public static func pattern<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let bodyEnd = RunnerRules.endlessSegments - trailingSegments
        var symbols = Array(intro)
        var lastHazard = RunnerStage.makeHazards(pattern: intro).last
        /// 台座・床の直後は素の平地にする（`RunnerStage.patterns` の配置規則 (1)(2)）。
        var forcePlain = false
        /// いま何区画続けて平地（障害・台座・床が無い区画）か。
        var flatRun = intro.reversed().prefix { $0 == "-" }.count

        while symbols.count < bodyEnd {
            let index = symbols.count
            let distance = Double(index) * segmentWidth
            if forcePlain {
                symbols.append("-")
                flatRun += 1
                forcePlain = false
                continue
            }
            let mustPlace = flatRun >= flatRunLimit(atDistance: distance)
            if !mustPlace {
                let roll = Double.random(in: 0..<1, using: &generator)
                if roll >= hazardDensity(atDistance: distance) {
                    // 平地。ときどきスピードアップアイテムを置く（障害ではないので条件は問わない）。
                    let pickup = Int.random(in: 0..<pickupOdds, using: &generator) == 0
                    // 中盤（`takoyakiUnlockDistance`）からは、残りの平地にときどきたこ焼き（#797）を置く。
                    let takoyaki = !pickup && distance >= takoyakiUnlockDistance
                        && Int.random(in: 0..<takoyakiOdds, using: &generator) == 0
                    symbols.append(pickup ? RunnerStage.pickupSymbol : takoyaki ? RunnerStage.takoyakiSymbol : "-")
                    flatRun += 1
                    continue
                }
            }

            /// `symbol` をこの区画に置けるなら置いて true。台座・床は連続で 1 基置く。
            func place(_ symbol: Character) -> Bool {
                switch symbol {
                case RunnerStage.platformSymbol, RunnerStage.boostFloorSymbol:
                    // 台座は 2〜3 区画、床は 1〜2 区画の連続で 1 基。台座の手前は素の平地でないと
                    // 助走が無い（配置規則 (1)）。床の手前も同じ平地を要求しておく——手前が
                    // 障害だと、跳んだ着地が床に入って基準速の踏み切り計算からずれる。
                    let run = symbol == RunnerStage.platformSymbol
                        ? Int.random(in: 2...3, using: &generator)
                        : Int.random(in: 1...2, using: &generator)
                    guard symbols.last == "-", index + run < bodyEnd,
                          symbol != RunnerStage.platformSymbol
                            || canPlacePlatform(at: distance, after: lastHazard, speed: speed(atDistance: distance))
                    else { return false }
                    symbols += Array(repeating: symbol, count: run)
                    forcePlain = true
                    return true
                default:
                    guard let spec = RunnerStage.segmentSpec(symbol) else { return false }
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
                    let before = speed(atDistance: distance)
                    let after = speed(atDistance: candidate.end + segmentWidth * 2)
                    guard canPlace(candidate, after: lastHazard, speedBefore: before, speedAfter: after) else {
                        return false
                    }
                    symbols.append(symbol)
                    // イノシシの次の区画に岩を置くと、イノシシは岩の右側で止まって岩と一続きになる
                    // （#801・`RunnerStage.boarStop`）。次の障害との間隔は**止まったイノシシの右端**から
                    // 測らないと、岩から測った 64 のうち 4 が埋まっているぶん足りなくなる。
                    if let boar = lastHazard, boar.kind == .boar, candidate.kind.isRock,
                       candidate.end <= boar.boarSpawn {
                        lastHazard = RunnerHazard(kind: .boar, start: boar.start, length: boar.length, stopAt: candidate.end)
                    } else {
                        lastHazard = candidate
                    }
                    return true
                }
            }

            var placed = false
            for _ in 0...redrawLimit where !placed {
                placed = place(pick(atDistance: distance, using: &generator))
            }
            if !placed, mustPlace {
                placed = place("1")
            }
            if placed {
                flatRun = 0
            } else {
                symbols.append("-")
                flatRun += 1
            }
        }
        symbols += Array(repeating: "-", count: RunnerRules.endlessSegments - symbols.count)
        return String(symbols)
    }

    /// 置けない候補を引き直す回数の上限（最初の 1 回に加えて）。
    ///
    /// 3 回あれば、部品が全部解禁された地点でも「必ず置ける `1`・`n`」（重み 6/20）を 4 回とも
    /// 引き損ねる確率は 1/4 ほどで、密度の抽選どおりに障害が置かれる。上限があるのは、
    /// 置ける部品が無い地点で乱数を無限に消費しないため。
    static let redrawLimit = 3

    /// その距離で許す平地の連続の上限（区画数）。序盤は 3、`flatRunTightenDistance` 以降は 2。
    ///
    /// 会長 QA「エンドレスモードの何もない時間が長過ぎる」（#930）の実体。#930 以前は密度 0.3 の
    /// 独立な抽選だけで決めていたので、序盤に平地が 8 区画（約 15 秒）続く種が珍しくなかった。
    static func flatRunLimit(atDistance distance: Double) -> Int {
        distance >= flatRunTightenDistance ? 2 : 3
    }

    /// 解禁済みの部品から重みで 1 つ選ぶ。
    private static func pick<G: RandomNumberGenerator>(
        atDistance distance: Double, using generator: inout G
    ) -> Character {
        let unlocked = parts.filter { $0.unlockDistance <= distance }
        let total = unlocked.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0..<total, using: &generator)
        for part in unlocked {
            roll -= part.weight
            if roll < 0 { return part.symbol }
        }
        return unlocked[unlocked.count - 1].symbol
    }

    // MARK: - 成立条件

    /// `hazard` を `previous` の次に置いてよいか。
    ///
    /// `RunnerStageTests` の `everyHazardIsClearable` / `hazardsAreFarEnoughApart` と同じ式で、
    /// 動く障害（#796〜#801）は**走者から見て等価な静止区間**（`RunnerHazard.encounter`）で見る。
    /// 速さは 2 つ受け取る——越えられるかは遅いほど厳しく、間隔は速いほど厳しいので、
    /// それぞれ厳しい側で判定する。
    ///
    /// イノシシの次の区画に岩を置くと、イノシシはその岩の右側で止まって**岩と一続きの障害**になる
    /// （`RunnerStage.boarStop`）。その場合は間隔ではなく「岩の高さを保ったまま岩＋イノシシを
    /// 越えきれるか」で判定する（`isClearableWithBoarBehind`）。
    static func canPlace(
        _ hazard: RunnerHazard, after previous: RunnerHazard?,
        speedBefore: Double, speedAfter: Double
    ) -> Bool {
        guard isClearable(hazard, speed: speedBefore) else { return false }
        guard let previous else { return true }
        if let previous = previous.kind == .boar ? previous : nil,
           hazard.kind.isRock, hazard.end <= previous.boarSpawn {
            return isClearableWithBoarBehind(hazard, speed: speedBefore)
        }
        return hasLandingGap(from: previous, to: hazard, speed: speedAfter)
    }

    /// 岩の右側で止まったイノシシ（#801）ごと、1 回のジャンプで越えられるか。
    ///
    /// 岩の上端を越える高さのまま、岩＋イノシシ（1 タイル）＋走者の幅を通り抜けられれば
    /// 確実に越えられる（イノシシは岩より低いので、これは十分条件）。
    static func isClearableWithBoarBehind(_ rock: RunnerHazard, speed: Double) -> Bool {
        let window = RunnerRules.airTime(above: rock.height + RunnerAutoPilot.clearance)
        let overlap = (rock.length + RunnerRules.tileWidth + RunnerField.Metrics.playerWidth) / speed
        return window > overlap
    }

    /// 左端が `start` の台座を `previous` の次に置いてよいか。
    ///
    /// 手前を素の平地にする規則だけでも実際には常に足りる（区画 1 つ = 64 に対して要る余白は
    /// 十数単位）が、暗黙の余裕に寄りかからず、障害と同じ形で明示的に判定する:
    /// 前の障害（動く障害は等価な静止区間）を跳んだ着地が台座への踏み切り位置より手前で終わること。
    static func canPlacePlatform(at start: Double, after previous: RunnerHazard?, speed: Double) -> Bool {
        guard let previous else { return true }
        let rise = RunnerRules.riseTime(to: RunnerRules.platformHeight + RunnerAutoPilot.clearance)
        let takeOff = start - RunnerAutoPilot.baseLead - speed * rise
        let landing = previous.encounter.start
            - RunnerAutoPilot.lead(for: previous, speed: speed)
            + speed * RunnerRules.jumpAirTime
        return landing < takeOff
    }

    /// 押さない（最小の）ジャンプで越えられるか。動く障害は等価な静止区間（`encounter`）で見る。
    static func isClearable(_ hazard: RunnerHazard, speed: Double) -> Bool {
        let encounter = hazard.encounter
        switch hazard.kind {
        case .pit:
            let range = speed * RunnerRules.jumpAirTime
            let needed = RunnerAutoPilot.lead(for: hazard, speed: speed) + hazard.length
            return range > needed + RunnerRules.tileWidth
        case .lowBlock, .tallBlock, .bird, .dog, .boar:
            let window = RunnerRules.airTime(above: encounter.height + RunnerAutoPilot.clearance)
            let overlap = (encounter.length + RunnerField.Metrics.playerWidth) / speed
            return window > overlap && encounter.height < RunnerRules.jumpApex
        }
    }

    /// 前の障害を跳んで着地してから、次の踏み切りに入れるだけの間隔があるか。
    /// 動く障害は等価な静止区間（`encounter`）で見る。
    static func hasLandingGap(from previous: RunnerHazard, to next: RunnerHazard, speed: Double) -> Bool {
        let needed = speed * RunnerRules.jumpAirTime + RunnerAutoPilot.lead(for: next, speed: speed)
        return next.encounter.start - previous.encounter.start > needed
    }
}

/// 種から決定論的に乱数を出す生成器（SplitMix64）。
///
/// `SystemRandomNumberGenerator` は種を持てないので、コースの再現に使えない。
/// 64 ビットの種 1 つで同じ並びが出ることだけが要件で、暗号学的な強さは要らない。
struct RunnerSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
