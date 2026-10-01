import SwiftUI

/// 終局後の「もう一回」と「設定を変える」（#1689・会長決裁 2026-10-02）。
///
/// 難易度・先後などを選ばせる 9 本（将棋・チェス・五目並べ・オセロ・囲碁・マインスイーパー・ナンプレ・
/// 神経衰弱・しりとり）で、終局後のボタンを**同じ見た目・文言・並び**に揃える部品。
/// - 主ボタン「同じ条件でもう一回」: 前回の条件で設定シートを開かずにすぐ始める（`onReplay`）。
/// - 副ボタン「設定を変える」: 従来どおり設定シートを開く（`onChangeSettings`）。
///
/// 主ボタンの文言は会長案の「同じ条件でもう一回」で、**幅が足りないときだけ「もう一回」に縮める**
/// （`ViewThatFits`。折り返し・省略でボタンの高さが揃わなくなるのを避ける。会長決裁 2026-10-02）。
/// 高さは従来の「もう一度」の 1 段（カプセル 28pt + 縦余白 8pt ×2）と同じにしてあり、
/// 対局中の操作列と高さが揃う契約（#148・#139。決着で盤が縮まない）を崩さない。
public struct GameReplayBar<Leading: View>: View {
    private let onReplay: () -> Void
    private let onChangeSettings: () -> Void
    private let leading: Leading
    private let contentMinHeight: CGFloat?
    private let verticalPadding: CGFloat

    /// - Parameters:
    ///   - contentMinHeight: 行の中身の最低の高さ。ボタンより背の高い操作列（ナンプレの数字パッド）と
    ///     高さを揃えたいときだけ渡す（ボタン自体は大きくならない）。
    ///   - verticalPadding: カードの縦余白。
    ///   - leading: 左端に置く記録ラベルなど。幅が足りなければ縮む。
    public init(
        contentMinHeight: CGFloat? = nil,
        verticalPadding: CGFloat = 8,
        onReplay: @escaping () -> Void,
        onChangeSettings: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.contentMinHeight = contentMinHeight
        self.verticalPadding = verticalPadding
        self.onReplay = onReplay
        self.onChangeSettings = onChangeSettings
        self.leading = leading()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            row(replayTitle: GameReplayBarText.replay)
            row(replayTitle: GameReplayBarText.replayShort)
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, verticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    private func row(replayTitle: String) -> some View {
        HStack(spacing: 8) {
            leading
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button(action: onReplay) {
                Self.capsule(replayTitle, fill: Theme.Fill.coral, foreground: Theme.onAccent)
            }
            Button(action: onChangeSettings) {
                Self.capsule(GameReplayBarText.changeSettings, fill: Theme.fillMuted, foreground: .white)
            }
        }
        .frame(minHeight: contentMinHeight)
    }

    /// 文字を拡大しても折り返してボタンの高さが跳ねないよう、1 行に固定する（`ViewThatFits` が幅を見る）。
    private static func capsule(_ title: String, fill: Color, foreground: Color) -> some View {
        Text(title)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(fill))
    }
}

public extension GameReplayBar where Leading == EmptyView {
    init(
        contentMinHeight: CGFloat? = nil,
        verticalPadding: CGFloat = 8,
        onReplay: @escaping () -> Void,
        onChangeSettings: @escaping () -> Void
    ) {
        self.init(contentMinHeight: contentMinHeight, verticalPadding: verticalPadding,
                  onReplay: onReplay, onChangeSettings: onChangeSettings) { EmptyView() }
    }
}

/// 終局後ボタンの文言。画面とテストが同じ文字列を見る。
public enum GameReplayBarText {
    public static let replay = "同じ条件でもう一回"
    public static let replayShort = "もう一回"
    public static let changeSettings = "設定を変える"
}
