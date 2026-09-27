import SwiftUI

/// 手詰まり・詰み確定を告げる救済パネル（麻雀ソリティア・ソリティア・スパイダーソリティア・
/// フリーセル共通・#1490）。画面全体を暗くし、中央にダイアログ風のパネルを置く構成は変えない
/// （会長決裁 2026-09-27）。ボタンの見た目（高さ・余白・色の役割・説明文の大きさ）は
/// #1486（失敗パネルのデザイン統一）の基準に揃える。
public struct GameDeadEndPanel<Buttons: View>: View {
    private let emoji: String
    private let title: String
    private let message: String
    private let buttons: Buttons

    public init(
        emoji: String,
        title: String,
        message: String,
        @ViewBuilder buttons: () -> Buttons
    ) {
        self.emoji = emoji
        self.title = title
        self.message = message
        self.buttons = buttons()
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            // 大きな文字設定＋ボタン多めのゲーム（ソリティアの4ボタン等）は、収まらない盤面で
            // 最後のボタンに届かなくなる（CodeRabbit指摘）。**収まるあいだは今までの非スクロール
            // 表示のままにし、収まらないときだけスクロールに落とす**（`PokerView` と同じ手当て）。
            ViewThatFits(in: .vertical) {
                card
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        // 幅を枠に固定する（`ScrollView` は中身の理想幅を提案してくるため）。
                        card
                            .frame(width: geo.size.width)
                            .frame(minHeight: geo.size.height, alignment: .top)
                    }
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private var card: some View {
        VStack(spacing: 20) {
            Text(emoji).font(.system(size: 52))
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(message)
                .themeBody(15, weight: .semibold)
                .foregroundStyle(Theme.inkSub)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                buttons
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
    }
}

/// 主・救済系のボタン（塗りつぶし）。高さ・文字は #1486 の基準（52pt 以上・17pt 相当）。
public struct GameDeadEndActionButton: View {
    private let label: String
    private let systemImage: String?
    private let tint: Color
    private let isDisabled: Bool
    private let action: () -> Void

    public init(
        _ label: String,
        systemImage: String? = nil,
        tint: Color = Theme.Fill.purple,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(tint, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }

    @ViewBuilder
    private var content: some View {
        if let systemImage {
            Label(label, systemImage: systemImage).themeBody(17)
        } else {
            Text(label).themeBody(17)
        }
    }
}

/// やめる・最初から・このまま続ける等の締めのボタン。主ボタンと色を分ける
/// （白地＋濃い文字＋枠線。ナンプレの薄いグレー地＋白文字のような低コントラストにはしない・#1486）。
public struct GameDeadEndDismissButton: View {
    private let label: String
    private let isDisabled: Bool
    private let action: () -> Void

    public init(_ label: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .themeBody(17)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Theme.ink)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.ink.opacity(0.3), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
