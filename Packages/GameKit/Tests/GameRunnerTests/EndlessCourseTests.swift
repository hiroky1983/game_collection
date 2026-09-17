import Core
import Foundation
import Testing
@testable import GameRunner
import CoreTestSupport

/// エンドレスモードのコース生成（#675 → #1086 で終わりの無いコースに）。
///
/// 生成器は置く前に成立条件を判定する（`RunnerEndlessCourse.canPlace`）が、ここでは
/// **生成したコースを独立に検め直す**。判定式はステージ制の `RunnerStageTests` と同じ物差し
/// （弾道は `RunnerRules`、踏み切りは `RunnerAutoPilot.lead`）で書き、生成器より厳しい速さの
/// 幅（区画 1 つ手前の遅い速さ／2 区画先の速い速さ）で見る。
///
/// 検算するコースは**枠（`RunnerEndlessTrack`）を通して集めたもの**で、区画を捨てて枠を回した
/// 継ぎ目をまたぐ並びも含む（`EndlessCourseSample`）。
@Suite("チャリンコおじさん: エンドレスのコース生成")
struct RunnerEndlessCourseTests {
    private static let segmentWidth = RunnerEndlessSegment.width
    /// 受け入れ条件「1,000 種 × 70,000 単位以上」の種の数。
    private static let seedCount: UInt64 = 1_000
    /// 検算する区画の数。1,100 区画 = 70,400 単位で、速さの上限（約 22,187）・密度の上限（20,480）・
    /// 最後の部品（イノシシ 8,192・たこ焼き 12,800）の解禁のどれよりも 3 倍以上先まで見る。
    /// その先は生成の条件が変わらないので、ここで詰まなければどこまで走っても同じ（#1086 の設計）。
    static let verifiedSegments = 1_100
    /// 密度・解禁距離などの分布を見る窓（先頭 400 区画 = 25,600 単位。速さも密度も上限に届く距離）。
    private static let analysisSegments = 400

    @Test("同じ種なら同じコース、違う種なら違うコース")
    func sameSeedSameCourse() {
        #expect(RunnerEndlessCourse.pattern(seed: 42, count: 500) == RunnerEndlessCourse.pattern(seed: 42, count: 500))
        let patterns = Set((1...20).map { RunnerEndlessCourse.pattern(seed: UInt64($0), count: 400) })
        #expect(patterns.count == 20, "種が違えばコースも違う（冒頭だけ同じ）")
        // 長さを変えて作っても、先頭の並びは同じ（区画 N の中身は種と N だけで決まる）。
        #expect(RunnerEndlessCourse.pattern(seed: 42, count: 1_000).hasPrefix(RunnerEndlessCourse.pattern(seed: 42, count: 300)))
    }

    /// 「最初の数区画は毎回同じ」（会長決裁）。導入はステージ 1 の出だし（最初の穴まで）と
    /// 同じ並びで、別の導入を書きたくなったらここを直す。
    @Test("冒頭はステージ 1 の出だしと同じ固定パターンで、以降がランダム")
    func introIsFixedAndMatchesStageOne() {
        #expect(RunnerStage.all[0].pattern.hasPrefix(RunnerEndlessCourse.intro))
        for seed in 1...Self.seedCount {
            let pattern = RunnerEndlessCourse.pattern(seed: seed, count: 8)
            #expect(pattern.hasPrefix(RunnerEndlessCourse.intro), "種 \(seed) の冒頭が固定パターンでない")
        }
    }

    /// 走りながら作る生成器（#1086）が、#675 / #930 の一括生成と**同じ並び**を出すこと。
    /// 判定式・部品の解禁距離・速さと密度の上がり方・乱数の引き方を変えていないことの証拠。
    /// 期待値は一括生成（`pattern(using:)`・400 区画）を置き換える直前に採った先頭 390 区画
    /// （一括生成は末尾の 2 区画を平地に固定し、その手前 3 区画では台座・床を置かなかったので、
    /// そこより手前だけを比べる）。
    @Test("先頭 390 区画は一括生成だった頃の並びと 1 文字も変わらない")
    func streamingMatchesTheFormerBatchGenerator() {
        for (seed, expected) in Self.batchFingerprints {
            #expect(RunnerEndlessCourse.pattern(seed: seed, count: 390) == expected, "種 \(seed)")
        }
    }

    private static let batchFingerprints: [(UInt64, String)] = [
        (1, "--1---1-11--n-1-1ns--n--nnn-s-1---1-1--s2sd2--2n---tndsdn--d1ds2s-2d--n2n-s2-1dt--t--nn11--n2s2-s1ns-n-1-2n2-3-1-3sbb31-1t-1-t--1it--n--PP-stbt21-t-b--bn1t--1t-i-bd-2b31--31ti-sbbstd1s-niinit-btnb1s-3t-tt-n1--d-2--=-st1-ns3-n--bt3--dd1-i1-n-3idnkndn1bbnin2112tn-d--b1n31t1tb-1b3tn-dd11n3n313-b2n3i1-1n-n1nddi1-ni3t3-b2nn-d--b1nbi2i21n12in--bnnn-=-n13n1-3b--b-b1bsnb--nd-1n--nb1biis-nb-i-n2t"),
        (2, "--1---1--1---1--1---2-2---1--2---2-nd-12-12-n2---n--d-n-2d---1--b1-s2n--nd-tb-dndn-d1--n-sn2tbtn-snb2ss31--12--d--d-sn--3dd-bn--=--i3n-n13n--tb--n-n--i1b-d--21n-1s-PPP--dd-in1dns-n-b2b--nb--n1s-n3b-tnsd-1ds-33ninbb2--=-12n2b-1ttb2i31bidb-bt-2i-bi11b-n--t-PP-=-dbdd-==-3sdnnnt--d21ibs-11n-131332s1bid1ds-i1b1di2-b331t1-==-kb-PP-ktn1t-n2-b3binn2dt12bsb3tnd-3-3ibi312ni3binbnn-3-t1-3ids31kiin3"),
        (3, "--1--s1s1--n1-nn-1---21---n---1-2-t-1---tn-n2nt--sd-dtd--sd-nd-t--nbs-=--2-t-s1b2--1-bsn1--=-b--12n2--d--3bn--n-d--tsn31n-3n--dsi-t--1--i-b-bin-sb-d--3n1--n2s-2i12nn--b-1tin-3s-n11-PP-3--n-nni-13-si--ii3n-t321-PP--iininsd3dn32-2d1sin-1n21b-bsn1bk2-kdni-ii31i1nd1t1t-1-31b31-2-1dnd1i3tnddn32-bnt1dni-d2-kd23t13-dd1-s21bdd11b3dtin-ii-k212i1tti23131s22-t-3nd11i-1t-1d1bnis3dnt3-in--23ti--di-1n"),
        (675, "--1---n---n1-s-1--2sn---1--12s--n-d---t-1---2-1-tdsd--11t-n-1s-1-2-=-n2-b--n-1-122-1-n--d-n-n1-PP--23--bt-s1-s1--323--nnn--n--311bb-sb--bb1bs-b2-sn-2--1b-t-i-nniid-s3n12-s3t--1s1-1tsb1--n3t11t--3-3-PP-b-in3--ii-21di-n--ns-i--3-nn-1bbn121s-=--ti32-nd21-b21tdnb1tbi2-n2--tndi--2-ns-nb-in-is1sddi--b3n211b--ni1i21int3b1n-3itii22i-db-3k-2itntn2-in213b12nt-t-snntnd12d2t1i-=-k1ni1bdn1isb22i1tb1-"),
        (1086, "--1---n--1s-1---n---2--1---1---n-1n2-dnss-t-nn-n--n11--n-ns--n-s1-bn--PP--1dd-nt11sb--2n1-b-1-n--==--t-n2d--bs-tb-b2tdd-22--n--1t112s-b--dib--b222-s3--ndtb--tnn-t-=-tb-t-si--2-b3sn-1n1d-n-PP-tnbn-i-ibn-d--nn3-=-1bsb--1stb11321tts-1--binn-1t2dn1-1i1-t-b-sn-22k1-i2-i--ntt--=-i2s-bdt1nt1d1d121in-1d1n31b2bi-it133-b1i-2ttn-i311-d132n1bni2d--2nn-i33tb3sd--t1d2isn13-snn32n3ti2tsnts-PPP--n-nikn2"),
    ]

    /// 受け入れ条件 B「1,000 種 × 70,000 単位以上で、生成されたコースを成立条件で検算する」。
    /// 種を 100 ずつに分けて並列に回す（Swift Testing は引数ごとのケースを並列に走らせる）。
    @Test(
        "1,000 種すべてのコースが 70,000 単位先までステージ制と同じ成立条件を満たす（継ぎ目も含む）",
        .timeLimit(.minutes(5)),
        arguments: 0..<10
    )
    func everySeedSatisfiesLayoutRules(chunk: Int) {
        let first = UInt64(chunk) * 100 + 1
        for seed in first...(first + 99) {
            let sample = EndlessCourseSample(seed: seed, segments: Self.verifiedSegments)
            #expect(sample.seamPairs > 100, "種 \(seed): 継ぎ目をまたぐ並びを見ていない（\(sample.seamPairs)）")
            expectSatisfiesLayoutRules(sample, seed: seed)
        }
    }

