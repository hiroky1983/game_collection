import SwiftUI
import Core
import CoreEngine

/// クリアの流れ（#3304）のうち、モーダルの前の 2 段（ライフが pt になる／ランキングの結果）を見せる。
/// ライフ → pt はカード、ランキングは盤の領域いっぱいの全画面の画面（#3329。バナーは覆わない）。
/// 段の切り替えは親が持つ `CatPuzzleClearFlow` が決め、このカードは今の段を描いて、時間が来るかタップされたら `onFinish` を呼ぶ。
struct CatPuzzleClearFlowCard: View {
    let step: CatPuzzleClearFlow.Step
    /// 残ったライフ（= そのまま pt）。
    let lives: Int
    let isKey: Bool
    /// 今日の合計 pt（加算後）。
    let total: Int
    /// 今日の順位表を読む処理。読めなければ nil（未サインイン・失敗・時間切れ）。
    let loadBoard: @MainActor () async -> GameCenterBoard?
    /// 段の終わり（時間が来た・タップされた）。
    let onFinish: () -> Void
    /// 順位を読み終えたとき（読めなければ nil）。クリアのモーダルが今日の順位を載せるために受け取る。
    var onResult: (CatPuzzleClearFlow.RankingResult?) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// pt に飛んだライフの数。
    @State private var flown = 0
    @State private var multiplied = false
    @State private var result: CatPuzzleClearFlow.RankingResult?
    @State private var rankSettled = false

    private var gained: Int { isKey ? lives * CatPuzzleEvent.keyMultiplier : lives }

    var body: some View {
        Group {
            if step == .ranking {
                rankingPage.transition(.opacity)
            } else {
                card.transition(.opacity)
            }
        }
        .task(id: step) { await run() }
    }

    /// ランキングの全画面（柵越えおじさんの順位表の画面と同じ見せ方）。幕を重ねる側（`overlayAboveBanner`）が
    /// バナーの上までに収めるので、バナーは覆わない。順位表（行 36pt × 10）は背が高いので、収まらないときは縦にスクロールする。
    private var rankingPage: some View {
        ScrollView {
            VStack(spacing: 14) {
                rankingBody
                Text(tr("タップで次へ"))
                    .scaledFont(12, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(Theme.inkSubText)
            }
            .multilineTextAlignment(.center)
            .padding(Theme.pad)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: tr("次へ進みます")) { onFinish() }
    }

    private var card: some View {
        VStack(spacing: 14) {
            switch step {
            case .lives: livesBody
            case .ranking, .modal: EmptyView()
            }
            Text(tr("タップで次へ"))
                .scaledFont(12, weight: .semibold, design: .rounded, maxScale: 1.3)
                .foregroundStyle(Theme.inkSubText)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner))
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("次へ進みます"))
        .accessibilityAction { onFinish() }
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
            if let result, result.showsTable {
                // 柵越えおじさんと同じ、自分の行が飛び上がる順位表（#3327）。
                RankingBoardView(board: result.board, motion: result.motion, style: rankingStyle) { state in
                    rankingSummary(state, result: result)
                }
            } else {
                Text(tr("%lldpt", total))
                    .scaledFont(34, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if let rank = result?.rank {
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
    }

    private var rankingStyle: RankingBoardStyle {
        RankingBoardStyle(rowHeight: 36, format: { tr("%lldpt", $0) }, scoreSize: { _ in 16 })
    }

    /// 順位表の上の見出し。順位の数字は動きに合わせてめくれ、入れ替えが終わったら「N 人抜き！」と特典の一言を出す。
    /// 行が増えて表がずれないよう、高さは先に確保しておく。
    private func rankingSummary(_ state: RankingBoardState, result: CatPuzzleClearFlow.RankingResult) -> some View {
        VStack(spacing: 2) {
            if let rank = state.myRank {
                Text(tr("今日 %lld 位", rank))
                    .themeBody(20, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(Theme.coralText)
                    .contentTransition(.numericText(countsDown: true))
            }
            if state.arrived, result.passedCount > 0 {
                Text(tr("%lld 人抜き！", result.passedCount))
                    .themeBody(15, weight: .heavy, maxScale: 1.5)
                    .foregroundStyle(Theme.ink)
                    .transition(.scale.combined(with: .opacity))
            }
            if state.arrived, let rank = state.myRank, (1...3).contains(rank) {
                Text(tr("上位 3 位なら、明日 特典がもらえます"))
                    .themeBody(13, weight: .semibold, maxScale: 1.5)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
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
            result = nil
            rankSettled = false
            let board = await CatPuzzleClearFlow.loadWithTimeout(loadBoard)
            guard !Task.isCancelled else { return }
            result = CatPuzzleClearFlow.result(board: board, beforeTotal: total - gained)
            rankSettled = true
            onResult(result)
            try? await Task.sleep(for: CatPuzzleClearFlow.rankingDuration(motion: result?.motion, reduceMotion: reduceMotion))
        case .modal:
            return
        }
        guard !Task.isCancelled else { return }
        onFinish()
    }
}
