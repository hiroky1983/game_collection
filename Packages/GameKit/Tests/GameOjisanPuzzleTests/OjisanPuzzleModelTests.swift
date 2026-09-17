import Testing
@testable import GameOjisanPuzzle

/// 進行役（`OjisanPuzzleModel`）のうち、落下タイマーを回さずに確かめられる部分。
/// 判定そのものは `OjisanPuzzleBoardTests` が見ているので、ここは受け口と状態の遷移だけ。
@Suite("腰痛おじさんパズルの進行")
@MainActor
struct OjisanPuzzleModelTests {

    private func makeModel() -> OjisanPuzzleModel {
        OjisanPuzzleModel(services: nil, seed: 42)
    }

    @Test("始めたときは空の盤と落下中の組がある")
    func startsWithEmptyBoardAndPair() {
        let model = makeModel()
        #expect(model.board == OjisanPuzzleBoard.emptyBoard())
        #expect(model.current != nil)
        #expect(model.score == 0)
        #expect(model.pain == 0)
        #expect(model.outcome == nil)
    }

    @Test("描画用の盤には落下中の組が重なっている")
    func displayBoardIncludesFallingPair() throws {
        let model = makeModel()
        let pair = try #require(model.current)
        #expect(model.displayBoard[pair.row][pair.col] == pair.axisKind)
        #expect(model.displayBoard[pair.childRow][pair.childCol] == pair.childKind)
    }

    @Test("左右へ動かすと落下中の組の列が変わる")
    func moveShiftsColumn() throws {
        let model = makeModel()
        let before = try #require(model.current).col
        #expect(model.move(by: 1))
        #expect(try #require(model.current).col == before + 1)
    }

    @Test("一気に落とすと盤に固定され、腰痛ゲージが増える")
    func hardDropLocksAndHurts() throws {
        let model = makeModel()
        let pair = try #require(model.current)
        #expect(model.hardDrop())
        #expect(model.current == nil, "固定したのに落下中の組が残っている")
        #expect(model.pain == OjisanPuzzlePain.perLock)
        let floor = OjisanPuzzleBoard.rows - 1
        #expect(model.board[floor][pair.col] == pair.axisKind)
        #expect(model.board[floor - 1][pair.col] == pair.childKind)
    }

    @Test("固定してから次の組が出るまでは操作を受け付けない")
    func ignoresInputWhileSettling() {
        let model = makeModel()
        #expect(model.hardDrop())
        #expect(!model.move(by: 1))
        #expect(!model.rotate(clockwise: true))
        #expect(!model.hardDrop())
    }

    @Test("もう一度でスコア・ゲージ・盤が戻る")
    func newGameResetsEverything() {
        let model = makeModel()
        #expect(model.hardDrop())
        model.newGame()
        #expect(model.board == OjisanPuzzleBoard.emptyBoard())
        #expect(model.pain == 0)
        #expect(model.score == 0)
        #expect(model.current != nil)
        #expect(model.outcome == nil)
        model.pause()
    }

    /// 落下タイマーを回す代わりに `tick()` を直に叩いて、固定 → 重力 → 消去 → 次の組、の
    /// つなぎ目を確かめる（判定そのものは盤のテストが見ている）。
    @Test("4つそろえると消えて点が入り、ゲージが減って次の組が出る")
    func settlingClearsAndSpawnsNext() throws {
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in (OjisanPuzzleBoard.rows - 3)..<OjisanPuzzleBoard.rows { board[row][0] = 1 }
        let pair = OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up)
        let model = OjisanPuzzleModel(services: nil, board: board, current: pair)

        #expect(model.hardDrop())
        #expect(model.pain == OjisanPuzzlePain.perLock)

        model.tick()    // 重力は動かないので、そのまま 4 つそろった 1 を消す
        #expect(model.score == OjisanPuzzleScoring.chainPoints(cells: 4, chain: 1))
        #expect(model.lastChain == 1)
        #expect(model.pain == 0, "消したのにゲージが減っていない")

        model.tick()    // 上に残った荷物が落ちる
        #expect(model.board[OjisanPuzzleBoard.rows - 1][0] == 2)

