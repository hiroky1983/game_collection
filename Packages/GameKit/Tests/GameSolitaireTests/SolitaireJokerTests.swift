import Testing
import Foundation
import Core
@testable import GameSolitaire

// MARK: - Mocks

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var raw: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        raw[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = raw[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { raw.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { raw[gameID] != nil }

    /// 旧形式・壊れた形式の中断データを外から差し込む。
    func put<T: Encodable>(_ snapshot: T, for gameID: String) throws {
        raw[gameID] = try JSONEncoder().encode(snapshot)
    }
}

/// ジョーカーが存在しなかった版の中断データ（`jokerGrants` を持たない）。
private struct LegacySnapshot: Encodable {
    let seed: UInt64
    let moves: [SolitaireMove]
    let elapsedSeconds: Int
}

/// 書き換えられた（または壊れた）中断データ。`jokerGrants` を明示して書ける。
private struct RawSnapshot: Encodable {
    let seed: UInt64
    let moves: [SolitaireMove]
    let elapsedSeconds: Int
    let jokerGrants: Int
}

@MainActor
private func makeServices(store: SnapshotStore = MemorySnapshotStore()) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService())
}

private let fixedSeed = SolitaireDealer.verifiedSeeds[0]

/// 指せる手は残っているが、**もう組札を揃えきれない**盤面。
///
/// スペードは 9 まで組札に載っている。次に要る 10 は 0 列目の Q の下に伏せたままで、
/// その Q は「赤の K」も空列も無いので永久に動かせない。一方 1 列目の K は空列へ動かせて
/// 伏せ札の J をめくれるので、**行き止まり（`isDeadEnd`）ではない**。
/// (a) では拾えず (b) でだけ拾える、という #406 の検知対象そのものの形。
private func hopelessButMovableBoard() -> SolitaireBoard {
    var piles = [SolitairePile](repeating: SolitairePile(), count: SolitaireBoard.pileCount)
    piles[0] = SolitairePile(faceDown: [SolitaireCard(.spade, 10)], faceUp: [SolitaireCard(.spade, 12)])
    piles[1] = SolitairePile(faceDown: [SolitaireCard(.spade, 11)], faceUp: [SolitaireCard(.spade, 13)])
    return SolitaireBoard(tableau: piles, foundations: [9, 13, 13, 13])
}

// MARK: - ジョーカー経済（#397 の仕様 / #406 の決裁1・2）

@Suite("ソリティアのジョーカー経済")
@MainActor
struct SolitaireJokerEconomyTests {

    @Test("配った時点で1枚持っている（初期所持1枚）")
    func startsWithOneJoker() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.hasJoker)
        #expect(!model.jokerUsed)
    }

    @Test("置くと所持が空になり、戻すと手持ちに返る（#397 吟味2）")
    func undoReturnsJokerToHand() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.placeJoker(onPile: 0))
        #expect(!model.hasJoker)
        #expect(model.jokerUsed)

        #expect(model.undo())
        #expect(model.hasJoker)
        #expect(!model.jokerUsed)
    }

    @Test("所持しているときに広告で補充しても増えない（所持上限1枚）")
    func grantIsCappedAtOne() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.hasJoker)
        #expect(model.grantJoker(forDeal: model.dealSerial) == false)
        #expect(model.hasJoker)
    }

    @Test("使い切ったあとの補充は成功し、そのまま置ける")
    func grantRefillsAfterUse() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.placeJoker(onPile: 0))
        #expect(!model.hasJoker)

        #expect(model.grantJoker(forDeal: model.dealSerial))
        #expect(model.hasJoker)
        #expect(model.placeJoker(onPile: 1))
        #expect(!model.hasJoker)
    }

    /// 広告のロード〜視聴の間に配り直されたら補充しない（#511。`grantUndos(forDeal:)` と同じ契約）。
    ///
    /// 照合しないと、前の局への報酬が新しい局で成立して 2 枚目のジョーカーになる。
    @Test("広告中に配り直したら補充されない（#511）")
    func grantIsRejectedAfterNewDeal() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.placeJoker(onPile: 0))
        let deal = model.dealSerial

        // 広告を見ている間に配り直し、初期の 1 枚も置いて手持ちを空にする。
        model.newGame()
        #expect(model.placeJoker(onPile: 0))
        #expect(!model.hasJoker)

        #expect(!model.grantJoker(forDeal: deal), "別の局への報酬が適用されている")
        #expect(!model.hasJoker)
        // いまの局の連番なら通る。
        #expect(model.grantJoker(forDeal: model.dealSerial))
        #expect(model.hasJoker)
    }

    @Test("配り直すと所持が初期の1枚に戻る")
    func newGameRestoresInitialJoker() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.placeJoker(onPile: 0))
        #expect(model.grantJoker(forDeal: model.dealSerial))
        #expect(model.placeJoker(onPile: 1))
        #expect(!model.hasJoker)

        model.newGame()
        #expect(model.hasJoker)
        #expect(!model.jokerUsed)
    }
}

