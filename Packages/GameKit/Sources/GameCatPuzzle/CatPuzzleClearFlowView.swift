import SwiftUI
import Core

/// クリアの流れ（#3304）のうち、モーダルの前の 2 段（ライフが pt になる／ランキングの結果）を見せるカード。
/// 段の切り替えは親が持つ `CatPuzzleClearFlow` が決め、このカードは今の段を描いて、時間が来るかタップされたら `onFinish` を呼ぶ。
struct CatPuzzleClearFlowCard: View {
    let step: CatPuzzleClearFlow.Step
    /// 残ったライフ（= そのまま pt）。
    let lives: Int
    let isKey: Bool
    /// 今日の合計 pt（加算後）。
    let total: Int
    /// 今日の順位を読む処理。読めなければ nil（未サインイン・失敗・時間切れ）。
    let loadRank: @MainActor () async -> Int?
    /// 段の終わり（時間が来た・タップされた）。
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// pt に飛んだライフの数。
    @State private var flown = 0
    @State private var multiplied = false
    @State private var rank: Int?
    @State private var rankSettled = false

    private var gained: Int { isKey ? lives * CatPuzzleEvent.keyMultiplier : lives }

    var body: some View {
        VStack(spacing: 14) {
            switch step {
            case .lives: livesBody
            case .ranking: rankingBody
            case .modal: EmptyView()
            }
            Text(tr("タップで次へ"))
                .scaledFont(12, weight: .semibold, design: .rounded, maxScale: 1.3)
                .foregroundStyle(Theme.inkSubText)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("次へ進みます"))
        .accessibilityAction { onFinish() }
        .task(id: step) { await run() }
    }

    // MARK: - ライフ → pt

    private var livesBody: some View {
        let shown = CatPuzzleClearFlow.progress(
            lives: lives, flown: reduceMotion ? lives : flown, isKey: isKey, multiplied: reduceMotion || multiplied
        )
        return VStack(spacing: 10) {
            Text(tr("ライフがポイントに！"))
                .themeBody(18, weight: .bold, maxScale: 1.5)
                .foregroundStyle(Theme.tealText)
            HStack(spacing: 6) {
                ForEach(0..<CatPuzzleModel.maxMistakes, id: \.self) { index in
                    Image(systemName: index < shown.hearts ? "heart.fill" : "heart")
                        .scaledFont(26, maxScale: 1.3)
                        .foregroundStyle(index < shown.hearts ? Theme.coralText : Theme.inkSubText.opacity(0.5))
                }
            }
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tr("+%lldpt", shown.multiplied ? shown.count * CatPuzzleEvent.keyMultiplier : shown.count))
                    .scaledFont(34, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                if isKey, shown.multiplied {
                    Text(tr("鍵の面 ×2"))
                        .scaledFont(14, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundStyle(Theme.yellowText)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .accessibilityLabel(tr("ライフ %1$lld、%2$lldpt を獲得", lives, gained))
        }
    }

    // MARK: - ランキングの結果

    private var rankingBody: some View {
        VStack(spacing: 8) {
            Text(tr("今日の結果"))
                .themeBody(18, weight: .bold, maxScale: 1.5)
                .foregroundStyle(Theme.tealText)
            Text(tr("%lldpt", total))
                .scaledFont(34, weight: .heavy, design: .rounded, maxScale: 1.3)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            if let rank {
                Text(tr("今日 %lld 位", rank))
                    .themeBody(20, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(Theme.coralText)
                if (1...3).contains(rank) {
                    Text(tr("上位 3 位なら、明日 特典がもらえます"))
                        .themeBody(13, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.inkSubText)
                }
            } else if !rankSettled {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - 進行

    /// 段が出てから、時間が来たら（または順位が決まったら）`onFinish` を呼ぶ。タップはこれを待たずに `onFinish` を呼ぶ。
    private func run() async {
        switch step {
        case .lives:
            flown = reduceMotion ? lives : 0
            multiplied = reduceMotion
            if !reduceMotion {
                for _ in 0..<lives {
                    try? await Task.sleep(for: CatPuzzleClearFlow.lifeInterval)
                    guard !Task.isCancelled else { return }
                    withGameAnimation(.spring(duration: 0.3)) { flown += 1 }
                }
                if isKey {
                    try? await Task.sleep(for: CatPuzzleClearFlow.keyMultiplyDelay)
                    guard !Task.isCancelled else { return }
                    withGameAnimation(.spring(duration: 0.3)) { multiplied = true }
                }
            }
            try? await Task.sleep(for: CatPuzzleClearFlow.hold)
        case .ranking:
            rank = nil
            rankSettled = false
            rank = await CatPuzzleClearFlow.loadRank(loadRank)
            guard !Task.isCancelled else { return }
            rankSettled = true
            try? await Task.sleep(for: CatPuzzleClearFlow.hold + .milliseconds(600))
        case .modal:
            return
        }
        guard !Task.isCancelled else { return }
        onFinish()
    }
}
