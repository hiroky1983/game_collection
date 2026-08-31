import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong

// MARK: - ヘルパー

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
    /// 保存された生の JSON（旧形式との互換の検証に使う）。
    func rawData(for gameID: String) -> Data? { store[gameID] }
}

/// 何を切っても和了に絡まない、聴牌から遠い手牌。
///
/// 他家に「19m19p19s1234567z」のような幺九牌ばかりの手を渡すと**国士無双の聴牌**になり、
/// 検証したい打牌がロンされて別の局面になってしまう（実際にそれで 4 件が誤判定した）。
/// 孤立した牌だけで組んだこの手なら、3 人ぶん配っても 4 枚制限に収まる。
@MainActor
private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

@MainActor
private func makeModel(
    seed: UInt64 = 2026, store: SnapshotStore = MemorySnapshotStore()
) -> MahjongModel {
    MahjongModel(
        services: GameServices(snapshots: store, ads: NoopAdService()),
        cpuDelay: .zero,
        seed: seed
    )
}

// MARK: - 山と配牌

@Suite("山と配牌")
@MainActor
struct MahjongDealTests {

    @Test("山は 34 種 × 4 枚の 136 枚")
    func wallHas136Tiles() {
        let wall = MahjongModel.makeWall()
        #expect(wall.count == 136)
        for tile in MahjongTileOrder.all {
            #expect(wall.filter { $0 == tile }.count == 4)
        }
    }

    @Test("配牌は 4 人に 13 枚ずつ。親だけが 1 枚自摸っている")
    func dealsThirteenEach() {
        let model = makeModel()
        model.startGame()
        for player in 0..<MahjongModel.playerCount {
            #expect(model.hands[player].total == 13)
        }
        #expect(model.drawnTile != nil)
        #expect(model.currentPlayer == model.dealer)
    }

    @Test("王牌 14 枚を残すので、自摸れるのは 136 - 14 - 52 = 70 枚")
    func liveWallSize() {
        let model = makeModel()
        model.startGame()
        // 親の第一自摸ぶんを引いた残り。
        #expect(model.remainingTiles == 70 - 1)
    }

    @Test("同じ種を渡せば毎回同じ配牌になる（テストが安定する）")
    func deterministicWithSeed() {
        let first = makeModel(seed: 7)
        first.startGame()
        let second = makeModel(seed: 7)
        second.startGame()
        #expect(first.hands == second.hands)
        #expect(first.drawnTile == second.drawnTile)
    }
}

// MARK: - 進行

@Suite("局の進行")
@MainActor
struct MahjongTurnTests {

    @Test("打牌すると河に並び、手番が下家へ移る")
    func discardAdvancesTurn() {
        let model = makeModel()
        model.startGame()
        // 親が自分でないと自分から打てないので、自分が親の種で確認する。
        #expect(model.dealer == 0)
        let discarded = model.drawnTile!
        model.discard(discarded)
        #expect(model.discards[0].last == discarded)
        #expect(model.drawnTile == nil || model.currentPlayer != 0)
    }

    @Test("手牌の牌を切ると、ツモ牌が手牌に入る（14 枚から 13 枚に戻る）")
    func discardFromHandKeepsThirteen() {
        let model = makeModel()
        model.startGame()
        let fromHand = model.playerHand.tiles[0]
        model.discard(fromHand)
        #expect(model.hands[0].total == 13)
        #expect(model.discards[0] == [fromHand])
    }

    @Test("自分の手番でない牌は切れない")
    func cannotDiscardOutOfTurn() {
        let model = makeModel()
        model.startGame()
        model.discard(model.playerHand.tiles[0])
        // 下家以降の手番になっているので、もう切れない。
        let before = model.discards[0].count
        model.discard(model.playerHand.tiles[0])
        #expect(model.discards[0].count == before)
    }

