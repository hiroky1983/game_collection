import Testing
import Foundation
import Core
@testable import GameFruits
import CoreTestSupport

// MARK: - Helpers

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    feedback: SpyFeedbackService = SpyFeedbackService(),
    playLog: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil
) -> GameServices {
    GameServices(
        snapshots: store,
        ads: NoopAdService(),
        feedback: feedback,
        playLog: playLog,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: ["fruits"]) }
    )
}

@MainActor
private func makePlayLog(_ suite: String) -> (PlayLog, UserDefaults, String) {
    let name = "asobiba.fruits.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults, name)
}

/// フレーム刻みで `seconds` ぶん進める。
@MainActor
private func advance(_ model: FruitsModel, seconds: Double) {
    var elapsed = 0.0
    while elapsed < seconds {
        model.tick(dt: 1.0 / 60)
        elapsed += 1.0 / 60
    }
}

/// 次の果物が手に来るまで待ってから `x` で落とす。
@MainActor
private func dropWhenReady(_ model: FruitsModel, at x: Double) {
    advance(model, seconds: FruitsModel.dropCooldown + 0.05)
    model.moveCursor(to: x)
    model.drop()
}

/// 盤の中身を決め打ちにした中断データを注入して起こす（乱数に頼らず狙った局面を作る手口）。
@MainActor
private func makeModel(
    fruits: [Fruit],
    store: MemorySnapshotStore = MemorySnapshotStore(),
    held: FruitKind? = .tsubaki,
    next: FruitKind = .ume,
    score: Int = 0,
    continueUsed: Bool = false,
    hasMadeKinmatsu: Bool = false,
    feedback: SpyFeedbackService = SpyFeedbackService(),
    playLog: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil
) -> FruitsModel {
    let services = makeServices(store: store, feedback: feedback, playLog: playLog, analytics: analytics)
    // 復元は新しいプレイではなく `game_start` を送らない（進行中のプレイが無いと `game_end` も出ない）ので、
    // 本番と同じく「一度始めて（game_start）、中断して、開き直した」形にする。
    _ = FruitsModel(services: services, seed: 1)
    feedback.reset()
    let snapshot = FruitsSnapshot(
        fruits: fruits, cursorX: 50, score: score, heldKind: held, nextKind: next,
        continueUsed: continueUsed, seed: 1, drawCount: 0, dropCount: fruits.count, hasMadeKinmatsu: hasMadeKinmatsu
    )
    try? store.save(snapshot, for: "fruits")
    return FruitsModel(services: services)
}

/// 止まっている果物（猶予を過ぎ、触れた手応えも済み）。
private func resting(_ id: Int, _ kind: FruitKind, x: Double, y: Double) -> Fruit {
    Fruit(id: id, kind: kind, x: x, y: y, age: 5, hasTouched: true)
}

/// 左の壁に沿った柱。いちばん上の真柏の頭が危険線より上に出る。
private let overflowingColumn: [Fruit] = {
    let kinmatsu = FruitKind.kinmatsu.radius
    let kuromatsu = FruitKind.kuromatsu.radius
    let shinpaku = FruitKind.shinpaku.radius
    return [
        resting(0, .kinmatsu, x: kinmatsu, y: kinmatsu),
        resting(1, .kuromatsu, x: kuromatsu, y: kinmatsu * 2 + kuromatsu),
        resting(2, .shinpaku, x: shinpaku, y: kinmatsu * 2 + kuromatsu * 2 + shinpaku),
    ]
}()

// MARK: - 開始と操作

@Suite("おじさんの盆栽の開始と操作（#1319）")
@MainActor
struct FruitsStartTests {

