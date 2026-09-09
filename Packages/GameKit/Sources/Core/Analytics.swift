import Foundation

/// 解析イベントのパラメータに載せられる値。**文字列と整数の2種だけ**を用意する。
/// 送信できる型をここで閉じることで、端末識別子やスコアの生値・自由入力の文字列を
/// そのまま流し込む経路を型の上で作れないようにする（#158 の受け入れ条件）。
public enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
}

/// `game_end` の `result`。決着の3値（`GameOutcome`）に**途中離脱**を足した4値（#500）。
///
/// `GameOutcome` 側に `quit` を足さないのは、あちらが自己ベスト（`PlayLog`）・Game Center・
/// 評価リクエストの入力でもあり、「勝ったか負けたか」以外の値が混ざると記録の意味が変わるため。
/// 離脱は解析にだけ存在する概念なので、解析側の型としてここで足す。
public enum AnalyticsResult: String, Equatable, Sendable, CaseIterable {
    /// 勝利・クリア。
    case win
    /// 敗北・投了・ゲームオーバー。
    case loss
    /// 引き分け・プッシュ。
    case draw
    /// 1手でも指した盤面を、決着しないまま捨てた（#500）。
    case quit

    public init(_ outcome: GameOutcome) {
        switch outcome {
        case .win:  self = .win
        case .loss: self = .loss
        case .draw: self = .draw
        }
    }
}

/// リワード広告を見た目的（#500）。`reward_ad` の `purpose` に載る値の全量。
///
/// 「どの救済が実際に使われているか」を面ごとに読むための分類で、
/// **ゲーム名は含めない**（それは `game_id` が持つ）。
public enum RewardPurpose: String, Equatable, Sendable, CaseIterable {
    /// 「戻す」「待った」の補充。
    case undo
    /// ゲームオーバーからそのまま続ける（盤面を保ったまま再開する）。
    case `continue`
    /// 失った残機・持ち駒などを回復して復活する。
    case revival
    /// ヒントの表示・補充。
    case hint
    /// ジョーカー（万能札）の付与。
    case joker
    /// チェックポイントからのやり直し。
    case checkpoint
    /// 手詰まりの盤面を、取り切れる配置へ並べ替える（麻雀ソリティア）。
    ///
    /// #500 が挙げた6分類のどれにも当たらないため足した7つ目（詳細は PR の「社長判断」）。
    /// 盤面は生きたままで、ゲームオーバーからの続行（`continue`）でも復活（`revival`）でもない。
    case shuffle
}

/// `game_start` の `level`。難易度・段階を**ゲーム横断で読める語彙**へ正規化する（#500）。
///
/// ゲームごとの呼び名（「やさしい」「初級」「弱」「レベル 0」…）をそのまま送ると、
/// GA4 では `game_id` ごとに別の文字列集合になり、横断で読めない。強さを選ぶゲームは
/// この4段階へ写し、面を進めるゲームは面番号を `stage-N` として送る。写像は各ゲーム側の
/// `analyticsLevel` に置く（Core は個々のゲームの型を知らない）。
/// 難易度・段階の概念を持たないゲームは `nil` で、`level` の鍵ごと送らない。
///
/// - Note: 送る値は必ず文字列。面番号を整数で送ると同じ `level` が数値と文字列の2型になり、
///   GA4 のカスタムディメンションとして読めなくなる。
public enum AnalyticsLevel: Equatable, Sendable {
    /// 入門・いちばんやさしい強さ。
    case beginner
    /// 標準の強さ。
    case normal
    /// 上級。
    case hard
    /// 最上級。段階が3つのゲームでは使わない。
    case expert
    /// 面・ステージの通し番号（1 始まり）。面を進めていくゲーム専用。
    ///
    /// 「何面で詰まるか」は難易度設計そのものなので、4段階へ丸めずに面番号のまま送る。
    case stage(Int)