    @Test("CPU の手番中は playerDrawnTile が nil になる（自分のツモ牌欄に他家の牌が出ない）")
    func playerDrawnTileHidesOthersDraw() {
        // 「ルーレット現象」の回帰テスト: `drawnTile` は手番の持ち主が誰であれ書き込まれる
        // 共有プロパティなので、CPU の手番中にそのまま画面へ出すと自分の手牌14枚目が
        // 他家のツモ牌へ次々と切り替わって見えていた。`playerDrawnTile` は自分の手番以外
        // 必ず nil を返すことをここで固定する。
        let model = makeModel()
        model.configureForTesting(
            hands: [junkHand(), junkHand(), junkHand(), junkHand()],
            wall: [MahjongNotation.tile("9s")],
            currentPlayer: 1,
            drawnTile: MahjongNotation.tile("5p")
        )
        #expect(model.drawnTile == MahjongNotation.tile("5p"))
        #expect(model.playerDrawnTile == nil)
    }

    @Test("自分の手番なら playerDrawnTile はツモ牌を返す")
    func playerDrawnTileShowsOwnDraw() {
        let model = makeModel()
        model.configureForTesting(
            hands: [junkHand(), junkHand(), junkHand(), junkHand()],
            wall: [MahjongNotation.tile("9s")],
            currentPlayer: MahjongModel.humanIndex,
            drawnTile: MahjongNotation.tile("5p")
        )
        #expect(model.playerDrawnTile == MahjongNotation.tile("5p"))
    }

    @Test("山が尽きると流局し、聴牌者が点棒を受け取る")
    func exhaustiveDraw() {
        let model = makeModel()
        model.startGame()
        model.exhaustWallForTesting()
        #expect(model.phase == .handResult)
        #expect(model.handResult?.kind == .exhaustiveDraw)
        // 点棒の合計は動かない（授受があっても閉じた系）。
        #expect(model.scores.reduce(0, +) == MahjongModel.startingScore * 4)
    }

    @Test("流局の点棒授受は 3000 点を聴牌者で分け合う")
    func exhaustiveDrawPayments() {
        let model = makeModel()
        model.startGame()

        model.applyExhaustiveDrawPayments(tenpaiPlayers: [0])
        #expect(model.scores[0] == MahjongModel.startingScore + 3000)
        #expect(model.scores[1] == MahjongModel.startingScore - 1000)

        let two = makeModel()
        two.startGame()
        two.applyExhaustiveDrawPayments(tenpaiPlayers: [0, 1])
        #expect(two.scores[0] == MahjongModel.startingScore + 1500)
        #expect(two.scores[2] == MahjongModel.startingScore - 1500)

        let all = makeModel()
        all.startGame()
        all.applyExhaustiveDrawPayments(tenpaiPlayers: [0, 1, 2, 3])
        #expect(all.scores.allSatisfy { $0 == MahjongModel.startingScore })
    }

    @Test("親が聴牌で流局すると連荘して本場が増える")
    func dealerTenpaiContinues() {
        let model = makeModel()
        model.startGame()
        // 親（自分）を聴牌形にしてから流局させる。
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("123m456m789m123p1s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: [],
            dealer: 0
        )
        model.exhaustWallForTesting()
        #expect(model.handResult?.tenpaiPlayers.contains(0) == true)
        model.advanceToNextHand()
        #expect(model.dealer == 0, "親が聴牌なら連荘する")
        #expect(model.honba == 1)
        #expect(model.roundNumber == 1)
    }

