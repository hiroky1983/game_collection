import Testing
import Foundation
@testable import GameGo

// MARK: - 連と呼吸点

@Suite("囲碁のルール: 連と呼吸点")
struct GoGroupTests {

    @Test("単独の石の呼吸点は隣接する空点の数（隅は 2・辺は 3・中央は 4）")
    func libertiesOfSingleStone() {
        let board = GoDiagram.board([
            "X....",
            ".....",
            "..X..",
            ".....",
            "X...X",
        ])
        let state = GoState(board: board, sideToMove: .black)
        #expect(state.group(at: GoPoint(row: 0, col: 0)).liberties == 2, "隅")
        #expect(state.group(at: GoPoint(row: 2, col: 2)).liberties == 4, "中央")
        #expect(state.group(at: GoPoint(row: 4, col: 4)).liberties == 2, "隅")
    }

    @Test("つながった石は 1 つの連として数え、呼吸点は重複させない")
    func groupIsMergedAndLibertiesAreDeduplicated() {
        let board = GoDiagram.board([
            ".....",
            ".XX..",
            ".X...",
            ".....",
            ".....",
        ])
        let state = GoState(board: board, sideToMove: .white)
        let group = state.group(at: GoPoint(row: 1, col: 1))
        #expect(Set(group.stones) == Set([
            GoPoint(row: 1, col: 1), GoPoint(row: 1, col: 2), GoPoint(row: 2, col: 1),
        ]))
        // (0,1)(0,2)(1,0)(1,3)(2,0)(2,2)(3,1) の 7 点。斜めはつながらない。
        #expect(group.liberties == 7)
    }

    @Test("斜めはつながらない（別々の連になる）")
    func diagonalsDoNotConnect() {
        let board = GoDiagram.board([
            "X....",
            ".X...",
            ".....",
            ".....",
            ".....",
        ])
        let state = GoState(board: board, sideToMove: .white)
        #expect(state.group(at: GoPoint(row: 0, col: 0)).stones.count == 1)
        #expect(state.group(at: GoPoint(row: 1, col: 1)).stones.count == 1)
    }
}

// MARK: - 取り

@Suite("囲碁のルール: 石を取る")
struct GoCaptureTests {

    @Test("単独の石を取る")
    func capturesSingleStone() {
        var state = GoDiagram.state([
            ".O...",
            "OX...",
            ".O...",
            ".....",
            ".....",
        ], to: .white)
        #expect(state.play(.play(row: 1, col: 2)) == nil)
        #expect(state.board[1, 1] == nil, "取られた黒石が残っている\n\(GoDiagram.text(state.board))")
        #expect(state.captures[GoStone.white.rawValue] == 1)
    }

    @Test("連なった石はまとめて取る")
    func capturesWholeGroup() {
        var state = GoDiagram.state([
            ".OO..",
            "OXX..",
            ".OO..",
            ".....",
            ".....",
        ], to: .white)
        #expect(state.play(.play(row: 1, col: 3)) == nil)
        #expect(state.board[1, 1] == nil)
        #expect(state.board[1, 2] == nil)
        #expect(state.captures[GoStone.white.rawValue] == 2)
    }

    @Test("1 手で複数方向の連を同時に取る")
    func capturesMultipleGroupsAtOnce() {
        var state = GoDiagram.state([
            "OXO..",
            "X....",
            "O....",
            ".....",
            ".....",
        ], to: .white)
        #expect(state.play(.play(row: 1, col: 1)) == nil)
        #expect(state.board[0, 1] == nil, "上の黒石が残っている")
        #expect(state.board[1, 0] == nil, "左の黒石が残っている")
        #expect(state.captures[GoStone.white.rawValue] == 2)
    }

    @Test("呼吸点が残っている連は取れない")
    func doesNotCaptureGroupWithLiberties() {
        var state = GoDiagram.state([
            ".O...",
            "OX...",
            ".....",
            ".....",
            ".....",
        ], to: .white)
        #expect(state.play(.play(row: 1, col: 2)) == nil)
        #expect(state.board[1, 1] == .black, "まだ (2,1) が空いているので取れない")
        #expect(state.captures[GoStone.white.rawValue] == 0)
    }
}

// MARK: - 自殺手

