import Core
import CoreEngine
import Observation

/// サイコロ役づくり（#1752）のゲーム状態。1 人用で、12 役ぜんぶに点を入れたら 1 局の決着。
///
/// 1 ターン = 最大 3 回振る → 役を 1 つ選んで点を入れる。キープした目は振り直さない。
/// 3 回振り切ったあと（ターンの終わり）に、広告 1 本で 1 ターンに 1 回（`maxAdRerolls`）、1 局に 5 回（`maxAdRerollsPerGame`）まで
/// もう 1 回振れる（#3257・#3345 で会長決裁 2026-11-05 により作り直し）。
/// 12 役を埋めたとき 0 点の役があれば、広告 1 本でそのうち 1 役を 1 局に 1 回だけやり直せる（#3257）。
///
/// **Game Center のリーダーボード・実績にはサイコロ役づくりを載せない**（広告で多く振った局と
/// 振っていない局を同じ順位表で競わせないため。今も載せていないし、今後も足さない・#3257）。
/// 端末内の記録（自己ベスト・通算）には載せてよい。
/// 役の判定と得点は `DiceComboLogic` に委譲し、ここは乱数・永続化・記録・解析だけを担う。
@MainActor
@Observable
public final class DiceComboModel {
    public static let gameID = "dicecombo"

    /// 1 ターンに広告で振り直せる回数の上限（通常の `DiceComboLogic.maxRolls` 回に加えて・#3257、1 回に変更・#3345）。
    public static let maxAdRerolls = 1
    /// 1 局に広告で振り直せる回数の上限（ターンごとの `maxAdRerolls` に重ねる・#3341、5 回に変更・#3345）。
    /// 短時間に広告を続けて頼んで在庫切れ・無効トラフィックの判定になるのを抑える。コンティニューは別枠。
    public static let maxAdRerollsPerGame = 5

    /// 大きな役として祝う点（#2804）。ファイブダイス（50）・ビッグストレート（30）・スモールストレート（25）。
    /// 通常の役（フルハウスの合計・チョイスなど）では超えにくい線に置く。
    public static let bigScoreThreshold = 25

    /// いまの出目。このターンでまだ振っていなければ空。
    public private(set) var dice: [Int] = []
    /// 各サイコロをキープしているか（`dice` と同じ並び）。
    public private(set) var held: [Bool] = []
    /// このターンに振った回数（0〜3）。
    public private(set) var rollsUsed = 0
    /// 埋めた役の点。
    public private(set) var scores: [DiceComboCategory: Int] = [:]
    /// 直前に点を入れた役（得点表で一瞬目立たせる）。永続化しない。
    public private(set) var lastFilled: DiceComboCategory?
    /// 12 役ぜんぶ埋まって決着したか。
    public private(set) var isFinished = false
    /// 直近の決着で確定した記録。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 振るたびに増える番号。View はサイコロの転がる動きの鍵にする。
    public private(set) var rollSerial = 0
    /// サイコロが転がっている演出の最中か（#2365）。出目は振った瞬間に `dice` へ確定済みで、
    /// これは「まだ見せていない」だけの印。永続化しない（中断から戻ったら止まった目を出す）。
    public private(set) var isRolling = false
    /// このターンに広告で振った回数（0〜`maxAdRerolls`）。通常の 3 回を振り切ったあとにだけ増え、役を選ぶと 0 に戻る。
    public private(set) var adRollsUsed = 0
    /// この局に広告で振った回数（0〜`maxAdRerollsPerGame`）。役を選んでも戻らず、新しいゲームで 0 に戻る（#3341）。
    public private(set) var gameAdRollsUsed = 0
    /// 12 役が埋まり、0 点の役があるので、広告で 1 役やり直すかを選ばせている間（#3257）。
    /// この間は `isFinished` だが記録・解析は確定しない。断る（`declineContinue`）・やり直す（`grantContinue`）・
    /// 新しいゲームのどれかで決まる。中断データには残るので、アプリを離れても提案から再開できる。
    public private(set) var isOfferingContinue = false
    /// この局でコンティニュー（広告での 1 役やり直し）を使ったか。1 局 1 回まで。
    public private(set) var continueUsed = false
    /// 何局目か。広告を出す前に控え、ロード中に始めた新しい局へ報酬を乗せないための印。永続化しない。
    public private(set) var gameSerial = 0
    /// 何ターン目の操作か（役を選ぶ・やり直す・新しいゲームで増える）。広告を出す前に控え、
    /// ロード中にターンが変わっていたら振り直しを乗せない。永続化しない。
    public private(set) var turnSerial = 0

