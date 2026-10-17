import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameDiceCombo

/// サイコロが転がる演出（#2365）。
///
/// 見た目そのものはシミュレータでしか確かめられないので、**振る → 転がる → 止まる → 結果表示** の状態遷移、
/// 途中の目の出し方、長さの整合、View の結線をここで固定する。実時間は待たない（止まる待ちは十分長くし、
/// `settleRoll()` を直接呼んで止める）。
@MainActor
@Suite("サイコロ役づくりの振る演出")
struct DiceComboRollMotionTests {
    /// テストの間に勝手に止まらない長さ。
    private static let longInterval: Duration = .seconds(3600)

    private func makeModel(feedback: SpyFeedbackService = SpyFeedbackService(),
                           store: MemorySnapshotStore = MemorySnapshotStore(),
                           seed: UInt64 = 11) -> DiceComboModel {
        let services = GameServices(snapshots: store, ads: NoopAdService(), feedback: feedback)
        return DiceComboModel(services: services, seed: seed, rollInterval: Self.longInterval)
    }

    @Test("振ると転がり始め、出目と保存はその瞬間に確定する。止まると役を選べる")
    func rollThenSettle() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.roll()
        #expect(model.isRolling)
        #expect(model.rollTask != nil)
        #expect(model.rollsUsed == 1)
        #expect(DiceComboLogic.isValidDice(model.dice))
        let rolled = model.dice
        let saved = try #require(store.load(DiceComboSnapshot.self, for: DiceComboModel.gameID))
        #expect(saved.dice == rolled, "中断データは演出を待たずに止まった目で書く")
        // 転がっている間は結果を見せない（役の点もキープもまだ）。
        #expect(!model.canHold)
        #expect(DiceComboCategory.allCases.allSatisfy { !model.canChoose($0) && model.preview($0) == nil })