@Suite("囲碁のルール: 自殺手の禁止")
struct GoSuicideTests {

    @Test("相手に完全に囲まれた点には打てない")
    func rejectsSuicide() {
        var state = GoDiagram.state([
            ".O...",
            "O.O..",
            ".O...",
            ".....",
            ".....",
        ], to: .black)
        #expect(state.illegalReason(for: .play(row: 1, col: 1)) == .suicide)
        #expect(state.play(.play(row: 1, col: 1)) == .suicide)
        #expect(state.board[1, 1] == nil, "拒否された手で盤面が変わってはいけない")
    }

    @Test("連が呼吸点を失う手も自殺手として拒否する")
    func rejectsSuicideThatKillsOwnGroup() {
        // (1,1) に打つと黒 (1,2) とつながるが、その連の呼吸点は 0 になる。
        let state = GoDiagram.state([
            ".OO..",
            "O.XO.",
            ".OO..",
            ".....",
            ".....",
        ], to: .black)
        #expect(state.illegalReason(for: .play(row: 1, col: 1)) == .suicide)
    }

    @Test("自殺に見えるが相手の連を取るので合法（取りが自殺判定より優先される）")
    func allowsMoveThatCapturesInsteadOfSuiciding() {
        var state = GoDiagram.state([
            ".XXX.",
            "XOOOX",
            "XO.OX",
            "XOOOX",
            ".XXX.",
        ], to: .black)
        // 白の環は (2,2) だけが呼吸点。黒がそこへ打つと自分の呼吸点は 0 だが、
        // 白 8 子をまとめて取るので合法になる。
        #expect(state.illegalReason(for: .play(row: 2, col: 2)) == nil)
        #expect(state.play(.play(row: 2, col: 2)) == nil)
        #expect(state.captures[GoStone.black.rawValue] == 8)
        #expect(state.board[2, 2] == .black)
        #expect(state.group(at: GoPoint(row: 2, col: 2)).liberties == 4)
    }
}

// MARK: - コウ

@Suite("囲碁のルール: コウ")
struct GoKoTests {

    /// 教科書どおりのコウの形。黒が (1,2) に打つと白 (1,1) を取り、白はすぐには取り返せない。
    private func koPosition() -> GoState {
        GoDiagram.state([
            ".XO..",
            "XO.O.",
            ".XO..",
            ".....",
            ".....",
        ], to: .black)
    }

    @Test("取り返しの直後、同じ点への打ち返しは禁止")
    func forbidsImmediateRecapture() {
        var state = koPosition()
        #expect(state.play(.play(row: 1, col: 2)) == nil)
        #expect(state.board[1, 1] == nil, "白石が取れていない")
        #expect(state.koPoint == GoPoint(row: 1, col: 1))
        #expect(state.illegalReason(for: .play(row: 1, col: 1)) == .ko)
    }

    @Test("1 手よそへ打てば取り返せる")
    func allowsRecaptureAfterOneMoveElsewhere() {
        var state = koPosition()
        #expect(state.play(.play(row: 1, col: 2)) == nil)   // 黒: コウを取る
        #expect(state.play(.play(row: 4, col: 4)) == nil)   // 白: コウ立て
        #expect(state.koPoint == nil, "取らない手ではコウは解ける")
        #expect(state.play(.play(row: 4, col: 3)) == nil)   // 黒: 受け
        #expect(state.illegalReason(for: .play(row: 1, col: 1)) == nil)
        #expect(state.play(.play(row: 1, col: 1)) == nil)   // 白: 取り返し
        #expect(state.board[1, 2] == nil)
    }

    @Test("2 子以上を取る手はコウにならない（すぐ取り返せる）")
    func multiStoneCaptureIsNotKo() {
        var state = GoDiagram.state([
            ".OO..",
            "OXX..",
            ".OO..",
            ".....",
            ".....",
        ], to: .white)
        #expect(state.play(.play(row: 1, col: 3)) == nil)
        #expect(state.koPoint == nil, "2 子取りは単純コウの条件に当たらない")
    }

    @Test("パスするとコウは解ける")
    func passClearsKo() {
        var state = koPosition()
        #expect(state.play(.play(row: 1, col: 2)) == nil)
        #expect(state.koPoint != nil)
        #expect(state.play(.pass) == nil)
        #expect(state.koPoint == nil)
    }
}

