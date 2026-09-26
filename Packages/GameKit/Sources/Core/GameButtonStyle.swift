import SwiftUI

/// ボタンの意味（#1413）。色は意味で決まり、ゲームごとに選ばない。
///
/// 広告ボタンが 4 色（コーラル／ティール／黄／紫）に割れていたのを、意味 → 色の対応表に寄せる。
/// 面色は `Theme.Fill`（文字 `Theme.onAccent` を載せて AA を満たす値。#220）から取る。
public enum GameButtonRole: Sendable, CaseIterable {
    /// 決定・主操作（開始・OK など）。
    case primary
    /// 取り消し（対戦の「待った」・一人用の「戻す」）。
    case undo
    /// ヒント。電球を添える。
    case hint
    /// 見送り（パス）。控えめな面に白文字。
    case skip
    /// 特別な宣言（リーチ・こいこい等）。
    case declaration
    /// 危険（投了・あきらめる）。確認ダイアログで広告と区別する。
    case destructive
    /// 広告を見て続ける。
    case ad

    /// 面の色。
    public var fill: Color {
        switch self {
        case .primary, .destructive, .ad: Theme.Fill.coral
        case .undo: Theme.Fill.teal
        case .hint: Theme.Fill.yellow
        case .skip: Theme.fillMuted
        case .declaration: Theme.Fill.purple
        }
    }

    /// 面の上の文字色。`skip` は面が `fillMuted`（`Theme.Hex.fillMuted` は白文字を載せる面色）なので白。
    public var foreground: Color {
        self == .skip ? Color.white : Theme.onAccent
    }

    /// 役割が決めているアイコン（ラベルに添える）。無ければ nil。
    public var systemImage: String? {
        switch self {
        case .hint: "lightbulb.fill"
        case .ad: "play.rectangle.fill"
        default: nil
        }
    }
}

/// ボタンの形（#1413）。「操作行のカプセル」と「横いっぱいの角丸」の 2 種類だけ。
public enum GameButtonShape: Sendable {
    /// 盤の下の操作行に並べるカプセル。44pt の枠に入れる。
    case capsule
    /// 横いっぱいのボタン。角丸は `Theme.cornerSmall`・高さ 44pt 以上。
    case block
}

/// 寸法。View と別の非隔離の型に置く（各ゲームの `Metrics` から参照できるように）。
public enum GameButtonMetrics {
    /// タップ標的の一辺の下限（Apple HIG）。
    public static let minTapTarget: CGFloat = 44
    /// 横いっぱいの形の角丸。
    public static let blockCorner: CGFloat = Theme.cornerSmall
}

/// 意味別のボタンスタイル（#1413）。`.buttonStyle(GameButtonStyle(role: .primary, shape: .block))`。
///
/// - 44pt は**ボタン自身の枠**に入れて矩形全体で受ける（枠の外へ当たり判定をはみ出させても反応しない。#711）。
/// - 押せないときは面を `fillMuted` に替える（差し色の面のままでは `.disabled` が見た目に出ない）。
public struct GameButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let role: GameButtonRole
    private let shape: GameButtonShape

    public init(role: GameButtonRole, shape: GameButtonShape = .capsule) {
        self.role = role
        self.shape = shape
    }

    public func makeBody(configuration: Configuration) -> some View {
        let fill = isEnabled ? role.fill : Theme.fillMuted
        let foreground = isEnabled ? role.foreground : Color.white
        switch shape {
        case .capsule:
            configuration.label
                .foregroundStyle(foreground)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(fill))
                .frame(minWidth: GameButtonMetrics.minTapTarget, minHeight: GameButtonMetrics.minTapTarget)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.85 : 1)
        case .block:
            configuration.label
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: GameButtonMetrics.minTapTarget)
                .background(
                    RoundedRectangle(cornerRadius: GameButtonMetrics.blockCorner, style: .continuous).fill(fill)
                )
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

public extension ButtonStyle where Self == GameButtonStyle {
    /// `.buttonStyle(.game(.primary, shape: .block))`。
    static func game(_ role: GameButtonRole, shape: GameButtonShape = .capsule) -> GameButtonStyle {
        GameButtonStyle(role: role, shape: shape)
    }
}