    /// 枠から取り出した区画の中身が、同じ並びを `RunnerStage` の展開（ステージ制と同じ式）で作った
    /// 障害・アイテム・台座・床と一致する——区画ごとの組み立て・イノシシの止まる岩の書き足し・
    /// 台座と床の長さが、継ぎ目をまたいでも欠けず重複しないことの独立な確認。
    @Test("枠から集めた区画の中身は、同じ並びをステージ制の式で展開したものと一致する", arguments: [1, 2, 675, 1086] as [UInt64])
    func trackSegmentsMatchStageExpansion(seed: UInt64) {
        let sample = EndlessCourseSample(seed: seed, segments: Self.verifiedSegments)
        let stage = RunnerStage(number: 0, pattern: String(sample.symbols), speed: RunnerRules.baseSpeed)
        // 末尾の 3 区画は比べない。並びを途中で切るので、ステージ制の展開では末尾の台座が短くなり、
        // 最後のイノシシの止まる岩（次の区画）も見えない（枠の区画はその先まで作ってから決めている）。
        let end = Double(Self.verifiedSegments - 3) * RunnerEndlessSegment.width
        #expect(sample.hazards.filter { $0.start < end } == stage.hazards.filter { $0.start < end })
        #expect(sample.pickups.filter { $0.start < end } == stage.pickups.filter { $0.start < end })
        #expect(sample.platforms.filter { $0.start < end } == stage.platforms.filter { $0.start < end })
        #expect(sample.floors.filter { $0.start < end } == stage.boostFloors.filter { $0.start < end })
        #expect(stage.hazards.contains { $0.kind == .boar && $0.stopAt != nil }, "岩で止まるイノシシを含む種で確かめる")
        #expect(!stage.platforms.isEmpty && !stage.boostFloors.isEmpty)
    }

    /// 部品は岩・穴・鳥・犬・イノシシ・アイテム・たこ焼き・台座・床のすべて（Issue #675「部品」、
    /// #800/#801 で動物・#797 でたこ焼きを追加）。解禁距離があるので 1 本の中に全部出るとは
    /// 限らないが、100 種も回せば全種類が出る。
    @Test("岩・穴・鳥・犬・イノシシ・アイテム・たこ焼き・台座・床のすべてが生成に使われる")
    func allPartsAppear() {
        var seen: Set<Character> = []
        for seed in 1...100 as ClosedRange<UInt64> {
            seen.formUnion(RunnerEndlessCourse.pattern(seed: seed, count: Self.analysisSegments))
        }
        #expect(seen == ["-", "1", "2", "3", "n", "t", "b", "d", "i", "s", "k", "P", "="], "出ていない記号がある: \(seen)")
    }

