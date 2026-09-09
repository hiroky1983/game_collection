import Testing
import Foundation
@testable import GameGo

/// 面積計算の**独立参照実装**（#398 のテスト計画 6）。
///
/// 本実装（`GoScoring.area`）は空点の連結領域を 1 回ずつまとめて処理するが、こちらは
/// **1 点ごとに独立して flood-fill をやり直す** 素朴版。同じ答えになることをランダム局面で
/// 突き合わせれば、領域のまとめ方に潜むバグ（訪問済みフラグの取り違え等）を検出できる。
enum GoScoringReference {
    static func area(of board: GoBoard) -> (black: Int, white: Int, neutral: Int) {
        var black = 0, white = 0, neutral = 0
        for row in 0..<board.size {
            for col in 0..<board.size {
                let point = GoPoint(row: row, col: col)
                if let stone = board[point] {
                    if stone == .black { black += 1 } else { white += 1 }
                    continue
                }
                switch owner(of: point, on: board) {
                case .some(.black): black += 1
                case .some(.white): white += 1
                case nil:           neutral += 1
                }
            }
        }
        return (black, white, neutral)
    }

    /// その空点から到達できる石の色が 1 色だけならその色、そうでなければ nil。
    private static func owner(of point: GoPoint, on board: GoBoard) -> GoStone? {
        var seen: Set<GoPoint> = [point]
        var queue = [point]
        var colors = Set<GoStone>()
        while let current = queue.first {
            queue.removeFirst()
            board.forEachNeighbor(of: current) { neighbor in
                if let stone = board[neighbor] {
                    colors.insert(stone)
                } else if seen.insert(neighbor).inserted {
                    queue.append(neighbor)
                }
            }
        }
        return colors.count == 1 ? colors.first : nil
    }
}

// MARK: - 面積計算

@Suite("囲碁の終局: 面積計算（中国ルール）")
struct GoAreaScoringTests {

    @Test("石と、その色だけに囲まれた空点を数える")
    func countsStonesAndSurroundedPoints() {
        // 左 2 列が黒、右 2 列が白、中央の 1 列は双方に接するので中立。
        let board = GoDiagram.board([
            ".X.O.",
            ".X.O.",
            ".X.O.",
            ".X.O.",
            ".X.O.",
        ])
        let counted = GoScoring.area(of: board)
        #expect(counted.black == 10, "黒石 5 + 左の空点 5")
        #expect(counted.white == 10, "白石 5 + 右の空点 5")
        #expect(counted.neutral == 5, "中央の列は双方に接する")
    }

    @Test("保存則: 黒の面積 + 白の面積 + 中立 = 交点数（ランダム局面 200 件）")
    func conservationLawHolds() {
        var random = GoRandom(seed: 0xC0FFEE)
        for _ in 0..<200 {
            var state = GoState.initial(ruleset: GoRuleset(size: 9), tracksSuperko: false)
            let plies = random.index(below: 70)
            for _ in 0..<plies { state.play(GoPlayout.move(in: state, random: &random)) }
            let counted = GoScoring.area(of: state.board)
            #expect(counted.black + counted.white + counted.neutral == state.board.pointCount,
                    "保存則が崩れた\n\(GoDiagram.text(state.board))")
        }
    }

    @Test("独立した参照実装（1 点ずつ flood-fill）と一致する（ランダム局面 200 件）")
    func matchesIndependentReferenceImplementation() {
        var random = GoRandom(seed: 0x5EED_1234)
        for _ in 0..<200 {
            var state = GoState.initial(ruleset: GoRuleset(size: 9), tracksSuperko: false)
            let plies = random.index(below: 90)
            for _ in 0..<plies { state.play(GoPlayout.move(in: state, random: &random)) }
            let mine = GoScoring.area(of: state.board)
            let reference = GoScoringReference.area(of: state.board)
            #expect(mine == reference, "参照実装と食い違う\n\(GoDiagram.text(state.board))")
        }
    }

    @Test("空の盤はすべて中立（どちらの色にも囲まれていない）")
    func emptyBoardIsAllNeutral() {
        let counted = GoScoring.area(of: GoBoard(size: 9))
        #expect(counted == (black: 0, white: 0, neutral: 81))
    }

    @Test("全部が片方の石なら面積は交点数と一致する")
    func fullBoardOfOneColour() {
        let board = GoBoard(size: 5, cells: Array(repeating: GoStone.black, count: 25))
        let counted = GoScoring.area(of: board)
        #expect(counted == (black: 25, white: 0, neutral: 0))
    }
}