// MARK: - 置き先の選択（#406 の決裁1: プレイヤー主導）

@Suite("ジョーカーの置き先の選択")
@MainActor
struct SolitaireJokerPlacementModeTests {

    @Test("ボタン → 列タップで置ける。置いたらモードから抜ける")
    func placesOnTappedPile() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.beginPlacingJoker()
        #expect(model.isPlacingJoker)

        model.tapPile(2)
        #expect(!model.isPlacingJoker)
        #expect(model.jokerUsed)
        #expect(model.board.tableau[2].top?.isJoker == true)
    }

    @Test("置けない列をタップしてもモードから抜けない（押し直しで済む）")
    func staysInModeOnIllegalPile() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.placeJoker(onPile: 3))
        #expect(model.grantJoker(forDeal: model.dealSerial))

        model.beginPlacingJoker()
        // 上がジョーカーの列には置けない（#397 ルール1）。
        model.tapPile(3)
        #expect(model.isPlacingJoker)
        #expect(model.rejectedTapCount == 1)
        #expect(model.hasJoker)

        // 押し直しがそのまま通る（モードを抜けていない）。
        model.tapPile(4)
        #expect(!model.isPlacingJoker)
        #expect(model.board.tableau[4].top?.isJoker == true)
    }

    @Test("所持していなければモードに入れない")
    func cannotEnterModeWithoutJoker() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(model.placeJoker(onPile: 0))
        model.beginPlacingJoker()
        #expect(!model.isPlacingJoker)
        #expect(model.rejectedTapCount == 1)
    }

    @Test("山札・捨て札・組札をタップするとモードから抜ける（盤面は動かない）")
    func tappingElsewhereCancelsMode() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        let before = model.board

        model.beginPlacingJoker()
        model.tapStock()
        #expect(!model.isPlacingJoker)
        #expect(model.board == before)

        model.beginPlacingJoker()
        model.tapWaste()
        #expect(!model.isPlacingJoker)
        #expect(model.board == before)

        model.beginPlacingJoker()
        model.tapFoundation(.spade)
        #expect(!model.isPlacingJoker)
        #expect(model.board == before)
    }

    @Test("選択モード中は救済の告知を引っ込める（列をタップさせるため）")
    func promptHidesWhilePlacing() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.applyLostVerdict(true, for: model.board.stateKey)
        #expect(model.showsRescuePrompt)

        model.beginPlacingJoker()
        #expect(!model.showsRescuePrompt)

        model.cancelPlacingJoker()
        #expect(model.showsRescuePrompt)
    }
}

// MARK: - 中断復元（#406 の申し送り2: replay の placeJoker 対応）

@Suite("ジョーカーを含む中断データの復元")
@MainActor
struct SolitaireJokerSnapshotTests {

    @Test("ジョーカーを置いた手順が、そのままの盤面で復元される")
    func restoresBoardWithJoker() {
        let store = MemorySnapshotStore()
        let model = SolitaireModel(services: makeServices(store: store), seed: fixedSeed)
        model.tapStock()
        #expect(model.placeJoker(onPile: 4))
        model.tapStock()
        let expected = model.board

        let resumed = SolitaireModel(services: makeServices(store: store))
        #expect(resumed.board == expected)
        #expect(resumed.jokerUsed)
        #expect(!resumed.hasJoker)
        #expect(resumed.moveCount == model.moveCount)
    }

    @Test("広告で補充した1枚は再開しても消えない")
    func restoresRefilledJoker() {
        let store = MemorySnapshotStore()
        let model = SolitaireModel(services: makeServices(store: store), seed: fixedSeed)
        #expect(model.placeJoker(onPile: 0))
        #expect(model.grantJoker(forDeal: model.dealSerial))
        #expect(model.hasJoker)

        let resumed = SolitaireModel(services: makeServices(store: store))
        #expect(resumed.hasJoker)
        #expect(resumed.jokerUsed)
    }