    /// Issue #797「エンドレスでは中盤から」。解禁距離より手前にたこ焼きが 1 つも無く、以降には出ること。
    /// 手前の乱数を余分に消費しないので、解禁前の並びは #797 以前と同じ。
    @Test("たこ焼きは中盤（解禁距離）より手前には出ない")
    func takoyakiAppearsOnlyFromTheMiddle() {
        var seenAfterUnlock = 0
        for seed in 1...100 as ClosedRange<UInt64> {
            let symbols = Array(RunnerEndlessCourse.pattern(seed: seed, count: Self.analysisSegments))
            for (index, symbol) in symbols.enumerated() where symbol == RunnerStage.takoyakiSymbol {
                let distance = Double(index) * Self.segmentWidth
                #expect(
                    distance >= RunnerEndlessCourse.takoyakiUnlockDistance,
                    "種 \(seed): 区画 \(index)（\(distance)）にたこ焼きが早すぎる"
                )
                seenAfterUnlock += 1
            }
        }
        #expect(seenAfterUnlock > 0, "解禁後にたこ焼きが 1 つも出ない")
    }

    /// 受け入れ条件 A「エンドレスにゴールが無い」。#675 は 400 区画目で打ち切り、末尾 2 区画を平地にしていた。
    /// いまは 400 区画を過ぎても同じ密度で障害が続き、平地の連続の上限も保たれる。
    @Test("400 区画を過ぎても末尾の平地は無く、障害が同じ密度で続く")
    func courseDoesNotEnd() {
        var around400 = 0
        var farther = 0
        var segments = 0
        for seed in 1...100 as ClosedRange<UInt64> {
            let symbols = Array(RunnerEndlessCourse.pattern(seed: seed, count: Self.verifiedSegments))
            #expect(symbols[396..<404].contains { RunnerStage.segmentSpec($0) != nil }, "種 \(seed): 400 区画のあたりが平地だけ")
            around400 += symbols[300..<400].filter { RunnerStage.segmentSpec($0) != nil }.count
            farther += symbols[1_000..<1_100].filter { RunnerStage.segmentSpec($0) != nil }.count
            segments += 100
        }
        let near = Double(around400) / Double(segments)
        let far = Double(farther) / Double(segments)
        #expect(abs(near - far) < 0.05, "300〜400 区画の密度 \(near) と 1,000〜1,100 区画の密度 \(far) が違う")
    }

    // MARK: - 難易度カーブ

    /// 受け入れ条件「距離に応じて速くなり障害が増える」。距離 0 と 5,000 で単調増加。
    @Test("距離 0 と 5,000 で速さと密度が単調増加し、どちらも上限で頭打ちになる")
    func difficultyRampsWithDistance() {
        #expect(RunnerEndlessCourse.speed(atDistance: 0) == RunnerRules.baseSpeed)
        #expect(RunnerEndlessCourse.speed(atDistance: 5_000) > RunnerEndlessCourse.speed(atDistance: 0))
        #expect(RunnerEndlessCourse.hazardDensity(atDistance: 5_000) > RunnerEndlessCourse.hazardDensity(atDistance: 0))
        var previousSpeed = 0.0
        var previousDensity = 0.0
        for distance in stride(from: 0.0, through: 10_000_000, by: 500) where distance <= 70_000 || distance.truncatingRemainder(dividingBy: 1_000_000) == 0 {
            let speed = RunnerEndlessCourse.speed(atDistance: distance)
            let density = RunnerEndlessCourse.hazardDensity(atDistance: distance)
            #expect(speed >= previousSpeed && density >= previousDensity, "距離 \(distance) で下がっている")
            #expect(speed <= RunnerRules.endlessMaxSpeed && density <= 1, "距離 \(distance) で上限を超えている")
            previousSpeed = speed
            previousDensity = density
        }
        #expect(previousSpeed == RunnerRules.endlessMaxSpeed, "終盤は上限に達する")
        // エンドレスの `RunnerStage` の `speed(at:)` も同じ式。
        let stage = RunnerEndlessCourse.stage
        for distance in [0.0, 1_000, 5_000, 20_000, 30_000, 10_000_000] {
            #expect(abs(stage.speed(at: distance) - RunnerEndlessCourse.speed(atDistance: distance)) < 1e-9)
        }
    }

    /// 密度の上がり方が生成結果にも出ていること（確率の式だけでなく、実際に後半のほうが密）。
    @Test("生成したコースは冒頭より終盤のほうが障害が多い")
    func generatedCoursesGetDenser() {
        var early = 0
        var late = 0
        for seed in 1...100 as ClosedRange<UInt64> {
            let symbols = Array(RunnerEndlessCourse.pattern(seed: seed, count: Self.analysisSegments))
            early += symbols[12..<112].filter { RunnerStage.segmentSpec($0) != nil }.count
            late += symbols[298..<398].filter { RunnerStage.segmentSpec($0) != nil }.count
        }
        #expect(Double(late) > Double(early) * 1.5, "冒頭 \(early) 個 / 終盤 \(late) 個")
    }

    // MARK: - 難易度曲線（#930・会長 QA「何もない時間が長過ぎる」）

    /// 区画の記号が「何もない」（素の平地・アイテム・たこ焼き）か。障害・台座・床は「何かある」。
    private static func isEmpty(_ symbol: Character) -> Bool {
        RunnerStage.segmentSpec(symbol) == nil
            && symbol != RunnerStage.platformSymbol
            && symbol != RunnerStage.boostFloorSymbol
    }

    /// 距離 `range` に入る区画の並び（区画の左端の距離で見る。先頭 `analysisSegments` 区画の中）。
    private static func body(of symbols: [Character], in range: Range<Double>) -> ArraySlice<Character> {
        let lower = Int((range.lowerBound / segmentWidth).rounded(.up))
        let upper = range.upperBound.isFinite
            ? min(symbols.count, Int((range.upperBound / segmentWidth).rounded(.up)))
            : symbols.count
        return symbols[lower..<upper]
    }

    /// 1,000 種の平均で、`range` の区画 1 つあたりの障害（岩・穴・動物）の数。
    private static func meanHazardDensity(in range: Range<Double>) -> Double {
        var hazards = 0
        var segments = 0
        for seed in 1...seedCount {
            let slice = body(of: Array(RunnerEndlessCourse.pattern(seed: seed, count: analysisSegments)), in: range)
            hazards += slice.filter { RunnerStage.segmentSpec($0) != nil }.count
            segments += slice.count
        }
        return Double(hazards) / Double(segments)
    }

    /// 冒頭の固定区間は 1 画面ぶん（`--1-`）。以前の `--1-1--1-1--`（12 区画）は
    /// 「何もない時間」の大半を占めていた（#930）。
    @Test("冒頭の固定区間は最初の穴までの 4 区画")
    func introIsShort() {
        #expect(RunnerEndlessCourse.intro == "--1-")
    }

    /// 最初の 2,000 単位（32 区画・約 1 分）に障害が平均 6 個以上ある（Issue #930 の下限）。
    /// 測定値: #930 で直す前は 10.67 個だが、うち 4 個は冒頭 12 区画の固定区間で、ランダム部分
    /// 20 区画には 6.7 個（密度 0.33）しか無かった。直した後は 12.50 個（固定 1 個＋28 区画に 11.5 個）。
    @Test("最初の 2,000 単位に障害が平均 6 個以上ある")
    func openingHasEnoughHazards() {
        var total = 0
        for seed in 1...Self.seedCount {
            let slice = Self.body(of: Array(RunnerEndlessCourse.pattern(seed: seed, count: 40)), in: 0..<2_000)
            total += slice.filter { RunnerStage.segmentSpec($0) != nil }.count
        }
        let mean = Double(total) / Double(Self.seedCount)
        #expect(mean >= 6, "最初の 2,000 単位の障害は平均 \(mean) 個")
    }

    /// 平地（何もない区画）の連続に上限がある: 序盤は最大 3 区画、4,000 単位以降は最大 2 区画。
    /// 70,000 単位先まで（継ぎ目をまたぐ連続も含めて）見る。
    /// 測定値: #930 で直す前は 1,000 種すべてが両方に落ちた（序盤の最長は 4〜23 区画、
    /// 4,000 以降の最長は 4〜18 区画。速さ 34 で 1 区画 ≒ 1.9 秒なので、8 区画 = 15 秒の空白が普通だった）。
    @Test("平地の連続は序盤 3 区画・4,000 単位以降 2 区画まで（70,000 単位先まで）")
    func flatRunsAreCapped() {
        let lateStart = Int((RunnerEndlessCourse.flatRunTightenDistance / Self.segmentWidth).rounded(.up))
        for seed in 1...Self.seedCount {
            let symbols = Array(RunnerEndlessCourse.pattern(seed: seed, count: Self.verifiedSegments))
            var run = 0
            var longestEarly = 0
            var longestLate = 0
            for index in symbols.indices {
                run = Self.isEmpty(symbols[index]) ? run + 1 : 0
                if index < lateStart {
                    longestEarly = max(longestEarly, run)
                } else if run >= 3 {
                    // 4,000 単位以降だけで 3 区画続いた（またぎは序盤の上限で見る）。
                    longestLate = max(longestLate, min(run, index - lateStart + 1))
                }
            }
            #expect(longestEarly <= 3, "種 \(seed): 序盤に平地が \(longestEarly) 区画続く")
            #expect(longestLate < 3, "種 \(seed): 4,000 単位以降に平地が \(longestLate) 区画続く")
        }
    }

    /// 距離 0〜2,000 / 2,000〜8,000 / 8,000〜 の障害密度（区画あたりの障害の数）が単調に増える。
    /// 測定値: #930 で直す前は 0.333 / 0.423 / 0.605（全体 0.540）、直した後は 0.391 / 0.468 / 0.677（全体 0.605）。
    @Test("障害密度は 0〜2,000 / 2,000〜8,000 / 8,000〜 の順に増える")
    func hazardDensityRisesByDistance() {
        let opening = Self.meanHazardDensity(in: 0..<2_000)
        let middle = Self.meanHazardDensity(in: 2_000..<8_000)
        let late = Self.meanHazardDensity(in: 8_000..<Double.infinity)
        #expect(opening < middle && middle < late, "密度 \(opening) / \(middle) / \(late)")
    }

    /// 解禁距離（#930 で前倒し）: 犬 2,048・鳥 4,096・台座と床 4,096・イノシシ 8,192・たこ焼き 12,800。
    /// 手前に 1 つも出ず、解禁後には出ること。
    @Test("鳥・犬・イノシシ・台座・床は解禁距離より手前に出ない")
    func partsUnlockAtTheirDistances() {
        let unlocks: [(symbol: Character, distance: Double)] = [
            ("d", 2_048), ("b", 4_096),
            (RunnerStage.platformSymbol, 4_096), (RunnerStage.boostFloorSymbol, 4_096),
            ("i", 8_192),
        ]
        var earliest: [Character: Double] = [:]
        for seed in 1...Self.seedCount {
            for (index, symbol) in RunnerEndlessCourse.pattern(seed: seed, count: Self.analysisSegments).enumerated() {
                let distance = Double(index) * Self.segmentWidth
                earliest[symbol] = min(earliest[symbol] ?? .infinity, distance)
            }
        }
        for unlock in unlocks {
            let first = earliest[unlock.symbol] ?? .infinity
            #expect(first >= unlock.distance, "'\(unlock.symbol)' が \(first) に出る（解禁は \(unlock.distance)）")
            #expect(first < unlock.distance + 2_048, "'\(unlock.symbol)' が解禁後すぐには出ない（初出 \(first)）")
        }
    }

    /// 速さの上限そのものが成立条件の内側にあること（`RunnerRules.endlessMaxSpeed` のドキュメント）。
    /// 隣り合う区画に**どの組み合わせで**障害が並んでも、着地して踏み切り直せる。
    ///
    /// 唯一の例外は**飛び立つ鳥の直後の高い岩**（`bt`）。鳥は出会う地点が区画中央より 6 先へ
    /// ずれる（`RunnerHazard.encounter`）ので、上限の速さでは高い岩への踏み切りに 2.7 足りない。
    /// 生成器はこの並びを `canPlace` で弾いて平地に倒す（置けないことをここで固定する）。
    /// ステージ制の `bt`（13・15・18 面）は速さ 47.6 以下（#968 までは 54.4）で余白が残る（`RunnerStageTests`）。
    @Test("速さの上限でも、隣り合う区画に並んだ障害の間に着地の余白がある（鳥→高い岩だけ弾く）")
    func maxSpeedKeepsAdjacentHazardsPassable() {
        let speed = RunnerRules.endlessMaxSpeed
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        for previous in ["1", "2", "3", "n", "t", "b", "d", "i"] {
            for next in ["1", "2", "3", "n", "t", "b", "d", "i"] {
                guard let a = RunnerStage.segmentSpec(Character(previous)),
                      let b = RunnerStage.segmentSpec(Character(next)) else { continue }
                let first = RunnerHazard(kind: a.kind, start: offset, length: Double(a.tiles) * RunnerRules.tileWidth)
                let second = RunnerHazard(
                    kind: b.kind, start: Self.segmentWidth + offset, length: Double(b.tiles) * RunnerRules.tileWidth
                )
                let placeable = RunnerEndlessCourse.canPlace(second, after: first, speedBefore: speed, speedAfter: speed)
                if previous == "b", next == "t" {
                    #expect(!placeable, "鳥の直後の高い岩は上限の速さでは置けない（置けるようになったら doc を直す）")
                } else {
                    #expect(placeable, "\(previous) の隣に \(next) を置けない")
                }
            }
        }
    }

    // MARK: - 成立条件（`RunnerStageTests` と同じ物差し）

    /// タップ（踏み切って即離す）の弾道の標本。`RunnerPlaythroughTests.tapFlight` と同じ測り方。
    private static let tapFlight: [Double] = {
        var field = RunnerField(stage: RunnerStage(number: 1, pattern: "----", speed: 40))
        field.jump()
        field.endHold()
        var samples: [Double] = []
        while !field.isGrounded, samples.count < 6000 {
            _ = field.step(dt: tapSampleDT)
            samples.append(field.altitude)
        }
        return samples
    }()
    private static let tapSampleDT = 1.0 / 600
    private static var tapAirTime: Double { Double(tapFlight.count) * tapSampleDT }
    private static func tapTime(above height: Double) -> Double {
        Double(tapFlight.filter { $0 >= height }.count) * tapSampleDT
    }

    /// 1 本のコースを、ステージ制の成立条件で検める。
    ///
    /// 速さは距離で上がるので、越えられるかは**手前の遅い**速さ（`low`）で、間隔・鳥の前後は
    /// **先の速い**速さ（`high`）で判定する。どちらも生成器が使う幅より外側を取る。
    private func expectSatisfiesLayoutRules(_ course: EndlessCourseSample, seed: UInt64) {
        let halfWidth = RunnerField.Metrics.playerHalfWidth
        func speed(_ distance: Double) -> Double { RunnerEndlessCourse.speed(atDistance: distance) }
        func low(_ hazard: RunnerHazard) -> Double { speed(hazard.start - Self.segmentWidth) }
        func high(_ hazard: RunnerHazard) -> Double { speed(hazard.end + Self.segmentWidth * 2) }
        // 瞬間タップで高さを越えている時間。高さの種類は数えるほどなので覚えておく（標本の走査は重い）。
        var tapTimes: [Double: Double] = [:]
        func tapTime(above height: Double) -> Double {
            if let known = tapTimes[height] { return known }
            let time = Self.tapTime(above: height)
            tapTimes[height] = time
            return time
        }

        // 記号。集めた並びの右端（`courseEnd`）をまたぐ台座・床と、右端の区画のイノシシは
        // 相手（連続の続き・止まる岩）が並びの外にあるので、それを要る検算からは外す。
        let symbols = course.symbols
        let courseEnd = Double(symbols.count) * Self.segmentWidth
        for symbol in symbols where symbol != "-" {
            let isKnown = RunnerStage.segmentSpec(symbol) != nil
                || symbol == RunnerStage.pickupSymbol
                || symbol == RunnerStage.takoyakiSymbol
                || symbol == RunnerStage.platformSymbol
                || symbol == RunnerStage.boostFloorSymbol
            #expect(isKnown, "種 \(seed): 未知の記号 '\(symbol)'")
        }

        // 障害 1 つずつ: 押さないジャンプで越えられる（動く障害は等価な静止区間で）。穴は最大 3 タイル表記（4 タイル幅）。
        for hazard in course.hazards {
            let speed = low(hazard)
            let encounter = hazard.encounter
            switch hazard.kind {
            case .pit:
                #expect(hazard.length <= 4 * RunnerRules.tileWidth, "種 \(seed): 穴が広すぎる（\(hazard.length)）")
                let needed = RunnerAutoPilot.lead(for: hazard, speed: speed) + hazard.length
                #expect(
                    speed * RunnerRules.jumpAirTime > needed + RunnerRules.tileWidth,
                    "種 \(seed): \(hazard.start) の穴（\(hazard.length)）が跳び越せない"
                )
                // 瞬間タップでも渡れる（`RunnerPlaythroughTests.instantTapClearsPitsAndLowBlocks` と同じ境目）。
                #expect(
                    speed * Self.tapAirTime > hazard.length + halfWidth + RunnerRules.tileWidth,
                    "種 \(seed): \(hazard.start) の穴（\(hazard.length)）を瞬間タップで渡れない（速さ \(speed)）"
                )
            case .lowBlock, .tallBlock, .bird, .dog, .boar:
                let overlap = (encounter.length + halfWidth * 2) / speed
                #expect(
                    RunnerRules.airTime(above: encounter.height + RunnerAutoPilot.clearance) > overlap,
                    "種 \(seed): \(hazard.start) の \(hazard.kind)（高さ \(encounter.height)）を越えきれない"
                )
                #expect(encounter.height < RunnerRules.jumpApex)
                if hazard.kind != .tallBlock, !(hazard.kind == .boar && hazard.stopAt != nil) {
                    #expect(
                        tapTime(above: encounter.height + RunnerAutoPilot.clearance) > overlap,
                        "種 \(seed): \(hazard.start) の \(hazard.kind) を瞬間タップで越えられない"
                    )
                }
                if hazard.kind == .boar, hazard.start + Self.segmentWidth < courseEnd {
                    // 止まる岩はステージ制の式（`boarStop`）で独立に求め直したものと一致する。
                    let moving = RunnerHazard(kind: .boar, start: hazard.start, length: hazard.length)
                    #expect(
                        hazard.stopAt == RunnerStage.boarStop(for: moving, among: course.hazards),
                        "種 \(seed): イノシシ \(hazard.start) の止まる岩が食い違う"
                    )
                }
                // 岩の右側で止まったイノシシ（#801）は岩と一続き。岩の高さのまま両方を越えきれること。
                if hazard.kind == .boar, hazard.start + Self.segmentWidth < courseEnd, let stopAt = hazard.stopAt {
                    let rock = course.hazards.first { $0.kind.isRock && $0.end == stopAt }
                    #expect(rock != nil, "種 \(seed): イノシシ \(hazard.start) が止まる岩が無い")
                    if let rock {
                        #expect(
                            RunnerEndlessCourse.isClearableWithBoarBehind(rock, speed: low(rock)),
                            "種 \(seed): 岩 \(rock.start) と止まったイノシシを越えきれない"
                        )
                    }
                }
            }
        }

        // 隣り合う障害の間隔（動く障害は等価な静止区間の並びで）。岩と、その右側で止まった
        // イノシシは一続きなので間隔を問わない。
        let ordered = course.hazards.sorted { $0.encounter.start < $1.encounter.start }
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            if next.kind == .boar, next.stopAt == previous.end, previous.kind.isRock { continue }
            let speed = high(next)
            let needed = speed * RunnerRules.jumpAirTime + RunnerAutoPilot.lead(for: next, speed: speed)
            #expect(
                next.encounter.start - previous.encounter.start > needed,
                "種 \(seed): \(previous.start)（\(previous.kind)）と \(next.start)（\(next.kind)）が近すぎる"
            )
        }
        // 障害のあとの台座への踏み切り（`RunnerEndlessCourse.canPlacePlatform` と同じ式）。
        for platform in course.platforms {
            guard let previous = ordered.last(where: { $0.encounter.start < platform.start }) else { continue }
            let speed = speed(platform.start + Self.segmentWidth)
            let rise = RunnerRules.riseTime(to: platform.top + RunnerAutoPilot.clearance)
            let takeOff = platform.start - RunnerAutoPilot.baseLead - speed * rise
            let landing = previous.encounter.start - RunnerAutoPilot.lead(for: previous, speed: speed)
                + speed * RunnerRules.jumpAirTime
            #expect(landing < takeOff, "種 \(seed): \(previous.start) の着地が台座 \(platform.start) の踏み切りに食い込む")
        }

        // 台座の前後は素の平地、床の直後は素の平地で台座の隣ではない（`RunnerStage.patterns` の配置規則）。
        for (index, symbol) in symbols.enumerated() {
            if symbol == RunnerStage.platformSymbol {
                if index > 0, symbols[index - 1] != RunnerStage.platformSymbol {
                    #expect(symbols[index - 1] == "-", "種 \(seed): 台座の手前（区画 \(index - 1)）が平地でない")
                }
                if index < symbols.count - 1, symbols[index + 1] != RunnerStage.platformSymbol {
                    #expect(symbols[index + 1] == "-", "種 \(seed): 台座の直後（区画 \(index + 1)）が平地でない")
                }
            }
            if symbol == RunnerStage.boostFloorSymbol {
                if index < symbols.count - 1, symbols[index + 1] != RunnerStage.boostFloorSymbol {
                    #expect(symbols[index + 1] == "-", "種 \(seed): 床の直後（区画 \(index + 1)）が平地でない")
                }
                if index > 0 {
                    #expect(symbols[index - 1] != RunnerStage.platformSymbol, "種 \(seed): 床が台座の直後（区画 \(index)）")
                }
            }
        }
        // 台座・床は連続の頭にだけ 1 基あり、長さは連続の区画数ちょうど（欠けない・重複しない）。
        func expectRuns<T>(of symbol: Character, _ items: [T], start: (T) -> Double, length: (T) -> Double, name: String) {
            var runs: [(start: Double, length: Double)] = []
            var index = 0
            while index < symbols.count {
                guard symbols[index] == symbol else { index += 1; continue }
                let head = index
                while index < symbols.count, symbols[index] == symbol { index += 1 }
                runs.append((Double(head) * Self.segmentWidth, Double(index - head) * Self.segmentWidth))
            }
            runs.removeAll { $0.start + $0.length >= courseEnd }
            let items = items.filter { start($0) + length($0) < courseEnd }
            #expect(items.count == runs.count, "種 \(seed): \(name)の数 \(items.count) と連続の数 \(runs.count)")
            for (item, run) in zip(items, runs) {
                #expect(start(item) == run.start && length(item) == run.length, "種 \(seed): \(name) \(start(item)) の範囲が連続と食い違う")
            }
        }
        expectRuns(of: RunnerStage.platformSymbol, course.platforms, start: \.start, length: \.length, name: "台座")
        expectRuns(of: RunnerStage.boostFloorSymbol, course.floors, start: \.start, length: \.length, name: "床")
        for platform in course.platforms {
            #expect(platform.top + RunnerAutoPilot.clearance < RunnerRules.jumpApex)
            // 台座の上の区画には障害・アイテム・床が無い（障害とアイテムは自分の区画の中にしか無い）。
            guard platform.end <= courseEnd else { continue }
            let first = Int(platform.start / Self.segmentWidth)
            let last = Int((platform.end / Self.segmentWidth).rounded()) - 1
            for index in first...last {
                #expect(symbols[index] == RunnerStage.platformSymbol, "種 \(seed): 台座の上（区画 \(index)）に '\(symbols[index])'")
            }
        }
    }

    // MARK: - 成立条件の判定そのもの（#833）
    //
    // 上の 1,000 種の検算は生成したコースしか見ないので、判定の境界は固定されない。ここで直接縛る。

    @Test("isClearable: 3 タイルの穴は走り出しの速さでは越えられず、速くなれば越えられる")
    func isClearableDependsOnSpeed() {
        let widest = RunnerStage.makeHazards(pattern: "3")[0]
        // 必要な飛距離 = 踏み切りの余裕 6 + 穴 16 + 1 タイル 4 = 26。飛距離は 速さ × 0.75。
        #expect(!RunnerEndlessCourse.isClearable(widest, speed: RunnerRules.baseSpeed), "34 × 0.75 = 25.5 < 26")
        #expect(RunnerEndlessCourse.isClearable(widest, speed: 35), "35 × 0.75 = 26.25 > 26")
        // 最高速の飛距離 45 に対して、必要 6 + 36 + 4 = 46 の穴は越えられず、6 + 34 + 4 = 44 なら越えられる。
        let maxSpeed = RunnerRules.endlessMaxSpeed
        #expect(!RunnerEndlessCourse.isClearable(RunnerHazard(kind: .pit, start: 0, length: 36), speed: maxSpeed))
        #expect(RunnerEndlessCourse.isClearable(RunnerHazard(kind: .pit, start: 0, length: 34), speed: maxSpeed))
        // 長すぎる岩は、上端を越えている時間のうちに通り抜けられない。
        #expect(RunnerEndlessCourse.isClearable(RunnerHazard(kind: .lowBlock, start: 0, length: 4), speed: RunnerRules.baseSpeed))
        #expect(!RunnerEndlessCourse.isClearable(RunnerHazard(kind: .lowBlock, start: 0, length: 100), speed: RunnerRules.baseSpeed))
    }

    @Test("hasLandingGap: 最高速で、着地して踏み切り直す間隔がちょうどしか無い並びは通さない")
    func hasLandingGapBoundaryAtMaxSpeed() {
        let speed = RunnerRules.endlessMaxSpeed
        let previous = RunnerHazard(kind: .pit, start: 24, length: 8)
        // 必要な間隔（左端どうし）= 跳んで進む 60 × 0.75 = 45 + 次の穴への踏み切りの余裕 6。
        let needed = speed * RunnerRules.jumpAirTime + RunnerAutoPilot.baseLead
        #expect(needed == 51)
        let tight = RunnerHazard(kind: .pit, start: previous.start + needed, length: 8)
        let enough = RunnerHazard(kind: .pit, start: previous.start + needed + 0.5, length: 8)
        #expect(!RunnerEndlessCourse.hasLandingGap(from: previous, to: tight, speed: speed), "ちょうどでは足りない")
        #expect(RunnerEndlessCourse.hasLandingGap(from: previous, to: enough, speed: speed))
        #expect(RunnerEndlessCourse.hasLandingGap(from: previous, to: tight, speed: RunnerRules.baseSpeed), "遅ければ同じ間隔で足りる")
        // 隣り合う区画（64 離れる）なら最高速でも足りる。
        let adjacent = RunnerStage.makeHazards(pattern: "11")
        #expect(RunnerEndlessCourse.hasLandingGap(from: adjacent[0], to: adjacent[1], speed: speed))
    }

    @Test("hasLandingGap: 動く障害は置いた位置ではなく出会う地点（encounter）から測る")
    func hasLandingGapMeasuresFromEncounter() {
        let speed = RunnerRules.endlessMaxSpeed
        let bird = RunnerHazard(kind: .bird, start: 24, length: RunnerRules.tileWidth)
        let shift = bird.encounter.start - bird.start
        #expect(shift > 0, "鳥は飛び立って前へ進んだ地点で出会う")
        let needed = speed * RunnerRules.jumpAirTime + RunnerAutoPilot.baseLead
        // 置いた位置から測れば足りるが、出会う地点から測ると足りない間隔。
        let next = RunnerHazard(kind: .pit, start: bird.start + needed + shift / 2, length: 8)
        #expect(next.start - bird.start > needed, "対照: 置いた位置から測れば足りる")
        #expect(!RunnerEndlessCourse.hasLandingGap(from: bird, to: next, speed: speed))
    }

    @Test("canPlacePlatform: 前の障害を跳んだ着地が、台座への踏み切りより手前で終わるときだけ置ける")
    func canPlacePlatformNeedsLandingBeforeTakeOff() {
        let speed = RunnerRules.baseSpeed
        #expect(RunnerEndlessCourse.canPlacePlatform(at: 64, after: nil, speed: speed), "前に障害が無ければ置ける")
        // 台座 64 への踏み切り = 64 − 6 − 34 × (高さ 8.5 までの上昇時間 ≒ 0.1392) ≒ 53.27。
        // 穴を跳んだ着地 = 穴の左端 − 6 + 34 × 0.75 = 左端 + 19.5。
        let previousSegment = RunnerHazard(kind: .pit, start: 24, length: 8)  // 着地 43.5
        let tooClose = RunnerHazard(kind: .pit, start: 40, length: 8)  // 着地 59.5
        #expect(RunnerEndlessCourse.canPlacePlatform(at: 64, after: previousSegment, speed: speed))
        #expect(!RunnerEndlessCourse.canPlacePlatform(at: 64, after: tooClose, speed: speed))
        // 踏み切り 53.27 をはさむ着地 53.0 / 53.5。上昇にかかる距離（34 × 0.1392 ≒ 4.73）を見込まないと
        // 踏み切りが 58 になり、53.5 の側も置けてしまう。
        #expect(RunnerEndlessCourse.canPlacePlatform(at: 64, after: RunnerHazard(kind: .pit, start: 33.5, length: 8), speed: speed))
        #expect(!RunnerEndlessCourse.canPlacePlatform(at: 64, after: RunnerHazard(kind: .pit, start: 34, length: 8), speed: speed))
    }
}

