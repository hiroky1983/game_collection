import Testing
@testable import GameOjisanPuzzle

/// 盤のロジック（連結判定・消去・重力・連鎖）。すべて純関数なので盤を直接組んで確かめる。
///
/// 盤の書き方: 1 行 = 6 文字（`.` が空きマス、`1`...`4` が荷物の種類）。**下の行から並べる**ので、
/// 配列の最後の要素が床（`rows - 1`）になる。足りない上の段は空きで埋める。
@Suite("腰痛おじさんパズルの盤")
struct OjisanPuzzleBoardTests {

    /// 下から順に積んだ行から盤を作る。
    static func board(fromBottom rows: [String]) -> [[Int]] {
        var board = OjisanPuzzleBoard.emptyBoard()
        for (index, text) in rows.enumerated() {
            let row = OjisanPuzzleBoard.rows - 1 - index
            for (col, char) in text.enumerated() {
                board[row][col] = char == "." ? 0 : Int(String(char)) ?? 0
            }
        }
        return board
    }

    // MARK: - 連結判定

    @Test("上下左右でつながっている同じ種類をまとめて数える")
    func connectsOrthogonally() {
        let board = Self.board(fromBottom: [
            "11....",
            "1.....",
            "1.....",
        ])
        let group = OjisanPuzzleBoard.connectedGroup(board, row: OjisanPuzzleBoard.rows - 1, col: 0)
        #expect(group.count == 4)
        #expect(group.contains(OjisanPuzzleCell(row: OjisanPuzzleBoard.rows - 1, col: 1)))
    }

    @Test("斜めはつながらない")
    func doesNotConnectDiagonally() {
        let board = Self.board(fromBottom: [
            "1.....",
            ".1....",
        ])
        let group = OjisanPuzzleBoard.connectedGroup(board, row: OjisanPuzzleBoard.rows - 1, col: 0)
        #expect(group.count == 1)
    }

    @Test("種類が違えばつながらない")
    func doesNotConnectDifferentKinds() {
        let board = Self.board(fromBottom: ["1233.."])
        #expect(OjisanPuzzleBoard.connectedGroup(board, row: OjisanPuzzleBoard.rows - 1, col: 0).count == 1)
        #expect(OjisanPuzzleBoard.connectedGroup(board, row: OjisanPuzzleBoard.rows - 1, col: 2).count == 2)
    }

    @Test("空きマス・盤の外を指したら空")
    func emptyAndOutsideYieldNothing() {
        let board = OjisanPuzzleBoard.emptyBoard()
        #expect(OjisanPuzzleBoard.connectedGroup(board, row: 0, col: 0).isEmpty)
        #expect(OjisanPuzzleBoard.connectedGroup(board, row: -1, col: 0).isEmpty)
        #expect(OjisanPuzzleBoard.connectedGroup(board, row: 0, col: OjisanPuzzleBoard.columns).isEmpty)
    }

    // MARK: - 消去

    @Test("3つではまだ消えない")
    func threeDoesNotClear() {
        let board = Self.board(fromBottom: ["111..."])
        #expect(OjisanPuzzleBoard.clearableGroups(board).isEmpty)
    }

    @Test("4つつながったら消える")
    func fourClears() {
        let board = Self.board(fromBottom: ["1111.."])
        let groups = OjisanPuzzleBoard.clearableGroups(board)
        #expect(groups.count == 1)
        #expect(groups.first?.count == 4)
    }

    @Test("離れた2か所は同時に消える")
    func twoGroupsClearTogether() {
        let board = Self.board(fromBottom: [
            "1111.1",
            "....22",
            "....22",
        ])
        let groups = OjisanPuzzleBoard.clearableGroups(board)
        #expect(groups.count == 2)
        #expect(groups.map(\.count).sorted() == [4, 4])
    }

    @Test("消した塊だけが空きマスになる")
    func removingClearsOnlyTheGroup() {
        let board = Self.board(fromBottom: ["11112."])
        let cleared = OjisanPuzzleBoard.removing(board, groups: OjisanPuzzleBoard.clearableGroups(board))
        let floor = OjisanPuzzleBoard.rows - 1
        #expect(cleared[floor][0] == 0)
        #expect(cleared[floor][3] == 0)
        #expect(cleared[floor][4] == 2)
    }

    // MARK: - 重力

