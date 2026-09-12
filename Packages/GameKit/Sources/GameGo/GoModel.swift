import Foundation
import Observation
import Core

/// 対局の局面。
///
/// `playing` → （両者パス）→ `scoring` → （結果を承認）→ `finished`。
/// **`scoring` を挟むのが要点**で、簡易死活の判定が疑わしいときにここから対局へ戻れる
/// （#398「判定が疑わしい場合は対局続行に戻れる導線」）。この段階では成績を記録しない。
public enum GoPhase: Int, Codable, Equatable, Sendable {
    case playing = 0
    case scoring = 1
    case finished = 2
}

/// 着手が拒否された理由（#202 の規約に合わせ、判定は Model に集約する）。
public enum GoTapRejection: Equatable, Sendable {
    /// CPU の手番・思考中のタップ。
    case notYourTurn
    /// ルール上の禁じ手（盤外・すでに石がある・自殺手・コウ・スーパーコウ）。
    case illegal(GoIllegalMove)

    public var message: String {
        switch self {
        case .notYourTurn:       return "CPU の番です"
        case .illegal(let why):  return why.message
        }
    }
}

/// 終局の計算結果。
public struct GoEndgame: Equatable, Sendable {
    public let score: GoScore
    public let dead: Set<GoPoint>
    /// 簡易死活の判定が曖昧か（真なら「対局続行」を強く勧める）。
    public let isUncertain: Bool
}

struct GoSnapshot: Codable {
    let size: Int
    let handicap: Int
    let komi: Double
    let humanSide: Int
    let aiLevel: Int
    let startedAt: Date
    let moves: [GoMove]
    let undoUsed: Bool
    let phase: Int?
}

@MainActor
@Observable
public final class GoModel {
    public private(set) var state: GoState
    public private(set) var ruleset: GoRuleset
    public private(set) var humanSide: GoStone
    public private(set) var aiLevel: GoLevel
    public private(set) var phase: GoPhase
    /// 決着した勝者。投了・終局の確定で入る。
    public private(set) var winner: GoStone?
    public private(set) var isThinking: Bool
    public private(set) var lastMove: GoPoint?
    public private(set) var undoUsed: Bool
    /// 終局の計算結果（`scoring` / `finished` で有効）。
    public private(set) var endgame: GoEndgame?
    /// 終局の計算中。
    public private(set) var isScoringInProgress: Bool = false
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial: Int = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 拒否されたタップの通し番号（#202）。View はこの値の変化を震え演出のトリガーにする。
    public private(set) var rejectedTapCount: Int = 0
    /// 直近の拒否理由（#202）。着手が通ると消える（View が理由の 1 行を引っ込める契機・#664）。
    public private(set) var lastRejection: GoTapRejection?
    /// 「パス」の札を飛び出させる契機（#664）。**人間・CPU のどちらがパスしても**増える。
    ///
    /// パスは盤が一切変わらない唯一の着手で、震えも石も出ない。札と触覚だけが
    /// 「押せた」「CPU がパスした」の手がかりになるため、着手の通し番号とは別に持つ。
    public private(set) var passEventID: Int = 0
    /// 出したままの「パス」の札を畳む契機（#664。将棋 #519 と同じ理由）。
    ///
    /// 札は固定時間で引っ込むので、その途中に**盤の意味が変わる操作**（待った・新規対局・
    /// 投了・対局続行・終局の確定）が入ると、パスしていない盤の上に札が残る。
    /// `passEventID` はパスでしか増えないため、畳む側の契機はこちらで別に持つ。
    /// `passEventID` と同じく **0 には戻さない**（View は「値が変わったこと」で畳む）。
    public private(set) var passBannerDismissID: Int = 0

    private var moves: [GoMove]
    private let services: GameServices?
    /// 同じモジュールの View も参照する（`reward_ad` の送信に要る・#500）。
    let gameID = "go"
    private var startedAt: Date

