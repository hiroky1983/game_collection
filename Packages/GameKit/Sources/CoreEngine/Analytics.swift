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

/// `reward_offer` の `result`。リワード広告を**提示した 1 回がどう終わったか**（#780）。
///
/// 提示 = 広告を見るかどうかを選ばせる画面（確認アラート・コンティニューの幕・リザルトの復活ボタン）が
/// 出たこと。常に出ている操作ボタン（ナンプレのヒント）は提示の瞬間が無いので数えない。
public enum RewardOfferResult: String, Equatable, Sendable, CaseIterable {
    /// 広告ボタンを押し、その時点で先読み済みの広告があった。
    case accepted
    /// 広告を選ばずに閉じた（キャンセル・「もう一度」・画面を離れた）。
    case declined
    /// 広告ボタンを押したが、先読み済みの広告が無かった（その場で読み込む。#658 の先読みで減る値）。
    case notReady = "not_ready"
}

/// `game_end` の `cause`。**そのプレイで最後にミスした原因**（#796）。
///
/// チャリンコおじさんの「鳥を置物から障害にしたら、鳥にやられる割合が変わったか」を数字で
/// 読むための分類。障害の種類ごとに鍵を増やさず、`game_id` と同じく**語彙は enum に閉じる**
/// ——ゲーム側の型（`RunnerHazardKind` など）をそのまま文字列にすると、絵柄を足すたびに GA4 の
/// 値の集合が増えて横断で読めなくなる。
///
/// 送るのは「最後のミス」だけ（ミスのたびにイベントは出さない・イベントの種類は増やさない）。
/// ステージ制のミスは決着ではなく、`game_end` は クリア（win）か途中離脱（quit）でしか出ないので、
/// 「何にやられて諦めたか」＝離脱直前の死因が読める。ミスの無いプレイは鍵ごと送らない。
public enum AnalyticsEndCause: String, Equatable, Sendable, CaseIterable {
    /// 穴に落ちた。
    case pit
    /// 岩（低い・高い）や台座の正面にぶつかった。
    case rock
    /// 鳥。
    case bird
    /// 地面を走る動物（犬・イノシシ）。
    case animal
    /// 沈む床（チャリンコおじさんの田んぼ・干潟）で跳び続けられず沈んで溺れた（#1089）。
    ///
    /// 穴（`pit`）と分けてあるのは、**落ちた理由が違う**から——穴は「跳び越せなかった」、
    /// こちらは「跳び続けられなかった」で、直す先（床の長さか、置いた位置か）も別になる。
    case sink
}

/// `game_start` の `level`。難易度・段階を**ゲーム横断で読める語彙**へ正規化する（#500）。
///
/// ゲームごとの呼び名（「やさしい」「初級」「弱」「レベル 0」…）をそのまま送ると、
/// GA4 では `game_id` ごとに別の文字列集合になり、横断で読めない。強さを選ぶゲームは
/// この5段階へ写し、面を進めるゲームは面番号を `stage-N` として送る。写像は各ゲーム側の
/// `analyticsLevel` に置く（Core は個々のゲームの型を知らない）。
/// 難易度・段階の概念を持たないゲームは `nil` で、`level` の鍵ごと送らない。
///
/// - Note: 送る値は必ず文字列。面番号を整数で送ると同じ `level` が数値と文字列の2型になり、
///   GA4 のカスタムディメンションとして読めなくなる。
public enum AnalyticsLevel: Equatable, Sendable {
    /// 最弱。段階が3つのゲームでは使わない（CPU 対戦の5段階の「入門」・#1174）。
    case novice
    /// いちばんやさしい強さ。5段階のゲームでは下から2番目（「簡単」）。
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
        case .novice:   return "novice"
        case .beginner: return "beginner"
        case .normal:   return "normal"
        case .hard:     return "hard"
        case .expert:   return "expert"
        // 面番号は 1 始まり。0 以下は表示・記録のどちらにも存在しないので 1 に丸める。
        case let .stage(number): return "stage-\(max(1, number))"
        }
    }

    /// 強さを表す段階の全量（やさしい順）。`stage` は面数がゲームごとに違うためここには入らない。
    public static let allStrengths: [AnalyticsLevel] = [.novice, .beginner, .normal, .hard, .expert]

    /// **0 始まり**の強さ設定（各ゲームの `aiLevel` など）を段階へ写す。
    /// 範囲外の値も型の上では作れるため、下は `beginner`・上は `expert` に倒して受け止める。
    ///
    /// CPU 対戦の5段階（将棋・チェス・五目並べ・オセロ）は番号が 0 始まりではないので、
    /// ここではなく `CPUStrength.analyticsLevel` が写す（#1174）。
    public static func aiStrength(_ zeroBased: Int) -> AnalyticsLevel {
        switch zeroBased {
        case ..<1:  return .beginner
        case 1:     return .normal
        case 2:     return .hard
        default:    return .expert
        }
    }
}

