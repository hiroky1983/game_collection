import Core

/// 触覚フィードバックの呼び出しを記録するスパイ（#841）。
///
/// 以前は `SpyFeedback` / `SpyFeedbackService` / `FeedbackSpy` の名前で 9 ファイルに同じ実装が散らばっていた。
/// 効果音へ変換して記録するような、記録の形が違うスパイは各テストに残してよい。
@MainActor
public final class SpyFeedbackService: FeedbackService {
    public private(set) var impacts: [FeedbackImpact] = []
    public private(set) var notices: [FeedbackNotice] = []

    public init() {}

    /// impact と notify を合わせた呼び出し回数。
    public var callCount: Int { impacts.count + notices.count }

    /// 指定した種類の notify が届いた回数。
    public func notices(of type: FeedbackNotice) -> Int { notices.filter { $0 == type }.count }

    public func impact(_ style: FeedbackImpact) { impacts.append(style) }
    public func notify(_ type: FeedbackNotice) { notices.append(type) }

    /// 記録を空に戻す（前提づくりの操作ぶんを数えないため）。
    public func reset() {
        impacts = []
        notices = []
    }
}
