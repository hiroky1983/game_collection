import Testing
import Core
@testable import GameShogi

/// 図で見る「はじめての遊び方」（#2825）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("将棋: はじめての遊び方")
struct ShogiOnboardingTests {
    private func position(_ name: String) -> Position {
        Position.fromSFEN(ShogiOnboarding.sampleSFENs[name]!)!
    }

    private func sq(_ usi: String) -> Int { Sq.fromUSI(Substring(usi))! }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(ShogiOnboarding.guide.isWellFormed)
        #expect(ShogiOnboarding.guide.gameID == ShogiGameModel().gameID)
    }

    @Test("詰み: 王手で、逃げる手も金を取る手も無い")
    func mate() {
        let pos = position("mate")
        #expect(pos.isKingInCheck(.white))
        #expect(pos.legalMoves().isEmpty)
    }

    @Test("王手: 玉が狙われているが、外す手は残っている。外す手しか指せない")
    func check() {
        let pos = position("check")
        #expect(pos.isKingInCheck(.white))
        let moves = pos.legalMoves()
        #expect(!moves.isEmpty)
        for move in moves {
            var next = pos
            next.make(move)
            #expect(!next.isKingInCheck(.white), "王手を外していない手が合法手に入っている: \(move.usi)")
        }
    }

    @Test("取る: 相手の駒のマスへ動くと取れて、持ち駒になる")
    func capture() throws {
        var pos = position("capture")
        let move = Move.board(from: sq("5f"), to: sq("5e"), promote: false)
        try #require(pos.legalMoves().contains(move))
        pos.make(move)
        #expect(pos.hands[Side.black.rawValue][PieceType.pawn.rawValue] == 1)
    }

    @Test("成り: 相手陣へ入る手は成・不成を選べ、最奥段では必ず成る。金は成れない")
    func promotion() {
        let pos = position("promotion")   // 先手歩 5d（相手陣の手前）
        let into = pos.legalMoves().filter { if case let .board(from, _, _) = $0 { return from == sq("5d") } else { return false } }
        #expect(into.contains(.board(from: sq("5d"), to: sq("5c"), promote: true)))
        #expect(into.contains(.board(from: sq("5d"), to: sq("5c"), promote: false)))

        let edge = Position.fromSFEN("k8/9/9/9/9/9/9/9/4K4 b P 1")!
        let drops = edge.legalMoves().contains { if case let .drop(.pawn, to) = $0 { return Sq.rank(to) == 0 } else { return false } }
        #expect(!drops, "最奥段には歩を打てない")

        let forced = Position.fromSFEN("8k/1P7/9/9/9/9/9/9/4K4 b - 1")!   // 先手歩 8b → 8a
        let pawnMoves = forced.legalMoves().filter { if case let .board(from, _, _) = $0 { return from == sq("8b") } else { return false } }
        #expect(pawnMoves == [.board(from: sq("8b"), to: sq("8a"), promote: true)])

        let gold = Position.fromSFEN("4k4/9/4G4/9/9/9/9/9/4K4 b - 1")!
        #expect(gold.legalMoves().allSatisfy { if case let .board(_, _, promote) = $0 { return !promote } else { return true } })
    }

    @Test("二歩: 歩のある筋には歩を打てず、別の筋なら打てる")
    func nifu() {
        let pos = position("nifu")
        let file = Sq.file(sq("5e"))
        let drops = pos.legalMoves().compactMap { move -> Int? in
            if case let .drop(.pawn, to) = move { return to } else { return nil }
        }
        #expect(!drops.contains { Sq.file($0) == file })
        #expect(drops.contains { Sq.file($0) != file })
    }

    @Test("打ち歩詰め: 歩を打って詰ませる手は反則")
    func uchifuzume() {
        // 後手玉 9a。金 7b が 8a・8b を、銀 8c が 9b を押さえている。歩を 9b へ打つと玉に逃げ場が無い。
        let pos = Position.fromSFEN("k8/2G6/1S7/9/9/9/9/9/4K4 b P 1")!
        let dropPawn = Move.drop(type: .pawn, to: sq("9b"))
        var after = pos
        after.make(dropPawn)
        guard after.isKingInCheck(.white), after.legalMoves().isEmpty else {
            Issue.record("この局面は打ち歩詰めの形になっていない")
            return
        }
        #expect(!pos.legalMoves().contains(dropPawn))
    }

    @Test("千日手: 同じ局面が 4 回で成立する")
    func repetition() {
        #expect(ShogiGameModel.repetitionLimit == 4)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in ShogiOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