// MARK: - 位置的スーパーコウ

@Suite("囲碁のルール: 位置的スーパーコウ（同一盤面の再現禁止）")
struct GoSuperkoTests {

    /// 3 つのコウを縦に並べた盤（三コウ）。互いに干渉しないよう 1 行あけて置く。
    ///
    /// 単純コウの禁止は「直前の 1 手」しか見ないため、コウが 3 つあると
    /// 「A を取る → B を取る → C を取る → A を取り返す → …」と**永遠に循環できてしまう**。
    /// これを止めるのが位置的スーパーコウで、6 手目でちょうど初期盤面に戻る。
    private func tripleKo() -> GoState {
        GoDiagram.state([
            ".XO..........",   // コウ A（黒が取る）
            "XO.O.........",
            ".XO..........",
            ".............",
            ".OX..........",   // コウ B（白が取る）
            "OX.X.........",
            ".OX..........",
            ".............",
            ".XO..........",   // コウ C（黒が取る）
            "XO.O.........",
            ".XO..........",
            ".............",
            ".............",
        ], to: .black)
    }

    @Test("三コウで初期盤面に戻る手は打てない（無限対局にならない）")
    func forbidsRepeatingAPreviousPosition() {
        var state = tripleKo()
        let start = state.board

        #expect(state.play(.play(row: 1, col: 2)) == nil, "黒: コウ A を取る")
        #expect(state.play(.play(row: 5, col: 2)) == nil, "白: コウ B を取る")
        #expect(state.play(.play(row: 9, col: 2)) == nil, "黒: コウ C を取る")
        #expect(state.play(.play(row: 1, col: 1)) == nil, "白: コウ A を取り返す")
        #expect(state.play(.play(row: 5, col: 1)) == nil, "黒: コウ B を取り返す")

        // ここで白が (9,1) に打つと盤面が初期状態に戻る。単純コウの禁止点は (5,2) なので
        // そちらでは止まらず、位置的スーパーコウだけが止める。
        #expect(state.koPoint == GoPoint(row: 5, col: 2))
        #expect(state.illegalReason(for: .play(row: 9, col: 1)) == .superko)
        #expect(state.play(.play(row: 9, col: 1)) == .superko)
        #expect(state.board != start, "拒否された手で盤面が変わってはいけない")
    }

    @Test("石を取らない手はスーパーコウで拒否されない（盤上の石が必ず増えるため）")
    func nonCapturingMovesAreNeverSuperko() {
        var state = tripleKo()
        for point in [GoPoint(row: 12, col: 12), GoPoint(row: 12, col: 11), GoPoint(row: 11, col: 12)] {
            #expect(state.illegalReason(for: .play(point)) == nil)
            #expect(state.play(.play(point)) == nil)
        }
    }

    @Test("プレイアウト用の局面はスーパーコウを見ない（単純コウだけを見る）")
    func playoutCopyDropsHistory() {
        let state = tripleKo()
        #expect(state.tracksSuperko)
        #expect(!state.playoutCopy().tracksSuperko)
    }
}

// MARK: - 基本の受け付け

@Suite("囲碁のルール: 着手の受け付け")
struct GoMoveAcceptanceTests {

    @Test("盤の外・すでに石がある点は理由つきで拒否する")
    func rejectsOutOfBoardAndOccupied() {
        var state = GoDiagram.state([
            "X....",
            ".....",
            ".....",
            ".....",
            ".....",
        ], to: .white)
        #expect(state.illegalReason(for: .play(row: -1, col: 0)) == .outOfBoard)
        #expect(state.illegalReason(for: .play(row: 0, col: 5)) == .outOfBoard)
        #expect(state.illegalReason(for: .play(row: 0, col: 0)) == .occupied)
        #expect(state.play(.play(row: 0, col: 0)) == .occupied)
    }

