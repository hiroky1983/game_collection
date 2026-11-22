import Testing
import Core
@testable import GameOthello

/// 「新規対局」の確認を出すかの境目（#1011）。
@MainActor
@Suite("オセロ 新規対局で失われる進行（#1011）")
struct OthelloProgressToLoseTests {

    @Test("初期配置のままなら失うものは無い")
    func freshBoardHasNothingToLose() {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        #expect(!model.hasProgressToLose)
    }

    @Test("1 往復打つと、決着前は失う進行がある")
    func playedBoardHasProgress() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        let move = try #require(model.board.validMoves(for: model.humanSide).first)
        model.tap(row: move.0, col: move.1)
        await model.performAIMoveIfNeeded()
        try #require(!model.gameOver, "前提: 1 往復では決着しない")
        #expect(model.hasProgressToLose)
    }

    @Test("投了して決着したあとは失うものが無い")
    func finishedGameHasNothingToLose() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        let move = try #require(model.board.validMoves(for: model.humanSide).first)
        model.tap(row: move.0, col: move.1)
        await model.performAIMoveIfNeeded()
        try #require(model.hasProgressToLose)
        model.resign()
        try #require(model.gameOver)
        #expect(!model.hasProgressToLose)
    }

    @Test("新規対局で初期配置に戻れば、また失うものは無い")
    func newGameResetsProgress() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        let move = try #require(model.board.validMoves(for: model.humanSide).first)
        model.tap(row: move.0, col: move.1)
        model.newGame()
        #expect(!model.hasProgressToLose)
    }
}

/// CPU 先手の局で、CPU の初手だけでは「新規」に確認を出さない（#3490。#2508 系の確認ダイアログ版）。
@MainActor
@Suite("オセロ CPU 先手の局の新規対局確認（#3490）")
struct OthelloCPUOpeningProgressTests {
    @Test("人間が白のとき、CPU の初手だけでは失う進行は無く、自分が打つと進行になる")
    func whiteAfterCPUOpening() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        model.newGame(humanSide: .white, aiLevel: -1) // 入門（最弱）にして、CPU の初手の読みを軽くする。
        await model.performAIMoveIfNeeded()
        try #require(!model.isAITurn, "前提: CPU が初手を打った")
        #expect(!model.hasProgressToLose)
        let point = try #require(model.board.validMoves(for: .white).first)
        model.tap(row: point.0, col: point.1)
        #expect(model.hasProgressToLose)
    }
}