/// 枠（`RunnerEndlessTrack`）を少しずつ進めながら、入ってきた区画を先頭から順に集めたもの。
///
/// 枠は `capacity` を使い回すので、集めた並びには**枠の最後から最初へ回った継ぎ目**をまたぐ
/// 隣り合う区画の組が含まれる（`seamPairs` がその数）。
struct EndlessCourseSample {
    var symbols: [Character] = []
    var segments: [RunnerEndlessSegment] = []
    var hazards: [RunnerHazard] = []
    var pickups: [RunnerPickup] = []
    var platforms: [RunnerPlatform] = []
    var floors: [RunnerBoostFloor] = []
    /// 枠の番号が `capacity − 1` から 0 へ回った隣り合う区画の組の数。
    var seamPairs = 0

    init(seed: UInt64, segments count: Int, capacity: Int = RunnerEndlessTrack.defaultCapacity,
         aheadDistance: Double = RunnerEndlessTrack.aheadDistance, step: Double = 7) {
        var track = RunnerEndlessTrack(seed: seed, capacity: capacity, aheadDistance: aheadDistance)
        var distance = 0.0
        var previousSlot: Int?
        while segments.count < count {
            for position in 0..<track.count {
                let segment = track[position]
                guard segment.index == segments.count else { continue }
                let slot = track.slot(ofSegmentIndex: segment.index)
                if let previousSlot, let slot, previousSlot == capacity - 1, slot == 0 { seamPairs += 1 }
                previousSlot = slot
                segments.append(segment)
                symbols.append(segment.symbol)
                if let hazard = segment.hazard { hazards.append(hazard) }
                if let pickup = segment.pickup { pickups.append(pickup) }
                if let platform = segment.platform { platforms.append(platform) }
                if let floor = segment.boostFloor { floors.append(floor) }
                if segments.count == count { break }
            }
            distance += step
            track.advance(to: distance)
        }
    }
}

