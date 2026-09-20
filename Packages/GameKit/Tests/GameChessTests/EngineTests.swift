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

// MARK: - 入門・ガチ（#1174）

/// 両端に足した 2 段（#1174）。段の番号は 0 始まりではない（`CPUStrength`）。
///
/// 将棋 `ShogiNoviceAndSeriousTests` と対で、同じ考え方・同じ物差しで見る
/// （エンジンは共通化しないが、段の設計は 4 ゲームで揃える）。
///
/// **「入門 < 簡単」の直接対戦もこのファイルの方針どおり CI に置かない。** 将棋と同じ理由が
/// そのまま当てはまる: 深さ 2 どうしの直接対戦では、乱択の幅が「簡単の最善からポーン 1 枚未満」
/// しかないため差が埋もれる。実測（8手だけランダムに進めてから 60 手・40 局、先後を半々にした
/// 直接対戦・デバッグビルド・192 秒）: **入門 19 勝/40 局・引き分け 7・入門視点の駒得合計 +5340**
/// と、むしろ入門が上回っている（ノイズの範囲。統計的な差にならない）。将棋の旧「弱」に相当する
/// 深い相手を挟めば差は出るはずだが、チェスの「ふつう」（深さ 3・位置評価＋静止探索あり）を
/// 相手に 16 局（4 シード×先後）試したところ 3 分 43 秒かかった（実測）ため、有意な局数を
/// 回すにはオフラインでも現実的な時間に収まらない。そのため CI には①設定の一致
/// ②タダ取り・刺し違え回避・1 手詰め（このファイルの下にある個別テスト）
/// ③入門がでたらめな相手には大差で勝つこと、の 3 つを置く。
@Suite("チェスの入門とガチ")
struct ChessNoviceAndSeriousTests {

    private static let novice = CPUStrength.novice.rawValue
    private static let serious = CPUStrength.serious.rawValue

    /// 時間で打ち切られない「入門」（`seed` を渡すと乱択を再現できる）。
    private func untimedNovice(seed: UInt64?) -> SimpleChessEngine {
        let shipped = SimpleChessEngine(level: Self.novice)
        return SimpleChessEngine(
            depth: shipped.depth, usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: shipped.useBook, timeLimit: 600,
            isNovice: true, seed: seed
        )
    }

    /// 呼び出し時点で既に期限切れの「入門」（#1196 回帰テスト用）。`timeLimit` に負の値を渡すと
    /// `ChessSearchContext.init` の `Date().addingTimeInterval` がその場で過去の時刻になる。
    private func expiredNovice(seed: UInt64?) -> SimpleChessEngine {
        let shipped = SimpleChessEngine(level: Self.novice)
        return SimpleChessEngine(
            depth: shipped.depth, usePositional: shipped.usePositional,
            useQuiescence: shipped.useQuiescence, useBook: shipped.useBook, timeLimit: -1,
            isNovice: true, seed: seed
        )
    }

    /// 「入門」は**読みの設定を「簡単」と 1 ビットも変えず**、着手の選び方だけを崩してある。
    /// 深さを 1 に落とすと只捨てを始めるので、そこには戻さない。
    @Test("入門の読みは簡単と同じで、選び方だけが違う")
    func noviceSharesTheEasySearch() {
        let novice = SimpleChessEngine(level: Self.novice)
        let easy = SimpleChessEngine(level: CPUStrength.easy.rawValue)
        #expect(novice.isNovice)
        #expect(!easy.isNovice)
        #expect(novice.depth == easy.depth && easy.depth == 2)
        #expect(novice.useQuiescence == easy.useQuiescence)
        #expect(novice.usePositional == easy.usePositional)
        #expect(novice.useBook == easy.useBook)
        #expect(novice.timeLimit == easy.timeLimit)
        // 許す損はポーン 1 枚未満。駒を只で捨てる手はこの幅に入らない。
        #expect(SimpleChessEngine.noviceMargin < ChessPieceValue.base(.pawn))
    }

    /// 既存の最上段（むずかしい）の設定はそのままで、その上に積んでいる。
    @Test("ガチはむずかしいより深く長く読む（むずかしいの設定は変えない）")
    func seriousIsDeeperThanHard() {
        let hard = SimpleChessEngine(level: CPUStrength.hard.rawValue)
        #expect(hard.depth == 5 && hard.timeLimit == 2.0, "むずかしいの設定は #1174 で触らない")

        let serious = SimpleChessEngine(level: Self.serious)
        #expect(serious.depth == 7)
        #expect(serious.depth > hard.depth)
        #expect(serious.timeLimit == 3.0)
        #expect(serious.timeLimit > hard.timeLimit, "深くするなら持ち時間も伸ばす（打ち切りで弱くなる）")
        #expect(serious.useBook && serious.useQuiescence && serious.usePositional)
        #expect(!serious.isNovice)
    }

