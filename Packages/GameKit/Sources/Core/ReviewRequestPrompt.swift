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
    /// deprecated になった API を避けられる（設定画面の「アプリを評価する」は #1471 から App Store の URL を開く）。
    func reviewRequestPrompt(_ service: ReviewRequestService?) -> some View {
        modifier(ReviewRequestPromptModifier(service: service))
    }
}

public extension View {
    /// ハブに評価リクエスト（遊んだ日数の節目・#3078）の実行を紐づける。`reviewRequestPrompt` の OS ダイアログの部分だけで、
    /// 感想カードは出さない（カードはゲームの画面が持つ）。
    ///
    /// ハブは NavigationStack の根でゲームの下に残り続けるので、`isActive`（ハブが前面にあるか）が false の間は
    /// 実行しない。待っている間にゲームを開いた（＝false になった）ら予定を破棄する。
    func hubReviewRequestPrompt(_ service: ReviewRequestService?, isActive: Bool) -> some View {
        modifier(HubReviewRequestPromptModifier(service: service, isActive: isActive))
    }
}

private struct HubReviewRequestPromptModifier: ViewModifier {
    let service: ReviewRequestService?
    let isActive: Bool
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.task(id: isActive ? service?.pendingRequestID : nil) {
            guard isActive, let service, service.pendingRequestID != nil else { return }
            await service.performPendingRequest { requestReview() }
        }
    }
}

private struct ReviewRequestPromptModifier: ViewModifier {
    let service: ReviewRequestService?
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .task(id: service?.pendingRequestID) {
                guard let service, service.pendingRequestID != nil else { return }
                await service.performPendingRequest { requestReview() }
            }
            .task(id: service?.pendingNewGameCardID) {
                guard let service, service.pendingNewGameCardID != nil else { return }
                await service.presentPendingNewGameCard()
            }
            // 表示中に戻るで画面を離れても、共有サービスに表示中の状態を残さない（別のゲームで再表示されない）。
            .onDisappear { service?.newGameCardDismissed() }
            .overlay {
                if let service, service.isNewGameCardPresented {
                    NewGameFeedbackCard(
                        onWriteReview: {
                            service.newGameCardWriteReviewTapped()
                            openURL(ReviewRequestService.writeReviewURL)
                        },
                        onLater: { service.newGameCardDismissed() }
                    )
                    .transition(.opacity)
                }
            }
    }
}

/// 新しいゲームを遊んだ直後に 1 回だけ出す、アプリ独自の感想カード（#3061）。
///
/// iOS の評価ダイアログは文言を変えられないので、その手前にこのカードを置く。行き先は App Store の
/// レビュー画面ただ 1 つ（感想の中身で振り分けない＝満足した人だけを評価へ回す選り分けにならない）。
/// 背景をタップするか「あとで」で閉じる。
private struct NewGameFeedbackCard: View {
    let onWriteReview: () -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onLater)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text(tr("新しいゲームはどうでしたか？"))
                        .themeBody(18, weight: .heavy)
                        .foregroundStyle(Theme.ink)
                    Text(tr("感想をお聞かせください"))
                        .themeCaption(13, weight: .semibold)
                        .foregroundStyle(Theme.inkSubText)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                VStack(spacing: 8) {
                    Button(action: onWriteReview) {
                        Text(tr("App Store で感想を書く")).themeBody(16)
                    }
                    .buttonStyle(.game(.primary, shape: .block))
                    Button(action: onLater) {
                        Text(tr("あとで")).themeBody(16)
                    }
                    .buttonStyle(.game(.skip, shape: .block))
                }
            }
            .padding(18)
            .frame(maxWidth: 340)
            .popCard()
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isModal)
        }
    }
}
