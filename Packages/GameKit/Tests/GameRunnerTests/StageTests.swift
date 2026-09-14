import Foundation
import Testing
@testable import GameRunner

/// ステージ定義の成立条件（#494）。
///
/// レイアウトは文字列なので、**打ち間違いが静かに「詰むステージ」になる**
/// （アクション枠の基盤規約 §6）。跳べる幅・越えられる高さ・間隔を機械的に確かめる。
@Suite("チャリンコおじさん: ステージ定義")
struct RunnerStageTests {

    @Test("受け入れ条件どおり 18 ステージある")
    func stageCount() {
        // #494 の受け入れ条件は「最低15ステージ」。16〜18 は乗れる台座の枠（#674）。
        #expect(RunnerRules.stageCount == 18)
        #expect(RunnerStage.all.map(\.number) == Array(1...18))
    }

    /// **1〜15 面のパターン文字列をリテラルで固定する**。
    ///
    /// 1〜6 は #626（序盤の難易度調整・会長決裁 2026-09-14）で調整した値。4〜13 は #800/#801
    /// （同日決裁）で `n` の一部を犬 `d`・イノシシ `i` に置き換えた（障害の数・位置は据え置き）。
    /// 4〜15 面は #797 で平地 1 区画を `k`（たこ焼き）に置き換えたが、`k` は障害ではないので
    /// 障害の並び・間隔・チェックポイント・速さは動いていない（`takoyakiDoesNotAffectClearability`）。
    /// 台座のために記号表・展開・接地判定へ手を入れた経緯があるので、コースが意図せず
    /// 書き換わっていないことをここで押さえる。ここが赤くなったら、既に遊ばれている面の
    /// ベストタイムの物差しが変わっている。
    @Test("1〜15 ステージのパターン文字列が固定値どおり")
    func firstFifteenStagePatternsArePinned() {
        let expected = [
            "--1-1--1-1--",
            "--1-n--1--n--",
            "--1-n-2--n-1--",
            "--1-n-t-kd1-2--",
            "--1sn-tb-2kd-t--",
            "--1sn-3-tbk2d-t--",
            "--1sn-3-t2-ikt-1--",
            "--2st-1d-3kt2-n-t--",
            "--2st1-n-3t-2kit-3--",
            "--2st1-n3-t-2dkt3-2--",
            "--t2sn3-t1t-2tk3i-tt--",
            "--t2sn3-t1t-2t3kit-t2--",
            "--t2sb3t1-t2t3kbtt2-i3--",
            "--3t2st3b-t3t2tk3tb-3t2--",
            "--3t2st3bt3t2kt3tb3-t2t3--",
        ]
        #expect(RunnerStage.all.prefix(15).map(\.pattern) == expected)
        // #797 以前の並び（`k` を平地に戻したもの）と障害が 1 つも違わないこと。
        let hazardsBefore797 = expected.map { RunnerStage.makeHazards(pattern: $0.replacingOccurrences(of: "k", with: "-")) }
        #expect(RunnerStage.all.prefix(15).map(\.hazards) == hazardsBefore797)
        // 既存 15 ステージには台座を置かない（#674 の「既存15ステージは変えない」）。
        #expect(RunnerStage.all.prefix(15).allSatisfy { $0.platforms.isEmpty })
    }

    // MARK: - 序盤の難易度（#626）

    /// 序盤（1〜6 面）の障害の総数が面番号に対して単調非減少であること。
    /// #626 は「序盤が簡単すぎる」対応なので、面が進んで障害が減る並びを作らない。
    @Test("1〜6 面の障害の総数は面が進んでも減らない")
    func earlyStageHazardCountsNeverDecrease() {
        let counts = RunnerStage.all.prefix(6).map(\.hazards.count)
        for (previous, next) in zip(counts, counts.dropFirst()) {
            #expect(previous <= next, "1〜6 面の障害数が減っている: \(counts)")
        }
    }

