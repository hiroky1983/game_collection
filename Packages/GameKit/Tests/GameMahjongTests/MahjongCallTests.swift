import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong

// MARK: - ヘルパー

private final class MemoryStore: SnapshotStore, @unchecked Sendable {
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
}

/// 鳴きにも和了にも絡まない手牌（`MahjongModelTests` と同じ考え方）。
/// 同じ牌が 2 枚無いのでポンできず、連番も無いのでチーもできない。
@MainActor
private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

@MainActor
private func makeModel(store: SnapshotStore = MemoryStore()) -> MahjongModel {
    MahjongModel(
        services: GameServices(snapshots: store, ads: NoopAdService()),
        cpuDelay: .zero,
        seed: 2026
    )
}

/// 王牌 14 枚。前から `[表ドラ, 裏ドラ] × 5`、末尾 4 枚が嶺上牌。
@MainActor
private func deadWall(rinshan: [MahjongTile] = [], indicator: MahjongTile = .wind(0)) -> [MahjongTile] {
    var tiles = Array(repeating: indicator, count: MahjongModel.deadWallCount)
    // 嶺上牌は末尾から順に引かれるので、渡された順に引かれるよう後ろから詰める。
    for (offset, tile) in rinshan.enumerated() {
        tiles[tiles.count - 1 - offset] = tile
    }
    return tiles
}

// MARK: - 鳴きの成立

@Suite("鳴きの成立")
@MainActor
struct MahjongCallFormationTests {

    @Test("ポンすると手牌から 2 枚抜けて明刻として晒され、自分の手番になる")
    func ponTakesTwoFromHandAndStealsTurn() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("55m234p567p234s99s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("5m")
        )
        model.discardForTesting(MahjongNotation.tile("5m"), by: 1)

        #expect(model.phase == .callOffer)
        #expect(model.callOffer?.options.map(\.kind) == [.pon], "ポンだけが提示される")

        model.acceptCall(model.callOffer!.options[0])

