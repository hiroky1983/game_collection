import Testing
import Foundation
import SwiftUI
import Core
import Game2048
import GameShogi
import GameGomoku
import GameMinesweeper
import GameOthello
import GamePoker
import GameConcentration
import GameBlackjack

// MARK: - Mocks

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// 発火の内訳を記録するスパイ。
@MainActor
private final class SpyFeedbackService: FeedbackService {
    private(set) var impacts: [FeedbackImpact] = []
    private(set) var notices: [FeedbackNotice] = []

    var callCount: Int { impacts.count + notices.count }
    func notices(of type: FeedbackNotice) -> Int { notices.filter { $0 == type }.count }

    func impact(_ style: FeedbackImpact) { impacts.append(style) }
    func notify(_ type: FeedbackNotice) { notices.append(type) }
}

/// トグルの状態を指定して、スパイ付きの GameServices を作る。
@MainActor
private func makeServices(hapticsEnabled: Bool) -> (GameServices, SpyFeedbackService) {
    let spy = SpyFeedbackService()
    let services = GameServices(
        snapshots: MemorySnapshotStore(),
        ads: NoopAdService(),
        feedback: GatedFeedbackService(base: spy) { hapticsEnabled }
    )
    return (services, spy)
}

// MARK: - 各ゲームの操作シナリオ
//
// 「有効な操作の成立 / 無効な操作の拒否 / 局面の決着」の 3 種を必ず通る手順を
// ゲームごとに 1 本ずつ用意し、オン（発火する）とオフ（1 度も発火しない）の
// 両方のテストから同じ手順を使う。

@MainActor
private func play2048(_ services: GameServices) {
    let model = Game2048Model(services: services)
    // 4 方向を順に試すと必ず動く方向があり、動かない方向が拒否になる。終局まで回す。
    outer: for _ in 0..<3000 {
        for direction in Direction.allCases {
            model.move(direction)
            if model.gameOver { break outer }
        }
    }
}

@MainActor
private func playShogi(_ services: GameServices) {
    let model = ShogiGameModel(services: services)

    // 拒否: 自駒を選んでから、指せないマスを叩く。
    guard case let .board(from, _, _)? = model.legalMovesCache.first(where: {
        if case .board = $0 { return true }
        return false
    }) else { return }
    model.tapSquare(from)
    if let dead = (0..<81).first(where: { !model.legalTargets.contains($0) && model.position.squares[$0] == nil }) {
        model.tapSquare(dead)
    }

    // 成立: 成り選択の出ない（候補が 1 つだけの）移動を選んで指す。
    let boardMoves = model.legalMovesCache.compactMap { move -> (Int, Int)? in
        if case let .board(f, t, _) = move { return (f, t) }
        return nil
    }
    if let unique = boardMoves.first(where: { pair in
        boardMoves.filter { $0 == pair }.count == 1
    }) {
        model.tapSquare(unique.0)
        model.tapSquare(unique.1)
    }

    // 決着: 投了。
    model.resign()
}

@MainActor
private func playGomoku(_ services: GameServices) async {
    let model = GomokuModel(services: services)
    model.newGame(humanSide: .black, aiLevel: 1)
    model.tap(row: 7, col: 7)          // 成立
    await model.performAIMoveIfNeeded() // 人間の手番に戻す
    model.tap(row: 7, col: 7)          // 拒否（埋まっているマス）
    model.resign()                     // 決着
}

@MainActor
private func playMinesweeper(_ services: GameServices) {
    let model = MinesweeperModel(services: services)
    model.newGame(rows: 9, cols: 9, mines: 10)
    model.tap(row: 0, col: 0)  // 成立（初手は必ず安全マス）
    model.tap(row: 0, col: 0)  // 拒否（開き済み）

    if let flagTarget = model.cells.indices.flatMap({ r in
        model.cells[r].indices.map { (r, $0) }
    }).first(where: { !model.cells[$0.0][$0.1].isRevealed }) {
        model.toggleFlag(row: flagTarget.0, col: flagTarget.1)  // 成立（旗）
        model.toggleFlag(row: flagTarget.0, col: flagTarget.1)  // 旗を戻す
    }

    // 決着: 地雷を踏む。
    if let mine = model.cells.indices.flatMap({ r in
        model.cells[r].indices.map { (r, $0) }
    }).first(where: { model.cells[$0.0][$0.1].isMine && !model.cells[$0.0][$0.1].isFlagged }) {
        model.tap(row: mine.0, col: mine.1)
    }
}

@MainActor
private func playOthello(_ services: GameServices) {
    let model = OthelloModel(services: services)
    model.newGame(humanSide: .black, aiLevel: 1)
    model.tap(row: 0, col: 0)  // 拒否（石を返せないマス）
    if let move = model.board.validMoves(for: .black).first {
        model.tap(row: move.0, col: move.1)  // 成立
    }
    model.resign()  // 決着
}

@MainActor
private func playPoker(_ services: GameServices) {
    let model = PokerModel(services: services)
    model.restartSession()
    model.startGame()                     // 成立（配り）
    model.bet1Action(.bet(999_999))       // 拒否（チップ不足）
    model.bet1Action(.check)
    if model.phase == .exchange {
        if let card = model.playerHand.first {
            model.toggleCardSelection(card)  // 成立（交換札の選択）
        }
        model.confirmExchange()              // 成立（交換）
    }
    if model.phase == .betting2 {
        model.bet2Action(.check)
    }
    if model.phase == .betting2, model.currentBet > 0 {
        model.callCPUBet()
    }
    // ここまでで必ず .result（CPU フォールドまたはショーダウン）＝ 決着。
}