    /// **序盤を難しくしすぎない**（#626 会長決裁: GA4 で 1 面 → 2 面の到達が 4 割しかない）。
    /// 1〜3 面の障害数は、調整前の値（3・3・4 個）+2 以下に固定する。ここが赤くなったら、
    /// 序盤の障害を足しすぎている——数値を緩める前に決裁を取り直す。
    @Test("1〜3 面の障害数は #626 調整前の値 +2 以下")
    func earlyStagesStayGentle() {
        let before = [3, 3, 4]   // #626 調整前の 1〜3 面の障害数（`--1---1--1--` など）
        for (index, limit) in before.enumerated() {
            let stage = RunnerStage.all[index]
            #expect(
                stage.hazards.count <= limit + 2,
                "ステージ \(stage.number) の障害が \(stage.hazards.count) 個——調整前 \(limit) 個 +2 を超えている"
            )
        }
    }

    /// 1〜6 面に同じ種類の障害が 3 区画連続する並び（`nnn` / `ttt` / `bbb`）が無いこと
    /// （#626 の 2 点目「同じ障害の単調な連続を減らす」）。穴は幅ごとに記号が違い、
    /// 幅の上限は `everyHazardIsClearable` が見るので、ここでは岩と鳥だけを縛る。
    @Test("1〜6 面に同じ岩・鳥が 3 区画連続する並びが無い")
    func earlyStagesAvoidMonotonousRuns() {
        for stage in RunnerStage.all.prefix(6) {
            for symbol in ["n", "t", "b", "d", "i"] {
                #expect(
                    !stage.pattern.contains(String(repeating: symbol, count: 3)),
                    "ステージ \(stage.number) に '\(symbol)' が 3 連続している: \(stage.pattern)"
                )
            }
        }
    }

    @Test("区画数と速さがステージ番号どおりに増える")
    func rampsUp() {
        for stage in RunnerStage.all {
            #expect(
                stage.pattern.count == RunnerRules.baseSegments + stage.number - 1,
                "ステージ \(stage.number) の区画数"
            )
            let expected = RunnerRules.baseSpeed + Double(stage.number - 1) * RunnerRules.speedStep
            #expect(abs(stage.speed - expected) < 1e-9, "ステージ \(stage.number) の速さ")
        }
    }

    @Test("先頭と末尾の 2 区画は平地（走り出しとゴール前に余白がある）")
    func hasStartAndGoalClearance() {
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        for stage in RunnerStage.all {
            #expect(stage.pattern.hasPrefix("--"), "ステージ \(stage.number) の走り出し")
            #expect(stage.pattern.hasSuffix("--"), "ステージ \(stage.number) のゴール前")
            guard let first = stage.hazards.first, let last = stage.hazards.last else {
                Issue.record("ステージ \(stage.number) に障害が 1 つも無い")
                continue
            }
            #expect(first.start >= segment * 2, "ステージ \(stage.number): 最初の障害が近すぎる")
            #expect(last.end <= stage.length - segment * 2, "ステージ \(stage.number): 最後の障害がゴールに近すぎる")
        }
    }

    @Test("未知の区画記号が混ざっていない")
    func onlyKnownSymbols() {
        for stage in RunnerStage.all {
            for symbol in stage.pattern where symbol != "-" {
                let isKnown = RunnerStage.segmentSpec(symbol) != nil
                    || symbol == RunnerStage.pickupSymbol
                    || symbol == RunnerStage.takoyakiSymbol
                    || symbol == RunnerStage.platformSymbol
                    || symbol == RunnerStage.boostFloorSymbol
                #expect(isKnown, "ステージ \(stage.number) に未知の記号 '\(symbol)' がある")
            }
        }
    }

    /// **押さない（最小の）ジャンプで越えられること**を全障害について確かめる。
    /// 大ジャンプは余裕を増やす上振れなので、下限で成立していれば詰みは起きない。
    /// 動く障害（#796〜#801）は走者から見て等価な静止区間（`RunnerHazard.encounter`）で見る
    /// ——飛び立つ鳥は区画中央より少し先の長さ 7、向かってくるイノシシは長さ −2（体の中を
    /// 通り抜ける）、止まった犬は低い岩そのもの。
    /// 岩で止まったイノシシは岩と一続きなので、岩の高さのまま両方を越えきれることを見る。
    @Test("すべての障害が押さないジャンプで越えられる（動く障害は等価な静止区間で）")
    func everyHazardIsClearable() {
        let halfWidth = RunnerField.Metrics.playerHalfWidth
        for stage in RunnerStage.all {
            let range = stage.speed * RunnerRules.jumpAirTime   // 1 回のジャンプで進む距離
            for hazard in stage.hazards {
                let encounter = hazard.encounter
                switch hazard.kind {
                case .pit:
                    // 縁の手前で踏み切り、向こう側の地面へ中心が届くこと。
                    let needed = RunnerAutoPilot.lead(for: hazard, speed: stage.speed) + hazard.length
                    #expect(
                        range > needed + RunnerRules.tileWidth,
                        "ステージ \(stage.number) の穴（長さ \(hazard.length)）が跳び越せない"
                    )
                case .lowBlock, .tallBlock, .bird, .dog, .boar:
                    // 当たり判定が重なるあいだ、ずっと上端より上にいられること。
                    let window = RunnerRules.airTime(above: encounter.height + RunnerAutoPilot.clearance)
                    let overlap = (encounter.length + halfWidth * 2) / stage.speed
                    #expect(
                        window > overlap,
                        "ステージ \(stage.number) の \(hazard.kind)（高さ \(encounter.height)）を越えきれない"
                    )
                    #expect(
                        encounter.height < RunnerRules.jumpApex,
                        "ステージ \(stage.number) の \(hazard.kind) がジャンプの頂点より高い"
                    )
                }
                if hazard.kind == .boar, let stopAt = hazard.stopAt {
                    guard let rock = stage.hazards.first(where: { $0.kind.isRock && $0.end == stopAt }) else {
                        Issue.record("ステージ \(stage.number): イノシシが止まる岩（\(stopAt)）が無い")
                        continue
                    }
                    #expect(
                        RunnerEndlessCourse.isClearableWithBoarBehind(rock, speed: stage.speed),
                        "ステージ \(stage.number): 岩（\(rock.start)）とその後ろで止まったイノシシを越えきれない"
                    )
                }
            }
        }
    }

    /// 前の障害を跳んで**着地してから**次の踏み切りに入れること。
    /// 間隔が足りないと、空中のまま次の障害へ突っ込んでどう操作しても越えられない。
    ///
    /// 動く障害は等価な静止区間（`encounter`）の並びで見る。岩の右側で止まったイノシシ（#801）は
    /// その岩と一続きの障害なので、岩との間隔は問わない（`everyHazardIsClearable` が岩ごと
    /// 越えられることを見る）。
    @Test("隣り合う障害のあいだに着地して踏み切り直す余地がある")
    func hazardsAreFarEnoughApart() {
        for stage in RunnerStage.all {
            let range = stage.speed * RunnerRules.jumpAirTime
            let ordered = stage.hazards.sorted { $0.encounter.start < $1.encounter.start }
            for (previous, next) in zip(ordered, ordered.dropFirst()) {
                if next.kind == .boar, next.stopAt == previous.end, previous.kind.isRock { continue }
                let needed = range + RunnerAutoPilot.lead(for: next, speed: stage.speed)
                #expect(
                    next.encounter.start - previous.encounter.start > needed,
                    "ステージ \(stage.number): \(previous.start) と \(next.start) の障害が近すぎる"
                )
            }
        }
    }

    /// **上の 2 つの成立条件が成り立ち続けるための前提**（#569）。
    ///
    /// どちらも「1 回のジャンプで進む距離 = `stage.speed × jumpAirTime`」を土台にしている。
    /// ペダルの乗り（#569）が空中の横速度にも効くようになると、この距離が乗りの分だけ伸びて
    /// 全ステージの間隔の判定がやり直しになる。**乗りをどこまで上げても空中は基準速度**である
    /// ことを、ここで実際に走らせて確かめる。
    @Test("跳んで進む距離はペダルの乗りに左右されない")
    func jumpRangeIgnoresPedalBoost() {
        let stage = RunnerStage(number: 1, pattern: String(repeating: "-", count: 40), speed: 40)

        func jumpRange(afterRunningFor seconds: Double) -> Double {
            var field = RunnerField(stage: stage)
            var remaining = seconds
            while remaining > 0 {
                _ = field.step(dt: min(1.0 / 240, remaining))
                remaining -= 1.0 / 240
            }
            let takeOff = field.distance
            // ここでは切り詰め無しの全弾道（着地まで離さない）を測る。地形の成立条件
            // （`RunnerStageTests`）が前提にしているのもこちらの軌道なので合わせる。
            field.jump()
            while !field.isGrounded { _ = field.step(dt: 1.0 / 240) }
            return field.distance - takeOff
        }

        let cold = jumpRange(afterRunningFor: 0)          // 乗りが 1.0 のまま
        let hot = jumpRange(afterRunningFor: 10)          // 上限まで乗せてから踏み切る
        #expect(hot > 1, "計測できていない")
        #expect(abs(hot - cold) < 0.5, "乗りで飛距離が変わっている（\(cold) → \(hot)）")
        #expect(
            abs(cold - stage.speed * RunnerRules.jumpAirTime) < 0.5,
            "飛距離が speed × jumpAirTime から外れている"
        )
    }

    /// ペダルの乗りの範囲。下限 1.0 = 従来の速さで、そこを割ると全体が遅くなる。
    @Test("ペダルの乗りは 1.0 を下限、maxPedalBoost を上限に収まる")
    func pedalBoostStaysInRange() {
        #expect(RunnerRules.maxPedalBoost > 1, "乗る余地が無いとタイムが操作で動かない")
        #expect(RunnerRules.pedalGain > 0)
        #expect(RunnerRules.pedalLoss > 0)
        var field = RunnerField(stage: RunnerStage.all[0])
        #expect(field.pedalBoost == 1, "走り出しは下限から")
        for _ in 0..<600 { _ = field.step(dt: 1.0 / 60) }
        #expect(field.pedalBoost <= RunnerRules.maxPedalBoost)
        field.jump()
        for _ in 0..<600 { _ = field.step(dt: 1.0 / 60) }
        #expect(field.pedalBoost >= 1)
    }

    /// (c) ピックアップは `hazards`/`checkpoint` に一切混ざらないので、
    /// 有無で `RunnerStageTests` の成立条件（間隔・跳べる高さ）が変わらないこと。
    @Test("スピードアップアイテムの有無はステージのクリア可能性に影響しない")
    func pickupsDoNotAffectClearability() {
        let withPickups = RunnerStage(number: 1, pattern: "--n-s-t--", speed: 40)
        let withoutPickups = RunnerStage(number: 1, pattern: "--n---t--", speed: 40)
        #expect(withPickups.hazards == withoutPickups.hazards)
        #expect(withPickups.length == withoutPickups.length)
        #expect(withPickups.checkpoint == withoutPickups.checkpoint)
        #expect(withPickups.pickups.count == 1)
        #expect(withPickups.pickups.first?.kind == .speed)
        #expect(withoutPickups.pickups.isEmpty)
    }

    // MARK: - たこ焼き（#797）

    /// スピードアップ（`pickupsDoNotAffectClearability`）と同じく、たこ焼きも障害ではない
    /// ——障害の並び・長さ・チェックポイントのどれにも影響しない。
    @Test("たこ焼きの有無はステージのクリア可能性に影響しない")
    func takoyakiDoesNotAffectClearability() {
        let withTakoyaki = RunnerStage(number: 1, pattern: "--n-k-t--", speed: 40)
        let without = RunnerStage(number: 1, pattern: "--n---t--", speed: 40)
        #expect(withTakoyaki.hazards == without.hazards)
        #expect(withTakoyaki.length == without.length)
        #expect(withTakoyaki.checkpoint == without.checkpoint)
        #expect(withTakoyaki.pickups.count == 1)
        #expect(withTakoyaki.pickups.first?.kind == .invincible)
        #expect(RunnerStage.segmentSpec(RunnerStage.takoyakiSymbol) == nil, "たこ焼きは障害の記号表に無い")
    }

    /// Issue #797「出現は 4 面以降」。1〜3 面は初見の人が間合いを覚える面なので置かない。
    @Test("たこ焼きは 4 面以降にだけ置かれている")
    func takoyakiAppearsOnlyFromStageFour() {
        for stage in RunnerStage.all {
            let takoyakis = stage.pickups.filter { $0.kind == .invincible }
            if stage.number >= 4 {
                #expect(!takoyakis.isEmpty, "ステージ \(stage.number) にたこ焼きが無い")
            } else {
                #expect(takoyakis.isEmpty, "ステージ \(stage.number) にたこ焼きがある")
            }
        }
    }

    #if DEBUG
    /// 実機スクリーンショット用の置き場（#797 受け入れ条件「実機スクショ」）。
    /// 最初の岩の直前に置き、取った直後に岩を無敵で突っ切る画を撮れるようにする。
    @Test("QA用ショーケースにたこ焼きが最初の岩の手前にある")
    func showcaseHasTakoyakiBeforeTheFirstRock() {
        let showcase = RunnerStage.debugShowcase
        guard let takoyaki = showcase.pickups.first(where: { $0.kind == .invincible }),
              let firstRock = showcase.hazards.first(where: { $0.kind != .pit }) else {
            Issue.record("ショーケースにたこ焼きか岩が無い")
            return
        }
        #expect(takoyaki.start < firstRock.start, "たこ焼きは最初の岩より手前にある")
        // 取ってから岩に着くまでに無敵が切れない（区画 1 つぶん = 64 は 3 秒で進む距離より短い）。
        #expect(firstRock.start - takoyaki.start < RunnerRules.baseSpeed * RunnerRules.invincibleDuration)
    }
    #endif

    // MARK: - スピードアップ床（#672）

    /// `=` が区間へ展開され、**連続する `=` は 1 つの床にまとまる**こと。
    @Test("スピードアップ床の区画記号が区間に展開され、連続すると1つにまとまる")
    func boostFloorSymbolExpandsToMergedRuns() {
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let stage = RunnerStage(number: 1, pattern: "-==-=-", speed: 40)
        #expect(stage.boostFloors == [
            RunnerBoostFloor(start: segment, length: segment * 2),
            RunnerBoostFloor(start: segment * 4, length: segment),
        ])
        #expect(stage.hazards.isEmpty, "床は障害としては平地なので障害の数に入らない")
    }

    /// ピックアップ（`pickupsDoNotAffectClearability`）と同じく、床も成立条件に混ざらないこと。
    @Test("スピードアップ床の有無はステージのクリア可能性に影響しない")
    func boostFloorsDoNotAffectClearability() {
        let withFloors = RunnerStage(number: 1, pattern: "--n-=-t--", speed: 40)
        let withoutFloors = RunnerStage(number: 1, pattern: "--n---t--", speed: 40)
        #expect(withFloors.hazards == withoutFloors.hazards)
        #expect(withFloors.length == withoutFloors.length)
        #expect(withFloors.checkpoint == withoutFloors.checkpoint)
        #expect(withFloors.boostFloors.count == 1)
        #expect(withoutFloors.boostFloors.isEmpty)
    }

    /// #672 のスコープ: **既存15ステージには床を置かない**（本番への投入は新ステージ・#674）。
    /// 床は #674 で 16〜18 面に入ったので、ここが見るのは先頭 15 面だけ
    /// （16〜18 に床があることは `newStagesHaveBoostFloors` が別に固定する）。
    @Test("既存15ステージにはスピードアップ床を置かない")
    func existingStagesHaveNoBoostFloors() {
        for stage in RunnerStage.all.prefix(15) {
            #expect(stage.boostFloors.isEmpty, "ステージ \(stage.number) に床がある")
        }
    }

    /// 配置規則の検査対象。**QA用ショーケース（DEBUG限定）も本番と同じ規則で縛る**
    /// ——撮影用のコースだけ規則の外に置くと、そこで規則違反が起きても誰も気付かないまま
    /// 「実機で確かめたはずの並び」が本番と違う状態になる。
    private var stagesUnderLayoutRules: [RunnerStage] {
        #if DEBUG
        return RunnerStage.all + [.debugShowcase]
        #else
        return RunnerStage.all
        #endif
    }

    /// #674 のスコープ「新ステージで台座とスピードアップ床を使う」の実体。
    ///
    /// 置き方の規則も一緒に縛る:
    /// - **床の直後は素の平地**（`RunnerAutoPilot.lead` は基準速で踏み切り位置を決めており、
    ///   床の上の倍率ぶんだけ踏み切りが遅れる。区間を出れば倍率は消えるので 1 区画で足りる）
    /// - **床は台座の隣に置かない**（台座の前後は素の平地であることを
    ///   `platformsHaveFlatGroundOnBothSides` が要求している）
    ///
    /// 対象は 16 面以降と QA用ショーケース（`stagesUnderLayoutRules`）。どちらも床を持つ。
    @Test("新ステージ 16〜18 とショーケースの床は、直後が素の平地・台座の隣ではない")
    func newStagesHaveBoostFloors() {
        for stage in stagesUnderLayoutRules.dropFirst(15) {
            #expect(!stage.boostFloors.isEmpty, "ステージ \(stage.number) に床が無い")
            let symbols = Array(stage.pattern)
            for (index, symbol) in symbols.enumerated() where symbol == RunnerStage.boostFloorSymbol {
                if index < symbols.count - 1, symbols[index + 1] != RunnerStage.boostFloorSymbol {
                    #expect(
                        symbols[index + 1] == "-",
                        "ステージ \(stage.number): 床の直後（区画 \(index + 1)）が素の平地でない"
                    )
                }
                if index > 0 {
                    #expect(
                        symbols[index - 1] != RunnerStage.platformSymbol,
                        "ステージ \(stage.number): 床が台座の直後にある（区画 \(index)）"
                    )
                }
                if index < symbols.count - 1 {
                    #expect(
                        symbols[index + 1] != RunnerStage.platformSymbol,
                        "ステージ \(stage.number): 床が台座の直前にある（区画 \(index)）"
                    )
                }
            }
            // 床は台座の上には架からない（台座の上は第1弾では何も置かない平らな安全地帯）。
            for floor in stage.boostFloors {
                for platform in stage.platforms {
                    #expect(
                        !(floor.start < platform.end && platform.start < floor.end),
                        "ステージ \(stage.number): 床が台座と重なっている"
                    )
                }
            }
        }
    }

    #if DEBUG
    /// 実機スクリーンショット用の置き場（#672 受け入れ条件4）。走り出してすぐ床の上を
    /// 撮れるよう、最初の障害より手前に置いてある。
    @Test("QA用ショーケースにスピードアップ床がある")
    func showcaseHasBoostFloor() {
        let showcase = RunnerStage.debugShowcase
        #expect(showcase.boostFloors.count == 1, "連続する = は 1 つの床にまとまる")
        guard let floor = showcase.boostFloors.first,
              let firstHazard = showcase.hazards.first else {
            Issue.record("ショーケースに床か障害が無い")
            return
        }
        #expect(floor.length > 0)
        #expect(floor.end <= firstHazard.start, "床は最初の障害より手前にある")
    }
    #endif

    @Test("チェックポイントはコースの中ほどの平地にある")
    func checkpointIsOnSafeGround() {
        let margin = RunnerField.Metrics.playerWidth
        for stage in RunnerStage.all {
            let x = stage.checkpoint
            #expect(x > stage.length * 0.4 && x < stage.length * 0.9, "ステージ \(stage.number) の位置")
            for hazard in stage.hazards {
                // 動く障害（#796）は当たり判定の位置ではなく、関わる距離の範囲ごと避ける。
                let range = hazard.activeRange
                #expect(
                    !(range.lowerBound - margin < x && x < range.upperBound + margin),
                    "ステージ \(stage.number): チェックポイントが障害（\(hazard.kind) \(hazard.start)）の範囲にある"
                )
            }
            // 台座（#674）も避ける。再開は必ず地面の高さから始まるので、台座の範囲に
            // 置くと走者が台座の中にめり込んだ状態で走り出す。
            for platform in stage.platforms {
                #expect(
                    !(platform.start - margin < x && x < platform.end + margin),
                    "ステージ \(stage.number): チェックポイントが台座と重なっている"
                )
            }
        }
    }

    // MARK: - 乗れる台座（#674）

    /// 区画記号 `P` の展開。**連続する `P` は 1 つの台座にまとまる**（継ぎ目を作らない）。
    @Test("台座の区画記号が区画まるごとの台座に展開され、連続ぶんはまとまる")
    func platformSymbolExpandsToOnePlatformPerRun() {
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let stage = RunnerStage(number: 1, pattern: "-PP--P-", speed: 40)
        #expect(stage.platforms.count == 2, "連続ぶんは 1 基にまとまる")
        #expect(stage.platforms[0] == RunnerPlatform(start: segment, length: segment * 2))
        #expect(stage.platforms[1] == RunnerPlatform(start: segment * 5, length: segment))
        #expect(stage.platforms[0].end == segment * 3)
        #expect(stage.platforms[0].top == RunnerRules.platformHeight)
        // 台座は障害ではない（越えられるかの成立条件チェックの対象に入れない）。
        #expect(stage.hazards.isEmpty)
        #expect(RunnerStage.segmentSpec(RunnerStage.platformSymbol) == nil)
    }

    /// 台座の高さは「地面から 1 回のジャンプで確実に乗れる」範囲に収まっていること。
    /// 越えられない高さの台座を置くとステージが詰む（岩と同じ理由）。
    @Test("台座の上面はジャンプの頂点より低い")
    func platformIsReachableInOneJump() {
        #expect(RunnerRules.platformHeight > 0)
        #expect(
            RunnerRules.platformHeight + RunnerAutoPilot.clearance < RunnerRules.jumpApex,
            "地面から 1 回のジャンプで乗れない高さの台座は置けない"
        )
        // 2 段ぶんは届かない刻みにしてある（次弾で高さ違いの台座を足したとき、段を
        // 飛ばして登れないようにするため。第1弾は高さ 1 種類なので段差そのものが無い）。
        #expect(RunnerRules.platformHeight * 2 > RunnerRules.jumpApex)
        for stage in RunnerStage.all {
            for platform in stage.platforms {
                #expect(
                    platform.top + RunnerAutoPilot.clearance < RunnerRules.jumpApex,
                    "ステージ \(stage.number) の台座（高さ \(platform.top)）に乗れない"
                )
            }
        }
    }

    /// **台座の前後の区画は必ず平地**（#674 の配置規則）。
    ///
    /// - 左端は正面から当たればミスなので、地面から助走して踏み切る余地が要る
    /// - 右端から降りると高さぶん（`platformHeight`）落ちるあいだは空中で、踏み切れない
    ///
    /// どちらも「隣の区画に障害があると踏み切りが間に合わない」形になる。実際に走らせる
    /// `RunnerPlaythroughTests` でも落ちるが、原因が配置のどこにあるかはここでしか分からない。
    ///
    /// QA用ショーケースも対象（`stagesUnderLayoutRules`）。
    @Test("台座の前後の区画は平地になっている")
    func platformsHaveFlatGroundOnBothSides() {
        for stage in stagesUnderLayoutRules {
            let symbols = Array(stage.pattern)
            for (index, symbol) in symbols.enumerated() where symbol == RunnerStage.platformSymbol {
                if index > 0, symbols[index - 1] != RunnerStage.platformSymbol {
                    #expect(
                        symbols[index - 1] == "-",
                        "ステージ \(stage.number): 台座の手前（区画 \(index - 1)）が平地でない"
                    )
                }
                if index < symbols.count - 1, symbols[index + 1] != RunnerStage.platformSymbol {
                    #expect(
                        symbols[index + 1] == "-",
                        "ステージ \(stage.number): 台座の直後（区画 \(index + 1)）が平地でない"
                    )
                }
            }
        }
    }

    /// 台座は第 1 弾では「平らな安全地帯」——上に障害・アイテムを置かない（#674 の決裁）。
    @Test("台座の上に障害もアイテムも無い")
    func platformsCarryNothingOnTop() {
        for stage in RunnerStage.all {
            for platform in stage.platforms {
                for hazard in stage.hazards {
                    #expect(
                        !(hazard.start < platform.end && platform.start < hazard.end),
                        "ステージ \(stage.number): 台座の上に障害がある"
                    )
                }
                for pickup in stage.pickups {
                    #expect(
                        !(platform.start <= pickup.start && pickup.start < platform.end),
                        "ステージ \(stage.number): 台座の上にアイテムがある"
                    )
                }
            }
        }
    }

    /// 台座は 16〜18 にだけ置く（既存 15 面の物差しを動かさない・#674）。
    @Test("台座はステージ 16〜18 にだけ置かれている")
    func platformsOnlyAppearInTheNewStages() {
        for stage in RunnerStage.all {
            if stage.number >= 16 {
                #expect(!stage.platforms.isEmpty, "ステージ \(stage.number) に台座が無い")
            } else {
                #expect(stage.platforms.isEmpty, "ステージ \(stage.number) に台座がある")
            }
        }
    }

    /// 標識に出す到達率（会長QA「50%と書かれた旗とか」対応）。
    /// ちょうど 50% 固定ではなく、ステージごとの実際の位置がそのまま数字になること。
    @Test("チェックポイントの到達率は実際の位置から計算され、40〜90%に収まる")
    func checkpointPercentMatchesPosition() {
        var percents: Set<Int> = []
        for stage in RunnerStage.all {
            let expected = Int((stage.checkpoint / stage.length * 100).rounded())
            #expect(stage.checkpointPercent == expected, "ステージ \(stage.number) の到達率")
            #expect(
                stage.checkpointPercent >= 40 && stage.checkpointPercent <= 90,
                "ステージ \(stage.number) の到達率 \(stage.checkpointPercent)% が想定の範囲外"
            )
            percents.insert(stage.checkpointPercent)
        }
        // 全ステージが同じ割合だと「固定の数字」に見え、標識にする意味が薄れる。
        #expect(percents.count > 1, "全ステージの到達率が同じ値になっている")
    }

    /// `init` は空の `pattern` を受け取れる。`length` が 0 になると `checkpoint / length` が
    /// NaN になり、`Int(_:)` の変換でクラッシュする（CodeRabbit 指摘・Major）。
    @Test("長さ 0 のステージでも到達率の計算が落ちない")
    func checkpointPercentIsSafeForEmptyPattern() {
        let stage = RunnerStage(number: 0, pattern: "", speed: RunnerRules.baseSpeed)
        #expect(stage.length == 0)
        #expect(stage.checkpointPercent == 0)
    }
}