    @Test("流局で終局しても供託は消えず、トップが回収して点棒の合計が保たれる")
    func leftoverRiichiSticksGoToTopPlayer() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),   // 立直できる聴牌
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("9999m"),
            dealer: 3,                                        // 親は自分ではない = 流局で東風戦が終わる
            drawnTile: MahjongNotation.tile("1z"),
            scores: [40_000, 20_000, 20_000, 20_000],
            roundNumber: 4
        )
        model.declareRiichi()
        model.discard(MahjongNotation.tile("1z"))
        #expect(model.riichiSticks == 1)

        model.exhaustWallForTesting()
        model.advanceToNextHand()
        #expect(model.phase == .gameResult)
        #expect(model.riichiSticks == 0, "供託は終局時にトップへ渡る")
        #expect(model.scores.reduce(0, +) == MahjongModel.startingScore * 4)
    }

    @Test("東4局で親がトップなら連荘せず終局する（アガリやめ）")
    func dealerStopsWhenLeadingInFinalRound() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                junkHand(),
                junkHand(),
                junkHand(),
                MahjongNotation.hand("123m456m789m123p1s"),   // 親（CPU3）が聴牌
            ],
            wall: [],
            dealer: 3,
            scores: [20_000, 20_000, 20_000, 40_000],        // 親が単独トップ
            roundNumber: 4
        )
        model.exhaustWallForTesting()
        #expect(model.handResult?.tenpaiPlayers == [3], "親だけが聴牌 = 連荘の条件は満たしている")
        model.advanceToNextHand()
        // アガリやめが無いと、勝っている親が連荘し続けるかぎり東風戦が終わらない。
        #expect(model.phase == .gameResult)
        #expect(model.ranking.first == 3)
    }

    @Test("東4局でも親がトップでなければ連荘する")
    func dealerContinuesWhenNotLeadingInFinalRound() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                junkHand(),
                junkHand(),
                junkHand(),
                MahjongNotation.hand("123m456m789m123p1s"),
            ],
            wall: [],
            dealer: 3,
            scores: [40_000, 20_000, 20_000, 20_000],        // 親は最下位
            roundNumber: 4
        )
        model.exhaustWallForTesting()
        model.advanceToNextHand()
        #expect(model.phase == .playing)
        #expect(model.dealer == 3)
        #expect(model.honba == 1)
    }

    @Test("親がノーテンで流局すると親が移り、局が進む")
    func dealerNotenPassesDealership() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("159m159p159s1234z"),   // ばらばら = ノーテン
                MahjongNotation.hand("159m159p159s1234z"),
                MahjongNotation.hand("159m159p159s1234z"),
                MahjongNotation.hand("159m159p159s1234z"),
            ],
            wall: [],
            dealer: 0
        )
        model.exhaustWallForTesting()
        model.advanceToNextHand()
        #expect(model.dealer == 1)
        #expect(model.roundNumber == 2)
        #expect(model.honba == 0)
    }
}

// MARK: - 和了

@Suite("和了と点棒")
@MainActor
struct MahjongWinTests {