        model.settleRoll()
        #expect(!model.isRolling)
        #expect(model.rollTask == nil)
        #expect(model.dice == rolled, "止まった目は振った瞬間の結果と同じ")
        #expect(model.canHold)
        #expect(model.preview(.choice) == DiceComboLogic.score(.choice, dice: rolled))
    }

    @Test("演出があってもなくても出目の乱数列は同じ")
    func animationDoesNotChangeResults() {
        let animated = makeModel(seed: 42)
        let instant = DiceComboModel(services: nil, seed: 42)
        for _ in 0..<3 {
            animated.roll()
            animated.settleRoll()
            instant.roll()
            #expect(animated.dice == instant.dice)
        }
    }

    @Test("転がっている最中の連打では二重に振れず、警告も鳴らさない")
    func tapsWhileRollingAreIgnored() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback: feedback)
        model.roll()
        let dice = model.dice
        model.roll()
        model.roll()
        #expect(model.rollsUsed == 1 && model.dice == dice && model.rollSerial == 1)
        #expect(!model.canRoll)
        #expect(feedback.notices(of: .warning) == 0)
        model.toggleHold(0)
        #expect(model.held[0] == false, "転がっている最中はキープできない")
        model.choose(.choice)
        #expect(model.scores.isEmpty, "転がっている最中は役を選べない")
        model.settleRoll()
        #expect(model.canRoll)
        model.roll()
        #expect(model.rollsUsed == 2)
    }

    @Test("触覚は振った瞬間（medium）と止まった瞬間（light）に 1 回ずつ")
    func feedbackOnRollAndSettle() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback: feedback)
        model.roll()
        #expect(feedback.impacts == [.medium])
        model.settleRoll()
        #expect(feedback.impacts == [.medium, .light])
        model.settleRoll()
        #expect(feedback.impacts == [.medium, .light], "止まったあとにもう一度止めても鳴らない")
    }

    @Test("演出の長さが 0 なら転がらずに即座に結果を出し、止まった触覚は重ねない")
    func zeroIntervalSettlesImmediately() {
        let feedback = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        let model = DiceComboModel(services: services, seed: 1)
        model.roll()
        #expect(!model.isRolling && model.rollTask == nil)
        #expect(model.canHold)
        #expect(feedback.impacts == [.medium])
    }

    @Test("待ち時間が過ぎると自分で止まる")
    func settlesAfterInterval() async throws {
        let model = DiceComboModel(services: nil, seed: 1, rollInterval: .milliseconds(1))
        model.roll()
        #expect(model.isRolling)
        let task = try #require(model.rollTask)
        await task.value
        #expect(!model.isRolling)
        #expect(model.canHold)
    }

    @Test("転がっている最中に新しいゲームにすると、演出を止めて振る前に戻る")
    func newGameCancelsRolling() {
        let model = makeModel()
        model.roll()
        let task = model.rollTask
        model.newGame()
        #expect(!model.isRolling && model.rollTask == nil)
        #expect(task?.isCancelled == true)
        #expect(model.dice.isEmpty && model.canRoll)
    }

    @Test("中断データから戻ると転がっておらず、止まった目のまま")
    func restoreIsNotRolling() {
        let store = MemorySnapshotStore()
        let first = makeModel(store: store)
        first.roll()
        let dice = first.dice
        let restored = makeModel(store: store)
        #expect(!restored.isRolling)
        #expect(restored.dice == dice && restored.canHold)
    }

    // MARK: - 途中の目

    @Test("途中の目は 1〜6 で、切り替わるたびに必ず変わる")
    func flickerFaceChangesEveryTick() {
        for final in 1...6 {
            for index in 0..<DiceComboLogic.diceCount {
                for tick in 0..<50 {
                    let face = DiceComboMotion.flickerFace(final: final, index: index, tick: tick)
                    #expect((1...6).contains(face))
                    #expect(face != DiceComboMotion.flickerFace(final: final, index: index, tick: tick + 1))
                }
            }
        }
        #expect((1...6).contains(DiceComboMotion.flickerFace(final: 3, index: 2, tick: -7)))
    }

    @Test("途中の目を出すのは転がっていてキープしていないサイコロだけ")
    func displayedFace() {
        // 止まっていれば確定した目。
        #expect(DiceComboMotion.displayedFace(final: 4, isRolling: false, isHeld: false, index: 0, tick: 9) == 4)
        // キープ中は転がらない。
        #expect(DiceComboMotion.displayedFace(final: 4, isRolling: true, isHeld: true, index: 0, tick: 9) == 4)
        // まだ振っていなければ「？」のまま。
        #expect(DiceComboMotion.displayedFace(final: nil, isRolling: true, isHeld: false, index: 0, tick: 9) == nil)
        #expect(DiceComboMotion.displayedFace(final: 4, isRolling: true, isHeld: false, index: 0, tick: 9)
                == DiceComboMotion.flickerFace(final: 4, index: 0, tick: 9))
    }

    // MARK: - 長さ

    @Test("長さは 0.6〜1 秒で、跳ねる・回るは止まるまでに収まり、Model の待ちと同じ値から作る")
    func durations() {
        #expect((0.6...1.0).contains(DiceComboMotion.rollDuration))
        #expect(DiceComboMotion.rollInterval == .milliseconds(Int((DiceComboMotion.rollDuration * 1000).rounded())))
        let bounce = DiceComboMotion.bounceSegments.map(\.duration).reduce(0, +)
        #expect(abs(bounce - DiceComboMotion.rollDuration) < 1e-9, "跳ね終わりと止まる時刻をそろえる")
        #expect(DiceComboMotion.bounceSegments.last?.lift == 0, "最後は着地している")
        #expect(DiceComboMotion.spinDuration <= DiceComboMotion.rollDuration)
        #expect(DiceComboMotion.spinDegrees.truncatingRemainder(dividingBy: 360) == 0, "回り終えたら元の向き")
        #expect(DiceComboMotion.flickerStep < DiceComboMotion.rollDuration / 5, "止まるまでに何度も目が変わる")
    }

    // MARK: - View の結線

    @Test("View は Motion の待ちを Model に渡し、Reduce Motion で跳ねる・回るを止め、止まってから読み上げる")
    func viewIsWiredToMotion() throws {
        let view = try SourceScan.packageSource("Sources/GameDiceCombo/DiceComboView.swift")
        #expect(SourceScan.matchCount(
            of: #"DiceComboModel\(services: services, rollInterval: DiceComboMotion\.rollInterval\)"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"@Environment\(\\\.accessibilityReduceMotion\)"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"let tumbles = !isHeld && !reduceMotion"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"DiceComboMotion\.displayedFace\("#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"paused: !model\.isRolling"#, in: view) == 1,
                "止まったあとも目の切り替えの時計が回り続ける")
        #expect(SourceScan.matchCount(of: #"guard wasRolling, !isRolling"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"AccessibilityNotification\.Announcement"#, in: view) == 1)
        // 読み上げは確定した目（value）から作り、途中の目（shown）からは作らない。
        #expect(SourceScan.matchCount(of: #"dieLabel\(index: index, value: \$0"#, in: view) == 1)
        #expect(!view.contains("shown.map"))
    }
}