    /// タダの駒は入門も取る（弱くはするが壊さない）。
    @Test("入門もタダのルークは取る")
    func noviceTakesAFreeRook() async {
        // e5 の黒ルークは e1 の白ルークで取れて、取り返されない。
        let fen = "k7/8/8/4r3/8/8/8/K3R3 w - - 0 1"
        for seed in UInt64(1)...10 {
            #expect(await untimedNovice(seed: seed).bestMove(fen: fen) == "e1e5",
                    "入門がタダのルークを取っていない（seed \(seed)）")
        }
    }

    /// 取り返されるだけの取りは入門も指さない（只捨てに落ちていない）。
    @Test("入門は取り返されるだけの取りを指さない")
    func noviceAvoidsTheHangingCapture() async {
        // Qxe5 は d6 のポーンに取り返される（クイーン 900 とポーン 100 の刺し違え）。
        let fen = "k7/8/3p4/4p3/8/8/8/K3Q3 w - - 0 1"
        for seed in UInt64(1)...10 {
            #expect(await untimedNovice(seed: seed).bestMove(fen: fen) != "e1e5",
                    "入門がクイーンをポーンと刺し違えている（seed \(seed)）")
        }
    }

    /// 勝てる手は入門も逃さない（乱択の幅に「詰み」は埋もれない）。
    @Test("入門も1手詰めは逃さない")
    func noviceFindsMateInOne() async {
        for seed in UInt64(1)...10 {
            #expect(await untimedNovice(seed: seed)
                .bestMove(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1") == "a1a8",
                    "入門が1手詰めを逃した（seed \(seed)）")
        }
    }

    /// 入門は同じ局面でも手が散る（＝選び方を崩している）。簡単は乱数を使わないので必ず同じ手。
    @Test("入門は同じ局面でも指す手が散る")
    func noviceVariesItsMove() async {
        var noviceMoves = Set<String>()
        for seed in UInt64(1)...30 {
            if let uci = await untimedNovice(seed: seed).bestMove(fen: ChessPosition.startFEN) {
                noviceMoves.insert(uci)
            }
        }
        #expect(noviceMoves.count > 1, "入門の手が 1 通りしかない（乱択が効いていない）")

        var easyMoves = Set<String>()
        for _ in 0..<5 {
            if let uci = await SimpleChessEngine(
                depth: 2, usePositional: false, useQuiescence: false, useBook: false, timeLimit: 600
            ).bestMove(fen: ChessPosition.startFEN) { easyMoves.insert(uci) }
        }
        #expect(easyMoves.count == 1, "前提が崩れている: 簡単は決定的")
    }

    /// 呼び出し時点で既に `deadline` を過ぎていても、`noviceMove` は評価済みの候補から選ぶ
    /// （#1196）。安全フロア（`minNoviceEvaluations`）を入れる前は、1手も評価できないまま
    /// `orderedMoves.first` を無条件に返していたため、乱数の種を変えても常に同じ手になっていた。
    @Test("期限切れでも評価済みの候補から選ぶ（1手固定に戻らない）")
    func noviceStillVariesWhenDeadlineAlreadyPassed() async {
        var moves = Set<String>()
        for seed in UInt64(1)...30 {
            if let uci = await expiredNovice(seed: seed).bestMove(fen: ChessPosition.startFEN) {
                moves.insert(uci)
            }
        }
        #expect(moves.count > 1, "期限切れ時に手が1通りしかない = 1件も評価されず orderedMoves.first に固定されている")
    }

    /// 安全フロアの評価は `negamax` の期限判定も無効化しないと、相手の応手を読まない
    /// 静的評価（`evaluate(pos)`）のまま候補に残り、取り返される取りを選びうる
    /// （CodeRabbit 指摘・PR #1199）。`noviceAvoidsTheHangingCapture` と同じ局面を
    /// 呼び出し時点で期限切れにして確認する。
    @Test("期限切れでも取り返されるだけの取りは選ばない")
    func expiredNoviceAvoidsTheHangingCapture() async {
        let fen = "k7/8/3p4/4p3/8/8/8/K3Q3 w - - 0 1"
        for seed in UInt64(1)...30 {
            #expect(await expiredNovice(seed: seed).bestMove(fen: fen) != "e1e5",
                    "期限切れの入門がクイーンをポーンと刺し違えている（seed \(seed)）")
        }
    }

    /// 弱くしても壊れていないことの下限: でたらめに指す相手には大差で駒得する
    /// （将棋 `noviceStillCrushesRandomPlay` と同じ物差し）。
    @Test("入門もでたらめな相手には大差で勝つ")
    func noviceStillCrushesRandomPlay() async {
        let novice = untimedNovice(seed: 13)

        let asWhite = await ChessSelfPlay.play(white: novice, black: nil, seed: 13, maxPlies: 120)
        #expect(asWhite.material > 1_000, "白の「入門」が駒得できていない（\(asWhite.material)）")

        let asBlack = await ChessSelfPlay.play(white: nil, black: novice, seed: 13, maxPlies: 120)
        #expect(asBlack.material < -1_000, "黒の「入門」が駒得できていない（\(asBlack.material)）")
    }
}
