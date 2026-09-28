import Testing
import Foundation
import Core
import CoreEngine
@testable import GameChess

/// CPU の思考。
///
/// **時間切れに依存させない**（#177 の教訓）。`timeLimit` は探索の打ち切りにしか使わないので、
/// テストでは十分に大きく取って「指定した深さを必ず読み切った結果」だけを検証する。
/// CI のデバッグビルドは実測で 10 倍以上遅く、時間で切ると同じ入力でも別の手を返してフレークする。
@Suite("チェスの CPU")
struct EngineTests {

    /// 時間で打ち切られない探索。
    private func engine(
        depth: Int, positional: Bool = true, quiescence: Bool = true, book: Bool = false
    ) -> SimpleChessEngine {
        SimpleChessEngine(
            depth: depth, usePositional: positional, useQuiescence: quiescence,
            useBook: book, timeLimit: 600
        )
    }

    @Test("初期局面で合法手を返す")
    func returnsLegalMoveFromStart() async {
        let uci = await engine(depth: 2).bestMove(fen: ChessPosition.startFEN)
        #expect(uci != nil)
        guard let uci, let move = ChessMove.fromUCI(uci) else { return }
        #expect(ChessPosition.start().legalMoves().contains(move))
    }

    @Test("合法手が無い局面では nil を返す（詰み・ステイルメイト）")
    func returnsNilWhenNoLegalMoves() async {
        #expect(await engine(depth: 2).bestMove(fen: "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1") == nil)
        #expect(await engine(depth: 2).bestMove(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1") == nil)
    }

