import Testing
import CoreEngine
@testable import GameShogi

/// 飛び駒（角・馬・飛・龍・香）で王手された局面で、王手が解けない玉の手（飛び駒の線の上で、
/// 玉の後ろ＝飛び駒から遠ざかる向きへ逃げる手）が、合法手・ヒント・CPU の手に入らないこと（#2779）。
///
/// 玉が元のマスに残ったまま利きを数えると、玉の後ろのマスは玉に遮られて「利きが無い」に見える
/// （いわゆる x-ray の誤り）。後ろのマスには相手の金を置いて、取りたくなる形にしてある。
@Suite("飛び駒の王手で玉が線の後ろへ逃げない（#2779）")
struct KingSliderCheckTests {

    struct Case: CustomStringConvertible, Sendable {
        let name: String
        /// 手番側が王手されている局面。
        let sfen: String
        /// 王手が解けない玉の行き先（飛び駒の線の上、玉の後ろ）。
        let forbidden: [String]
        var description: String { name }
    }

    // 先手玉 5e。後ろのマスに後手の金（取りたくなる駒）。後手玉は 9a。
    static let cases: [Case] = [
        // 角 2b → 3c・4d・5e。後ろは 6f。
        Case(name: "角", sfen: "k8/7b1/9/9/4K4/3g5/9/9/9 b - 1", forbidden: ["6f"]),
        // 馬 2b。
        Case(name: "馬", sfen: "k8/7+b1/9/9/4K4/3g5/9/9/9 b - 1", forbidden: ["6f"]),
        // 飛 5a → 5e。後ろは 5f。
        Case(name: "飛", sfen: "k3r4/9/9/9/4K4/4g4/9/9/9 b - 1", forbidden: ["5f"]),
        // 龍 5a。
        Case(name: "龍", sfen: "k3+r4/9/9/9/4K4/4g4/9/9/9 b - 1", forbidden: ["5f"]),
        // 香 5a（後手の香は下向き）。後ろは 5f。
        Case(name: "香", sfen: "k3l4/9/9/9/4K4/4g4/9/9/9 b - 1", forbidden: ["5f"]),
        // 横向きの飛: 飛 1e → 5e。後ろは 6e。
        Case(name: "飛（横）", sfen: "k8/9/9/9/4K3r/9/9/9/9 b - 1", forbidden: ["6e"]),
        // 両王手: 飛 5a と角 1a。後ろは 5f（飛）と 6f（角）。
        Case(name: "両王手（飛＋角）", sfen: "k3r3b/9/9/9/4K4/9/9/9/9 b - 1", forbidden: ["5f", "6f"]),
        // 後手番（人間が後手）: 先手の角 8h → 7g・6f・5e で後手玉 5e に王手。後ろは 4d。
        Case(name: "後手玉に先手の角", sfen: "8K/9/9/5G3/4k4/9/9/1B7/9 w - 1", forbidden: ["4d"]),
    ]

    /// 玉を取り除いた盤で、玉の行き先が相手の利きにあるかを確かめる（実装とは別の数え方）。
    static func kingMoveIsSafe(_ pos: Position, _ move: Move) -> Bool {
        guard case let .board(from, to, _) = move,
              pos.squares[from]?.type == .king else { return true }
        var p = pos
        p.squares[from] = nil
        p.squares[to] = nil
        return !p.isAttacked(to, by: pos.sideToMove.opponent)
    }

    static func isForbiddenKingMove(_ pos: Position, _ move: Move, _ c: Case) -> Bool {
        guard case let .board(from, to, _) = move, pos.squares[from]?.type == .king else { return false }
        return c.forbidden.contains(Sq.toUSI(to)) || !kingMoveIsSafe(pos, move)
    }

    @Test("局面は王手されている", arguments: cases)
    func positionIsCheck(_ c: Case) {
        let pos = Position.fromSFEN(c.sfen)!
        #expect(pos.isKingInCheck(pos.sideToMove), "\(c.name)")
    }

    @Test("合法手に王手が解けない玉の手が無い（詰みの判定も同じ合法手を使う）", arguments: cases)
    func legalMovesExcludeXray(_ c: Case) {
        let pos = Position.fromSFEN(c.sfen)!
        let moves = pos.legalMoves()
        #expect(!moves.isEmpty, "\(c.name): 逃げ道があるので詰みではない")
        for m in moves {
            #expect(!Self.isForbiddenKingMove(pos, m, c), "\(c.name): \(m.usi) は王手が解けない")
            var p = pos
            p.make(m)
            #expect(!p.isKingInCheck(pos.sideToMove), "\(c.name): \(m.usi) の後も王手")
        }
        // 疑似合法手には後ろへ逃げる手（後ろの金を取る手）が在り、合法手の段で落ちていること。
        let behind = pos.pseudoLegalMoves().filter { Self.isForbiddenKingMove(pos, $0, c) }
        #expect(!behind.isEmpty, "\(c.name): テストの局面が意図どおり（後ろへ逃げる手が候補に在る）")
    }

    @Test("CPU の各段は王手が解けない玉の手を指さない", arguments: cases)
    func cpuLevelsAvoidXray(_ c: Case) async {
        let pos = Position.fromSFEN(c.sfen)!
        for strength in CPUStrength.allCases {
            for seed in UInt64(1)...4 {
                let engine = SimpleMinimaxEngine(level: strength.rawValue, seed: seed, timeLimit: 0.2)
                let usi = await engine.bestMove(sfen: c.sfen)
                let move = usi.flatMap(Move.fromUSI)
                #expect(move.map { pos.legalMoves().contains($0) } == true, "\(c.name) \(strength): \(usi ?? "nil")")
                if let move {
                    #expect(!Self.isForbiddenKingMove(pos, move, c), "\(c.name) \(strength): \(move.usi)")
                }
            }
        }
    }

    @Test("ヒント（出荷の設定）は王手が解けない玉の手を出さない")
    func hintAvoidsXray() async {
        for c in Self.cases {
            let pos = Position.fromSFEN(c.sfen)!
            let usi = await SimpleMinimaxEngine.hint().bestMove(sfen: c.sfen)
            let move = usi.flatMap(Move.fromUSI)
            #expect(move.map { pos.legalMoves().contains($0) } == true, "\(c.name): \(usi ?? "nil")")
            if let move {
                #expect(!Self.isForbiddenKingMove(pos, move, c), "\(c.name): \(move.usi)")
            }
        }
    }

    /// 飛び駒の線の後ろにしか逃げ場が無いなら詰み（合法手 0）と判定する。誤りがあると詰みを見逃す。
    /// 先手玉 8e に後手の飛 1e（横の線）で王手。d 段・f 段は後手の飛 1d・1f が押さえ、
    /// 空いて見えるのは線の後ろの 9e だけ。
    @Test("線の後ろにしか逃げ場が無ければ詰みと判定する")
    func mateDetectedWhenOnlyBehindSquareRemains() {
        let pos = Position.fromSFEN("k8/9/9/8r/1K6r/8r/9/9/9 b - 1")!
        #expect(pos.isKingInCheck(.black))
        #expect(pos.legalMoves().isEmpty)
    }
}