    private let services: GameServices?
    private var generator: SplitMix64?
    /// 振ってから止まるまでの間。画面は `DiceComboMotion.rollInterval` を渡す。`.zero` なら即座に止まる。
    private let rollInterval: Duration
    /// 止まるのを待っている `Task`。新しいゲームで止める。
    private(set) var rollTask: Task<Void, Never>?

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    /// `seed` を渡すと出目を種から決める（テスト用。省略時はシステム乱数）。
    /// `rollInterval` はサイコロが転がる演出の長さ（#2365）。
    public init(services: GameServices? = nil, seed: UInt64? = nil, rollInterval: Duration = .zero) {
        self.services = services
        self.rollInterval = rollInterval
        generator = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(DiceComboSnapshot.self, for: Self.gameID),
           let restored = Self.restore(snap) {
            dice = restored.dice
            held = restored.held
            rollsUsed = restored.rollsUsed
            scores = restored.scores
            adRollsUsed = restored.adRollsUsed
            gameAdRollsUsed = restored.gameAdRollsUsed
            continueUsed = restored.continueUsed
            isOfferingContinue = restored.isOfferingContinue
            isFinished = restored.isOfferingContinue
        } else {
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            services?.gameDidStart(gameID: Self.gameID)
            persist()
        }
    }

    // MARK: - 読み取り

    /// いま何ターン目か（1〜12）。決着後は 12。
    public var turn: Int { min(scores.count + 1, DiceComboCategory.allCases.count) }

    /// このターンにあと何回振れるか。
    public var rollsRemaining: Int { DiceComboLogic.maxRolls - rollsUsed }

    /// 振れるか。転がっている最中は振れない（連打で二重に振らない・#2365）。
    public var canRoll: Bool { !isFinished && !isRolling && rollsUsed < DiceComboLogic.maxRolls }

    /// 通常の 3 回を振り切ったあと、広告で振り直せるか（#3257）。
    public var canAdReroll: Bool {
        !isFinished && !isRolling && rollsUsed == DiceComboLogic.maxRolls && adRerollsRemaining > 0
    }

    /// 広告で振り直せる残り。このターンの残りと、この局の残り（#3341）の少ない方（押せるかの判定に使う）。
    public var adRerollsRemaining: Int {
        min(Self.maxAdRerolls - adRollsUsed, Self.maxAdRerollsPerGame - gameAdRollsUsed)
    }

    /// この局で広告で振れる残り（0〜`maxAdRerollsPerGame`）。ターンの使用済みとは関係なく、画面の「この局 あと n 回」に出す（#3345）。
    public var gameAdRerollsRemaining: Int { max(0, Self.maxAdRerollsPerGame - gameAdRollsUsed) }

    /// この局の広告での振り直しを使い切ったか（#3341）。View は広告のボタンを「この局はここまで」にする。
    public var isAdRerollCapReached: Bool { gameAdRollsUsed >= Self.maxAdRerollsPerGame }

    /// このターンの広告での振り直しを使い切ったか（#3345）。局の残りがあっても押せず、View は「このターンは使用済み」と出す。
    public var isAdRerollTurnUsed: Bool { adRollsUsed >= Self.maxAdRerolls }

    /// キープを切り替えられるか（振ったあとで止まっていて、通常か広告でまだ振り直せるとき）。
    public var canHold: Bool {
        !isFinished && !isRolling && rollsUsed > 0
            && (rollsUsed < DiceComboLogic.maxRolls || adRerollsRemaining > 0)
    }