    @Test("新しいプレイは得点 0・果物を手に持って始まり、game_start を 1 回送る")
    func freshStart() {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let model = FruitsModel(services: makeServices(store: store, analytics: spy), seed: 7)
        #expect(model.score == 0)
        #expect(model.phase == .playing)
        #expect(model.heldKind != nil)
        #expect(FruitKind.dropPool.contains(model.heldKind!))
        #expect(FruitKind.dropPool.contains(model.nextKind))
        #expect(model.canDrop)
        #expect(model.dropCount == 0)
        #expect(!model.continueUsed)
        #expect(!model.hasProgressToLose)
        #expect(spy.starts(of: "fruits") == 1)
        #expect(store.isEmpty, "落とす前は中断データを書かない")
    }

    @Test("同じ種からは同じ果物の列が出る")
    func seedFixesTheSequence() {
        func sequence() -> [FruitKind] {
            let model = FruitsModel(services: makeServices(), seed: 42)
            var kinds: [FruitKind] = [model.heldKind!]
            for index in 0..<8 {
                dropWhenReady(model, at: 15 + Double(index) * 9)
                advance(model, seconds: FruitsModel.dropCooldown + 0.05)
                kinds.append(model.heldKind!)
            }
            return kinds
        }
        #expect(sequence() == sequence())
        #expect(Set(sequence()).count > 1, "5 種から引いているのに 9 回連続で同じ種類")
    }

    @Test("落とすと手が空き、間を置いて「つぎ」の果物が手に来る")
    func dropHandsOverTheNext() {
        let feedback = SpyFeedbackService()
        let store = MemorySnapshotStore()
        let model = FruitsModel(services: makeServices(store: store, feedback: feedback), seed: 3)
        let held = model.heldKind!
        let next = model.nextKind
        model.moveCursor(to: 40)
        model.drop()
        #expect(model.field.count == 1)
        #expect(model.fruitCount == 1)
        #expect(model.field.fruits.first?.kind == held)
        #expect(model.field.fruits.first?.x == 40)
        #expect(model.heldKind == nil)
        #expect(!model.canDrop)
        #expect(model.dropCount == 1)
        #expect(model.hasProgressToLose)
        #expect(feedback.impacts == [.light])
        #expect(store.saveCount == 1, "落とした瞬間に 1 回保存する")

        #expect(feedback.notices.isEmpty)
        model.drop()
        #expect(model.field.count == 1, "手が空のときは落ちない")
        #expect(feedback.notices == [.warning], "待ち時間中のタップは警告の手応えを返す")

        advance(model, seconds: FruitsModel.dropCooldown - 0.1)
        #expect(model.heldKind == nil, "間が開けるまでは空のまま")
        advance(model, seconds: 0.2)
        #expect(model.heldKind == next)
        #expect(model.canDrop)
    }

    @Test("落とす前の位置は持っている果物の半径ぶん壁から離す")
    func cursorClampsByHeldRadius() {
        let model = makeModel(fruits: [], held: .mikan, next: .sakura)
        model.moveCursor(to: 0)
        #expect(model.field.cursorX == FruitKind.mikan.radius)
        model.drop()
        // 手が空のあいだは「つぎ」の半径で丸める。
        model.moveCursor(to: 0)
        #expect(model.field.cursorX == FruitKind.sakura.radius)
        // 大きい果物へ持ち替えた瞬間、壁際なら内側へ寄る。
        advance(model, seconds: FruitsModel.dropCooldown + 0.05)
        #expect(model.field.cursorX >= model.heldKind!.radius)
    }

    @Test("落とすと 1 手として数え、盤面を捨てたら途中離脱になる")
    func dropCountsAsProgress() {
        let spy = SpyAnalyticsService()
        let model = FruitsModel(services: makeServices(analytics: spy), seed: 5)
        model.drop()
        model.newGame()
        #expect(spy.quits(of: "fruits") == 1, "落としたあとのやり直しは途中離脱")
        #expect(spy.starts(of: "fruits") == 2)
    }
}

// MARK: - 合体と得点

@Suite("おじさんの盆栽の合体と得点")
@MainActor
struct FruitsScoringTests {