    @Test("ジョーカーが無かった版の中断データも読め、初期の1枚が付く")
    func readsSnapshotWithoutJokerGrants() throws {
        let store = MemorySnapshotStore()
        try store.put(
            LegacySnapshot(seed: fixedSeed, moves: [.draw], elapsedSeconds: 12),
            for: "solitaire"
        )
        let resumed = SolitaireModel(services: makeServices(store: store))
        #expect(resumed.elapsedSeconds == 12)
        #expect(!resumed.isFreshDeal)
        #expect(resumed.hasJoker)
        #expect(!resumed.jokerUsed)
    }

    @Test("所持と食い違う placeJoker が入っていたら、その手前で切り詰める")
    func truncatesSnapshotWithUnaffordableJoker() throws {
        let store = MemorySnapshotStore()
        // 1 手目の山めくりは合法。2 手目の placeJoker は所持 0 枚なので適用できない。
        try store.put(
            RawSnapshot(
                seed: fixedSeed,
                moves: [.draw, .placeJoker(pile: 0), .draw],
                elapsedSeconds: 5,
                jokerGrants: 0
            ),
            for: "solitaire"
        )
        let resumed = SolitaireModel(services: makeServices(store: store))
        #expect(!resumed.jokerUsed)
        #expect(!resumed.hasJoker)
        expectMatchesOneDraw(resumed)
    }

    @Test("適用できない通常の手が混ざっていたら、その手前で切り詰めて復元する")
    func truncatesCorruptedSnapshot() throws {
        let store = MemorySnapshotStore()
        // 1 手目の山めくりは合法。2 手目は捨て札の Q を空の組札へ送ろうとしていて適用できない。
        try store.put(
            RawSnapshot(
                seed: fixedSeed,
                moves: [.draw, .wasteToFoundation, .draw],
                elapsedSeconds: 5,
                jokerGrants: 1
            ),
            for: "solitaire"
        )
        let resumed = SolitaireModel(services: makeServices(store: store))
        #expect(resumed.hasJoker)
        expectMatchesOneDraw(resumed)
    }

    /// 「1 手目（山めくり）まで指した盤面」と一致していることを確かめる。
    ///
    /// 落ちた手を読み飛ばして 3 手目まで進めると、山札が 1 枚多くめくれた別の盤面になる。
    /// 盤面と手順の両方を見て、**黙って読み飛ばしていない**ことを押さえる。
    private func expectMatchesOneDraw(_ resumed: SolitaireModel) {
        let reference = SolitaireModel(services: makeServices(), seed: fixedSeed)
        reference.tapStock()
        #expect(resumed.board.tableau == reference.board.tableau)
        #expect(resumed.board.waste == reference.board.waste)
        #expect(resumed.board.stock == reference.board.stock)
        // 手順そのものも切り詰まっている（戻せるのは 1 手だけ）。
        #expect(resumed.canUndo)
        #expect(resumed.undo())
        #expect(!resumed.canUndo)
    }
}

// MARK: - 敗北確定の検知（#406 の詰み検知（b））

@Suite("敗北確定の検知")
@MainActor
struct SolitaireLostDetectionTests {

    @Test("もう勝てない盤面を「敗北確定」と判定する（行き止まりではない）")
    func detectsHopelessPosition() {
        let board = hopelessButMovableBoard()
        #expect(!board.isWon)
        // 指せる手は残っている = (a) の行き止まり検知では拾えない。
        #expect(!board.isDeadEnd)
        #expect(SolitaireModel.hopelessVerdict(for: board) == true)
    }

    @Test("まだ勝てる盤面は「敗北確定」と判定しない")
    func doesNotFlagWinnablePosition() {
        // 検証済みの種の初期盤面は、定義上クリア可能。
        #expect(SolitaireModel.hopelessVerdict(for: SolitaireDealer.deal(seed: fixedSeed)) == false)
    }