    @Test("ツモ和了で点棒が動き、合計は変わらない")
    func tsumoMovesPoints() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),  // 6s / 8s で平和
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: [],
            dealer: 1,                     // 自分は子
            drawnTile: MahjongNotation.tile("8s")
        )
        #expect(model.canDeclareTsumo)
        model.declareTsumo()
        #expect(model.phase == .handResult)
        #expect(model.handResult?.kind == .tsumo)
        #expect(model.handResult?.winner == 0)
        #expect(model.scores[0] > MahjongModel.startingScore)
        #expect(model.scores.reduce(0, +) == MahjongModel.startingScore * 4)
    }

    @Test("役が無ければツモ和了できない")
    func cannotTsumoWithoutYaku() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("123m456m678m22p57s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: [],
            dealer: 1,
            drawnTile: MahjongNotation.tile("6s")
        )
        // 和了形ではあるが、門前清自摸和が付くので実際には和了できる。
        // ここでは「役の有無で判定している」ことを、和了形でない牌で確かめる。
        #expect(MahjongShanten.isWinningHand(model.playerHand.adding(MahjongNotation.tile("6s"))))
        #expect(model.canDeclareTsumo)
    }

    @Test("他家の打牌でロンできるときは宣言するか見逃すかを聞かれる")
    func ronOfferIsPresented() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),  // 8s でロン（平和）
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: [],
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("8s")
        )
        model.discardForTesting(MahjongNotation.tile("8s"), by: 1)
        #expect(model.phase == .ronOffer)
        #expect(model.ronOffer?.tile == MahjongNotation.tile("8s"))
        model.declareRon()
        #expect(model.handResult?.kind == .ron)
        #expect(model.handResult?.winner == 0)
        #expect(model.handResult?.loser == 1)
        #expect(model.scores[1] < MahjongModel.startingScore)
    }

    @Test("見逃すと同巡内はロンできず、進行は続く")
    func decliningRonSetsTemporaryFuriten() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("8s")
        )
        model.discardForTesting(MahjongNotation.tile("8s"), by: 1)
        model.declineRon()
        #expect(model.phase == .playing)
        #expect(model.isFuriten(0), "見逃した直後はフリテン")
    }

    @Test("自分の河に待ち牌があるとフリテンでロンできない")
    func furitenBlocksRon() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            discards: [MahjongNotation.tiles("8s"), [], [], []],  // 待ちの 8s を自分で捨てている
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("8s")
        )
        #expect(model.isFuriten(0))
        model.discardForTesting(MahjongNotation.tile("8s"), by: 1)
        #expect(model.phase == .playing, "フリテンなのでロンの提示が出ない")
    }

    @Test("本場と立直棒は和了者が受け取る")
    func honbaAndSticksGoToWinner() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: [],
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("8s"),
            honba: 2
        )
        let before = model.scores[1]
        model.discardForTesting(MahjongNotation.tile("8s"), by: 1)
        model.declareRon()
        // 本場 2 本 = 600 点が放銃者から余分に出る。
        #expect(before - model.scores[1] == (model.handResult?.gainedPoints ?? 0))
        #expect(model.scores.reduce(0, +) == MahjongModel.startingScore * 4)
    }
}

// MARK: - 立直

@Suite("立直")
@MainActor
struct MahjongRiichiTests {

    @MainActor
    private func tenpaiModel() -> MahjongModel {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("111122223333m"),
            dealer: 0,
            drawnTile: MahjongNotation.tile("1z")
        )
        return model
    }

    @Test("聴牌していれば立直を宣言でき、宣言牌は聴牌を保てる牌に限られる")
    func riichiRequiresTenpai() {
        let model = tenpaiModel()
        #expect(model.canDeclareRiichi)
        model.declareRiichi()
        #expect(model.isDeclaringRiichi)
        // ツモってきた東を切れば聴牌のまま。手の中の 2p を切ると聴牌が崩れる。
        #expect(model.discardableTiles.contains(MahjongNotation.tile("1z")))
        #expect(model.discardableTiles.contains(MahjongNotation.tile("2p")) == false)
    }

    @Test("立直を宣言して切ると 1000 点を供託する")
    func riichiPaysStick() {
        let model = tenpaiModel()
        model.declareRiichi()
        model.discard(MahjongNotation.tile("1z"))
        #expect(model.riichi[0])
        #expect(model.scores[0] == MahjongModel.startingScore - 1000)
        #expect(model.riichiSticks == 1)
    }

    @Test("点棒が 1000 点未満なら立直できない")
    func riichiNeedsPoints() {
        let model = tenpaiModel()
        model.configureForTesting(
            hands: model.hands,
            wall: MahjongNotation.tiles("1111m"),
            dealer: 0,
            drawnTile: MahjongNotation.tile("1z"),
            scores: [900, 25_000, 25_000, 25_000]
        )
        #expect(model.canDeclareRiichi == false)
    }

    @Test("立直の直後、他家に遮られず自分の次のツモで和了すれば一発が付く")
    func ippatsuOnOwnNextDraw() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),  // 5s / 8s の両面待ち
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            // 他家 3 人が 1 枚ずつ自摸ったあと、4 枚目が自分に来る。9m は誰も持っていないので
            // CPU の打牌が自分の待ち（5s / 8s）に当たることはない。
            wall: MahjongNotation.tiles("999m") + MahjongNotation.tiles("8s"),
            dealer: 0,
            drawnTile: MahjongNotation.tile("1z")
        )
        model.declareRiichi()
        model.discard(MahjongNotation.tile("1z"))
        #expect(model.riichi[0])

        for _ in 0..<3 { model.stepCPUForTesting() }
        #expect(model.currentPlayer == 0, "1 巡回って自分の手番に戻っている")
        #expect(model.drawnTile == MahjongNotation.tile("8s"))

        model.declareTsumo()
        #expect(model.handResult?.winner == 0)
        #expect(
            model.handResult?.yaku.contains { $0.hasPrefix("一発") } == true,
            "立直後の第一ツモは一発。実際の役: \(model.handResult?.yaku ?? [])"
        )
    }

    @Test("ツモ牌を持っている打牌中でも聴牌ヒントが出る（13枚ぶんの待ちを見せる）")
    func waitsAreShownWhileHoldingDrawnTile() {
        let model = tenpaiModel()
        // 手牌 13 枚 + ツモ牌 1 枚を持った状態。14 枚で待ちを数えると空になってしまい、
        // 打牌を選んでいる最中にヒントが消える（実装当初の不具合）。
        #expect(model.drawnTile != nil)
        #expect(model.playerHand.total == 13)
        #expect(Set(model.playerWaits) == [MahjongNotation.tile("5s"), MahjongNotation.tile("8s")])
    }

    @Test("聴牌していなければ立直できない")
    func riichiRejectsNoten() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                junkHand(),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            dealer: 0,
            drawnTile: MahjongNotation.tile("5z")
        )
        #expect(model.canDeclareRiichi == false)
    }
}