    /// `level` パラメータに載る文字列。
    public var parameterValue: String {
        switch self {
        case .beginner: return "beginner"
        case .normal:   return "normal"
        case .hard:     return "hard"
        case .expert:   return "expert"
        // 面番号は 1 始まり。0 以下は表示・記録のどちらにも存在しないので 1 に丸める。
        case let .stage(number): return "stage-\(max(1, number))"
        }
    }

    /// 強さを表す4段階の全量。`stage` は面数がゲームごとに違うためここには入らない。
    public static let allStrengths: [AnalyticsLevel] = [.beginner, .normal, .hard, .expert]

    /// **0 始まり**の強さ設定（各ゲームの `aiLevel` など）を段階へ写す。
    /// 範囲外の値も型の上では作れるため、下は `beginner`・上は `expert` に倒して受け止める。
    public static func aiStrength(_ zeroBased: Int) -> AnalyticsLevel {
        switch zeroBased {
        case ..<1:  return .beginner
        case 1:     return .normal
        case 2:     return .hard
        default:    return .expert
        }
    }
}

/// 送信する解析イベント。**`game_start` / `game_end` / `reward_ad` の3種のみ**
/// （#158 の決裁範囲 + #500 の会長決裁 2026-09-08）。
///
/// パラメータは各ケースの関連値だけから組み立てるため、呼び出し側が任意のキーや値を
/// 追加する余地が無い。イベントを増やすにはこの enum にケースを足す = 意図的な変更が要る。
public enum AnalyticsEvent: Equatable, Sendable {
    /// 1プレイの開始。パラメータは `game_id` と、難易度を持つゲームだけ `level`。
    case gameStart(gameID: String, level: AnalyticsLevel? = nil)
    /// 1プレイの終わり。パラメータは `game_id` / `result` / `duration_sec` のみ。
    /// 決着（win / loss / draw）と途中離脱（quit）の両方がこのイベントで出る。
    case gameEnd(gameID: String, result: AnalyticsResult, durationSec: Int)
    /// リワード広告の**視聴完了**。パラメータは `game_id` / `purpose` のみ（#500）。
    case rewardAd(gameID: String, purpose: RewardPurpose)

    /// Firebase のイベント名。
    public var name: String {
        switch self {
        case .gameStart: return "game_start"
        case .gameEnd:   return "game_end"
        case .rewardAd:  return "reward_ad"
        }
    }

    /// 送信するパラメータ。キーも値もこの1か所でしか組み立てない。
    public var parameters: [String: AnalyticsValue] {
        switch self {
        case let .gameStart(gameID, level):
            var parameters: [String: AnalyticsValue] = ["game_id": .string(gameID)]
            // 難易度を持たないゲームでは鍵ごと送らない（GA4 で "none" のような
            // 実在しない段階を作らないため）。
            if let level { parameters["level"] = .string(level.parameterValue) }
            return parameters
        case let .gameEnd(gameID, result, durationSec):
            return [
                "game_id": .string(gameID),
                // `AnalyticsResult` は win / loss / draw / quit の4値に閉じた enum。
                // 「クリア」「ゲームオーバー」は各ゲームが決着判定の時点で正規化済み。
                "result": .string(result.rawValue),
                "duration_sec": .int(durationSec),
            ]
        case let .rewardAd(gameID, purpose):
            return [
                "game_id": .string(gameID),
                "purpose": .string(purpose.rawValue),
            ]
        }
    }
}

/// 解析送信の境界。**Firebase に依存しない**プロトコルで、実装は App 層が注入する
/// （`Packages` 配下に `import Firebase*` を持ち込まないための境界）。
public protocol AnalyticsService {
    @MainActor func log(_ event: AnalyticsEvent)
}

/// 何もしない実装。テスト・プレビュー用。
public struct NoopAnalyticsService: AnalyticsService {
    public init() {}
    @MainActor public func log(_ event: AnalyticsEvent) {}
}

/// 設定トグルがオフのときは下位サービスへ委譲しないラッパー。
/// `GatedFeedbackService` と同じ形で、オン / オフ判定をここに閉じ込める。
public struct GatedAnalyticsService: AnalyticsService {
    private let base: AnalyticsService
    private let isEnabled: @MainActor () -> Bool

