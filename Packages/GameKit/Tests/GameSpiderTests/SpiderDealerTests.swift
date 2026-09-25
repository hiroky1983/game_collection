import Testing
import Foundation
import GameKitTestSupport
@testable import GameSpider

@Suite("配札")
struct SpiderDealerTests {

    @Test("配札はスパイダーの初期配置になる", arguments: SpiderSuitCount.allCases)
    func dealsSpiderLayout(suits: SpiderSuitCount) {
        let board = SpiderDealer.deal(seed: 12345, suits: suits)
        #expect(board.piles.count == 10)
        // 10 列へ 1 枚ずつ順に 54 枚配るので、左 4 列が 6 枚・右 6 列が 5 枚。一番上だけ表向き。
        #expect(board.piles.prefix(4).allSatisfy { $0.cards.count == 6 && $0.faceDownCount == 5 })
        #expect(board.piles.suffix(6).allSatisfy { $0.cards.count == 5 && $0.faceDownCount == 4 })
        #expect(board.stock.count == 5)
        #expect(board.stock.allSatisfy { $0.count == 10 })
        #expect(board.completed.isEmpty)
    }

    @Test("104 枚がちょうど 1 枚ずつ配られ、スートの顔ぶれが難度に合う", arguments: SpiderSuitCount.allCases)
    func usesEveryCardOnce(suits: SpiderSuitCount) {
        let board = SpiderDealer.deal(seed: 999, suits: suits)
        let all = board.piles.flatMap(\.cards) + board.stock.flatMap { $0 }
        #expect(all.count == 104)
        #expect(Set(all.map(\.id)).count == 104)
        #expect(Set(all.map(\.suit)) == Set(suits.suits))
        for suit in suits.suits {
            for rank in 1...13 {
                #expect(all.filter { $0.suit == suit && $0.rank == rank }.count == suits.copiesPerSuit)
            }
        }
    }

    @Test("同じ種はいつでも同じ配札になり、スート数が違えば別の配札になる")
    func isDeterministic() {
        #expect(SpiderDealer.deal(seed: 7, suits: .two) == SpiderDealer.deal(seed: 7, suits: .two))
        #expect(SpiderDealer.deal(seed: 7, suits: .two) != SpiderDealer.deal(seed: 8, suits: .two))
        #expect(SpiderDealer.deal(seed: 7, suits: .two) != SpiderDealer.deal(seed: 7, suits: .four))
    }

    @Test("検証済みの種は十分な数があり、重複していない", arguments: SpiderSuitCount.allCases)
    func verifiedSeedsAreUsable(suits: SpiderSuitCount) {
        let seeds = SpiderDealer.verifiedSeeds(for: suits)
        #expect(seeds.count >= (suits == .four ? 50 : 200))
        #expect(Set(seeds).count == seeds.count)
    }

    /// **`SpiderVerifiedSeeds.swift` を作り直す手順**
    ///
    /// 種の並びは「1 から順に試して、ソルバーが上限内に勝ち筋を見つけた種を採用したもの」で、
    /// `SpiderSolver.defaultMaxStates(for:)`・段の配分・評価関数を変えると結果も変わる。
    /// ソルバーに手を入れたら、**必ず作り直す**。
    ///
    /// デバッグビルドでは 1 配札あたり数秒〜数十秒かかり、4 スートは -O でも十数秒かかるので、
    /// `swift test` ではなく **`swiftc -O` で純ロジックのファイルだけを 1 バイナリにして回す**
    /// （`GameSpider` の盤・配札・ソルバーは Core すら import しないのでそのまま並べられる。
    /// 乱数と待ち行列は CoreEngine の共通部品（#916）なので、その 2 ファイルも並べる。
    /// `import CoreEngine` は `#if canImport` で囲ってあり、1 バイナリにまとめたときは飛ばされる）:
    ///
    /// ```
    /// S=Packages/GameKit/Sources/GameSpider
    /// E=Packages/GameKit/Sources/CoreEngine
    /// swiftc -O -o /tmp/spider-gen $S/SpiderCard.swift $S/SpiderRules.swift $S/SpiderBoard.swift \
    ///   $S/SpiderDealer.swift $S/SpiderSolver.swift $S/SpiderVerifiedSeeds.swift \
    ///   $E/SplitMix64.swift $E/BestFirstQueue.swift main.swift
    /// ```
    ///
    /// `main.swift` は `SpiderDealer.deal(seed:suits:)` を 1 から順に `SpiderSolver.solve` へ渡し、
    /// `isSolvable` の種と `statesExplored` を出力するだけのもの（内容はこのテストと同じ）。
    /// 出力でファイルの配列を丸ごと置き換え、実測（採用率・平均局面数・所要時間）を冒頭に書く。
    @Test("検証済みの種を作り直す",
          .enabled(if: ProcessInfo.processInfo.environment["SPIDER_REGENERATE_SEEDS"] != nil))
    func regenerateVerifiedSeeds() {
        let target = Int(ProcessInfo.processInfo.environment["SPIDER_REGENERATE_SEEDS"] ?? "20") ?? 20
        for suits in SpiderSuitCount.allCases {
            var seeds: [UInt64] = []
            var seed: UInt64 = 1
            while seeds.count < target {
                let result = SpiderSolver.solve(
                    SpiderDealer.deal(seed: seed, suits: suits),
                    maxStates: SpiderSolver.defaultMaxStates(for: suits))
                if result.isSolvable { seeds.append(seed) }
                seed += 1
            }
            print("let spiderVerifiedSeeds\(suits): [UInt64] = \(seeds)")
        }
    }

