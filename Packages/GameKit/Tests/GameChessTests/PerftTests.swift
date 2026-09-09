import Testing
@testable import GameChess

/// perft（合法手生成の全数検証）。
///
/// 期待値は Chess Programming Wiki が公表している標準局面の既知の正解値で、独立実装との
/// 突き合わせにあたる。**コードを取り込まず数値だけを照合する**ので、参照実装のライセンス
/// （GPL 系）が製品コードに混入しない（#462 の権利確認）。
///
/// CI の `swift test` はデバッグビルドで最適化が効かないため、深さは実行時間とのつり合いで
/// 決めている。初期局面は深さ 4（197,281 ノード）まで、キャスリング・アンパッサン・
/// プロモーションが密に出る局面は深さ 3 まで取り、合計でルールの全要素を覆う。
@Suite("チェスの perft（合法手生成の全数検証）")
struct PerftTests {

    /// 初期局面。深さ 1〜4 の値は将棋の `PerftTests` と同じく広く公表されている。
    @Test("初期局面 perft(1..4) = 20 / 400 / 8902 / 197281")
    func startPosition() {
        let pos = ChessPosition.start()
        #expect(pos.perft(1) == 20)
        #expect(pos.perft(2) == 400)
        #expect(pos.perft(3) == 8902)
        #expect(pos.perft(4) == 197_281)
    }

    /// Kiwipete（Position 2）。キャスリング両側・アンパッサン・ピンが同時に絡む定番の検証局面。
    @Test("Kiwipete perft(1..3) = 48 / 2039 / 97862")
    func kiwipete() {
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        let pos = ChessPosition.fromFEN(fen)
        #expect(pos != nil)
        guard let pos else { return }
        #expect(pos.perft(1) == 48)
        #expect(pos.perft(2) == 2039)
        #expect(pos.perft(3) == 97_862)
    }

    /// Position 3。ポーンの押し合いとアンパッサンの絡む終盤で、深さを伸ばしても軽い。
    @Test("Position 3 perft(1..5) = 14 / 191 / 2812 / 43238 / 674624")
    func position3() {
        let pos = ChessPosition.fromFEN("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        #expect(pos != nil)
        guard let pos else { return }
        #expect(pos.perft(1) == 14)
        #expect(pos.perft(2) == 191)
        #expect(pos.perft(3) == 2812)
        #expect(pos.perft(4) == 43_238)
        #expect(pos.perft(5) == 674_624)
    }

    /// Position 4。プロモーションが大量に出る局面（黒番の鏡像も同じ値になることを併せて確認する）。
    @Test("Position 4 perft(1..4) = 6 / 264 / 9467 / 422333")
    func position4() {
        let pos = ChessPosition.fromFEN(
            "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
        #expect(pos != nil)
        guard let pos else { return }
        #expect(pos.perft(1) == 6)
        #expect(pos.perft(2) == 264)
        #expect(pos.perft(3) == 9467)
        #expect(pos.perft(4) == 422_333)
    }

    /// Position 5。キャスリング権の消え方（ルークを取られる／キングが動く）を突く局面。
    @Test("Position 5 perft(1..3) = 44 / 1486 / 62379")
    func position5() {
        let pos = ChessPosition.fromFEN("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
        #expect(pos != nil)
        guard let pos else { return }
        #expect(pos.perft(1) == 44)
        #expect(pos.perft(2) == 1486)
        #expect(pos.perft(3) == 62_379)
    }

    /// Position 6。開いた中盤で、駒の利きが最も込み合う局面。
    @Test("Position 6 perft(1..3) = 46 / 2079 / 89890")
    func position6() {
        let pos = ChessPosition.fromFEN(
            "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10")
        #expect(pos != nil)
        guard let pos else { return }
        #expect(pos.perft(1) == 46)
        #expect(pos.perft(2) == 2079)
        #expect(pos.perft(3) == 89_890)
    }

    /// make / unmake が完全に可逆であること。perft が合っていても、
    /// 巻き戻しの取りこぼし（キャスリング権・アンパッサン標的・50手計数）は
    /// 「同じノードを2回通ると結果が変わる」形でしか出ないので、別に確かめる。
    @Test("make の直後に unmake すると局面が完全に元へ戻る")
    func makeUnmakeIsReversible() {
        for fen in [
            ChessPosition.startFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        ] {
            guard var pos = ChessPosition.fromFEN(fen) else {
                Issue.record("FEN を読めません: \(fen)")
                continue
            }
            let before = pos
            for move in pos.legalMoves() {
                let undo = pos.make(move)
                pos.unmake(undo)
                #expect(pos == before, "\(move.uci) の巻き戻しで局面が戻りませんでした（\(fen)）")
            }
        }
    }
}
