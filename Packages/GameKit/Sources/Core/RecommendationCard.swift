import SwiftUI

/// リザルトの下に1枚だけ出す「次はこれで遊ぶ？」のカード。
///
/// **非モーダル**。操作をブロックせず、×で閉じられる。全画面ダイアログやアラートは使わない。
public struct RecommendationCard: View {
    private let module: GameModule
    private let accent: Color
    private let onOpen: () -> Void
    private let onDismiss: () -> Void

    public init(
        module: GameModule,
        accent: Color,
        onOpen: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.module = module
        self.accent = accent
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            module.icon
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("次はこれで遊ぶ？")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                        Text(module.title)
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer(minLength: 4)
                    Text("あそぶ")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(accent))
                }
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkSub)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// 各ゲームのリザルト直下に置く枠。提示するものが無ければ**何も描かない**（余白も作らない）。
public struct RecommendationSlot: View {
    private let services: GameServices
    private let isFinished: Bool

    /// - Parameter isFinished: そのゲームがリザルトを表示している状態か。
    ///   新しい対局を始めた時点でカードを引っ込めるために使う。
    public init(services: GameServices, isFinished: Bool) {
        self.services = services
        self.isFinished = isFinished
    }

    public var body: some View {
        if isFinished,
           let service = services.recommendations,
           let module = service.suggestedModule {
            RecommendationCard(
                module: module,
                accent: service.suggestedAccent,
                onOpen: { service.accept() },
                onDismiss: { service.dismiss() }
            )
        }
    }
}