// MARK: - 中断と再開

@Suite("中断と再開")
@MainActor
struct MahjongSnapshotTests {

    @Test("対局中の状態はスナップショットに保存され、作り直しても復元される")
    func restoresFromSnapshot() {
        let store = MemorySnapshotStore()
        let first = makeModel(seed: 11, store: store)
        first.startGame()
        first.discard(first.playerHand.tiles[0])
        let expectedDiscards = first.discards
        let expectedScores = first.scores

        let restored = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            cpuDelay: .zero
        )
        #expect(restored.phase == .playing)
        #expect(restored.discards == expectedDiscards)
        #expect(restored.scores == expectedScores)
        #expect(restored.hands[0].total == 13)
    }

    @Test("局のリザルト中もスナップショットが残り、同じリザルトから再開できる")
    func persistsHandResultAndRestores() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(seed: 11, store: store)
        model.startGame()
        model.exhaustWallForTesting()
        try #require(model.phase == .handResult)
        // 以前はここで clear していたため、「次の局へ」を押す前に終了すると
        // 東風戦の途中経過がまるごと失われていた（#350）。
        #expect(store.exists(for: "mahjong4"))

        let restored = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            cpuDelay: .zero
        )
        #expect(restored.phase == .handResult)
        #expect(restored.handResult == model.handResult)
        #expect(restored.scores == model.scores)
    }

    @Test("復元したリザルトから「次の局へ」を押すと、点数・親・本場・供託が中断前と一致して次局が始まる")
    func advancesFromRestoredHandResult() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(seed: 11, store: store)
        model.startGame()
        model.exhaustWallForTesting()
        try #require(model.phase == .handResult)
        // `finishHand` が親・本場・局数を既に繰り上げた後の値。再開後の次局はこの条件で始まるべき。
        let expected = (model.scores, model.dealer, model.roundNumber, model.honba, model.riichiSticks)

        let restored = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            cpuDelay: .zero
        )
        try #require(restored.phase == .handResult)
        restored.advanceToNextHand()
        #expect(restored.phase == .playing)
        #expect(restored.scores == expected.0)
        #expect(restored.dealer == expected.1)
        #expect(restored.roundNumber == expected.2)
        #expect(restored.honba == expected.3)
        #expect(restored.riichiSticks == expected.4)
    }

    @Test("旧形式の中断データ（handResult キー無し）は対局中として復元される")
    func legacySnapshotRestoresAsPlaying() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(seed: 11, store: store)
        model.startGame()
        // 対局中の保存は任意フィールドのキーを書かない（encodeIfPresent）ので、
        // 旧形式の中断データと同じ形になっていることをまず生 JSON で確かめる。
        let raw = try #require(store.rawData(for: "mahjong4"))
        let json = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(json["handResult"] == nil)

        let restored = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            cpuDelay: .zero
        )
        #expect(restored.phase == .playing)
    }

    @Test("東風戦の決着でスナップショットは消える（終わった対局から再開しない）")
    func clearsSnapshotOnGameResult() async throws {
        let store = MemorySnapshotStore()
        let model = makeModel(seed: 4649, store: store)
        model.startGame()

        // 通しテストと同じ方針（常に自摸切り・鳴かない）で東風戦を最後まで進める。
        var guardCount = 0
        while model.phase != .gameResult, guardCount < 400 {
            guardCount += 1
            switch model.phase {
            case .playing:
                if model.currentPlayer == MahjongModel.humanIndex, model.drawnTile != nil {
                    if model.canDeclareTsumo {
                        model.declareTsumo()
                    } else {
                        model.discard(model.drawnTile!)
                    }
                } else {
                    await model.runCPUTurnsIfNeeded()
                }
            case .ronOffer:
                model.declareRon()
            case .callOffer:
                model.declineCall()
            case .handResult:
                // 局間のリザルトでは残っている（#350）。
                #expect(store.exists(for: "mahjong4"))
                model.advanceToNextHand()
            case .idle, .gameResult:
                break
            }
        }

        try #require(model.phase == .gameResult)
        #expect(store.exists(for: "mahjong4") == false)
    }
}