    @Test("1手詰めを見つける")
    func findsMateInOne() async {
        // 白番。Ra8 でバックランクメイト。
        let uci = await engine(depth: 2).bestMove(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        #expect(uci == "a1a8")
    }

    @Test("ただで取れるクイーンを取る")
    func capturesHangingQueen() async {
        // d5 の黒クイーンは白ルークで取れて、取り返されない。
        let uci = await engine(depth: 3).bestMove(fen: "4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1")
        #expect(uci == "d1d5")
    }

    @Test("ステイルメイトを引き分けとして扱う（勝勢でわざと膠着させない）")
    func avoidsStalemateWhenWinning() async {
        // 白は K+Q vs K で圧勝。h8 の黒キングに対し Qf7 はステイルメイトなので選んではいけない。
        // 「合法手ゼロ = 負け」で括る実装（将棋の写し）だと、ここで Qf7 が最善に化ける。
        let fen = "7k/8/6K1/5Q2/8/8/8/8 w - - 0 1"
        let uci = await engine(depth: 3).bestMove(fen: fen)
        #expect(uci != nil)
        guard let uci, let move = ChessMove.fromUCI(uci),
              var pos = ChessPosition.fromFEN(fen) else { return }
        pos.make(move)
        let isStalemate = pos.legalMoves().isEmpty && !pos.isKingInCheck(pos.sideToMove)
        #expect(isStalemate == false, "\(uci) はステイルメイトになる")
    }

    @Test("難易度の設定が表示している文言と一致する（#416・#1462）")
    func levelsMatchTheirLabels() {
        // 段階の差は考える時間・深さの上限・最善手の確率だけ（会長決裁 2026-09-27）。上の段ほど長く深く読む。
        let engines = CPUStrength.allCases.map { SimpleChessEngine(level: $0.rawValue) }
        #expect(engines.map(\.timeLimit) == [0.02, 0.1, 0.5, 2])
        #expect(engines.map(\.depth) == [1, 2, 3, SimpleChessEngine.maxDepth])
        #expect(engines.allSatisfy { $0.usePositional && $0.useQuiescence && $0.nodeLimit == nil })
        // 定跡は「むずかしい」だけの売り。
        #expect(engines.map(\.useBook) == [false, false, false, true])
    }

    @Test("定跡は「強」だけが使い、初手は定跡どおりに指す")
    func bookIsUsedOnlyByStrongLevel() async {
        let booked = await engine(depth: 1, book: true).bestMove(fen: ChessPosition.startFEN)
        #expect(["e2e4", "d2d4", "c2c4"].contains(booked ?? ""), "登録した初手のどれか")
        // 定跡は手数を無視したキーで引くので、別の手順で同じ局面に来ても効く。
        let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        #expect(await engine(depth: 1, book: true).bestMove(fen: afterE4) != nil)
    }

    @Test("深く読む設定はクイーンを只で捨てない")
    func deepSearchKeepsTheQueen() async {
        // 白のクイーンが d5 に出ると、c6 の黒ポーンでも e6 の黒ポーンでも取られる。
        // 深さ 3 の探索は取り返される手を選ばないことを固定する。
        let fen = "rnbqkbnr/pp1p1ppp/2p1p3/8/3Q4/8/PPP1PPPP/RNB1KBNR w KQkq - 0 1"
        let strong = await engine(depth: 3).bestMove(fen: fen)
        #expect(strong != nil)
        guard let strong, let move = ChessMove.fromUCI(strong),
              var pos = ChessPosition.fromFEN(fen) else { return }
        pos.make(move)
        // 指したあとにクイーンがただで取られる状態になっていないこと。
        if let queen = pos.squares.firstIndex(where: {
            $0 == ChessPiece(type: .queen, color: .white)
        }) {
            #expect(pos.isAttacked(queen, by: .black) == false, "強い設定はクイーンを只で捨てない")
        }
    }

    /// 静止探索の穴（CodeRabbit 指摘・Major）。`quiesce` が終局を見ずに `evaluate` を返すと、
    /// 取る手で詰んだ局面が「駒得」としてしか数えられず、詰みを見落とす。
    ///
    /// **返り値を正確に突き合わせる**。「十分に負の値か」だけを見ると、探索が何も読まずに
    /// `alpha` をそのまま返しているだけでも通ってしまう（変異テストで実測した穴）。
    @Test("静止探索は終局を静的評価で誤魔化さない（詰みは詰み・ステイルメイトは 0）")
    func quiescenceDetectsTerminalPositions() {
        var ctx = ChessSearchContext(
            maxDepth: 1, usePositional: true, useQuiescence: true, timeLimit: 600)
        let wide = 2 * chessMateScore

        // チェックメイト（黒番・合法手ゼロ・王手あり）。手数（ply）を引いた値がそのまま返る。
        var mated = ChessPosition.fromFEN("R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1")!
        #expect(mated.legalMoves().isEmpty && mated.isKingInCheck(.black), "テストの前提")
        #expect(ctx.quiesce(&mated, alpha: -wide, beta: wide, qdepth: 0, ply: 3)
                == -(chessMateScore - 3))

        // ステイルメイト（黒番・合法手ゼロ・王手なし）。クイーンを1枚損している局面だが、
        // 引き分けなので **0** でなければならない（静的評価をそのまま返すと大きく負になる）。
        var stalemated = ChessPosition.fromFEN("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!
        #expect(stalemated.legalMoves().isEmpty && !stalemated.isKingInCheck(.black), "テストの前提")
        #expect(ctx.evaluate(stalemated) < -500, "静的評価では大きく負に見える局面であること")
        #expect(ctx.quiesce(&stalemated, alpha: -wide, beta: wide, qdepth: 0, ply: 3) == 0)
    }

    /// 王手されている局面で stand-pat を許すと、「何も指さなければこの評価」という
    /// 成り立たない前提で枝を切る。静かな回避手（逃げる・合駒）が見えなくなる。
    @Test("王手されている局面では静かな回避手も読む（stand-pat しない）")
    func searchesQuietEvasionsWhenInCheck() async {
        // 黒番で王手されている。取る手は無く、キングが逃げるしかない。
        // 王手中に stand-pat すると「取る手ゼロ = 静止」と見なして評価だけ返し、
        // 回避手を1つも読まないまま探索が終わる。
        let fen = "4k3/8/8/8/8/8/4R3/4K3 b - - 0 1"
        var ctx = ChessSearchContext(
            maxDepth: 1, usePositional: true, useQuiescence: true, timeLimit: 600)
        var pos = ChessPosition.fromFEN(fen)!
        let score = ctx.quiesce(&pos, alpha: -2_000_000, beta: 2_000_000, qdepth: 0, ply: 0)
        // 逃げれば駒損はしないので、静的評価（ルーク1枚ぶんの劣勢 = 大きく負）より
        // 悪くならない…ではなく、**回避手を読んだ結果**が返ることを見る。
        // 王手中でも stand-pat していたら `evaluate` そのものが返る。
        #expect(score != ctx.evaluate(pos), "王手中に静的評価をそのまま返していない")
        #expect(pos == ChessPosition.fromFEN(fen)!, "探索が局面を壊していない")
    }

    @Test("静的評価は手番側から見た値で、駒得している側が正になる")
    func evaluationIsFromSideToMove() {
        let e = engine(depth: 1)
        // 白がクイーン 1 枚多い局面。白番なら正、黒番なら負。
        let white = ChessPosition.fromFEN("4k3/8/8/8/8/8/8/3QK3 w - - 0 1")!
        let black = ChessPosition.fromFEN("4k3/8/8/8/8/8/8/3QK3 b - - 0 1")!
        #expect(e.evaluate(white) > 0)
        #expect(e.evaluate(black) < 0)
        // 対称な局面は 0。
        #expect(engine(depth: 1, positional: false).evaluate(ChessPosition.start()) == 0)
    }
}

// MARK: - 自己対戦ハーネス（将棋 `ShogiSelfPlay` と同じ設計）

/// 難易度の実測用。`timeLimit` を実測の 100 倍以上に取って**深さで決まる**状態にしてから使う。
enum ChessSelfPlay {
    struct Result {
        /// 白視点の駒得（キングを除く盤上の駒）。
        var material: Int
        var plies: Int
        /// 詰みで終わったなら負けた側。手数上限・ステイルメイトなら nil。
        var mated: ChessColor?
    }