/// 全ステージを実際に走り切れることの実証（#494 の受け入れ条件1）。
///
/// 静的な成立条件（上の `RunnerStageTests`）だけでは「物理と Model をつないだ結果」までは
/// 保証できない。ここでは `RunnerAutoPilot`（**製品コードと同じ判断**）で 1 フレームずつ
/// 実際に走らせ、ゴールに着くことを確かめる。
@Suite("チャリンコおじさん: 全ステージのクリア可能性")
@MainActor
struct RunnerPlaythroughTests {

    /// 1 ステージを自動操縦で走らせる。戻り値は決着時の phase と経過フレーム数。
    ///
    /// `wastefulJumpAtStart` は「地形と関係なく 1 回跳ぶ」下手な操作の再現（#569）。
    /// `hopWastefully` は「地形上は要らないのに、安全な平地では毎回跳んでしまう」下手な操作の
    /// 再現（#578 の会長再QA対応）。`wastefulJumpAtStart` の 1 回きりと違い、平地が続く限り
    /// 跳び続けるので乗りが上限近くまで戻る暇が無い。
    private func play(
        stage number: Int,
        slow: Bool = false,
        wastefulJumpAtStart: Bool = false,
        hopWastefully: Bool = false
    ) -> (phase: RunnerPhase, frames: Int, just: Int) {
        let suite = "play-\(number)-\(slow)-\(wastefulJumpAtStart)-\(hopWastefully)"
        let model = RunnerModel(startingAt: number, preference: makePreference(suite))
        model.setSlowMode(slow)
        model.press()
        model.release()
        if wastefulJumpAtStart {
            model.press()
            model.release()
        }
        var frames = 0
        // `.falling` は `isRunning` に含めない（ミス直後の演出中はタップ・一時停止を無効にする
        // ための設計）ので、`.failed` に落ち着くまで回し続ける。
        while model.phase.isRunning || model.phase == .falling, frames < 60 * 300 {
            frames += 1
            // 着地するまで離さない（`RunnerAutoPilot.shouldRelease`）。無駄ジャンプ
            // （`hopWastefully`）も含め、自動操縦の跳躍はすべて切り詰め無しの全弾道で揃える
            // ——早く離して小さいホップになると、ペダルの乗りへの影響が変わり
            // タイム差を検証する既存テストの前提が崩れる。
            if RunnerAutoPilot.shouldJump(field: model.field) {
                model.press()
            } else if hopWastefully, shouldHopWastefully(field: model.field) {
                model.press()
            }
            if RunnerAutoPilot.shouldRelease(field: model.field) {
                model.release()
            }
            model.tick(dt: 1.0 / 60)
        }
        return (model.phase, frames, model.field.justLandingCount)
    }

