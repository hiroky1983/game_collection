import StoreKit
import SwiftUI

public extension View {
    /// 評価リクエストの実行をこの画面に紐づける。描画するものは無く、レイアウトには影響しない。
    ///
    /// リザルトが出てから1.0秒後に OS へ評価ダイアログを依頼する（条件6）。待っている間に画面を
    /// 離れたら予定を破棄するので、ゲーム進行中や別のゲームの最中に出ることはない。
    ///
    /// `SKStoreReviewController.requestReview(in:)` を直接呼ばず SwiftUI の `requestReview` を使う。
    /// 中身は同じ StoreKit のリクエストで、シーンの取得を自分でやらずに済み、iOS 18 で
    /// deprecated になった API を避けられる（設定画面の「アプリを評価する」も同じ API）。
    func reviewRequestPrompt(_ service: ReviewRequestService?) -> some View {
        modifier(ReviewRequestPromptModifier(service: service))
    }
}

private struct ReviewRequestPromptModifier: ViewModifier {
    let service: ReviewRequestService?
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.task(id: service?.pendingRequestID) {
            guard let service, service.pendingRequestID != nil else { return }
            await service.performPendingRequest { requestReview() }
        }
    }
}