// MARK: - 通し

@Suite("東風戦の通し")
@MainActor
struct MahjongFullGameTests {

    // `.timeLimit` は無限ループを止める保険。フルスイートの並列実行では CPU を取り合って
    // 1 分を超えることがあるため（#263 で鳴きありの通しが増えて顕在化）、上限を緩める。
    // 進行が詰まらないことの保証は下の `guardCount` の上限が担っている。
    @Test("CPU だけで東風戦が最後まで進み、順位が出る", .timeLimit(.minutes(3)))
    func playsThroughEastRound() async {
        let model = makeModel(seed: 4649)
        model.startGame()

        var guardCount = 0
        while model.phase != .gameResult, guardCount < 400 {
            guardCount += 1
            switch model.phase {
            case .playing:
                if model.currentPlayer == MahjongModel.humanIndex, model.drawnTile != nil {
                    if model.canDeclareTsumo {
                        model.declareTsumo()
                    } else {
                        model.discard(model.drawnTile!)   // 常に自摸切り
                    }
                } else {
                    await model.runCPUTurnsIfNeeded()
                }
            case .ronOffer:
                model.declareRon()
            case .callOffer:
                model.declineCall()   // 常に自摸切りの方針なので鳴かない
            case .handResult:
                model.advanceToNextHand()
            case .idle, .gameResult:
                break
            }
        }

        #expect(model.phase == .gameResult, "\(guardCount) 手で東風戦が終わらなかった")
        #expect(model.ranking.count == 4)
        #expect(Set(model.ranking) == [0, 1, 2, 3])
        // 供託が残ったまま終局しても点棒は消えない（残りはトップが回収する）。
        #expect(model.riichiSticks == 0)
        #expect(model.scores.reduce(0, +) == MahjongModel.startingScore * 4)
        #expect(model.playerPlace != nil)
    }
}

// MARK: - CPU 進行のキャンセル