        #expect(model.playerMelds.count == 1)
        #expect(model.playerMelds[0].kind == .pon)
        #expect(model.playerMelds[0].tiles == MahjongNotation.tiles("555m"))
        #expect(model.playerMelds[0].from == 1)
        #expect(model.playerHand == MahjongNotation.hand("234p567p234s99s"), "手牌から 5m が 2 枚抜ける")
        #expect(model.discards[1].isEmpty, "鳴かれた牌は河から取り上げられる")
        // 本来は 1 → 2 と回るところを、鳴いた 0 が割り込んで手番を取る。
        #expect(model.currentPlayer == MahjongModel.humanIndex)
        #expect(model.drawnTile == nil, "ポンでは自摸らずそのまま切る")
        #expect(model.isPlayerTurn, "ツモ牌が無くても切る番として扱う")
    }

    @Test("チーは上家の捨て牌にだけ反応し、順子として晒される")
    func chiOnlyFromLeftPlayer() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("34m234p567p99s123z"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 3,
            dealer: 3,
            drawnTile: MahjongNotation.tile("5m")
        )
        // 3 は 0 の上家（0 は 3 の下家）なのでチーできる。
        model.discardForTesting(MahjongNotation.tile("5m"), by: 3)

        #expect(model.phase == .callOffer)
        #expect(model.callOffer?.options.map(\.kind) == [.chi])
        model.acceptCall(model.callOffer!.options[0])

        #expect(model.playerMelds[0].kind == .chi)
        #expect(model.playerMelds[0].tiles == MahjongNotation.tiles("345m"))
        #expect(model.playerHand == MahjongNotation.hand("234p567p99s123z"))
        #expect(model.currentPlayer == MahjongModel.humanIndex)
    }

    @Test("上家以外の捨て牌はチーできない")
    func chiIsNotOfferedFromOtherPlayers() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("34m234p567p99s123z"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("5m")
        )
        model.discardForTesting(MahjongNotation.tile("5m"), by: 1)
        #expect(model.phase == .playing, "対面の捨て牌はチーできないので提示されない")
        #expect(model.playerMelds.isEmpty)
    }

    @Test("チーの取り方が複数あるときは全通り提示される")
    func chiOffersEveryInterpretation() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            // 3m4m6m7m を持っていれば 5m は 345m / 456m / 567m の 3 通りで鳴ける。
            hands: [
                MahjongNotation.hand("3467m234p567p99s1z"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 3,
            dealer: 3,
            drawnTile: MahjongNotation.tile("5m")
        )
        model.discardForTesting(MahjongNotation.tile("5m"), by: 3)
        let options = model.callOffer?.options ?? []
        #expect(options.count == 3)
        #expect(options.map(\.tile) == MahjongNotation.tiles("345m"), "順子の先頭は 3m・4m・5m")
    }

    @Test("スルーすると鳴かずに進み、手番は捨てた人の下家へ移る")
    func decliningCallContinuesTheTurn() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("55m234p567p234s99s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("5m")
        )
        model.discardForTesting(MahjongNotation.tile("5m"), by: 1)
        model.declineCall()

        #expect(model.phase == .playing)
        #expect(model.playerMelds.isEmpty)
        #expect(model.discards[1] == MahjongNotation.tiles("5m"), "鳴かなければ河に残る")
        #expect(model.currentPlayer == 2, "本来の順どおり下家へ")
    }

    @Test("大明槓は 3 枚を晒して嶺上牌を引き、新しいドラがめくれる")
    func openKanDrawsFromDeadWall() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("555m234p567p23s99s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m2222m"),
            deadWall: deadWall(rinshan: MahjongNotation.tiles("9p")),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("5m")
        )
        let remainingBefore = model.remainingTiles
        model.discardForTesting(MahjongNotation.tile("5m"), by: 1)

        #expect(model.callOffer?.options.map(\.kind) == [.openKan, .pon], "カンのほうが先に並ぶ")
        model.acceptCall(model.callOffer!.options[0])

        #expect(model.playerMelds[0].kind == .openKan)
        #expect(model.playerMelds[0].tiles.count == 4)
        #expect(model.playerHand == MahjongNotation.hand("234p567p23s99s"))
        #expect(model.drawnTile == MahjongNotation.tile("9p"), "王牌の末尾から嶺上牌を引く")
        #expect(model.doraIndicators.count == 2, "カンで新ドラがめくれる")
        #expect(model.remainingTiles == remainingBefore - 1, "嶺上牌のぶん自摸れる枚数が減る")
    }

    @Test("暗槓は自分の手番で宣言でき、門前のまま嶺上牌を引く")
    func closedKanKeepsConcealment() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("5555m234p567p99s1z"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m2222m"),
            deadWall: deadWall(rinshan: MahjongNotation.tiles("9p")),
            currentPlayer: 0,
            dealer: 0,
            drawnTile: MahjongNotation.tile("3s")
        )
        let kans = model.availableSelfKans
        #expect(kans.count == 1)
        #expect(kans[0].kind == .closedKan)

        model.declareKan(kans[0])
        #expect(model.playerMelds[0].kind == .closedKan)
        #expect(model.playerMelds[0].breaksConcealment == false)
        #expect(model.playerHand == MahjongNotation.hand("234p567p99s1z3s"), "ツモ牌が手牌に入り 5m が 4 枚抜ける")
        #expect(model.drawnTile == MahjongNotation.tile("9p"))
        #expect(model.doraIndicators.count == 2)
    }

    @Test("加槓はポン済みの刻子を槓子に差し替える（副露の数は増えない）")
    func addedKanReplacesThePon() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234p567p99s1z2z3z4z"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m2222m"),
            deadWall: deadWall(rinshan: MahjongNotation.tiles("9p")),
            currentPlayer: 0,
            dealer: 0,
            drawnTile: MahjongNotation.tile("5m"),
            melds: [
                [MahjongCall(
                    kind: .pon, tile: MahjongNotation.tile("5m"),
                    from: 2, claimedTile: MahjongNotation.tile("5m")
                )],
                [], [], [],
            ]
        )
        let kans = model.availableSelfKans
        #expect(kans.map(\.kind) == [.addedKan])

        model.declareKan(kans[0])
        #expect(model.playerMelds.count == 1, "ポンが加槓に置き換わるだけ")
        #expect(model.playerMelds[0].kind == .addedKan)
        #expect(model.playerMelds[0].tiles.count == 4)
        #expect(model.drawnTile == MahjongNotation.tile("9p"))
    }

    @Test("立直している人は鳴けない")
    func riichiPlayerCannotCall() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("55m234p567p99s123z"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("5m"),
            riichi: [true, false, false, false]
        )
        model.discardForTesting(MahjongNotation.tile("5m"), by: 1)
        #expect(model.phase == .playing, "立直後は手牌を変えられないので鳴きは提示されない")
    }

    @Test("鳴いたあとは立直できない。暗槓だけなら門前のままなので宣言できる")
    func callingBlocksRiichi() {
        let melds = [
            MahjongCall(kind: .pon, tile: MahjongNotation.tile("5m"), from: 2,
                        claimedTile: MahjongNotation.tile("5m")),
        ]
        let openModel = makeModel()
        openModel.startGame()
        openModel.configureForTesting(
            hands: [MahjongNotation.hand("234p567p234s99s"), junkHand(), junkHand(), junkHand()],
            wall: MahjongNotation.tiles("1111m2222m3333m4444m"),
            currentPlayer: 0,
            drawnTile: MahjongNotation.tile("1z"),
            melds: [melds, [], [], []]
        )
        #expect(openModel.canDeclareRiichi == false)

        let closedModel = makeModel()
        closedModel.startGame()
        closedModel.configureForTesting(
            hands: [MahjongNotation.hand("234p567p234s99s"), junkHand(), junkHand(), junkHand()],
            wall: MahjongNotation.tiles("1111m2222m3333m4444m"),
            currentPlayer: 0,
            drawnTile: MahjongNotation.tile("1z"),
            melds: [
                [MahjongCall(kind: .closedKan, tile: MahjongNotation.tile("5m"))], [], [], [],
            ]
        )
        #expect(closedModel.canDeclareRiichi, "暗槓は門前を崩さない")
    }

    @Test("鳴かれて河から消えても、捨てた事実は残るのでフリテンは続く")
    func furitenSurvivesWhenTheDiscardIsCalled() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234m567m22p345p67s"),   // 5s / 8s 待ち
                MahjongNotation.hand("88s11z22z345p678p3s"),  // 8s をポンすると聴牌に近づく
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m2222m"),
            currentPlayer: 0,
            dealer: 0,
            drawnTile: MahjongNotation.tile("8s")
        )
        model.discard(MahjongNotation.tile("8s"))

        #expect(model.melds[1].map(\.kind) == [.pon], "CPU1 が 8s をポンする")
        #expect(model.discards[MahjongModel.humanIndex].isEmpty, "鳴かれた牌は河から消える")
        #expect(model.isFuriten(MahjongModel.humanIndex), "捨てた事実は消えないのでフリテンは続く")
    }

    @Test("鳴きを含む局面を中断して再開しても副露が残る")
    func snapshotKeepsMelds() {
        let store = MemoryStore()
        let model = makeModel(store: store)
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("55m234p567p234s99s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m2222m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("5m")
        )
        model.discardForTesting(MahjongNotation.tile("5m"), by: 1)
        model.acceptCall(model.callOffer!.options[0])

        let resumed = makeModel(store: store)
        #expect(resumed.playerMelds.map(\.kind) == [.pon])
        #expect(resumed.playerHand == MahjongNotation.hand("234p567p234s99s"))
        #expect(resumed.currentPlayer == MahjongModel.humanIndex)
        #expect(resumed.isPlayerTurn, "再開しても「切る番」のまま止まらない")
    }

    @Test("加槓は槍槓で横取りできる")
    func addedKanCanBeRobbed() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("234p567p99s1z2z3z4z"),
                MahjongNotation.hand("34m234p567p234s99s"),   // 2m / 5m 待ち
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m2222m"),
            deadWall: deadWall(rinshan: MahjongNotation.tiles("9p")),
            currentPlayer: 0,
            dealer: 0,
            drawnTile: MahjongNotation.tile("5m"),
            melds: [
                [MahjongCall(
                    kind: .pon, tile: MahjongNotation.tile("5m"),
                    from: 2, claimedTile: MahjongNotation.tile("5m")
                )],
                [], [], [],
            ]
        )
        model.declareKan(model.availableSelfKans[0])

        #expect(model.handResult?.kind == .ron)
        #expect(model.handResult?.winner == 1)
        #expect(model.handResult?.loser == MahjongModel.humanIndex)
        #expect(model.handResult?.yaku.contains { $0.hasPrefix("槍槓") } == true)
    }

    @Test("嶺上牌で和了すると嶺上開花が付く")
    func rinshanKaihou() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: [
                MahjongNotation.hand("5555m234p567p99s3s"),
                junkHand(),
                junkHand(),
                junkHand(),
            ],
            wall: MahjongNotation.tiles("1111m2222m"),
            deadWall: deadWall(rinshan: MahjongNotation.tiles("5s")),
            currentPlayer: 0,
            dealer: 0,
            drawnTile: MahjongNotation.tile("4s")
        )
        model.declareKan(model.availableSelfKans[0])
        #expect(model.drawnTile == MahjongNotation.tile("5s"))
        #expect(model.canDeclareTsumo)

        model.declareTsumo()
        #expect(model.handResult?.kind == .tsumo)
        #expect(model.handResult?.yaku.contains { $0.hasPrefix("嶺上開花") } == true)
    }
}