    /// `hopWastefully` 用の判断: 次の障害の踏み切りに間に合う余地がまだあるとき、
    /// 要らないジャンプを 1 回挟んでも構わないか。**安全な間だけ**跳ぶので、
    /// 下手なりにステージはクリアできる（クラッシュするだけの操作は比較にならない）。
    ///
    /// 前方にあるもの（障害でも台座でも）は `RunnerAutoPilot.nextTarget` でまとめて見る。
    /// 動く障害（#796）も `nextTarget` がいまの位置で見るので、ここで別扱いする必要は無い。
    /// 台座（#674）を見落とすと、台座の直前の平地で跳んでしまって正面に突っ込む
    /// ——「下手だがクリアはできる操作」という、この比較実験の前提が壊れる。
    private func shouldHopWastefully(field: RunnerField) -> Bool {
        guard field.isGrounded, let target = RunnerAutoPilot.nextTarget(field: field) else { return false }
        let jumpRange = field.stage.speed * RunnerRules.jumpAirTime
        let requiredTakeoff = target.start - target.lead
        return field.distance + jumpRange + RunnerRules.tileWidth < requiredTakeoff
    }

    @Test("全ステージを最初から最後まで走り切れる")
    func everyStageIsBeatable() {
        for number in 1...RunnerRules.stageCount {
            let result = play(stage: number)
            let expected: RunnerPhase = number == RunnerRules.stageCount ? .allCleared : .cleared
            #expect(result.phase == expected, "ステージ \(number) がクリアできない（\(result.phase)）")
        }
    }

