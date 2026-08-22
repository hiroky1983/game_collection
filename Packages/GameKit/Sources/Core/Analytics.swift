import Foundation

/// 解析イベントのパラメータに載せられる値。**文字列と整数の2種だけ**を用意する。
/// 送信できる型をここで閉じることで、端末識別子やスコアの生値・自由入力の文字列を
/// そのまま流し込む経路を型の上で作れないようにする（#158 の受け入れ条件）。
public enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
}

/// 送信する解析イベント。**`game_start` と `game_end` の2種のみ**（#158 の決裁範囲）。
///
/// パラメータは各ケースの関連値だけから組み立てるため、呼び出し側が任意のキーや値を
/// 追加する余地が無い。イベントを増やすにはこの enum にケースを足す = 意図的な変更が要る。
public enum AnalyticsEvent: Equatable, Sendable {
    /// 1プレイの開始。パラメータは `game_id` のみ。
    case gameStart(gameID: String)
    /// 1プレイの終局。パラメータは `game_id` / `result` / `duration_sec` のみ。
    case gameEnd(gameID: String, outcome: GameOutcome, durationSec: Int)

    /// Firebase のイベント名。
    public var name: String {
        switch self {
        case .gameStart: return "game_start"
        case .gameEnd:   return "game_end"
        }
    }

    /// 送信するパラメータ。キーも値もこの1か所でしか組み立てない。
    public var parameters: [String: AnalyticsValue] {
        switch self {
        case let .gameStart(gameID):
            return ["game_id": .string(gameID)]
        case let .gameEnd(gameID, outcome, durationSec):
            return [
                "game_id": .string(gameID),
                // `GameOutcome` は win / loss / draw の3値に閉じた enum。
                // 「クリア」「ゲームオーバー」は各ゲームが決着判定の時点でこの3値へ正規化済み。
                "result": .string(outcome.rawValue),
                "duration_sec": .int(durationSec),
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

/// 1プレイの開始・終局を対応付けて `game_start` / `game_end` を送る係。
///
/// 各ゲームは「開始した」「やり直した」「終局した」を伝えるだけで、
/// **二重発火の抑制と経過秒の計測はここ1か所**に閉じ込める。ゲーム側に条件分岐を撒くと
/// 10本ぶん同じ間違いを繰り返すため。
///
/// - Note: 送信するのは `allowedGameIDs`（ハブに登録済みの ID）に含まれる gameID だけ。
///   知らない ID は捨てるので、任意の文字列が `game_id` として外へ出ることがない。
@MainActor
public final class GameAnalytics {
    /// そのゲームの1プレイの状態。**キーが無い = この画面でまだ1プレイも数えていない**。
    private enum PlayState {
        /// 進行中。値は開始時刻（`duration_sec` の起点）。
        case inFlight(startedAt: Date)
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
    public func startPlay(gameID: String) {
        guard allowedGameIDs.contains(gameID), plays[gameID] == nil else { return }
        beginPlay(gameID: gameID)
    }

    /// 「新しいゲーム」「次のラウンド」など、明示的に次のプレイを始めたときに呼ぶ。
    /// 前のプレイが終局していてもいなくても、**必ず1プレイとして数える**。
    ///
    /// - Note: 終局しないまま始め直した前のプレイには `game_end` を送らない。
    ///   離脱したプレイは「`game_start` があって `game_end` が無い」ぶんとして
    ///   集計側で差分から求める（画面離脱を拾う発火点を増やさないため）。
    public func restartPlay(gameID: String) {
        guard allowedGameIDs.contains(gameID) else { return }
        beginPlay(gameID: gameID)
    }

    /// 終局したときに呼ぶ。進行中のプレイが無いときは**何も送らない**
    /// （中断からの再開など、開始を数えていないプレイの終局。`duration_sec` の起点が
    /// 分からないため、対応の取れない `game_end` を作らない）。
    public func finishPlay(gameID: String, outcome: GameOutcome) {
        guard case let .inFlight(startedAt) = plays[gameID] else { return }
        plays[gameID] = .finished
        // 時計が巻き戻っても負の秒数を送らない。
        let seconds = max(0, Int(now().timeIntervalSince(startedAt)))
        service.log(.gameEnd(gameID: gameID, outcome: outcome, durationSec: seconds))
    }

    /// ゲーム画面から離れたときに呼ぶ（ハブが1か所で呼ぶ）。
    /// 次に同じゲームを開いたときを新しいプレイとして数え直せるようにする。
    ///
    /// - Important: **進行中のプレイは残す**。遊びかけでハブに戻り「続きから」で再開して終局する
    ///   のはよくある流れで、ここで状態を捨てると（再開では `game_start` を数えないため）
    ///   `game_end` が送れず、実際は遊び切ったプレイが「始めたのに終わっていない」ぶんとして
    ///   数えられてしまう（PR #162 の CodeRabbit 指摘）。捨てるのは終局済みのプレイだけ。
    public func leaveGame(gameID: String) {
        guard case .finished = plays[gameID] else { return }
        plays[gameID] = nil
    }

    private func beginPlay(gameID: String) {
        plays[gameID] = .inFlight(startedAt: now())
        service.log(.gameStart(gameID: gameID))
    }
}
