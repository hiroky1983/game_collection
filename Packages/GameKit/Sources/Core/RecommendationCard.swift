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
    private let caption: String
    private let onOpen: () -> Void
    private let onDismiss: () -> Void

    /// - Parameter caption: 見出し（`RecommendationReason.caption`）。久しぶり枠では
    ///   「◯日ぶりに遊んでみない？」に変わるため、**必ず1行に収める**（高さ契約・#139）。
    public init(
        module: GameModule,
        accent: Color,
        caption: String,
        onOpen: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.module = module
        self.accent = accent
        self.caption = caption
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
                                .foregroundStyle(Theme.onAccent)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(caption)
                            .themeCaption(Self.captionSize, weight: .semibold)
                            .foregroundStyle(Theme.inkSub)
                            .lineLimit(1)
                        Text(module.title)
                            .themeBody(16)
                            .foregroundStyle(Theme.ink)
                            // ひな形（`heightPlaceholder`）の同じ位置は 1 文字 = 必ず 1 行なので、
                            // 実カード側も 1 行に固定しないと高さの契約が崩れる（#600）。
                            // 名前の長いゲームでは枠が伸び、下に置いたものが押し出される。
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("あそぶ")
                        .themeCaption(13)
                        .foregroundStyle(Theme.onAccent)
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

    /// `heightPlaceholder` が常に占める高さ（pt）の**下限**。
    ///
    /// 中身で一番背が高いのは先頭のアイコンなので、枠の高さはアイコンと上下の余白で決まる
    /// （文字はこれより低い。ダイナミックタイプで文字が伸びた場合だけ枠もそのぶん伸びる）。
    /// この枠に相乗りする部品が「枠を超えず、周りの寸法を動かさない」ことを
    /// テストで確かめるための基準として公開している（#600 のブロック崩しの一時停止ボタン）。
    public static let placeholderMinimumHeight: CGFloat = iconSide + verticalPadding * 2

    /// カードが出ていない間も同じ高さを占める**不可視**のひな形（#139）。
    ///
    /// カードが出た瞬間に下の領域が伸びると、盤面（`aspectRatio` + `layoutPriority`）が
    /// 帳尻合わせに縮む画面がある。呼び出し側はこれを `ZStack` の高さの基準に置き、
    /// カードの有無で高さが動かないようにする。実カードと同じ寸法・同じフォントで組むため、
    /// カードの見た目を変えても基準がずれない。
    ///
    /// 見出しの文字列は見出しの**高さ**を決めるためだけのもので、実カードの文言
    /// （`RecommendationReason.caption`）とは一致しなくてよい。実カード側を
    /// `lineLimit(1)` に固定してあるので、文言が伸びても高さは変わらない。
    public static var heightPlaceholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .frame(width: iconSide, height: iconSide)
            VStack(alignment: .leading, spacing: 2) {
                Text("次はこれで遊ぶ？").themeCaption(captionSize, weight: .semibold).lineLimit(1)
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
                caption: service.suggestedReason.caption,
                onOpen: { service.accept() },
                onDismiss: { service.dismiss() }
            )
        }
    }
}

/// レコメンドの枠だけを置く画面用（#148・#528）。
///
/// 盤の下に操作列を持たないゲーム（2048・ブロックならべ・ブロック崩し・チャリンコおじさん）が
/// **同じ 4 行を各自で書いていた**。ひな形（`RecommendationCard.heightPlaceholder`）を敷いて
/// おかないと、カードが出た瞬間に下の領域が伸びて盤面が帳尻合わせに縮む。カードは出るとは
/// 限らず×でも閉じられるため、条件付きで高さを足すのでは安定しない。
///
/// 終局後に操作列（「もう一度」など）も出す画面は `GameControlArea` を使う。
public struct RecommendationArea: View {
    private let services: GameServices
    private let isFinished: Bool

    public init(services: GameServices, isFinished: Bool) {
        self.services = services
        self.isFinished = isFinished
    }

    public var body: some View {
        ZStack(alignment: .top) {
            RecommendationCard.heightPlaceholder
            RecommendationSlot(services: services, isFinished: isFinished)
        }
    }
}
