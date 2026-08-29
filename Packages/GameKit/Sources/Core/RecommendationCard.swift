import SwiftUI

/// リザルトの下に1枚だけ出す「次はこれで遊ぶ？」のカード。
///
/// **非モーダル**。操作をブロックせず、×で閉じられる。全画面ダイアログやアラートは使わない。
public struct RecommendationCard: View {
    /// 先頭のアイコンの一辺。カードの高さはこれで決まる（文字はこれより低い）。
    private static let iconSide: CGFloat = 36
    private static let verticalPadding: CGFloat = 10
    /// 見出しの基準 pt。実カードと `heightPlaceholder` で必ず同じ値を使う（高さ契約）。
    private static let captionSize: CGFloat = 11

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
                        .frame(width: Self.iconSide, height: Self.iconSide)
                        .overlay {
                            module.icon
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("次はこれで遊ぶ？")
                            .themeCaption(Self.captionSize, weight: .semibold)
                            .foregroundStyle(Theme.inkSub)
                        Text(module.title)
                            .themeBody(16)
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer(minLength: 4)
                    Text("あそぶ")
                        .themeCaption(13)
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
        .padding(.horizontal, 12).padding(.vertical, Self.verticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// カードが出ていない間も同じ高さを占める**不可視**のひな形（#139）。
    ///
    /// カードが出た瞬間に下の領域が伸びると、盤面（`aspectRatio` + `layoutPriority`）が
    /// 帳尻合わせに縮む画面がある。呼び出し側はこれを `ZStack` の高さの基準に置き、
    /// カードの有無で高さが動かないようにする。実カードと同じ寸法・同じフォントで組むため、
    /// カードの見た目を変えても基準がずれない。
    public static var heightPlaceholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .frame(width: iconSide, height: iconSide)
            VStack(alignment: .leading, spacing: 2) {
                Text("次はこれで遊ぶ？").themeCaption(captionSize, weight: .semibold)
                Text("　").themeBody(16)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12).padding(.vertical, verticalPadding)
        .popCard(corner: Theme.cornerSmall)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