/// `game_start` / `game_end` の `mode`。1 回の**遊び方**の区分（#783・#820）。
///
/// `level`（難易度・段階）とは別の軸で、同じゲームの中で 1 回の長さや終わり方が変わる遊び方を分ける。
/// ゲームごとの型（`MahjongGameLength` / `RunnerMode`）はそれぞれの `analyticsMode` でここへ写す
/// （Core は個々のゲームの型を知らない）。遊び方を選べないゲームは `nil` で、`mode` の鍵ごと送らない。
public enum AnalyticsMode: String, Equatable, Sendable, CaseIterable {
    /// 四人打ち麻雀の東風戦。
    case tonpuu
    /// 四人打ち麻雀の一局戦（v1.1.5）。1 対局が 1 局なので `game_start` が機械的に増える。
    case singleHand = "single_hand"
    /// チャリンコおじさんのステージ制。面番号は `level` の `stage-N` が持つ。
    case stage
    /// チャリンコおじさんのエンドレス。面が無いので `level` を送らない。
    case endless
}

/// `game_open` の `source`。ゲーム画面へ**どこから入ったか**（#659）。
///
/// ハブの中の導線を面ごとに読むための分類で、ゲーム名は含めない（それは `game_id` が持つ）。
public enum GameOpenSource: String, Equatable, Sendable, CaseIterable {
    /// ハブのグリッドのカード。
    case hub
    /// ハブ最上部の「つづき・最近」の行（#660）。
    case recent
    /// リザルト画面のレコメンドカード（#52）。
    case recommendation
    /// 中断したゲームのローカル通知（#663）。**発火点はまだ無い**（#663 の実装で使う）。
    case notification
    /// ハブ最上部の「はじめの1本」（#721）。記録がゼロの初回だけ出る1枚。
    case firstPick = "first_pick"

    /// 並びの中の位置を持つ導線か。持たない導線（1枚しか出ないカード・通知）では
    /// `position` の鍵ごと送らない。
    public var hasPosition: Bool {
        switch self {
        case .hub, .recent:                              return true
        case .recommendation, .notification, .firstPick: return false
        }
    }
}

/// `game_start` に添える、そのゲームのこれまでの遊び込み具合（#1195）。
///
/// 送るのは**回数と経過日数だけ**（日時そのものや個人を特定する情報は載せない）。
/// 目的は会長が GA4 で「どのゲームが繰り返し遊ばれ、どれが離れているか」を人の目で分析すること
/// で、アプリ側の判定（久しぶり通知など）には使わない。
public struct AnalyticsEngagement: Equatable, Sendable {
    /// このプレイより前に**終局した**回数（そのゲームの通算・区分は合算）。初めてなら 0。
    public let playCount: Int
    /// 前回の決着からの経過日数（暦日ではなく 24 時間単位の切り捨て）。一度も遊んでいなければ nil で、鍵ごと送らない。
    public let daysSinceLastPlay: Int?

    public init(playCount: Int, daysSinceLastPlay: Int?) {
        self.playCount = max(0, playCount)
        self.daysSinceLastPlay = daysSinceLastPlay.map { max(0, $0) }
    }
}