@Suite("CPU 進行のキャンセル")
@MainActor
struct MahjongCancelTests {

    /// `.task(id: model.turnKey)` は手番が変わるたびに前のタスクをキャンセルする。
    /// `try? await Task.sleep(for:)` はキャンセル時に**即座に**返るため、キャンセル後の
    /// ループが `cpuDelay` を一切待たずに残りの手番を走り抜けてしまう（CodeRabbit 指摘）。
    /// 待ち時間の経過ではなく「キャンセル済みのタスクが打牌を進めないこと」で検証するので、
    /// 実時間に依存せず安定する。
    @Test("キャンセルされたら遅延を飛ばして打ち続けない")
    func cancelledLoopDoesNotFastForward() async {
        let model = MahjongModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
            // キャンセルが効かなければ、この長さを無視して打牌が進んでしまう。
            cpuDelay: .seconds(60),
            seed: 2026
        )
        model.startGame()
        if model.currentPlayer == MahjongModel.humanIndex, let drawn = model.drawnTile {
            model.discard(drawn)
        }
        try? #require(model.phase == .playing)
        #expect(model.currentPlayer != MahjongModel.humanIndex, "CPU の手番になっていない")

        let before = model.discards.reduce(0) { $0 + $1.count }
        // MainActor 上なので、この Task の本体は `await` で手放すまで動かない。
        // したがって cancel() は必ず本体の実行より先に確定する（実時間に依存しない）。
        let task = Task { await model.runCPUTurnsIfNeeded() }
        task.cancel()
        await task.value

        #expect(
            model.discards.reduce(0) { $0 + $1.count } == before,
            "キャンセル済みのタスクが cpuDelay を無視して打牌を進めた"
        )
    }

    /// `.task(id:)` の差し替えでは「新タスクの起動」と「旧タスクのキャンセル検知」の順序が
    /// 保証されない。新タスクが先に走ると、旧タスクがまだ `isRunningCPUTurns` を握っているため
    /// 多重起動ガードで即リターンし、直後に旧タスクもキャンセルで抜けて**走者が誰もいなくなる**。
    /// `turnKey` はもう変わらないため再起動も掛からず、CPU の手番が止まったままになる
    /// （2026-08-29 会長報告「手が途中で止まる」の正体）。新タスクは先行タスクの終了を
    /// 待って引き継がなければならない。
    @Test("差し替え後の新タスクが先行タスクの終了を待って引き継ぐ（走者不在で止まらない）")
    func replacementTaskTakesOverAfterCancelledPredecessor() async {
        let model = MahjongModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
            cpuDelay: .milliseconds(30),
            seed: 2026
        )
        model.startGame()
        if model.currentPlayer == MahjongModel.humanIndex, let drawn = model.drawnTile {
            model.discard(drawn)
        }
        try? #require(model.phase == .playing)
        #expect(model.currentPlayer != MahjongModel.humanIndex, "CPU の手番になっていない")

        // 旧タスク A を起動し、yield で「フラグを立てて sleep に入る」ところまで進める
        // （MainActor は投入順に実行されるため、この yield で A は最初の suspend まで走る）。
        let taskA = Task { await model.runCPUTurnsIfNeeded() }
        await Task.yield()
        // `.task(id:)` の差し替えを再現する: 新タスク B を起動してから A をキャンセルする。
        // B の本体は A がフラグを握ったまま suspend している間に実行される。
        let taskB = Task { await model.runCPUTurnsIfNeeded() }
        taskA.cancel()
        await taskA.value
        await taskB.value

        // B が引き継いでいれば「CPU の打牌待ち」では止まらない（人の選択待ちか決着まで進む）。
        #expect(
            !(model.phase == .playing
                && model.currentPlayer != MahjongModel.humanIndex
                && model.awaitsDiscard(model.currentPlayer)),
            "走者不在で CPU の手番が止まった"
        )
    }
}