// MARK: - 鳴きと役

@Suite("鳴きと役・点数")
struct MahjongOpenHandScoringTests {

    private let chi234m = MahjongCall(
        kind: .chi, tile: MahjongNotation.tile("2m"), from: 3, claimedTile: MahjongNotation.tile("2m")
    )

    @Test("鳴くと平和・門前清自摸和が消え、三色同順は 1 飜に下がる")
    func openHandLosesConcealedYaku() {
        let winningTile = MahjongNotation.tile("4s")
        let closed = MahjongScoring.score(
            hand: MahjongNotation.hand("234m234p567p234s99s"),
            context: MahjongWinContext(winningTile: winningTile, isTsumo: true)
        )
        let open = MahjongScoring.score(
            hand: MahjongNotation.hand("234p567p234s99s"),
            calls: [chi234m],
            context: MahjongWinContext(winningTile: winningTile, isTsumo: true)
        )

        let closedNames = closed?.yaku.map(\.name) ?? []
        #expect(closedNames.contains("平和"))
        #expect(closedNames.contains("門前清自摸和"))
        #expect(closed?.yaku.first { $0.name == "三色同順" }?.han == 2)

        let openNames = open?.yaku.map(\.name) ?? []
        #expect(openNames.contains("平和") == false)
        #expect(openNames.contains("門前清自摸和") == false)
        #expect(open?.yaku.first { $0.name == "三色同順" }?.han == 1, "食い下がりで 1 飜")
        #expect(open!.total < closed!.total, "鳴いたぶん安くなる")
    }