    @Test("同じ種類が触れると 1 つ上の種類の得点が入り、演出の合図が積まれる")
    func mergeScores() {
        let feedback = SpyFeedbackService()
        let r = FruitKind.tsubaki.radius
        let model = makeModel(
            fruits: [resting(0, .tsubaki, x: 40, y: r), resting(1, .tsubaki, x: 40 + r * 2 - 0.1, y: r)],
            feedback: feedback
        )
        advance(model, seconds: 1)
        #expect(model.score == FruitKind.fuji.points)
        #expect(model.field.count == 1)
        #expect(model.field.fruits.first?.kind == .fuji)
        #expect(model.effects.count == 1)
        #expect(model.effects.first?.kind == .merge(.fuji))
        #expect(model.effects.first?.serial == 0)
        #expect(feedback.impacts.contains(.light), "小さい合体は軽い手応え")
        #expect(!model.hasMadeKinmatsu)
    }

    @Test("金の松ができると勝ちの印が立ち、節目の手応えが鳴る")
    func makingAMelonMarksTheWin() {
        let feedback = SpyFeedbackService()
        let r = FruitKind.kuromatsu.radius
        let model = makeModel(
            fruits: [resting(0, .kuromatsu, x: r, y: r), resting(1, .kuromatsu, x: r * 3 - 0.1, y: r)],
            feedback: feedback
        )
        advance(model, seconds: 1)
        #expect(model.hasMadeKinmatsu)
        #expect(model.score == FruitKind.kinmatsu.points)
        #expect(feedback.notices(of: .milestone) == 1)
        #expect(feedback.notices(of: .success) == 0)
        #expect(model.field.fruits.map(\.kind) == [.kinmatsu])
        #expect(model.highestKind == .kinmatsu)
    }

    @Test("最高の段は合体でできた段を覚え、はじめからで消える（#2865）")
    func highestKindTracksLargestMerge() {
        let r = FruitKind.tsubaki.radius
        let model = makeModel(
            fruits: [resting(0, .tsubaki, x: 40, y: r), resting(1, .tsubaki, x: 40 + r * 2 - 0.1, y: r)]
        )
        #expect(model.highestKind == nil)
        advance(model, seconds: 1)
        #expect(model.highestKind == .fuji)
        model.newGame()
        #expect(model.highestKind == nil, "はじめからで消える")
    }

    @Test("最高の段は中断データから復元でき、鍵の無い古いデータは盤から推定する（#2865）")
    func highestKindRestores() throws {
        let store = MemorySnapshotStore()
        let kuro = FruitKind.kuromatsu.radius
        let model = makeModel(fruits: [resting(0, .kuromatsu, x: kuro, y: kuro)], store: store)
        #expect(model.highestKind == .kuromatsu, "鍵無しの中断データは盤の最大の段")
        let snapshot = FruitsSnapshot(
            fruits: [], cursorX: 50, score: 0, heldKind: .tsubaki, nextKind: .ume,
            continueUsed: false, seed: 1, drawCount: 0, dropCount: 0, hasMadeKinmatsu: false,
            highestKind: .shinpaku
        )
        try store.save(snapshot, for: "fruits")
        #expect(FruitsModel(services: makeServices(store: store)).highestKind == .shinpaku)
    }

    @Test("金の松どうしが消えると 100 点と節目の手応え")
    func melonsVanishForBonus() {
        let feedback = SpyFeedbackService()
        let r = FruitKind.kinmatsu.radius
        let model = makeModel(
            fruits: [resting(0, .kinmatsu, x: r, y: r), resting(1, .kinmatsu, x: r * 3 - 0.1, y: r)],
            score: 10, hasMadeKinmatsu: true, feedback: feedback
        )
        advance(model, seconds: 1)
        #expect(model.score == 10 + FruitKind.kinmatsuVanishPoints)
        #expect(model.field.count == 0)
        #expect(model.effects.last?.kind == .vanish)
        #expect(feedback.notices(of: .milestone) == 1)
    }