/// 枠（`RunnerEndlessTrack`）と、走りながら作るコースの性質（#1086 の受け入れ条件 C・D・E）。
@Suite("チャリンコおじさん: エンドレスの枠")
struct RunnerEndlessTrackTests {
    /// 受け入れ条件 C「区画 N の中身は種と N だけで決まる」「枠の数・何区画先まで作るかに左右されない」。
    @Test("枠の数・先読みの距離・進め方を変えても、区画ごとの中身は同じ")
    func contentIsIndependentOfCapacityAndLookahead() {
        for seed in [7, 1086] as [UInt64] {
            let reference = EndlessCourseSample(seed: seed, segments: 600)
            for (capacity, ahead, step) in [(8, 160.0, 1.3), (16, 400.0, 23.0), (32, 1_000.0, 64.0), (64, 2_000.0, 250.0)] {
                let other = EndlessCourseSample(seed: seed, segments: 600, capacity: capacity, aheadDistance: ahead, step: step)
                #expect(other.segments == reference.segments, "種 \(seed)・枠 \(capacity)・先読み \(ahead)・刻み \(step)")
            }
            // 生成器を直接回した並びとも同じ（枠は中身を作り替えない）。
            var generator = RunnerEndlessGenerator(seed: seed)
            #expect((0..<600).map { _ in generator.next() } == reference.segments)
        }
    }

    /// 受け入れ条件 D「保持する区画データの数に上限があり、距離に比例して増えない」
    /// 「走行中に区画データ用の配列の再確保が起きない」。
    @Test("枠は 8 区画で、10,000,000 単位先まで進めても増えず、配列も再確保されない")
    func trackStaysBoundedWithoutReallocation() {
        #expect(RunnerEndlessTrack.defaultCapacity == 8)
        var track = RunnerEndlessTrack(seed: 3)
        let address = track.storageAddress
        var distance = 0.0
        var maxCount = 0
        while distance < 70_000 {
            distance += 4.65  // 最高速（60 × ペダル 1.55）で 1/20 秒ぶん
            track.advance(to: distance)
            maxCount = max(maxCount, track.count)
            #expect(track.count <= 7, "距離 \(distance) で \(track.count) 区画")
            #expect(track.storageAddress == address, "距離 \(distance) で配列が再確保された")
        }
        #expect(maxCount == 7, "同時に持つ区画の最大（doc の根拠）: \(maxCount)")
        // 一気に遠くへ進めても、持つ区画の数と配列は変わらない。
        track.advance(to: 10_000_000)
        #expect(track.count <= 7)
        #expect(track.storageAddress == address)
        #expect(track.firstIndex == Int(10_000_000 / RunnerEndlessSegment.width) - RunnerEndlessTrack.retainedSegmentsBehind)
    }