/// 送信する解析イベント。**`game_start` / `game_end` / `reward_ad` / `reward_request` / `game_open` /
/// `reward_offer` / `share_tap` の7種のみ**（#158 の決裁範囲 + #500 の会長決裁 2026-09-08 + #659 の会長決裁 2026-09-12 +
/// #780 の会長決裁 2026-09-16 + #1043 の会長決裁 2026-09-16）。`game_start` の `play_count` / `days_since_last_play` は
/// #1195 の会長決裁（2026-09-21・案A）でイベントは増やさずパラメータだけ足した。
///
/// パラメータは各ケースの関連値だけから組み立てるため、呼び出し側が任意のキーや値を
/// 追加する余地が無い。イベントを増やすにはこの enum にケースを足す = 意図的な変更が要る。
public enum AnalyticsEvent: Equatable, Sendable {
    /// 1プレイの開始。パラメータは `game_id` と、難易度を持つゲームだけ `level`、
    /// 遊び方を選べるゲームだけ `mode`（#783・#820。値の全量は `AnalyticsMode`）。
    /// 遊び込み具合を渡したときだけ `play_count` / 一度でも遊んだゲームだけ `days_since_last_play`（#1195）。
    case gameStart(
        gameID: String, level: AnalyticsLevel? = nil, mode: AnalyticsMode? = nil,
        engagement: AnalyticsEngagement? = nil
    )
    /// 1プレイの終わり。パラメータは `game_id` / `result` / `duration_sec` と、開始時に `mode` を
    /// 付けたプレイだけ `mode`（開始と終わりを同じ鍵で突き合わせるため）、そのプレイで 1 度でも
    /// ミスしたゲームだけ `cause`（最後のミスの原因・#796）、無料ヒントを 1 回でも使ったプレイだけ
    /// `hints_used`（#1326）。
    /// 決着（win / loss / draw）と途中離脱（quit）の両方がこのイベントで出る。
    case gameEnd(
        gameID: String, result: AnalyticsResult, durationSec: Int,
        mode: AnalyticsMode? = nil, cause: AnalyticsEndCause? = nil, hintsUsed: Int = 0
    )
    /// リワード広告の**視聴完了**。パラメータは `game_id` / `purpose` のみ（#500）。
    case rewardAd(gameID: String, purpose: RewardPurpose)
    /// リワード広告の**要求**（タップ）。視聴できたかどうかに関係なく1回出る（#659）。
    /// パラメータは `game_id` / `purpose` のみで、`reward_ad` と同じ語彙で突き合わせられる。
    case rewardRequest(gameID: String, purpose: RewardPurpose)
    /// ハブからゲーム画面を開いた（#659）。パラメータは `game_id` / `source` / `resume` と、
    /// 並びを持つ導線だけ `position`。
    ///
    /// - Parameters:
    ///   - position: 導線の中での位置（**1 始まり**）。並びを持たない導線では nil で、鍵ごと送らない。
    ///   - resume: 開いた時点で「続きから」だったか。GA4 で集計しやすいよう 0 / 1 で送る。
    case gameOpen(gameID: String, source: GameOpenSource, position: Int?, resume: Bool)
    /// リワード広告の**提示**が終わった（#780）。1 回の提示につき 1 回。パラメータは
    /// `game_id` / `purpose` / `result` のみで、`purpose` は `reward_ad` と同じ語彙。
    case rewardOffer(gameID: String, purpose: RewardPurpose, result: RewardOfferResult)
    /// リザルトの共有ボタン（自己ベストを更新した回だけ出る）を押した（#1043）。パラメータは `game_id` のみ。
    ///
    /// 数えるのは**押したこと**で、共有シートで実際に送ったか・どこへ送ったかは載せない
    /// （共有シートは OS の画面で、アプリからは結果を確実には取れないため）。スコアの生値も載せない。
    case shareTap(gameID: String)

    /// Firebase のイベント名。
    public var name: String {
        switch self {
        case .gameStart:     return "game_start"
        case .gameEnd:       return "game_end"
        case .rewardAd:      return "reward_ad"
        case .rewardRequest: return "reward_request"
        case .gameOpen:      return "game_open"
        case .rewardOffer:   return "reward_offer"
        case .shareTap:      return "share_tap"
        }
    }