    @Test("探索を尽くせなかった局面は「分からない」（nil）に写す。負けに倒さない")
    func mapsTruncatedSearchToUnknown() {
        let board = SolitaireDealer.deal(seed: fixedSeed)
        // 上限に達して打ち切った形（`hitLimit`）は勝ち筋の不在を証明していない。
        let truncated = SolitaireSolver.solve(board, allowJoker: false, maxStates: 1)
        #expect(truncated.hitLimit)
        #expect(truncated.solution == nil)
        // 同じ条件で `hopelessVerdict` を呼ぶと nil。true（負け）に倒したらここが落ちる。
        #expect(SolitaireModel.hopelessVerdict(for: board, maxStates: 1) == nil)
    }

    @Test("取り消された探索も「分からない」に倒れる（途中まで見た結果を負けと読まない）")
    func mapsCancelledSearchToUnknown() {
        // もう勝てない盤面（本来なら true が返る）でも、取り消されたら nil。
        #expect(SolitaireModel.hopelessVerdict(for: hopelessButMovableBoard()) == true)
        #expect(
            SolitaireModel.hopelessVerdict(for: hopelessButMovableBoard(), isCancelled: { true })
                == nil
        )
        // ソルバー側でも「最後まで見ていない」印が立っている。
        let cancelled = SolitaireSolver.solve(
            SolitaireDealer.deal(seed: fixedSeed), allowJoker: false, isCancelled: { true }
        )
        #expect(cancelled.hitLimit)
        #expect(cancelled.solution == nil)
    }

    @Test("「分からない」が返ってきたときは告知を出さない")
    func doesNotFlagOnUnknownVerdict() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.applyLostVerdict(nil, for: model.board.stateKey)
        #expect(!model.isLost)
        #expect(!model.showsRescuePrompt)
    }

    @Test("敗北確定が返ってきたら告知を出す")
    func raisesPromptOnLostVerdict() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        #expect(!model.isLost)
        model.applyLostVerdict(true, for: model.board.stateKey)
        #expect(model.isLost)
        #expect(model.showsRescuePrompt)
    }

    @Test("探索している間に盤面が変わっていたら結果を捨てる")
    func ignoresStaleVerdict() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        let staleKey = model.board.stateKey
        model.tapStock()
        #expect(model.board.stateKey != staleKey)

        model.applyLostVerdict(true, for: staleKey)
        #expect(!model.isLost)
    }

    @Test("戻して同じ局面に返ったら、探索し直さずに敗北確定のまま扱う")
    func remembersHopelessPositionAcrossUndo() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.tapStock()
        let lostKey = model.board.stateKey
        model.applyLostVerdict(true, for: lostKey)
        #expect(model.isLost)

        model.tapStock()
        #expect(!model.isLost)
        #expect(model.undo())
        #expect(model.board.stateKey == lostKey)
        #expect(model.isLost)
    }

    @Test("バックグラウンドの探索が最後まで走り、もう勝てない局面で告知に繋がる")
    func backgroundCheckRaisesPrompt() async {
        let previous = SolitaireModel.lostCheckDelayMilliseconds
        SolitaireModel.lostCheckDelayMilliseconds = 0
        defer { SolitaireModel.lostCheckDelayMilliseconds = previous }

        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.replaceBoardForTesting(hopelessButMovableBoard())
        // 実時間で待たず、仕込まれた探索そのものの完了を待ち合わせる。
        await model.lostCheckTask?.value
        #expect(model.isLost)
        #expect(model.showsRescuePrompt)
    }

    @Test("バックグラウンドの探索は、クリア可能な局面では告知を出さない")
    func backgroundCheckLeavesWinnablePositionAlone() async {
        let previous = SolitaireModel.lostCheckDelayMilliseconds
        SolitaireModel.lostCheckDelayMilliseconds = 0
        defer { SolitaireModel.lostCheckDelayMilliseconds = previous }

        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        await model.lostCheckTask?.value
        #expect(!model.isLost)
        #expect(!model.showsRescuePrompt)
    }
}

// MARK: - 告知の出し分け（#406 の UX 副作用への対処）

@Suite("救済の告知の出し分け")
@MainActor
struct SolitaireRescuePromptTests {

    @Test("敗北確定の告知は「このまま続ける」で閉じられる")
    func lostPromptIsDismissible() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.applyLostVerdict(true, for: model.board.stateKey)
        #expect(model.showsRescuePrompt)

