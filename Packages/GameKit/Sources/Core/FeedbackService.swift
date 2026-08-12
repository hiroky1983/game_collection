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
