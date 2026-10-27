import Foundation

/// 触覚フィードバックの強さ。UIKit の `UIImpactFeedbackGenerator.FeedbackStyle` に対応する。
public enum FeedbackImpact: Equatable, Sendable {
    /// 軽い操作（1マス開く・カードを1枚めくる）。
    case light
    /// 手応えのある操作（着手・ペア成立・カード配り）。
    case medium
    /// 硬い操作（フラグの着脱など切り替え系）。
    case rigid
    /// 駒・牌・カードを「選ぶ」だけの操作（まだ何も確定しない）。`UISelectionFeedbackGenerator` で最も弱い。
    /// 効果音は鳴らさない（`SoundEffect` に対応する音が無い）。
    case selection
    /// トランプの配る・めくる・出す・切る。触覚は `CardSound.haptic`、効果音は同梱のカードの音（#2697）。
    case card(CardSound)
    /// 将棋・囲碁・五目並べ・オセロ・チェスの自分の着手。触覚は `BoardSound.haptic`、効果音は同梱の駒・石の音（#2767）。
    case board(BoardSound)

    /// 効果音を相乗りさせるか。選ぶだけの操作は触覚だけ（効果音を増やさない・#2303）。
    public var hasSound: Bool { self != .selection }
}

/// 局面の決着を伝えるフィードバック。UIKit の `UINotificationFeedbackGenerator.FeedbackType` に対応する。
public enum FeedbackNotice: Equatable, Sendable {
    /// 勝ち・クリア。
    case success
    /// 引き分け・無効な操作の拒否。
    case warning
    /// 負け・ゲームオーバー。
    case error
    /// 大きな節目の達成（今のところチャリンコおじさんのゴール到達のみ・会長指示 2026-09-23）。
    /// 触覚は `success` と同じものを使う（`UINotificationFeedbackGenerator` にそれ以上強い種類が無い）。
    /// 効果音だけ `success` より長く派手なもの（`SoundEffect.fanfare`）に差し替える。
    case milestone
}

/// 触覚フィードバックの境界。App 層が UIKit 実装を注入し、テスト・プレビューでは `NoopFeedbackService` を使う。
/// 各ゲームは判定済みの Model 側からのみ呼ぶ（View のタップハンドラに撒くと無効操作を拾い漏らすため）。
public protocol FeedbackService {
    /// 操作の成立を伝える。
    @MainActor func impact(_ style: FeedbackImpact)
    /// 決着・拒否など結果を伝える。
    @MainActor func notify(_ type: FeedbackNotice)
}

/// 何もしない実装。テスト・プレビュー・触覚非対応環境用。
public struct NoopFeedbackService: FeedbackService {
    public init() {}
    @MainActor public func impact(_ style: FeedbackImpact) {}
    @MainActor public func notify(_ type: FeedbackNotice) {}
}

/// 設定トグルがオフのときは下位サービスへ委譲しないラッパー。
/// オン / オフ判定をここに閉じ込め、各ゲーム側に条件分岐を撒かない。
public struct GatedFeedbackService: FeedbackService {
    private let base: FeedbackService
    private let isEnabled: @MainActor () -> Bool

    public init(base: FeedbackService, isEnabled: @escaping @MainActor () -> Bool) {
        self.base = base
        self.isEnabled = isEnabled
    }

    @MainActor public func impact(_ style: FeedbackImpact) {
        guard isEnabled() else { return }
        base.impact(style)
    }

    @MainActor public func notify(_ type: FeedbackNotice) {
        guard isEnabled() else { return }
        base.notify(type)
    }
}

/// 同じ発火を複数の実装へ配るラッパー。触覚と効果音を**同じ呼び出し箇所に相乗り**させるために使う。
/// これにより各ゲーム側には新しい発火点を作らずに済み、鳴りすぎの制御も 1 か所に残る。
public struct CompositeFeedbackService: FeedbackService {
    private let services: [FeedbackService]

    public init(_ services: [FeedbackService]) {
        self.services = services
    }

    @MainActor public func impact(_ style: FeedbackImpact) {
        for service in services { service.impact(style) }
    }

    @MainActor public func notify(_ type: FeedbackNotice) {
        for service in services { service.notify(type) }
    }
}

