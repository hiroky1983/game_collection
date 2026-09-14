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
    /// 冒頭の固定区画。**ステージ 1 のパターンそのもの**（1 タイルの穴 3 つで間合いを覚える）。
    ///
    /// 「最初の数区画は毎回同じ」（会長決裁）の実体。ステージ 1 と同じ文字列であることは
    /// `RunnerEndlessCourseTests` が固定する——別の導入を書きたくなったらそこを直す。
    public static let intro = "--1-1--1-1--"
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
    public static func hazardDensity(atDistance distance: Double) -> Double {
        let ratio = min(1, max(0, distance) / densityRampDistance)
        return minDensity + (maxDensity - minDensity) * ratio
    }

    static let minDensity = 0.3
    static let maxDensity = 0.8
    /// 密度が上限に達する距離（320 区画）。
    static let densityRampDistance: Double = 20_480

    // MARK: - 部品

    /// 生成に使う部品と、その重み・解禁距離。
    ///
    /// **解禁距離はステージ制の初出に合わせてある**（穴 2 タイルは 3 面、高い障害物・犬は 4 面、
    /// 鳥は 5 面だが「中盤」の決裁（#796）で 8 区画ぶん後ろ、イノシシは「後半」（#801）で
    /// 台座・床より後、台座と床は 16 面）。初めて遊ぶ人が導入で一通り見てから難しい部品に会う、
    /// という順序をランダムでも保つため。
    ///
    /// 3 タイルの穴（`3`）だけは距離ではなく**速さ**で解禁する。跳べる幅は `speed × jumpAirTime`
    /// で、速さ 34 の走り出しでは足りない（必要 26 に対して 25.5）。ステージ制でも 6 面
    /// （速さ 40）が初出で、そこでは瞬間タップ（`jumpCutGraceTime`）の飛距離 24.04 で
    /// 幅 24 をぎりぎり渡る。ここでは速さ 41.2（= 6,144 進んだ地点）以上に置き、タップでも
    /// 余裕を残す（`RunnerEndlessCourseTests.instantTapClearsPitsAndLowBlocks`）。
    private static let parts: [(symbol: Character, weight: Int, unlockDistance: Double)] = [
        ("1", 3, 0),
        ("n", 3, 0),
        ("2", 2, 1_024),
        ("t", 2, 2_048),
        ("d", 2, 2_048),
        ("3", 2, 6_144),
        ("b", 2, 8_192),
        (RunnerStage.platformSymbol, 1, 10_240),
        (RunnerStage.boostFloorSymbol, 1, 10_240),
        ("i", 2, 12_288),
    ]

    /// 平地の区画にスピードアップアイテムを置く割合（1/6）。
    private static let pickupOdds = 6
    /// たこ焼き（#797）を置き始める距離。**全 400 区画のちょうど半分（200 区画）**で、
    /// Issue の「エンドレスでは中盤から」の実体。台座・床（160 区画）より後ろにしてあるので、
    /// 部品が出揃ってから無敵のご褒美が混ざる順序になる。
    ///
    /// この距離より手前では乱数を 1 つも余分に引かない（下の `pattern(using:)`）ので、
    /// 同じ種の前半のコースは #797 より前とまったく同じ並びのまま。
    static let takoyakiUnlockDistance: Double = 12_800
    /// 解禁後、スピードアップアイテムを置かなかった平地の区画にたこ焼きを置く割合（1/16）。
    /// 後半 200 区画の平地は 60〜70 区画ほどなので 1 本あたり 4 個前後——3 秒の無敵
    /// （最高速で約 4 区画ぶん）が後半の 1 割弱を占める程度に留める。
    private static let takoyakiOdds = 16

    // MARK: - 生成

    /// 区画記号の並びを作る。長さは常に `RunnerRules.endlessSegments`。
    ///
    /// 区画ごとに「障害を置くか」を密度で決め、置くなら解禁済みの部品から重みで 1 つ選ぶ。
    /// 成立条件（`canPlace`）を満たさない候補は**引き直さず平地に倒す**——引き直すと
    /// 条件が厳しい地点ほど乱数を多く消費して密度の意味が変わるうえ、詰みの原因が
    /// 「置けなかった」ではなく「たまたま置けた候補」に隠れて読みにくくなる。
    public static func pattern<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let bodyEnd = RunnerRules.endlessSegments - trailingSegments
        var symbols = Array(intro)
        var lastHazard = RunnerStage.makeHazards(pattern: intro).last
        /// 台座・床の直後は素の平地にする（`RunnerStage.patterns` の配置規則 (1)(2)）。
        var forcePlain = false

        while symbols.count < bodyEnd {
            let index = symbols.count
            let distance = Double(index) * segmentWidth
            if forcePlain {
                symbols.append("-")
                forcePlain = false
                continue
            }
            let roll = Double.random(in: 0..<1, using: &generator)
            guard roll < hazardDensity(atDistance: distance) else {
                // 平地。ときどきスピードアップアイテムを置く（障害ではないので条件は問わない）。
                let pickup = Int.random(in: 0..<pickupOdds, using: &generator) == 0
                if pickup {
                    symbols.append(RunnerStage.pickupSymbol)
                    continue
                }
                // 中盤（`takoyakiUnlockDistance`）からは、残りの平地にときどきたこ焼き（#797）を置く。
                // 解禁前は乱数を引かない（手前のコースの並びを変えないため）。
                let takoyaki = distance >= takoyakiUnlockDistance
                    && Int.random(in: 0..<takoyakiOdds, using: &generator) == 0
                symbols.append(takoyaki ? RunnerStage.takoyakiSymbol : "-")
                continue
            }
            let symbol = pick(atDistance: distance, using: &generator)
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
                else {
                    symbols.append("-")
                    continue
                }
                symbols += Array(repeating: symbol, count: run)
                forcePlain = true
            default:
                guard let spec = RunnerStage.segmentSpec(symbol) else {
                    symbols.append("-")
                    continue
                }
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
                if canPlace(candidate, after: lastHazard, speedBefore: before, speedAfter: after) {
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
                } else {
                    symbols.append("-")
                }
            }
        }
        symbols += Array(repeating: "-", count: RunnerRules.endlessSegments - symbols.count)
        return String(symbols)
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
