import Foundation

/// 触覚フィードバックの強さ。UIKit の `UIImpactFeedbackGenerator.FeedbackStyle` に対応する。
public enum FeedbackImpact: Equatable, Sendable {
    /// 軽い操作（1マス開く・カードを1枚めくる）。
    case light
    /// 手応えのある操作（着手・ペア成立・カード配り）。
    case medium
    /// 硬い操作（フラグの着脱など切り替え系）。
    case rigid
}

/// 局面の決着を伝えるフィードバック。UIKit の `UINotificationFeedbackGenerator.FeedbackType` に対応する。
public enum FeedbackNotice: Equatable, Sendable {
    /// 勝ち・クリア。
    case success
    /// 引き分け・無効な操作の拒否。
    case warning
    /// 負け・ゲームオーバー。
    case error
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

    /// ブロック崩しの「ゆっくりモード」（#463）。**既定はオフ**。
    ///
    /// 反射神経を使うゲームは VoiceOver で完全に代替できないため、球の速さを落とす手段を
    /// アクセシビリティの代替手段として用意している（アクション枠の基盤規約）。
    /// 設定画面（App 層）とゲームのポーズ画面（GameKit 側）の両方が読み書きするので、
    /// `hints` と同じくキーの定義をここで共有する。
    static var blocksSlowMode: FeedbackPreference {
        FeedbackPreference(key: "blocksSlowMode_v1", defaultValue: false)
    }
}
