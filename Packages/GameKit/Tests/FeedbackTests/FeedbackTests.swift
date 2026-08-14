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
import GameDaifugo
import GameMahjongSolitaire

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

/// 2048: マージ・移動のみ・拒否・終局を 1 度ずつ通す。
///
/// 自動プレイで終局まで回すと「1マスも動かないスワイプ」に一度も遭遇しない試行があり、
/// 約 25% で落ちていた（#94）。局面を注入して、乱数（新タイルの位置・値）が
/// どう転んでも結果が変わらない手順に固定する。
/// 終局する手では impact を鳴らさない実装なので、鳴らす手と終局する手は別の局面に分ける。
@MainActor
private func play2048(_ services: GameServices) {
    // マージあり → impact(.medium)。空きが多いので新タイルがどこに出ても終局しない。
    Game2048Model(services: services, board: [
        [2, 2, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]).move(.left)

    // マージなしの移動 → impact(.light)。同上。
    Game2048Model(services: services, board: [
        [2, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]).move(.right)

    // 空きは (0,0) の 1 マスだけで、同値の隣接も無い盤面。
    // 右へは 1 マスも動かず拒否になり、左へ寄せると空きが (0,3) に移る。
    // (0,3) の隣は 8 と 16 なので、新タイルが 2 でも 4 でも同値の隣接は生まれない = 必ず終局。
    let ending = Game2048Model(services: services, board: [
        [0, 2, 4, 8],
        [4, 8, 2, 16],
        [2, 4, 8, 2],
        [8, 2, 4, 8],
    ])
    ending.move(.right)  // 拒否 → notify(.warning)
    ending.move(.left)   // 終局 → notify(.error)
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
@discardableResult
private func playPoker(_ services: GameServices) -> PokerModel {
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
    return model
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

/// 大富豪: 何も選ばずに「出す」（拒否）→ 貪欲法で最後まで打ち切る（決着）。
/// CPU の手番は `runCPUTurnsIfNeeded` が進める（CPU 側では鳴らさない）。
@MainActor
@discardableResult
private func playDaifugo(_ services: GameServices) async -> DaifugoModel {
    let model = DaifugoModel(services: services, cpuDelay: .zero, seed: 2026)
    model.startGame()
    var didReject = false
    for _ in 0..<500 where model.phase == .playing {
        await model.runCPUTurnsIfNeeded()
        guard model.phase == .playing, model.isPlayerTurn else { continue }
        if !didReject {
            didReject = true
            model.playSelected()   // 何も選んでいないので拒否される
        }
        if let play = DaifugoRules.greedyPlay(
            hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
        ) {
            for card in play { model.toggleSelection(card) }
            model.playSelected()
        } else {
            model.pass()
        }
    }
    return model
}

/// 麻雀ソリティア: 取れない牌をタップ（拒否）→ 牌を選ぶ → 生成時の解法どおりに最後まで取り切る。
@MainActor
@discardableResult
private func playMahjong(_ services: GameServices) -> MahjongSolitaireModel {
    let model = MahjongSolitaireModel(services: services, seed: 4649)
    if let covered = MahjongSolitaireRules.index(layer: 3, hx: 12, hy: 6) {
        model.tap(covered)   // 最上段に覆われているので取れない
    }
    for pair in model.solution {
        model.tap(pair[0])
        model.tap(pair[1])
    }
    return model
}

/// ブラックジャック: 初手がブラックジャックだと配りの手応え（impact）に到達せずに決着するため、
/// 種を固定して「初手がブラックジャックにならない配り」に寄せる（#94。無指定では約 4.8% で落ちていた）。
@MainActor
@discardableResult
private func playBlackjack(_ services: GameServices) -> BlackjackModel {
    let model = BlackjackModel(services: services, seed: 20260813)
    model.restartSession()
    model.placeBet(999_999)  // 拒否（チップ不足）
    model.placeBet(100)      // 成立（配り）
    if model.phase == .playerTurn { model.hit() }
    if model.phase == .playerTurn { model.stand() }
    // stand → ディーラー進行 → 決着。hit でバストした場合もその時点で決着。
    return model
}

/// 発火を**効果音の種類に変換してから**記録するスパイ（#116）。
/// アプリ本体の `SoundFeedbackService` と同じ `SoundEffect(_:)` を通すため、
/// 「どのゲームのどの操作で、どの音が鳴るか」をそのまま検証できる。
@MainActor
private final class SpySoundService: FeedbackService {
    private(set) var effects: [SoundEffect] = []

    var kinds: Set<SoundEffect> { Set(effects) }
    var callCount: Int { effects.count }

    func impact(_ style: FeedbackImpact) { effects.append(SoundEffect(style)) }
    func notify(_ type: FeedbackNotice) { effects.append(SoundEffect(type)) }
}

/// 触覚と効果音のトグルを別々に指定して、両方をスパイした GameServices を作る（#116）。
/// 実機と同じ配線（`CompositeFeedbackService` で 2 つの `GatedFeedbackService` を束ねる）にして、
/// 「片方を切ってももう片方は鳴る」ことをそのまま検証できるようにする。
@MainActor
private func makeServices(
    hapticsEnabled: Bool,
    soundEnabled: Bool
) -> (GameServices, haptics: SpyFeedbackService, sound: SpySoundService) {
    let haptics = SpyFeedbackService()
    let sound = SpySoundService()
    let services = GameServices(
        snapshots: MemorySnapshotStore(),
        ads: NoopAdService(),
        feedback: CompositeFeedbackService([
            GatedFeedbackService(base: haptics) { hapticsEnabled },
            GatedFeedbackService(base: sound) { soundEnabled },
        ])
    )
    return (services, haptics, sound)
}

/// 全 10 ゲームの手順を 1 度ずつ通す。
@MainActor
private func playAllGames(_ services: GameServices) async {
    play2048(services)
    playShogi(services)
    await playGomoku(services)
    playMinesweeper(services)
    playOthello(services)
    playPoker(services)
    playConcentration(services)
    playBlackjack(services)
    await playDaifugo(services)
    playMahjong(services)
}

// MARK: - オン: 3 種すべてが発火する

@Suite("触覚フィードバック（オン）")
@MainActor
struct FeedbackEnabledTests {

    @Test("2048: 移動・無効なスワイプ・ゲームオーバーで発火する")
    func game2048() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        play2048(services)
        #expect(spy.impacts.contains(.medium), "マージが起きたスワイプで発火する")
        #expect(spy.impacts.contains(.light), "マージなしで動いたスワイプで発火する")
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
        let model = playPoker(services)
        #expect(spy.impacts.contains(.medium), "カードを配ると発火する")
        #expect(spy.notices(of: .warning) > 0, "チップ不足のベットは拒否として発火する")
        // 決着は「最後の notify が勝敗と一致するか」で見る（件数だけだと拒否の発火で常に真になる）。
        #expect(model.phase == .result, "手順の最後は必ず決着している")
        let expected: FeedbackNotice
        switch model.winner {
        case .player: expected = .success
        case .cpu:    expected = .error
        default:      expected = .warning
        }
        #expect(spy.notices.last == expected, "ラウンドの決着が勝敗どおりに発火する")
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
        let model = playBlackjack(services)
        #expect(spy.impacts.contains(.medium), "カードを配ると発火する")
        #expect(spy.notices(of: .warning) > 0, "チップ不足のベットは拒否として発火する")
        // ポーカーと同じ理由で、件数ではなく最後の notify を結果と突き合わせる。
        #expect(model.phase == .result, "手順の最後は必ず決着している")
        let expected: FeedbackNotice
        switch model.outcome {
        case .playerBlackjack, .win: expected = .success
        case .push:                  expected = .warning
        default:                     expected = .error
        }
        #expect(spy.notices.last == expected, "決着が結果どおりに発火する")
    }

    @Test("大富豪: カード選択・出し・拒否・決着で発火する")
    func daifugo() async {
        let (services, spy) = makeServices(hapticsEnabled: true)
        let model = await playDaifugo(services)
        #expect(spy.impacts.contains(.rigid), "カードを選ぶと発火する")
        #expect(spy.impacts.contains(.medium), "配り・カードを出すと発火する")
        #expect(spy.notices(of: .warning) > 0, "出せない組は拒否として発火する")
        #expect(model.phase == .result, "手順の最後は必ず決着している")
        let expected: FeedbackNotice
        switch model.reviewOutcome {
        case .win:  expected = .success
        case .loss: expected = .error
        case .draw: expected = .warning
        }
        #expect(spy.notices.last == expected, "決着が階級どおりに発火する")
    }

    @Test("麻雀ソリティア: 牌の選択・ペア成立・取れない牌・クリアで発火する")
    func mahjong() {
        let (services, spy) = makeServices(hapticsEnabled: true)
        let model = playMahjong(services)
        #expect(spy.impacts.contains(.rigid), "牌を選ぶと発火する")
        #expect(spy.impacts.contains(.medium), "ペア成立で発火する")
        #expect(spy.notices(of: .warning) > 0, "取れない牌は拒否として発火する")
        #expect(model.phase == .won, "手順の最後は必ず取り切っている")
        #expect(spy.notices.last == .success, "クリアで発火する")
    }
}

// MARK: - CPU の着手では手応えを鳴らさない
//
// 指を触れていない間に端末が振動するのを避ける（決着の notify は結果の通知なので鳴らす）。

@Suite("CPU の着手では鳴らさない")
@MainActor
struct FeedbackCPUSilentTests {

    @Test("五目並べ: CPU の着手では impact が増えない")
    func gomoku() async {
        let (services, spy) = makeServices(hapticsEnabled: true)
        let model = GomokuModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        model.tap(row: 7, col: 7)
        let afterHuman = spy.impacts.count
        #expect(afterHuman > 0, "人間の着手では鳴る")
        await model.performAIMoveIfNeeded()
        #expect(spy.impacts.count == afterHuman, "CPU の着手では鳴らない")
    }

    @Test("オセロ: CPU の着手では impact が増えない")
    func othello() async {
        let (services, spy) = makeServices(hapticsEnabled: true)
        let model = OthelloModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        guard let move = model.board.validMoves(for: .black).first else { return }
        model.tap(row: move.0, col: move.1)
        let afterHuman = spy.impacts.count
        #expect(afterHuman > 0, "人間の着手では鳴る")
        await model.performAIMoveIfNeeded()
        #expect(spy.impacts.count == afterHuman, "CPU の着手では鳴らない")
    }

    @Test("将棋: CPU の着手では impact が増えない")
    func shogi() async {
        let (services, spy) = makeServices(hapticsEnabled: true)
        let model = ShogiGameModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        guard case let .board(from, to, _)? = model.legalMovesCache.first(where: {
            if case .board = $0 { return true }
            return false
        }) else { return }
        model.apply(.board(from: from, to: to, promote: false))
        let afterHuman = spy.impacts.count
        #expect(afterHuman > 0, "人間の着手では鳴る")
        await model.performAIMoveIfNeeded()
        #expect(spy.impacts.count == afterHuman, "CPU の着手では鳴らない")
    }
}

// MARK: - オフ: どの契機でも 1 度も発火しない（受け入れ条件）

@Suite("触覚フィードバック（オフ）")
@MainActor
struct FeedbackDisabledTests {

    @Test("設定がオフなら全10ゲームのどの契機でも発火しない")
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
        await playDaifugo(services)
        playMahjong(services)

        #expect(spy.callCount == 0, "オフのときは impact / notify とも 1 度も呼ばれない")
    }

    @Test("設定がオンなら同じ手順で発火する（オフの検証が空振りでないことの確認）")
    func firesWhenEnabled() async {
        let (services, spy) = makeServices(hapticsEnabled: true)
        await playAllGames(services)
        #expect(spy.callCount > 0)
    }
}

// MARK: - 効果音（#116）
//
// 効果音は触覚と同じ呼び出し箇所に相乗りする（各ゲームに新しい発火点を作らない）ため、
// 「触覚が鳴るところでは効果音も鳴る」「トグルは互いに独立している」の 2 点を押さえれば足りる。

@Suite("効果音")
@MainActor
struct SoundFeedbackTests {

    /// 全10ゲームの「有効な操作の成立」「無効な操作の拒否」「局面の決着」で、
    /// アプリ本体と同じ `SoundEffect` への変換を通した音が鳴ることを、ゲームごとに確かめる。
    @Test("全10ゲームの主要な操作で効果音が鳴る（操作音・拒否音・決着音）")
    func everyGameMakesSound() async {
        // ゲームごとに分けて回し、どのゲームで落ちたかが分かるようにする。
        func check(_ name: String, _ play: @MainActor (GameServices) async -> Void) async {
            let (services, _, sound) = makeServices(hapticsEnabled: false, soundEnabled: true)
            await play(services)

            let operations: Set<SoundEffect> = [.light, .medium, .rigid]
            let endings: Set<SoundEffect> = [.success, .warning, .error]
            #expect(!sound.kinds.isDisjoint(with: operations), "\(name): 操作の成立で音が鳴る（鳴った音: \(sound.kinds)）")
            #expect(!sound.kinds.isDisjoint(with: endings), "\(name): 拒否・決着で音が鳴る（鳴った音: \(sound.kinds)）")
        }

        await check("2048") { play2048($0) }
        await check("将棋") { playShogi($0) }
        await check("五目並べ") { await playGomoku($0) }
        await check("マインスイーパー") { playMinesweeper($0) }
        await check("オセロ") { playOthello($0) }
        await check("ポーカー") { _ = playPoker($0) }
        await check("神経衰弱") { playConcentration($0) }
        await check("ブラックジャック") { _ = playBlackjack($0) }
        await check("大富豪") { _ = await playDaifugo($0) }
        await check("麻雀ソリティア") { _ = playMahjong($0) }
    }

    @Test("6種類の効果音がすべて、いずれかのゲームで実際に使われている（鳴らない音を定義していない）")
    func everySoundIsReachable() async {
        let (services, _, sound) = makeServices(hapticsEnabled: false, soundEnabled: true)
        await playAllGames(services)
        #expect(sound.kinds == Set(SoundEffect.allCases), "使われていない音: \(Set(SoundEffect.allCases).subtracting(sound.kinds))")
    }

    @Test("CompositeFeedbackService は束ねた全ての実装へ同じ発火を配る")
    func compositeFansOutToEveryService() {
        let a = SpyFeedbackService()
        let b = SpyFeedbackService()
        let c = SpyFeedbackService()
        let composite = CompositeFeedbackService([a, b, c])
        composite.impact(.medium)
        composite.notify(.error)
        for spy in [a, b, c] {
            #expect(spy.impacts == [.medium])
            #expect(spy.notices == [.error])
        }
    }

    @Test("効果音だけオフにすると、効果音は鳴らず触覚は残る")
    func soundOffKeepsHaptics() async {
        let (services, haptics, sound) = makeServices(hapticsEnabled: true, soundEnabled: false)
        await playAllGames(services)
        #expect(sound.callCount == 0, "効果音は 1 度も鳴らない")
        #expect(haptics.callCount > 0, "触覚は今までどおり鳴る")
    }

    @Test("触覚だけオフにすると、触覚は鳴らず効果音は残る")
    func hapticsOffKeepsSound() async {
        let (services, haptics, sound) = makeServices(hapticsEnabled: false, soundEnabled: true)
        await playAllGames(services)
        #expect(haptics.callCount == 0, "触覚は 1 度も鳴らない")
        #expect(sound.callCount > 0, "効果音は今までどおり鳴る")
    }

    @Test("両方オフなら、どちらも 1 度も鳴らない")
    func bothOff() async {
        let (services, haptics, sound) = makeServices(hapticsEnabled: false, soundEnabled: false)
        await playAllGames(services)
        #expect(haptics.callCount == 0)
        #expect(sound.callCount == 0)
    }
}
