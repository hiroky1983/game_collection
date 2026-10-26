import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2825）の将棋。
///
/// 成り・二歩・打ち歩詰め・行き所のない駒・千日手は `MoveGenerator` / `ShogiGameModel` の実装どおり。
/// 詰み・王手・二歩・成りの図は `sampleSFENs` の局面で、`ShogiOnboardingTests` が同じ SFEN を `Position` に読み込んで
/// 図が示すとおりの結果になることを確かめる。図は遊び方の図（`ShogiHowToFigures`）の部品を使い回す。
/// 駒ごとの動き方・手合い（駒落ち）は盤の駒をタップする・「くわしいルール」・開始シートに任せ、ここでは触れない。
@MainActor
enum ShogiOnboarding {
    /// 図の局面。キーは図の名前（盤の中央の筋に置き直したもの）。
    static let sampleSFENs: [String: String] = [
        "mate": "4k4/4G4/4P4/9/9/9/9/9/4K4 w - 1",
        "check": "4k4/9/9/9/9/9/9/4R4/4K4 w - 1",
        "capture": "4k4/9/9/9/4p4/4S4/9/9/4K4 b - 1",
        "promotion": "4k4/9/9/4P4/9/9/9/9/4K4 b - 1",
        "nifu": "4k4/9/9/9/4P4/9/9/9/4K4 b P 1",
    ]

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "shogi",
            title: tr("将棋のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("相手の王将（玉）を追いつめたら勝ちです。"),
                        tr("逃げ場の無い王手を「詰み」といいます。"),
                    ],
                    figure: { AnyView(ShogiHowToFigures.MateFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("自分の駒をタップすると、動けるマスが光ります。"),
                        tr("光ったマスをタップして、駒を動かします。"),
                    ],
                    figure: { AnyView(ShogiHowToFigures.SelectMoveFigure()) }
                ),
                OnboardingPage(
                    heading: tr("駒を取る・持ち駒"),
                    lines: [
                        tr("相手の駒があるマスへ動くと、その駒を取れます。"),
                        tr("取った駒は持ち駒になり、あとで好きなマスに打てます。"),
                    ],
                    figure: { AnyView(ShogiHowToFigures.CaptureFigure()) }
                ),
                OnboardingPage(
                    heading: tr("成り"),
                    lines: [
                        tr("相手陣（奥の 3 段）に入る・中で動く・出るときに、駒を成れます。"),
                        tr("金と玉は成れません。動けなくなる段へ進むときは、必ず成ります。"),
                    ],
                    figure: { AnyView(ShogiHowToFigures.PromoteFigure()) }
                ),
                OnboardingPage(
                    heading: tr("打てない場所"),
                    lines: [
                        tr("同じ筋に自分の歩がある筋へ、歩は打てません（二歩）。"),
                        tr("歩を打って、すぐ相手を詰ませる手は反則です（打ち歩詰め）。"),
                        tr("歩・香・桂は、動けなくなる段へは打てません。"),
                    ],
                    figure: { AnyView(NifuFigure()) }
                ),
                OnboardingPage(
                    heading: tr("王手と勝ち負け"),
                    lines: [
                        tr("次に玉を取られる形が「王手」。王手を外す手しか指せません。"),
                        tr("外せない王手が「詰み」で、詰ませた方の勝ちです。"),
                        tr("同じ局面が 4 回くり返されると千日手で引き分け。王手を続けた側は負けです。"),
                    ],
                    figure: { AnyView(CheckFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 二歩: 歩のある筋の空きマスには、歩を打てない。
    private struct NifuFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 3, cols: 3, cell: ShogiHowToFigures.cell, style: .shogi) { row, col in
                    ZStack {
                        if col == 1, row < 2 { RuleBoardMark.cross() }
                        if col != 1, row < 2 { RuleBoardMark.dot() }
                        if col == 1, row == 2 { ShogiHowToFigures.koma(.pawn) }
                    }
                }
                RuleFigureLabel(tr("歩のある筋の ✕ には歩を打てない（二歩）"), color: Theme.coralText)
            }
        }
    }

    /// 王手: 飛車の利きが王将に届いている。
    private struct CheckFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 3, cols: 3, cell: ShogiHowToFigures.cell, style: .shogi) { row, col in
                    ZStack {
                        if col == 1, row == 1 { RuleBoardMark.tint(opacity: 0.25) }
                        if row == 0, col == 1 { ShogiHowToFigures.koma(.king, mine: false) }
                        if row == 2, col == 1 { ShogiHowToFigures.koma(.rook) }
                    }
                }
                RuleFigureLabel(tr("飛車が王将を狙っている（王手）"), color: Theme.coralText)
            }
        }
    }
}