// MARK: - セキ

@Suite("囲碁の終局: セキ")
struct GoSekiTests {

    /// セキ（相互に取れない形）。白の外壁の中に黒の環があり、その中に白 2 子がいる。
    /// 黒の環と内側の白 2 子は **(2,2) と (2,3) の 2 点だけを共有の呼吸点**にしている。
    private func sekiBoard() -> GoBoard {
        GoDiagram.board([
            "OOOOOO...",
            "OXXXXO...",
            "OX..XO...",
            "OXOOXO...",
            "OXXXXO...",
            "OOOOOO...",
            ".........",
            ".........",
            ".........",
        ])
    }

    @Test("セキの当事者はどちらも呼吸点 2 で、先に詰めたほうが取られる")
    func neitherSideCanFillWithoutLosing() {
        let board = sekiBoard()
        var black = GoState(board: board, sideToMove: .black)
        var white = GoState(board: board, sideToMove: .white)

        #expect(black.group(at: GoPoint(row: 1, col: 1)).liberties == 2, "黒の環の呼吸点")
        #expect(black.group(at: GoPoint(row: 3, col: 2)).liberties == 2, "内側の白 2 子の呼吸点")

        // 黒が (2,2) を詰めると自分が呼吸点 1 になり、白の (2,3) で環ごと取られる。
        #expect(black.play(.play(row: 2, col: 2)) == nil)
        #expect(black.group(at: GoPoint(row: 1, col: 1)).liberties == 1)
        #expect(black.play(.play(row: 2, col: 3)) == nil)
        #expect(black.board[1, 1] == nil, "黒の環が取られていない\n\(GoDiagram.text(black.board))")

        // 白が先に詰めても同じことが起きる（内側の白 2 子が取られる）。
        #expect(white.play(.play(row: 2, col: 2)) == nil)
        #expect(white.play(.play(row: 2, col: 3)) == nil)
        #expect(white.board[3, 2] == nil, "内側の白が取られていない\n\(GoDiagram.text(white.board))")
    }

    /// 仕様（`GoScore` のコメントにも明記）: 面積計算はセキを特別扱いしない。
    /// セキの石は持ち主の面積に入り、共有のダメはどちらの色にも囲まれていないので中立になる。
    @Test("面積計算はセキを特別扱いしない（石は持ち主に・共有のダメは中立）")
    func sekiIsCountedByPlainAreaRules() {
        let counted = GoScoring.area(of: sekiBoard())
        #expect(counted.black == 12, "黒の環の石 12")
        #expect(counted.white == 67, "白石 22 + 外側の白地 45")
        #expect(counted.neutral == 2, "共有のダメ (2,2)(2,3)")
        #expect(counted.black + counted.white + counted.neutral == 81)
    }
}

// MARK: - コミ・置き石

@Suite("囲碁の終局: コミと置き石の補正")
struct GoKomiTests {

    private let halfBoard = GoDiagram.board([
        ".X.O.",
        ".X.O.",
        ".X.O.",
        ".X.O.",
        ".X.O.",
    ])

    @Test("コミは白に加算される（黒 10 / 白 10 + 6.5 なら白の 6.5 目勝ち）")
    func komiGoesToWhite() {
        let score = GoScoring.score(board: halfBoard, ruleset: GoRuleset(size: 5, handicap: 0))
        #expect(score.blackTotal == 10)
        #expect(score.whiteTotal == 16.5)
        #expect(score.winner == .white)
        #expect(score.margin == -6.5)
        #expect(score.summary == "白 6.5目勝ち")
    }

    @Test("置き石があるとコミは 0.5 目になり、置き石 1 子につき 1 目を白に補正する")
    func handicapCompensatesWhite() {
        var ruleset = GoRuleset(size: 5, handicap: 4)
        #expect(ruleset.komi == 0.5)
        #expect(ruleset.handicapCompensation == 4)
        let score = GoScoring.score(board: halfBoard, ruleset: ruleset)
        #expect(score.blackTotal == 10)
        #expect(score.whiteTotal == 14.5, "白 10 + コミ 0.5 + 置き石補正 4")
        #expect(score.winner == .white)

        // 補正が無ければ差は 0.5 目しかない。置き石 4 子ぶんがそのまま差に乗っている。
        ruleset.handicap = 0
        ruleset.komi = 0.5
        #expect(GoScoring.score(board: halfBoard, ruleset: ruleset).margin == -0.5)
        #expect(score.margin == -4.5)
    }