    /// 受け入れ条件 E「最高速でも走者の前方に生成済みの区画が常に一定数以上ある」。
    /// 一定数 = `aheadDistance`（160 = 画面の先読み 74 に、イノシシが突進を始める 76 先の区画の右端 116 を
    /// 覆うだけの余裕を足した距離）。走者のいる区画の先に、少なくとも 2 区画まるごと。
    @Test("最高速で最大の刻みで進めても、走者の前 160 単位（2 区画以上）は常に生成済み")
    func generationKeepsAheadAtMaxSpeed() {
        // 最高速 = 速さの上限 × ペダルの上限 × アイテム・ジャスト着地の上乗せ × 床（`RunnerField.step` の見積もりと同じ）。
        let top = RunnerRules.endlessMaxSpeed
            * (RunnerRules.maxPedalBoost + RunnerRules.pickupOverboost + RunnerRules.justLandingOverboost)
            * RunnerRules.boostFloorMultiplier
        var track = RunnerEndlessTrack(seed: 11)
        var distance = 0.0
        while distance < 30_000 {
            distance += top * RunnerRules.maxStep
            track.advance(to: distance)
            #expect(track.generatedEnd - distance >= RunnerEndlessTrack.aheadDistance)
            let current = Int(distance / RunnerEndlessSegment.width)
            #expect(track.endIndex - current - 1 >= 2, "距離 \(distance): 前に \(track.endIndex - current - 1) 区画")
        }
    }

    /// 受け入れ条件 E「区画を作る処理でフレーム落ちしない。1 区画ぶんの生成時間を計測する」。
    /// デバッグビルドの計測値（最適化なしなので製品より遅い側の見積もり）を出力し、1 フレーム（16.7 ミリ秒）の
    /// 1/100 に当たる 0.167 ミリ秒を上限にする。1 フレームで作る区画は最高速でも 1 つ未満（64 ÷ 93 × 1/60）。
    @Test("1 区画の生成はデバッグビルドでも 0.167 ミリ秒未満")
    func generationIsFastEnough() {
        var generator = RunnerEndlessGenerator(seed: 5)
        let count = 50_000
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<count { _ = generator.next() }
        }
        let perSegment = (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18) / Double(count)
        print("エンドレスの生成: 1 区画 \(String(format: "%.4f", perSegment * 1_000)) ミリ秒（\(count) 区画の平均）")
        #expect(perSegment < 0.167e-3, "1 区画 \(perSegment * 1_000) ミリ秒")
    }

    /// 受け入れ条件 E「生成されていない場所に走者が入っても地面として扱われ、落ちない」。
    /// 先読みを負にして、生成がわざと走者の後ろを追いかける枠で走らせる（穴は区画のデータでしか表さない）。
    @Test("まだ作っていない場所は地面で、跳ばずに走っても落ちない")
    func ungeneratedGroundIsSolid() {
        var field = RunnerField(endless: RunnerEndlessTrack(seed: 1, capacity: 8, aheadDistance: -200))
        var events: [RunnerEvent] = []
        for _ in 0..<(60 * 20) { events += field.step(dt: 1.0 / 60) }
        #expect(field.distance > 800)
        let terminals = events.filter { $0.isTerminal }
        #expect(terminals.isEmpty, "\(terminals)")
        let beyond = field.distance + 20
        #expect(beyond > field.track?.generatedEnd ?? 0, "対照: 走者の前は作っていない")
        #expect(!field.isPit(at: beyond))
        #expect(field.surfaceY(at: beyond) == RunnerField.Metrics.groundY)
        // 対照: ふつうの先読みなら同じ時間のうちに穴で落ちる。
        var normal = RunnerField(endlessSeed: 1)
        var normalEvents: [RunnerEvent] = []
        for _ in 0..<(60 * 20) where !normalEvents.contains(where: \.isTerminal) { normalEvents += normal.step(dt: 1.0 / 60) }
        #expect(normalEvents.contains(.fell))
    }
}

/// エンドレスのコースを実際に走り続けられることの実証（`RunnerPlaythroughTests` と同じ自動操縦）。
@Suite("チャリンコおじさん: エンドレスのクリア可能性")
struct RunnerEndlessPlaythroughTests {
    /// 受け入れ条件 A「自動操縦で 70,000 単位以上をミスせず走れる。少なくとも 20 種」。
    ///
    /// あわせて、走っているあいだずっと次を確かめる（受け入れ条件 A・D・E・F）:
    /// - ゴール・チェックポイントのできごとが出ない
    /// - 枠は 7 区画以内で、配列は再確保されない
    /// - 前 160 単位は生成済み
    /// - 取ったアイテムは枠を回しても取ったまま、取っていないアイテムは消えない、通り過ぎたアイテムは必ず取っている
    /// 種 675 は撮影・長時間の実測（`-simulateRunner endless-*`）が使う種。
    @Test("自動操縦が 20 種すべて（と撮影用の種）で 70,000 単位をミスせず走り続ける", .timeLimit(.minutes(5)), arguments: Array(1...20) + [675])
    func autoPilotRuns70000Units(seed: Int) {
        let goal = 70_000.0
        var field = RunnerField(endlessSeed: UInt64(seed))
        let address = field.track?.storageAddress
        // 同じ並びをステージ制の式で一括に展開したコース。足元の接地面・床・穴をこれと突き合わせ、
        // 枠から後ろの区画を早く捨てすぎていない（乗っている台座が消えない）ことを走りながら確かめる。
        let reference = RunnerField(stage: RunnerStage(
            number: 0, pattern: RunnerEndlessCourse.pattern(seed: UInt64(seed), count: 1_200), speed: RunnerRules.baseSpeed
        ))
        var frames = 0
        var collectedEver = Set<Int>()
        var pickupsPassed = Set<Int>()
        while frames < 60 * 2_000, field.distance < goal {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
            if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
            let events = field.step(dt: 1.0 / 60)
            if let terminal = events.first(where: \.isTerminal) {
                Issue.record("種 \(seed): \(field.distance) で \(terminal)")
                return
            }
            if events.contains(.passedCheckpoint) { Issue.record("種 \(seed): チェックポイントのできごとが出た") }
            guard let track = field.track else { Issue.record("枠が無い"); return }
            if track.count > 7 || track.storageAddress != address {
                Issue.record("種 \(seed): 距離 \(field.distance) で枠 \(track.count)・配列の再確保")
            }
            for x in [field.playerMinX, field.distance, field.playerMaxX]
            where field.surfaceY(at: x) != reference.surfaceY(at: x) || field.isPit(at: x) != reference.isPit(at: x) {
                Issue.record("種 \(seed): 距離 \(field.distance) の足元（x \(x)）が一括展開と違う")
            }
            if track.generatedEnd - field.distance < RunnerEndlessTrack.aheadDistance {
                Issue.record("種 \(seed): 距離 \(field.distance) で生成が追いついていない")
            }
            // アイテム。
            for index in field.collectedPickupIndices {
                if track.segment(withIndex: index)?.pickup == nil { Issue.record("種 \(seed): 枠に無い区画 \(index) を取った印") }
            }
            collectedEver.formUnion(field.collectedPickupIndices)
            for position in 0..<track.count {
                let segment = track[position]
                guard let pickup = segment.pickup else { continue }
                let collected = field.collectedPickupIndices.contains(segment.index)
                if collectedEver.contains(segment.index), !collected {
                    Issue.record("種 \(seed): 取ったアイテム（区画 \(segment.index)）が復活した")
                }
                if collected, pickup.start > field.playerMaxX {
                    Issue.record("種 \(seed): まだ触れていないアイテム（区画 \(segment.index)）が消えた")
                }
                if pickup.start < field.playerMinX {
                    pickupsPassed.insert(segment.index)
                    if !collected { Issue.record("種 \(seed): 通り過ぎたアイテム（区画 \(segment.index)）を取っていない") }
                }
            }
        }
        #expect(field.distance >= goal, "種 \(seed): \(field.distance) までしか走れていない（\(frames) フレーム）")
        // 最後のフレームでちょうど体に触れているアイテムは、取ったがまだ通り過ぎていない。
        #expect(
            (pickupsPassed.count...(pickupsPassed.count + 1)).contains(field.collectedPickupCount),
            "種 \(seed): 取った数 \(field.collectedPickupCount) / 通り過ぎた数 \(pickupsPassed.count)"
        )
        #expect(field.collectedPickupIndices.count <= RunnerEndlessTrack.defaultCapacity, "取った印は枠のぶんしか持たない")
    }

    /// 受け入れ条件 C「区画の中身がフレームレート・ゆっくりモード・一時停止に左右されない」。
    /// 走り方（刻み・遅さ・止め方）を変えて同じ種を走らせ、途中で枠に入った区画を通し番号ごとに比べる。
    @MainActor
    @Test("刻み・ゆっくりモード・一時停止を変えて走っても、区画ごとの中身は同じ")
    func courseIsIndependentOfHowYouRun() {
        let seed: UInt64 = 42
        let goal = 12_000.0
        func observe(_ field: RunnerField, into seen: inout [Int: RunnerEndlessSegment]) {
            guard let track = field.track else { return }
            for position in 0..<track.count { seen[track[position].index] = track[position] }
        }
        func runField(dt: Double) -> [Int: RunnerEndlessSegment] {
            var field = RunnerField(endlessSeed: seed)
            var seen: [Int: RunnerEndlessSegment] = [:]
            var frames = 0
            while field.distance < goal, frames < 60 * 600 {
                frames += 1
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                if field.step(dt: dt).contains(where: \.isTerminal) { break }
                observe(field, into: &seen)
            }
            return seen
        }
        func runModel(slow: Bool) -> [Int: RunnerEndlessSegment] {
            let preference = makePreference("endless-determinism-\(slow)")
            preference.isEnabled = slow
            let model = RunnerModel(startingAt: 1, preference: preference)
            model.newEndlessGame(seed: seed)
            model.press()
            model.release()
            var seen: [Int: RunnerEndlessSegment] = [:]
            var frames = 0
            var pausedCycle = -1
            while model.distance < goal, model.phase.isRunning || model.phase == .paused, frames < 60 * 900 {
                frames += 1
                // 200 フレームほどごとに 30 フレーム止める（止めているあいだに枠が動かないことも見る）。
                // 止めるのは接地しているときだけ——一時停止は押している指を離した扱いにするので
                // （`RunnerModel.pause`）、跳んでいる最中に止めると自動操縦の全弾道が切り詰められる。
                if frames % 230 >= 200, frames / 230 != pausedCycle, model.field.isGrounded {
                    pausedCycle = frames / 230
                    model.pause()
                    let before = model.field.track
                    for _ in 0..<30 { model.tick(dt: 1.0 / 60) }
                    #expect(model.field.track == before, "一時停止中に枠が動いた")
                    model.resume()
                }
                if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
                if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
                model.tick(dt: 1.0 / 60)
                observe(model.field, into: &seen)
            }
            #expect(model.distance >= goal, "ゆっくりモード \(slow): \(model.distance) で止まった（\(model.phase)）")
            return seen
        }
        let reference = runField(dt: 1.0 / 60)
        let runs = [
            ("1/90 秒刻み", runField(dt: 1.0 / 90)),
            ("1/120 秒刻み", runField(dt: 1.0 / 120)),
            ("ゆっくりモード・一時停止あり", runModel(slow: true)),
            ("通常・一時停止あり", runModel(slow: false)),
        ]
        for (name, seen) in runs {
            let common = Set(seen.keys).intersection(reference.keys)
            #expect(common.count > 150, "\(name): 比べられた区画が少ない（\(common.count)）")
            for index in common where seen[index] != reference[index] {
                Issue.record("\(name): 区画 \(index) の中身が違う")
            }
        }
    }

    /// 跳ばなければ必ずミスになる（自動操縦が「何もしなくても勝てる」証明にならないための対照）。
    @Test("一度も跳ばなければ最初の穴でミスになる")
    func doingNothingFails() {
        var field = RunnerField(endlessSeed: 1)
        var events: [RunnerEvent] = []
        var frames = 0
        while frames < 60 * 60, !events.contains(where: { $0.isTerminal }) {
            frames += 1
            events += field.step(dt: 1.0 / 60)
        }
        #expect(events.contains(.fell))
    }
}