    @Test("演出の合図は直近 16 件だけ残す")
    func effectsAreTrimmed() {
        // 同じ種類の組を 17 組、できた椿どうしが触れない間隔で格子に並べる
        // （縦横とも、椿の直径 8.2 + 隙間 0.3 より離す）。
        var fruits: [Fruit] = []
        let r = FruitKind.sakura.radius
        for pair in 0..<17 {
            let x = 12 + Double(pair % 4) * 24
            let y = 10 + Double(pair / 4) * 10.5
            fruits.append(resting(pair * 2, .sakura, x: x - r + 0.05, y: y))
            fruits.append(resting(pair * 2 + 1, .sakura, x: x + r - 0.05, y: y))
        }
        let model = makeModel(fruits: fruits)
        model.tick(dt: 1.0 / 60)
        #expect(model.effects.count == FruitsModel.effectHistoryLimit)
        #expect(model.effects.first?.serial == 1, "古いほうから落ちる")
        #expect(model.score == 17 * FruitKind.tsubaki.points)
    }
}

// MARK: - 終局・コンティニュー・やり直し

@Suite("おじさんの盆栽の終局とコンティニュー")
@MainActor
struct FruitsGameOverTests {

    @Test("危険線を越えたままなら終局し、記録・解析・中断データの消去が 1 回ずつ起きる")
    func overflowFinishesTheGame() {
        let spy = SpyAnalyticsService()
        let feedback = SpyFeedbackService()
        let (playLog, defaults, name) = makePlayLog("gameover")
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MemorySnapshotStore()
        let model = makeModel(fruits: overflowingColumn, store: store, score: 120, feedback: feedback, playLog: playLog, analytics: spy)
        advance(model, seconds: 3.5)
        #expect(model.phase == .gameOver)
        #expect(model.heldKind == nil)
        #expect(!model.canDrop)
        #expect(!model.hasProgressToLose)
        #expect(model.recordResult != nil)
        #expect(model.recordResult?.record.bestPoints == 120)
        #expect(model.recordResult?.record.plays == 1)
        #expect(model.recordResult?.record.losses == 1, "金の松を作れなかったプレイは負け")
        #expect(spy.ends(of: "fruits") == 1)
        #expect(spy.outcomes == [.loss])
        #expect(feedback.notices(of: .error) == 1)
        #expect(!store.exists(for: "fruits"), "終局で中断データは消える")

        // 終局後は動かず、落とせない。
        let frozen = model.field
        model.drop()
        advance(model, seconds: 1)
        #expect(model.field == frozen)
        #expect(spy.ends(of: "fruits") == 1, "game_end は 1 回だけ")
    }

    @Test("金の松を作っていたプレイの終局は勝ちとして記録する")
    func melonMakesTheFinishAWin() {
        let (playLog, defaults, name) = makePlayLog("win")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyAnalyticsService()
        let model = makeModel(fruits: overflowingColumn, score: 500, hasMadeKinmatsu: true, playLog: playLog, analytics: spy)
        advance(model, seconds: 3.5)
        #expect(model.phase == .gameOver)
        #expect(model.recordResult?.record.wins == 1)
        #expect(spy.outcomes == [.win])
    }

    @Test("順位表へ送る成績は得点で、コンティニューを使った回は送らない")
    func leaderboardEligibility() {
        let model = makeModel(fruits: [], score: 50)
        #expect(model.finishingScore == GameScore(metric: .points, points: 50, isLeaderboardEligible: true))
        let continued = makeModel(fruits: [], score: 50, continueUsed: true)
        #expect(continued.finishingScore.isLeaderboardEligible == false)
        #expect(continued.finishingScore.points == 50)
    }