    /// **回帰テスト**: 会長QA「進まねえ」（2026-09-11）——踏み切った直後（同フレーム）に
    /// 離す「瞬間タップ」でも、穴・低い障害物は必ず越えられること。`jumpCutGraceTime`
    /// による猶予が無いと、ステージ1の最初の穴（幅8）にすら届かなかった。
    ///
    /// 高い障害物（`tallBlock`）は対象外——設計上「頂点近くを通す」必要があり、
    /// 意図的に長押しを要求する（`RunnerRules.jumpCutGraceTime` のドキュメント参照）。
    /// 岩の右側で止まったイノシシ（#801）も対象外——岩と一続きで、岩の高さで越える。
    /// 犬・向かってくるイノシシは低い岩と同じ高さ 5 なので対象（踏み切り位置は等価な静止区間
    /// `encounter` から取る。動く相手でも、踏み切ってからの弾道は同じ）。
    /// 飛び立つ鳥（#796）は逃げる相手で重なりが岩より長い（等価な長さ 7）ため、いちばん遅い
    /// 5 面では瞬間タップの窓（上端 5.5 を越えている 0.42 秒）に 0.03 秒足りない。鳥は
    /// 「普通のジャンプ」（0.15 秒のタップ）で越える障害として `shortTapClearsBirds` が別に固定する。
    @Test("瞬間タップでも、穴と低い障害物（犬・イノシシを含む）はすべて越えられる")
    func instantTapClearsPitsAndLowBlocks() {
        for stage in RunnerStage.all {
            for hazard in stage.hazards
            where hazard.kind != .tallBlock && hazard.kind != .bird && !(hazard.kind == .boar && hazard.stopAt != nil) {
                var field = RunnerField(stage: stage)
                // 踏み切り位置へ直接置く。**測っているのは「踏み切ってからの弾道だけ」**で、
                // そこまでどう走ってきたかは問いに含まれない——コースの頭から走らせる書き方は
                // 手前の地形（台座・床・別の障害）を一緒に走ることになり、赤くなったときに
                // 「この障害を瞬間タップで越えられないのか、手前で何かあったのか」が
                // 切り分けられない。助走を省いても結果は変わらない: `pedalBoost` は走り出しの
                // 1.0 に戻るが、**空中の横速度は常に `stage.speed`**（`currentSpeed`）なので、
                // 跳んだあとの軌道は乗り具合に左右されない（`jumpRangeIgnoresPedalBoost`）。
                let encounter = hazard.encounter
                field.placeForTesting(
                    distance: encounter.start - RunnerAutoPilot.lead(for: hazard, speed: stage.speed),
                    altitude: 0,
                    vy: 0
                )
                field.jump()
                field.endHold() // 同フレームで即離す＝瞬間タップ
                var events: [RunnerEvent] = []
                var frames = 0
                while frames < 3000 {
                    frames += 1
                    events += field.step(dt: 1.0 / 600)
                    if events.contains(where: { $0 == .fell || $0 == .crashed }) { break }
                    if field.isGrounded, field.distance > encounter.end { break }
                }
                #expect(
                    !events.contains(where: { $0 == .fell || $0 == .crashed }),
                    "ステージ \(stage.number) の \(hazard.kind) を瞬間タップで越えられない"
                )
            }
        }
    }

    /// 飛び立つ鳥（#796）は**0.15 秒のタップ**（瞬間タップより少しだけ長い「普通のジャンプ」）で
    /// 全ステージ越えられること。`instantTapClearsPitsAndLowBlocks` から外した理由の裏取り
    /// ——長押しでしか越えられない障害ではない。
    @Test("0.15 秒のタップで、鳥は全ステージで越えられる")
    func shortTapClearsBirds() {
        let hold = 0.15
        for stage in RunnerStage.all {
            for bird in stage.hazards where bird.kind == .bird {
                var field = RunnerField(stage: stage)
                let encounter = bird.encounter
                field.placeForTesting(
                    distance: encounter.start - RunnerAutoPilot.lead(for: bird, speed: stage.speed),
                    altitude: 0,
                    vy: 0
                )
                field.jump()
                var events: [RunnerEvent] = []
                var elapsed = 0.0
                var released = false
                while elapsed < 5 {
                    elapsed += 1.0 / 600
                    if !released, elapsed >= hold { field.endHold(); released = true }
                    events += field.step(dt: 1.0 / 600)
                    if events.contains(where: { $0 == .fell || $0 == .crashed }) { break }
                    if field.isGrounded, field.distance > encounter.end { break }
                }
                #expect(
                    !events.contains(where: { $0 == .fell || $0 == .crashed }),
                    "ステージ \(stage.number) の鳥（\(bird.start)）を 0.15 秒のタップで越えられない"
                )
            }
        }
    }

    /// ゆっくりモードは**時間の進みだけ**を遅くする（速さを落とすと飛距離が縮んで詰む）。
    /// 同じ操作でクリアでき、かかるフレーム数だけが増えることを確かめる。
    @Test("ゆっくりモードでも同じ操作でクリアでき、実時間だけが伸びる")
    func slowModeKeepsStagesBeatable() {
        for number in [1, 8, RunnerRules.stageCount] {
            let normal = play(stage: number)
            let slow = play(stage: number, slow: true)
            #expect(slow.phase == normal.phase, "ステージ \(number): ゆっくりモードで結果が変わる")
            #expect(
                Double(slow.frames) > Double(normal.frames) * 1.3,
                "ステージ \(number): ゆっくりモードで実時間が伸びていない"
            )
        }
    }

    /// 上手く漕げば 20 秒を切るステージもある（ペダルの乗り・#569）。下限を 15 秒に置いてあるのは
    /// 「タイムが縮む」ことを許しつつ、コースが短すぎて手応えが無い状態を弾くため。
    @Test("1 ステージはおおむね 15〜60 秒で走り切れる")
    func stagesAreShortEnough() {
        for number in 1...RunnerRules.stageCount {
            let seconds = Double(play(stage: number).frames) / 60
            #expect(seconds > 15 && seconds < 60, "ステージ \(number) は \(seconds) 秒")
        }
    }

    /// **クリアタイムが操作を反映すること**の実証（#569 の A 案・2026-09-10 会長決裁）。
    ///
    /// 以前は `distance += stage.speed * dt` が操作と無関係だったため、1 ステージのタイムは
    /// `length / speed` の固定値にしかならず、ベストタイムが更新される余地が無かった。
    /// 走り出しに 1 回だけ余計に跳ぶ（コース頭の 2 区画は必ず平地なので安全に跳べる）と、
    /// 空中にいるあいだの失速でゴールが遅れる。
    @Test("無駄なジャンプを 1 回挟むとクリアタイムが遅くなる")
    func wastefulJumpsCostTime() {
        for number in [1, 8, RunnerRules.stageCount] {
            let clean = play(stage: number)
            let wasteful = play(stage: number, wastefulJumpAtStart: true)
            #expect(wasteful.phase == clean.phase, "ステージ \(number): 余計なジャンプでミスになった")
            #expect(
                wasteful.frames > clean.frames,
                "ステージ \(number): 無駄に跳んでもタイムが変わらない（\(clean.frames) → \(wasteful.frames)）"
            )
        }
    }

    /// **効率よく走った場合と下手に走った場合で、クリアタイムに意味のある差が出ること**の実証
    /// （#578 実装後の会長再QA「オブジェクトの出現回数が決まってるのでスピードの概念入れても
    /// ゴールしたときの秒数に差がでない」対応）。`wastefulJumpsCostTime` の「1 回だけ余計に跳ぶ」
    /// は乗りがすぐ回復してしまい、タイム差が 1〜2% 程度しか出なかった。ここでは平地のたびに
    /// 跳んでしまう下手な操作と比べ、体感できる差（10% 以上）が出ることを確かめる。
    ///
    /// **しきい値は 10% のまま維持する**。#587 のマージ後にステージ15が 5.3% まで落ちたのは
    /// スピードアップアイテムのせいではなく、鳥が**平地区間と置き換えて**置かれ、余計な
    /// ジャンプを挟める平地が 0 区画になったため（実測: 鳥を既存の障害と置き換える配置に
    /// 直すと 10.8% に戻る。アイテムの寄与は 11.3% → 10.8% の 0.5 ポイントぶん）。
    /// **しきい値ではなくステージの配置を直す**のが正しい対処なので、`3360ea3` で 5% へ
    /// 緩めたのをここで戻している。
    @Test("平地でも跳び続ける下手な操作と比べ、クリアタイムに10%以上の差が出る")
    func inefficientPlayCostsMeaningfulTime() {
        for number in [1, 8, RunnerRules.stageCount] {
            let efficient = play(stage: number)
            let clumsy = play(stage: number, hopWastefully: true)
            #expect(clumsy.phase == efficient.phase, "ステージ \(number): 下手なジャンプでミスになった")
            let efficientSeconds = Double(efficient.frames) / 60
            let clumsySeconds = Double(clumsy.frames) / 60
            let diff = (clumsySeconds - efficientSeconds) / efficientSeconds
            #expect(
                diff > 0.1,
                "ステージ \(number): タイム差が小さすぎる（\(efficientSeconds)秒 → \(clumsySeconds)秒、\(diff * 100)%）"
            )
        }
    }

    /// 動く障害（#796 鳥・#800 犬・#801 イノシシ）は**何もしなければ当たる**こと。全ステージの
    /// 動く障害 1 つずつについて、その障害にだけ踏み切らずに走らせ（他の障害・台座は自動操縦で
    /// 越える）、その障害でミスになる（死因もその障害）ことを確かめる。置物だった鳥（#671）は
    /// 走っていれば当たらなかったので、これが「置物から障害になった」ことの実証。
    /// 岩の右側で止まったイノシシは岩と一続きで、岩を跳べば一緒に越えるので対象外。
    ///
    /// たこ焼き（`k`・#797）は跳んでも取れてしまい、取ってから 3 秒は動く障害にも当たらない
    /// （4〜6 面の犬・11 面のイノシシ・13・18 面の鳥はたこ焼きの直後にある）。ここで検めるのは
    /// 障害そのものなので、`k` を平地に戻した面で走らせる（障害の並びは `k` に依らない——
    /// `firstFifteenStagePatternsArePinned` / `takoyakiDoesNotAffectClearability`）。
    @Test("動く障害は全ステージで、跳ばなければその障害に当たる")
    func movingHazardsHitWhenIgnored() {
        for original in RunnerStage.all {
            let stage = RunnerStage(
                number: original.number,
                pattern: original.pattern.replacingOccurrences(of: String(RunnerStage.takoyakiSymbol), with: "-"),
                speed: original.speed
            )
            for hazard in stage.hazards
            where (hazard.kind == .bird || hazard.kind.isAnimal) && hazard.stopAt == nil {
                var field = RunnerField(stage: stage)
                var events: [RunnerEvent] = []
                var frames = 0
                while field.distance < hazard.activeRange.upperBound + 8, frames < 60 * 120 {
                    frames += 1
                    // 踏み切りの相手がこの障害（いまの位置）でなければ、自動操縦どおり跳ぶ。
                    if RunnerAutoPilot.shouldJump(field: field) {
                        let target = RunnerAutoPilot.nextTarget(field: field)?.start
                        let own = hazard.frame(atRunnerDistance: field.distance)?.start
                        if target != own { field.jump() }
                    }
                    if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                    events += field.step(dt: 1.0 / 60)
                    if events.contains(where: { $0.isTerminal }) { break }
                }
                #expect(
                    events.contains(.crashed) && field.lastMissCause == hazard.kind.missCause,
                    "ステージ \(stage.number) の \(hazard.kind)（\(hazard.start)）は跳ばなくても当たらない（\(events.last.map { "\($0)" } ?? "-")・死因 \(String(describing: field.lastMissCause))）"
                )
            }
        }
    }

    /// 飛び立つ鳥は**早すぎた踏み切りを 2 段目で救える**こと（#796 の受け入れ条件「遅れても
    /// 2 段ジャンプで抜けられる」の、距離決定論の下で成り立つ形——`RunnerHazardKind.bird` の doc）。
    /// 飛び立った瞬間に跳ぶと、降りてくるところに低く飛ぶ鳥がいて当たる。頂点で 2 段目を
    /// 使えば上を抜けられる。全ステージの鳥 1 羽ずつで、両方を実際に走らせて確かめる。
    @Test("飛び立った瞬間に跳ぶと当たるが、頂点で 2 段目を使えば全ステージで抜けられる")
    func doubleJumpRescuesAnEarlyJumpOverBirds() {
        for stage in RunnerStage.all {
            for bird in stage.hazards where bird.kind == .bird {
                func run(doubleJump: Bool) -> [RunnerEvent] {
                    var field = RunnerField(stage: stage)
                    field.placeForTesting(distance: bird.birdTakeoffDistance, altitude: 0, vy: 0)
                    field.jump()
                    var events: [RunnerEvent] = []
                    var jumps = 1
                    while field.distance < bird.encounter.end + RunnerField.Metrics.playerWidth {
                        if doubleJump, jumps < RunnerRules.maxJumps, field.vy <= 0 {
                            field.jump()
                            jumps += 1
                        }
                        events += field.step(dt: 1.0 / 600)
                        if events.contains(where: { $0.isTerminal }) { break }
                    }
                    return events
                }
                #expect(
                    run(doubleJump: false).contains(.crashed),
                    "ステージ \(stage.number) の鳥（\(bird.start)）: 早すぎる 1 段だけで越えられてしまう（2 段目の必然が無い）"
                )
                #expect(
                    !run(doubleJump: true).contains(.crashed),
                    "ステージ \(stage.number) の鳥（\(bird.start)）を 2 段ジャンプで越えられない"
                )
            }
        }
    }

    /// 岩の手前に置いたイノシシ（`it`・#801）は、置いたステージで**必ず岩で止まる**こと。
    /// 「岩で止まる」読みができる並びとして 9・11・12 面に置いてあるので、その並びが
    /// 意図どおり止まる配置（出現点が岩より先）になっていることを固定する。
    @Test("岩の手前に置いたイノシシは、その岩の右側で止まる")
    func boarsBeforeRocksStopAtTheRock() {
        var stopped = 0
        for stage in RunnerStage.all {
            let symbols = Array(stage.pattern)
            for (index, symbol) in symbols.enumerated() where symbol == "i" && index + 1 < symbols.count {
                let nextIsRock = symbols[index + 1] == "n" || symbols[index + 1] == "t"
                guard let boar = stage.hazards.first(where: {
                    $0.kind == .boar && Int($0.start / 64) == index
                }) else { Issue.record("ステージ \(stage.number): 区画 \(index) のイノシシが無い"); continue }
                if nextIsRock {
                    let rock = stage.hazards.first { $0.kind.isRock && Int($0.start / 64) == index + 1 }
                    #expect(boar.stopAt == rock?.end, "ステージ \(stage.number): 区画 \(index) のイノシシが次の岩で止まらない")
                    stopped += 1
                } else {
                    #expect(boar.stopAt == nil, "ステージ \(stage.number): 区画 \(index) のイノシシが岩でないもので止まる")
                }
            }
        }
        #expect(stopped >= 2, "岩で止まるイノシシが 9・12 面に置いてある")
    }

    /// **台座がコースとして機能していること**の実証（#674）。
    ///
    /// 「クリアできる」だけなら、台座に一度も乗らずに済むコース——例えば台座が短くて
    /// 跳び越せてしまう配置——でも通ってしまう。新ステージのすべての台座について、
    /// 自動操縦が実際に上面へ足を乗せて走ったことを確かめる。
    @Test("新ステージ 16〜18 では、置いたすべての台座の上を実際に走る")
    func newStagesActuallyUsePlatforms() {
        for number in 16...RunnerRules.stageCount {
            guard let stage = RunnerStage.stage(number: number) else {
                Issue.record("ステージ \(number) が無い")
                continue
            }
            #expect(!stage.platforms.isEmpty, "ステージ \(number) に台座が無い")
            var field = RunnerField(stage: stage)
            var events: [RunnerEvent] = []
            var ridden: Set<Int> = []
            var frames = 0
            while frames < 60 * 300, !events.contains(where: { $0.isTerminal }) {
                frames += 1
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                events += field.step(dt: 1.0 / 60)
                for (index, platform) in stage.platforms.enumerated()
                where field.isGrounded && field.altitude == platform.top
                    && platform.start < field.distance && field.distance < platform.end {
                    ridden.insert(index)
                }
            }
            #expect(events.contains(.reachedGoal), "ステージ \(number) を走り切れない")
            #expect(
                ridden.count == stage.platforms.count,
                "ステージ \(number): 乗っていない台座がある（\(ridden.count)/\(stage.platforms.count)）"
            )
        }
    }

    /// **台座の上では踏み切らない**（#674）。`RunnerField.nextPlatform(from:)` が
    /// 「左端がまだ前方にある台座だけを返す」と謳っている不変条件の、唯一の実証。
    ///
    /// あそこを `$0.end > x`（いま乗っている台座も返す）に緩めると、自動操縦は上面の上で
    /// 「目の前の台座へ乗るための踏み切り」を延々と繰り返す——ステージ16 だけで 8 回の
    /// 無駄ジャンプになり、跳ぶたびにペダルの乗りが落ちてタイムが伸びる。それでも**コースは
    /// クリアできてしまう**ので、完走を見ている他のテストはどれも赤くならない。
    @Test("台座の上を走っているあいだは自動操縦が踏み切らない")
    func autoPilotNeverJumpsWhileOnAPlatform() {
        for number in 16...RunnerRules.stageCount {
            guard let stage = RunnerStage.stage(number: number) else {
                Issue.record("ステージ \(number) が無い")
                continue
            }
            var field = RunnerField(stage: stage)
            var events: [RunnerEvent] = []
            var jumpsOnPlatform = 0
            var framesOnPlatform = 0
            var frames = 0
            while frames < 60 * 300, !events.contains(where: { $0.isTerminal }) {
                frames += 1
                let onPlatform = field.isGrounded && stage.platforms.contains {
                    $0.start < field.distance && field.distance < $0.end
                }
                if onPlatform { framesOnPlatform += 1 }
                if RunnerAutoPilot.shouldJump(field: field) {
                    if onPlatform { jumpsOnPlatform += 1 }
                    field.jump()
                }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                events += field.step(dt: 1.0 / 60)
            }
            #expect(framesOnPlatform > 0, "ステージ \(number): 台座の上を一度も走っていない（前提が崩れている）")
            #expect(
                jumpsOnPlatform == 0,
                "ステージ \(number): 台座の上で \(jumpsOnPlatform) 回踏み切っている"
            )
        }
    }

    /// 跳ばなければ必ずどこかでミスになる。**自動操縦が「何もしなくても勝てる」ことを
    /// 証明しているだけ**にならないための対照実験。
    @Test("一度も跳ばなければ最初の障害でミスになる")
    func doingNothingFails() {
        for number in 1...RunnerRules.stageCount {
            let model = RunnerModel(startingAt: number, preference: makePreference("idle-\(number)"))
            model.press()
            model.release()
            var frames = 0
            while model.phase.isRunning || model.phase == .falling, frames < 60 * 300 {
                frames += 1
                model.tick(dt: 1.0 / 60)
            }
            #expect(model.phase == .failed, "ステージ \(number): 跳ばずにゴールできてしまう")
        }
    }

    // MARK: - ジャスト着地（#673）

    /// タップ（踏み切って即離す＝越えられる最小のジャンプ）の弾道を 1 度だけ測った標本。
    ///
    /// 添字が `1/600` 秒刻みの経過時間、値がそのときの高さ。`jumpCutGraceTime` などの
    /// 定数が変わってもテストが勝手に追従するよう、**数式で書かずに実際に 1 回跳ばせて**測る。
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
    /// タップの滞空時間。
    private static var tapAirTime: Double { Double(tapFlight.count) * tapSampleDT }
    /// タップで足が高さ `height` 以上にいる時間。
    private static func tapTime(above height: Double) -> Double {
        Double(tapFlight.filter { $0 >= height }.count) * tapSampleDT
    }
    /// タップで足が高さ `height` に届くまでの時間。届かなければ `.infinity`。
    private static func tapRiseTime(to height: Double) -> Double {
        guard let index = tapFlight.firstIndex(where: { $0 >= height }) else { return .infinity }
        return Double(index) * tapSampleDT
    }

    /// **ジャスト着地（#673）を狙う踏み切り位置**。岩と穴に対してだけ使う。
    ///
    /// 1. 越えられる**最小のジャンプ**を選ぶ（高い障害物だけは頂点が要るので押しっぱなし）
    /// 2. 着地が右端のすぐ裏（`justLandingWindow` の真ん中）に来る位置で踏み切る
    ///
    /// 空中の速さは乗りに左右されない（`currentSpeed`）ので、踏み切り位置と弾道だけで
    /// 着地点は決まる——狙って降りられることが腕前、というのがこの仕組みの設計。
    ///
    /// **狙える窓を過ぎていたら諦めて `safeTakeOff`（自動操縦と同じ踏み切り）に戻す**
    /// 安全弁つき。前のジャンプの着地や鳥のくぐり（`RunnerAutoPilot.nextTarget` が
    /// 帯の下では nil を返す）で判断が 1 フレーム遅れると、狙いの位置を過ぎた地点から
    /// 踏み切ることになり、岩の上端を越えきれずに当たる。
    ///
    /// **実測（2026-09-13）では、この安全弁が働くのは全18ステージで 1 フレームだけ**
    /// （ステージ6・鳥は関係なく、前の着地の直後に次の穴の狙いを過ぎていた 1 回）。
    /// 外しても全ステージ緑のままなので、いま守っているのは将来のステージ追加のほう。
    /// 鳥のすぐ後ろに岩がある配置（ステージ18 の `bt`・`bn`）は、くぐり終えた時点で
    /// まだ狙いの位置に届いており、実際には発火していない。
    private func justLandingTakeOff(
        for hazard: RunnerHazard, speed: Double, from distance: Double, safeTakeOff: Double
    ) -> (x: Double, tap: Bool) {
        let half = RunnerField.Metrics.playerHalfWidth
        let clearHeight = hazard.height + RunnerAutoPilot.clearance
        // 高い障害物は頂点近くを通す設計なので、タップでは越えられない（`jumpCutGraceTime`）。
        let overlap = (hazard.length + half * 2) / speed
        let tap = hazard.kind != .pit
            ? Self.tapTime(above: clearHeight) > overlap
            : speed * Self.tapAirTime > hazard.length + half + RunnerRules.tileWidth
        let airTime = tap ? Self.tapAirTime : RunnerRules.jumpAirTime
        let range = speed * airTime
        // 狙いは窓の真ん中。フレーム（1/60 秒）の粒度で踏み切り位置がずれても収まるように。
        let desired = hazard.end + RunnerRules.justLandingWindow / 2 - range
        let earliest: Double
        let latest: Double
        switch hazard.kind {
        case .pit:
            // 早すぎると向こう岸に届かず穴へ落ちる。遅すぎると縁で踏み切れない。
            earliest = hazard.end - range + RunnerRules.tileWidth / 2
            latest = hazard.start - half
        case .lowBlock, .tallBlock, .dog:
            // 上端を越える高さに上がりきってから当たり判定へ入り、抜け切るまで落ちないこと。
            // 止まった犬（#800）は低い岩そのもの。
            let rise = tap ? Self.tapRiseTime(to: clearHeight) : RunnerRules.riseTime(to: clearHeight)
            let above = tap ? Self.tapTime(above: clearHeight) : RunnerRules.airTime(above: clearHeight)
            latest = hazard.start - half - speed * rise
            earliest = latest - speed * max(0, above - overlap) + RunnerRules.tileWidth / 2
        case .bird, .boar:
            // 動いている相手（#796/#801）は「真裏」が置いた位置に無いので狙わない（呼び出し側で弾いている）。
            return (safeTakeOff, false)
        }
        guard distance <= latest else { return (safeTakeOff, false) }
        return (min(max(desired, earliest), latest), tap)
    }

    /// **ジャスト着地（#673）を狙う操作**の再現。
    ///
    /// 土台は**自動操縦とまったく同じ判断**（`RunnerAutoPilot.nextTarget`）で、そこから
    /// **岩と穴に対してだけ**「最小のジャンプで右端の真裏へ降りる」踏み切りに差し替える。
    ///
    /// 鳥・イノシシ（#796/#801）と台座（#674）は自動操縦に任せる——動いている相手は
    /// 「越えた直後に降りる」対象ではなく、台座は越えるのではなく乗るものでジャスト着地の
    /// 対象でもない（`RunnerField.applyJustLanding`）。
    /// **台座の上に立っているあいだも狙わない**（`altitude == 0` の条件）: 上面（高さ 8）から
    /// 踏み切ると落差のぶん着地が伸び、狙いの計算が「地面から跳ぶ」前提から外れる。
    private func playAimingAtJustLanding(stage number: Int) -> (phase: RunnerPhase, frames: Int, just: Int) {
        let model = RunnerModel(startingAt: number, preference: makePreference("just-\(number)"))
        model.press()
        model.release()
        var frames = 0
        var releaseNow = false
        while model.phase.isRunning || model.phase == .falling, frames < 60 * 300 {
            frames += 1
            let field = model.field
            if field.isGrounded, let target = RunnerAutoPilot.nextTarget(field: field) {
                // 既定は自動操縦と同じ踏み切り（台座・鳥まわりはこの判断に任せる）。
                var plan = (x: target.start - target.lead, tap: false)
                if field.altitude == 0,
                   let hazard = field.nextHazard(from: field.playerMaxX),
                   hazard.kind != .bird, hazard.kind != .boar,
                   abs(hazard.start - target.start) < 1e-9 {
                    plan = justLandingTakeOff(
                        for: hazard,
                        speed: field.stage.speed,
                        from: field.distance,
                        safeTakeOff: plan.x
                    )
                }
                if field.distance >= plan.x {
                    model.press()
                    releaseNow = plan.tap
                }
            }
            // タップなら同じフレームで離す（最小のジャンプ）。押しっぱなしの場合は着地まで待つ。
            if releaseNow || model.field.isGrounded {
                model.release()
                releaseNow = false
            }
            model.tick(dt: 1.0 / 60)
        }
        return (model.phase, frames, model.field.justLandingCount)
    }

    /// **ベストタイムにスキル差が出ること**の実証（#673・#635 決裁）。
    ///
    /// 比べるのは「安全に跳ぶだけの走り」（`RunnerAutoPilot` = 地形が要求する最後の瞬間に
    /// 踏み切り、着地まで押しっぱなし。機械的に再現できる決め打ちの軌道）と、
    /// 「越えられる最小のジャンプで、障害の真裏へ降りることを狙う走り」。
    ///
    /// **実測（2026-09-12・上乗せ +0.2 / 減衰 2 秒）**:
    ///
    /// | | 1 | 8 | 15 | 16 | 17 | 18 |
    /// |---|---|---|---|---|---|---|
    /// | 差（秒） | 0.55 | 0.77 | 1.32 | 0.62 | 0.55 | 0.53 |
    /// | 差（%） | 3.7 | 3.8 | 5.3 | 2.6 | 2.3 | 2.2 |
    ///
    /// **台座・床の入ったステージ（16〜18）だけ割合が下がるのは設計どおり**——長さが
    /// 27〜29 区画に伸びたのに障害は 8〜10 個（15 面は 26 区画に 19 個）で、台座に乗って
    /// 走る区間・床を駆け抜ける区間は誰が走っても同じだから。そこでしきい値は
    /// 岩と穴だけのステージで 3%、台座・床のステージで 2% と分けてあった。
    /// #796 で 18 面の鳥 3 羽が「くぐる置物」から「跳ぶ障害」になり、誰が走っても同じ滞空が
    /// 3 回増えたぶん割合がさらに下がった（実測 1.9%）ので、16〜18 のしきい値は 1.5% に置く。
    ///
    /// `pedalBoost` への加算では 1.4〜3.0% しか出なかった（上限 1.55 に張り付いて効かない）。
    /// 上限を超える上乗せへ切り替えた経緯は `RunnerRules.justLandingOverboost` を参照。
    @Test("ジャスト着地を狙うと、安全に跳ぶだけの走りよりクリアタイムが縮む")
    func aimingAtJustLandingBeatsSafePlay() {
        // 岩と穴だけのステージ（1〜15）。
        for number in [1, 8, 15] {
            expectJustLandingPaysOff(stage: number, atLeast: 0.03)
        }
        // 台座（#674）とスピードアップ床（#672）の入ったステージ（16〜）。
        for number in [16, 17, RunnerRules.stageCount] {
            expectJustLandingPaysOff(stage: number, atLeast: 0.015)
        }
    }

    /// 上のテストの 1 ステージぶん。狙った走りが**ミスせず・ジャスト着地を決めて・速い**こと。
    private func expectJustLandingPaysOff(stage number: Int, atLeast ratio: Double) {
        let safe = play(stage: number)
        let skilled = playAimingAtJustLanding(stage: number)
        #expect(skilled.phase == safe.phase, "ステージ \(number): 狙った走りでミスになった（\(skilled.phase)）")
        // 岩（`lowBlock`/`tallBlock`）は上端からの落下距離だけで窓を外れるので、
        // ジャスト着地を決められるのは**穴の数まで**（`RunnerRules.justLandingWindow`）。
        // 実測では対象のステージすべてで穴の数ぶん全部決まっているが、しきい値は
        // その 2/3 に置く（1 フレームの粒度で 1 個取りこぼしてもテストの意図は変わらない）。
        let pits = RunnerStage.all[number - 1].hazards.filter { $0.kind == .pit }.count
        #expect(
            skilled.just >= max(1, pits * 2 / 3),
            "ステージ \(number): 穴 \(pits) 個に対してジャスト着地が \(skilled.just) 回しかない"
        )
        let safeSeconds = Double(safe.frames) / 60
        let skilledSeconds = Double(skilled.frames) / 60
        let diff = (safeSeconds - skilledSeconds) / skilledSeconds
        #expect(
            diff > ratio,
            "ステージ \(number): タイム差が小さすぎる（\(safeSeconds)秒 → \(skilledSeconds)秒、\(diff * 100)%）"
        )
    }

    /// **窓（`justLandingWindow`）の広さが正しいこと**の実証。
    ///
    /// 自動操縦は「地形が要求する最後の瞬間に踏み切って着地まで押しっぱなし」——
    /// ジャスト着地を狙わないベースラインで、これで上乗せが乗ってしまうなら窓が広すぎる
    /// （誰が走っても同じだけ乗るので、タイムにスキル差が出ない）。
    ///
    /// 実測では全18ステージ177障害のうち 1 回だけ成立する（ステージ6・跳べる最大幅の穴を
    /// 全弾道でちょうど渡り切ったもので、これは実際にジャスト着地）。
    @Test("安全に跳ぶだけの自動操縦では、ジャスト着地はほとんど起きない")
    func autoPilotRarelyEarnsJustLanding() {
        var total = 0
        for number in 1...RunnerRules.stageCount {
            let result = play(stage: number)
            total += result.just
            #expect(result.just <= 1, "ステージ \(number): 決め打ちの走りで \(result.just) 回も成立している")
        }
        #expect(total <= 2, "全ステージ合計 \(total) 回——窓が広すぎる")
    }
}
