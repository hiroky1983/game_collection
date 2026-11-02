import Core
import SwiftUI

/// ステージの今の位置の文言（開始シートとクリアのカード・#3240）。面番号→表示の対応はここに集める（テストで固定）。
enum CatPuzzleStageProgressText {
    /// 「7×7：3 / 15 面」。12×12 は面数が決まっていないので「12×12：5 面目」。
    static func position(_ progress: CatPuzzleStage.Progress) -> String {
        if let count = progress.count {
            return tr("%1$@：%2$lld / %3$lld 面", progress.size.sizeLabel, progress.position, count)
        }
        return tr("%1$@：%2$lld 面目", progress.size.sizeLabel, progress.position)
    }

    /// 「次の盤（8×8）まであと 12 面」。盤の最後の面は「次の面から 8×8」。12×12 に入ったら nil。
    static func nextBoard(_ progress: CatPuzzleStage.Progress) -> String? {
        guard let next = progress.nextSize, let rest = progress.toNextBoard else { return nil }
        if rest == 0 { return tr("次の面から %@", next.sizeLabel) }
        return tr("次の盤（%1$@）まであと %2$lld 面", next.sizeLabel, rest)
    }

    /// 「鍵の面まであと 5 面」。鍵の面そのものは「鍵の面」、1 つ前は「次は鍵の面」。
    static func key(_ progress: CatPuzzleStage.Progress) -> String {
        if progress.isKey { return tr("鍵の面") }
        if progress.toKey == 0 { return tr("次は鍵の面") }
        return tr("鍵の面まであと %lld 面", progress.toKey)
    }

    /// 「次の盤」と「鍵」を 1 行に並べたもの（クリアのカード用）。
    static func upcoming(_ progress: CatPuzzleStage.Progress) -> String {
        [nextBoard(progress), key(progress)].compactMap { $0 }.joined(separator: "・")
    }

    /// 盤が切り替わったときの一言（「8×8 に進んだ！」）。
    static func advanced(to size: CatPuzzleSize) -> String { tr("%@ に進んだ！", size.sizeLabel) }
}

/// 開始シートに出す、次に遊ぶ面の位置。文言 3 行と、盤ごとの進み具合の細い棒。
struct CatPuzzleStageProgressView: View {
    let progress: CatPuzzleStage.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CatPuzzleStageProgressText.position(progress))
                .scaledFont(15, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundStyle(Theme.ink)
            if let fraction = progress.fraction {
                Gauge(fraction: fraction)
                    .frame(height: 6)
                    .accessibilityHidden(true)
            }
            if let next = CatPuzzleStageProgressText.nextBoard(progress) {
                Text(next)
            }
            Label(CatPuzzleStageProgressText.key(progress), systemImage: "key.fill")
                .labelStyle(.titleAndIcon)
        }
        .scaledFont(13, weight: .semibold, design: .rounded, maxScale: 1.3)
        .foregroundStyle(Theme.inkSubText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// 細い棒（角丸の帯に進んだ分だけ色を重ねる）。
    private struct Gauge: View {
        let fraction: Double

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fillMuted.opacity(0.35))
                    Capsule().fill(Theme.Fill.coral)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
        }
    }
}

/// 盤が切り替わる面に入ったとき、盤の上に短く出す「8×8 に進んだ！」。触れても邪魔にならないよう操作を通す。
struct CatPuzzleBoardAdvanceBanner: View {
    let size: CatPuzzleSize

    var body: some View {
        Text(CatPuzzleStageProgressText.advanced(to: size))
            .scaledFont(22, weight: .heavy, design: .rounded, maxScale: 1.3)
            .foregroundStyle(Theme.onAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Capsule().fill(Theme.Fill.coral))
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isStaticText)
    }
}