/// エンドレスの進行・記録・解析（#675）。
@Suite("チャリンコおじさん: エンドレスの進行と記録")
@MainActor
struct RunnerEndlessModelTests {

    /// 使い捨ての `PlayLog`（`UserDefaults.standard` を汚さない）。
    private func makePlayLog(_ suite: String) -> PlayLog {
        let name = "asobiba.runner.tests.playlog.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    /// 送信されたイベントをそのまま溜めるスパイ（`MahjongNewGameTests` と同じ形）。
    @MainActor
    private final class SpyAnalyticsService: AnalyticsService {
        private(set) var events: [AnalyticsEvent] = []
        func log(_ event: AnalyticsEvent) { events.append(event) }
    }

    @Test("モードは開始時に焼き込まれ、ステージ制の続き（ステージ番号）はそのまま残る")
    func modeIsBakedAtStart() {
        let model = RunnerModel(startingAt: 5, preference: makePreference("endless-mode"))
        #expect(model.mode == .stages)
        #expect(model.endlessSeed == nil)
        #expect(model.field.track == nil, "ステージ制は枠を持たない")
        model.newEndlessGame(seed: 42)
        #expect(model.mode == .endless)
        #expect(model.endlessSeed == 42)
        #expect(model.phase == .ready)
        #expect(model.distance == 0)
        #expect(model.field.track?.seed == 42, "コースは種から決まる")
        #expect(model.stage == RunnerEndlessCourse.stage, "コースの中身は枠が持ち、ステージは速さの式だけ")
        #expect(model.stageNumber == 5, "エンドレス中もステージ制の続きを失わない")
        #expect(!model.canResumeFromCheckpoint)
        // 「はじめから」でステージ制へ戻るとステージ 1 から。
        model.newGame(mode: .stages)
        #expect(model.mode == .stages)
        #expect(model.stageNumber == 1)
        #expect(model.stage.number == 1)
        #expect(model.field.track == nil)
    }

    @Test("ミスで 1 回が終わり、走行距離が残る。もう一度は新しい種で始まる")
    func missEndsTheRunAndRetryRollsANewCourse() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-miss"))
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        #expect(model.phase == .failed)
        #expect(model.isRunOver)
        #expect(model.distance > 0)
        #expect(model.endlessBestDistance == model.distanceMeters)
        #expect(model.didSetBestDistance, "初回は必ず更新")
        #expect(!model.canResumeFromCheckpoint, "エンドレスに広告での再開は無い")
        let generation = model.runGeneration
        model.retryStage()
        #expect(model.phase == .ready)
        #expect(model.mode == .endless)
        #expect(model.endlessSeed != 1, "同じコースを走り直す導線は無い")
        #expect(model.field.track?.seed == model.endlessSeed)
        #expect(model.runGeneration == generation + 1)
        #expect(model.distance == 0)
    }