    public init(base: AnalyticsService, isEnabled: @escaping @MainActor () -> Bool) {
        self.base = base
        self.isEnabled = isEnabled
    }

    @MainActor public func log(_ event: AnalyticsEvent) {
        guard isEnabled() else { return }
        base.log(event)
    }
}

/// 1プレイの開始・終わりを対応付けて `game_start` / `game_end` / `reward_ad` を送る係。
///
/// 各ゲームは「開始した」「1手指した」「やり直した」「終局した」を伝えるだけで、
/// **二重発火の抑制と経過秒の計測、離脱と休憩の切り分けはここ1か所**に閉じ込める。
/// ゲーム側に条件分岐を撒くと 20 本ぶん同じ間違いを繰り返すため。
///
/// - Note: 送信するのは `allowedGameIDs`（ハブに登録済みの ID）に含まれる gameID だけ。
///   知らない ID は捨てるので、任意の文字列が `game_id` として外へ出ることがない。
@MainActor
public final class GameAnalytics {
    /// そのゲームの1プレイの状態。**キーが無い = この画面でまだ1プレイも数えていない**。
    private enum PlayState {
        /// 進行中。`startedAt` は `duration_sec` の起点、`didProgress` は「1手でも指したか」。
        case inFlight(startedAt: Date, didProgress: Bool)
        /// 終局済み。`game_end` は送信済みなので、同じプレイで二度送らない。
        case finished
    }

    private let service: AnalyticsService
    private let allowedGameIDs: Set<String>
    /// 現在時刻。テストが実時間で待たずに経過秒を検証できるよう差し替え可能にする。
    private let now: () -> Date
    private var plays: [String: PlayState] = [:]

    public init(
        service: AnalyticsService,
        allowedGameIDs: Set<String>,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.allowedGameIDs = allowedGameIDs
        self.now = now
    }

    /// ゲーム画面を開いて新規にプレイが始まったときに呼ぶ。**冪等**。
    ///
    /// SwiftUI は親の再描画のたびに `State(initialValue:)` の式を評価するため、Model の
    /// `init` は1回の表示で何度も走りうる。ここで冪等にしておくことで、再描画・
    /// バックグラウンド復帰で `game_start` が増えない。
    public func startPlay(gameID: String, level: AnalyticsLevel? = nil) {
        guard allowedGameIDs.contains(gameID), plays[gameID] == nil else { return }
        beginPlay(gameID: gameID, level: level)
    }

    /// 「新しいゲーム」「次のラウンド」など、明示的に次のプレイを始めたときに呼ぶ。
    /// 前のプレイが終局していてもいなくても、**必ず1プレイとして数える**。
    ///
    /// - Note: 前のプレイが未決着で、かつ**1手でも指していた**場合は、始め直す前に
    ///   `game_end`（`result = quit`）を送る（#500）。1手も指していない配り直しは
    ///   捨てた盤面が無いので送らない（ソリティア #397 の敗北記録と同じ境目）。
    public func restartPlay(gameID: String, level: AnalyticsLevel? = nil) {
        guard allowedGameIDs.contains(gameID) else { return }
        endPlayAsQuitIfProgressed(gameID: gameID)
        beginPlay(gameID: gameID, level: level)
    }

    /// そのプレイで1手指した（盤面が動いた）ときに呼ぶ。**冪等**で、何度呼んでも状態は変わらない。
    ///
    /// この値だけが「捨てたら離脱として数える盤面か」を決める。呼ばないゲームでは
    /// 離脱が一切記録されないだけで、`game_start` / `game_end` の対応は従来どおり保たれる。
    public func recordProgress(gameID: String) {
        guard case let .inFlight(startedAt, didProgress) = plays[gameID], !didProgress else { return }
        plays[gameID] = .inFlight(startedAt: startedAt, didProgress: true)
    }