    @Test("鳴くと立直も一発も付かない")
    func openHandLosesRiichi() {
        let score = MahjongScoring.score(
            hand: MahjongNotation.hand("234p567p234s99s"),
            calls: [chi234m],
            context: MahjongWinContext(
                winningTile: MahjongNotation.tile("4s"), isTsumo: false,
                isRiichi: true, isIppatsu: true
            )
        )
        let names = score?.yaku.map(\.name) ?? []
        #expect(names.contains("立直") == false)
        #expect(names.contains("一発") == false)
    }

    @Test("暗槓は門前を崩さないので立直も門前清自摸和も残る")
    func closedKanKeepsConcealedYaku() {
        let kan = MahjongCall(kind: .closedKan, tile: MahjongNotation.tile("5m"))
        let score = MahjongScoring.score(
            hand: MahjongNotation.hand("234p567p234s99s"),
            calls: [kan],
            context: MahjongWinContext(
                winningTile: MahjongNotation.tile("4s"), isTsumo: true, isRiichi: true
            )
        )
        let names = score?.yaku.map(\.name) ?? []
        #expect(names.contains("立直"))
        #expect(names.contains("門前清自摸和"))
    }

    @Test("役牌は鳴いても付く")
    func yakuhaiSurvivesCalling() {
        let pon = MahjongCall(
            kind: .pon, tile: MahjongNotation.tile("7z"), from: 1,
            claimedTile: MahjongNotation.tile("7z")
        )
        let score = MahjongScoring.score(
            hand: MahjongNotation.hand("234p567p234s99s"),
            calls: [pon],
            context: MahjongWinContext(winningTile: MahjongNotation.tile("4s"), isTsumo: false)
        )
        #expect(score?.yaku.contains { $0.name.hasPrefix("役牌") } == true)
    }

    @Test("七対子は鳴いた手では成立しない（鳴くと 4 面子 + 雀頭しか残らない）")
    func sevenPairsNeedsConcealedHand() {
        let chiitoi = MahjongScoring.score(
            hand: MahjongNotation.hand("1133m5599p2244s7z7z"),
            context: MahjongWinContext(winningTile: MahjongNotation.tile("7z"), isTsumo: true)
        )
        #expect(chiitoi?.yaku.contains { $0.name == "七対子" } == true)
    }

