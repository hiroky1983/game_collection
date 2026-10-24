import SwiftUI

/// 終局後の「もう一回」と「設定を変える」（#1689・会長決裁 2026-10-02）。
///
/// 難易度・先後などを選ばせる 9 本（将棋・チェス・五目並べ・オセロ・囲碁・マインスイーパー・ナンプレ・
/// 神経衰弱・しりとり）と倉庫のゲームで、終局後のボタンを**同じ見た目・文言・並び**に揃える部品。
/// - 主ボタン「同じ条件でもう一回」: 前回の条件で設定シートを開かずにすぐ始める（`onReplay`）。
/// - 副ボタン「設定を変える」: 従来どおり設定シートを開く（`onChangeSettings`）。
///
/// 主ボタンの文言は会長案の「同じ条件でもう一回」で、**幅が足りないときだけ「もう一回」に縮める**
/// （`ViewThatFits`。折り返し・省略でボタンの高さが揃わなくなるのを避ける。会長決裁 2026-10-02）。
///
/// 並びは #2360 の案3（会長方針 2026-10-25「将棋でも実装できるなら全部 案3 に揃える」）:
/// - ボタン自体を 44pt（`BoardGameControlMetrics.minTapTarget`）にし、2 つを**全幅で等分**する（間隔 8pt）。
///   以前はカプセル 28.5pt で、押せる範囲が 44pt に届かず「もう一回」のつもりで「設定を変える」が開いた。
/// - 記録（`leading`）はボタンの左ではなく**カードの上段**に出す（ボタンの幅を削らない）。行の高さは記録が無いあいだも確保する。
/// - カードの外寸は 44 + 縦余白 8 × 2 = 60pt（記録を出す画面は上段のぶん高い 90pt）。従来の 44.5pt より 15.5pt 高く、
///   盤が高さで決まる iPhone SE では盤がそのぶん縮む（将棋 252 → 237pt など。実画面で崩れないことを確認済み・#2360）。
///   「決着で盤が縮まない」契約（#148・#139）は、`GameControlArea` のひな形がこの部品の実寸で高さを取り、
///   この部品が記録の有無で高さを変えないことで保たれる。
public struct GameReplayBar<Leading: View>: View {
    private let onReplay: () -> Void
    private let onChangeSettings: () -> Void
    private let leading: Leading
    private let hasLeading: Bool
    private let verticalPadding: CGFloat

    /// - Parameters:
    ///   - verticalPadding: カードの縦余白。
    ///   - leading: 上段に置く記録ラベルなど。幅が足りなければ縮む。
    public init(
        verticalPadding: CGFloat = GameReplayBarMetrics.verticalPadding,
        onReplay: @escaping () -> Void,
        onChangeSettings: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.verticalPadding = verticalPadding
        self.onReplay = onReplay
        self.onChangeSettings = onChangeSettings
        self.leading = leading()
        self.hasLeading = Leading.self != EmptyView.self
    }

    public var body: some View {
        VStack(spacing: GameReplayBarMetrics.leadingSpacing) {
            if hasLeading {
                // 記録の行の高さは常に確保する。`RecordLabel` は記録が無いあいだ（対局中・`GameControlArea` のひな形）は
                // 何も描かないので、行をそのまま置くと決着して記録が入った瞬間にカードが伸び、盤が縮む（#148）。
                // 「自己ベスト更新！」のバッジが載る行でも伸びない高さ（`leadingRowHeight`）を透明な面で確保する。
                ZStack(alignment: .leading) {
                    Color.clear.frame(height: GameReplayBarMetrics.leadingRowHeight)
                    leading
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: GameReplayBarMetrics.buttonSpacing) {
                Button(action: onReplay) {
                    ViewThatFits(in: .horizontal) {
                        capsule(GameReplayBarText.replay, fill: Theme.Fill.coral, foreground: Theme.onAccent)
                        capsule(GameReplayBarText.replayShort, fill: Theme.Fill.coral, foreground: Theme.onAccent)
                    }
                }
                Button(action: onChangeSettings) {
                    capsule(GameReplayBarText.changeSettings, fill: Theme.fillMuted, foreground: .white)
                }
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, verticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 文字を拡大しても折り返してボタンの高さが跳ねないよう、1 行に固定する（`ViewThatFits` が幅を見る）。
    /// カプセルは 44pt の枠いっぱいに描き、押せる範囲は枠全体（角の外側まで `contentShape` で受ける）。
    /// 枠の外へはみ出させる負の padding は使わない（#711 のプローブで、枠の外は Button が反応しなかった）。
    private func capsule(_ title: String, fill: Color, foreground: Color) -> some View {
        Text(title)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: GameReplayBarMetrics.buttonHeight)
            .background(Capsule().fill(fill))
            .contentShape(Rectangle())
    }
}

public extension GameReplayBar where Leading == EmptyView {
    init(
        verticalPadding: CGFloat = GameReplayBarMetrics.verticalPadding,
        onReplay: @escaping () -> Void,
        onChangeSettings: @escaping () -> Void
    ) {
        self.init(verticalPadding: verticalPadding, onReplay: onReplay, onChangeSettings: onChangeSettings) { EmptyView() }
    }
}

/// `GameReplayBar` の寸法（#2360・案3）。View の `static let` は MainActor に隔離されるので View の外に置く。
public enum GameReplayBarMetrics {
    /// ボタンの高さ = 押せる範囲の高さ（Apple HIG の 44pt）。
    public static let buttonHeight: CGFloat = BoardGameControlMetrics.minTapTarget
    /// 2 つのボタンのあいだ。押せる範囲はここで切れて重ならない。
    public static let buttonSpacing: CGFloat = 8
    /// カードの縦余白。
    public static let verticalPadding: CGFloat = 8
    /// 記録の行とボタンの段のあいだ。
    public static let leadingSpacing: CGFloat = 6
    /// 記録の行の高さ（記録が無いあいだも確保する）。`RecordLabel` の「自己ベスト更新！」バッジ（12pt の文字 + 上下 4pt + 枠）が
    /// 載っても伸びない値。記録の有無・バッジの有無でカードの外寸が変わらないことがテストで固定されている。
    public static let leadingRowHeight: CGFloat = 24
    /// 記録を出さない画面のカードの外寸（60pt）。
    public static var cardHeight: CGFloat { buttonHeight + verticalPadding * 2 }
    /// 記録を出す画面のカードの外寸（90pt）。
    public static var cardHeightWithLeading: CGFloat { cardHeight + leadingRowHeight + leadingSpacing }
}

/// 終局後ボタンの文言。画面とテストが同じ文字列を見る。
public enum GameReplayBarText {
    public static var replay: String { tr("同じ条件でもう一回") }
    public static var replayShort: String { tr("もう一回") }
    public static var changeSettings: String { tr("設定を変える") }
}