    @Test("半目のコミがあるので引き分けにならない（ランダム局面 100 件）")
    func halfKomiRemovesDraws() {
        var random = GoRandom(seed: 0xD1CE)
        let ruleset = GoRuleset(size: 9)
        for _ in 0..<100 {
            var state = GoState.initial(ruleset: ruleset, tracksSuperko: false)
            GoPlayout.run(&state, random: &random)
            #expect(GoScoring.score(board: state.board, ruleset: ruleset).winner != nil)
        }
    }

    @Test("死に石を取り除いてから数える")
    func removesDeadStonesBeforeCounting() {
        // 黒地の中に取り残された白 1 子。生きたままなら黒地が 1 目減る。
        let board = GoDiagram.board([
            "XXXXX",
            "X...X",
            "X.O.X",
            "X...X",
            "XXXXX",
        ])
        let ruleset = GoRuleset(size: 5)
        let alive = GoScoring.score(board: board, ruleset: ruleset)
        #expect(alive.blackArea == 16, "白石が生きている扱いだと中の空点は中立になる")

        let dead = GoScoring.score(board: board, removing: [GoPoint(row: 2, col: 2)], ruleset: ruleset)
        #expect(dead.blackArea == 25, "死に石を上げれば盤全部が黒")
        #expect(dead.whiteArea == 0)
    }
}

// MARK: - 簡易死活

@Suite("囲碁の終局: 簡易死活の判定")
struct GoDeadStoneTests {

    @Test("囲まれて生きられない石は死んだと判定する")
    func detectsClearlyDeadStones() {
        // 黒の完全な地の中に白 1 子。どう打っても白は生きられない。
        let state = GoDiagram.state([
            "XXXXXXXXX",
            "X.......X",
            "X..O....X",
            "X.......X",
            "X.......X",
            "X.......X",
            "X.......X",
            "X.......X",
            "XXXXXXXXX",
        ], to: .black)
        let analysis = GoDeadStones.analyze(state: state, playouts: 300, seed: 11)
        #expect(analysis.dead.contains(GoPoint(row: 2, col: 3)), "囲まれた白石が死と判定されていない")
        #expect(analysis.isConfident, "明確な形なのに曖昧と判定されている（\(analysis.uncertainty)）")
    }

    @Test("二眼で生きている石は死と判定しない")
    func keepsAliveGroups() {
        // 白は隅で二眼を持って生きている。
        let state = GoDiagram.state([
            "OO.O.OOOO",
            "OOOOOOOOO",
            "XXXXXXXXX",
            ".........",
            ".........",
            ".........",
            ".........",
            "XXXXXXXXX",
            "XX.X.XXXX",
        ], to: .black)
        let analysis = GoDeadStones.analyze(state: state, playouts: 300, seed: 13)
        #expect(!analysis.dead.contains(GoPoint(row: 0, col: 0)), "生きている白が死と判定された")
        #expect(!analysis.dead.contains(GoPoint(row: 1, col: 4)))
    }

    @Test("同じ種なら結果が 1 ビットも変わらない（判定を再現できる）")
    func isDeterministicForTheSameSeed() {
        let state = GoDiagram.state([
            "XXXXXXXXX",
            "X.......X",
            "X..O....X",
            "X.......X",
            "X.......X",
            "X.......X",
            "X.......X",
            "X.......X",
            "XXXXXXXXX",
        ], to: .black)
        let first = GoDeadStones.analyze(state: state, playouts: 120, seed: 99)
        let second = GoDeadStones.analyze(state: state, playouts: 120, seed: 99)
        #expect(first == second)
    }

    @Test("プレイアウト 0 回では何も死と判定せず、曖昧として返す")
    func zeroPlayoutsIsTreatedAsUncertain() {
        let state = GoState.initial(ruleset: GoRuleset(size: 9))
        let analysis = GoDeadStones.analyze(state: state, playouts: 0)
        #expect(analysis.dead.isEmpty)
        #expect(!analysis.isConfident)
    }
}