    /// 配列の中身が本当に「クリア可能」であることを、**勝ち筋を実際に指し切って**確かめる。
    /// ソルバーの結論をそのまま信じず、公開 API（`apply`）を通してクリアに到達することまで見る。
    ///
    /// 1 スートはどの種も軽い。2 スートは `SpiderVerifiedSeeds.swift` の実測で局面数の少ない種を選ぶ
    /// （デバッグビルドは -O の 10 倍ほど遅い。CI の 180 秒制限・#676 を踏まないため）。
    /// 4 スートはソルバーが -O でも十数秒かかるため**ここでは回さず**、`SpiderSolutionReplayTests` が
    /// 保存した勝ち筋の再生で確かめる。
    @Test("検証済みの種は勝ち筋を指し切ればクリアできる", arguments: [
        (SpiderSuitCount.one, 0), (.one, 199), (.two, 0),
    ])
    func verifiedSeedsAreActuallyWinnable(suits: SpiderSuitCount, index: Int) {
        let seed = SpiderDealer.verifiedSeeds(for: suits)[index]
        var board = SpiderDealer.deal(seed: seed, suits: suits)
        let result = SpiderSolver.solve(board, maxStates: SpiderSolver.defaultMaxStates(for: suits))
        guard let solution = result.solution else {
            Issue.record("種 \(seed)（\(suits)）の勝ち筋が見つからなかった（\(result.statesExplored) 局面）")
            return
        }
        for move in solution {
            let applied1 = board.apply(move)
            #expect(applied1, "勝ち筋の手 \(move) が適用できない")
        }
        #expect(board.isWon)
    }