    @Test("コンティニューは小さい果物と線より上の果物を片づけ、得点を残し、負けの記録を取り消す")
    func continueAfterAd() {
        let spy = SpyAnalyticsService()
        let (playLog, defaults, name) = makePlayLog("continue")
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MemorySnapshotStore()
        let fruits = overflowingColumn + [resting(3, .sakura, x: 70, y: FruitKind.sakura.radius),
                                          resting(4, .mikan, x: 85, y: FruitKind.mikan.radius)]
        let model = makeModel(fruits: fruits, store: store, score: 300, playLog: playLog, analytics: spy)
        advance(model, seconds: 3.5)
        #expect(model.phase == .gameOver)
        let serial = model.gameSerial

        #expect(model.continueAfterAd(forGame: serial))
        #expect(model.phase == .playing)
        #expect(model.continueUsed)
        #expect(model.score == 300, "得点は残る")
        #expect(model.recordResult == nil)
        #expect(model.field.fruits.map(\.kind).sorted() == [.mikan, .kuromatsu, .kinmatsu], "真柏（線の上）と桜（小さい）が消える")
        #expect(model.fruitCount == 3, "果物の数の鏡も片づけに追従する")
        #expect(model.heldKind != nil, "すぐ落とせる")
        #expect(model.canDrop)
        #expect(playLog.record(gameID: "fruits")?.losses == 0, "負けは取り消す")
        #expect(playLog.record(gameID: "fruits")?.plays == 0)
        #expect(playLog.record(gameID: "fruits")?.bestPoints == 300, "自己ベストは残す")
        #expect(spy.starts(of: "fruits") == 2, "続きは次の 1 プレイとして数え直す（最初の開始 1 + やり直し 1）")
        #expect(store.exists(for: "fruits"), "続きは中断データに残す")

        // 2 回目は無い。
        #expect(!model.continueAfterAd(forGame: serial))
    }

    @Test("コンティニュー → 落とさずに「はじめから」: 続きの 1 プレイに game_end(quit) が 1 件付く（#3041）")
    func newGameRightAfterAdContinueSendsQuit() {
        let spy = SpyAnalyticsService()
        let model = makeModel(fruits: overflowingColumn, score: 300, analytics: spy)
        advance(model, seconds: 3.5)
        #expect(model.phase == .gameOver)
        let endsAtGameOver = spy.ends(of: "fruits")
        #expect(model.continueAfterAd(forGame: model.gameSerial))

        model.newGame()

        #expect(spy.ends(of: "fruits") == endsAtGameOver + 1, "続きの 1 プレイに game_end が付く")
        #expect(spy.quits(of: "fruits") == 1, "付いた game_end は quit")
    }

    @Test("金の松を作っていた回のコンティニューは勝ちを巻き戻し、再終局で 1 勝に数え直す（#1359）")
    func continueRewindsTheWinAndRecountsOnce() {
        let (playLog, defaults, name) = makePlayLog("continue-win")
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(fruits: overflowingColumn, score: 400, hasMadeKinmatsu: true, playLog: playLog)
        advance(model, seconds: 3.5)
        #expect(model.phase == .gameOver)
        #expect(playLog.record(gameID: "fruits")?.wins == 1)
        #expect(model.continueAfterAd(forGame: model.gameSerial))
        #expect(playLog.record(gameID: "fruits")?.wins == 0, "続きは次の 1 プレイなので、先の勝ちは巻き戻す")
        #expect(playLog.record(gameID: "fruits")?.plays == 0)
        #expect(playLog.record(gameID: "fruits")?.currentStreak == 0)
        #expect(model.hasMadeKinmatsu, "続きでも金の松を作った印は残る")

        // 続きを遊んで、もう一度終局するまで落とし続ける。
        var drops = 0
        while model.phase != .gameOver, drops < 400 {
            dropWhenReady(model, at: 70)
            drops += 1
        }
        #expect(model.phase == .gameOver, "続きが終局まで進む")
        let record = playLog.record(gameID: "fruits")
        #expect(record?.plays == 1, "1 プレイは 1 回だけ数える")
        #expect(record?.wins == 1, "2 勝にならない")
        #expect(record?.currentStreak == 1)
    }

