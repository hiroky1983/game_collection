import Testing
@testable import GameShogi

@Suite("角道テスト")
struct KakudoTest {
    @Test func firstMoveOpensKakudo() async {
        let engine = SimpleMinimaxEngine(level: 1)
        let startSFEN = "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1"
        let move = await engine.bestMove(sfen: startSFEN)
        print("Black first move: \(move ?? "nil")")
        // 7g7f = ７六歩（黒の角道を開ける）
    }

    @Test func whiteRespondsWithKakudo() async {
        // 黒が２六歩（飛車先）を指した後、白が角道を開けるか
        let engine = SimpleMinimaxEngine(level: 1)
        let afterNirokufuSFEN = "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPP1/1B5R1/LNSGKGSNL w - 2"
        // wait: 2六歩は pawn 2g→2f = index: 2g=(file1,rank6)→2f=(file1,rank5)
        // ２六歩後のSFEN: rank6の2筋の歩がなくなり、rank5に移動
        let whiteSFEN = "lnsgkgsnl/1r5b1/ppppppppp/9/9/1P7/P1PPPPPPP/1B5R1/LNSGKGSNL w - 2"
        let move = await engine.bestMove(sfen: whiteSFEN)
        print("White response after 2六歩: \(move ?? "nil")")
        // 3c3d = ３四歩（白の角道を開ける）
    }
}