        model.dismissRescuePrompt()
        #expect(!model.showsRescuePrompt)
        // 状態そのものは残す（ステータスバーの表示に使う）。
        #expect(model.isLost)
    }

    @Test("閉じたあとに行き止まりへ落ちたら、あらためて告知する")
    func deadEndPromptSurvivesDismissal() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.applyLostVerdict(true, for: model.board.stateKey)
        model.dismissRescuePrompt()
        #expect(!model.showsRescuePrompt)

        // (a) の行き止まりは (b) を閉じた覚えとは別に数える（#491 でも分けたまま）。
        // 山札も捨て札も空で、動かせる札も無い盤面を置く。
        var piles = [SolitairePile](repeating: SolitairePile(), count: SolitaireBoard.pileCount)
        piles[0] = SolitairePile(faceDown: [SolitaireCard(.spade, 10)], faceUp: [SolitaireCard(.spade, 12)])
        model.replaceBoardForTesting(SolitaireBoard(tableau: piles, foundations: [9, 13, 13, 13]))
        #expect(model.isDeadEnd)
        #expect(model.showsRescuePrompt)
    }

    @Test("配り直すと閉じた覚えも消える")
    func newGameClearsDismissal() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.applyLostVerdict(true, for: model.board.stateKey)
        model.dismissRescuePrompt()

        model.newGame()
        #expect(!model.isLost)
        model.applyLostVerdict(true, for: model.board.stateKey)
        #expect(model.showsRescuePrompt)
    }

    // MARK: - 行き止まりの告知も閉じられる（#491・#475 の決裁 C）

    /// 行き止まりだが**合法手は残っている**盤面（#475 の会長QAの局面）。
    ///
    /// 先頭が K・伏せ札なしの列が1本だけあり、他は空。K を空列へ移す手は合法だが
    /// 「列を入れ替えるだけ」で盤面は進まないので `hasProgressMove` は数えない。
    /// 組札は ♠ が 0 なので K は送れず、山札・捨て札も空。
    private static func deadEndBoardWithIdleMove() -> SolitaireBoard {
        var piles = [SolitairePile](repeating: SolitairePile(), count: SolitaireBoard.pileCount)
        piles[0] = SolitairePile(faceUp: [SolitaireCard(.spade, 13)])
        return SolitaireBoard(tableau: piles, foundations: [0, 13, 13, 13])
    }

    @Test("行き止まりの盤面でも、K を空列へ動かす合法手は残っている")
    func deadEndStillHasLegalMove() {
        let board = Self.deadEndBoardWithIdleMove()
        #expect(board.isDeadEnd)
        // 「進む手が無い」だけで「触れる手が無い」ではない。ここが #491 の前提。
        var moved = board
        let applied = moved.apply(.tableauToTableau(from: 0, cardIndex: 0, to: 1))
        #expect(applied)
        #expect(moved.tableau[1].top == SolitaireCard(.spade, 13))
    }

    @Test("行き止まりの告知も「このまま続ける」で閉じられる")
    func deadEndPromptIsDismissible() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.replaceBoardForTesting(Self.deadEndBoardWithIdleMove())
        #expect(model.isDeadEnd)
        #expect(model.showsRescuePrompt)

        model.dismissRescuePrompt()
        #expect(!model.showsRescuePrompt)
        // 状態そのものは残す（ステータスバーと 😵 の表示に使う）。
        #expect(model.isDeadEnd)
    }

    @Test("行き止まりの告知は、閉じたら配り直すまで再表示しない")
    func deadEndPromptStaysDismissedUntilNewGame() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.replaceBoardForTesting(Self.deadEndBoardWithIdleMove())
        model.dismissRescuePrompt()
        #expect(!model.showsRescuePrompt)

        // 残っている合法手（K → 空列）を指しても、告知は戻ってこない。
        model.tapPile(0)
        model.tapPile(1)
        #expect(model.isDeadEnd)
        #expect(!model.showsRescuePrompt)

        model.newGame()
        model.replaceBoardForTesting(Self.deadEndBoardWithIdleMove())
        #expect(model.showsRescuePrompt)
    }

    @Test("行き止まりと敗北確定が同時に立っていても、1回で閉じ切れる")
    func dismissClosesBothKindsAtOnce() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.replaceBoardForTesting(Self.deadEndBoardWithIdleMove())
        model.applyLostVerdict(true, for: model.board.stateKey)
        #expect(model.isDeadEnd)
        #expect(model.isLost)

        // 片方しか閉じないと、😵 が 🤔 に差し替わって告知が居座る。
        model.dismissRescuePrompt()
        #expect(!model.showsRescuePrompt)
    }

    @Test("行き止まりを閉じたあとに敗北確定が立ったら、あらためて告知する")
    func lostPromptSurvivesDeadEndDismissal() {
        let model = SolitaireModel(services: makeServices(), seed: fixedSeed)
        model.replaceBoardForTesting(Self.deadEndBoardWithIdleMove())
        model.dismissRescuePrompt()
        #expect(!model.showsRescuePrompt)

        model.applyLostVerdict(true, for: model.board.stateKey)
        #expect(model.showsRescuePrompt)
    }

}

