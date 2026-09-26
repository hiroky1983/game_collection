import SwiftUI

/// 対戦ゲームの「ヘッダー下の行」の共通の枠と手番表示（#1419・#1011）。
///
/// 以前は将棋・チェスが最小 36pt、囲碁・五目並べが 32pt、オセロが未指定と、
/// ゲームごとに高さも手番の色も違っていた。ここに 1 つだけ置いて全対戦ゲームで揃える。
/// 寸法は View の `static let` に置くと MainActor 隔離になりテストから読めないので、非隔離の enum に持つ。
public enum GameStatusBarStyle {
    /// 最小の高さ。タップ対象ではないが、行が変わっても盤が上下に揺れないよう揃える。
    public static let minHeight: CGFloat = 44
    public static let horizontalPadding: CGFloat = 12
    public static let verticalPadding: CGFloat = 6
}

/// 左右に中身を置く共通の枠。左は手番表示（`TurnBadge`）や結果、右は手数・スコアなど。
public struct GameStatusBar<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing
    private let verticalPadding: CGFloat

    /// `verticalPadding` は、44pt のトグルボタンが帯の高さを決めるゲーム（一人用の拡大・旗）が
    /// 盤の高さを食わないよう詰めるための口（#1420）。既定は対戦ゲームと同じ 6。
    public init(verticalPadding: CGFloat = GameStatusBarStyle.verticalPadding,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.verticalPadding = verticalPadding
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GameStatusBarStyle.horizontalPadding)
        .padding(.vertical, verticalPadding)
        // 余白のあとに下限を掛ける。先に掛けると完成した高さが 44 + 6×2 = 56pt になる。
        .frame(minHeight: GameStatusBarStyle.minHeight)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// 手番の表示。あなた＝ティール、CPU＝コーラル、終局＝fillMuted（#1419・会長決裁 2026-09-25）。
public struct TurnBadge: View {
    public enum Kind: Equatable, Sendable {
        case you, cpu, finished

        /// 面の色。
        public var fill: Color {
            switch self {
            case .you: return Theme.Fill.teal
            case .cpu: return Theme.Fill.coral
            case .finished: return Theme.fillMuted
            }
        }

        /// 面に載せる文字色。fillMuted は濃色なので白（`Theme.onAccent` は差し色用）。
        public var text: Color {
            self == .finished ? .white : Theme.onAccent
        }
    }

    private let title: String
    private let kind: Kind

    public init(_ title: String, kind: Kind) {
        self.title = title
        self.kind = kind
    }

    /// 「あなたの番」「CPUの番」。
    public init(isYourTurn: Bool) {
        self.init(isYourTurn ? "あなたの番" : "CPUの番", kind: isYourTurn ? .you : .cpu)
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(kind.text)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(kind.fill))
    }
}