@MainActor
private func playConcentration(_ services: GameServices) {
    let model = ConcentrationModel(services: services)
    model.newGame(pairCount: .medium, cpuLevel: .normal)
    model.tap(index: 0)  // 成立（1 枚目）
    model.tap(index: 0)  // 拒否（めくり済み）

    // 決着: 絵柄が一致するペアを順に取り切る（一致している間は手番が続く）。
    for _ in 0..<model.cards.count where !model.isGameOver {
        let unmatched = model.cards.indices.filter { !model.cards[$0].isMatched }
        guard let first = unmatched.first,
              let second = unmatched.first(where: {
                  $0 != first && model.cards[$0].symbol == model.cards[first].symbol
              }) else { break }
        if model.firstFlippedIndex == nil { model.tap(index: first) }
        model.tap(index: second)
    }
}

@MainActor
private func playBlackjack(_ services: GameServices) {
    let model = BlackjackModel(services: services)
    model.restartSession()
    model.placeBet(999_999)  // 拒否（チップ不足）
    model.placeBet(100)      // 成立（配り）
    if model.phase == .playerTurn { model.hit() }
    if model.phase == .playerTurn { model.stand() }
    // stand → ディーラー進行 → 決着。hit でバストした場合もその時点で決着。
}

// MARK: - オン: 3 種すべてが発火する

@Suite("触覚フィードバック（オン）")
@MainActor
struct FeedbackEnabledTests {

    @Test("2048: 移動・無効なスワイプ・ゲームオーバーで発火する")
    func game2048() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        play2048(services)
        #expect(!spy.impacts.isEmpty, "動いたスワイプで発火する")
        #expect(spy.notices(of: .warning) > 0, "1マスも動かないスワイプは拒否として発火する")
        #expect(spy.notices(of: .error) > 0, "ゲームオーバーで発火する")
    }

    @Test("将棋: 着手・指せないマス・投了で発火する")
    func shogi() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        playShogi(services)
        #expect(spy.impacts.contains(.medium), "着手で発火する")
        #expect(spy.notices(of: .warning) > 0, "指せないマスは拒否として発火する")
        #expect(spy.notices(of: .error) > 0, "投了で発火する")
    }

    @Test("五目並べ: 着手・埋まったマス・投了で発火する")
    func gomoku() async {
        let (services, spy) = makeServices(hapticsEnabled: true)
        await playGomoku(services)
        #expect(spy.impacts.contains(.medium), "着手で発火する")
        #expect(spy.notices(of: .warning) > 0, "埋まっているマスは拒否として発火する")
        #expect(spy.notices(of: .error) > 0, "投了で発火する")
    }

    @Test("マインスイーパー: 開く・開き済み・地雷で発火する")
    func minesweeper() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        playMinesweeper(services)
        #expect(spy.impacts.contains(.light), "マスを開くと発火する")
        #expect(spy.impacts.contains(.rigid), "旗の着脱で発火する")
        #expect(spy.notices(of: .warning) > 0, "開き済みのマスは拒否として発火する")
        #expect(spy.notices(of: .error) > 0, "地雷を踏むと発火する")
    }

    @Test("オセロ: 着手・置けないマス・投了で発火する")
    func othello() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        playOthello(services)
        #expect(spy.impacts.contains(.medium), "着手で発火する")
        #expect(spy.notices(of: .warning) > 0, "石を返せないマスは拒否として発火する")
        #expect(spy.notices(of: .error) > 0, "投了で発火する")
    }

    @Test("ポーカー: 配り・チップ不足・決着で発火する")
    func poker() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        playPoker(services)
        #expect(spy.impacts.contains(.medium), "カードを配ると発火する")
        #expect(spy.notices(of: .warning) > 0, "チップ不足のベットは拒否として発火する")
        #expect(!spy.notices.isEmpty, "ラウンドの決着で発火する")
    }

    @Test("神経衰弱: めくり・めくり済み・全ペア成立で発火する")
    func concentration() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        playConcentration(services)
        #expect(spy.impacts.contains(.light), "カードをめくると発火する")
        #expect(spy.impacts.contains(.medium), "ペア成立で発火する")
        #expect(spy.notices(of: .warning) > 0, "めくり済みのカードは拒否として発火する")
        #expect(spy.notices(of: .success) > 0, "全ペア成立（勝ち）で発火する")
    }

    @Test("ブラックジャック: 配り・チップ不足・決着で発火する")
    func blackjack() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        playBlackjack(services)
        #expect(!spy.impacts.isEmpty, "配り・ヒットで発火する")
        #expect(spy.notices(of: .warning) > 0, "チップ不足のベットは拒否として発火する")
        #expect(!spy.notices.isEmpty, "決着で発火する")
    }
}

// MARK: - オフ: どの契機でも 1 度も発火しない（受け入れ条件）

@Suite("触覚フィードバック（オフ）")
@MainActor
struct FeedbackDisabledTests {

    @Test("設定がオフなら全8ゲームのどの契機でも発火しない")
    func nothingFiresWhenDisabled() async {
        let (services, spy) = makeServices(hapticsEnabled: false)

        play2048(services)
        playShogi(services)
        await playGomoku(services)
        playMinesweeper(services)
        playOthello(services)
        playPoker(services)
        playConcentration(services)
        playBlackjack(services)

        #expect(spy.callCount == 0, "オフのときは impact / notify とも 1 度も呼ばれない")
    }

    @Test("設定がオンなら同じ手順で発火する（オフの検証が空振りでないことの確認）")
    func firesWhenEnabled() async {
        let (services, spy) = makeServices(hapticsEnabled: true)

        play2048(services)
        playShogi(services)
        await playGomoku(services)
        playMinesweeper(services)
        playOthello(services)
        playPoker(services)
        playConcentration(services)
        playBlackjack(services)

        #expect(spy.callCount > 0)
    }
}