// MARK: - Game Center（#397 の受け入れ条件: ジョーカー未使用クリアのみ送信）

@Suite("ジョーカーを使ったクリアは順位表に送らない")
struct SolitaireJokerLeaderboardTests {

    @Test("未使用のクリアは送る")
    func sendsCleanClear() {
        let score = GameScore(metric: .shortestTime, seconds: 240, moves: 120)
        let submitted = GameCenterLeaderboard.score(gameID: "solitaire", outcome: .win, score: score)
        #expect(submitted?.leaderboardID == GameCenterLeaderboard.solitaireTime)
        #expect(submitted?.value == 240)
    }

    @Test("ジョーカーを使ったクリアは送らない")
    func skipsAssistedClear() {
        let score = GameScore(
            metric: .shortestTime, seconds: 240, moves: 120, isLeaderboardEligible: false
        )
        #expect(GameCenterLeaderboard.score(gameID: "solitaire", outcome: .win, score: score) == nil)
    }

    @Test("旗は指標を問わず効く（救済を足した他ゲームでも自動で対象外になる）")
    func skipsAssistedPointsScore() {
        let assisted = GameScore(metric: .points, points: 4096, isLeaderboardEligible: false)
        #expect(GameCenterLeaderboard.score(gameID: "2048", outcome: .win, score: assisted) == nil)
        let clean = GameScore(metric: .points, points: 4096)
        #expect(GameCenterLeaderboard.score(gameID: "2048", outcome: .win, score: clean) != nil)
    }
}

// MARK: - 決着から送信までの繋ぎ（対応表だけ直しても、Model が渡さなければ意味が無い）

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) { completion(true) }
}

@Suite("クリアの送信")
@MainActor
struct SolitaireJokerSubmissionTests {

    /// 4 枚の K を送るだけで上がれる盤面（`autoFinish` で決着まで走らせるため）。
    private func almostWonBoard() -> SolitaireBoard {
        var piles = [SolitairePile](repeating: SolitairePile(), count: SolitaireBoard.pileCount)
        for suit in SolitaireSuit.allCases {
            piles[suit.rawValue] = SolitairePile(faceUp: [SolitaireCard(suit, 13)])
        }
        return SolitaireBoard(tableau: piles, foundations: [12, 12, 12, 12])
    }

    @MainActor
    private func finishGame(usingJoker: Bool) -> SpyGameCenterService {
        let spy = SpyGameCenterService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(),
            ads: NoopAdService(),
            gameCenter: GameCenterReporter(service: spy, allowedGameIDs: ["solitaire"])
        )
        let model = SolitaireModel(services: services, seed: fixedSeed)
        if usingJoker { #expect(model.placeJoker(onPile: 0)) }
        // 0 秒のクリアは対応表が弾くので、1 秒だけ進めてから決着させる。
        model.tick()
        model.replaceBoardForTesting(almostWonBoard())
        #expect(model.autoFinish())
        #expect(model.phase == .won)
        return spy
    }

    @Test("ジョーカーを使わずにクリアしたらタイムを送る")
    func submitsCleanClear() {
        let spy = finishGame(usingJoker: false)
        #expect(spy.scores.map(\.leaderboardID) == [GameCenterLeaderboard.solitaireTime])
    }

    @Test("ジョーカーを使ってクリアしたら何も送らない")
    func skipsAssistedClear() {
        let spy = finishGame(usingJoker: true)
        #expect(spy.scores.isEmpty)
    }
}

// MARK: - ローカル記録（使用の有無を問わず残す・#397）

@Suite("ジョーカーを使っても自己ベストは残る")
@MainActor
struct SolitaireJokerPlayRecordTests {

    @Test("順位表の対象外でも `PlayLog` には取り込まれる")
    func recordsAssistedClearLocally() {
        let name = "asobiba.solitaire.joker.record"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)