    /// その役にいま点を入れられるか。転がっている最中は止まった目をまだ見せていないので選べない。
    public func canChoose(_ category: DiceComboCategory) -> Bool {
        !isFinished && !isRolling && rollsUsed > 0 && scores[category] == nil
    }

    /// いまの出目をその役に入れたときの点（入れられないときは nil）。
    public func preview(_ category: DiceComboCategory) -> Int? {
        guard canChoose(category) else { return nil }
        return DiceComboLogic.score(category, dice: dice)
    }

    public var upperSubtotal: Int { DiceComboLogic.upperSubtotal(scores) }
    public var bonus: Int { DiceComboLogic.bonus(scores) }
    public var total: Int { DiceComboLogic.total(scores) }

    /// ヘッダーに常時出す「ベスト」（#2808・2048 の #2615 と同じ形）。保存済みの自己ベストと今の合計の大きい方。
    /// 記録は決着時にしか書かれないので、今の合計が超えた瞬間にここで追従させる。0 のときは nil（出さない）。
    var liveBestScore: Int? {
        let best = max(services?.playLog?.record(gameID: Self.gameID)?.bestPoints ?? 0, total)
        return best > 0 ? best : nil
    }

    /// 「新しいゲーム」で失われる進行があるか（#1011）。1 回も振っていない局と決着した局は捨てて構わない。
    public var hasProgressToLose: Bool { !isFinished && (rollsUsed > 0 || !scores.isEmpty) }

    // MARK: - 操作

    /// キープしていないサイコロを振る。1 ターン 3 回まで（そのあとは広告で `grantReroll`）。
    ///
    /// 出目はここで確定して保存する。`rollInterval` があれば `isRolling` を立て、その間だけ画面が転がる演出を出す。
    public func roll() {
        // 転がっている最中の連打は黙って捨てる（警告の触覚を鳴らすと、押した手応えと紛らわしい）。
        guard !isRolling else { return }
        guard canRoll else {
            services?.feedback.notify(.warning)
            return
        }
        performRoll(viaAd: false)
    }

    /// リワード広告の**視聴完了後**に 1 回振る（#3257）。キープは通常の振りと同じに効く。
    ///
    /// - Parameters:
    ///   - serial: 広告を出す前に控えた `gameSerial`。
    ///   - turn: 広告を出す前に控えた `turnSerial`。広告のロード中に局やターンが変わっていたら振らない。
    /// - Returns: 振れたか。false のとき View は「振り直せなかった」と伝える。
    @discardableResult
    public func grantReroll(forGame serial: Int, turn: Int) -> Bool {
        guard serial == gameSerial, turn == turnSerial, canAdReroll else { return false }
        adRollsUsed += 1
        gameAdRollsUsed += 1
        performRoll(viaAd: true)
        return true
    }

    private func performRoll(viaAd: Bool) {
        if rollsUsed == 0 { held = Array(repeating: false, count: DiceComboLogic.diceCount) }
        dice = rollDice()
        if !viaAd { rollsUsed += 1 }
        rollSerial += 1
        lastFilled = nil
        // 振った = 捨てたら途中離脱として数える局（冪等）。
        services?.gameDidProgress(gameID: Self.gameID)
        services?.feedback.impact(.medium)
        persist()
        runRoll()
    }