    @Test("検証済みの種を全件確かめる",
          .enabled(if: ProcessInfo.processInfo.environment["SPIDER_VERIFY_ALL"] != nil))
    func allVerifiedSeedsAreWinnable() {
        for suits in SpiderSuitCount.allCases {
            for seed in SpiderDealer.verifiedSeeds(for: suits) {
                let board = SpiderDealer.deal(seed: seed, suits: suits)
                #expect(SpiderSolver.solve(board, maxStates: SpiderSolver.defaultMaxStates(for: suits))
                    .isSolvable, "種 \(seed)（\(suits)）")
            }
        }
    }

    /// 共通の乱数（CoreEngine の `SplitMix64`。`SpiderSeededGenerator` はその別名）の出力列そのものの固定（#916）。
    /// 同じ種の 2 インスタンスを比べるだけでは、定数を取り違えた変更を見逃す。出力が 1 ビットでも変わると
    /// 5 ゲームの検証済みの種と保存した勝ち筋がすべて無効になるので、既知の値と突き合わせる。
    /// 期待値は共通化の前の実装（`FreeCellSeededGenerator`）で出したもので、種 0 は SplitMix64 の参照実装の出力と同じ。
    @Test("共通の乱数は既知の出力列を返す")
    func splitMix64GoldenVectors() {
        let expected: [(seed: UInt64, outputs: [UInt64])] = [
            (0, [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F]),
            (42, [0xBDD7_3226_2FEB_6E95, 0x28EF_E333_B266_F103, 0x4752_6757_130F_9F52]),
        ]
        for (seed, outputs) in expected {
            var rng = SpiderSeededGenerator(seed: seed)
            let actual = outputs.indices.map { _ in rng.next() }
            #expect(actual == outputs, "種 \(seed)")
        }
    }

    /// SplitMix64 の実装が CoreEngine の 1 本だけであることの固定（#1074）。
    /// #916 の確認は `0x9E3779B97F4A7C15` の書式しか見ておらず、`0x9E37_79B9_7F4A_7C15` と書いた
    /// 同じ実装が 8 ファイルに残っていた。区切りの `_` と大文字小文字、10 進表記まで揃えて数える。
    @Test("SplitMix64 の増分定数は CoreEngine の共通部品にしか現れない")
    func splitMix64HasSingleImplementation() throws {
        let sources = SourceScan.packageRoot.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        // 空振り防止。パスの導出が外れて 0 件になると「1 ファイルだけ」を見る検査が崩れる。
        #expect(files.count > 100)
        let hits = try files.filter { file in
            let text = try String(contentsOf: file, encoding: .utf8)
                .replacingOccurrences(of: "_", with: "")
                .lowercased()
            return text.contains("9e3779b97f4a7c15") || text.contains("11400714819323198485")
        }
        .map { $0.path.replacingOccurrences(of: sources.path + "/", with: "") }
        #expect(hits == ["CoreEngine/SplitMix64.swift"])
    }

    @Test("出題は検証済みの種からしか選ばない", arguments: SpiderSuitCount.allCases)
    func randomSeedComesFromTheVerifiedList(suits: SpiderSuitCount) {
        var rng = SpiderSeededGenerator(seed: 42)
        let verified = Set(SpiderDealer.verifiedSeeds(for: suits))
        for _ in 0..<50 {
            #expect(verified.contains(SpiderDealer.randomVerifiedSeed(for: suits, using: &rng)))
        }
    }

    /// 種を固定した乱数なので結果は毎回同じ。回数は種 400 個の 1・2 スートでも、除外を外せば
    /// 必ずどこかで直前と重なる数にしてある（500 回だと 1・2 スートは緑のまま通り抜けた。#914 の変異テストで実測）。
    @Test("出題は直前の種を除いて選ぶ（#914）", arguments: SpiderSuitCount.allCases)
    func randomSeedExcludesPrevious(suits: SpiderSuitCount) {
        var rng = SpiderSeededGenerator(seed: 42)
        let verified = Set(SpiderDealer.verifiedSeeds(for: suits))
        var previous = SpiderDealer.verifiedSeeds(for: suits)[0]
        for _ in 0..<20_000 {
            let next = SpiderDealer.randomVerifiedSeed(for: suits, excluding: previous, using: &rng)
            #expect(next != previous)
            #expect(verified.contains(next))
            previous = next
        }
    }

    @Test("ほかに候補が無いときだけ直前と同じ種を返す")
    func pickFallsBackWhenOnlyPreviousRemains() {
        var rng = SpiderSeededGenerator(seed: 1)
        #expect(SpiderDealer.pick(from: [7], excluding: 7, using: &rng) == 7)
        for _ in 0..<20 {
            #expect(SpiderDealer.pick(from: [7, 8], excluding: 7, using: &rng) == 8)
        }
    }
}

@Suite("ソルバー")
struct SpiderSolverTests {

    private func card(_ suit: SpiderSuit, _ rank: Int, id: Int) -> SpiderCard {
        SpiderCard(id: id, suit: suit, rank: rank)
    }

    @Test("あと 1 手でクリアの局面は解ける")
    func solvesTrivialBoard() {
        var piles: [SpiderPile] = Array(repeating: SpiderPile(cards: []), count: 10)
        piles[0] = SpiderPile(cards: (2...13).reversed().enumerated().map { card(.spade, $1, id: $0) })
        piles[1] = SpiderPile(cards: [card(.spade, 1, id: 50)])
        let board = SpiderBoard(piles: piles, completed: Array(repeating: .spade, count: 7))
        let result = SpiderSolver.solve(board, maxStates: 100)
        #expect(result.isSolvable)
        #expect(result.solution == [.move(from: 1, cardIndex: 0, to: 0)])
    }