        let assisted = GameScore(
            metric: .shortestTime, seconds: 300, moves: 90, isLeaderboardEligible: false
        )
        let result = log.recordResult(gameID: "solitaire", outcome: .win, score: assisted)
        #expect(result.record.bestSeconds == 300)
        #expect(result.record.wins == 1)
    }
}

// MARK: - 読み上げ

@Suite("ジョーカーの読み上げ")
struct SolitaireJokerAccessibilityTests {

    @Test("所持しているかどうかがラベルだけで分かる")
    func labelTellsPossession() {
        let owned = SolitaireAccessibility.jokerButtonLabel(hasJoker: true, isPlacing: false)
        let empty = SolitaireAccessibility.jokerButtonLabel(hasJoker: false, isPlacing: false)
        #expect(owned.contains("1枚所持"))
        #expect(empty.contains("所持していません"))
        #expect(owned != empty)
    }

    @Test("補充の案内は、告知が出る2つの条件のどちらも取りこぼさない")
    func hintCoversBothRescueConditions() {
        let hint = SolitaireAccessibility.jokerButtonHint(hasJoker: false, isPlacing: false)
        // 有効手ゼロ（手詰まり）だけでなく、敗北確定（指せる手はあるがクリアできない）でも出る。
        #expect(hint.contains("手詰まり"))
        #expect(hint.contains("クリアできない"))
        #expect(hint.contains("広告"))
    }

    @Test("置き先を選んでいる最中はやめ方が読まれる")
    func labelTellsPlacingMode() {
        let placing = SolitaireAccessibility.jokerButtonLabel(hasJoker: false, isPlacing: true)
        #expect(placing.contains("やめる"))
        #expect(
            SolitaireAccessibility.jokerButtonHint(hasJoker: false, isPlacing: true)
                .contains("列をタップ")
        )
    }

    @Test("ステータスバーは敗北確定も読み上げる（告知を閉じたあとの唯一の手がかり）")
    func statusLabelTellsLostState() {
        let normal = SolitaireAccessibility.statusLabel(
            phase: .playing, elapsedSeconds: 60, moveCount: 20, isDeadEnd: false, isLost: false
        )
        let lost = SolitaireAccessibility.statusLabel(
            phase: .playing, elapsedSeconds: 60, moveCount: 20, isDeadEnd: false, isLost: true
        )
        let deadEnd = SolitaireAccessibility.statusLabel(
            phase: .playing, elapsedSeconds: 60, moveCount: 20, isDeadEnd: true, isLost: true
        )
        #expect(!normal.contains("クリアできません"))
        #expect(lost.hasPrefix("このままではクリアできません"))
        // 行き止まりのほうが強い状態なので、両方立っていたらそちらを読む。
        #expect(deadEnd.hasPrefix("進める手がありません"))
    }

    @Test("告知は行き止まりと敗北確定を読み分け、対価の有無も伝える")
    func rescueLabelDistinguishesKinds() {
        let deadEndWithJoker = SolitaireAccessibility.rescuePromptLabel(isDeadEnd: true, hasJoker: true)
        let lostWithoutJoker = SolitaireAccessibility.rescuePromptLabel(isDeadEnd: false, hasJoker: false)
        #expect(deadEndWithJoker.contains("進める手がありません"))
        #expect(deadEndWithJoker.contains("ジョーカーが1枚使えます"))
        #expect(lostWithoutJoker.contains("クリアできません"))
        #expect(lostWithoutJoker.contains("広告"))
    }

    @Test("行き止まりの読み上げは、残っている入れ替えの存在を否定しない（#491）")
    func rescueLabelDoesNotDenyIdleMoves() {
        let deadEnd = SolitaireAccessibility.rescuePromptLabel(isDeadEnd: true, hasJoker: false)
        // 画面の本文と同じ内容まで読む。見出しだけだと合法手までゼロだと伝わる。
        #expect(deadEnd.contains("山札をめくるか、盤面が進まない入れ替えしか残っていません"))
        #expect(!deadEnd.contains("山札をめくるしか手が残っていません"))

        // ステータスバーは見出しと同じ文言のまま（画面表示と食い違わせない）。
        let status = SolitaireAccessibility.statusLabel(
            phase: .playing, elapsedSeconds: 10, moveCount: 3, isDeadEnd: true, isLost: false
        )
        #expect(status.hasPrefix("進める手がありません"))
        #expect(deadEnd.hasPrefix("進める手がありません"))
    }
}
