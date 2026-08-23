import SwiftUI
import Core

/// ATT 許可ダイアログを出すタイミングの門番。
/// 「初回起動でいきなり出さず、最初のゲームを遊び終えてハブに戻った時点で1回だけ」を判定する。
enum TrackingConsentGate {
    /// 事前説明を出し終えたかどうかの永続フラグ。
    static let promptShownKey = "attPrePromptShown"

    /// 事前説明を出してよいか。まだ出しておらず、かつ ATT が未決定のときだけ true。
    static func shouldPrompt(
        defaults: UserDefaults = .standard,
        isUndetermined: Bool
    ) -> Bool {
        !defaults.bool(forKey: promptShownKey) && isUndetermined
    }

    /// 事前説明を出し終えた（以後は許可・拒否のいずれでも二度と出さない）。
    static func markPrompted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: promptShownKey)
    }
}

/// ATT の事前説明シート。システムダイアログの手前に1枚挟んで、何に使うのか・拒否しても損が無いことを先に伝える。
struct TrackingConsentPrompt: View {
    /// 「続ける」が押されたときに呼ぶ（システムの ATT ダイアログへ引き継ぐ）。
    let onContinue: () -> Void
    @State private var isContinuing = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Theme.coral.gradient))
                .shadow(color: Theme.coral.opacity(0.4), radius: 8, y: 4)

            Text("広告の表示について")
                .themeTitle(24)
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 14) {
                row("sparkles", "より関連性の高い広告を表示するために、端末の広告識別子を使わせてください。")
                row("checkmark.circle.fill", "許可しなくても、8つのゲームはすべてそのまま遊べます。")
                row("info.circle.fill", "許可しない場合も広告は表示されます（内容が関連性の低いものになります）。")
            }
            .padding(20)
            .popCard()

            Text("このあとに表示される確認画面で選べます。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSub)
                .multilineTextAlignment(.center)

            Spacer(minLength: 12)

            Button {
                guard !isContinuing else { return }
                isContinuing = true
                onContinue()
            } label: {
                Text("続ける")
                    .themeBody(18)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.coral.gradient)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isContinuing)
        }
        .padding(Theme.pad)
        .padding(.top, 40)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .popBackground()
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.coral)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
