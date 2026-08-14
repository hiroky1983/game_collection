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

/// 触覚 / 効果音のオン・オフを `UserDefaults` に保存する小さな箱。
/// 「未設定ならオン」という既定値と保存先キーの規則をここ 1 か所に閉じ込め、
/// App 層の設定モデル（`GameSettings`）からは読み書きするだけにする。
public struct FeedbackPreference {
    private let key: String
    private let defaults: UserDefaults

    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    /// 保存された設定。キーが無いとき（初回起動）はオン。
    public var isEnabled: Bool {
        get { defaults.object(forKey: key) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}