        model.tick()    // もう消えないので次の組が出る
        #expect(model.current != nil, "次の組が出ていない")
        #expect(model.outcome == nil)
    }

    // MARK: - 腰痛が遊びに効く（会長指示 2026-09-17）

    @Test("腰が重いほど落下の刻みが短くなる")
    func dropIntervalShrinksWithPain() {
        let easy = OjisanPuzzleModel(services: nil, board: OjisanPuzzleBoard.emptyBoard(), current: nil, pain: 0)
        let aching = OjisanPuzzleModel(services: nil, board: OjisanPuzzleBoard.emptyBoard(), current: nil, pain: 50)
        let severe = OjisanPuzzleModel(services: nil, board: OjisanPuzzleBoard.emptyBoard(), current: nil, pain: 90)
        #expect(easy.dropInterval == OjisanPuzzleModel.baseDropInterval)
        #expect(aching.dropInterval < easy.dropInterval)
        #expect(severe.dropInterval < aching.dropInterval)
        #expect(severe.dropInterval > 0)
        #expect(easy.painStage == .easy && aching.painStage == .aching && severe.painStage == .severe)
    }

    @Test("腰が軽いうちは左右移動を連打できる")
    func inputIsFreeWhilePainIsLow() {
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: 0
        )
        #expect(model.move(by: 1))
        #expect(model.move(by: 1), "腰が軽いのに間隔が空いている")
        #expect(model.rotate(clockwise: true))
    }

    @Test("腰が重いと、続けて出した左右移動・回転はワンテンポ待たされる")
    func inputIsThrottledWhilePainIsHigh() throws {
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: 90
        )
        let start = try #require(model.current).col
        #expect(model.move(by: 1), "1 回目は受け付ける")
        #expect(!model.move(by: 1), "続けて出した 2 回目が通ってしまっている")
        #expect(!model.rotate(clockwise: true), "回転も同じ間隔で待たされる")
        #expect(try #require(model.current).col == start + 1, "1 マスしか動いていないはず")
    }

    /// 落とす操作まで遅らせると「重い」ではなく「操作を奪われた」手触りになるため、
    /// 下スワイプ（ソフトドロップ）は腰が重くても素通しする。
    @Test("腰が重くても落とす操作は遅らせない")
    func softDropIsNeverThrottled() {
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 2, rotation: .up),
            pain: 95
        )
        #expect(model.softDrop())
        #expect(model.softDrop())
        #expect(model.softDrop())
    }

    @Test("もう一度で入力の間隔もリセットされる")
    func newGameClearsInputThrottle() {
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 2, rotation: .up),
            pain: 90
        )
        #expect(model.move(by: 1))
        #expect(!model.move(by: 1))
        model.newGame()
        model.pause()
        #expect(model.pain == 0)
        #expect(model.move(by: 1), "やり直したのに待たされている")
    }

    // MARK: - 決着

    @Test("腰痛ゲージが 100 に達したら入院で終わる")
    func hospitalizesWhenPainReachesLimit() {
        // あと 1 回固定すれば 100 に届くゲージから始める。
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - OjisanPuzzlePain.perLock
        )
        #expect(model.hardDrop())
        #expect(model.pain == OjisanPuzzlePain.limit)
        #expect(model.outcome == .hospitalized)
        // 決着したら操作も進行も受け付けない。
        #expect(!model.move(by: 1))
        model.tick()
        #expect(model.current == nil)
    }

    /// **現仕様の明示**: 入院の判定は固定した瞬間に行う（消して減らす前）。
    /// その手で 4 つそろって消える並びでも、ゲージが 100 に届いていれば入院で終わる。
    /// 「消し終えてから判定する」ほうが優しいが、ゲージは固定で増えるものなので判定も固定時に置いた。
    @Test("その手で消える並びでも、固定でゲージが 100 に届けば入院する")
    func hospitalizesBeforeClearingCanReducePain() {
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in (OjisanPuzzleBoard.rows - 3)..<OjisanPuzzleBoard.rows { board[row][0] = 1 }
        let model = OjisanPuzzleModel(
            services: nil,
            board: board,
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - OjisanPuzzlePain.perLock
        )
        #expect(model.hardDrop())   // 落とせば 1 が 4 つそろう並び
        #expect(model.outcome == .hospitalized)
        #expect(model.score == 0, "入院後に消去が走っている")
    }

    @Test("出てくる場所まで積み上がったらゲームオーバー")
    func buriesWhenSpawnIsBlocked() {
        // 出口の列（中央）を天井まで埋める。3 個ずつ種類を変えて、4 つつながって消えないようにする。
        var board = OjisanPuzzleBoard.emptyBoard()
        let column = OjisanPuzzleBoard.columns / 2 - 1
        for row in 0..<OjisanPuzzleBoard.rows {
            board[row][column] = row / 3 + 1
        }
        #expect(OjisanPuzzleBoard.clearableGroups(board).isEmpty, "前提: この盤では何も消えない")

        let model = OjisanPuzzleModel(
            services: nil,
            board: board,
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up)
        )
        #expect(model.hardDrop())
        #expect(model.outcome == nil, "固定しただけでは終わらない")
        model.tick()    // 重力も消去も起きないので、次の組を出そうとして詰まる
        #expect(model.outcome == .buried)
        #expect(model.current == nil)
    }

    @Test("落下中の組が無ければ操作を受け付けない")
    func ignoresInputWithoutFallingPair() {
        let board = OjisanPuzzleBoard.emptyBoard()
        let model = OjisanPuzzleModel(services: nil, board: board, current: nil)
        #expect(model.displayBoard == board)
        #expect(!model.move(by: 1))
        #expect(!model.rotate(clockwise: false))
        #expect(!model.softDrop())
        #expect(!model.hardDrop())
    }
}
