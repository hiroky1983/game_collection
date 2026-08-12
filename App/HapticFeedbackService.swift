import UIKit
import Core

/// UIKit 標準のジェネレータによる触覚フィードバック実装。
/// オン / オフ判定は持たない（Core の `GatedFeedbackService` が受け持つ）。
/// ジェネレータは種類ごとに使い回し、`prepare()` で発火までの遅延を抑える。
@MainActor
final class HapticFeedbackService: FeedbackService {
    private let light  = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid  = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()

    func impact(_ style: FeedbackImpact) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light:  generator = light
        case .medium: generator = medium
        case .rigid:  generator = rigid
        }
        generator.impactOccurred()
        generator.prepare() // 連打される操作なので次回に備えて温めておく
    }

    func notify(_ type: FeedbackNotice) {
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case .success: feedbackType = .success
        case .warning: feedbackType = .warning
        case .error:   feedbackType = .error
        }
        notification.notificationOccurred(feedbackType)
    }
}
