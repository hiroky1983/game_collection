import Core
import Foundation
import HomerunCore
import Observation

/// 柵越えおじさん（#1348）の画面の状態。判定・台帳・蓄積の中身は `HomerunCore` にあり、ここは
/// 「打席前 → 投球 → 1 球の結果 → … → 10 球の結果」の進行と、指の操作をスイングの入力（`HomerunSwing`）に
/// 直すことだけを持つ。
///
/// **時計を持たない**。時刻はすべて引数で受け（`Date`）、「次に何時に起こしてほしいか」（`nextWake`）を返す。
/// 実際に待つのは View の `.task(id: step)` だけで、輪の大きさは View の `TimelineView` が時刻から描く
/// （スピード #1323・ぱっと暗算 #1321 と同じ考え方）。テストは時計を手で進めて実時間を待たずに検証できる。
///
/// 操作は片手（README §3.1）: 下 1/3 を押す → 押したままずらすとミートカーソルが**指の移動量だけ**動く
/// （トラックパッド式）→ 離した瞬間がスイング。
@MainActor
@Observable
public final class HomerunModel {
    public static let gameID = "homerun"

    public enum Phase: Equatable, Sendable {
        /// 打席前（今日の残り・きろく）。
        case idle
        /// 投球中（マシンが球を込める → 打ち出して輪が縮む）。
        case pitching
        /// 1 球の結果を見せている。
        case ballResult
        /// 10 球が終わった。
        case finished
    }

