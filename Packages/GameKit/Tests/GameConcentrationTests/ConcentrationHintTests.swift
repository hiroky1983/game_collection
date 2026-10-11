import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameConcentration

/// 神経衰弱のヒント（#2026）。1 枚目をめくったあとだけ押せて、相方の札を光らせる。無料 1 回・広告で最大 3 回。
@MainActor
@Suite("神経衰弱 ヒント（#2026）")
struct ConcentrationHintTests {

    private func makeModel(services: GameServices? = nil) -> ConcentrationModel {
        ConcentrationModel(services: services, autoClearDelay: 40_000_000)
    }

    /// 札を 1 枚めくった状態にして、その札を返す。
    @discardableResult
    private func flipFirst(_ model: ConcentrationModel, at index: Int = 0) -> Int {
        model.tap(index: index)
        return index
    }

    @Test("示した位置は必ず1枚目と同じ絵柄の別の札")
    func hintPointsAtThePartner() throws {
        for pairs in ConcentrationPairCount.allCases {
            let model = makeModel()
            model.newGame(pairCount: pairs, cpuLevel: .normal)
            for first in model.cards.indices {
                let m = makeModel()
                m.newGame(pairCount: pairs, cpuLevel: .normal)
                m.tap(index: first)
                #expect(m.requestHint())
                let hint = try #require(m.hintIndex)
                #expect(hint != first)
                #expect(m.cards[hint].symbol == m.cards[first].symbol)
                #expect(!m.cards[hint].isFaceUp, "札をめくってはいけない（めくるのはプレイヤー）")
            }
        }
    }

    @Test("1枚目をめくる前は押せず、回数も減らない")
    func notBeforeTheFirstFlip() {
        let model = makeModel()
        #expect(!model.canUseHint)
        #expect(!model.requestHint())
        #expect(model.hints.used == 0)
        #expect(model.hintIndex == nil)
    }

    @Test("2枚めくったあと（不一致の表示中）は押せず、回数も減らない")
    func notAfterTheSecondFlip() throws {
        let model = makeModel()
        let a = flipFirst(model)
        let b = try #require(model.cards.indices.first { model.cards[$0].symbol != model.cards[a].symbol })
        model.tap(index: b)
        #expect(!model.mismatchedIndices.isEmpty)
        #expect(!model.canUseHint)
        #expect(!model.requestHint())
        #expect(model.hints.used == 0)
    }

    @Test("CPU の番は押せない")
    func notOnCPUTurn() {
        let model = makeModel()
        flipFirst(model)
        model.clearMismatch() // 不一致が無いので何も起きない
        #expect(model.canUseHint)
        // CPU の番を直接作る: 不一致を出してターンを渡す
        let m = makeModel()
        let a = flipFirst(m)
        let b = m.cards.indices.first { m.cards[$0].symbol != m.cards[a].symbol }!
        m.tap(index: b)
        m.clearMismatch()
        #expect(!m.isHumanTurn)
        #expect(!m.canUseHint)
        #expect(!m.requestHint())
        #expect(m.hints.used == 0)
    }

    @Test("決着後は押せない")
    func notAfterGameOver() {
        let model = makeModel()
        model.newGame(pairCount: .small, cpuLevel: .weak)
        // 全ペアを人間が揃えて決着させる。
        var done = Set<Int>()
        for i in model.cards.indices where !done.contains(i) {
            let j = model.cards.indices.first { $0 != i && model.cards[$0].symbol == model.cards[i].symbol }!
            model.tap(index: i)
            model.tap(index: j)
            done.insert(i); done.insert(j)
        }
        #expect(model.isGameOver)
        #expect(!model.canUseHint)
        #expect(!model.requestHint())
        #expect(model.hints.used == 0)
    }

    @Test("無料1回 → 広告で最大3回 → 使い切り")
    func freeThenAdThenExhausted() throws {
        let model = makeModel()
        flipFirst(model)
        #expect(model.hintsRemaining == 4)
        #expect(!model.needsAdForHint)
        #expect(model.requestHint())
        #expect(model.hints.used == 1)
        #expect(model.needsAdForHint)
        #expect(!model.requestHint(), "無料を使い切ったら広告なしでは出ない")
        #expect(model.hints.used == 1)
        for n in 2...4 {
            let first = model.firstFlippedIndex
            #expect(model.grantAdHint(forGame: model.gameSerial, first: first))
            #expect(model.hints.used == n)
        }
        #expect(model.hints.isExhausted)
        #expect(!model.canUseHint)
        #expect(!model.grantAdHint(forGame: model.gameSerial, first: model.firstFlippedIndex))
        #expect(model.hints.used == 4)
    }

    @Test("無料が残っているうちは広告の付与を受け付けない")
    func adGrantRefusedWhileFreeRemains() {
        let model = makeModel()
        flipFirst(model)
        #expect(!model.grantAdHint(forGame: model.gameSerial, first: model.firstFlippedIndex))
        #expect(model.hints.used == 0)
    }

