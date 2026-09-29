import Core

/// 送信された解析イベントをそのまま溜めるスパイ（#1150）。Firebase もネットワークも使わない。
///
/// 以前は 8 ファイルが同じ `SpyAnalyticsService` を private に持ち、取り出し口（`starts` / `ends` /
/// `rewards` …）だけが少しずつ違っていた。`AnalyticsEvent` にケースやパラメータを足すたびに
/// 全部を追う必要があったので 1 本に寄せた。**取り出し口の形は「並び」に揃えてある**——
/// 件数が欲しいところは `spy.starts.count` のように数える（同じ名前が場所によって
/// `Int` だったり配列だったりするのを避けるため）。
///
/// 取り出し口を持たない生のイベント列が要るテストは `events` をそのまま読む。
@MainActor
public final class SpyAnalyticsService: AnalyticsService {
    public private(set) var events: [AnalyticsEvent] = []

    public init() {}

    public func log(_ event: AnalyticsEvent) { events.append(event) }

    /// `game_start` の `game_id`。
    public var starts: [String] {
        events.compactMap { if case let .gameStart(gameID, _, _, _) = $0 { return gameID } else { return nil } }
    }

    /// `game_start` に載った難易度（#500）。載せていないゲームは nil。
    public var startLevels: [AnalyticsLevel?] {
        events.compactMap { if case let .gameStart(_, level, _, _) = $0 { return .some(level) } else { return nil } }
    }

    /// `game_end` の `game_id` / `result` / `duration_sec`。
    public var ends: [(gameID: String, result: AnalyticsResult, durationSec: Int)] {
        events.compactMap {
            if case let .gameEnd(gameID, result, durationSec, _, _, _) = $0 {
                return (gameID, result, durationSec)
            }
            return nil
        }
    }

    /// `game_end` の `result` だけ。
    public var outcomes: [AnalyticsResult] { ends.map(\.result) }

    /// 中断（`result == .quit`）で終わったプレイ。
    public var quits: [(gameID: String, durationSec: Int)] {
        ends.filter { $0.result == .quit }.map { ($0.gameID, $0.durationSec) }
    }

    /// 視聴完了したリワード広告（#500）。
    public var rewards: [(gameID: String, purpose: RewardPurpose)] {
        events.compactMap {
            if case let .rewardAd(gameID, purpose) = $0 { return (gameID, purpose) }
            return nil
        }
    }

    /// リワード広告の要求（#659）。視聴できたかどうかに関係なく出る。
    public var requests: [(gameID: String, purpose: RewardPurpose)] {
        events.compactMap {
            if case let .rewardRequest(gameID, purpose) = $0 { return (gameID, purpose) }
            return nil
        }
    }

    /// リワード広告の提示とその結末（#780）。受けた / 断った / 在庫が無かった、の別が入る。
    public var offers: [(gameID: String, purpose: RewardPurpose, result: RewardOfferResult)] {
        events.compactMap {
            if case let .rewardOffer(gameID, purpose, result) = $0 { return (gameID, purpose, result) }
            return nil
        }
    }

    public func starts(of gameID: String) -> Int { starts.filter { $0 == gameID }.count }
    public func ends(of gameID: String) -> Int { ends.filter { $0.gameID == gameID }.count }
    public func quits(of gameID: String) -> Int { quits.filter { $0.gameID == gameID }.count }
}