    /// 受け入れ条件「ステージ制の記録・順位表に影響しない」。
    @Test("エンドレスの記録はステージ制の自己ベストを汚さず、別の順位表へ送られる")
    func endlessRecordIsSeparateFromStages() {
        let log = makePlayLog("separate")
        let gameCenter = SpyGameCenterService()
        let store = MemorySnapshotStore()
        let model = RunnerModel(
            services: makeServices(store: store, log: log, gameCenter: gameCenter),
            startingAt: 1, preference: makePreference("endless-record")
        )
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        let stageRecord = log.record(gameID: RunnerModel.gameID)
        #expect(stageRecord?.bestPoints == 1, "ステージ制は到達ステージ数")
        let saveCount = store.saveCount

        model.newEndlessGame(seed: 3)
        failCurrentStage(model)
        let meters = model.distanceMeters
        #expect(meters > 0)

        #expect(log.record(gameID: RunnerModel.gameID) == stageRecord, "ステージ制の記録が動いていない")
        let endless = log.record(gameID: RunnerModel.gameID, variant: RunnerMode.endless.recordVariant)
        #expect(endless?.bestPoints == meters)
        #expect(endless?.variantLabel == "エンドレス")
        #expect(endless?.losses == 1 && endless?.wins == 0, "ミスで終わった回は負けとして数える")
        #expect(gameCenter.scores == [
            GameCenterScore(leaderboardID: GameCenterLeaderboard.runnerStage, value: 1),
            GameCenterScore(leaderboardID: GameCenterLeaderboard.runnerDistance, value: meters),
        ])
        #expect(store.saveCount == saveCount, "エンドレスは中断データに書かない")
        #expect(store.load(RunnerSnapshot.self, for: RunnerModel.gameID)?.stage == 2, "ステージ制の続きはそのまま")

        // 開き直すと自己ベストを `PlayLog` から読む。
        let reopened = RunnerModel(
            services: makeServices(store: store, log: log), preference: makePreference("endless-reopen")
        )
        #expect(reopened.mode == .stages, "起動時は必ずステージ制（エンドレスは復元しない）")
        #expect(reopened.endlessBestDistance == meters)
    }

    @Test("自己ベストは伸びたときだけ更新され、同じ距離では更新しない")
    func bestDistanceUpdatesOnlyWhenLonger() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-best"))
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        let first = model.endlessBestDistance
        #expect(first != nil)
        // 同じ種・同じ操作（跳ばない）なら同じ距離でミスする。同点は更新扱いにしない。
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        #expect(model.endlessBestDistance == first)
        #expect(!model.didSetBestDistance)
    }

    /// 受け入れ条件 A「エンドレスで `phase` が `.allCleared` にならない」、I「クリア演出の分岐が発火しない」
    /// （`RunnerScene.sync` の紙吹雪は `.cleared` / `.allCleared` に入った最初のフレームでだけ出る）。
    /// #675 の固定長（400 区画 = 25,600 単位）を越えて走り続け、ミス以外で決着しないことを確かめる。
    @Test("400 区画（25,600 単位）を越えて走ってもゴールに着かず、クリアにならない", .timeLimit(.minutes(3)))
    func endlessNeverClears() {
        let log = makePlayLog("never-clears")
        let model = RunnerModel(services: makeServices(log: log), startingAt: 1, preference: makePreference("endless-never-clears"))
        model.newEndlessGame(seed: 2)
        model.press()
        model.release()
        var frames = 0
        while model.distance < 30_000, frames < 60 * 900 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            if model.phase != .running {
                Issue.record("距離 \(model.distance) で \(model.phase) になった")
                break
            }
        }
        #expect(model.distance >= 30_000)
        #expect(!model.isRunOver)
        #expect(model.recordResult == nil, "ミスするまで記録は書かない")
        #expect(log.record(gameID: RunnerModel.gameID, variant: RunnerMode.endless.recordVariant) == nil)
        // その先は無い。「次の面へ」は効かない。
        model.advanceToNextStage()
        #expect(model.phase == .running, "エンドレスに次のステージは無い")
    }

    /// 受け入れ条件 D「走行中に、区画データ用の配列の再確保が起きない」を Model の `tick` 越しに確かめる
    /// （`@Observable` のプロパティ越しに書き換えても、枠の配列が複製されないこと）。
    @Test("Model の tick で走らせても、枠の配列は再確保されない")
    func modelTickDoesNotReallocateTrack() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-no-realloc"))
        model.newEndlessGame(seed: 9)
        let address = model.field.track?.storageAddress
        #expect(address != nil)
        model.press()
        model.release()
        var frames = 0
        while model.distance < 5_000, model.phase.isRunning, frames < 60 * 300 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.distance >= 5_000)
        #expect(model.field.track?.storageAddress == address)
    }

    /// 受け入れ条件 H「記録と順位表が 7 桁以上の距離でも正しく送られる・表示される」。
    @Test("7 桁の走行距離でも記録・順位表・桁区切りが正しい")
    func sevenDigitDistanceIsRecorded() {
        let log = makePlayLog("seven-digits")
        let gameCenter = SpyGameCenterService()
        let model = RunnerModel(
            services: makeServices(log: log, gameCenter: gameCenter),
            startingAt: 1, preference: makePreference("endless-seven-digits")
        )
        model.newEndlessGame(seed: 4)
        model.press()
        model.release()
        model.fastForwardEndlessForDebug(to: 4_000_000)
        failCurrentStage(model)
        #expect(model.phase == .failed)
        let meters = model.distanceMeters
        #expect(meters >= 1_000_000 && meters < 1_001_000, "\(meters) m")
        #expect(model.endlessBestDistance == meters)
        #expect(log.record(gameID: RunnerModel.gameID, variant: RunnerMode.endless.recordVariant)?.bestPoints == meters)
        #expect(gameCenter.scores == [GameCenterScore(leaderboardID: GameCenterLeaderboard.runnerDistance, value: meters)])
        #expect(RecordFormat.number(meters) == "1,000,\(String(format: "%03d", meters - 1_000_000))")
        #expect(RunnerAccessibility.distanceLabel(meters) == "走行距離 \(meters)メートル")
        #expect(RunnerAccessibility.startEndlessLabel(bestDistance: meters).hasPrefix("エンドレス、自己ベスト 1,000,"))
    }

    /// 撮影用シナリオ（`-simulateRunner endless-*`）が狙った画で止まること。種は固定なので決定論的。
    @Test("撮影用シナリオ endless / endless-running / endless-failed / endless-far / endless-far-failed は狙った状態で止まる")
    func captureScenariosLandWhereIntended() {
        let ready = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-ready"))
        ready.applyDebugScenario("endless")
        #expect(ready.mode == .endless && ready.phase == .ready)

        let running = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-running"))
        running.applyDebugScenario("endless-running")
        #expect(running.mode == .endless && running.phase == .running)
        #expect(!running.field.isGrounded, "跳んでいる最中で止める")

        let failed = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-failed"))
        failed.applyDebugScenario("endless-failed")
        #expect(failed.mode == .endless && failed.phase == .failed)
        #expect(failed.distance > 700, "冒頭の固定区画を抜けてからミスする")

        let far = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-far"))
        far.applyDebugScenario("endless-far")
        #expect(far.mode == .endless && far.phase == .running)
        #expect(!far.field.isGrounded, "跳んでいる最中で止める")
        #expect(far.distanceMeters >= 2_500_000, "7 桁の距離（\(far.distanceMeters) m）")
        let distance = far.distance
        far.tick(dt: 1.0 / 60)
        #expect(far.distance == distance, "撮影のために止めてある")

        let farFailed = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-far-failed"))
        farFailed.applyDebugScenario("endless-far-failed")
        #expect(farFailed.mode == .endless && farFailed.phase == .failed)
        #expect(farFailed.distanceMeters >= 2_500_000 && farFailed.endlessBestDistance == farFailed.distanceMeters)
    }

    /// 長時間の実測用の `-simulateRunner endless-autopilot` は、フレームが伸びても（1/20 秒）自動操縦の判断を
    /// 1/60 秒以下の刻みで行い、テストと同じくミスせず走り続ける。
    @Test("長時間の実測用シナリオは、フレームが伸びてもミスせず走り続ける", .timeLimit(.minutes(3)))
    func autopilotScenarioSurvivesSlowFrames() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-autopilot"))
        model.applyDebugScenario("endless-autopilot")
        #expect(model.mode == .endless && model.phase == .running)
        var frames = 0
        while model.distance < 25_000, model.phase.isRunning, frames < 60 * 900 {
            frames += 1
            // 実機で計測中に起きる長いフレーム（上限の 1/20 秒）と短いフレームを混ぜる。
            model.tick(dt: frames % 3 == 0 ? 1.0 / 20 : 1.0 / 60)
        }
        #expect(model.phase == .running, "\(model.distance) で \(model.phase)")
        #expect(model.distance >= 25_000)
    }

    @Test("一時停止はエンドレスでも効く")
    func pauseWorksInEndless() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-pause"))
        model.newEndlessGame(seed: 1)
        model.press()
        model.release()
        model.tick(dt: 0.5)
        let distance = model.distance
        let track = model.field.track
        model.pause()
        #expect(model.phase == .paused)
        for _ in 0..<60 { model.tick(dt: 1.0 / 60) }
        #expect(model.distance == distance)
        #expect(model.field.track == track, "止めているあいだに区画を作らない・捨てない")
        model.resume()
        #expect(model.phase == .running)
    }

    /// `game_start` の `mode` でステージ制（`stage`・`level` はそのまま）とエンドレス（`endless`）を分ける。
    @Test("解析の game_start にモードが付き、エンドレスには level が付かない")
    func analyticsCarriesMode() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: [RunnerModel.gameID], now: { Date(timeIntervalSince1970: 0) }
        )
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = RunnerModel(services: services, startingAt: 3, preference: makePreference("endless-analytics"))
        model.newEndlessGame(seed: 1)
        model.newGame(mode: .stages)
        let starts = spy.events.compactMap { event -> (level: String?, mode: String?)? in
            if case let .gameStart(_, level, mode) = event { return (level?.parameterValue, mode?.rawValue) } else { return nil }
        }
        #expect(starts.map(\.mode) == ["stage", "endless", "stage"])
        #expect(starts.map(\.level) == ["stage-3", nil, "stage-1"])
    }

    /// `game_end` にも開始時の `mode` が焼き込まれて載る（#785 の中核。#820）。受け入れ条件 H
    /// 「エンドレスの `game_end` はミスした時だけ、1 回の走行につきちょうど 1 本（`result = loss`・
    /// `mode = endless`・`cause` 付き）」を、長く走ってからのミスと続けての 2 回で確かめる。
    @Test("エンドレスの game_end はミスした時だけ 1 走行 1 本（loss・endless・cause 付き）")
    func endlessMissSendsOneGameEndWithMode() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: [RunnerModel.gameID], now: { Date(timeIntervalSince1970: 0) }
        )
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = RunnerModel(services: services, startingAt: 1, preference: makePreference("endless-analytics-end"))
        func ends() -> [(result: AnalyticsResult, mode: AnalyticsMode?, cause: AnalyticsEndCause?)] {
            spy.events.compactMap { event in
                if case let .gameEnd(_, result, _, mode, cause) = event { return (result, mode, cause) } else { return nil }
            }
        }
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        #expect(model.phase == .failed)
        #expect(ends().count == 1)

        // 2 回目: 400 区画を越えるまで自動操縦で走り、そのあいだは game_end が増えない。そこから跳ばずにミス。
        model.retryStage()
        model.press()
        model.release()
        var frames = 0
        while model.distance < 26_000, model.phase.isRunning, frames < 60 * 900 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.distance >= 26_000)
        #expect(ends().count == 1, "走っているあいだは game_end を出さない")
        failCurrentStage(model)
        #expect(model.phase == .failed)
        // 「もう一度」は新しい 1 回の開始で、ミスした回の game_end を重ねない。
        model.retryStage()
        let all = ends()
        #expect(all.count == 2)
        for end in all {
            #expect(end.mode == .endless)
            #expect(end.result == .loss)
            #expect(end.cause != nil, "ミスの原因が載る")
        }
    }
}