/// オン・オフの設定を `UserDefaults` に保存する小さな箱。
/// 「未設定ならオン」という既定値と保存先キーの規則をここ 1 か所に閉じ込め、
/// App 層の設定モデル（`GameSettings`）からは読み書きするだけにする。
///
/// 触覚・効果音のために作ったが、解析送信（#158）・ヒント表示（#190）も同じ箱に相乗りしている
/// （オン / オフ 1 つのために新しい永続化の仕組みを増やさない）。
public struct FeedbackPreference {
    private let key: String
    private let defaults: UserDefaults
    /// キーが保存されていないとき（初回起動）に返す値。
    ///
    /// 触覚・効果音・ヒント・解析はいずれも「既定でオン」だが、あとから足した機能には
    /// 既定でオフにすべきものもある（ブロック崩しのゆっくりモード・#463）。
    /// オン / オフ 1 つのために別の永続化の仕組みを増やさず、既定値だけを可変にする。
    private let defaultValue: Bool

    public init(key: String, defaults: UserDefaults = .standard, defaultValue: Bool = true) {
        self.key = key
        self.defaults = defaults
        self.defaultValue = defaultValue
    }

    /// 保存された設定。キーが無いとき（初回起動）は `defaultValue`。
    public var isEnabled: Bool {
        get { defaults.object(forKey: key) as? Bool ?? defaultValue }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}

/// 効果音の音量（小・中・大・#3007）。オンのときだけ意味を持つ。既定は中。
///
/// `scale` は `AVAudioPlayer.volume` にそのまま渡す値。中は従来の固定値（0.6）と同じにして、
/// 設定を触っていない人の聞こえ方を変えない。保存は文字列の rawValue（並びを入れ替えても壊れない）。
public enum SoundVolume: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public static let `default`: SoundVolume = .medium

    public var scale: Float {
        switch self {
        case .small: return 0.3
        case .medium: return 0.6
        case .large: return 1.0
        }
    }
}

/// `SoundVolume` の保存。`FeedbackPreference` と同じく `UserDefaults` の注入でテストできる。
public struct SoundVolumePreference {
    private let key: String
    private let defaults: UserDefaults

    public init(key: String = "soundVolume_v1", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    /// 保存が無い・読めない値のときは既定（中）。
    public var volume: SoundVolume {
        get { defaults.string(forKey: key).flatMap(SoundVolume.init(rawValue:)) ?? .default }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key) }
    }
}

public extension FeedbackPreference {
    /// ヒント表示（いま出せる手の強調・出せない理由の表示）のオン / オフ（#190）。既定はオン。
    ///
    /// 設定画面（App 層）と各ゲーム（GameKit 側）の両方が読むため、キーの定義をここで共有する。
    /// 保存先は `UserDefaults.standard` 固定なので、テストは `FeedbackPreference(key:defaults:)` で
    /// 使い捨ての suite を作って注入する。
    ///
    /// `static let` にすると `UserDefaults` を抱えた共有可変状態として Sendable 違反になるため、
    /// 都度組み立てる計算プロパティにしている（実体は文字列と `UserDefaults` の参照だけなので安い）。
    static var hints: FeedbackPreference { FeedbackPreference(key: "hintsEnabled_v1") }

    /// アクション枠の「ゆっくりモード」（#463・#494）。**既定はオフ**。
    ///
    /// 反射神経を使うゲームは VoiceOver で完全に代替できないため、進みを遅くする手段を
    /// アクセシビリティの代替手段として用意している（アクション枠の基盤規約）。
    /// 設定画面（App 層）とゲームのポーズ画面（GameKit 側）の両方が読み書きするので、
    /// `hints` と同じくキーの定義をここで共有する。
    ///
    /// **アクション枠のゲームすべてで 1 つの設定を共有する**（#494 で横スクロールランナーを
    /// 足したときに、ゲームごとにスイッチを増やさない方針を採った）。保存キーが
    /// `blocksSlowMode_v1` のままなのは、名前を変えると**既にオンにしている人の設定が
    /// 初期値へ戻る**ため。キーは保存されたデータの識別子で、意味の説明はこの名前が担う。
    static var actionSlowMode: FeedbackPreference {
        FeedbackPreference(key: "blocksSlowMode_v1", defaultValue: false)
    }

    /// 柵越えおじさんの方向メーター（打席の左上）の表示（#1348）。**既定はオン**。
    /// 上級者向けに消せる。消しても判定は変わらない（表示だけ）。ゲームの打席前の画面から切り替える。
    static var homerunDirectionMeter: FeedbackPreference {
        FeedbackPreference(key: "homerunDirectionMeter_v1")
    }
}