    @Test("鳴いた手の 20 符（喰い平和形）は 30 符として数える")
    func openPinfuShapeIsThirtyFu() {
        let score = MahjongScoring.score(
            hand: MahjongNotation.hand("234p567p234s99s"),
            calls: [chi234m],
            context: MahjongWinContext(winningTile: MahjongNotation.tile("4s"), isTsumo: false)
        )
        #expect(score?.fu == 30)
    }

    @Test("明刻は暗刻より符が低い")
    func openTripletScoresLessFuThanConcealed() {
        // 東（自風）の刻子 + 断幺九にならない形で、明刻と暗刻の符だけを比べる。
        let winningTile = MahjongNotation.tile("4s")
        let concealed = MahjongScoring.score(
            hand: MahjongNotation.hand("111z234p567p234s99s"),
            context: MahjongWinContext(winningTile: winningTile, isTsumo: false, seatWind: 0)
        )
        let called = MahjongScoring.score(
            hand: MahjongNotation.hand("234p567p234s99s"),
            calls: [MahjongCall(
                kind: .pon, tile: MahjongNotation.tile("1z"), from: 1,
                claimedTile: MahjongNotation.tile("1z")
            )],
            context: MahjongWinContext(winningTile: winningTile, isTsumo: false, seatWind: 0)
        )
        // 暗刻（字牌）8 符 + 門前ロン 10 符 に対し、明刻（字牌）4 符のみ。
        #expect(concealed?.fu == 40)
        #expect(called?.fu == 30)
    }

    @Test("暗槓は暗刻として数えるが、鳴いた刻子は数えない")
    func closedKanCountsAsConcealedTriplet() {
        let calls = [
            MahjongCall(kind: .closedKan, tile: MahjongNotation.tile("1z")),
            MahjongCall(
                kind: .pon, tile: MahjongNotation.tile("2z"), from: 1,
                claimedTile: MahjongNotation.tile("2z")
            ),
        ]
        let score = MahjongScoring.score(
            hand: MahjongNotation.hand("333m555p99s"),
            calls: calls,
            context: MahjongWinContext(winningTile: MahjongNotation.tile("5p"), isTsumo: true)
        )
        // 暗刻 2 つ + 暗槓 1 つ = 三暗刻。ポンした 2z は明刻なので数えない。
        #expect(score?.yaku.contains { $0.name == "三暗刻" } == true)
        #expect(score?.yaku.contains { $0.name == "対々和" } == true)
        #expect(score?.yaku.contains { $0.name == "四暗刻" } == false)

        // 同じ形でポンを暗槓に替えると、暗刻が 4 つになって四暗刻（役満）になる。
        let allConcealed = MahjongScoring.score(
            hand: MahjongNotation.hand("333m555p99s"),
            calls: [
                MahjongCall(kind: .closedKan, tile: MahjongNotation.tile("1z")),
                MahjongCall(kind: .closedKan, tile: MahjongNotation.tile("2z")),
            ],
            context: MahjongWinContext(winningTile: MahjongNotation.tile("5p"), isTsumo: true)
        )
        #expect(allConcealed?.yaku.contains { $0.name == "四暗刻" } == true)
    }

    @Test("混一色・チャンタも鳴くと 1 飜下がる")
    func flushAndTerminalYakuDropOneHan() {
        let closed = MahjongScoring.score(
            hand: MahjongNotation.hand("123p456p789p111z22p"),
            context: MahjongWinContext(winningTile: MahjongNotation.tile("2p"), isTsumo: false)
        )
        let chi123p = MahjongCall(
            kind: .chi, tile: MahjongNotation.tile("1p"), from: 3,
            claimedTile: MahjongNotation.tile("1p")
        )
        let open = MahjongScoring.score(
            hand: MahjongNotation.hand("456p789p111z22p"),
            calls: [chi123p],
            context: MahjongWinContext(winningTile: MahjongNotation.tile("2p"), isTsumo: false)
        )
        #expect(closed?.yaku.first { $0.name == "混一色" }?.han == 3)
        #expect(open?.yaku.first { $0.name == "混一色" }?.han == 2)
    }

