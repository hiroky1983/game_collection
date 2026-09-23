import Core
import CoreEngine
import Foundation
import Observation

/// ゲームの進行状態。
public enum FruitsPhase: Equatable, Sendable {
    /// 果物を落として遊んでいる。
    case playing
    /// 危険線を越えて終局した。コンティニュー（リワード広告）を選べる。
    case gameOver
}

/// 描画側（`FruitsScene`）が拾う演出の合図。Model は得点を確定させたあと、ここへ 1 件ずつ積む。
public struct FruitsEffect: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 合体して `FruitKind` ができた。
        case merge(FruitKind)
        /// メロンどうしが消えた。
        case vanish
    }

    public let serial: Int
    public let kind: Kind
    public let x: Double
    public let y: Double
}

/// くっつきフルーツの進行（#1319）。
///
/// 盤面そのもの（果物・落下・合体）は `FruitField` が持ち、ここは
/// **得点・落とす果物の抽選・終局・コンティニュー・中断復元・横断サービスへの通知**だけを担う。
/// SpriteKit には一切依存しないので、1 プレイ丸ごとをユニットテストで再生できる。
@MainActor
@Observable
public final class FruitsModel {
    /// 永続化キー・解析・リーダーボードで使う ID。`FruitsModule.id` との一致は `ModuleTests` が確かめる。
    public nonisolated static let gameID = "fruits"

    /// 落としてから次の果物が手に現れるまでの間（秒）。
    public static let dropCooldown: Double = 0.5
    /// 1 フレームで進める上限（秒）。バックグラウンドから戻った直後などの巨大な `dt` を刻む。
    public static let maxStep: Double = 1.0 / 30
    /// これより長いフレームは「描画ループを止めていたあいだ」とみなして進めない（ブロック崩し #522 と同じ）。
    public static let staleFrameThreshold: Double = 0.5
    /// 「止まった」と判断するまで、止まって見える状態が続く必要のある秒数。
    /// 跳ねた果物は頂点で一瞬速度が 0 になるので、1 フレームの判定だけで書き出すと空中の盤を保存してしまう。
    public static let settleConfirmation: Double = 0.25
    /// 描画側が拾い残しても溜め込まないよう、演出の合図は直近この件数だけ残す。
    static let effectHistoryLimit = 16

    public private(set) var field: FruitField
    public private(set) var score: Int
    public private(set) var phase: FruitsPhase
    /// 手に持っている果物。落とした直後、次が現れるまでは nil。
    public private(set) var heldKind: FruitKind?
    /// 「つぎ」に出す果物。手の果物を落とすと、間を置いてこれが手に来る。
    public private(set) var nextKind: FruitKind
    /// コンティニュー（リワード広告）を使ったか。1 プレイにつき 1 回まで。
    public private(set) var continueUsed: Bool
    /// 直近の終局で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// このプレイでメロンを作ったか。終局の勝敗（評価リクエスト・記録の勝ち数）に使う。
    public private(set) var hasMadeMelon: Bool
    /// このプレイで落とした数。
    public private(set) var dropCount: Int
    /// 危険線より上に果物があるか（描画の警告に使う）。
    ///
    /// `field` は毎フレーム変わるため、画面が `field.isOverLine` を直接読むと**毎フレーム再評価される**。
    /// ここで鏡を持ち、変わったときだけ代入する（ブロック崩しの `isPaddleWide` と同じ理由）。
    public private(set) var isOverLine = false
    /// プレイの通し番号。「はじめから」とコンティニューの照合に使う（#729）。
    public private(set) var gameSerial = 0
    /// 演出の合図（新しい順ではなく古い順・直近 `effectHistoryLimit` 件）。
    public private(set) var effects: [FruitsEffect] = []

    /// 次の果物が手に現れるまでの残り秒。0 なら持っている。
    private var cooldown: Double = 0
    /// 中断データを書き出したい変化（落とす・合体）が起きてから、まだ止まっていない。
    private var needsCheckpoint = false
    /// 果物が止まって見える状態が続いている秒数。
    private var settledTime: Double = 0
    private var seed: UInt64
    private var drawCount: Int
    private var generator: SplitMix64
    private var nextEffectSerial = 0
    private let services: GameServices?