    @Test("行き止まりの盤面は「クリア不能」と言い切れる")
    func provesDeadEndUnsolvable() {
        let piles = (0..<10).map { SpiderPile(cards: [card(.spade, 13, id: $0)]) }
        let result = SpiderSolver.solve(SpiderBoard(piles: piles), maxStates: 1_000)
        #expect(!result.isSolvable)
        #expect(!result.hitLimit)
    }

    @Test("上限に達したら「不明」に倒れる（不能とは言わない）")
    func hitLimitIsUnknownNotUnsolvable() {
        let result = SpiderSolver.solve(SpiderDealer.deal(seed: 1, suits: .four), maxStates: 50)
        #expect(!result.isSolvable)
        #expect(result.hitLimit)
    }

    /// 1 局面の展開で上限を一気に超えると、次の局面を取り出す前にループが抜ける。
    /// そこで「打ち切った」印を落とすと、解けていないだけの盤面を「不能」と言い切ってしまう
    /// （verifier の敵対的検証で見つかった穴）。山札の無い 1 段だけの局面で再現する。
    @Test("1 局面の展開で上限を超えても「不明」に倒れる")
    func overshootInOneExpansionIsStillUnknown() {
        var piles = (0..<10).map { SpiderPile(cards: [card(.spade, 5, id: $0)]) }
        piles[0] = SpiderPile(cards: [card(.heart, 6, id: 20)])
        piles[1] = SpiderPile(cards: [card(.spade, 6, id: 21)])
        piles[2] = SpiderPile(cards: [card(.club, 6, id: 22)])
        let board = SpiderBoard(piles: piles)
        #expect(board.legalMoves.count > 2)
        let result = SpiderSolver.solve(board, maxStates: 2)
        #expect(!result.isSolvable)
        #expect(result.hitLimit)
    }

    @Test("取り消されたら「不明」に倒れる")
    func cancellationIsUnknown() {
        let result = SpiderSolver.solve(SpiderDealer.deal(seed: 1, suits: .one), maxStates: 10_000) { true }
        #expect(!result.isSolvable)
        #expect(result.hitLimit)
    }

    @Test("勝ち筋の手はすべて合法手として適用でき、配りを 5 回含む")
    func solutionIsApplicable() {
        let seed = SpiderDealer.verifiedSeeds(for: .one)[0]
        var board = SpiderDealer.deal(seed: seed, suits: .one)
        guard let solution = SpiderSolver.solve(board, maxStates: SpiderSolver.defaultMaxStates(for: .one))
            .solution else {
            Issue.record("勝ち筋が見つからなかった")
            return
        }
        #expect(solution.filter { $0 == .deal }.count == 5)
        for move in solution {
            let applied = board.apply(move)
            #expect(applied)
        }
        #expect(board.isWon)
    }

    /// 待ち行列を共通部品（`BestFirstQueue`）へ寄せたとき（#916）に、**探索順が 1 手も変わっていない**ことの固定。
    /// スパイダーは同点なら後から生まれた局面を先に見る（`.laterFirst`）。向きを取り違えると局面数が変わる。
    /// 値は共通化の前のソルバーで実測したもの。ソルバーに手を入れて変わったら、種の作り直しと合わせて更新する。
    @Test("同じ配札なら探索した局面数と勝ち筋の長さが変わらない", arguments: [
        (SpiderSuitCount.one, 25_221, 1_410), (.two, 63_109, 458),
    ])
    func searchOrderIsPinned(suits: SpiderSuitCount, states: Int, moves: Int) {
        let seed = SpiderDealer.verifiedSeeds(for: suits)[0]
        let result = SpiderSolver.solve(SpiderDealer.deal(seed: seed, suits: suits),
                                        maxStates: SpiderSolver.defaultMaxStates(for: suits))
        #expect(result.statesExplored == states, "\(suits)")
        #expect(result.solution?.count == moves, "\(suits)")
    }
}