    @Test("浮いている荷物は順序を保ったまま下まで落ちる")
    func gravityPacksColumnsDownward() {
        var board = OjisanPuzzleBoard.emptyBoard()
        board[0][0] = 1     // 一番上
        board[5][0] = 2     // 途中
        let settled = OjisanPuzzleBoard.applyingGravity(board)
        let floor = OjisanPuzzleBoard.rows - 1
        #expect(settled[floor][0] == 2)
        #expect(settled[floor - 1][0] == 1)
        #expect(settled[0][0] == 0)
    }

    @Test("既に詰まっている盤は重力で変わらない")
    func gravityIsIdempotentOnSettledBoard() {
        let board = Self.board(fromBottom: ["123412", "1....."])
        #expect(OjisanPuzzleBoard.applyingGravity(board) == board)
    }

    // MARK: - 連鎖

    @Test("消えた上の荷物が落ちてきて連鎖する")
    func clearsChain() {
        // 1 列に「2・2・1・1・1・1・2・2」と積む。まず縦の 1 が 4 つ消え、
        // 分かれていた 2 が落ちて合流して 4 つになり、2 連鎖目が起きる。
        let board = Self.board(fromBottom: [
            "2.....",
            "2.....",
            "1.....",
            "1.....",
            "1.....",
            "1.....",
            "2.....",
            "2.....",
        ])
        let result = OjisanPuzzleBoard.resolve(board)
        #expect(result.chains == [4, 4], "連鎖の内訳が違う: \(result.chains)")
        #expect(result.board == OjisanPuzzleBoard.emptyBoard(), "連鎖のあとに荷物が残っている")
    }

    @Test("消える塊が無ければ連鎖は 0 回で、盤は詰めただけ")
    func resolveWithoutClearsOnlyPacks() {
        var board = OjisanPuzzleBoard.emptyBoard()
        board[0][3] = 3
        let result = OjisanPuzzleBoard.resolve(board)
        #expect(result.chains.isEmpty)
        #expect(result.board[OjisanPuzzleBoard.rows - 1][3] == 3)
    }

    // MARK: - 落ちてくる 2 個組