    private func runRoll() {
        guard rollInterval > .zero else { return }
        isRolling = true
        let interval = rollInterval
        rollTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            // 新しいゲームで止められたか、画面ごと捨てられた。
            guard !Task.isCancelled, let self, self.isRolling else { return }
            self.rollTask = nil
            self.settleRoll()
        }
    }

    /// サイコロが止まった。止まった瞬間の手応えを返す。出目は振った時点で決まっているので変えない。
    /// 待ちを飛ばしたいテストからも呼ぶ。
    func settleRoll() {
        guard isRolling else { return }
        rollTask?.cancel()
        rollTask = nil
        isRolling = false
        services?.feedback.impact(.light)
    }

    /// `index` のサイコロのキープを切り替える。
    public func toggleHold(_ index: Int) {
        guard canHold, held.indices.contains(index) else { return }
        held[index].toggle()
        services?.feedback.impact(.light)
        persist()
    }

    /// いまの出目を `category` に入れてターンを終える。条件を満たさない役でも 0 点で入れられる。
    public func choose(_ category: DiceComboCategory) {
        guard canChoose(category) else {
            services?.feedback.notify(.warning)
            return
        }
        let points = DiceComboLogic.score(category, dice: dice)
        scores[category] = points
        lastFilled = category
        if points >= Self.bigScoreThreshold { services?.feedback.notify(.milestone) }
        dice = []
        held = []
        rollsUsed = 0
        adRollsUsed = 0
        turnSerial += 1
        if DiceComboLogic.isComplete(scores) {
            finish()
        } else {
            if points < Self.bigScoreThreshold { services?.feedback.impact(.light) }
            persist()
        }
    }

    // MARK: - コンティニュー（#3257）

    /// 広告でやり直せる役（0 点で埋めた役）。提案中だけ空でない。
    public var continueCandidates: [DiceComboCategory] {
        guard isOfferingContinue else { return [] }
        return DiceComboCategory.allCases.filter { scores[$0] == 0 }
    }

    /// 広告を見て 1 役やり直す。**視聴が済んでから** View が呼ぶ。`category` の点を消し、その役だけを開けた
    /// 3 回振れるターンに戻す（キープも広告の振り直しも通常どおり使える）。点は入れ直して合計・ボーナスを出し直す。
    /// 1 局 1 回まで。
    ///
    /// - Parameter serial: 広告を出す前に控えた `gameSerial`。
    /// - Returns: やり直せたか。false のとき View は「やり直せなかった」と伝える。
    @discardableResult
    public func grantContinue(forGame serial: Int, category: DiceComboCategory) -> Bool {
        guard serial == gameSerial, isOfferingContinue, !continueUsed, scores[category] == 0 else { return false }
        scores[category] = nil
        isOfferingContinue = false
        isFinished = false
        continueUsed = true
        dice = []
        held = []
        rollsUsed = 0
        adRollsUsed = 0
        turnSerial += 1
        lastFilled = nil
        services?.feedback.notify(.success)
        persist()
        return true
    }

    /// コンティニューを断って、そのまま終える。記録・解析はここで確定する。
    public func declineContinue() {
        guard isOfferingContinue else { return }
        isOfferingContinue = false
        commitFinish()
    }

    /// 新しいゲーム。
    public func newGame() {
        // 提案中に始め直したら、断ったのと同じ（まだ確定していない決着をここで確定する）。
        if isOfferingContinue {
            isOfferingContinue = false
            commitFinish()
        }
        gameSerial += 1
        turnSerial += 1
        adRollsUsed = 0
        gameAdRollsUsed = 0
        continueUsed = false
        rollTask?.cancel()
        rollTask = nil
        isRolling = false
        dice = []
        held = []
        rollsUsed = 0
        scores = [:]
        lastFilled = nil
        isFinished = false
        recordResult = nil
        persist()
        services?.gameDidRestart(gameID: Self.gameID)
    }

    // MARK: - 内部

    private func finish() {
        isFinished = true
        // 0 点の役があり、まだ使っていなければ、記録を確定する前に広告でのやり直しを提案する。
        if !continueUsed, scores.values.contains(0) {
            isOfferingContinue = true
            persist()
            return
        }
        commitFinish()
    }

    /// 決着を確定する。決着 1 回につき `gameDidFinish` は 1 回だけ（提案中は呼ばない）。
    private func commitFinish() {
        services?.feedback.notify(.success)
        // 1 人用の得点ゲーム。12 役を埋め切ったら勝ちとして数え、合計点を自己ベストの対象にする（2048 と同じ）。
        // 評価リクエストの見せ場は自己ベストの更新だけにする（毎局が勝ちになるため）。
        // 決着 1 回につき `gameDidFinish` は 1 回だけ。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .win,
            score: GameScore(metric: .points, points: total),
            isReviewHighlight: false
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    private func rollDice() -> [Int] {
        if var seeded = generator {
            defer { generator = seeded }
            return DiceComboLogic.roll(dice, held: held, using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return DiceComboLogic.roll(dice, held: held, using: &system)
    }

    private func persist() {
        guard !isFinished || isOfferingContinue else { return }
        let snap = DiceComboSnapshot(
            dice: dice,
            held: held,
            rollsUsed: rollsUsed,
            scores: Dictionary(uniqueKeysWithValues: scores.map { ($0.key.rawValue, $0.value) }),
            adRollsUsed: adRollsUsed,
            continueUsed: continueUsed,
            gameAdRollsUsed: gameAdRollsUsed
        )
        services?.snapshots.saveReportingFailure(snap, for: Self.gameID)
    }

    /// 中断データを検証して局面に戻す。壊れたデータ・終わった局は nil（新規で始める）。
    /// 12 役が埋まっていても、コンティニューの提案中（0 点の役があり未使用）なら提案から再開する。
    static func restore(_ snap: DiceComboSnapshot) -> (
        dice: [Int], held: [Bool], rollsUsed: Int, scores: [DiceComboCategory: Int],
        adRollsUsed: Int, gameAdRollsUsed: Int, continueUsed: Bool, isOfferingContinue: Bool
    )? {
        guard (0...DiceComboLogic.maxRolls).contains(snap.rollsUsed) else { return nil }
        if snap.rollsUsed == 0 {
            guard snap.dice.isEmpty, snap.held.isEmpty else { return nil }
        } else {
            guard DiceComboLogic.isValidDice(snap.dice), snap.held.count == DiceComboLogic.diceCount else { return nil }
        }
        var scores: [DiceComboCategory: Int] = [:]
        for (key, value) in snap.scores {
            guard let category = DiceComboCategory(rawValue: key),
                  DiceComboLogic.isPossibleScore(value, for: category) else { return nil }
            scores[category] = value
        }
        // 後から足した鍵（optional）。鍵が無い・壊れた旧データは未使用として読む。
        let continueUsed = snap.continueUsed ?? false
        let offering = DiceComboLogic.isComplete(scores)
        if offering {
            guard !continueUsed, snap.rollsUsed == 0, scores.values.contains(0) else { return nil }
        }
        // 広告で振った回数は、通常の 3 回を振り切ったあとにだけ意味がある。
        let adRolls = snap.rollsUsed == DiceComboLogic.maxRolls
            ? min(max(0, snap.adRollsUsed ?? 0), maxAdRerolls) : 0
        // この局の合計は、このターンの回数より少なくならない（旧データ・壊れた値は下限に丸める）。
        let gameAdRolls = min(max(snap.gameAdRollsUsed ?? 0, adRolls), maxAdRerollsPerGame)
        return (snap.dice, snap.held, snap.rollsUsed, scores, adRolls, gameAdRolls, continueUsed, offering)
    }

    #if DEBUG
    /// 撮影・動作確認用（`-dicecomboScenario rolled|late|continue|result`）。局面を固定して絵を安定させる。
    public func applyDebugScenario(_ name: String) {
        let sample: [DiceComboCategory: Int] = [
            .ones: 3, .twos: 6, .threes: 9, .fours: 12, .fives: 15, .sixes: 18,
            .choice: 24, .fourDice: 0, .fullHouse: 23, .smallStraight: 15, .bigStraight: 30,
        ]
        switch name {
        case "rolled":
            scores = [.ones: 3, .sixes: 24, .choice: 22]
            dice = [4, 4, 2, 4, 6]
            held = [true, true, false, true, false]
            rollsUsed = 2
        case "late":
            scores = sample
            dice = [5, 5, 5, 5, 3]
            held = [true, true, true, true, false]
            rollsUsed = 2
        case "continue":
            // 0 点の役が残る終局（広告でのやり直しの提案）。
            scores = sample.merging([.fiveDice: 50]) { a, _ in a }
            dice = []
            held = []
            rollsUsed = 0
            isFinished = true
            isOfferingContinue = true
        case "result":
            scores = sample.merging([.fiveDice: 50]) { a, _ in a }
            dice = []
            held = []
            rollsUsed = 0
            isFinished = true
        default:
            return
        }
        rollSerial += 1
    }
    #endif
}