    /// 本番の入口。中断データがあれば復元し、無ければ新しいプレイを始める。
    ///
    /// - Parameter seed: 落とす果物の抽選の種。nil なら毎回変わる。テストは固定して渡す。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services
        if let snap = services?.snapshots.load(FruitsSnapshot.self, for: Self.gameID) {
            var generator = SplitMix64(seed: snap.seed)
            var drawCount = 0
            // 同じ列の続きを引けるよう、保存された回数ぶん進める。
            for _ in 0..<max(0, snap.drawCount) {
                _ = generator.next()
                drawCount += 1
            }
            var held = snap.heldKind
            var next = snap.nextKind
            // 落とした直後（次が出るまでの間）に保存されていたら、待たずに次を手に持たせる。
            if held == nil {
                held = next
                next = Self.draw(&generator, count: &drawCount)
            }
            field = FruitField(fruits: snap.fruits, cursorX: snap.cursorX)
            score = snap.score
            phase = .playing
            continueUsed = snap.continueUsed
            hasMadeMelon = snap.hasMadeMelon
            dropCount = snap.dropCount
            self.seed = snap.seed
            self.drawCount = drawCount
            self.generator = generator
            heldKind = held
            nextKind = next
            isOverLine = field.isOverLine
            // 復元は新しいプレイではないので `game_start` は送らない。
        } else {
            let seed = seed ?? UInt64.random(in: 0...UInt64.max)
            var generator = SplitMix64(seed: seed)
            var drawCount = 0
            let held = Self.draw(&generator, count: &drawCount)
            let next = Self.draw(&generator, count: &drawCount)
            field = FruitField()
            score = 0
            phase = .playing
            continueUsed = false
            hasMadeMelon = false
            dropCount = 0
            self.seed = seed
            self.drawCount = drawCount
            self.generator = generator
            heldKind = held
            nextKind = next
            // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
            services?.gameDidStart(gameID: Self.gameID)
        }
    }

    // MARK: - 操作

    /// 落とせる状態か（遊んでいて、果物を手に持っている）。
    public var canDrop: Bool { phase == .playing && heldKind != nil }

    /// 手の果物を `x`（盤の抽象単位）へ動かす。次を待っているあいだも位置は覚えておく。
    public func moveCursor(to x: Double) {
        guard phase == .playing else { return }
        field.moveCursor(to: x, holding: heldKind ?? nextKind)
    }

    /// 手の果物を落とす。
    public func drop() {
        guard phase == .playing, let kind = heldKind else { return }
        field.drop(kind)
        heldKind = nil
        cooldown = Self.dropCooldown
        dropCount += 1
        // 落とした瞬間に 1 回、着地して塊が止まったときにもう 1 回書く（開き直したとき止まった盤が出る）。
        needsCheckpoint = true
        services?.feedback.impact(.light)
        // 果物を落とした = 捨てたら途中離脱として数える盤面（#500）。
        services?.gameDidProgress(gameID: Self.gameID)
        persist()
    }

    /// `dt` 秒ぶん進める。SpriteKit のゲームループから毎フレーム呼ばれる唯一の入口。
    public func tick(dt: Double) {
        guard phase == .playing, dt > 0 else { return }
        let step = min(dt, Self.maxStep)
        if cooldown > 0 {
            cooldown -= step
            if cooldown <= 0 {
                cooldown = 0
                heldKind = nextKind
                nextKind = draw()
                // 大きい果物へ持ち替えたとき、壁際にいれば半径ぶん内側へ寄せる。
                field.moveCursor(to: field.cursorX, holding: heldKind ?? nextKind)
            }
        }
        let events = field.step(dt: step)
        for event in events {
            guard phase == .playing else { break }
            handle(event)
        }
        if isOverLine != field.isOverLine { isOverLine = field.isOverLine }
        settledTime = field.isSettled ? settledTime + step : 0
        if needsCheckpoint, phase == .playing, cooldown == 0, settledTime >= Self.settleConfirmation {
            needsCheckpoint = false
            persist()
        }
    }

    /// 「はじめから」で失われる進行があるか（#515）。終局後はもう失うものが無い。
    public var hasProgressToLose: Bool { phase == .playing && dropCount > 0 }

    /// はじめから遊び直す。
    public func newGame() {
        gameSerial += 1
        field = FruitField()
        score = 0
        phase = .playing
        continueUsed = false
        hasMadeMelon = false
        dropCount = 0
        recordResult = nil
        effects = []
        cooldown = 0
        needsCheckpoint = false
        settledTime = 0
        isOverLine = false
        seed = UInt64.random(in: 0...UInt64.max)
        generator = SplitMix64(seed: seed)
        drawCount = 0
        heldKind = draw()
        nextKind = draw()
        services?.snapshots.clear(for: Self.gameID)
        services?.gameDidRestart(gameID: Self.gameID)
    }

    /// リワード広告の視聴後にコンティニューする。小さい果物と危険線より上の果物が消え、得点はそのまま。
    ///
    /// - Parameter serial: 広告を出す前に控えた `gameSerial`。**広告のロード〜視聴の間に「はじめから」で
    ///   プレイが入れ替わっていたら適用しない**（#729。ブロック崩しの `continueAfterAd(forRun:)` と同じ契約）。
    @discardableResult
    public func continueAfterAd(forGame serial: Int) -> Bool {
        guard phase == .gameOver, !continueUsed, serial == gameSerial else { return false }
        // 同じ 1 プレイの続きなので、直前に記録した「負け」は無かったことにする。
        // メロンを作っていた回は勝ちとして記録されているので取り消すものが無い。
        if !hasMadeMelon {
            services?.playLog?.cancelLoss(gameID: Self.gameID)
        }
        recordResult = nil
        continueUsed = true
        field.clearForContinue()
        phase = .playing
        isOverLine = false
        cooldown = 0
        if heldKind == nil {
            heldKind = nextKind
            nextKind = draw()
        }
        needsCheckpoint = true
        persist()
        // `game_end` は送信済みなので、続きは次の 1 プレイとして数え直す（#158）。
        services?.gameDidRestart(gameID: Self.gameID)
        return true
    }

    // MARK: - 内部

    /// 落とす果物を 1 つ引く。種と回数だけで列が決まる（復元時に同じ列の続きを引くため）。
    private static func draw(_ generator: inout SplitMix64, count: inout Int) -> FruitKind {
        count += 1
        let index = Int.random(in: 0..<FruitKind.dropPool.count, using: &generator)
        return FruitKind.dropPool[index]
    }

    private func draw() -> FruitKind {
        Self.draw(&generator, count: &drawCount)
    }

    private func handle(_ event: FruitEvent) {
        switch event {
        case .touched:
            services?.feedback.impact(.light)
        case let .merged(_, into, x, y, _):
            score += into.points
            needsCheckpoint = true
            appendEffect(.merge(into), x: x, y: y)
            if into == .melon {
                hasMadeMelon = true
                services?.feedback.notify(.success)
            } else {
                services?.feedback.impact(into >= .kiwi ? .medium : .light)
            }
        case let .vanished(x, y):
            score += FruitKind.melonVanishPoints
            needsCheckpoint = true
            appendEffect(.vanish, x: x, y: y)
            services?.feedback.notify(.milestone)
        case .gameOver:
            finish()
        }
    }

    private func appendEffect(_ kind: FruitsEffect.Kind, x: Double, y: Double) {
        effects.append(FruitsEffect(serial: nextEffectSerial, kind: kind, x: x, y: y))
        nextEffectSerial += 1
        if effects.count > Self.effectHistoryLimit {
            effects.removeFirst(effects.count - Self.effectHistoryLimit)
        }
    }

    /// 終局で記録する成績。スコアが主役で、コンティニューを使った回は世界の順位表へ送らない
    /// （#406 と同じ考え方。手元の自己ベストには残す）。
    var finishingScore: GameScore {
        GameScore(metric: .points, points: score, isLeaderboardEligible: !continueUsed)
    }

    private func finish() {
        phase = .gameOver
        heldKind = nil
        cooldown = 0
        isOverLine = field.isOverLine
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            // メロンを作れたプレイは勝ち（評価リクエストの入口・記録の勝ち数）。作れずに埋まったら負け。
            outcome: hasMadeMelon ? .win : .loss,
            score: finishingScore
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    /// 区切りの状態だけを保存する。呼ぶのは落とした直後と、そのあと塊が止まったとき。
    private func persist() {
        guard phase == .playing else { return }
        let snapshot = FruitsSnapshot(
            fruits: field.fruits,
            cursorX: field.cursorX,
            score: score,
            heldKind: heldKind,
            nextKind: nextKind,
            continueUsed: continueUsed,
            seed: seed,
            drawCount: drawCount,
            dropCount: dropCount,
            hasMadeMelon: hasMadeMelon
        )
        try? services?.snapshots.save(snapshot, for: Self.gameID)
    }

    #if DEBUG
    /// 撮影・動作確認用に狙った画面まで進める（起動引数 `-simulateFruits <名前>`）。
    ///
    /// 積み上がった盤・終局・メロンの画は、実機では**指で遊ばないと**出せない。シミュレータには
    /// 自動タップの手段が無いため、ブロック崩しの `-simulateBlocks` と同じ形で起動引数から状態を作る。
    /// DEBUG ビルド限定で、製品には入らない。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "stack":
            // 12 個ほど落として落ち着いた盤。合体も数回起きる。
            dropSequenceForDebug(count: 14)
        case "melon":
            // メロンを含む大きい果物の塊。
            for (kind, x) in [(FruitKind.melon, 24.0), (.pineapple, 66), (.apple, 86), (.peach, 50)] {
                field.placeFruitForTesting(kind, x: x, y: kind.radius + 40)
            }
            hasMadeMelon = true
            score = 480
            settleForDebug(seconds: 3)
        case "gameover":
            var guardCount = 0
            while phase == .playing, guardCount < 80 {
                guardCount += 1
                let kind: FruitKind = [.grape, .pineapple, .apple, .peach][guardCount % 4]
                field.placeFruitForTesting(kind, x: 30 + Double(guardCount % 3) * 20, y: FruitField.Metrics.spawnY)
                settleForDebug(seconds: 0.8)
            }
        default:
            break
        }
    }

    private func dropSequenceForDebug(count: Int) {
        for index in 0..<count {
            moveCursor(to: 18 + Double((index * 7) % 5) * 16)
            settleForDebug(seconds: Self.dropCooldown + 0.05)
            drop()
        }
        settleForDebug(seconds: 3)
    }

    private func settleForDebug(seconds: Double) {
        var elapsed = 0.0
        while elapsed < seconds {
            tick(dt: 1.0 / 60)
            elapsed += 1.0 / 60
        }
    }
    #endif
}
