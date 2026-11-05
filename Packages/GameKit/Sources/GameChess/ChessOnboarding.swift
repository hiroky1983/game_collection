import Core
import CoreMiniBoard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2827）のチェス。
///
/// 特別な動き（キャスリング・アンパッサン・プロモーション）と、チェック・ステイルメイトの図は、
/// `sampleFENs` の局面をそのまま描いたもの。`ChessOnboardingTests` が同じ局面を `ChessPosition` に読み込み、
/// 図が示すとおりに指せる・詰む・引き分けになることを確かめる。盤は本番の駒（`ChessPieceView`）で描く。
@MainActor
public enum ChessOnboarding {
    /// 図の局面。キーは図の名前。
    static let sampleFENs: [String: String] = [
        "castling": "4k3/8/8/8/8/8/8/4K2R w K - 0 1",
        "enPassant": "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
        "promotion": "4k3/P7/8/8/8/8/8/4K3 w - - 0 1",
        "check": "k1R5/8/8/8/8/8/8/6K1 b - - 0 1",
        "stalemate": "k7/2Q5/2K5/8/8/8/8/8 b - - 0 1",
        "mate": "4R2k/6pp/8/8/8/8/8/6K1 b - - 0 1",
    ]

    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "chess",
            title: tr("チェスのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("相手のキングを詰ませたら勝ちです。"),
                        tr("逃げ場の無い王手を「チェックメイト」といいます。"),
                    ],
                    figure: { AnyView(ChessHowToFigures.MateFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("自分の駒をタップすると、動けるマスが光ります。"),
                        tr("光ったマスをタップして、駒を動かします。"),
                        tr("相手の駒があるマスへ動くと、その駒を取れます。"),
                    ],
                    figure: { AnyView(ChessHowToFigures.SelectMoveFigure()) }
                ),
                OnboardingPage(
                    heading: tr("駒の動き方"),
                    lines: [
                        tr("ナイトは L 字、ビショップはななめ、ルークはたてよこ。"),
                        tr("クイーンはたてよこななめ、キングは 1 マス。"),
                        tr("ポーンは前へ 1 マス（最初だけ 2 マス）。取るときはななめ前。"),
                    ],
                    figure: { AnyView(ChessHowToFigures.MovesFigure()) }
                ),
                OnboardingPage(
                    heading: tr("特別な動き"),
                    lines: [
                        tr("キャスリング: キングとルークを一度に動かします。"),
                        tr("アンパッサン: 2 マス進んだポーンを、通り過ぎたマスへ取ります。"),
                        tr("プロモーション: ポーンが奥に着くと、好きな駒に変わります。"),
                    ],
                    figure: { AnyView(SpecialMovesFigure()) }
                ),
                OnboardingPage(
                    heading: tr("王手（チェック）"),
                    lines: [
                        tr("キングが次に取られる形が「王手（チェック）」です。"),
                        tr("王手のときは、逃げるか、守るか、取るかで外します。"),
                        tr("どうしても外せない王手が、チェックメイトです。"),
                    ],
                    figure: { AnyView(CheckFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("チェックメイトをかけた側の勝ちです。"),
                        tr("王手が無いのに動かせない「ステイルメイト」は引き分けです。"),
                        tr("同じ局面が 3 回・50 手のあいだポーンも駒取りも無い・駒不足も引き分けです。"),
                    ],
                    figure: { AnyView(StalemateFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    private static func piece(_ type: ChessPieceType, _ color: ChessColor = .white) -> some View {
        ChessHowToFigures.piece(type, color, size: 26)
    }

    /// キャスリング・アンパッサン・プロモーション。前 → 後のコマで見せる。
    private struct SpecialMovesFigure: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                row(tr("キャスリング")) { castling(after: $0) }
                row(tr("アンパッサン")) { enPassant(after: $0) }
                row(tr("プロモーション")) { promotion(after: $0) }
            }
        }

        private func row<Frame: View>(_ name: String, @ViewBuilder frame: @escaping (Bool) -> Frame) -> some View {
            HStack(spacing: 12) {
                RuleFigureLabel(name, color: Theme.coralText)
                    .frame(width: 84, alignment: .leading)
                RuleFrames(count: 2, spacing: 8) { index in frame(index == 1) }
            }
        }

        /// e1 のキング・h1 のルーク → g1 と f1。
        private func castling(after: Bool) -> some View {
            RuleMiniBoard(rows: 1, cols: 4, cell: 26, style: .checker) { _, col in
                ZStack {
                    if !after, col == 0 { ChessOnboarding.piece(.king) }
                    if !after, col == 3 { ChessOnboarding.piece(.rook) }
                    if after, col == 1 { ChessOnboarding.piece(.rook) }
                    if after, col == 2 { ChessOnboarding.piece(.king) }
                }
            }
        }

        /// d5 の黒ポーンが 2 マス進んだ直後、e5 の白ポーンが d6 へ取る。
        private func enPassant(after: Bool) -> some View {
            RuleMiniBoard(rows: 2, cols: 2, cell: 26, style: .checker) { row, col in
                ZStack {
                    if !after, row == 0, col == 0 { RuleBoardMark.dot() }
                    if !after, row == 1, col == 0 { ChessOnboarding.piece(.pawn, .black) }
                    if !after, row == 1, col == 1 { ChessOnboarding.piece(.pawn) }
                    if after, row == 0, col == 0 { ChessOnboarding.piece(.pawn) }
                }
            }
        }

        /// 7 段目のポーン → 8 段目でクイーン。
        private func promotion(after: Bool) -> some View {
            RuleMiniBoard(rows: 2, cols: 1, cell: 26, style: .checker) { row, _ in
                ZStack {
                    if !after, row == 1 { ChessOnboarding.piece(.pawn) }
                    if after, row == 0 { ChessOnboarding.piece(.queen) }
                }
            }
        }
    }

    /// 王手: ルークの利きがキングに届いている。
    private struct CheckFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 3, cols: 3, cell: 34, style: .checker) { row, col in
                    ZStack {
                        if row == 0, col == 1 { RuleBoardMark.tint() }
                        if row == 0, col == 0 { ChessOnboarding.piece(.king, .black) }
                        if row == 0, col == 2 { ChessOnboarding.piece(.rook) }
                    }
                }
                RuleFigureLabel(tr("ルークがキングを狙っている（王手）"), color: Theme.coralText)
            }
        }
    }

    /// ステイルメイト: 王手ではないのに、黒は動ける所が無い（引き分け）。
    private struct StalemateFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 3, cols: 3, cell: 34, style: .checker) { row, col in
                    ZStack {
                        if row == 0, col == 0 { ChessOnboarding.piece(.king, .black) }
                        if row == 1, col == 2 { ChessOnboarding.piece(.queen) }
                        if row == 2, col == 2 { ChessOnboarding.piece(.king) }
                    }
                }
                RuleFigureLabel(tr("王手ではないのに黒は動けない（引き分け）"), color: Theme.coralText)
            }
        }
    }
}