    @Test("副露した牌もドラに数える")
    func calledTilesCountForDora() {
        let pon = MahjongCall(
            kind: .pon, tile: MahjongNotation.tile("7z"), from: 1,
            claimedTile: MahjongNotation.tile("7z")
        )
        let score = MahjongScoring.score(
            hand: MahjongNotation.hand("234p567p234s99s"),
            calls: [pon],
            context: MahjongWinContext(
                winningTile: MahjongNotation.tile("4s"), isTsumo: false,
                // 發（6z）の次が中（7z）。晒した 3 枚がそのままドラ 3。
                doraIndicators: [MahjongNotation.tile("6z")]
            )
        )
        #expect(score?.yaku.first { $0.name == "ドラ" }?.han == 3)
    }
}

// MARK: - シャンテンと待ち

@Suite("副露ありのシャンテン")
struct MahjongOpenShantenTests {

    @Test("副露 1 つなら 3 面子 + 雀頭で和了")
    func winsWithOneMeld() {
        let hand = MahjongNotation.hand("234p567p234s99s")
        #expect(hand.total == 11)
        #expect(MahjongShanten.shanten(hand, meldCount: 1) == -1)
        #expect(MahjongShanten.isWinningHand(hand, meldCount: 1))
        // 副露を数えなければ 4 面子に足りないので和了ではない。
        #expect(MahjongShanten.isWinningHand(hand) == false)
    }

    @Test("副露ありでも待ち牌が求まる")
    func waitsWithMelds() {
        let hand = MahjongNotation.hand("234p567p23s99s")
        #expect(hand.total == 10)
        #expect(MahjongShanten.isTenpai(hand, meldCount: 1))
        #expect(Set(MahjongShanten.waits(hand, meldCount: 1)) == Set(MahjongNotation.tiles("14s")))
    }

    @Test("副露していると七対子・国士無双は数えない")
    func openHandCannotUseSpecialShapes() {
        // 対子 6 組 + 1 枚。門前なら七対子の聴牌だが、鳴いていると通常形しか数えないので遠い。
        // 枚数を変えると比べる対象がずれるので、同じ手牌に `meldCount` だけを足して分岐を見る。
        let hand = MahjongNotation.hand("1133m5599p2244s7z")
        #expect(MahjongShanten.shanten(hand) == 0, "七対子の聴牌")
        #expect(MahjongShanten.sevenPairs(hand.counts) == 0)
        #expect(MahjongShanten.shanten(hand, meldCount: 1) > 0, "鳴いていれば七対子は数えない")
    }

    @Test("副露した面子は和了形の分解にも含まれる")
    func decompositionIncludesCalledMelds() {
        let chi = MahjongCall(
            kind: .chi, tile: MahjongNotation.tile("2m"), from: 3,
            claimedTile: MahjongNotation.tile("2m")
        )
        let results = MahjongDecomposer.decompositions(
            MahjongNotation.hand("234p567p234s99s"), calls: [chi]
        )
        #expect(results.count == 1)
        #expect(results[0].melds.count == 4)
        #expect(results[0].melds.last == chi.meld)
        #expect(results[0].melds.last?.isConcealed == false)
        #expect(results[0].pair == MahjongNotation.tile("9s"))
    }
}

// MARK: - CPU の鳴き判断

@Suite("CPU の鳴き判断")
struct MahjongCallAITests {

    private func options(hand: MahjongHand, tile: MahjongTile, allowsChi: Bool = true) -> [MahjongCall] {
        MahjongCallFinder.claimOptions(hand: hand, tile: tile, from: 1, allowsChi: allowsChi)
    }

    @Test("役牌でシャンテンが進むならポンする")
    func ponsYakuhaiThatAdvancesTheHand() {
        let hand = MahjongNotation.hand("11z12m345p678p99s3s")
        let tile = MahjongNotation.tile("1z")
        let chosen = MahjongAI.chooseCall(
            options: options(hand: hand, tile: tile),
            hand: hand, melds: [], seatWind: 0, roundWind: 0
        )
        #expect(chosen?.kind == .pon)
        #expect(chosen?.tile == tile)
    }

    @Test("役の見込みが無ければ、シャンテンが進んでもポンしない")
    func skipsCallWithoutAnyYaku() {
        // 北（4z）は自風でも場風でもないので、鳴いても役にならない。
        let hand = MahjongNotation.hand("44z12m345p678p99s3s")
        let tile = MahjongNotation.tile("4z")
        let candidates = options(hand: hand, tile: tile)
        #expect(candidates.map(\.kind) == [.pon], "形の上ではポンできる")

        let chosen = MahjongAI.chooseCall(
            options: candidates, hand: hand, melds: [], seatWind: 0, roundWind: 0
        )
        #expect(chosen == nil, "役が付かない鳴きはしない")
    }