    @Test("パス 2 回で終局し、それ以降は打てない")
    func twoPassesEndTheGame() {
        var state = GoState(board: GoBoard(size: 5), sideToMove: .black)
        #expect(state.play(.pass) == nil)
        #expect(!state.isTwoPassEnd)
        #expect(state.play(.pass) == nil)
        #expect(state.isTwoPassEnd)
        #expect(state.illegalReason(for: .play(row: 2, col: 2)) == .gameOver)
        #expect(state.illegalReason(for: .pass) == .gameOver)
    }

    @Test("終局から対局へ戻すとまた打てる（簡易死活の誤判定からの復帰）")
    func resumePlayReopensTheGame() {
        var state = GoState(board: GoBoard(size: 5), sideToMove: .black)
        state.play(.pass)
        state.play(.pass)
        #expect(state.isTwoPassEnd)
        state.resumePlay()
        #expect(!state.isTwoPassEnd)
        #expect(state.illegalReason(for: .play(row: 2, col: 2)) == nil)
    }

    @Test("置き石を置くと黒が先に並び、手番は白から始まる")
    func handicapPlacesBlackStonesFirst() {
        for handicap in [2, 3, 4, 5] {
            let ruleset = GoRuleset(size: 9, handicap: handicap)
            let state = GoState.initial(ruleset: ruleset)
            #expect(state.board.stoneCount == handicap, "\(handicap) 子")
            #expect(state.sideToMove == .white)
            #expect(state.board.cells.allSatisfy { $0 != .white })
            #expect(ruleset.komi == GoRuleset.handicapKomi)
        }
    }

    @Test("互先（置き石なし）は黒番から・コミは 6.5 目")
    func evenGameStartsWithBlack() {
        let ruleset = GoRuleset(size: 9, handicap: 0)
        let state = GoState.initial(ruleset: ruleset)
        #expect(state.board.stoneCount == 0)
        #expect(state.sideToMove == .black)
        #expect(ruleset.komi == 6.5)
        #expect(ruleset.handicapCompensation == 0)
    }

    @Test("置き石は星と天元に置かれ、重複しない")
    func handicapPointsAreDistinctStars() {
        let points = GoRuleset(size: 9, handicap: 5).handicapPoints()
        #expect(points.count == 5)
        #expect(Set(points).count == 5)
        #expect(points.contains(GoPoint(row: 4, col: 4)), "5 子目は天元")
        #expect(points.allSatisfy { (0..<9).contains($0.row) && (0..<9).contains($0.col) })
    }
}

// MARK: - 眼

@Suite("囲碁のルール: 眼の判定（プレイアウトが自分の眼を埋めないため）")
struct GoEyeTests {

    @Test("四方を自分の石で囲んだ点は眼")
    func recognisesSimpleEye() {
        let state = GoDiagram.state([
            ".X...",
            "X.X..",
            ".X...",
            ".....",
            ".....",
        ], to: .black)
        #expect(state.isSimpleEye(GoPoint(row: 1, col: 1), for: .black))
        #expect(!state.isSimpleEye(GoPoint(row: 1, col: 1), for: .white))
    }

    @Test("盤の縁では斜めに相手の石が 1 つでもあれば眼とみなさない（欠け眼）")
    func edgeFalseEye() {
        let state = GoDiagram.state([
            "X.X..",
            ".XO..",
            ".....",
            ".....",
            ".....",
        ], to: .black)
        // (0,1) は上下左右（盤上にあるもの）が黒だが、斜めの (1,2) が白なので眼としない。
        #expect(!state.isSimpleEye(GoPoint(row: 0, col: 1), for: .black))
    }

    @Test("中央では斜めの相手石が 1 つまでなら眼とみなす")
    func centreAllowsOneEnemyDiagonal() {
        // (2,1) の上下左右は黒。斜めのうち (1,0) だけが白なので、中央の点なら眼として扱う。
        let state = GoDiagram.state([
            ".....",
            "OX...",
            "X.X..",
            ".X...",
            ".....",
        ], to: .black)
        #expect(state.isSimpleEye(GoPoint(row: 2, col: 1), for: .black))
    }

    @Test("石のある点は眼ではない")
    func occupiedPointIsNotAnEye() {
        let state = GoDiagram.state([
            "X....",
            ".....",
            ".....",
            ".....",
            ".....",
        ], to: .black)
        #expect(!state.isSimpleEye(GoPoint(row: 0, col: 0), for: .black))
    }
}