    /// `nil` を渡した側はランダムに指す（「壊れていないこと」の対照）。
    static func play(
        white: SimpleChessEngine?,
        black: SimpleChessEngine?,
        seed: UInt64,
        maxPlies: Int
    ) async -> Result {
        var pos = ChessPosition.start()
        var rng = MMIXRandom(seed: seed)
        for ply in 0..<maxPlies {
            let moves = pos.legalMoves()
            if moves.isEmpty {
                let mated = pos.isKingInCheck(pos.sideToMove) ? pos.sideToMove : nil
                return Result(material: material(pos), plies: ply, mated: mated)
            }
            var chosen = moves[Int.random(in: 0..<moves.count, using: &rng)]
            let engine = pos.sideToMove == .white ? white : black
            if let engine {
                let uci = await engine.bestMove(fen: pos.toFEN())
                let move = uci.flatMap(ChessMove.fromUCI)
                #expect(move != nil, "CPU が手を返さなかった")
                if let move {
                    #expect(moves.contains(move), "CPU が非合法手を選んだ: \(uci ?? "-")")
                    chosen = move
                }
            }
            pos.make(chosen)
        }
        return Result(material: material(pos), plies: maxPlies, mated: nil)
    }

    /// キングを除いた駒の価値の差（白視点）。
    static func material(_ pos: ChessPosition) -> Int {
        var s = 0
        for sq in 0..<ChessSquare.count {
            guard let p = pos.squares[sq], p.type != .king else { continue }
            s += (p.color == .white ? 1 : -1) * ChessPieceValue.base(p.type)
        }
        return s
    }
}

// MARK: - 段階ごとの手（#1174・#1462）

/// 下の段（入門・かんたん）の読みの下限と、最善手を外す段の振る舞い。段の番号は 0 始まりではない（`CPUStrength`）。
///
/// 段階どうしの強さの差（上の段の得点率 90% 以上）は CI では回さない。最適化ビルドでも 1 組数十分かかるため、
/// `Scripts/chess-cpu-bench` で計測し `docs/analytics/chess-1462-ladder.md` に記録してある。
@Suite("チェスの入門・かんたん")
struct ChessNoviceAndSeriousTests {

    private static let novice = CPUStrength.novice.rawValue

    /// 時間で打ち切られない指定段階。`slips` が `false` なら最善手を外さない（読みの深さだけを固定するテスト用）。
    /// むずかしいの深さ上限（32）はそのままでは終わらないので 4 に絞る。
    private func untimed(level: Int, seed: UInt64? = nil, slips: Bool = false) -> SimpleChessEngine {
        let shipped = SimpleChessEngine(level: level)
        return SimpleChessEngine(
            depth: min(shipped.depth, 4), usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: false, timeLimit: .infinity,
            policy: slips ? shipped.policy : shipped.policy.withoutSlip, seed: seed
        )
    }

    /// 呼び出し時点で既に期限切れの指定段階。`timeLimit` に負の値を渡すと
    /// `ChessSearchContext.init` の `Date().addingTimeInterval` がその場で過去の時刻になる。
    private func expired(level: Int, seed: UInt64?) -> SimpleChessEngine {
        let shipped = SimpleChessEngine(level: level)
        return SimpleChessEngine(
            depth: shipped.depth, usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: false, timeLimit: -1,
            policy: shipped.policy, seed: seed
        )
    }

    @Test("むずかしいの設定（定跡・2 秒・深さ上限なし・100%）")
    func hardConfiguration() {
        let hard = SimpleChessEngine(level: CPUStrength.hard.rawValue)
        #expect(hard.useBook && hard.timeLimit == 2 && hard.depth == SimpleChessEngine.maxDepth && hard.policy.isExact)
    }

