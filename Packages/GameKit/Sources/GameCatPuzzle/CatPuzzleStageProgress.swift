import Core
import SwiftUI

/// ステージの今の位置の文言（開始シートとクリアのカード・#3240）。面番号→表示の対応はここに集める（テストで固定）。
enum CatPuzzleStageProgressText {
    /// 「7×7：3 / 15 面」。141 面目以降は面数が決まっていないので「12×12：5 面目」、ボーナスは「ボーナスステージ（6×6）」。
    static func position(_ progress: CatPuzzleStage.Progress) -> String {
        if progress.isBonus { return tr("ボーナスステージ（%@）", progress.size.sizeLabel) }
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

    /// 「次のボーナスまであと 4 面」。ボーナスそのものは「ボーナスステージ」、1 つ前は「次はボーナスステージ」。141 面目より前は nil（#3260）。
    static func bonus(_ progress: CatPuzzleStage.Progress) -> String? {
        guard let rest = progress.toBonus else { return nil }
        if progress.isBonus { return tr("ボーナスステージ") }
        if rest == 0 { return tr("次はボーナスステージ") }
        return tr("次のボーナスまであと %lld 面", rest)
    }

    /// 「次の盤」「ボーナス」「鍵」を 1 行に並べたもの（クリアのカード用）。
    static func upcoming(_ progress: CatPuzzleStage.Progress) -> String {
        [nextBoard(progress), bonus(progress), key(progress)].compactMap { $0 }.joined(separator: tr("・"))
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
            if let bonus = CatPuzzleStageProgressText.bonus(progress) {
                Label(bonus, systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
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
/// ボーナスステージに入ったときは同じ形で色を替えて「ボーナスステージ」を出す（#3260）。
struct CatPuzzleBoardAdvanceBanner: View {
    let text: String
    var fill: Color = Theme.Fill.coral

    init(size: CatPuzzleSize) { text = CatPuzzleStageProgressText.advanced(to: size) }

    init(bonusSize size: CatPuzzleSize) {
        text = tr("ボーナスステージ（%@）", size.sizeLabel)
        fill = Theme.Fill.purple
    }

    var body: some View {
        Text(text)
            .scaledFont(22, weight: .heavy, design: .rounded, maxScale: 1.3)
            .foregroundStyle(Theme.onAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Capsule().fill(fill))
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isStaticText)
    }
}