    /// 進行を止めている理由（1 つでも残っていれば止まったまま）。
    public struct Hold: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// バックグラウンド・非アクティブ。
        public static let inactive = Hold(rawValue: 1 << 0)
        /// 遊び方のシートの提示中。
        public static let sheet = Hold(rawValue: 1 << 1)
        /// 打席の一時停止ボタン（#1550）。
        public static let paused = Hold(rawValue: 1 << 2)
    }

    // MARK: 時間の定数（README §2）

    /// マシンが球を込める時間（的が出るまで・`HomerunMachineMotion`）。投手の頃の 0.8 秒から 0.4 秒延ばした（#1612 会長 QA:
    /// 「投げるアクションが無いのでテンポが早く、終わるのが早く感じる」）。結果から次の的までの間がそのぶん延び、
    /// 球が受け皿からレールを転がり落ちて車輪の間から出るまでを見せる。
    nonisolated public static let windup: TimeInterval = 1.2
    /// 輪が縮み切って的に重なるまで（判定窓の幾何が成り立つのは 1.2 秒だけ）。
    public static var travel: TimeInterval { TimeInterval(HomerunPitch.travelMilliseconds) / 1000 }
    /// 見送りの締め切り（輪が的に重なってからの秒数）。これを過ぎても離していなければ見送り（空振りと同じ扱い）で締める。
    /// 当たり窓（±110ms）より長く取り、3D の球が打点（輪が的に重なる瞬間 = 判定の 0・#1594 会長決裁 A）を過ぎて
    /// ミットに入る（約 0.14 秒後）までに離した振りは、遅すぎても「振るのが遅い」空振りとして判定する（会長 QA 2026-09-30:
    /// 以前は当たり窓の端 +110ms で締めていたため、振ったのに全部「見送り」になっていた）。
    /// 0.3 秒 = 球が打点に来てからの猶予を #1607 の 0.5 秒（当時は球が打点に来るのが輪の約 0.2 秒後）と同じに保った値。
    public static let lateLimit: TimeInterval = 0.3

    /// 1 球の結果を見せる時間。空振り・見逃しは短く、打球（ファウルを含む）は打球をカメラが追って止まるのを見せてから
    /// 結果のカードを出すぶん長く（`HomerunBallChase.resultDuration`・#1613）。
    public static func resultDuration(for kind: HomerunKind) -> TimeInterval {
        switch kind {
        case .miss: 1.2
        case .foul, .inPlay, .fenceHit, .homer: HomerunBallChase.resultDuration(for: kind)
        }
    }

    /// 1 球の結果を見せる時間（月まで飛んだ打球・#1680 は月の演出のぶん長い）。
    public static func resultDuration(for ball: HomerunBattedBall?) -> TimeInterval {
        if let moon = ball?.moon { return HomerunMoonShot.resultDuration(moon) }
        if ball?.isTankobu == true { return HomerunTankobuGag.resultDuration }
        // ジャストミート（#1775）は確定演出のヒットストップのぶん長い。
        let held = HomerunJustMeet.applies(to: ball) ? HomerunJustMeet.extraDuration : 0
        if ball?.isPoleHit == true { return HomerunBallChase.poleResultDuration + held }
        return resultDuration(for: ball?.kind ?? .miss) + held
    }

    // MARK: 状態

    public private(set) var phase: Phase = .idle
    public private(set) var ledger: HomerunLedger
    public private(set) var records: HomerunRecords
    public private(set) var challenge: HomerunChallenge?
    /// 直前の 1 球の結果。
    public private(set) var lastBall: HomerunBattedBall?
    /// 実際に振った回数（見送りは数えない）。打席の 3D の打者がスイングを再生する合図に使う（試作）。
    public private(set) var swingCount = 0
    /// 直前の 1 球で振ったか（見送りなら false）。
    public private(set) var didSwingLastBall = false
    /// 直前の 1 球の空振りの理由（早い / 遅い / 照準のずれ・#1594）。見送り・当たり・ファウルは nil。
    public private(set) var lastMissReason: HomerunMissReason?
    /// 直前の空振りで回って倒れて目を回す演出（#1681・`HomerunWhiffGag`）を出すか。振った空振りのときだけ立つ。
    public private(set) var showsWhiffGag = false
    /// いまの挑戦で振った空振りの回数（2 回目は必ず演出を出す）。
    private(set) var whiffCount = 0
    /// 直前の 1 球の結果に重ねる頭の記号（キラキラ目・怒りマーク・#1760）。結果の間だけ見せる（見せる局面の判断は `HomerunSwingPlan`）。
    private(set) var faceMark: HomerunFaceMark = .none
    /// 次の球の構えで見せる頭の記号（柵越えを打った次の 1 球だけ・#1762）。その球を打つ・見送ると入れ替わる。
    private(set) var waitingFaceMark: HomerunFaceMark = .none
    /// 振った空振りの連続回数（怒りマーク用）。当たり・ファウルで 0 に戻り、見送りは数えず戻しもしない。
    private(set) var whiffStreak = 0
    /// 演出を出すかを決める乱数（0 以上 1 未満）。テストは差し替えて固定する。
    var whiffGagRoll: () -> Double = { Double.random(in: 0..<1) }
    /// たんこぶの演出（#1793・`HomerunTankobu`）を出すかを決める乱数（0 以上 1 未満）。テストは差し替えて固定する。
    var tankobuRoll: () -> Double = { Double.random(in: 0..<1) }
    /// 10 球の結果で自己ベストを更新したか。
    public private(set) var isNewBest = false
    /// 回数が無いのに打席に立とうとした（使い切りシートを出す）。
    public var showsExhausted = false
    /// 方向メーター（打席の左上）を出すか。上級者向けに消せる（README §3.1）。消しても判定は変わらない。
    public var showsDirectionMeter: Bool {
        didSet { directionMeter.isEnabled = showsDirectionMeter }
    }
    /// 操作の説明（#1763）を見たか。初めて打席に入ったとき 1 球目の前に自動で出し、見たら端末に記録して 2 回目以降は
    /// 自動では出さない（一時停止の「操作の説明」からはいつでも開ける）。
    static let tutorialSeenKey = "homerun_tutorialSeen_v1"
    var hasSeenTutorial: Bool { defaults.bool(forKey: Self.tutorialSeenKey) }
    func markTutorialSeen() { defaults.set(true, forKey: Self.tutorialSeenKey) }
    /// 進行が変わるたびに進む。View は `.task(id:)` の鍵にする。
    public private(set) var step = 0
    public private(set) var holds: Hold = []
    /// 止め始めた時刻（結果の間に止めたら、戻ったときに `ballClock` をその間ぶんずらす）。
    private var heldSince: Date?

    /// 投球が始まる（マシンが球を打ち出し、的が出て輪が縮み始める）時刻。
    public private(set) var pitchStart: Date?

    /// 今（または直前）の 1 球の時刻の記録。3D の打者のスイングと球を判定の時刻に同期させるためのもの（試作・
    /// `HomerunSwingPlan`）。結果を見せている間も残す（`pitchStart` は結果に入ると消えるため）。判定には使わない。
    public struct BallClock: Equatable, Sendable {
        /// 的が出る（輪が縮み始める）時刻。
        public var pitchStart: Date
        /// この球のゾーン（0〜8）。
        public var zone: Int
        /// この球で押した時刻（押していなければ nil。的が出る前に離したら nil に戻る）。
        public var pressedAt: Date?
        /// 振った（離した）時刻。振っていなければ nil。
        public var releasedAt: Date?
        /// 振ったときのずれ（ms・負が早い）。
        public var timingOffset: Double?
        /// 的が出る前（マシンが込めている間）に離して素振りした時刻（最後の 1 回）。3D の打者がその場で振るためだけのもので、
        /// 判定・球数・台帳・記録には使わない（その球はそのまま投げられてくる）。
        public var practiceSwingAt: Date? = nil
        /// 輪が的に重なる時刻。
        public var arrival: Date { pitchStart.addingTimeInterval(TimeInterval(HomerunPitch.travelMilliseconds) / 1000) }

        /// 記録の時刻をすべて `seconds` 秒後ろへずらす（止めていた間を無かったことにする）。
        mutating func shift(by seconds: TimeInterval) {
            pitchStart = pitchStart.addingTimeInterval(seconds)
            pressedAt = pressedAt?.addingTimeInterval(seconds)
            releasedAt = releasedAt?.addingTimeInterval(seconds)
            practiceSwingAt = practiceSwingAt?.addingTimeInterval(seconds)
        }
    }
    public private(set) var ballClock: BallClock?
    /// 1 球の結果を閉じる時刻。
    public private(set) var resultUntil: Date?

    /// 押している指（nil なら押していない）。`anchor` は押した位置（投球が替わると今の指の位置に置き直す）。
    public private(set) var isHolding = false
    private var anchor: CGPoint = .zero
    private var finger: CGPoint = .zero
    /// ゾーン中心から見たミートカーソルの位置（pt・右と下が正）。投球ごとに中央（0, 0）へ戻る。
    public private(set) var cursor: CGPoint = .zero
    /// カーソルの基準（押した時点のカーソル位置）。
    private var cursorBase: CGPoint = .zero
    /// 押したまま見送りで締めた球の結果の間は、離しても素振りにしない（見送りのカードの裏で打者が振ると「振ったのに
    /// 見送り」に見える・会長 QA 2026-09-30）。次の球に入ったら外す（押したまま次の球で離せば通常の判定）。
    private var suppressesPracticeOnLift = false

    /// 照準の吸い寄せ（#1594 試作）。テストは `.off` で入力どおりの照準を確かめる。
    let aimAssist: HomerunAimAssist

    private let defaults: UserDefaults
    private let directionMeter: FeedbackPreference
    private let calendar: Calendar
    private let pitches: [HomerunPitch]
    /// 解析・記録・広告の窓口。nil（テスト・プレビュー）なら何も送らない。
    private let services: GameServices?
    /// このモデルで 1 回でも打席に立ったか（初回は `game_start`、以降は `game_end`（quit）を挟む始め直し）。
    private var hasCountedStart = false
    /// いまの挑戦で 1 球でも投げたか（`gameDidProgress` の冪等は解析側だが、呼ぶ回数を絞る）。
    private var hasProgressed = false

    public init(services: GameServices? = nil, defaults: UserDefaults = .standard, calendar: Calendar = .current,
                directionMeter: FeedbackPreference = .homerunDirectionMeter,
                pitches: [HomerunPitch] = HomerunPitch.standardSequence, aimAssist: HomerunAimAssist = .standard,
                now: Date = Date()) {
        self.services = services
        self.aimAssist = aimAssist
        self.defaults = defaults
        self.directionMeter = directionMeter
        showsDirectionMeter = directionMeter.isEnabled
        self.calendar = calendar
        self.pitches = pitches
        ledger = HomerunStorage.loadLedger(defaults)
        records = HomerunStorage.loadRecords(defaults)
        refreshDay(now: now)
    }

    // MARK: 派生値

    public var currentPitch: HomerunPitch? { challenge?.currentPitch }
    /// いま投げている（または直前に投げた）球の番号（1 始まり）。
    public var pitchNumber: Int {
        guard let challenge else { return 0 }
        return phase == .pitching ? challenge.results.count + 1 : challenge.results.count
    }
    public var isHeld: Bool { !holds.isEmpty }
    /// 打席の一時停止ボタンで止めているか（#1550。バックグラウンド・遊び方のシートでの停止とは別）。
    public var isPaused: Bool { holds.contains(.paused) }

    /// 輪が的に重なる時刻。
    public var arrival: Date? { pitchStart.map { $0.addingTimeInterval(Self.travel) } }

    /// いまの球のボール（的）の位置（ゾーン中心から・pt）。
    public var ballPoint: CGPoint {
        currentPitch.map { HomerunZoneGeometry.ballPoint(zone: $0.zone) } ?? .zero
    }

    /// 投球の開始からの経過（秒）。モーション中は負。投球中でなければ nil。
    public func pitchElapsed(at now: Date) -> TimeInterval? {
        guard phase == .pitching, let pitchStart else { return nil }
        return now.timeIntervalSince(pitchStart)
    }

    /// いま離したときのタイミングのずれ（ミリ秒・負が早い）。投球前・投球中でなければ nil。
    public func timingOffset(at now: Date) -> Double? {
        guard phase == .pitching, let arrival, let pitchStart, now >= pitchStart else { return nil }
        return now.timeIntervalSince(arrival) * 1000
    }

    /// いまのカーソルで振った場合のスイング入力（方向メーター用）。タイミングは当たり窓の端に丸める。
    public func previewSwing(at now: Date) -> HomerunSwing {
        let offset = timingOffset(at: now) ?? -HomerunTiming.hitWindow
        let clamped = min(max(offset, -HomerunTiming.hitWindow), HomerunTiming.hitWindow)
        return makeSwing(offset: clamped, cursor: aimCursor(at: now))
    }

    /// 照準（画面に描き、離した瞬間に判定へ渡す位置）。指で動かしたカーソルを、投球中に押している間だけ
    /// ボールの方へ吸い寄せる（`HomerunAimAssist`・#1594 試作）。的が出る前・押していない間はカーソルのまま。
    /// 時刻から決まる純粋な値（モデルは時計を読まない）。
    public func aimCursor(at now: Date) -> CGPoint {
        guard phase == .pitching, isHolding, let pitchStart, now > pitchStart else { return cursor }
        let since = max(pitchStart, ballClock?.pressedAt ?? pitchStart)
        let k = aimAssist.pull(heldFor: now.timeIntervalSince(since))
        let ball = ballPoint
        return CGPoint(x: cursor.x + (ball.x - cursor.x) * k, y: cursor.y + (ball.y - cursor.y) * k)
    }

    /// 次に起こしてほしい時刻（投球の締め切り・結果を閉じる時刻）。止まっているあいだは nil。
    public var nextWake: Date? {
        guard !isHeld, !awaitsAtBat else { return nil }
        switch phase {
        case .pitching: return arrival?.addingTimeInterval(Self.lateLimit)
        case .ballResult: return resultEnd
        case .idle, .finished: return nil
        }
    }

    // MARK: 打席前

    /// 日付が進んでいたら台帳を補充する（0:00 リセット）。画面に戻るたびに呼ぶ。
    public func refreshDay(now: Date) {
        let before = ledger
        ledger.roll(to: HomerunLedger.dayKey(for: now, calendar: calendar))
        if ledger != before { HomerunStorage.saveLedger(ledger, defaults) }
    }

    /// 打席に立つ。**この時点で挑戦回数を 1 減らす**（途中でやめても戻らない）。回数が無ければ使い切りシートを出す。
    /// 動作確認用の強制（回数無制限・月・ポール）は DEBUG ビルドだけで効く（`HomerunDebugOverrides`）。
    @discardableResult
    public func start(now: Date) -> Bool {
        guard phase == .idle || phase == .finished else { return false }
        refreshDay(now: now)
        let debug = HomerunDebugOverrides.current(defaults)
        // 消費した枠（#1685）。DEBUG の回数無制限（`-homerunUnlimited`）では台帳を使わないので載せない。
        var credit: AnalyticsCredit?
        if !debug.unlimited {
            credit = ledger.nextCredit.map(Self.analyticsCredit)
            guard ledger.consume() else {
                showsExhausted = true
                return false
            }
            HomerunStorage.saveLedger(ledger, defaults)
        }
        beginChallenge(now: now, withAd: false, credit: credit)
        return true
    }

    /// 回数を使い切ったあと、広告を見終えたところで呼ぶ（#1694）。**回数は増やさず**、その場で 1 挑戦を始めて打席へ入る
    /// （シートや確認は挟まない）。広告を出す前に控えた日付で照合する（見ている間に 0:00 をまたぐと台帳が作り直されて
    /// 無料分が戻っているので、前の日の広告では始めない）。回数が残っている・広告の上限（`HomerunLedger.adLimitPerDay`）
    /// に達している・打席前/結果でなければ始めず false（→ 「始められなかった」の知らせ）。
    @discardableResult
    public func startWithAd(forDay dayKey: Int, now: Date) -> Bool {
        guard phase == .idle || phase == .finished else { return false }
        refreshDay(now: now)
        guard ledger.dayKey == dayKey, ledger.consumeAdPlay() else { return false }
        HomerunStorage.saveLedger(ledger, defaults)
        beginChallenge(now: now, withAd: true, credit: .ad)
        return true
    }

    /// いまの挑戦を広告を見て始めたか（#1694。台帳の `adPlays` と合わせ、計測 #1685 で枠を見分ける材料）。
    public private(set) var startedWithAd = false

    private func beginChallenge(now: Date, withAd: Bool, credit: AnalyticsCredit?) {
        startedWithAd = withAd
        let debug = HomerunDebugOverrides.current(defaults)
        challenge = HomerunChallenge(pitches: pitches, forcesMoon: debug.forcesMoon, forcesPole: debug.forcesPole)
        awaitsAtBat = true
        lastBall = nil
        isNewBest = false
        hasProgressed = false
        whiffCount = 0
        faceMark = .none
        waitingFaceMark = .none
        beginPitch(now: now)
        if hasCountedStart {
            services?.gameDidRestart(gameID: Self.gameID, credit: credit)
        } else {
            services?.gameDidStart(gameID: Self.gameID, credit: credit)
            hasCountedStart = true
        }
        // 1 挑戦は途中から戻せない（中断データを持たない）。画面を離れたら休憩ではなく離脱として数える。
        services?.gameWillNotResume(gameID: Self.gameID)
    }

    private static func analyticsCredit(_ credit: HomerunLedger.Credit) -> AnalyticsCredit {
        switch credit {
        case .free:   return .free
        case .bonus:  return .bonus
        case .survey: return .survey
        case .ad:     return .ad
        }
    }

    /// 打席の画面（3D）が描き始めたときに View が 1 回呼ぶ。1 球目のマシンの込める動きを今から数え直す（打席の 3D を作って
    /// 描き始めるまで（シミュレータで約 1 秒）は画面が止まるので、打席に立った時刻から数えるとモーションが見えないまま的が
    /// 出ていた・画面の E2E で実測）。1 球目をまだ押していないときだけ（押した・振った後は数え直さない）。
    public func atBatDidAppear(now: Date) {
        guard awaitsAtBat else { return }
        awaitsAtBat = false
        guard phase == .pitching, !isHeld, !isHolding, challenge?.results.isEmpty == true,
              ballClock?.releasedAt == nil, ballClock?.practiceSwingAt == nil else { return }
        beginPitch(now: now)
    }

    /// 打席に立ってから、打席の画面が描き始める（`atBatDidAppear`）までの間。1 球目は数え直す前なので、ゾーンの読み上げに
    /// ボールの位置を出さない。
    public private(set) var awaitsAtBat = false

    /// アンケートに答えた報酬として今日の挑戦回数を 1 回増やす（1 日 1 回）。日付の照合は `startWithAd` と同じ。
    /// 回答は選択肢の番号だけを `survey_answer` で送り、端末には残さない（台帳の「済み」フラグだけ）。
    /// 未回答の設問がある・すでに済み・日付が変わっていれば増やさず false（回答も送らない）。
    @discardableResult
    public func submitSurvey(_ answers: [Int], forDay dayKey: Int, now: Date) -> Bool {
        refreshDay(now: now)
        guard HomerunSurvey.isValid(answers), ledger.dayKey == dayKey, ledger.grantSurvey() else { return false }
        HomerunStorage.saveLedger(ledger, defaults)
        services?.gameDidAnswerSurvey(gameID: Self.gameID, answers: answers)
        return true
    }

    /// 広告を出す前に控える「今日」の鍵（`startWithAd(forDay:now:)` へ渡す）。台帳の日付ではなく**時計から**
    /// 作る（画面を開いたまま 0:00 を過ぎても、日付の更新は前面へ戻るか打席に立つまで走らないため、
    /// 台帳の日付を控えると、日をまたいでいない広告まで「前の日」として弾いてしまう）。
    public func dayKey(at now: Date) -> Int { HomerunLedger.dayKey(for: now, calendar: calendar) }

    /// 10 球の結果から打席前へ戻る。
    public func backToLobby() {
        guard phase == .finished else { return }
        phase = .idle
        challenge = nil
        lastBall = nil
        ballClock = nil
        step += 1
    }

    // MARK: 指の操作（片手: 押す → ずらす → 離す）

    /// 押す。投球前・投球中どちらでもよい（押しただけでは振らない）。`point` は押せる帯の中の座標（pt）。
    /// `now` は押した時刻（照準の吸い寄せ `aimCursor` を押し始めから数えるのに使う）。
    public func press(at point: CGPoint, now: Date = .distantPast) {
        guard phase == .pitching || phase == .ballResult, !isHeld else { return }
        isHolding = true
        anchor = point
        finger = point
        cursorBase = cursor
        if phase == .pitching { ballClock?.pressedAt = now }
    }

    /// 押したままずらす。カーソルは指の移動量だけ動く（指 1pt = カーソル 1pt）。
    public func drag(to point: CGPoint) {
        guard isHolding else { return }
        finger = point
        cursor = HomerunZoneGeometry.clampCursor(CGPoint(
            x: cursorBase.x + point.x - anchor.x,
            y: cursorBase.y + point.y - anchor.y
        ))
    }

    /// 離す。投球中（的が出てから）なら、その瞬間がスイング（照準は吸い寄せた位置 `aimCursor`）。
    /// モーション中（的が出る前）・1 球の結果を見せている間に離したときは**素振り**: 打者はその場で振る
    /// （`BallClock.practiceSwingAt`）が判定には使わず、その球はそのまま投げられてくる（nil を返す）。
    /// 振り（本番・素振り）は始まったら最後まで振り切る（#1594）ので、振っている最中の素振りは受け付けない。
    @discardableResult
    public func release(at point: CGPoint, now: Date) -> HomerunBattedBall? {
        guard isHolding else { return nil }
        drag(to: point)
        guard let offset = timingOffset(at: now) else {
            isHolding = false
            ballClock?.pressedAt = nil
            if phase == .pitching || phase == .ballResult, !suppressesPracticeOnLift, !isSwinging(at: now) {
                ballClock?.practiceSwingAt = now
            }
            suppressesPracticeOnLift = false
            return nil
        }
        cursor = aimCursor(at: now)
        isHolding = false
        ballClock?.releasedAt = now
        ballClock?.timingOffset = offset
        return resolve(makeSwing(offset: offset, cursor: cursor), now: now)
    }

    /// 打者がいま振っている（本番か素振りの振り抜き〜フォロースルーの途中）か。本番の振りは離した瞬間に振り抜きの途中から
    /// 流すので、振り終わりは 20 コマ目を置いた時刻（`HomerunSwingContact.swingStart`）から数える。
    func isSwinging(at now: Date) -> Bool {
        // 空振りの演出（#1681）の間は、回って座りきるまで振っている扱い（素振りで演出を切らない）。
        if phase == .ballResult, showsWhiffGag || lastBall?.isTankobu == true { return true }
        guard let clock = ballClock else { return false }
        let column = HomerunSwingContact.column(zone: clock.zone)
        let spans: [(begin: Date, clipStart: Date)] = [
            clock.releasedAt.map {
                ($0, HomerunSwingContact.swingStart(release: $0, offsetMilliseconds: clock.timingOffset ?? 0, column: column))
            },
            clock.practiceSwingAt.map { ($0, $0) },
        ].compactMap { $0 }
        return spans.contains { now >= $0.begin && now < $0.clipStart.addingTimeInterval(HomerunBatterMotion.swingDuration) }
    }

    // MARK: 時間を進める

    /// 締め切りを過ぎていたら進める。View の `.task` が `nextWake` まで待ってから呼ぶ。
    public func advance(now: Date) {
        guard !isHeld else { return }
        switch phase {
        case .pitching:
            // 見送りの締め切りを過ぎても離していない = 見送り（空振りと同じ扱い・README §3.1）。押したままなら、この球の結果の
            // 間に離しても素振りにしない。
            if let arrival, now >= arrival.addingTimeInterval(Self.lateLimit) {
                suppressesPracticeOnLift = isHolding
                resolve(nil, now: now)
            }
        case .ballResult:
            guard let resultEnd, now >= resultEnd else { return }
            if challenge?.isFinished == true {
                finish()
            } else {
                beginPitch(now: now)
            }
        case .idle, .finished:
            break
        }
    }

    /// 進行を止める / 再開する。投球中に止めたら、戻ったときに**その球を投げ直す**（台帳は戻さない）。
    public func hold(_ reason: Hold, _ on: Bool, now: Date) {
        let wasHeld = isHeld
        if on { holds.insert(reason) } else { holds.remove(reason) }
        if !wasHeld, isHeld {
            isHolding = false
            if phase == .pitching {
                pitchStart = nil
                ballClock = nil
            }
            heldSince = now
            step += 1
        } else if wasHeld, !isHeld {
            switch phase {
            case .pitching: beginPitch(now: now)
            case .ballResult:
                // 止めていた間ぶん、この球の時刻の記録を後ろへずらす（打球を追うカメラ・打者の振りを止めた所から続ける・#1613。
                // ずらさないと、打球が飛んでいる間に止めて戻ったとき、追う様子を見せないまま止まった球とカードが出る）。
                if let heldSince, now > heldSince { ballClock?.shift(by: now.timeIntervalSince(heldSince)) }
                resultUntil = now.addingTimeInterval(Self.resultDuration(for: lastBall))
            case .idle, .finished: break
            }
            step += 1
        }
    }

    /// 打席の一時停止（#1550）。打席（投球中・1 球の結果）だけで効く。止め方・戻し方は `hold` と同じで、
    /// 投球中に止めたら再開でその球を投げ直す。
    public func pause(now: Date) {
        guard phase == .pitching || phase == .ballResult else { return }
        hold(.paused, true, now: now)
    }

    public func resume(now: Date) {
        hold(.paused, false, now: now)
    }

    /// 一時停止から挑戦を途中でやめて打席前へ戻る（#1550）。**回数は戻さない**（打席に立った時点で減っている）。
    /// 記録・`gameDidFinish` は付けない。解析の途中終了（`game_end` の quit）は、次に打席に立ったとき
    /// （`gameDidRestart`）か画面を離れたとき（`gameDidLeave`）に共通の経路で出る。
    public func quitChallenge() {
        guard isPaused, phase == .pitching || phase == .ballResult else { return }
        holds.remove(.paused)
        awaitsAtBat = false
        phase = .idle
        challenge = nil
        lastBall = nil
        ballClock = nil
        pitchStart = nil
        resultUntil = nil
        isHolding = false
        step += 1
    }

    // MARK: 空振りの演出（#1681）

    /// 1 球の結果を閉じる時刻。ふだんは `resultUntil` で、空振りの演出のときは座りきるまで（`HomerunWhiffGag.resultDuration`）
    /// 延ばす（演出の間は次の球を投げない）。
    public var resultEnd: Date? {
        resultUntil.map { showsWhiffGag ? $0.addingTimeInterval(Self.whiffGagExtension) : $0 }
    }

    /// 空振りの演出で結果の時間を延ばす分（秒）。
    static var whiffGagExtension: TimeInterval { HomerunWhiffGag.resultDuration - resultDuration(for: .miss) }

    /// 1 球を締めたときに、空振りの演出を出すか決める（振った空振りだけを数える。見送りは数えない）。
    private func decideWhiffGag(swung: Bool, ball: HomerunBattedBall?) {
        guard swung, ball?.kind == .miss else {
            showsWhiffGag = false
            return
        }
        whiffCount += 1
        showsWhiffGag = HomerunDebugOverrides.current(defaults).forcesWhiffGag
            || HomerunWhiffGag.shows(whiffNumber: whiffCount, roll: whiffGagRoll())
    }

    // MARK: 内部

    private func makeSwing(offset: Double, cursor: CGPoint) -> HomerunSwing {
        let ball = ballPoint
        return HomerunSwing(timingOffset: offset,
                            cursorDX: Double(cursor.x - ball.x),
                            cursorDY: Double(cursor.y - ball.y))
    }

    private func beginPitch(now: Date) {
        phase = .pitching
        suppressesPracticeOnLift = false
        pitchStart = now.addingTimeInterval(Self.windup)
        // 結果の間に始めた素振りがまだ振り終わっていなければ、次の球でも最後まで振る（途中で構えに戻さない）。
        let carriedPractice = ballClock?.practiceSwingAt.flatMap {
            now < $0.addingTimeInterval(HomerunBatterMotion.swingDuration) ? $0 : nil
        }
        // 押したまま次の球に入ったら、その押しは新しい球でも「押していた」扱い（時刻は前の球のまま）。
        ballClock = BallClock(pitchStart: pitchStart!, zone: currentPitch?.zone ?? 4,
                              pressedAt: isHolding ? (ballClock?.pressedAt ?? .distantPast) : nil,
                              practiceSwingAt: carriedPractice)
        resultUntil = nil
        // カーソルは投球ごとにゾーンの中央へ戻る。押したままなら今の指の位置を新しい基準にする。
        cursor = .zero
        cursorBase = .zero
        anchor = finger
        step += 1
    }

    @discardableResult
    private func resolve(_ swing: HomerunSwing?, now: Date) -> HomerunBattedBall? {
        guard phase == .pitching, var challenge else { return nil }
        awaitsAtBat = false
        didSwingLastBall = swing != nil
        lastMissReason = HomerunJudge.missReason(swing)
        if didSwingLastBall { swingCount += 1 }
        let ball = challenge.swing(swing, tankobuRoll: swing == nil ? 1 : tankobuRoll())
        self.challenge = challenge
        decideWhiffGag(swung: swing != nil, ball: ball)
        if !hasProgressed {
            hasProgressed = true
            services?.gameDidProgress(gameID: Self.gameID)
        }
        lastBall = ball
        // 月が割れた（#1680）: 残りの球は没収（挑戦は `isFinished`）・今日のプレイ回数を +2（当日分・上限なし）。
        if ball?.moon == .broken {
            refreshDay(now: now)
            ledger.grantMoonBonus()
            HomerunStorage.saveLedger(ledger, defaults)
        }
        phase = .ballResult
        pitchStart = nil
        // 10 球目を打った時点で蓄積に取り込む（結果を見せている 2 秒余りのあいだに画面を閉じても、
        // 打ち終えた挑戦は記録に残す）。
        if challenge.isFinished { record(challenge) }
        faceMark = .decide(ball: ball, swung: swing != nil, isNewBest: isNewBest)
        waitingFaceMark = .waiting(after: ball, swung: swing != nil, challengeFinished: challenge.isFinished)
        resultUntil = now.addingTimeInterval(Self.resultDuration(for: ball))
        step += 1
        return ball
    }

    private func record(_ challenge: HomerunChallenge) {
        let previousBest = records.bestTotalTenths
        records.record(challenge)
        isNewBest = records.bestTotalTenths > previousBest
        HomerunStorage.saveRecords(records, defaults)
        // 決着 1 回につき `gameDidFinish` は 1 回だけ。合計飛距離（m・切り捨て）を points に載せる。
        // 柵越えが 1 本でもあれば勝ち（評価リクエストの見せ場）、無ければ負け。
        services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: challenge.homerCount > 0 ? .win : .loss,
            score: GameScore(metric: .points, points: Int(challenge.totalDistance))
        )
    }

    private func finish() {
        phase = .finished
        resultUntil = nil
        isHolding = false
        step += 1
    }
}