    /// 送信するパラメータ。キーも値もこの1か所でしか組み立てない。
    public var parameters: [String: AnalyticsValue] {
        switch self {
        case let .gameStart(gameID, level, mode, engagement):
            var parameters: [String: AnalyticsValue] = ["game_id": .string(gameID)]
            // 難易度を持たないゲームでは鍵ごと送らない（GA4 で "none" のような
            // 実在しない段階を作らないため）。`mode` も同じ扱い。
            if let level { parameters["level"] = .string(level.parameterValue) }
            if let mode { parameters["mode"] = .string(mode.rawValue) }
            if let engagement {
                parameters["play_count"] = .int(engagement.playCount)
                // 初めて遊ぶゲームでは鍵ごと送らない（`level` と同じく、実在しない値を作らない）。
                if let days = engagement.daysSinceLastPlay { parameters["days_since_last_play"] = .int(days) }
            }
            return parameters
        case let .gameEnd(gameID, result, durationSec, mode, cause, hintsUsed):
            var parameters: [String: AnalyticsValue] = [
                "game_id": .string(gameID),
                // `AnalyticsResult` は win / loss / draw / quit の4値に閉じた enum。
                // 「クリア」「ゲームオーバー」は各ゲームが決着判定の時点で正規化済み。
                "result": .string(result.rawValue),
                "duration_sec": .int(durationSec),
            ]
            if let mode { parameters["mode"] = .string(mode.rawValue) }
            // ミスの無いプレイ・ミスの概念が無いゲームでは鍵ごと送らない（`level` と同じ扱い）。
            if let cause { parameters["cause"] = .string(cause.rawValue) }
            // ヒントを使わなかったプレイ・ヒントを持たないゲームでは鍵ごと送らない（`cause` と同じ扱い）。
            if hintsUsed > 0 { parameters["hints_used"] = .int(hintsUsed) }
            return parameters
        case let .rewardAd(gameID, purpose), let .rewardRequest(gameID, purpose):
            return [
                "game_id": .string(gameID),
                "purpose": .string(purpose.rawValue),
            ]
        case let .gameOpen(gameID, source, position, resume):
            var parameters: [String: AnalyticsValue] = [
                "game_id": .string(gameID),
                "source": .string(source.rawValue),
                "resume": .int(resume ? 1 : 0),
            ]
            // 並びを持たない導線では鍵ごと送らない（`level` と同じく、実在しない位置を作らない）。
            // 位置は 1 始まり。0 以下は並びの中に存在しないので 1 に丸める。
            if source.hasPosition, let position { parameters["position"] = .int(max(1, position)) }
            return parameters
        case let .rewardOffer(gameID, purpose, result):
            return [
                "game_id": .string(gameID),
                "purpose": .string(purpose.rawValue),
                "result": .string(result.rawValue),
            ]
        case let .shareTap(gameID):
            return ["game_id": .string(gameID)]
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

/// 1プレイの開始・終わりを対応付けて `game_start` / `game_end` を送り、あわせて
/// `reward_ad` / `reward_request` / `game_open` / `share_tap` も送る係。
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
        /// 進行中。`startedAt` は `duration_sec` の起点、`didProgress` は「1手でも指したか」、
        /// `canResume` は「画面を離れても続きから戻れるか」、`hintsUsed` は使った無料ヒントの回数（#1326）。
        case inFlight(startedAt: Date, didProgress: Bool, canResume: Bool, hintsUsed: Int)
        /// 終局済み。`game_end` は送信済みなので、同じプレイで二度送らない。
        case finished
    }

    private let service: AnalyticsService
    private let allowedGameIDs: Set<String>
    /// 現在時刻。テストが実時間で待たずに経過秒を検証できるよう差し替え可能にする。
    private let now: () -> Date
    /// `game_start` に載せる遊び込み具合の取得元（#1195）。nil を返せば載せない。
    /// 呼ぶのは開始のたびで、まだ今回のプレイを数えていない時点の記録を返すこと。
    private let engagement: @MainActor (String, Date) -> AnalyticsEngagement?
    private var plays: [String: PlayState] = [:]
    /// 進行中のプレイの `mode`（#783）。開始で覚え、終わりの `game_end` に同じ値を載せる。
    /// `mode` を持たないゲームは鍵が無い。
    private var modes: [String: AnalyticsMode] = [:]
    /// 進行中のプレイで最後にミスした原因（#796）。終わりの `game_end` に `cause` として載せる。
    /// プレイを始め直すと消える。ミスしていないプレイは鍵が無い。
    private var causes: [String: AnalyticsEndCause] = [:]
    /// 進行中のプレイの `duration_sec` の元になる、計時済みの秒数（#1373）。
    /// 積むのは「アプリが前面 かつ 休憩中でない」区間だけ。
    private var activeSeconds: [String: TimeInterval] = [:]
    /// 計時中のプレイの、いまの区間の開始時刻。計時を止めている間は鍵が無い。
    private var countingSince: [String: Date] = [:]
    /// ハブへ戻って休憩している（続きから戻れる）プレイ。再開（`startPlay`）か決着で外れる。
    private var resting: Set<String> = []
    /// アプリが前面にあるか。前面から外れている間は誰の計時も進めない。
    private var isAppActive = true
    /// 休憩中のプレイの控えの保存先（#1374）。nil なら保存しない（テスト・プレビュー）。
    private let restStore: UserDefaults?
    /// 休憩中のプレイの控えを入れる鍵。**この 1 つだけ**で、値はゲーム ID をキーにした辞書。
    /// 書くのは休憩に入った時点の 1 回で、決着・離脱・新規開始・解析オフで消す。
    public static let restStoreKey = "analytics_resting_plays_v1"
    /// `duration_sec` の上限（秒）。計時を止め損ねた場合の歯止め（#1373）。
    static let maxDurationSeconds = 2 * 60 * 60

    public init(
        service: AnalyticsService,
        allowedGameIDs: Set<String>,
        now: @escaping () -> Date = Date.init,
        engagement: @escaping @MainActor (String, Date) -> AnalyticsEngagement? = { _, _ in nil },
        restStore: UserDefaults? = nil
    ) {
        self.service = service
        self.allowedGameIDs = allowedGameIDs
        self.now = now
        self.engagement = engagement
        self.restStore = restStore
    }

    /// ゲーム画面を開いて新規にプレイが始まったときに呼ぶ。**冪等**。
    ///
    /// SwiftUI は親の再描画のたびに `State(initialValue:)` の式を評価するため、Model の
    /// `init` は1回の表示で何度も走りうる。ここで冪等にしておくことで、再描画・
    /// バックグラウンド復帰で `game_start` が増えない。
    public func startPlay(gameID: String, level: AnalyticsLevel? = nil, mode: AnalyticsMode? = nil) {
        guard allowedGameIDs.contains(gameID) else { return }
        // 休憩していたプレイの再開。開始は数え直さず、計時だけ再開する。
        if resting.remove(gameID) != nil { resumeClock(gameID: gameID) }
        guard plays[gameID] == nil else { return }
        beginPlay(gameID: gameID, level: level, mode: mode)
    }

    /// 「新しいゲーム」「次のラウンド」など、明示的に次のプレイを始めたときに呼ぶ。
    /// 前のプレイが終局していてもいなくても、**必ず1プレイとして数える**。
    ///
    /// - Note: 前のプレイが未決着で、かつ**1手でも指していた**場合は、始め直す前に
    ///   `game_end`（`result = quit`）を送る（#500）。1手も指していない配り直しは
    ///   捨てた盤面が無いので送らない（ソリティア #397 の敗北記録と同じ境目）。
    public func restartPlay(gameID: String, level: AnalyticsLevel? = nil, mode: AnalyticsMode? = nil) {
        guard allowedGameIDs.contains(gameID) else { return }
        endPlayAsQuitIfProgressed(gameID: gameID)
        beginPlay(gameID: gameID, level: level, mode: mode)
    }

    /// そのプレイで1手指した（盤面が動いた）ときに呼ぶ。**冪等**で、何度呼んでも状態は変わらない。
    ///
    /// この値だけが「捨てたら離脱として数える盤面か」を決める。呼ばないゲームでは
    /// 離脱が一切記録されないだけで、`game_start` / `game_end` の対応は従来どおり保たれる。
    ///
    /// - Important: **一度立つと、そのプレイが終わるまで下ろす手段は無い**（下ろす API を置かない）。
    ///   「戻す」で初期配置まで巻き戻してから捨てた場合も離脱として数える。遊んだ時間は実際に
    ///   使われており、`duration_sec` と対応の取れない `game_start` を作らないほうが集計が読める。
    public func recordProgress(gameID: String) {
        guard case let .inFlight(startedAt, didProgress, canResume, hintsUsed) = plays[gameID], !didProgress
        else { return }
        plays[gameID] = .inFlight(
            startedAt: startedAt, didProgress: true, canResume: canResume, hintsUsed: hintsUsed
        )
    }

    /// この局は**画面を離れたら失われる**ことを伝える（#500）。
    ///
    /// 既定では「中断データが在る = 続きから戻れる」と見なすが、それが成り立たないゲームがある。
    /// チャリンコおじさんの中断データはステージ番号とベストタイムの控えで、走行そのものは
    /// 復元せず必ずステージの頭から始まる（しかも記録を守るため決着後も消さない）。
    /// これを休憩と読むと、走行を捨てた離脱が永久に記録されない。
    public func markUnresumable(gameID: String) {
        guard case let .inFlight(startedAt, didProgress, canResume, hintsUsed) = plays[gameID], canResume
        else { return }
        plays[gameID] = .inFlight(
            startedAt: startedAt, didProgress: didProgress, canResume: false, hintsUsed: hintsUsed
        )
    }

    /// 無料ヒントを 1 回使ったときに呼ぶ（#1326）。**イベントは送らない**。
    ///
    /// 回数は進行中のプレイに覚えておき、終わりの `game_end` に `hints_used` として載せる。
    /// `game_end` は決着（`finishPlay`）でも途中離脱（`leaveGame` / `restartPlay`）でも `sendEnd` の
    /// 1 か所から出るので、ヒントを使った直後に離脱しても値は失われない。
    /// 進行中のプレイが無ければ何もしない（中断からの再開など、開始を数えていないプレイ）。
    public func recordHintUsed(gameID: String) {
        guard case let .inFlight(startedAt, didProgress, canResume, hintsUsed) = plays[gameID]
        else { return }
        plays[gameID] = .inFlight(
            startedAt: startedAt, didProgress: didProgress, canResume: canResume, hintsUsed: hintsUsed + 1
        )
    }

    /// そのプレイでミスした（穴に落ちた・ぶつかった）ときに呼ぶ（#796）。**イベントは送らない**。
    ///
    /// 覚えておいて、終わりの `game_end` に「最後のミスの原因」として載せる。何度ミスしても
    /// 最後の 1 つで上書きするだけなので、リトライを繰り返しても送信は増えない。
    /// 進行中のプレイが無ければ何もしない（中断からの再開など、開始を数えていないプレイ）。
    public func recordMissCause(gameID: String, cause: AnalyticsEndCause) {
        guard case .inFlight = plays[gameID] else { return }
        causes[gameID] = cause
    }

    /// 終局したときに呼ぶ。進行中のプレイが無いときは**何も送らない**
    /// （中断からの再開など、開始を数えていないプレイの終局。`duration_sec` の起点が
    /// 分からないため、対応の取れない `game_end` を作らない）。
    public func finishPlay(gameID: String, outcome: GameOutcome) {
        guard case let .inFlight(startedAt, _, _, hintsUsed) = plays[gameID] else { return }
        plays[gameID] = .finished
        sendEnd(gameID: gameID, result: AnalyticsResult(outcome), startedAt: startedAt, hintsUsed: hintsUsed)
    }

    /// リワード広告を**視聴し終えた**ときに呼ぶ（#500）。
    /// 表示しただけ・途中で閉じた場合は呼ばない（`GameServices.showRewardedAd` が判定する）。
    public func recordRewardAd(gameID: String, purpose: RewardPurpose) {
        guard allowedGameIDs.contains(gameID) else { return }
        service.log(.rewardAd(gameID: gameID, purpose: purpose))
    }

    /// リワード広告を**要求した**（タップした）ときに呼ぶ（#659）。
    /// 視聴完了の `reward_ad` と対にして、完了率（`reward_ad ÷ reward_request`）を読むためのもの。
    /// プレイの数え方には影響しない。
    public func recordRewardRequest(gameID: String, purpose: RewardPurpose) {
        guard allowedGameIDs.contains(gameID) else { return }
        service.log(.rewardRequest(gameID: gameID, purpose: purpose))
    }

    /// リワード広告の**提示が終わった**ときに呼ぶ（#780）。`reward_request` がタップの数なのに対し、
    /// こちらは「出したのに断られた」まで数える。プレイの数え方には影響しない。
    public func recordRewardOffer(gameID: String, purpose: RewardPurpose, result: RewardOfferResult) {
        guard allowedGameIDs.contains(gameID) else { return }
        service.log(.rewardOffer(gameID: gameID, purpose: purpose, result: result))
    }

    /// ハブからゲーム画面を開いたときに呼ぶ（#659）。プレイの数え方には影響しない
    /// （1プレイの開始は各ゲームの `startPlay` が決める。開いただけで遊ばずに戻る人もいるため）。
    public func recordGameOpen(gameID: String, source: GameOpenSource, position: Int?, resume: Bool) {
        guard allowedGameIDs.contains(gameID) else { return }
        // アプリが終了してから「続きから」で開いた局は、休憩前の計測状態を取り戻す（#1374）。
        if resume { adoptRest(gameID: gameID) }
        service.log(.gameOpen(gameID: gameID, source: source, position: position, resume: resume))
    }

    /// リザルトの共有ボタンを押したときに呼ぶ（#1043）。プレイの数え方には影響しない。
    public func recordShareTap(gameID: String) {
        guard allowedGameIDs.contains(gameID) else { return }
        service.log(.shareTap(gameID: gameID))
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
        activeSeconds.removeAll()
        countingSince.removeAll()
        resting.removeAll()
        restStore?.removeObject(forKey: Self.restStoreKey)
    }

    /// アプリが前面から外れたときに呼ぶ（#1373）。戻るまでの時間は `duration_sec` に入れない。
    public func appDidResignActive() {
        isAppActive = false
        for gameID in plays.keys { pauseClock(gameID: gameID) }
    }

    /// アプリが前面に戻ったときに呼ぶ（#1373）。休憩中のプレイは再開まで止めたまま。
    public func appDidBecomeActive() {
        isAppActive = true
        for (gameID, state) in plays {
            if case .inFlight = state, !resting.contains(gameID) { resumeClock(gameID: gameID) }
        }
    }

    private func pauseClock(gameID: String) {
        guard let since = countingSince.removeValue(forKey: gameID) else { return }
        activeSeconds[gameID, default: 0] += max(0, now().timeIntervalSince(since))
    }

    private func resumeClock(gameID: String) {
        guard isAppActive, countingSince[gameID] == nil else { return }
        countingSince[gameID] = now()
    }

    private func clearClock(gameID: String) {
        activeSeconds[gameID] = nil
        countingSince[gameID] = nil
        resting.remove(gameID)
        forgetRest(gameID: gameID)
    }

    /// 休憩中の計測状態の控え。アプリが終了しても「続きから」で戻った局の `game_end` を出せるように、
    /// 休憩に入る時点で書き留める（#1374）。中断データと同じく端末の中にだけ置き、ゲーム数を超えて増えない。
    private struct RestEntry: Codable {
        var activeSeconds: TimeInterval
        var didProgress: Bool
        var hintsUsed: Int
        var mode: String?
    }

    private func loadRests() -> [String: RestEntry] {
        guard let data = restStore?.data(forKey: Self.restStoreKey),
              let rests = try? JSONDecoder().decode([String: RestEntry].self, from: data)
        else { return [:] }
        return rests
    }

    private func saveRests(_ rests: [String: RestEntry]) {
        guard let restStore else { return }
        if rests.isEmpty {
            restStore.removeObject(forKey: Self.restStoreKey)
        } else if let data = try? JSONEncoder().encode(rests) {
            restStore.set(data, forKey: Self.restStoreKey)
        }
    }

    private func rememberRest(gameID: String) {
        guard restStore != nil, case let .inFlight(_, didProgress, _, hintsUsed) = plays[gameID] else { return }
        var rests = loadRests()
        rests[gameID] = RestEntry(
            activeSeconds: activeSeconds[gameID] ?? 0, didProgress: didProgress,
            hintsUsed: hintsUsed, mode: modes[gameID]?.rawValue
        )
        saveRests(rests)
    }

    private func forgetRest(gameID: String) {
        guard restStore != nil else { return }
        var rests = loadRests()
        guard rests.removeValue(forKey: gameID) != nil else { return }
        saveRests(rests)
    }

    /// アプリの終了をまたいだ休憩を、進行中のプレイとして取り戻す。開始は数え直さない（送信済みのため）。
    private func adoptRest(gameID: String) {
        guard plays[gameID] == nil, let entry = loadRests()[gameID] else { return }
        plays[gameID] = .inFlight(
            startedAt: now(), didProgress: entry.didProgress, canResume: true, hintsUsed: entry.hintsUsed
        )
        modes[gameID] = entry.mode.flatMap(AnalyticsMode.init(rawValue:))
        activeSeconds[gameID] = entry.activeSeconds
        resumeClock(gameID: gameID)
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
            clearClock(gameID: gameID)
            return
        }
        // 中断データが在っても、そこから局を復元しないゲームは離脱として扱う（`markUnresumable`）。
        if case let .inFlight(_, _, canResume, _) = plays[gameID], canResume, isResumable {
            // 休憩。再開するまでの時間は `duration_sec` に入れない（#1373）。
            resting.insert(gameID)
            pauseClock(gameID: gameID)
            rememberRest(gameID: gameID)
            return
        }
        endPlayAsQuitIfProgressed(gameID: gameID)
        // 送っても送らなくても、再開できない盤面はもう続きが無い。次に開いたら数え直す。
        plays[gameID] = nil
        clearClock(gameID: gameID)
    }