    @Test("広告を見ているあいだに新規ゲームが始まったら、印を出さず回数も減らさない")
    func adGrantRejectedAfterNewGame() {
        let model = makeModel()
        flipFirst(model)
        _ = model.requestHint()
        let game = model.gameSerial
        let first = model.firstFlippedIndex
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        flipFirst(model)
        #expect(model.hints.used == 0, "新しい局では回数が戻る")
        // 無料を使い切らせてから、前の局の広告を当てる
        _ = model.requestHint()
        let used = model.hints.used
        #expect(!model.grantAdHint(forGame: game, first: first))
        #expect(model.hints.used == used)
    }

    @Test("広告を見ているあいだに待ったで札が戻ったら、印を出さず回数も減らさない")
    func adGrantRejectedAfterMatta() throws {
        let model = makeModel()
        flipFirst(model)
        _ = model.requestHint()
        let first = model.firstFlippedIndex
        let game = model.gameSerial
        // 札を戻す: 不一致を出して待った
        let a = try #require(first)
        let b = try #require(model.cards.indices.first { model.cards[$0].symbol != model.cards[a].symbol })
        model.tap(index: b)
        model.pauseAutoTurn()
        #expect(model.useMatta())
        #expect(model.firstFlippedIndex == nil)
        #expect(!model.grantAdHint(forGame: game, first: first))
        #expect(model.hints.used == 1)
        #expect(model.hintIndex == nil)
    }

    @Test("光らせる時間は Model が返し、過ぎたら消える（実時間は待たない）")
    func glowDurationAndFinish() throws {
        let model = makeModel()
        flipFirst(model)
        #expect(model.hintGlowDuration == nil)
        #expect(model.requestHint())
        #expect(model.hintGlowDuration == .seconds(1))
        let run = model.hintRun
        model.finishHint(run: run - 1)
        #expect(model.hintIndex != nil, "古い待ちが新しい印を消してはいけない")
        model.finishHint(run: run)
        #expect(model.hintIndex == nil)
        #expect(model.hintGlowDuration == nil)
    }

    @Test("光っている間は押せず、回数も減らない")
    func notWhileGlowing() {
        let model = makeModel()
        flipFirst(model)
        #expect(model.requestHint())
        #expect(!model.canUseHint)
        #expect(!model.requestHint())
        #expect(!model.grantAdHint(forGame: model.gameSerial, first: model.firstFlippedIndex))
        #expect(model.hints.used == 1)
        model.finishHint(run: model.hintRun)
        #expect(model.canUseHint)
    }

    @Test("印が出ている間に2枚目をめくったら印は消える")
    func hintClearsOnFlip() throws {
        let model = makeModel()
        let a = flipFirst(model)
        #expect(model.requestHint())
        let partner = try #require(model.hintIndex)
        model.tap(index: partner)
        #expect(model.hintIndex == nil)
        #expect(model.cards[a].isMatched)
    }

    @Test("使った回数は中断データに持ち回り、復元しても戻らない。印は復元しない")
    func hintsUsedSurvivesResume() throws {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let model = makeModel(services: services)
        flipFirst(model)
        #expect(model.requestHint())
        let restored = makeModel(services: services)
        #expect(restored.hints.used == 1)
        #expect(restored.needsAdForHint)
        #expect(restored.hintIndex == nil)
        #expect(restored.firstFlippedIndex != nil, "1枚目は表のまま戻る")
    }

    @Test("ヒントの鍵を持たない旧い中断データは未使用として読む")
    func legacySnapshotReadsAsUnused() throws {
        struct Legacy: Codable {
            var symbols: [String]; var isFaceUp: [Bool]; var isMatched: [Bool]
            var currentPlayer = 0; var playerScore = 0; var cpuScore = 0
            var pairCount = ConcentrationPairCount.small.rawValue
            var cpuLevel = ConcentrationCPULevel.normal.rawValue
            var mattaUsed = false
        }
        let pairs = ConcentrationPairCount.small.rawValue
        let symbols = (0..<pairs).flatMap { [ConcentrationFigure.allCases[$0].rawValue, ConcentrationFigure.allCases[$0].rawValue] }
        let store = MemorySnapshotStore()
        try store.save(Legacy(symbols: symbols, isFaceUp: Array(repeating: false, count: symbols.count),
                              isMatched: Array(repeating: false, count: symbols.count)), for: "concentration")
        let model = makeModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.hints.used == 0)
        #expect(model.hintsRemaining == 4)
    }

    @Test("新規ゲームで回数が戻る")
    func newGameResetsBudget() {
        let model = makeModel()
        flipFirst(model)
        _ = model.requestHint()
        model.newGame(pairCount: .small, cpuLevel: .normal)
        #expect(model.hints.used == 0)
        #expect(model.hintIndex == nil)
    }
}