    @Test("広告のあいだに「はじめから」で入れ替わった局へは適用しない（#729）")
    func continueRejectsStaleSerial() {
        let model = makeModel(fruits: overflowingColumn)
        advance(model, seconds: 3.5)
        #expect(model.phase == .gameOver)
        let stale = model.gameSerial
        model.newGame()
        #expect(model.gameSerial == stale + 1)
        #expect(!model.continueAfterAd(forGame: stale))
        #expect(!model.continueUsed)
        // 遊んでいる最中にも効かない。
        #expect(!model.continueAfterAd(forGame: model.gameSerial))
    }

    @Test("「はじめから」は盤・得点・コンティニュー権を戻し、中断データを消して game_start を送り直す")
    func newGameResetsEverything() {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let model = makeModel(fruits: overflowingColumn, store: store, score: 77, continueUsed: true, hasMadeKinmatsu: true, analytics: spy)
        advance(model, seconds: 3.5)
        model.newGame()
        #expect(model.phase == .playing)
        #expect(model.score == 0)
        #expect(model.field.count == 0)
        #expect(!model.continueUsed)
        #expect(!model.hasMadeKinmatsu)
        #expect(model.dropCount == 0)
        #expect(model.effects.isEmpty)
        #expect(model.heldKind != nil)
        #expect(!store.exists(for: "fruits"))
        #expect(spy.starts(of: "fruits") == 2, "最初の開始 1 回 + やり直し 1 回")
    }
}

// MARK: - 中断と復元

@Suite("おじさんの盆栽の中断データ")
@MainActor
struct FruitsSnapshotTests {

    @Test("落として止まった盤を、次に開いたときそのまま復元する（game_start は送らない）")
    func restoresTheBoard() {
        let store = MemorySnapshotStore()
        let first = FruitsModel(services: makeServices(store: store), seed: 11)
        for index in 0..<5 {
            dropWhenReady(first, at: 20 + Double(index) * 15)
        }
        advance(first, seconds: 3)
        #expect(first.field.isSettled)

        let spy = SpyAnalyticsService()
        let second = FruitsModel(services: makeServices(store: store, analytics: spy))
        #expect(second.score == first.score)
        #expect(second.dropCount == 5)
        #expect(second.field.fruits.map(\.id) == first.field.fruits.map(\.id))
        #expect(second.field.fruits.map(\.kind) == first.field.fruits.map(\.kind))
        // 保存は止まった瞬間で、その後も元のモデルは進み続ける（接触の微小な揺れ）ので、ぴったりではなく近さで見る。
        for (a, b) in zip(first.field.fruits, second.field.fruits) {
            #expect(abs(a.x - b.x) < 0.5 && abs(a.y - b.y) < 0.5, "\(a.kind.name): (\(a.x), \(a.y)) vs (\(b.x), \(b.y))")
        }
        #expect(second.heldKind == first.heldKind)
        #expect(second.nextKind == first.nextKind)
        #expect(second.field.cursorX == first.field.cursorX)
        #expect(spy.starts(of: "fruits") == 0, "復元は新しいプレイではない")
        #expect(second.phase == .playing)
    }

    @Test("落とした直後（手が空）に保存されていたら、開いた時点で次の果物を手に持っている")
    func restoreHandsOverImmediately() {
        let store = MemorySnapshotStore()
        let model = makeModel(fruits: [], store: store, held: nil, next: .mikan)
        #expect(model.heldKind == .mikan)
        #expect(FruitKind.dropPool.contains(model.nextKind))
        #expect(model.canDrop)
    }