    /// 未決着のまま捨てられたプレイに `game_end`（`quit`）を送る。1手も指していなければ何も送らない。
    private func endPlayAsQuitIfProgressed(gameID: String) {
        guard case let .inFlight(startedAt, didProgress, _, hintsUsed) = plays[gameID], didProgress
        else { return }
        plays[gameID] = .finished
        sendEnd(gameID: gameID, result: .quit, startedAt: startedAt, hintsUsed: hintsUsed)
    }

    private func sendEnd(gameID: String, result: AnalyticsResult, startedAt: Date, hintsUsed: Int) {
        // 前面にいた時間だけを数える。計時中の区間を締めてから読む。負の秒数は送らず、上限で頭打ちにする（#1373）。
        pauseClock(gameID: gameID)
        resting.remove(gameID)
        forgetRest(gameID: gameID)
        let seconds = min(Self.maxDurationSeconds, max(0, Int(activeSeconds[gameID] ?? 0)))
        service.log(.gameEnd(
            gameID: gameID, result: result, durationSec: seconds,
            mode: modes[gameID], cause: causes[gameID], hintsUsed: hintsUsed
        ))
    }

    private func beginPlay(gameID: String, level: AnalyticsLevel?, mode: AnalyticsMode?) {
        let startedAt = now()
        plays[gameID] = .inFlight(startedAt: startedAt, didProgress: false, canResume: true, hintsUsed: 0)
        modes[gameID] = mode
        clearClock(gameID: gameID)
        resumeClock(gameID: gameID)
        // 前のプレイの死因を次のプレイへ持ち越さない。
        causes[gameID] = nil
        service.log(.gameStart(
            gameID: gameID, level: level, mode: mode, engagement: engagement(gameID, startedAt)
        ))
    }
}