    /// タダの駒は入門も取る（弱くはするが壊さない）。
    @Test("入門もタダのルークは取る")
    func noviceTakesAFreeRook() async {
        // e5 の黒ルークは e1 の白ルークで取れて、取り返されない。
        let fen = "k7/8/8/4r3/8/8/8/K3R3 w - - 0 1"
        for seed in UInt64(1)...10 {
            #expect(await untimed(level: Self.novice, seed: seed).bestMove(fen: fen) == "e1e5",
                    "入門がタダのルークを取っていない（seed \(seed)）")
        }
    }

    /// 全段階が静止探索つきで読む（#1462）ので、入門（1 手先）でも最善手の手番では取り返しを見る。
    @Test("入門・かんたんは（外さない手番では）取り返されるだけの取りを指さない")
    func lowerLevelsAvoidTheHangingCapture() async {
        // Qxe5 は d6 のポーンに取り返される（クイーン 900 とポーン 100 の刺し違え）。
        let fen = "k7/8/3p4/4p3/8/8/8/K3Q3 w - - 0 1"
        for level in [Self.novice, CPUStrength.easy.rawValue] {
            #expect(await untimed(level: level).bestMove(fen: fen) != "e1e5",
                    "段階 \(level) がクイーンをポーンと刺し違えている")
        }
    }

    /// 勝てる手は入門も逃さない。
    @Test("入門も1手詰めは逃さない")
    func noviceFindsMateInOne() async {
        #expect(await untimed(level: Self.novice)
            .bestMove(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1") == "a1a8")
    }

    /// 入門・かんたん・ふつうは最善手を外すので、同じ局面でも指す手が散る。むずかしいは決定的。
    @Test("最善手を外す段は同じ局面でも指す手が散り、むずかしいは散らない")
    func slippingLevelsVaryTheirMove() async {
        let fen = "k7/8/8/4p3/8/8/8/K3R3 w - - 0 1"
        for level in [Self.novice, CPUStrength.easy.rawValue, CPUStrength.normal.rawValue] {
            var moves = Set<String>()
            for seed in UInt64(1)...40 {
                if let uci = await untimed(level: level, seed: seed, slips: true).bestMove(fen: fen) { moves.insert(uci) }
            }
            #expect(moves.count > 1, "段階 \(level) の手が 1 通りしかない（外しが効いていない）")
        }
        var hard = Set<String>()
        for seed in UInt64(1)...5 {
            if let uci = await untimed(level: CPUStrength.hard.rawValue, seed: seed, slips: true).bestMove(fen: fen) {
                hard.insert(uci)
            }
        }
        #expect(hard.count == 1, "むずかしいの手が散っている")
    }

    /// 呼び出し時点で既に期限切れでも、外しの採点（最低限の手数）か探索の先頭の手で合法手を返す。
    @Test("期限切れでも合法手を返す")
    func expiredStillReturnsALegalMove() async {
        let legal = Set(ChessPosition.start().legalMoves().map(\.uci))
        for level in CPUStrength.allCases.map(\.rawValue) {
            for seed in UInt64(1)...10 {
                let uci = await expired(level: level, seed: seed).bestMove(fen: ChessPosition.startFEN)
                #expect(uci.map(legal.contains) == true, "段階 \(level) が合法手を返さない（\(uci ?? "nil")）")
            }
        }
    }

    /// 弱くしても壊れていないことの下限: 入門の読み（1 手先）でも、でたらめに指す相手には大差で勝つ。
    /// 種を固定した同じエンジンは毎手同じ目を引くので、ここでは外しを切って読みだけを見る
    /// （出荷どおり 60% で外す入門の対一様乱択は、計測で 100 局全勝・`docs/analytics/chess-1462-ladder.md`）。
    @Test("入門もでたらめな相手には大差で勝つ")
    func noviceStillCrushesRandomPlay() async {
        let novice = untimed(level: Self.novice, seed: 13)

        let asWhite = await ChessSelfPlay.play(white: novice, black: nil, seed: 13, maxPlies: 120)
        #expect(asWhite.mated == .black || asWhite.material > 1_000,
                "白の「入門」が勝てていない（駒得 \(asWhite.material)）")

        let asBlack = await ChessSelfPlay.play(white: nil, black: novice, seed: 13, maxPlies: 120)
        #expect(asBlack.mated == .white || asBlack.material < -1_000,
                "黒の「入門」が勝てていない（駒得 \(asBlack.material)）")
    }
}
