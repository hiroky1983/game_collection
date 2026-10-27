import Core
import CoreGraphics
import CoreOjisanPixel
import SwiftUI

/// 図入りの遊び方（#2044）のチャリンコおじさんの図。文言は `HowToPlayGuide.runner.items` /
/// `.runnerEndless.items`（Core）と同じ順で、先頭（目的）と最後（ミス）だけがモードで変わる。
/// 走者は本番と同じドット絵（`OjisanPixel.rider`）、地面や穴は図形で描く。
@MainActor
enum RunnerHowToFigures {
    /// ステージ制の版。
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(StageGoalFigure()) },
        { AnyView(StartFigure()) },
        { AnyView(JumpFigure()) },
        { AnyView(DoubleJumpFigure()) },
        { AnyView(MissFigure(isEndless: false)) },
    ]

    /// エンドレスの版。
    static let endlessItems: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(EndlessFigure()) },
        { AnyView(StartFigure()) },
        { AnyView(JumpFigure()) },
        { AnyView(DoubleJumpFigure()) },
        { AnyView(MissFigure(isEndless: true)) },
    ]

    // MARK: 部品

    /// コマごとに 1 回だけビットマップにする（`RunnerTutorial.riderJump` と同じ作法）。
    private static let images: [OjisanPixel.RiderFrame: (CGImage, CGFloat)] = {
        var out: [OjisanPixel.RiderFrame: (CGImage, CGFloat)] = [:]
        for frame in [OjisanPixel.RiderFrame.ride0, .jump, .tumble] {
            let sprite = OjisanPixel.rider(frame)
            if let cg = sprite.cgImage(scale: 4) {
                out[frame] = (cg, CGFloat(sprite.width) / CGFloat(max(sprite.height, 1)))
            }
        }
        return out
    }()

    /// 走者のドット絵を高さ `height` で置く。
    @ViewBuilder
    static func rider(_ frame: OjisanPixel.RiderFrame, height: CGFloat) -> some View {
        if let entry = images[frame] {
            Image(decorative: entry.0, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: height * entry.1, height: height)
        }
    }

    private static let groundColor = Color(hex: 0x8A6A4A)
    private static let grassColor = Color(hex: 0x6BBF59)

    /// 地面の帯（上に草の線）。
    private struct Ground: View {
        let width: CGFloat
        var body: some View {
            VStack(spacing: 0) {
                Rectangle().fill(RunnerHowToFigures.grassColor).frame(height: 4)
                Rectangle().fill(RunnerHowToFigures.groundColor).frame(height: 10)
            }
            .frame(width: width)
        }
    }

    /// 跳んだ軌跡（点線の弧）。`rise` が弧の高さ。
    private struct Arc: Shape {
        let rise: CGFloat
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                           control: CGPoint(x: rect.midX, y: rect.maxY - rise * 2))
            return p
        }
    }

    // MARK: 図

    /// ステージ制: ゴールまで走ればクリア。
    struct StageGoalFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Ground(width: 240)
                    HStack(alignment: .bottom, spacing: 0) {
                        RunnerHowToFigures.rider(.ride0, height: 40)
                        Image(systemName: "arrow.right")
                            .scaledFont(14, weight: .black, maxScale: 1.2)
                            .foregroundStyle(Theme.inkSubText)
                            .padding(.horizontal, 10).padding(.bottom, 16)
                        Spacer(minLength: 0)
                        Image(systemName: "flag.checkered")
                            .scaledFont(30, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(Theme.ink)
                            .padding(.bottom, 14)
                    }
                    .frame(width: 220)
                    .padding(.bottom, 12)
                }
                RuleFigureLabel(tr("ゴールでステージクリア"), color: Theme.coralText)
            }
        }
    }

    /// エンドレス: ミスするまで走った距離が記録。
    struct EndlessFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Ground(width: 240)
                    HStack(alignment: .bottom, spacing: 6) {
                        RunnerHowToFigures.rider(.ride0, height: 40)
                        Rectangle()
                            .fill(Theme.coral)
                            .frame(width: 150, height: 3)
                            .overlay(alignment: .trailing) {
                                Image(systemName: "arrowtriangle.right.fill")
                                    .scaledFont(10, maxScale: 1.2)
                                    .foregroundStyle(Theme.coralText)
                                    .offset(x: 6)
                            }
                            .padding(.bottom, 20)
                    }
                    .frame(width: 220, alignment: .leading)
                    .padding(.bottom, 12)
                }
                RuleFigureLabel(tr("走った距離が記録"), color: Theme.coralText)
            }
        }
    }

    /// タップで走り出し、あとは自動で右へ。
    struct StartFigure: View {
        var body: some View {
            HStack(spacing: 14) {
                Image(systemName: "hand.tap.fill")
                    .scaledFont(28, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(Theme.coralText)
                Image(systemName: "arrow.right")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Ground(width: 150)
                        HStack(alignment: .bottom, spacing: 4) {
                            RunnerHowToFigures.rider(.ride0, height: 36)
                            Image(systemName: "chevron.right.2")
                                .scaledFont(14, weight: .black, maxScale: 1.2)
                                .foregroundStyle(Theme.inkSubText)
                                .padding(.bottom, 12)
                        }
                        .padding(.bottom, 12)
                    }
                    RuleFigureLabel(tr("自動で右へ進む"))
                }
            }
        }
    }

    /// 短く押すと低く、長く押すと高く跳ぶ。
    struct JumpFigure: View {
        var body: some View {
            HStack(alignment: .bottom, spacing: 18) {
                jump(rise: 14, label: tr("ちょんと押す"))
                jump(rise: 34, label: tr("長く押す"))
            }
        }

        private func jump(rise: CGFloat, label: String) -> some View {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Ground(width: 120)
                    Arc(rise: rise)
                        .stroke(Theme.coral, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 80, height: rise)
                        .padding(.bottom, 14)
                    RunnerHowToFigures.rider(.jump, height: 30)
                        .padding(.bottom, 14 + rise)
                }
                RuleFigureLabel(label, color: rise > 20 ? Theme.coralText : Theme.inkSubText)
            }
        }
    }

    /// 空中でもう一度タップすると二段ジャンプ。
    struct DoubleJumpFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomLeading) {
                    Ground(width: 220)
                    Arc(rise: 22)
                        .stroke(Theme.inkSub, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 90, height: 22)
                        .padding(.leading, 10).padding(.bottom, 14)
                    Arc(rise: 26)
                        .stroke(Theme.coral, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 100, height: 26)
                        .padding(.leading, 55).padding(.bottom, 14 + 22)
                    Image(systemName: "hand.tap.fill")
                        .scaledFont(18, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                        .padding(.leading, 46).padding(.bottom, 14 + 22 + 4)
                    RunnerHowToFigures.rider(.jump, height: 30)
                        .padding(.leading, 90).padding(.bottom, 14 + 22 + 26)
                }
                .frame(width: 220, height: 104, alignment: .bottomLeading)
                RuleFigureLabel(tr("空中でもう一度タップ"), color: Theme.coralText)
            }
        }
    }

    /// 穴に落ちたらミス（ステージ制は頭から・エンドレスはおしまい）。
    struct MissFigure: View {
        let isEndless: Bool

        var body: some View {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    HStack(spacing: 0) {
                        Ground(width: 90)
                        Color.clear.frame(width: 50, height: 14)
                        Ground(width: 90)
                    }
                    RunnerHowToFigures.rider(.tumble, height: 30)
                        .offset(y: 18)
                    RuleVerdictMark(false)
                        .offset(x: 34, y: -20)
                }
                .padding(.top, 16)
                .padding(.bottom, 12)
                RuleFigureLabel(isEndless ? tr("穴に落ちたらおしまい") : tr("穴に落ちたらミス"), color: Theme.coralText)
            }
        }
    }
}

extension RunnerMode {
    /// このモードの図入りの遊び方。ゲーム画面ヘッダーの「？」と開始シートで同じものを使う。
    @MainActor
    var howToPlayGuide: HowToPlayGuide {
        switch self {
        case .stages: .runner.illustrated(RunnerHowToFigures.items)
        case .endless: .runnerEndless.illustrated(RunnerHowToFigures.endlessItems)
        }
    }

    /// 開始シートで常に見せる項目の位置（`howToPlayGuide.items` の添字）: 目的・ミス（モードで変わる 2 つ）。
    static let setupKeyItemIndices = [0, 4]

    /// 開始シートで常に見せる項目。
    @MainActor
    var setupKeyItems: [HowToPlayItem] {
        let items = howToPlayGuide.items
        return Self.setupKeyItemIndices.map { items[$0] }
    }

    /// 開始シートで折りたたむ項目（走り出し・ジャンプ・二段ジャンプ。どちらのモードも同じ操作）。
    @MainActor
    var setupDetailItems: [HowToPlayItem] {
        let keys = Set(Self.setupKeyItemIndices)
        return howToPlayGuide.items.enumerated().filter { !keys.contains($0.offset) }.map(\.element)
    }
}
