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
        /// 投球中（投手のモーション → 輪が縮む）。
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
    }

    // MARK: 時間の定数（README §2）

    /// 投手のモーション（的が出るまで）。
    public static let windup: TimeInterval = 0.8
    /// 輪が縮み切って的に重なるまで（判定窓の幾何が成り立つのは 1.2 秒だけ）。
    public static var travel: TimeInterval { TimeInterval(HomerunPitch.travelMilliseconds) / 1000 }
    /// 当たり窓の遅い側の端。これを過ぎても離していなければ見送り（空振りと同じ扱い）で締める。
    public static var lateLimit: TimeInterval { HomerunTiming.hitWindow / 1000 }

    /// 1 球の結果を見せる時間。空振り・見逃しは短く、打球は長く（外野カメラの代わりに落下点を描く）。
    public static func resultDuration(for kind: HomerunKind) -> TimeInterval {
        switch kind {
        case .miss: 1.2
        case .foul: 1.6
        case .inPlay, .fenceHit, .homer: 2.4
        }
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
    /// 10 球の結果で自己ベストを更新したか。
    public private(set) var isNewBest = false
    /// 回数が無いのに打席に立とうとした（使い切りシートを出す）。
    public var showsExhausted = false
    /// 方向メーター（打席の右上）を出すか。上級者向けに消せる（README §3.1）。消しても判定は変わらない。
    public var showsDirectionMeter: Bool {
        didSet { directionMeter.isEnabled = showsDirectionMeter }
    }
    /// 打席のカメラ（前 / 後ろ・#1506）。既定は前。選んだ方は保存して次回も使う。見た目だけで、判定・座標・解析は変えない
    /// （投球中に切り替えても同じ球のまま続く）。
    var atBatCamera: HomerunAtBatLayout.CameraPreset {
        didSet { defaults.set(atBatCamera.rawValue, forKey: Self.atBatCameraKey) }
    }
    static let atBatCameraKey = "homerun_atBatCamera_v1"
    /// 進行が変わるたびに進む。View は `.task(id:)` の鍵にする。
    public private(set) var step = 0
    public private(set) var holds: Hold = []

    /// 投球が始まる（投手のモーションが終わり、的が出て輪が縮み始める）時刻。
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
        /// 輪が的に重なる時刻。
        public var arrival: Date { pitchStart.addingTimeInterval(TimeInterval(HomerunPitch.travelMilliseconds) / 1000) }
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
                pitches: [HomerunPitch] = HomerunPitch.standardSequence, now: Date = Date()) {
        self.services = services
        self.defaults = defaults
        self.directionMeter = directionMeter
        showsDirectionMeter = directionMeter.isEnabled
        atBatCamera = defaults.string(forKey: Self.atBatCameraKey).flatMap(HomerunAtBatLayout.CameraPreset.init(rawValue:)) ?? .front
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
        return makeSwing(offset: clamped)
    }

    /// 次に起こしてほしい時刻（投球の締め切り・結果を閉じる時刻）。止まっているあいだは nil。
    public var nextWake: Date? {
        guard !isHeld else { return nil }
        switch phase {
        case .pitching: return arrival?.addingTimeInterval(Self.lateLimit)
        case .ballResult: return resultUntil
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
    @discardableResult
    public func start(now: Date) -> Bool {
        guard phase == .idle || phase == .finished else { return false }
        refreshDay(now: now)
        guard ledger.consume() else {
            showsExhausted = true
            return false
        }
        HomerunStorage.saveLedger(ledger, defaults)
        challenge = HomerunChallenge(pitches: pitches)
        lastBall = nil
        isNewBest = false
        hasProgressed = false
        beginPitch(now: now)
        if hasCountedStart {
            services?.gameDidRestart(gameID: Self.gameID)
        } else {
            services?.gameDidStart(gameID: Self.gameID)
            hasCountedStart = true
        }
        // 1 挑戦は途中から戻せない（中断データを持たない）。画面を離れたら休憩ではなく離脱として数える。
        services?.gameWillNotResume(gameID: Self.gameID)
        return true
    }

    /// 広告を見た報酬として今日の挑戦回数を 1 回増やす。**広告を出す前の日付で照合する**（見ている間に
    /// 0:00 をまたぐと台帳が作り直されており、前の日の広告で今日の回数が増えるのを防ぐ）。
    /// 上限（1 日 5 本）に達していれば増やさず false（→ 「適用できなかった」の知らせ）。
    @discardableResult
    public func grantAdChallenge(forDay dayKey: Int, now: Date) -> Bool {
        refreshDay(now: now)
        guard ledger.dayKey == dayKey, ledger.grantAd() else { return false }
        HomerunStorage.saveLedger(ledger, defaults)
        return true
    }

    /// アンケートに答えた報酬として今日の挑戦回数を 1 回増やす（1 日 1 回）。日付の照合は `grantAdChallenge` と同じ。
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

    /// 広告を出す前に控える「今日」の鍵（`grantAdChallenge(forDay:now:)` へ渡す）。台帳の日付ではなく**時計から**
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
    /// `now` は押した時刻（3D の打者が逆算して振り始める時刻に押していたかを見るだけ。判定には使わない）。
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

    /// 離す。投球中（的が出てから）なら、その瞬間がスイング。モーション中に離したときは振らない。
    @discardableResult
    public func release(at point: CGPoint, now: Date) -> HomerunBattedBall? {
        guard isHolding else { return nil }
        drag(to: point)
        isHolding = false
        guard let offset = timingOffset(at: now) else {
            ballClock?.pressedAt = nil
            return nil
        }
        ballClock?.releasedAt = now
        ballClock?.timingOffset = offset
        return resolve(makeSwing(offset: offset), now: now)
    }

    // MARK: 時間を進める

    /// 締め切りを過ぎていたら進める。View の `.task` が `nextWake` まで待ってから呼ぶ。
    public func advance(now: Date) {
        guard !isHeld else { return }
        switch phase {
        case .pitching:
            // 当たり窓の遅い側を過ぎても振っていない = 見送り（空振りと同じ扱い・README §3.1）。
            if let arrival, now >= arrival.addingTimeInterval(Self.lateLimit) {
                resolve(nil, now: now)
            }
        case .ballResult:
            guard let resultUntil, now >= resultUntil else { return }
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
            step += 1
        } else if wasHeld, !isHeld {
            switch phase {
            case .pitching: beginPitch(now: now)
            case .ballResult: resultUntil = now.addingTimeInterval(Self.resultDuration(for: lastBall?.kind ?? .miss))
            case .idle, .finished: break
            }
            step += 1
        }
    }

    // MARK: 内部

    private func makeSwing(offset: Double) -> HomerunSwing {
        let ball = ballPoint
        return HomerunSwing(timingOffset: offset,
                            cursorDX: Double(cursor.x - ball.x),
                            cursorDY: Double(cursor.y - ball.y))
    }

    private func beginPitch(now: Date) {
        phase = .pitching
        pitchStart = now.addingTimeInterval(Self.windup)
        // 押したまま次の球に入ったら、その押しは新しい球でも「押していた」扱い（時刻は前の球のまま = 振り始めより前）。
        ballClock = BallClock(pitchStart: pitchStart!, zone: currentPitch?.zone ?? 4,
                              pressedAt: isHolding ? (ballClock?.pressedAt ?? .distantPast) : nil)
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
        didSwingLastBall = swing != nil
        if didSwingLastBall { swingCount += 1 }
        let ball = challenge.swing(swing)
        self.challenge = challenge
        if !hasProgressed {
            hasProgressed = true
            services?.gameDidProgress(gameID: Self.gameID)
        }
        lastBall = ball
        phase = .ballResult
        pitchStart = nil
        // 10 球目を打った時点で蓄積に取り込む（結果を見せている 2 秒余りのあいだに画面を閉じても、
        // 打ち終えた挑戦は記録に残す）。
        if challenge.isFinished { record(challenge) }
        resultUntil = now.addingTimeInterval(Self.resultDuration(for: ball?.kind ?? .miss))
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
