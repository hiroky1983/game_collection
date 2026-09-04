import Testing
import Foundation
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

    @Test("難易度の設定が表示している文言と一致する（#416）")
    func levelsMatchTheirLabels() {
        // 弱: 駒の損得だけ（位置評価も静止探索も定跡も無し・浅い）
        let weak = SimpleChessEngine(level: 0)
        #expect(weak.depth == 2)
        #expect(weak.usePositional == false, "「駒の損得だけ」なので位置評価を持たない")
        #expect(weak.useQuiescence == false)
        #expect(weak.useBook == false)

        // 普通: 駒の働きも見る
        let normal = SimpleChessEngine(level: 1)
        #expect(normal.usePositional, "「駒の働きも見る」ので位置評価を持つ")
        #expect(normal.useBook == false, "定跡は「強」だけの売り")

        // 強: 定跡＋深読み
        let strong = SimpleChessEngine(level: 2)
        #expect(strong.useBook, "「定跡」を名乗るので定跡を持つ")
        #expect(strong.depth > normal.depth, "「深読み」を名乗るので普通より深い")
        #expect(normal.depth > weak.depth)
    }

    @Test("定跡は「強」だけが使い、初手は定跡どおりに指す")
    func bookIsUsedOnlyByStrongLevel() async {
        let booked = await engine(depth: 1, book: true).bestMove(fen: ChessPosition.startFEN)
        #expect(["e2e4", "d2d4", "c2c4"].contains(booked ?? ""), "登録した初手のどれか")
        // 定跡は手数を無視したキーで引くので、別の手順で同じ局面に来ても効く。
        let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        #expect(await engine(depth: 1, book: true).bestMove(fen: afterE4) != nil)
    }

    @Test("弱いレベルは駒の只捨てを見落とす（初心者が勝てる最弱の根拠）")
    func weakLevelHangsPieces() async {
        // 白のクイーンが d5 に出ると、c6 の黒ポーンでも e6 の黒ポーンでも取られる。
        // 静止探索が無い level 0 は「取ったら得」までしか読まず、取り返しを見ない。
        // ここでは「level 2 は取り返される手を選ばない」ことだけを固定する
        // （level 0 の具体的な手は評価の細部に依存するので固定しない）。
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