    @Test("復元後の抽選は保存した列の続きになる")
    func drawsContinueTheSequence() throws {
        let store = MemorySnapshotStore()
        let first = FruitsModel(services: makeServices(store: store), seed: 99)
        dropWhenReady(first, at: 50)
        advance(first, seconds: 2)
        let saved = try #require(store.rawData(for: "fruits"))

        /// 同じ中断データから開いて、手に来る果物を 3 個控える（落とすたびに保存が上書きされるので置き場は分ける）。
        func nextThree() -> [FruitKind] {
            let copy = MemorySnapshotStore()
            copy.inject(saved, for: "fruits")
            let model = FruitsModel(services: makeServices(store: copy))
            var kinds: [FruitKind] = []
            for _ in 0..<3 {
                advance(model, seconds: FruitsModel.dropCooldown + 0.05)
                kinds.append(model.heldKind!)
                model.moveCursor(to: 50)
                model.drop()
            }
            return kinds
        }
        #expect(nextThree() == nextThree())
    }

    @Test("保存するのは落とした瞬間と、そのあと塊が止まったときだけ")
    func persistsOnlyAtCheckpoints() {
        let store = MemorySnapshotStore()
        let r = FruitKind.tsubaki.radius
        // 触れている椿 2 個が最初のフレームで合体する。
        let model = makeModel(fruits: [resting(0, .tsubaki, x: 40, y: r), resting(1, .tsubaki, x: 40 + r * 2 - 0.1, y: r)], store: store)
        let baseline = store.saveCount
        advance(model, seconds: 2)
        #expect(store.saveCount == baseline + 1, "合体 → 止まったときに 1 回")
        advance(model, seconds: 2)
        #expect(store.saveCount == baseline + 1, "何も変わらなければ書かない")
        model.drop()
        #expect(store.saveCount == baseline + 2, "落とした瞬間に 1 回")
        advance(model, seconds: 3)
        #expect(store.saveCount == baseline + 3, "着地して止まったときにもう 1 回（開き直したとき止まった盤が出る）")
        advance(model, seconds: 2)
        #expect(store.saveCount == baseline + 3, "止まったあとは書かない")
    }

    @Test("壊れた中断データは無視して新しいプレイを始める")
    func brokenSnapshotStartsFresh() {
        let store = MemorySnapshotStore()
        store.inject(Data("{}".utf8), for: "fruits")
        let spy = SpyAnalyticsService()
        let model = FruitsModel(services: makeServices(store: store, analytics: spy), seed: 1)
        #expect(model.field.count == 0)
        #expect(model.score == 0)
        #expect(spy.starts(of: "fruits") == 1)
    }

    @Test("中断データの JSON には抽選の種と回数が入る（旧鍵の互換は初版なので不要）")
    func snapshotCarriesTheSeed() throws {
        let store = MemorySnapshotStore()
        let model = FruitsModel(services: makeServices(store: store), seed: 1234)
        model.drop()
        let json = try #require(store.rawData(for: "fruits"))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["seed"] as? UInt64 == 1234)
        #expect(object["drawCount"] as? Int == 2)
        #expect(object["dropCount"] as? Int == 1)
        #expect(object["heldKind"] == nil, "落とした直後は手が空")
        #expect((object["fruits"] as? [Any])?.count == 1)
    }

    @Test("金の松を作った印は くっつきフルーツ時代の鍵（hasMadeMelon）で書き、読む（#2361）")
    func kinmatsuFlagKeepsTheOldKey() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(fruits: [resting(0, .ume, x: 50, y: 6)], store: store, hasMadeKinmatsu: true)
        model.drop()
        let json = try #require(store.rawData(for: "fruits"))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["hasMadeMelon"] as? Bool == true)
        #expect(object["hasMadeKinmatsu"] == nil)
        let restored = FruitsModel(services: makeServices(store: store))
        #expect(restored.hasMadeKinmatsu)
    }
}

// MARK: - 縁側のおじさんの合図

