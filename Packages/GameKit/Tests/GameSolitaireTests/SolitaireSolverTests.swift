import Testing
import Foundation
@testable import GameSolitaire

private let s = SolitaireSuit.spade
private let h = SolitaireSuit.heart
private let d = SolitaireSuit.diamond
private let c = SolitaireSuit.club

private func board(
    _ piles: [SolitairePile],
    foundations: [Int] = [0, 0, 0, 0],
    stock: [SolitaireCard] = [],
    joker: Bool = false
) -> SolitaireBoard {
    var piles = piles
    while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
    return SolitaireBoard(tableau: piles, foundations: foundations,
                          stock: stock, jokerAvailable: joker)
}

@Suite("ソルバー")
struct SolitaireSolverTests {

    @Test("あと1枚で揃う盤面は解ける")
    func solvesTrivialBoard() {
        let b = board([SolitairePile(faceUp: [SolitaireCard(s, 13)])],
                      foundations: [12, 13, 13, 13])
        let result = SolitaireSolver.solve(b)
        #expect(result.isSolvable)
        #expect(!result.hitLimit)
    }

    @Test("勝ち筋はそのまま指せてクリアに到達する")
    func solutionIsReplayable() {
        // ♠K は場札から、♥K は山札をめくってから組札へ送れば揃う。
        var b = board([SolitairePile(faceUp: [SolitaireCard(s, 13)])],
                      foundations: [12, 12, 13, 13],
                      stock: [SolitaireCard(h, 13)])
        let result = SolitaireSolver.solve(b)
        guard let solution = result.solution else {
            Issue.record("解けるはずの盤面が解けなかった")
            return
        }
        for move in solution {
            let applied = b.apply(move)
            #expect(applied, "勝ち筋に非合法手が混ざっている: \(move)")
        }
        #expect(b.isWon)
    }

    @Test("詰んだ盤面は「不能」と結論する（打ち切りではない）")
    func provesUnsolvable() {
        // 山札も捨て札も無く、互いに積めない2枚だけ。組札にも送れない。
        let b = board([
            SolitairePile(faceUp: [SolitaireCard(s, 5)]),
            SolitairePile(faceUp: [SolitaireCard(c, 9)]),
        ], foundations: [0, 13, 13, 0])
        let result = SolitaireSolver.solve(b)
        #expect(!result.isSolvable)
        #expect(!result.hitLimit)
    }

    @Test("安全な組札送りだけを分岐させずに実行する")
    func autoplaysOnlySafeCards() {
        // ♦2 は安全（A・2 は常に安全）。♠5 は反対色の組札が足りないので送らない。
        let b = board([
            SolitairePile(faceUp: [SolitaireCard(d, 2)]),
            SolitairePile(faceUp: [SolitaireCard(s, 5)]),
        ], foundations: [4, 0, 1, 0])
        let (settled, moves) = SolitaireSolver.autoplaySafe(b)
        #expect(moves == [.tableauToFoundation(pile: 0)])
        #expect(settled.foundations[d.rawValue] == 2)
        #expect(settled.tableau[1].top == SolitaireCard(s, 5))
    }

    @Test("反対色の組札が追いついた札は安全とみなして送る")
    func autoplaysWhenOppositeColorsCaughtUp() {
        // ♥5 を受けうる黒4 は2枚とも組札にあるので、♥5 を場札に残す理由が無い。
        let b = board([SolitairePile(faceUp: [SolitaireCard(h, 5)])],
                      foundations: [4, 4, 0, 4])
        let (settled, moves) = SolitaireSolver.autoplaySafe(b)
        #expect(moves == [.tableauToFoundation(pile: 0)])
        #expect(settled.foundations[h.rawValue] == 5)
    }

    @Test("ジョーカーを許すと解ける盤面が、許さないと解けない")
    func jokerRescuesADeadPosition() {
        // ♠・♥・♣ は完了、残りは ♦5〜♦K だけ。♦5 が ♦6 の下に埋まっている。
        // 同色は重ねられず、7列すべて埋まっていて空列も作れないので ♦6 は永久に動かせない。
        // ジョーカーを1枚置ければ ♦6 をそこへ逃がせて、♦5 以降が組札へ流れる。
        let piles = [
            SolitairePile(faceDown: [SolitaireCard(d, 5)], faceUp: [SolitaireCard(d, 6)]),
            SolitairePile(faceUp: [SolitaireCard(d, 7)]),
            SolitairePile(faceUp: [SolitaireCard(d, 8)]),
            SolitairePile(faceUp: [SolitaireCard(d, 9)]),
            SolitairePile(faceUp: [SolitaireCard(d, 10)]),
            SolitairePile(faceUp: [SolitaireCard(d, 11)]),
            SolitairePile(faceUp: [SolitaireCard(d, 12)]),
        ]
        let foundations = [13, 13, 4, 13]
        let stock = [SolitaireCard(d, 13)]

        #expect(!SolitaireSolver.solve(board(piles, foundations: foundations, stock: stock)).isSolvable)

        let withJoker = board(piles, foundations: foundations, stock: stock, joker: true)
        #expect(!SolitaireSolver.solve(withJoker, allowJoker: false).isSolvable)

        let rescued = SolitaireSolver.solve(withJoker, allowJoker: true)
        #expect(rescued.isSolvable)
        // 勝ち筋を実際に指し切れることまで見る（中継札の消滅まで含めた通し確認）。
        var replay = withJoker
        for move in rescued.solution ?? [] {
            let applied = replay.apply(move)
            #expect(applied, "救済の勝ち筋に非合法手が混ざっている: \(move)")
        }
        #expect(replay.isWon)
    }
}
