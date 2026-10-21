import Core
import SwiftUI

/// 図入りの遊び方（#2044）の明かり消しパズルの図。文言は `HowToPlayGuide.akariKeshi.items`（Core）と同じ順。
/// 明かりは本番と同じ `AkariKeshiLamp`。
@MainActor
enum AkariKeshiHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PressFigure()) },
        { AnyView(EdgeFigure()) },
        { AnyView(ClearFigure()) },
    ]

    private static let side: CGFloat = 22

    /// 3×3 の小さな盤。`lit` の升が点灯、`pressed` の升に押した印。
    private struct MiniBoard: View {
        let lit: Set<Int>
        var pressed: Int? = nil
        var body: some View {
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            AkariKeshiLamp(isLit: lit.contains(index), side: AkariKeshiHowToFigures.side,
                                           isPressed: index == pressed)
                        }
                    }
                }
            }
        }
    }

    /// 真ん中を押す → 真ん中と上下左右の 5 つが入れ替わる。
    private struct PressFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    if index == 0 {
                        MiniBoard(lit: [0, 4], pressed: 4)
                    } else {
                        MiniBoard(lit: [0, 1, 3, 5, 7])
                    }
                }
                RuleFigureLabel(tr("押したマスと上下左右"), color: Theme.coralText)
            }
        }
    }

    /// 角を押す → 盤の中にある隣（2 つ）と自分だけが入れ替わる。
    private struct EdgeFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    if index == 0 {
                        MiniBoard(lit: [], pressed: 0)
                    } else {
                        MiniBoard(lit: [0, 1, 3])
                    }
                }
                RuleFigureLabel(tr("角は 3 マスだけ"), color: Theme.coralText)
            }
        }
    }

    /// 全部消えたらクリア。
    private struct ClearFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    if index == 0 {
                        MiniBoard(lit: [1, 3, 4, 5, 7], pressed: 4)
                    } else {
                        MiniBoard(lit: [])
                    }
                }
                RuleFigureLabel(tr("全部消せばクリア"), color: Theme.tealText)
            }
        }
    }
}
