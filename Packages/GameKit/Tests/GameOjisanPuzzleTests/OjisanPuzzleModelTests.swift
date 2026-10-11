import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameOjisanPuzzle

/// 進行役（`OjisanPuzzleModel`）のうち、落下タイマーを回さずに確かめられる部分。
/// 判定そのものは `OjisanPuzzleBoardTests` が見ているので、ここは受け口と状態の遷移だけ。
@Suite("腰痛おじさんパズルの進行")
@MainActor
struct OjisanPuzzleModelTests {

    /// 軸 1・子 2 の組（座布団の山 + スイカ）を固定したときに増える量。
    private static let lockOf12 = OjisanPuzzlePain.lockAmount(weights: [1, 2])

    private func makeModel(mode: OjisanPuzzleMode = .backpain) -> OjisanPuzzleModel {
        OjisanPuzzleModel(services: nil, mode: mode, seed: 42)
    }

    @Test("始めたときは空の盤と落下中の組がある")
    func startsWithEmptyBoardAndPair() {
        let model = makeModel(mode: .puzzle)
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
        // 腰痛モードは最初から荷物が積まれているので、空の盤から始めて床への固定を確かめる。
        let pair = OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 2, rotation: .up)
        let model = OjisanPuzzleModel(services: nil, board: OjisanPuzzleBoard.emptyBoard(), current: pair)
        #expect(model.hardDrop())
        #expect(model.current == nil, "固定したのに落下中の組が残っている")
        #expect(model.pain == OjisanPuzzlePain.lockAmount(weights: [pair.axisKind, pair.childKind]))
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
        let model = makeModel(mode: .puzzle)
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
        #expect(model.pain == Self.lockOf12)

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
        #expect(model.pain == OjisanPuzzlePain.initial(board: model.board), "やり直しは盤から決まる開始値に戻る")
        #expect(model.pain < 90)
        #expect(model.move(by: 1), "やり直したのに待たされている")
    }

    // MARK: - 挟まれた列での回転（#2063）

    /// 1 列ぶんの隙間（col 2）に縦で収まっている組。左右は荷物で塞がっている。
    private func sandwichedModel() -> OjisanPuzzleModel {
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in 0..<OjisanPuzzleBoard.rows {
            board[row][1] = 3
            board[row][3] = 3
        }
        return OjisanPuzzleModel(
            services: nil,
            board: board,
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 5, col: 2, rotation: .up)
        )
    }

    @Test("左右を挟まれていると、1 回目は回らず、続けてもう一度押すと上下が入れ替わる")
    func secondRotatePressFlipsWhenSandwiched() throws {
        let model = sandwichedModel()
        #expect(!model.rotate(clockwise: true), "1 回目は回せない")
        #expect(try #require(model.current).rotation == .up)
        #expect(model.rotate(clockwise: true), "2 回目は反転する")
        let flipped = try #require(model.current)
        #expect(flipped.rotation == .down)
        #expect(flipped.col == 2)
        // 反転できたあとにまた塞がれたら、もう一度 2 回押しが要る（押しっぱなしで回り続けない）。
        #expect(model.rotate(clockwise: false) == false)
        #expect(model.rotate(clockwise: false))
        #expect(try #require(model.current).rotation == .up)
    }

    @Test("間に別の操作が入ったら、2 回押しの数え直し")
    func blockedPressIsForgottenAfterOtherInput() throws {
        let model = sandwichedModel()
        #expect(!model.rotate(clockwise: true))
        #expect(model.softDrop())               // 1 段落ちた
        #expect(!model.rotate(clockwise: true), "間に落下が挟まったので、これは 1 回目の扱い")
        #expect(try #require(model.current).rotation == .up)
    }

    // MARK: - 決着

    @Test("腰痛ゲージが 100 に達したら入院で終わる")
    func hospitalizesWhenPainReachesLimit() {
        // あと 1 回固定すれば 100 に届くゲージから始める。
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - Self.lockOf12
        )
        #expect(model.hardDrop())
        #expect(model.pain == OjisanPuzzlePain.limit)
        #expect(model.outcome == .hospitalized)
        // 決着したら操作も進行も受け付けない。
        #expect(!model.move(by: 1))
        model.tick()
        #expect(model.current == nil)
    }

    /// 入院は消える荷物の判定を済ませてから見る（#2063。かつては固定の瞬間に入院させていた）。
    @Test("置いた瞬間に満タンでも、その手で消えてゲージが下がるなら入院しない")
    func doesNotHospitalizeWhenTheMoveClears() {
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in (OjisanPuzzleBoard.rows - 3)..<OjisanPuzzleBoard.rows { board[row][0] = 1 }
        let model = OjisanPuzzleModel(
            services: nil,
            board: board,
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - Self.lockOf12
        )
        #expect(model.hardDrop())   // 落とせば 1 が 4 つそろう並び
        #expect(model.pain == OjisanPuzzlePain.limit, "置いた瞬間は満タン")
        #expect(model.outcome == nil, "消える判定の前に入院している")

        model.tick()    // 4 つそろった 1 が消える
        #expect(model.score == OjisanPuzzleScoring.chainPoints(cells: 4, chain: 1))
        #expect(model.pain < OjisanPuzzlePain.limit)
        model.tick()    // 上に残った荷物が落ちる
        model.tick()    // もう消えないので次の組が出る
        #expect(model.outcome == nil)
        #expect(model.current != nil)
    }

    @Test("すでにラインより下に収まる盤なら、消えなくても満タンの入院よりクリアを優先する")
    func clearBeatsImmediateHospitalization() {
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: 97,
            mode: .backpain,
            clearLineRow: OjisanPuzzleCleanup.clearLineRow
        )
        #expect(model.hardDrop())
        #expect(model.pain == OjisanPuzzlePain.limit)
        for _ in 0..<3 where model.outcome == nil { model.tick() }
        #expect(model.outcome == .cleared)
    }

    @Test("ラインより下に片付く手なら、満タンでも入院よりクリアを優先する")
    func clearBeatsHospitalization() {
        // 行 8 より上は 4 つそろう塊だけ。消えると全体がラインより下になる。
        var board = OjisanPuzzleBoard.emptyBoard()
        let line = OjisanPuzzleCleanup.clearLineRow
        for row in (line - 1)..<(line + 2) { board[row][0] = 1 }   // 縦に 3 つ（うち 1 つがライン上）
        let model = OjisanPuzzleModel(
            services: nil,
            board: board,
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - Self.lockOf12,
            mode: .backpain,
            clearLineRow: line
        )
        #expect(model.hardDrop())
        for _ in 0..<8 where model.outcome == nil { model.tick() }
        #expect(model.outcome == .cleared)
    }

    @Test("盤が出口までぎっしり埋まったらゲームオーバー")
    func buriesWhenNothingCanSpawn() {
        // 隣り合うマスがかならず別の種類になる並びで全面を埋める（何も消えない）。左上の 2 マスだけ落下中の組のために空ける。
        func kind(_ row: Int, _ col: Int) -> Int { (row + 2 * col) % 5 + 1 }
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in 0..<OjisanPuzzleBoard.rows {
            for col in 0..<OjisanPuzzleBoard.columns { board[row][col] = kind(row, col) }
        }
        board[0][0] = 0
        board[1][0] = 0
        #expect(OjisanPuzzleBoard.clearableGroups(board).isEmpty, "前提: この盤では何も消えない")

        let model = OjisanPuzzleModel(
            services: nil,
            board: board,
            current: OjisanPuzzlePair(axisKind: kind(1, 0), childKind: kind(0, 0), row: 1, col: 0, rotation: .up)
        )
        #expect(model.hardDrop())
        #expect(model.outcome == nil, "固定しただけでは終わらない")
        model.tick()    // 重力も消去も起きないので、次の組を出そうとして詰まる
        #expect(model.outcome == .buried)
        #expect(model.current == nil)
    }

    /// #1954: 出口の列が塞がったとき、別の列へ逃がすと出る場所が読めない。いつも同じ列から出し、塞がれば終わり。
    @Test("出口の列が塞がったら、ほかに空きがあっても積み上がりで終わる（#1954）")
    func buriesWhenSpawnColumnBlocked() {
        var board = OjisanPuzzleBoard.emptyBoard()
        let column = OjisanPuzzleBoard.spawnColumn
        // 3 個ずつ種類を変えて、4 つつながって消えないようにする。
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
        model.tick()
        #expect(model.outcome == .buried)
        #expect(model.current == nil)
    }

    @Test("出口の列に余裕があれば、いつも同じ列から次の組が出る（#1954）")
    func spawnsFromFixedColumn() throws {
        let model = OjisanPuzzleModel(
            services: nil,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up)
        )
        #expect(model.hardDrop())
        model.tick()
        let current = try #require(model.current)
        #expect(current.col == OjisanPuzzleBoard.spawnColumn)
        #expect(current.rotation == .up)
    }

    @Test("決着すると負けとして 1 回だけ記録し、得点を自己ベストに残す（#1904）")
    func finishRecordsLossWithPoints() throws {
        let suite = "asobiba.ojisanpuzzle.tests.record"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)

        let model = OjisanPuzzleModel(
            services: services,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - Self.lockOf12
        )
        #expect(model.hardDrop())
        #expect(model.outcome == .hospitalized)
        // 腰痛モードの記録はクリアタイムの区分（入院は勝敗の数だけ残る）。パズルモードの得点の区分とは別。
        #expect(log.record(gameID: OjisanPuzzleModule().id, variant: OjisanPuzzleMode.puzzle.recordVariant) == nil)
        let record = try #require(log.record(gameID: OjisanPuzzleModule().id, variant: OjisanPuzzleMode.backpain.recordVariant))
        #expect(record.metric == .shortestTime)
        #expect(record.plays == 1)
        #expect(record.losses == 1)
        #expect(record.bestSeconds == nil)
        #expect(model.recordResult != nil)

        // 決着後の操作は二重に記録しない。もう一度で結果は消える。
        model.tick()
        #expect(log.record(gameID: OjisanPuzzleModule().id, variant: "backpain")?.plays == 1)
        model.newGame()
        model.pause()
        #expect(model.recordResult == nil)
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
