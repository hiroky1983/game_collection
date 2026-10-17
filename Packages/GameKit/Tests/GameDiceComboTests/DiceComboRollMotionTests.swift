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
        // まだ振っていなければ確定した目はない（View が振る前の固定の目で埋める）。
        #expect(DiceComboMotion.displayedFace(final: nil, isRolling: true, isHeld: false, index: 0, tick: 9) == nil)
        #expect(DiceComboMotion.displayedFace(final: 4, isRolling: true, isHeld: false, index: 0, tick: 9)
                == DiceComboMotion.flickerFace(final: 4, index: 0, tick: 9))
    }

    // MARK: - 長さ

    @Test("長さは 0.6〜1 秒で、跳ねる・回るは止まるまでに収まり、Model の待ちと同じ値から作る")
    func durations() throws {
        #expect((0.6...1.0).contains(DiceComboMotion.rollDuration))
        #expect(DiceComboMotion.rollInterval == .milliseconds(Int((DiceComboMotion.rollDuration * 1000).rounded())))
        let bounce = DiceComboMotion.bounceSegments.map(\.duration).reduce(0, +)
        #expect(abs(bounce - DiceComboMotion.rollDuration) < 1e-9, "跳ね終わりと止まる時刻をそろえる")
        #expect(DiceComboMotion.bounceSegments.last?.lift == 0, "最後は着地している")
        #expect(DiceComboMotion.spinDuration <= DiceComboMotion.rollDuration)
        for segments in [DiceComboMotion.tumbleSegmentsX, DiceComboMotion.tumbleSegmentsY] {
            let total = segments.map(\.duration).reduce(0, +)
            #expect(abs(total - DiceComboMotion.spinDuration) < 1e-9, "転がりきる時刻をそろえる")
            let last = try #require(segments.last?.degrees)
            #expect(last.truncatingRemainder(dividingBy: 360) == 0 && last != 0, "転がり終えたら前面が正面に戻る")
        }
        #expect(DiceComboMotion.flickerStep < DiceComboMotion.rollDuration / 5, "止まるまでに何度も目が変わる")
    }

    @Test("キーフレームのコマ: 最初は正面・途中は転がって浮いている・止まる時刻には着地して正面に戻る")
    func tumbleFrames() {
        let start = DiceComboMotion.tumble(at: 0)
        #expect(start.lift == 0 && start.rollX == 0 && start.rollY == 0)

        let middle = DiceComboMotion.tumble(at: 0.2)
        #expect(middle.lift < -1, "跳ねて浮いている")
        #expect(middle.rollX > 30 && middle.rollX < 330, "手前へ転がっている途中")
        #expect(middle.rollY > 30 && middle.rollY < 330, "横へ転がっている途中")
        // 正面でない向きでは立方体の面が 2 枚以上見える。
        #expect(DiceComboCube.visibleFaces(front: 3, rotation: middle.rotation(direction: 1), side: 60).count >= 2)

        let end = DiceComboMotion.tumble(at: DiceComboMotion.rollDuration)
        #expect(abs(end.lift) < 1e-6, "止まる時刻には着地")
        #expect(abs(end.rollX.truncatingRemainder(dividingBy: 360)) < 1e-6)
        #expect(abs(end.rollY.truncatingRemainder(dividingBy: 360)) < 1e-6)
        // 止まった向きで描くと、回転 0 と同じく前面 1 枚だけ。
        let settled = DiceComboCube.visibleFaces(front: 3, rotation: end.rotation(direction: -1), side: 60)
        #expect(settled.count == 1 && settled.first?.value == 3)
    }

    // MARK: - 振る前の目

    @Test("振る前の目は 1〜6 の固定の並びで、添字がはみ出しても落ちない")
    func idleFaces() {
        #expect(DiceComboMotion.idleFaces.count == DiceComboLogic.diceCount)
        #expect(DiceComboMotion.idleFaces.allSatisfy { (1...6).contains($0) })
        #expect(Set(DiceComboMotion.idleFaces).count == DiceComboMotion.idleFaces.count, "同じ目を並べない")
        #expect(DiceComboMotion.idleFaces.sorted() != DiceComboMotion.idleFaces, "連番に見せない")
        for index in -2..<10 {
            #expect((1...6).contains(DiceComboMotion.idleFace(index: index)))
        }
        #expect(DiceComboMotion.idleFace(index: 1) == DiceComboMotion.idleFaces[1])
    }

    // MARK: - 立方体

    @Test("向かい合う面の和は 7 で、6 面に 1〜6 がちょうど 1 回ずつ")
    func cubeFaceValues() {
        for front in 1...6 {
            let values = DiceComboCube.faceValues(front: front)
            #expect(values[.front] == front)
            #expect(values[.front]! + values[.back]! == 7)
            #expect(values[.right]! + values[.left]! == 7)
            #expect(values[.top]! + values[.bottom]! == 7)
            #expect(Set(values.values) == Set(1...6))
        }
        #expect(DiceComboCube.faceValues(front: 9)[.front] == 1, "範囲外は 1 に丸める")
    }

    @Test("回転 0 なら前面 1 枚だけで、その写像は辺の長さへの拡大そのもの")
    func cubeIdentityIsFlatSquare() throws {
        let faces = DiceComboCube.visibleFaces(front: 5, rotation: .identity, side: 40)
        let face = try #require(faces.first)
        #expect(faces.count == 1 && face.value == 5)
        #expect(face.brightness == 1)
        let t = face.transform
        #expect(t.a == 40 && t.d == 40 && t.b == 0 && t.c == 0 && t.tx == 0 && t.ty == 0)
        // 1 周しても同じ絵。
        let turned = DiceComboCube.visibleFaces(front: 5, rotation: .init(x: 360, y: -360), side: 40)
        #expect(turned.count == 1 && turned.first?.value == 5)
        #expect(abs((turned.first?.transform.tx ?? 1) - 0) < 1e-6)
    }

    @Test("横へ 45° 回すと前面と右面が同じ明るさで見え、横の面は正面より暗い")
    func cubeSideFacesAreShaded() throws {
        // y を負に回すと右面が手前へ出てくる。
        let faces = DiceComboCube.visibleFaces(front: 1, rotation: .init(y: -45), side: 40)
        #expect(faces.count == 2)
        let values = Set(faces.map(\.value))
        #expect(values == [1, 2], "前面 1 と右面（1 の残りの組の小さい方 2）")
        #expect(abs(faces[0].brightness - faces[1].brightness) < 1e-6)
        #expect(faces.allSatisfy { $0.brightness < 1 && $0.brightness >= DiceComboCube.shadowFloor })
        // 投影した幅は辺の √2 倍（平行投影）。
        let xs = faces.flatMap { face in
            [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)].map { $0.applying(face.transform).x }
        }
        #expect(abs((xs.max()! - xs.min()!) - 40 * 2.0.squareRoot()) < 1e-6)

        // 3 軸とも傾ければ 3 面見える。
        #expect(DiceComboCube.visibleFaces(front: 1, rotation: .init(x: 30, y: 40), side: 40).count == 3)
        // 真横（90°）は幅がないので描かない。
        #expect(DiceComboCube.visibleFaces(front: 1, rotation: .init(y: 90), side: 40).count == 1)
    }

    // MARK: - View の結線

    @Test("View は Motion の待ちを Model に渡し、Reduce Motion で跳ねる・転がるを止め、止まってから読み上げる")
    func viewIsWiredToMotion() throws {
        let view = try SourceScan.packageSource("Sources/GameDiceCombo/DiceComboView.swift")
        #expect(SourceScan.matchCount(
            of: #"DiceComboModel\(services: services, rollInterval: DiceComboMotion\.rollInterval\)"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"@Environment\(\\\.accessibilityReduceMotion\)"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"let tumbles = !isHeld && !reduceMotion && value != nil"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"DiceComboMotion\.displayedFace\("#, in: view) == 1)
        // 立体の向きはキーフレームの値から作り、View と テストで同じキーフレームを使う。
        #expect(SourceScan.matchCount(of: #"DiceComboMotion\.tumbleKeyframes\(\)"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"tumble\.rotation\(direction:"#, in: view) == 1)
        // 振る前は「？」ではなく固定の目を薄く出す。
        #expect(SourceScan.matchCount(of: #"DiceComboMotion\.idleFace\(index: index\)"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"isUnrolled: value == nil"#, in: view) == 1)
        #expect(!view.contains(#"Text(verbatim: "?")"#))
        #expect(SourceScan.matchCount(of: #"paused: !model\.isRolling"#, in: view) == 1,
                "止まったあとも目の切り替えの時計が回り続ける")
        #expect(SourceScan.matchCount(of: #"guard wasRolling, !isRolling"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"AccessibilityNotification\.Announcement"#, in: view) == 1)
        // 読み上げは確定した目（value）から作り、途中の目（shown）からは作らない。
        #expect(SourceScan.matchCount(of: #"dieLabel\(index: index, value: \$0"#, in: view) == 1)
        #expect(!view.contains("shown.map"))
    }
}