    /// 終局したときに呼ぶ。進行中のプレイが無いときは**何も送らない**
    /// （中断からの再開など、開始を数えていないプレイの終局。`duration_sec` の起点が
    /// 分からないため、対応の取れない `game_end` を作らない）。
    public func finishPlay(gameID: String, outcome: GameOutcome) {
        guard case let .inFlight(startedAt, _) = plays[gameID] else { return }
        plays[gameID] = .finished
        sendEnd(gameID: gameID, result: AnalyticsResult(outcome), startedAt: startedAt)
    }

    /// リワード広告を**視聴し終えた**ときに呼ぶ（#500）。
    /// 表示しただけ・途中で閉じた場合は呼ばない（`GameServices.showRewardedAd` が判定する）。
    public func recordRewardAd(gameID: String, purpose: RewardPurpose) {
        guard allowedGameIDs.contains(gameID) else { return }
        service.log(.rewardAd(gameID: gameID, purpose: purpose))
    }

    /// 解析送信の設定（オン / オフ）が切り替わったときに呼ぶ。**数え方の状態を丸ごと捨てる**。
    ///
    /// `GatedAnalyticsService` は個々のイベントの送信を止めるだけで、ここの数え方は止まらない。
    /// そのため設定をまたいだプレイは `game_start` と `game_end` の対応が崩れる（#212）:
    /// - オフ中に開始 → オンに戻して終局: 対応する `game_start` の無い `game_end` が出る
    /// - オン中に開始 → オフ → オンで終局: `duration_sec` にオフだった時間が混ざる
    ///
    /// 切り替えた時点で捨てることで、送るのは**設定がオンだった一続きの期間の中で
    /// 開始し終局したプレイだけ**になる。捨てたプレイの `game_end` は送られないが、
    /// 送信済みの `game_start` とだけ対応が付く（= 集計側では「始めたのに終わっていない」ぶんに入る）。
    public func discardPlayState() {
        plays.removeAll()
    }

    /// ゲーム画面から離れたときに呼ぶ（ハブが1か所で呼ぶ）。
    /// 次に同じゲームを開いたときを新しいプレイとして数え直せるようにする。
    ///
    /// - Parameter isResumable: 中断データが残っていて「続きから」で再開できるか。
    ///   `GameServices` が `SnapshotStore` に聞いて渡す。
    ///
    /// - Important: **再開できる進行中のプレイは残す**。遊びかけでハブに戻り「続きから」で再開して
    ///   終局するのはよくある流れで、ここで状態を捨てると（再開では `game_start` を数えないため）
    ///   `game_end` が送れず、実際は遊び切ったプレイが「始めたのに終わっていない」ぶんとして
    ///   数えられてしまう（PR #162 の CodeRabbit 指摘）。これが**休憩**で、離脱ではない（#500）。
    ///   中断データが残らない = 盤面を捨てたときだけ `quit` を送る。
    public func leaveGame(gameID: String, isResumable: Bool) {
        if case .finished = plays[gameID] {
            plays[gameID] = nil
            return
        }
        guard !isResumable else { return }
        endPlayAsQuitIfProgressed(gameID: gameID)
        // 送っても送らなくても、再開できない盤面はもう続きが無い。次に開いたら数え直す。
        plays[gameID] = nil
    }

    /// 未決着のまま捨てられたプレイに `game_end`（`quit`）を送る。1手も指していなければ何も送らない。
    private func endPlayAsQuitIfProgressed(gameID: String) {
        guard case let .inFlight(startedAt, didProgress) = plays[gameID], didProgress else { return }
        plays[gameID] = .finished
        sendEnd(gameID: gameID, result: .quit, startedAt: startedAt)
    }

    private func sendEnd(gameID: String, result: AnalyticsResult, startedAt: Date) {
        // 時計が巻き戻っても負の秒数を送らない。
        let seconds = max(0, Int(now().timeIntervalSince(startedAt)))
        service.log(.gameEnd(gameID: gameID, result: result, durationSec: seconds))
    }

    private func beginPlay(gameID: String, level: AnalyticsLevel?) {
        plays[gameID] = .inFlight(startedAt: now(), didProgress: false)
        service.log(.gameStart(gameID: gameID, level: level))
    }
}
