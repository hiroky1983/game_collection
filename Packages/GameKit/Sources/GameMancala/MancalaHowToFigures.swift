import Core
import SwiftUI

/// 図入りの遊び方（#2044）のマンカラの図。文言は `HowToPlayGuide.mancala.items`（Core）と同じ順。
///
/// 盤は本番と同じ色の小さな穴（数字入り）とストアで描く。外部の画像は使わない。
@MainActor
enum MancalaHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(SowFigure()) },
        { AnyView(ExtraTurnFigure()) },
        { AnyView(CaptureFigure()) },
        { AnyView(EndFigure()) },
    ]

    private static let pit: CGFloat = 30

    /// 図の小さな穴（くぼみ + 数字）。
    private struct MiniPit: View {
        let seeds: Int
        var tone: Tone = .plain

        enum Tone { case plain, picked, gained, taken }

        var body: some View {
            ZStack {
                Circle().fill(Color(hex: MancalaBoardStyle.hole))
                if tone == .gained { Circle().fill(Theme.yellow.opacity(0.45)) }
                Text(verbatim: "\(seeds)")
                    .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Color.white)
                if tone == .picked { Circle().strokeBorder(Theme.teal, lineWidth: 3) }
                if tone == .taken { Circle().strokeBorder(Theme.coral, style: StrokeStyle(lineWidth: 2.5, dash: [3, 2])) }
            }
            .frame(width: MancalaHowToFigures.pit, height: MancalaHowToFigures.pit)
        }
    }

    /// 図の小さなストア（縦長のくぼみ + 数字）。
    private struct MiniStore: View {
        let seeds: Int
        var gained = false

        var body: some View {
            ZStack {
                Capsule().fill(Color(hex: MancalaBoardStyle.hole))
                if gained { Capsule().fill(Theme.yellow.opacity(0.45)) }
                Text(verbatim: "\(seeds)")
                    .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Color.white)
            }
            .frame(width: MancalaHowToFigures.pit * 0.9, height: MancalaHowToFigures.pit * 2 + 4)
        }
    }

    /// 木の板の地。
    private struct Plate<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            content
                .padding(5)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(Color(hex: MancalaBoardStyle.wood)))
        }
    }

    /// 手前の段（穴 4 つ + 自分のストア）だけの盤。
    private struct HumanRow: View {
        let pits: [Int]
        let tones: [MiniPit.Tone]
        let store: Int
        var storeGained = false

        var body: some View {
            Plate {
                HStack(spacing: 4) {
                    ForEach(pits.indices, id: \.self) { i in MiniPit(seeds: pits[i], tone: tones[i]) }
                    ZStack {
                        Capsule().fill(Color(hex: MancalaBoardStyle.hole))
                        if storeGained { Capsule().fill(Theme.yellow.opacity(0.45)) }
                        Text(verbatim: "\(store)")
                            .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: MancalaHowToFigures.pit * 0.9, height: MancalaHowToFigures.pit)
                }
            }
        }
    }

    /// 穴をタップすると、種を 1 個ずつ右どなりへまく: [3, 1, 1] → [0, 2, 2] + 次へ 1 個。
    private struct SowFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 10) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HumanRow(pits: [3, 1, 1, 2], tones: [.picked, .plain, .plain, .plain], store: 0)
                        RuleFigureLabel(tr("3 個の穴をタップ"), color: Theme.coralText)
                    } else {
                        HumanRow(pits: [0, 2, 2, 3], tones: [.plain, .gained, .gained, .gained], store: 0)
                        RuleFigureLabel(tr("右へ 1 個ずつ"))
                    }
                }
            }
        }
    }

    /// 最後の 1 個がストアに入ると、もう一度。
    private struct ExtraTurnFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 10) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HumanRow(pits: [0, 1, 2, 2], tones: [.plain, .plain, .picked, .plain], store: 5)
                        RuleFigureLabel(tr("2 個をまくと…"), color: Theme.coralText)
                    } else {
                        HumanRow(pits: [0, 1, 0, 3], tones: [.plain, .plain, .plain, .gained], store: 6, storeGained: true)
                        RuleFigureLabel(tr("ストアに入って もう一度！"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 空の穴に最後の 1 個が入ると、向かいの種ごと取る。
    private struct CaptureFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 10) { index in
                VStack(spacing: 4) {
                    Plate {
                        HStack(spacing: 4) {
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    MiniPit(seeds: 2)
                                    MiniPit(seeds: index == 0 ? 5 : 0, tone: index == 0 ? .plain : .taken)
                                }
                                HStack(spacing: 4) {
                                    MiniPit(seeds: index == 0 ? 1 : 0, tone: index == 0 ? .picked : .plain)
                                    MiniPit(seeds: 0, tone: index == 0 ? .plain : .taken)
                                }
                            }
                            MiniStore(seeds: index == 0 ? 4 : 10, gained: index == 1)
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("空の穴へ 1 個") : tr("向かいの 5 個と合わせて 6 個"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 片側が空になったら終わり。ストアの多いほうの勝ち。
    private struct EndFigure: View {
        var body: some View {
            HStack(spacing: 22) {
                tally(tr("あなた"), 27, isWinner: true)
                tally("CPU", 21, isWinner: false)
            }
        }

        private func tally(_ who: String, _ seeds: Int, isWinner: Bool) -> some View {
            VStack(spacing: 4) {
                Plate { MiniStore(seeds: seeds, gained: isWinner) }
                RuleFigureLabel(who, color: isWinner ? Theme.coralText : Theme.inkSubText)
                if isWinner { RuleFigureLabel(tr("多いほうの勝ち"), color: Theme.coralText) }
            }
        }
    }
}