@Suite("おじさんの盆栽: 危険線に近いときの合図（#2361）")
@MainActor
struct NearLineTests {
    @Test("線の近くに止まった盆栽があるとしかめ面の合図が立ち、無ければ立たない")
    func nearLineFollowsTheStack() {
        let low = makeModel(fruits: [resting(0, .ume, x: 50, y: 6)])
        #expect(!low.isNearLine)
        let margin = FruitField.Metrics.nearLineMargin
        let r = FruitKind.ume.radius
        // 上端が線の少し下（近い）。
        let near = makeModel(fruits: [resting(0, .ume, x: 50, y: FruitField.Metrics.deadlineY - margin / 2 - r)])
        #expect(near.isNearLine)
        #expect(!near.isOverLine, "近いだけで、線は越えていない")
    }

    @Test("落としたばかりの盆栽（手から落ちる途中）では合図を立てない")
    func freshDropIsNotNear() {
        let model = FruitsModel(services: makeServices(), seed: 1)
        model.drop()
        model.tick(dt: 1.0 / 60)
        #expect(!model.isNearLine, "出現位置は線より上だが、猶予の内は数えない")
    }

    @Test("はじめからやり直すと合図は消える")
    func newGameClearsTheSignal() {
        let model = makeModel(fruits: [resting(0, .ume, x: 50, y: FruitField.Metrics.deadlineY - 2 - FruitKind.ume.radius)])
        #expect(model.isNearLine)
        model.newGame()
        #expect(!model.isNearLine)
    }
}

// MARK: - 撮影用の経路

@Suite("おじさんの盆栽の撮影用シナリオ（DEBUG）")
@MainActor
struct FruitsDebugScenarioTests {
    @Test("stack は遊べる盤、gameover は終局、kinmatsu は金の松のある盤を作る")
    func scenariosProduceTheirScreens() {
        let stack = FruitsModel(services: makeServices(), seed: 1)
        stack.applyDebugScenario("stack")
        #expect(stack.phase == .playing)
        #expect(stack.field.count >= 6)
        #expect(stack.field.isSettled)

        let over = FruitsModel(services: makeServices(), seed: 1)
        over.applyDebugScenario("gameover")
        #expect(over.phase == .gameOver)

        let kinmatsu = FruitsModel(services: makeServices(), seed: 1)
        kinmatsu.applyDebugScenario("kinmatsu")
        #expect(kinmatsu.field.fruits.contains { $0.kind == .kinmatsu })
        #expect(kinmatsu.hasMadeKinmatsu)
        #expect(kinmatsu.phase == .playing)

        let unknown = FruitsModel(services: makeServices(), seed: 1)
        unknown.applyDebugScenario("nonsense")
        #expect(unknown.field.count == 0)
    }
}

// MARK: - 壊れた中断データ（#1913）

@Suite("おじさんの盆栽の壊れた中断データ")
@MainActor
struct FruitsBrokenSnapshotTests {
    private func snapshot(drawCount: Int) -> FruitsSnapshot {
        FruitsSnapshot(
            fruits: [], cursorX: 50, score: 0, heldKind: .shinpaku, nextKind: .shinpaku,
            continueUsed: false, seed: 1, drawCount: drawCount, dropCount: 0, hasMadeKinmatsu: false
        )
    }

    @Test("抽選回数が桁外れの中断データは、固まらずに新規開始し中断データを消す")
    func hugeDrawCountIsDiscarded() throws {
        let store = MemorySnapshotStore()
        try store.save(snapshot(drawCount: 4_000_000_000), for: "fruits")
        let model = FruitsModel(services: makeServices(store: store), seed: 1)
        #expect(model.score == 0)
        #expect(store.load(FruitsSnapshot.self, for: "fruits") == nil)
    }

    @Test("上限ちょうどの抽選回数は復元する（対照）")
    func limitDrawCountIsKept() throws {
        let store = MemorySnapshotStore()
        try store.save(snapshot(drawCount: FruitsModel.maxRestorableDrawCount), for: "fruits")
        _ = FruitsModel(services: makeServices(store: store), seed: 1)
        #expect(store.load(FruitsSnapshot.self, for: "fruits") != nil)
    }
}