    @Test("最初の組は盤の上・中央に出る")
    func spawnsAtTopCenter() {
        let pair = OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2)
        #expect(pair.row == 1)
        #expect(pair.col == OjisanPuzzleBoard.columns / 2 - 1)
        #expect(pair.rotation == .up)
        #expect(pair.childRow == 0)
        #expect(OjisanPuzzleBoard.canPlace(OjisanPuzzleBoard.emptyBoard(), pair))
    }

    @Test("左右へ動かせる。壁の外へは動かせない")
    func movesWithinWalls() {
        let board = OjisanPuzzleBoard.emptyBoard()
        var pair = OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2)
        pair.col = 0
        #expect(OjisanPuzzleBoard.moved(board, pair, byColumns: -1) == nil)
        #expect(OjisanPuzzleBoard.moved(board, pair, byColumns: 1)?.col == 1)
    }

    @Test("埋まっているマスへは動かせない")
    func doesNotMoveIntoOccupiedCell() {
        var board = OjisanPuzzleBoard.emptyBoard()
        board[1][3] = 4
        let pair = OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2)   // 軸は (1, 2)
        #expect(OjisanPuzzleBoard.moved(board, pair, byColumns: 1) == nil)
    }

    @Test("一気に落とすと床まで落ちる")
    func hardDropReachesFloor() {
        let board = OjisanPuzzleBoard.emptyBoard()
        let dropped = OjisanPuzzleBoard.hardDropped(board, OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2))
        #expect(dropped.row == OjisanPuzzleBoard.rows - 1)
        #expect(dropped.childRow == OjisanPuzzleBoard.rows - 2)
    }

    @Test("一気に落とすと積んである荷物の上で止まる")
    func hardDropStopsOnStack() {
        let board = Self.board(fromBottom: ["..3...", "..3..."])
        let dropped = OjisanPuzzleBoard.hardDropped(board, OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2))
        #expect(dropped.row == OjisanPuzzleBoard.rows - 3)
    }

    @Test("床に着いたらそれ以上下がらない")
    func steppedDownReturnsNilAtFloor() {
        let board = OjisanPuzzleBoard.emptyBoard()
        let dropped = OjisanPuzzleBoard.hardDropped(board, OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2))
        #expect(OjisanPuzzleBoard.steppedDown(board, dropped) == nil)
    }

    @Test("回すと子の位置が 4 方向を巡る")
    func rotationCyclesThroughFourDirections() throws {
        let board = OjisanPuzzleBoard.emptyBoard()
        var pair = OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2)
        pair.row = 5
        let order: [OjisanPuzzleRotation] = [.right, .down, .left, .up]
        var current = pair
        for expected in order {
            current = try #require(OjisanPuzzleBoard.rotated(board, current, clockwise: true))
            #expect(current.rotation == expected)
        }
        #expect(current == pair)
    }

    @Test("壁ぎわで回すと軸がずれて逃げる（壁蹴り）")
    func rotationKicksOffTheWall() throws {
        let board = OjisanPuzzleBoard.emptyBoard()
        var pair = OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2)
        pair.row = 5
        pair.col = OjisanPuzzleBoard.columns - 1   // 右端。子を右へ回すと盤の外に出る
        let turned = try #require(OjisanPuzzleBoard.rotated(board, pair, clockwise: true))
        #expect(turned.rotation == .right)
        #expect(turned.col == OjisanPuzzleBoard.columns - 2, "軸が左へ逃げていない")
        #expect(turned.childCol == OjisanPuzzleBoard.columns - 1)
    }

    @Test("逃げ場が無ければ回せない")
    func rotationFailsWhenBoxedIn() {
        var board = OjisanPuzzleBoard.emptyBoard()
        // 1 列ぶんの隙間に縦に収まっている状態で、横向きにはどうやっても回せない。
        var pair = OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2)
        pair.row = 5
        pair.col = 2
        for row in 0..<OjisanPuzzleBoard.rows {
            board[row][1] = 3
            board[row][3] = 3
        }
        #expect(OjisanPuzzleBoard.rotated(board, pair, clockwise: true) == nil)
        #expect(OjisanPuzzleBoard.rotated(board, pair, clockwise: false) == nil)
    }

    @Test("固定すると 2 マスとも盤に入る")
    func lockingWritesBothCells() {
        let board = OjisanPuzzleBoard.emptyBoard()
        let dropped = OjisanPuzzleBoard.hardDropped(board, OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2))
        let locked = OjisanPuzzleBoard.locking(board, dropped)
        #expect(locked[dropped.row][dropped.col] == 1)
        #expect(locked[dropped.childRow][dropped.childCol] == 2)
    }

    @Test("盤として妥当かを見分ける")
    func validatesBoardShape() {
        #expect(OjisanPuzzleBoard.isValid(OjisanPuzzleBoard.emptyBoard()))
        var broken = OjisanPuzzleBoard.emptyBoard()
        broken[0][0] = OjisanPuzzleBoard.kindCount + 1
        #expect(!OjisanPuzzleBoard.isValid(broken))
        #expect(!OjisanPuzzleBoard.isValid([[0, 0]]))
    }
}

/// 運ぶ荷物の中身（何を運んでいるか・重さ）。
@Suite("荷物の種類")
struct OjisanPuzzleLuggageTests {

    @Test("盤に入る 1...4 のすべてに中身がある")
    func everyValueHasKind() {
        for value in 1...OjisanPuzzleBoard.kindCount {
            let kind = OjisanPuzzleLuggage.kind(value)
            #expect(kind != nil, "\(value) に対応する荷物が無い")
            #expect(kind?.name.isEmpty == false)
            #expect(kind?.symbol.isEmpty == false)
        }
        #expect(OjisanPuzzleLuggage.all.count == OjisanPuzzleBoard.kindCount)
    }

    @Test("空きマス・範囲外には中身が無い")
    func emptyAndOutOfRangeHaveNoKind() {
        #expect(OjisanPuzzleLuggage.kind(0) == nil)
        #expect(OjisanPuzzleLuggage.kind(OjisanPuzzleBoard.kindCount + 1) == nil)
    }

    @Test("見分けが付くよう、絵柄は 4 種とも違う")
    func symbolsAreDistinct() {
        #expect(Set(OjisanPuzzleLuggage.all.map(\.symbol)).count == OjisanPuzzleLuggage.all.count)
        #expect(Set(OjisanPuzzleLuggage.all.map(\.name)).count == OjisanPuzzleLuggage.all.count)
    }

    @Test("軽い順に並んでいる（表示の濃さがこの順に付く）")
    func weightsAreAscending() {
        let weights = OjisanPuzzleLuggage.all.map(\.weight)
        #expect(weights == weights.sorted())
        #expect(weights.first == 1)
    }
}

/// 腰痛ゲージと得点。
@Suite("腰痛ゲージと得点")
struct OjisanPuzzlePainTests {