    public var board: GoBoard { state.board }
    public var moveCount: Int { moves.count }
    public var gameOver: Bool { phase == .finished }
    /// CPU が着手すべき状態か。終局の確認中は動かさない（人間が結果を判断する段階のため）。
    public var isAITurn: Bool { phase == .playing && state.sideToMove != humanSide }
    /// 人間が取った石の数。
    public var capturedByHuman: Int { state.captures[humanSide.rawValue] }
    public var capturedByCPU: Int { state.captures[humanSide.opponent.rawValue] }

    /// View の `.task(id:)` に渡す CPU 起動トリガー（#140 と同じ理由で対局の通し番号と組にする）。
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: moves.count) }

    public init(services: GameServices? = nil) {
        self.services = services

        var ruleset = GoRuleset(size: GoBoardSize.nine.rawValue, handicap: 0)
        var humanSide = GoStone.black
        var aiLevel = GoLevel.normal
        var moves: [GoMove] = []
        var startedAt = Date()
        var undoUsed = false
        var phase = GoPhase.playing
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = true

        if let snap = services?.snapshots.load(GoSnapshot.self, for: "go") {
            ruleset = Self.restoredRuleset(size: snap.size, handicap: snap.handicap, komi: snap.komi)
            humanSide = GoStone(rawValue: snap.humanSide) ?? .black
            aiLevel = GoLevel(rawValue: snap.aiLevel) ?? .normal
            moves = snap.moves
            startedAt = snap.startedAt
            undoUsed = snap.undoUsed
            phase = GoPhase(rawValue: snap.phase ?? 0) ?? .playing
            isFreshStart = false
        }

        // 終局まで進んだ対局はスナップショットを消しているので、復元されるのは対局中か
        // 終局の確認中だけ。確認中で保存されていた場合は、もう一度計算し直す。
        let restoredPhase: GoPhase = phase == .finished ? .playing : phase

        self.ruleset = ruleset
        self.humanSide = humanSide
        self.aiLevel = aiLevel
        self.state = Self.replay(&moves, ruleset: ruleset, resumingAtEnd: restoredPhase == .playing)
        self.moves = moves
        self.startedAt = startedAt
        self.undoUsed = undoUsed
        self.isThinking = false
        self.lastMove = moves.last?.point
        self.phase = restoredPhase
        self.winner = nil
        self.endgame = nil
        self.recordResult = nil

        // **開始シートを出す局には `level` を載せない**（PR #572 の指摘）。この分岐と開始シートの
        // 表示条件はどちらも「中断データが無いこと」で、シートで強さを選ぶのはこの直後。
        // ここで既定値を送ると、選び直された強さぶんまで `normal` として数えてしまう。
        // 実際に選んだ強さは `newGame` の `gameDidRestart` が送る（シートを閉じてそのまま
        // 遊んだ局は `level` 無しになる = 選ばれていない事実をそのまま表す）。
        if isFreshStart { services?.gameDidStart(gameID: gameID) }
    }

    /// 中断データから対局設定を組み直す。**既知の値だけを受け入れる**（#520）。
    ///
    /// 路数と置き石は `GoBoard` の確保と置き石の座標計算にそのまま渡るため、範囲外の値が入ると
    /// 起動そのものが落ちる（路数 0 で置き石ありなら盤外への代入、負なら配列の確保で fatal）。
    /// ディスク破損や旧バージョンのデータで起動不能ループに入らないよう、
    /// 読めない値は既定（9 路・互先）に倒して対局を続けられる状態にする。
    static func restoredRuleset(size: Int, handicap: Int, komi: Double) -> GoRuleset {
        let boardSize = GoBoardSize(rawValue: size) ?? .nine
        let validHandicap = GoRuleset.handicapChoices.contains(handicap) ? handicap : 0
        var ruleset = GoRuleset(size: boardSize.rawValue, handicap: validHandicap)
        // コミは勝敗の計算に直に効くので、有限値のときだけ引き継ぐ（不正なら置き石に応じた既定のまま）。
        if komi.isFinite { ruleset.komi = komi }
        return ruleset
    }

    /// 手順を先頭から再生して局面を作る。**不正な手が現れたらそこで `moves` を切り詰める**（#520）。
    ///
    /// 連続パスのあとにまだ手が続く手順は、「対局続行」（#398 の導線）を通った証跡なので、
    /// 再生でもそのつど終局判定を解いてから続ける。解かないと `isTwoPassEnd` が立ったままになり、
    /// 以降の手が `.gameOver` として全部捨てられて盤面が壊れる（#426）。
    /// - Parameter resumingAtEnd: 再生し終えた局面から対局を続けるか（`phase == .playing`）。
    ///   「続行した直後に中断・待った」で手順の末尾が連続パスのまま残る場合に、ここで解く。
    private static func replay(
        _ moves: inout [GoMove],
        ruleset: GoRuleset,
        resumingAtEnd: Bool
    ) -> GoState {
        var state = GoState.initial(ruleset: ruleset)
        var applied = 0
        for move in moves {
            if state.isTwoPassEnd { state.resumePlay() }
            // 盤外・重複着手などが混ざった手順は、その手前で打ち切る。飛ばして続けると
            // 手番と手数が手順とずれ、待った（`moves.removeLast(2)`）が別の局面を作る。
            if state.play(move) != nil { break }
            applied += 1
        }
        if applied < moves.count { moves.removeLast(moves.count - applied) }
        if resumingAtEnd, state.isTwoPassEnd { state.resumePlay() }
        return state
    }

    // MARK: - 着手

    /// 盤面へのタップ。**盤外の座標を渡してよい**（範囲判定もここで行う）。
    public func tap(row: Int, col: Int) {
        guard phase == .playing else { return }
        guard !isAITurn, !isThinking else { return reject(.notYourTurn) }
        let move = GoMove.play(row: row, col: col)
        if let why = state.illegalReason(for: move) { return reject(.illegal(why)) }
        apply(move)
    }

    /// パス。2 回続くと終局の確認へ進む。
    public func pass() {
        guard phase == .playing, !isAITurn, !isThinking else { return }
        apply(.pass)
    }

    private func reject(_ reason: GoTapRejection) {
        lastRejection = reason
        rejectedTapCount += 1
        services?.feedback.notify(.warning)
    }

    /// 1 手進める共通経路（人間・CPU 双方）。
    /// テストは `@testable` からここを直接呼び、CPU の応手を指定して読みの時間を省く。
    func apply(_ move: GoMove) {
        let mover = state.sideToMove
        guard state.play(move) == nil else { return }
        moves.append(move)
        lastMove = move.point
        // 打てた時点で直前の拒否理由は用済み（五目の `place` と同じ畳み方・#664）。
        lastRejection = nil
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。
        services?.gameDidProgress(gameID: gameID)

        if move == .pass {
            // パスは盤が変わらないので、札（View 側）と触覚だけが手応えになる（#664）。
            // 札は CPU のパスでも出す — 相手がパスしたことが分からないと、こちらが
            // パスして終局へ進めてよい局面なのか判断できない。
            passEventID += 1
            // 2 回目のパスは直後に終局の合図（`notify(.warning)`）が鳴るので重ねない
            // （同じ着手で 2 度鳴ると合図が濁る・将棋 #377 と同じ判断）。
            if mover == humanSide, !state.isTwoPassEnd { services?.feedback.impact(.light) }
        } else if mover == humanSide {
            // 着手の手応えは自分が打ったときだけ。CPU の着手では鳴らさない。
            services?.feedback.impact(.medium)
        }

        if state.isTwoPassEnd {
            phase = .scoring
            endgame = nil
            services?.feedback.notify(.warning)
        }
        persist()
    }

    // MARK: - 終局

    /// 両者パスのあとの簡易死活と面積計算。重いので `Task.detached` に逃がす。
    public func evaluateEndgameIfNeeded() async {
        guard phase == .scoring, endgame == nil, !isScoringInProgress else { return }
        isScoringInProgress = true
        let serial = gameSerial
        defer { if gameSerial == serial { isScoringInProgress = false } }

        let snapshot = state
        let ruleset = ruleset
        let moveCount = moves.count
        // 種は手数から決める。同じ局面なら何度計算しても同じ結果になり、
        // 「もう一度パスしたら別の判定になった」という不可解な挙動を作らない。
        let seed = UInt64(moveCount) &* 0x9E37_79B9 &+ 0x60_0D_5EED
        let result = await Task.detached(priority: .userInitiated) {
            let analysis = GoDeadStones.analyze(state: snapshot, playouts: 600, seed: seed)
            let score = GoScoring.score(board: snapshot.board, removing: analysis.dead, ruleset: ruleset)
            return GoEndgame(score: score, dead: analysis.dead, isUncertain: !analysis.isConfident)
        }.value

        adoptEndgame(result, serial: serial, moveCount: moveCount)
    }

    /// 計算結果を採用してよいか判定してから反映する。
    ///
    /// 手数まで照合するのは、計算中に「対局へ戻す→着手→再び両者パス」と進むと
    /// `gameSerial` も `phase` も一致したまま**戻す前の盤面**の結果が届くため（#512）。
    func adoptEndgame(_ result: GoEndgame, serial: Int, moveCount: Int) {
        guard gameSerial == serial, phase == .scoring, moves.count == moveCount else { return }
        endgame = result
    }

    /// 終局の結果を確定する。ここではじめて成績として記録する。
    public func acceptEndgame() {
        guard phase == .scoring, let endgame else { return }
        passBannerDismissID += 1
        phase = .finished
        winner = endgame.score.winner
        finish(outcome: outcome(for: endgame.score.winner))
    }

    /// 終局判定から対局へ戻す（簡易死活の誤判定からの復帰）。
    public func resumePlay() {
        guard phase == .scoring else { return }
        state.resumePlay()
        phase = .playing
        endgame = nil
        // 連続パスを解いた盤なので、直前のパスの札は残さない（#664）。
        passBannerDismissID += 1
        persist()
    }

    public func resign() {
        guard phase != .finished else { return }
        passBannerDismissID += 1
        phase = .finished
        winner = humanSide.opponent
        endgame = nil
        finish(outcome: .loss)
    }

    private func outcome(for winner: GoStone?) -> GameOutcome {
        guard let winner else { return .draw }
        return winner == humanSide ? .win : .loss
    }

    private func finish(outcome: GameOutcome) {
        switch outcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        // 盤面が毎回変わる対 CPU 戦なので、記録は勝敗だけ（`GameCenterLeaderboard` の
        // 選定理由どおり順位表の対象外。App Store Connect への登録作業も増やさない）。
        recordResult = services?.gameDidFinish(
            gameID: gameID,
            outcome: outcome,
            score: GameScore(metric: .winLoss)
        )
        persist()
    }

    // MARK: - 待った

    /// 人間の手番で、直前の自分の手と CPU の応手をまとめて戻せるか。
    public var canUndo: Bool {
        guard phase == .playing, !isAITurn, !isThinking else { return false }
        return moves.count >= 2
    }

    /// 待った: 直前 2 手（人間 → CPU）を巻き戻し、人間が打ち直せる状態にする。
    public func undoLastExchange() {
        guard canUndo else { return }
        moves.removeLast(2)
        // 待ったで手順の末尾が「続行前の連続パス」に戻ることがあるので、対局中として再生する。
        state = Self.replay(&moves, ruleset: ruleset, resumingAtEnd: true)
        lastMove = moves.last?.point
        undoUsed = true
        endgame = nil
        lastRejection = nil
        // 戻した 2 手にパスが含まれることがあるので、札は残さない（#664）。
        passBannerDismissID += 1
        persist()
    }

    // MARK: - 新規対局

    public func newGame(humanSide: GoStone = .black, level: GoLevel = .normal, handicap: Int = 0) {
        var ruleset = GoRuleset(size: GoBoardSize.nine.rawValue, handicap: handicap)
        // 置き石は「黒（人間）がハンデをもらう」ための仕組み。人間が白を選んだときは
        // 置き石なしに倒す（白がハンデをもらう形は 9 路の慣行に無く、表示も破綻する）。
        if humanSide == .white { ruleset = GoRuleset(size: GoBoardSize.nine.rawValue, handicap: 0) }

        self.ruleset = ruleset
        self.humanSide = humanSide
        self.aiLevel = level
        self.moves = []
        self.state = GoState.initial(ruleset: ruleset)
        self.phase = .playing
        self.winner = nil
        self.endgame = nil
        self.lastMove = nil
        self.undoUsed = false
        self.recordResult = nil
        self.startedAt = Date()
        self.isThinking = false
        self.isScoringInProgress = false
        self.gameSerial += 1
        self.lastRejection = nil
        // 通し番号（`passEventID`）は 0 に戻さない。View は「値が変わったこと」で札を出すため、
        // 対局をまたいで単調に増やさないと巻き戻しが合図として拾われる（将棋 #519 と同じ）。
        // 前対局の札が出たままなら、新しい盤の上には残さない。
        self.passBannerDismissID += 1
        persist()
        services?.gameDidRestart(gameID: gameID, level: .aiStrength(aiLevel.rawValue))
    }

    // MARK: - CPU

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        // 計算中に新規対局が始まると、旧盤面で選んだ手が新しい盤面に着手されてしまう。
        // 計算開始時のトリガー（対局の通し番号 × 手数）を控え、完了時に一致する場合だけ着手する。
        let key = aiTurnKey
        let serial = gameSerial
        isThinking = true
        defer { if gameSerial == serial { isThinking = false } }

        let snapshot = state
        let ruleset = ruleset
        let level = aiLevel
        // 同じ局面でも対局・手数が違えば別の読みになるよう種をずらす。
        let seed = UInt64(gameSerial &* 1_000_003 &+ moves.count) &* 0x9E37_79B9 &+ 0xA50_B1BA
        let move = await Task.detached(priority: .userInitiated) {
            GoEngine(
                config: .level(level, seed: seed),
                ruleset: ruleset
            ).bestMove(state: snapshot)
        }.value

        guard aiTurnKey == key, isAITurn else { return }
        apply(move)
    }

    // MARK: - 永続化

    private func persist() {
        guard phase != .finished else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = GoSnapshot(
            size: ruleset.size,
            handicap: ruleset.handicap,
            komi: ruleset.komi,
            humanSide: humanSide.rawValue,
            aiLevel: aiLevel.rawValue,
            startedAt: startedAt,
            moves: moves,
            undoUsed: undoUsed,
            phase: phase.rawValue
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }

    #if DEBUG
    /// 撮影用（#398）: 中盤風の盤面を機械的に作る。人間の手番で止まるので CPU は動かない。
    public func applyPreviewMidgameForTesting() {
        guard moves.isEmpty, phase == .playing else { return }
        let preset: [(Int, Int)] = [
            (2, 2), (6, 6), (2, 6), (6, 2), (4, 4),
            (3, 5), (5, 3), (4, 6), (4, 2), (5, 5),
            (3, 3), (6, 4), (2, 4), (5, 6), (3, 6),
            (5, 2),
        ]
        for (row, col) in preset where state.isLegal(.play(row: row, col: col)) {
            apply(.play(row: row, col: col))
        }
    }

    /// 撮影用（#398）: 中盤の局面を作ってから両者パスし、終局の確認画面まで進める。
    /// 死活の × 印と「対局続行」の導線は両者パスに到達しないと出ないため、
    /// タップ操作なしでその画面を撮るにはここを通すしかない。
    public func applyPreviewScoringForTesting() async {
        applyPreviewMidgameForTesting()
        guard phase == .playing else { return }
        apply(.pass)
        apply(.pass)
        await evaluateEndgameIfNeeded()
    }
    #endif
}
