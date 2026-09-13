import SwiftUI

/// リザルトで「一段上の難易度」を勧める提案 1 件（#722）。
public struct DifficultyLadderOffer: Equatable, Sendable {
    /// いまの連勝数。
    public let streak: Int
    /// 勧める難易度の位置（0 始まり。ゲームの難易度の並びでの添字）。
    public let nextLevel: Int
    /// 勧める難易度の表示名（「普通」「中級」など。開始シートと同じ呼び名）。
    public let nextLevelLabel: String
    /// 何回目の決着に対する提案か（`PlayRecord.plays`）。×で閉じた提案を見分けるための識別子で、
    /// 同じ連勝数・同じ段の提案でも、別の決着なら別物として扱う。
    let plays: Int

    /// カードの見出し。
    public var caption: String { "\(streak)連勝中！" }
    /// カードの本文。
    public var title: String { "つぎは「\(nextLevelLabel)」にしてみる？" }
}

/// 勝ち・クリアが続いたら、リザルトで一段上の難易度を勧める「階段」（#722）の提示条件。
///
/// `RecommendationPolicy` と同じく**乱数を使わず決定的**にし、状態は増やさない。
/// 提示の間隔は連勝数そのもので持つ（`streakThreshold` の倍数のときだけ出す）ため、
/// 断った（勧めを使わずに同じ段で遊んだ）人に次の勝ちで即座に出し直すことが構造的に無く、
/// 新しい保存キーも要らない。
public enum DifficultyLadder {
    /// これだけ連勝したら勧める。**次に勧めるのはさらにこれだけ勝ったとき**（提示間隔を兼ねる）。
    public static let streakThreshold = 3

    /// 勧める提案。勧めないときは nil。
    ///
    /// - Parameters:
    ///   - result: `GameServices.gameDidFinish` の戻り値（その回の決着を記録した結果）。
    ///   - currentLevel: いま遊んだ難易度の位置（0 始まり）。プリセットに当たらない盤
    ///     （マインスイーパーの旧サイズの中断データなど）は nil で、勧めない。
    ///   - levelLabels: 難易度の表示名を**やさしい順**に並べたもの。
    public static func offer(
        for result: RecordResult?,
        currentLevel: Int?,
        levelLabels: [String]
    ) -> DifficultyLadderOffer? {
        guard let record = result?.record, let currentLevel else { return nil }
        let streak = record.currentStreak
        // 連勝は勝ち以外で 0 に戻るので、streak > 0 はその回が勝ちだったことも意味する。
        guard streak >= streakThreshold, streak % streakThreshold == 0 else { return nil }
        let next = currentLevel + 1
        // 最上級（とそれより上の範囲外）では勧めない。
        guard currentLevel >= 0, levelLabels.indices.contains(next) else { return nil }
        return DifficultyLadderOffer(
            streak: streak,
            nextLevel: next,
            nextLevelLabel: levelLabels[next],
            plays: record.plays
        )
    }
}

/// 提案と、それを押したときに一段上で始め直す処理の組。各ゲームの View が作り、
/// レコメンドの枠（`RecommendationSlot` / `GameControlArea`）へ渡す。
public struct DifficultyLadderPrompt {
    public let offer: DifficultyLadderOffer
    /// 勧めた段で始め直す。
    public let climb: () -> Void

    /// 勧める条件を満たさなければ nil（何も出さない）。
    ///
    /// - Parameter climb: 勧めた段（`DifficultyLadderOffer.nextLevel`）で新しい局を始める。
    ///   **その段で `gameDidRestart` を通すこと**（`game_start` の `level` がその段で送られる）。
    public init?(
        result: RecordResult?,
        currentLevel: Int?,
        levelLabels: [String],
        climb: @escaping (Int) -> Void
    ) {
        guard let offer = DifficultyLadder.offer(
            for: result, currentLevel: currentLevel, levelLabels: levelLabels
        ) else { return nil }
        self.offer = offer
        self.climb = { climb(offer.nextLevel) }
    }
}

/// 「3連勝中！ つぎは「普通」にしてみる？」のカード（#722）。
///
/// レコメンドの枠に出すので **`RecommendationCard` と同じ寸法・同じフォントで組む**（高さ契約）。
/// 非モーダルで、×で閉じられる。
struct DifficultyLadderCard: View {
    let offer: DifficultyLadderOffer
    let onClimb: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClimb) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Fill.yellow.gradient)
                        .frame(width: RecommendationCard.iconSide, height: RecommendationCard.iconSide)
                        .overlay {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.onAccent)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(offer.caption)
                            .themeCaption(RecommendationCard.captionSize, weight: .semibold)
                            .foregroundStyle(Theme.inkSub)
                            .lineLimit(1)
                        Text(offer.title)
                            .themeBody(16)
                            .foregroundStyle(Theme.ink)
                            // 高さ契約のため 1 行に固定する。「むずかしい」でも狭い画面に収まるよう縮める。
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    Text("あそぶ")
                        .themeCaption(13)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Fill.yellow))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(offer.caption)\(offer.title)")
            .accessibilityHint("「\(offer.nextLevelLabel)」で新しく始めます")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkSub)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 12).padding(.vertical, RecommendationCard.verticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }
}