    @Test("荷物を固定するたびにゲージが増える")
    func lockingIncreasesPain() {
        #expect(OjisanPuzzlePain.afterLock(0) == OjisanPuzzlePain.perLock)
        #expect(OjisanPuzzlePain.afterLock(20) == 20 + OjisanPuzzlePain.perLock)
    }

    @Test("消すとゲージが減る。連鎖が深いほどよく減る")
    func clearingReducesPain() {
        #expect(OjisanPuzzlePain.afterChain(50, cells: 4, chain: 1) == 50 - 8)
        #expect(OjisanPuzzlePain.afterChain(50, cells: 4, chain: 2) == 50 - 8 - OjisanPuzzlePain.perExtraChain)
        #expect(OjisanPuzzlePain.afterClears(50, chains: [4, 4]) == 50 - 8 - 8 - OjisanPuzzlePain.perExtraChain)
    }

    @Test("ゲージは 0...100 に収まる")
    func painStaysInRange() {
        #expect(OjisanPuzzlePain.afterChain(3, cells: 10, chain: 3) == 0)
        #expect(OjisanPuzzlePain.afterLock(OjisanPuzzlePain.limit) == OjisanPuzzlePain.limit)
    }

    @Test("100 になったら入院")
    func hospitalizedAtLimit() {
        #expect(!OjisanPuzzlePain.isHospitalized(99))
        #expect(OjisanPuzzlePain.isHospitalized(OjisanPuzzlePain.limit))
    }

    // MARK: - 腰痛が遊びに効く（会長指示 2026-09-17）

    @Test("ゲージから 3 段階が引ける")
    func stagesFollowThresholds() {
        #expect(OjisanPuzzlePain.stage(for: 0) == .easy)
        #expect(OjisanPuzzlePain.stage(for: 39) == .easy)
        #expect(OjisanPuzzlePain.stage(for: 40) == .aching)
        #expect(OjisanPuzzlePain.stage(for: 79) == .aching)
        #expect(OjisanPuzzlePain.stage(for: 80) == .severe)
        #expect(OjisanPuzzlePain.stage(for: OjisanPuzzlePain.limit) == .severe)
    }

    @Test("段階の境目は定数と一致している（調整しても検査が追う）")
    func stagesMatchThresholds() {
        for threshold in OjisanPuzzlePain.stageThresholds {
            #expect(OjisanPuzzlePain.stage(for: threshold - 1) < OjisanPuzzlePain.stage(for: threshold),
                    "\(threshold) の前後で段階が上がっていない")
        }
        #expect(OjisanPuzzlePain.stageThresholds.count + 1 == OjisanPuzzlePain.Stage.allCases.count)
    }

    @Test("腰が重いほど荷物が速く落ちる")
    func fallsFasterWhenPainRises() {
        #expect(OjisanPuzzlePain.fallFactor(for: 0) == 1.0)
        #expect(OjisanPuzzlePain.fallFactor(for: 50) < OjisanPuzzlePain.fallFactor(for: 0))
        #expect(OjisanPuzzlePain.fallFactor(for: 90) < OjisanPuzzlePain.fallFactor(for: 50))
        #expect(OjisanPuzzlePain.fallFactor(for: 90) > 0, "止まってしまう係数にはしない")
    }

    @Test("腰が重いほど左右移動・回転がワンテンポ遅れる")
    func inputGetsSluggishWhenPainRises() {
        #expect(OjisanPuzzlePain.inputDelayMilliseconds(for: 0) == 0)
        #expect(OjisanPuzzlePain.inputDelayMilliseconds(for: 50) > 0)
        #expect(OjisanPuzzlePain.inputDelayMilliseconds(for: 90)
                > OjisanPuzzlePain.inputDelayMilliseconds(for: 50))
    }

    @Test("段階ごとに呼び名がある")
    func everyStageHasCaption() {
        for stage in OjisanPuzzlePain.Stage.allCases {
            #expect(!stage.caption.isEmpty)
        }
        #expect(Set(OjisanPuzzlePain.Stage.allCases.map(\.caption)).count
                == OjisanPuzzlePain.Stage.allCases.count)
    }

    @Test("連鎖が深いほど点が伸びる")
    func deeperChainsScoreMore() {
        #expect(OjisanPuzzleScoring.chainPoints(cells: 4, chain: 1) == 40)
        #expect(OjisanPuzzleScoring.chainPoints(cells: 4, chain: 2) == 80)
        #expect(OjisanPuzzleScoring.totalPoints(chains: [4, 4]) == 120)
        #expect(OjisanPuzzleScoring.totalPoints(chains: []) == 0)
    }
}