    @Test("シャンテンが進まない鳴きはしない")
    func skipsCallThatDoesNotAdvance() {
        // 1z を鳴くと雀頭が無くなり、形が良くならない。
        let hand = MahjongNotation.hand("11z123p456p789p35s")
        let tile = MahjongNotation.tile("1z")
        let chosen = MahjongAI.chooseCall(
            options: options(hand: hand, tile: tile),
            hand: hand, melds: [], seatWind: 0, roundWind: 0
        )
        #expect(chosen == nil)
    }

    @Test("チーは聴牌になるときだけ仕掛ける")
    func chiOnlyWhenItReachesTenpai() {
        // チーすると 2 シャンテンから 1 シャンテンへ進むが、聴牌には届かない形。
        let hand = MahjongNotation.hand("34m234p56p9p22s45s8s")
        let tile = MahjongNotation.tile("5m")
        let candidates = options(hand: hand, tile: tile)
        #expect(candidates.contains { $0.kind == .chi })

        let chosen = MahjongAI.chooseCall(
            options: candidates, hand: hand, melds: [], seatWind: 0, roundWind: 0
        )
        #expect(chosen == nil, "聴牌にならないチーはしない")
    }

    @Test("形が悪くならない暗槓はする")
    func kansWhenTheShapeIsUnchanged() {
        let hand = MahjongNotation.hand("5555m234p567p99s1z")
        let drawn = MahjongNotation.tile("3s")
        let candidates = MahjongCallFinder.selfKanOptions(hand: hand, drawnTile: drawn, melds: [])
        #expect(candidates.map(\.kind) == [.closedKan])

        let chosen = MahjongAI.chooseSelfKan(
            options: candidates, hand: hand, drawnTile: drawn, melds: []
        )
        #expect(chosen?.kind == .closedKan)
    }

    @Test("受けが狭くなる暗槓はしない")
    func skipsKanThatNarrowsTheHand() {
        // 5m は 456m の順子としても使えるので、槓にすると受け入れが減る。
        let hand = MahjongNotation.hand("5555m46m234p567p9s")
        let drawn = MahjongNotation.tile("9s")
        let candidates = MahjongCallFinder.selfKanOptions(hand: hand, drawnTile: drawn, melds: [])
        let chosen = MahjongAI.chooseSelfKan(
            options: candidates, hand: hand, drawnTile: drawn, melds: []
        )
        #expect(chosen == nil)
    }
}

// MARK: - 通し（鳴きあり）

@Suite("鳴きありの通し")
@MainActor
struct MahjongCallFullGameTests {

    @Test("鳴けるときは必ず鳴いても東風戦が最後まで進む", .timeLimit(.minutes(1)))
    func playsThroughWhileAlwaysCalling() async {
        let model = makeModel()
        model.startGame()

        var callCount = 0
        var guardCount = 0
        while model.phase != .gameResult, guardCount < 1200 {
            guardCount += 1
            switch model.phase {
            case .playing:
                guard model.currentPlayer == MahjongModel.humanIndex else {
                    await model.runCPUTurnsIfNeeded()
                    continue
                }
                if model.canDeclareTsumo {
                    model.declareTsumo()
                } else if let kan = model.availableSelfKans.first {
                    model.declareKan(kan)
                    callCount += 1
                } else if let tile = model.discardableTiles.first {
                    model.discard(tile)
                } else {
                    // 手番なのに切れる牌が無い = 進行が詰まっている。
                    Issue.record("自分の手番で切れる牌が無い（ツモ牌 \(String(describing: model.drawnTile))）")
                    return
                }
            case .ronOffer:
                model.declareRon()
            case .callOffer:
                // 提示された鳴きは必ず受ける（手番の割り込みが正しく回るかを見る）。
                model.acceptCall(model.callOffer!.options[0])
                callCount += 1
            case .handResult:
                model.advanceToNextHand()
            case .idle, .gameResult:
                break
            }
        }

        #expect(model.phase == .gameResult, "\(guardCount) 手で東風戦が終わらなかった")
        #expect(callCount > 0, "1 度も鳴きの機会が来ないなら、この通しは何も検証していない")
        #expect(model.ranking.count == MahjongModel.playerCount)
        #expect(model.scores.reduce(0, +) == MahjongModel.startingScore * MahjongModel.playerCount)
    }
}
