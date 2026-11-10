import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 「X でポストして特典をもらう」（#3359・会長決裁 2026-11-06）の共通部品。
///
/// - 特典を付けるゲームだけが `XShareOffer` を作って結果画面に出す（それ以外のゲームには出ない）。
/// - **ゲームごとに 1 回だけ**。受け取ったら `XShareReward.markClaimed` で端末に残し、以後そのゲームでは提案を出さない。
/// - 渡す条件は「共有シートが完了し、選ばれた先が X の共有拡張だった」こと。実際に投稿が残ったかは確かめない
///   （会長了承: 投稿後に消されても仕方ない）。X が入っていない・X 以外を選んだ・途中で閉じたときは渡さない。
/// - 通常の共有（結果カード・記録・設定）とは別の経路で、そちらは特典なしで何回でも使える。
public enum XShareReward {
    /// そのゲームの特典を受け取り済みかの保存先。
    public static func claimedKey(gameID: String) -> String { "xShareRewardClaimed_\(gameID)" }

    public static func isClaimed(_ defaults: UserDefaults, gameID: String) -> Bool {
        defaults.bool(forKey: claimedKey(gameID: gameID))
    }

    /// 受け取り済みにする。
    public static func markClaimed(_ defaults: UserDefaults, gameID: String) {
        defaults.set(true, forKey: claimedKey(gameID: gameID))
    }

    /// X（旧 Twitter）の共有拡張の `UIActivity.ActivityType`。**実機で確かめる値**（PR の「社長判断」に結果を書く）。
    /// X アプリの共有拡張は `com.atebits.Tweetie2.ShareExtension`。接頭辞で見るのは拡張の名前が版で変わっても拾うため。
    static let xActivityPrefixes = ["com.atebits.Tweetie2"]

    public static func isX(activityType: String?) -> Bool {
        guard let activityType else { return false }
        return xActivityPrefixes.contains { activityType.hasPrefix($0) }
    }

    /// 共有シートの終わり方が「X でポストした」と見なせるか。完了しなかった（閉じた・取り消した）、X 以外は false。
    public static func qualifies(activityType: String?, completed: Bool) -> Bool {
        completed && isX(activityType: activityType)
    }
}

/// 結果画面に出す提案の中身。ゲームごとに作る（見出し・本文・特典の渡し方がゲームで違うため）。
public struct XShareOffer {
    /// 「X でポストして ○○ をもらう」。
    public let title: String
    /// 特典を渡した後に出す文。
    public let grantedText: String
    /// 共有する本文（App Store のリンクはここへ足さない。部品が足す）。
    public let message: String
    /// 提案を出した（画面に現れた）とき。
    public let onShown: @MainActor () -> Void
    /// 「X でポスト」を押したとき。
    public let onTap: @MainActor () -> Void
    /// X でポストしたと見なせたとき。特典を渡すのはここ。
    public let onPosted: @MainActor () -> Void

    public init(title: String, grantedText: String, message: String,
                onShown: @escaping @MainActor () -> Void,
                onTap: @escaping @MainActor () -> Void,
                onPosted: @escaping @MainActor () -> Void) {
        self.title = title
        self.grantedText = grantedText
        self.message = message
        self.onShown = onShown
        self.onTap = onTap
        self.onPosted = onPosted
    }
}

/// 結果画面の提案の枠。共有の情報（App Store の URL）はハブが配る `RecordShareContext` から読み、配られない画面
/// （テスト・プレビュー）では何も出さない。
public struct XShareOfferView: View {
    private let offer: XShareOffer
    private let granted: Bool
    @Environment(\.recordShare) private var share
    @State private var didReportShown = false

    public init(_ offer: XShareOffer, granted: Bool) {
        self.offer = offer
        self.granted = granted
    }

    public var body: some View {
        if let share {
            VStack(spacing: 8) {
                if granted {
                    Label(offer.grantedText, systemImage: "gift.fill")
                        .themeBody(14, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.tealText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(offer.title)
                        .themeBody(14, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        offer.onTap()
                        XSharePresenter.present(text: "\(offer.message)\n\(share.url.absoluteString)") { type, completed in
                            if XShareReward.qualifies(activityType: type, completed: completed) { offer.onPosted() }
                        }
                    } label: {
                        Text(tr("X でポスト"))
                            .themeBody(15, weight: .bold, maxScale: 1.5)
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Theme.Fill.coral))
                    }
                    .buttonStyle(.pop)
                    Text(tr("ポストしなくても遊べます"))
                        .themeCaption(11)
                        .foregroundStyle(Theme.inkSubText)
                }
            }
            .padding(.vertical, 4)
            .onAppear {
                guard !didReportShown, !granted else { return }
                didReportShown = true
                offer.onShown()
            }
        }
    }
}

/// 共有シート（`UIActivityViewController`）を出して、終わり方（選ばれた先・完了したか）を受け取る。
/// SwiftUI の `ShareLink` は終わり方を返さないので、この提案だけは UIKit の共有シートを直接出す。
@MainActor
enum XSharePresenter {
    static func present(text: String, completion: @escaping @MainActor (_ activityType: String?, _ completed: Bool) -> Void) {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        sheet.completionWithItemsHandler = { type, completed, _, _ in
            let raw = type?.rawValue
            Task { @MainActor in completion(raw, completed) }
        }
        // iPad では起点が要る。
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        top.present(sheet, animated: true)
        #endif
    }
}
